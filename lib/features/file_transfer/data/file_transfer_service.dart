import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/app_constants.dart';
import '../models/transfer_task.dart';

/// The actual file-transfer networking. No Flutter/UI imports here on
/// purpose — same reasoning as DiscoveryService: testable and reusable
/// outside a widget tree.
///
/// Wire protocol per connection (deliberately tiny, no external libs):
/// 1. Sender opens a TCP connection to the receiver's
///    [AppConstants.fileTransferPort].
/// 2. Sender writes one UTF-8 JSON line, newline-terminated:
///    {tag, id, name, fileName, fileSize}.
/// 3. Sender then writes exactly fileSize raw bytes — no further framing,
///    because the receiver already knows how much to expect from the
///    header, and closes the socket when done.
class FileTransferService {
  static const _uuid = Uuid();

  ServerSocket? _server;
  final _updateController = StreamController<TransferTask>.broadcast();

  /// Emits a TransferTask snapshot every time a transfer is created,
  /// makes progress, completes, or fails — for both directions.
  Stream<TransferTask> get onUpdate => _updateController.stream;

  String? _selfId;
  String? _selfName;

  Future<void> startServer({
    required String selfId,
    required String selfName,
  }) async {
    _selfId = selfId;
    _selfName = selfName;
    await _server?.close();
    _server = await ServerSocket.bind(
      InternetAddress.anyIPv4,
      AppConstants.fileTransferPort,
    );
    _server!.listen(_handleIncomingConnection, onError: (_) {});
  }

  // ---------------------------------------------------------------------
  // Receiving
  // ---------------------------------------------------------------------

  Future<void> _handleIncomingConnection(Socket socket) async {
    final taskId = _uuid.v4();
    final headerBytes = <int>[];
    var headerParsed = false;
    IOSink? sink;
    File? file;
    TransferTask? task;
    var received = 0;
    var fileSize = 0;
    final done = Completer<void>();

    late final StreamSubscription<Uint8List> sub;
    sub = socket.listen(
      (chunk) async {
        // Pause immediately (synchronously, before any await) so the
        // next chunk can't arrive and be processed out of order while
        // we're still awaiting file I/O for this one.
        sub.pause();
        try {
          var offset = 0;

          if (!headerParsed) {
            final newlineIndex = chunk.indexOf(10); // '\n'
            if (newlineIndex == -1) {
              headerBytes.addAll(chunk);
              sub.resume();
              return;
            }
            headerBytes.addAll(chunk.sublist(0, newlineIndex));
            offset = newlineIndex + 1;
            headerParsed = true;

            final json =
                jsonDecode(utf8.decode(headerBytes)) as Map<String, dynamic>;
            if (json['tag'] != AppConstants.protocolTag) {
              await sub.cancel();
              socket.destroy();
              if (!done.isCompleted) done.complete();
              return;
            }

            final fileName = json['fileName'] as String;
            fileSize = json['fileSize'] as int;
            final peerName = json['name'] as String? ?? 'Unknown device';
            final peerIp = socket.remoteAddress.address;

            final dir = await _downloadDirectory();
            final safeName = await _uniqueFileName(dir, fileName);
            file = File('${dir.path}${Platform.pathSeparator}$safeName');
            sink = file!.openWrite();

            task = TransferTask(
              id: taskId,
              fileName: fileName,
              totalBytes: fileSize,
              transferredBytes: 0,
              direction: TransferDirection.incoming,
              status: TransferStatus.inProgress,
              peerName: peerName,
              peerIp: peerIp,
            );
            _updateController.add(task!);
          }

          if (task != null && offset < chunk.length) {
            final body = chunk.sublist(offset);
            final remaining = fileSize - received;
            final toWrite =
                body.length > remaining ? body.sublist(0, remaining) : body;
            if (toWrite.isNotEmpty) {
              sink!.add(toWrite);
              received += toWrite.length;
              task = task!.copyWith(transferredBytes: received);
              _updateController.add(task!);
            }
          }

          if (task != null && received >= fileSize) {
            await sub.cancel();
            await sink!.flush();
            await sink!.close();
            task = task!.copyWith(
              status: TransferStatus.completed,
              savedPath: file!.path,
            );
            _updateController.add(task!);
            socket.destroy();
            if (!done.isCompleted) done.complete();
            return;
          }

          sub.resume();
        } catch (e) {
          await sub.cancel();
          await sink?.close();
          _emitFailure(taskId, task, socket, e);
          socket.destroy();
          if (!done.isCompleted) done.complete();
        }
      },
      onError: (Object e) async {
        await sink?.close();
        _emitFailure(taskId, task, socket, e);
        if (!done.isCompleted) done.complete();
      },
      onDone: () async {
        // Socket closed before we ever reached fileSize bytes — the
        // sender crashed, lost network, or the user cancelled mid-send.
        if (task != null && received < fileSize) {
          await sink?.close();
          task = task!.copyWith(
            status: TransferStatus.failed,
            errorMessage: 'Connection closed before the transfer finished',
          );
          _updateController.add(task!);
        }
        if (!done.isCompleted) done.complete();
      },
      cancelOnError: true,
    );

    await done.future;
  }

