import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../../../models/device_model.dart';
import '../data/file_transfer_service.dart';
import '../models/transfer_task.dart';

/// Bridges FileTransferService (raw sockets) to the widget tree.
///
/// This controller is created once for the whole app session,
/// because the incoming-file server must keep listening regardless
/// of which screen is currently open.
class FileTransferController extends ChangeNotifier {
  final FileTransferService _service =
      FileTransferService();

  final Map<String, TransferTask> _tasks = {};

  StreamSubscription<TransferTask>? _subscription;

  bool isServerReady = false;

  /// Newest activity first.
  List<TransferTask> get tasks =>
      _tasks.values.toList()
        ..sort(
          (a, b) => b.id.compareTo(a.id),
        );

  Future<void> init({
    required String selfId,
    required String selfName,
  }) async {
    _subscription =
        _service.onUpdate.listen((task) {
      _tasks[task.id] = task;
      notifyListeners();
    });

    // No ensureDownloadDirectory() here.
    // The receiving service creates:
    // /storage/emulated/0/KnightSync/<category>/
    // when an actual file arrives.
    await _service.startServer(
      selfId: selfId,
      selfName: selfName,
    );

    isServerReady = true;
    notifyListeners();
  }

  /// Opens the system file picker and sends
  /// the selected file to [device].
  Future<void> pickAndSendFile(
    DeviceModel device,
  ) async {
    final result =
        await FilePicker.platform.pickFiles();

    final path =
        result?.files.single.path;

    if (path == null) {
      return;
    }

    await sendFile(
      device: device,
      file: File(path),
    );
  }

  Future<void> sendFile({
    required DeviceModel device,
    required File file,
  }) async {
    final fileName =
        file.uri.pathSegments.last;

    await _service.sendFile(
      targetIp: device.ip,
      peerName: device.name,
      file: file,
      fileName: fileName,
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _service.dispose();
    super.dispose();
  }
}