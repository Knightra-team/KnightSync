import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../../core/constants/app_constants.dart';
import '../../../models/device_model.dart';
import '../models/peer_session_event.dart';

class PeerSessionService {
  ServerSocket? _server;
  String? _selfId;
  String? _selfName;
  String? _selfPlatform;

  final _events = StreamController<PeerSessionEvent>.broadcast();
  final Map<String, _SocketHandle> _outgoing = {};
  final Map<String, _SocketHandle> _incoming = {};
  final Map<String, DeviceModel> _connectedDevices = {};

  Stream<PeerSessionEvent> get events => _events.stream;

  bool isConnected(String peerId) => _connectedDevices.containsKey(peerId);

  Future<void> startServer({
    required String selfId,
    required String selfName,
    required String selfPlatform,
  }) async {
    _selfId = selfId;
    _selfName = selfName;
    _selfPlatform = selfPlatform;

    await _server?.close();
    _server = await ServerSocket.bind(
      InternetAddress.anyIPv4,
      AppConstants.sessionPort,
      shared: true,
    );

    _server!.listen(
      _handleIncomingConnection,
      onError: (_) {},
    );
  }

  Future<bool> connect(DeviceModel device) async {
    if (device.id.startsWith('manual:')) {
      // A manually entered device is still a valid target. The real peer id is
      // learned from its session_open packet and the server response.
    }

    // There should be one live session at a time in the current app flow.
    await disconnectAll();

    final socket = await _connectSocket(device.ip);
    if (socket == null) return false;

    final peerIdCompleter = Completer<String>();
    final peerDeviceCompleter = Completer<DeviceModel>();
    final buffer = <int>[];
    late StreamSubscription<Uint8List> subscription;
    var remotePeerId = device.id;

    void completePeer(DeviceModel peer) {
      remotePeerId = peer.id;
      if (!peerDeviceCompleter.isCompleted) {
        peerDeviceCompleter.complete(peer);
      }
      if (!peerIdCompleter.isCompleted) {
        peerIdCompleter.complete(peer.id);
      }
    }

    subscription = socket.listen(
      (data) {
        buffer.addAll(data);
        _consumeLines(
          buffer,
          (line) async {
            final json = _decode(line);
            if (json == null || json['tag'] != AppConstants.protocolTag) {
              return;
            }

            final type = json['type'];
            if (type == 'session_ack') {
              try {
                final peer = DeviceModel.fromJson(
                  json,
                  socket.remoteAddress.address,
                );
                completePeer(peer);
              } catch (_) {}
            } else if (type == 'session_disconnect') {
              final peer = _deviceFromJsonOrFallback(
                json,
                socket.remoteAddress.address,
                device,
              );
              await _handleRemoteDisconnect(peer);
            }
          },
        );
      },
      onError: (_) {
        if (!peerIdCompleter.isCompleted) {
          peerIdCompleter.complete(remotePeerId);
        }
        if (!peerDeviceCompleter.isCompleted) {
          peerDeviceCompleter.complete(device);
        }
      },
      onDone: () {
        if (!peerIdCompleter.isCompleted) {
          peerIdCompleter.complete(remotePeerId);
        }
        if (!peerDeviceCompleter.isCompleted) {
          peerDeviceCompleter.complete(device);
        }

        final known = _connectedDevices[remotePeerId];
        if (known != null) {
          _markDisconnected(
            known,
            PeerSessionEventType.peerLeft,
          );
        }
      },
      cancelOnError: false,
    );

    final selfId = _selfId;
    final selfName = _selfName;
    final selfPlatform = _selfPlatform;
    if (selfId == null || selfName == null || selfPlatform == null) {
      await subscription.cancel();
      await socket.close();
      return false;
    }

    final hello = jsonEncode({
      'tag': AppConstants.protocolTag,
      'type': 'session_open',
      'id': selfId,
      'name': selfName,
      'platform': selfPlatform,
      'port': AppConstants.sessionPort,
    });

    _outgoing[device.id] = _SocketHandle(socket, subscription);
    socket.add(utf8.encode('$hello\n'));
    await socket.flush();

    DeviceModel peer;
    try {
      peer = await peerDeviceCompleter.future.timeout(
        AppConstants.sessionHandshakeTimeout,
      );
    } on TimeoutException {
      await _removeOutgoing(device.id, close: true);
      return false;
    }

    // Move the outgoing socket under the real peer id returned by the peer.
    final current = _outgoing.remove(device.id);
    if (current != null) {
      _outgoing[peer.id] = current;
    }

    _markConnected(peer);
    return true;
  }

  Future<Socket?> _connectSocket(String ip) async {
    try {
      return await Socket.connect(
        ip,
        AppConstants.sessionPort,
        timeout: AppConstants.socketConnectTimeout,
      );
    } catch (_) {
      return null;
    }
  }