  void _emitFailure(String id, TransferTask? task, Socket socket, Object e) {
    final base = task ??
        TransferTask(
          id: id,
          fileName: 'unknown',
          totalBytes: 0,
          transferredBytes: 0,
          direction: TransferDirection.incoming,
          status: TransferStatus.inProgress,
          peerName: 'Unknown device',
          peerIp: socket.remoteAddress.address,
        );
    _updateController.add(
      base.copyWith(status: TransferStatus.failed, errorMessage: e.toString()),
    );
  }

  Future<Directory> _downloadDirectory() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(
      '${base.path}${Platform.pathSeparator}${AppConstants.downloadFolderName}',
    );
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Avoids silently overwriting a file the user already received —
  /// appends " (1)", " (2)", etc. before the extension until the name
  /// is free.
  Future<String> _uniqueFileName(Directory dir, String original) async {
    var candidate = original;
    var counter = 1;
    while (await File('${dir.path}${Platform.pathSeparator}$candidate')
        .exists()) {
      final dotIndex = original.lastIndexOf('.');
      candidate = dotIndex <= 0
          ? '$original ($counter)'
          : '${original.substring(0, dotIndex)} ($counter)${original.substring(dotIndex)}';
      counter++;
    }
    return candidate;
  }

  // ---------------------------------------------------------------------
  // Sending
  // ---------------------------------------------------------------------

  Future<void> sendFile({
    required String targetIp,
    required String peerName,
    required File file,
    required String fileName,
  }) async {
    final taskId = _uuid.v4();
    final fileSize = await file.length();
    var task = TransferTask(
      id: taskId,
      fileName: fileName,
      totalBytes: fileSize,
      transferredBytes: 0,
      direction: TransferDirection.outgoing,
      status: TransferStatus.inProgress,
      peerName: peerName,
      peerIp: targetIp,
    );
    _updateController.add(task);

    Socket? socket;
    try {
      socket = await Socket.connect(
        targetIp,
        AppConstants.fileTransferPort,
        timeout: const Duration(seconds: 10),
      );

      final header = jsonEncode({
        'tag': AppConstants.protocolTag,
        'id': _selfId,
        'name': _selfName,
        'fileName': fileName,
        'fileSize': fileSize,
      });
      socket.add(utf8.encode('$header\n'));

      var sent = 0;
      await for (final chunk in file.openRead()) {
        socket.add(chunk);
        await socket.flush();
        sent += chunk.length;
        task = task.copyWith(transferredBytes: sent);
        _updateController.add(task);
      }

      task = task.copyWith(status: TransferStatus.completed);
      _updateController.add(task);
    } catch (e) {
      task = task.copyWith(status: TransferStatus.failed, errorMessage: e.toString());
      _updateController.add(task);
    } finally {
      await socket?.close();
    }
  }

  Future<void> dispose() async {
    await _server?.close();
    await _updateController.close();
  }
}
