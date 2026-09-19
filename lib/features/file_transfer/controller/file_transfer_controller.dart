import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../../../models/connection_request.dart';
import '../../../models/device_model.dart';
import '../../history/data/history_repository.dart';
import '../../history/models/transfer_history_entry.dart';
import '../../session/data/peer_session_service.dart';
import '../../session/models/peer_session_event.dart';
import '../data/file_transfer_service.dart';
import '../models/transfer_task.dart';

/// Bridges file transfer, persistent peer sessions and history to the widget
/// tree. The controller lives for the whole app session so both TCP servers
/// remain available while navigating between screens.
class FileTransferController extends ChangeNotifier {
  final FileTransferService _service = FileTransferService();
  final PeerSessionService _sessionService = PeerSessionService();
  final HistoryRepository _historyRepository = HistoryRepository();

  final Map<String, TransferTask> _tasks = {};

  StreamSubscription<TransferTask>? _subscription;
  StreamSubscription<PeerSessionEvent>? _sessionSubscription;

  bool isServerReady = false;
  String? _openTransferScreenDeviceId;

  /// Fires whenever a peer asks to connect. The reliable TCP handshake is
  /// separate from the persistent session used after the user accepts.
  Stream<ConnectionRequest> get onConnectionRequest =>
      _service.onConnectionRequest;

  Stream<PeerSessionEvent> get onSessionEvent => _sessionService.events;

  bool get hasTransferScreenOpen => _openTransferScreenDeviceId != null;

  List<TransferTask> get tasks =>
      _tasks.values.toList()
        ..sort(
          (a, b) => b.id.compareTo(a.id),
        );

  bool isSessionConnected(String deviceId) =>
      _sessionService.isConnected(deviceId);

  void enterTransferScreen(String deviceId) {
    // This is a lifecycle/guard flag only. Do not notify here: this method is
    // also called from a route's initState, where notifyListeners() can cause
    // Flutter's "setState() or markNeedsBuild() called during build" error.
    _openTransferScreenDeviceId = deviceId;
  }

  void leaveTransferScreen(String deviceId) {
    if (_openTransferScreenDeviceId == deviceId) {
      _openTransferScreenDeviceId = null;
    }

    // The route is already leaving, so there is no widget rebuild needed here.
    // The next screen reads the updated guard value directly.
    if (_sessionService.isConnected(deviceId)) {
      unawaited(_sessionService.disconnect(deviceId));
    }
  }

  Future<void> init({
    required String selfId,
    required String selfName,
    required String selfPlatform,
  }) async {
    _subscription = _service.onUpdate.listen((task) {
      _tasks[task.id] = task;
      notifyListeners();

      if (task.direction == TransferDirection.incoming &&
          task.status == TransferStatus.completed &&
          task.savedPath != null) {
        unawaited(
          _historyRepository.add(
            TransferHistoryEntry(
              id: task.id,
              fileName: task.fileName,
              peerName: task.peerName,
              peerIp: task.peerIp,
              savedPath: task.savedPath!,
              sizeBytes: task.totalBytes,
              receivedAt: DateTime.now(),
            ),
          ),
        );
      }
    });

    _sessionSubscription = _sessionService.events.listen((_) {
      notifyListeners();
    });

    await _service.startServer(
      selfId: selfId,
      selfName: selfName,
      selfPlatform: selfPlatform,
    );

    await _sessionService.startServer(
      selfId: selfId,
      selfName: selfName,
      selfPlatform: selfPlatform,
    );

    isServerReady = true;
    notifyListeners();
  }

  /// Asks [targetIp] to connect. The peer must accept before this resolves as
  /// `accepted` — see [ConnectionRequestResult].
  Future<ConnectionRequestResult> requestConnection(String targetIp) {
    return _service.sendConnectionRequest(targetIp);
  }

  /// Opens a fresh persistent session for a newly accepted connection. The
  /// visible transfer list is deliberately cleared here so an old session's
  /// files do not leak into the next session.
  Future<bool> openSession(DeviceModel device) async {
    // Clear the previous session before the new screen's first build. There
    // is intentionally no notifyListeners() here because this can be called
    // from a StatefulWidget.initState(). The new screen already reads the
    // cleared list, and session/file events will notify later when appropriate.
    _tasks.clear();
    return _sessionService.connect(device);
  }

  Future<void> disconnectSession(DeviceModel device) async {
    await _sessionService.disconnect(device.id);
    notifyListeners();
  }

  /// Opens the system file picker and sends the selected file to [device].
  Future<void> pickAndSendFile(DeviceModel device) async {
    if (!_sessionService.isConnected(device.id)) return;

    final result = await FilePicker.platform.pickFiles();
    final path = result?.files.single.path;
    if (path == null) return;

    // The peer can leave while the file picker is open.
    if (!_sessionService.isConnected(device.id)) return;

    await sendFile(
      device: device,
      file: File(path),
    );
  }

  Future<void> sendFile({
    required DeviceModel device,
    required File file,
  }) async {
    if (!_sessionService.isConnected(device.id)) return;

    final fileName = file.uri.pathSegments.last;

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
    _sessionSubscription?.cancel();
    _sessionService.dispose();
    _service.dispose();
    super.dispose();
  }
}