  void _handleIncomingConnection(Socket socket) {
    final buffer = <int>[];
    String? peerId;
    DeviceModel? peerDevice;
    late StreamSubscription<Uint8List> subscription;

    Future<void> closeCurrent() async {
      try {
        await subscription.cancel();
      } catch (_) {}
      try {
        await socket.close();
      } catch (_) {}
    }

    subscription = socket.listen(
      (data) {
        buffer.addAll(data);
        _consumeLines(
          buffer,
          (line) async {
            final json = _decode(line);
            if (json == null || json['tag'] != AppConstants.protocolTag) {
              return;
            }

            final type = json['type'];
            if (peerDevice == null && type == 'session_open') {
              try {
                peerDevice = DeviceModel.fromJson(
                  json,
                  socket.remoteAddress.address,
                );
                peerId = peerDevice!.id;
              } catch (_) {
                await closeCurrent();
                return;
              }

              final selfId = _selfId;
              final selfName = _selfName;
              final selfPlatform = _selfPlatform;
              if (selfId == null ||
                  selfName == null ||
                  selfPlatform == null ||
                  peerDevice!.id == selfId) {
                await closeCurrent();
                return;
              }

              final old = _incoming[peerDevice!.id];
              if (old != null && !identical(old.socket, socket)) {
                await _closeHandle(old);
              }
              _incoming[peerDevice!.id] =
                  _SocketHandle(socket, subscription);

              final ack = jsonEncode({
                'tag': AppConstants.protocolTag,
                'type': 'session_ack',
                'id': selfId,
                'name': selfName,
                'platform': selfPlatform,
                'port': AppConstants.sessionPort,
              });
              socket.add(utf8.encode('$ack\n'));
              await socket.flush();
              _markConnected(peerDevice!);
              return;
            }

            if (peerDevice == null) return;

            if (type == 'session_disconnect') {
              await _handleRemoteDisconnect(peerDevice!);
              return;
            }
          },
        );
      },
      onError: (_) {
        final peer = peerDevice;
        if (peer != null) {
          _handleIncomingClosed(peer, socket);
        }
      },
      onDone: () {
        final peer = peerDevice;
        if (peer != null) {
          _handleIncomingClosed(peer, socket);
        }
      },
      cancelOnError: false,
    );
  }

  Future<void> _handleRemoteDisconnect(DeviceModel device) async {
    _markDisconnected(
      device,
      PeerSessionEventType.peerLeft,
    );
    await _removeIncoming(device.id, close: true);
    await _removeOutgoing(device.id, close: true);
  }

  void _handleIncomingClosed(DeviceModel device, Socket socket) {
    final current = _incoming[device.id];
    if (current != null && identical(current.socket, socket)) {
      _incoming.remove(device.id);
    }
    if (_connectedDevices.containsKey(device.id)) {
      _markDisconnected(
        device,
        PeerSessionEventType.peerLeft,
      );
    }
  }

  void _markConnected(DeviceModel device) {
    final wasConnected = _connectedDevices.containsKey(device.id);
    _connectedDevices[device.id] = device;
    if (!wasConnected) {
      _events.add(
        PeerSessionEvent(
          type: PeerSessionEventType.connected,
          device: device,
        ),
      );
    }
  }

  void _markDisconnected(
    DeviceModel device,
    PeerSessionEventType type,
  ) {
    final existing = _connectedDevices.remove(device.id);
    if (existing == null) return;
    _events.add(
      PeerSessionEvent(
        type: type,
        device: device,
      ),
    );
  }

  Future<void> disconnect(String peerId) async {
    final device = _connectedDevices.remove(peerId);
    if (device == null) {
      await _removeIncoming(peerId, close: true);
      await _removeOutgoing(peerId, close: true);
      return;
    }

    final message = jsonEncode({
      'tag': AppConstants.protocolTag,
      'type': 'session_disconnect',
      'id': _selfId,
      'name': _selfName,
      'platform': _selfPlatform,
      'port': AppConstants.sessionPort,
    });

    await _sendAndClose(_outgoing.remove(peerId), message);
    await _sendAndClose(_incoming.remove(peerId), message);
  }

  Future<void> disconnectAll() async {
    final ids = <String>{
      ..._connectedDevices.keys,
      ..._incoming.keys,
      ..._outgoing.keys,
    };
    for (final id in ids) {
      await disconnect(id);
    }
  }

  Future<void> _removeIncoming(
    String peerId, {
    required bool close,
  }) async {
    final handle = _incoming.remove(peerId);
    if (handle == null) return;
    if (close) {
      await _closeHandle(handle);
    }
  }

  Future<void> _removeOutgoing(
    String peerId, {
    required bool close,
  }) async {
    final handle = _outgoing.remove(peerId);
    if (handle == null) return;
    if (close) {
      await _closeHandle(handle);
    }
  }

  Future<void> _sendAndClose(
    _SocketHandle? handle,
    String message,
  ) async {
    if (handle == null) return;
    try {
      handle.socket.add(utf8.encode('$message\n'));
      await handle.socket.flush();
    } catch (_) {}
    await _closeHandle(handle);
  }

  Future<void> _closeHandle(_SocketHandle handle) async {
    try {
      await handle.subscription.cancel();
    } catch (_) {}
    try {
      await handle.socket.close();
    } catch (_) {}
  }

  void _consumeLines(
    List<int> buffer,
    Future<void> Function(String line) onLine,
  ) {
    while (true) {
      final index = buffer.indexOf(10);
      if (index == -1) return;
      final lineBytes = buffer.sublist(0, index);
      buffer.removeRange(0, index + 1);
      final line = utf8.decode(lineBytes, allowMalformed: true).trim();
      if (line.isEmpty) continue;
      unawaited(onLine(line));
    }
  }

  Map<String, dynamic>? _decode(String line) {
    try {
      final decoded = jsonDecode(line);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return null;
  }

  DeviceModel _deviceFromJsonOrFallback(
    Map<String, dynamic> json,
    String ip,
    DeviceModel fallback,
  ) {
    try {
      return DeviceModel.fromJson(json, ip);
    } catch (_) {
      return fallback.copyWith(lastSeen: DateTime.now());
    }
  }

  Future<void> dispose() async {
    await disconnectAll();
    await _server?.close();
    _server = null;
    await _events.close();
  }
}

class _SocketHandle {
  const _SocketHandle(this.socket, this.subscription);

  final Socket socket;
  final StreamSubscription<Uint8List> subscription;
}
