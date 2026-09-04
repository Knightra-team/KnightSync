import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../core/constants/app_constants.dart';
import '../../../models/device_model.dart';

class DiscoveryService {
  RawDatagramSocket? _socket;
  Timer? _broadcastTimer;

  final _deviceFoundController =
      StreamController<DeviceModel>.broadcast();

  final _connectionRequestController =
      StreamController<DeviceModel>.broadcast();

  final Set<String> _acknowledgedIds = {};

  Stream<DeviceModel> get onDeviceFound =>
      _deviceFoundController.stream;

  Stream<DeviceModel> get onConnectionRequest =>
      _connectionRequestController.stream;

  String? _selfId;
  String? _selfName;
  String? _selfPlatform;

  bool _isBinding = false;

  Future<void> start({
    required String selfId,
    required String selfName,
    required String selfPlatform,
  }) async {
    _selfId = selfId;
    _selfName = selfName;
    _selfPlatform = selfPlatform;

    await _bindSocket();

    _broadcastTimer?.cancel();

    _broadcastTimer = Timer.periodic(
      AppConstants.broadcastInterval,
      (_) => _sendHelloToNetwork(),
    );

    // Announce ourselves immediately.
    _sendHelloToNetwork();
  }

  Future<void> _bindSocket() async {
    if (_isBinding) return;

    _isBinding = true;

    try {
      _socket?.close();
      _socket = null;

      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        AppConstants.discoveryPort,
        reuseAddress: true,
      );

      socket.broadcastEnabled = true;

      _socket = socket;

      socket.listen((RawSocketEvent event) {
        if (event != RawSocketEvent.read) return;

        while (true) {
          final datagram = socket.receive();

          if (datagram == null) {
            break;
          }

          _handleIncomingPacket(
            datagram,
            _selfId ?? '',
          );
        }
      });
    } finally {
      _isBinding = false;
    }
  }

  Future<void> restart() async {
    if (_selfId == null) return;

    await _bindSocket();

    // Important:
    // After rebinding, immediately announce ourselves again.
    _sendHelloToNetwork();
  }

  void _sendHelloToNetwork() {
    final id = _selfId;
    final name = _selfName;
    final platform = _selfPlatform;

    if (id == null ||
        name == null ||
        platform == null) {
      return;
    }

    final data = utf8.encode(
      _buildPayload(
        id: id,
        name: name,
        platform: platform,
        type: 'hello',
      ),
    );

    final socket = _socket;

    if (socket == null) return;

    // Global broadcast.
    _sendBroadcast(
      socket,
      data,
      '255.255.255.255',
    );

    // Local subnet broadcast.
    //
    // Some Android/Wi-Fi networks don't reliably deliver
    // 255.255.255.255, so we also send x.x.x.255.
    _sendSubnetBroadcasts(
      socket,
      data,
    );
  }

  void _sendBroadcast(
    RawDatagramSocket socket,
    List<int> data,
    String address,
  ) {
    try {
      socket.send(
        data,
        InternetAddress(address),
        AppConstants.discoveryPort,
      );
    } catch (_) {
      // Ignore unavailable network interfaces.
    }
  }

  Future<void> _sendSubnetBroadcasts(
    RawDatagramSocket socket,
    List<int> data,
  ) async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );

      final sent = <String>{};

      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (address.isLoopback) continue;

          final parts = address.address.split('.');

          if (parts.length != 4) continue;

          // Most Wi-Fi and hotspot networks use /24.
          final broadcast =
              '${parts[0]}.${parts[1]}.${parts[2]}.255';

          if (sent.add(broadcast)) {
            _sendBroadcast(
              socket,
              data,
              broadcast,
            );
          }
        }
      }
    } catch (_) {
      // Global broadcast was already attempted.
    }
  }

  void sendConnectionRequest(String targetIp) {
    if (_selfId == null ||
        _selfName == null ||
        _selfPlatform == null) {
      return;
    }

    final data = utf8.encode(
      _buildPayload(
        id: _selfId!,
        name: _selfName!,
        platform: _selfPlatform!,
        type: 'connect_request',
      ),
    );

    try {
      _socket?.send(
        data,
        InternetAddress(targetIp),
        AppConstants.discoveryPort,
      );
    } catch (_) {
      // Ignore unavailable target.
    }
  }

  void sendDirectHello(String targetIp) {
    if (_selfId == null ||
        _selfName == null ||
        _selfPlatform == null) {
      return;
    }

    final data = utf8.encode(
      _buildPayload(
        id: _selfId!,
        name: _selfName!,
        platform: _selfPlatform!,
        type: 'hello',
      ),
    );

    try {
      _socket?.send(
        data,
        InternetAddress(targetIp),
        AppConstants.discoveryPort,
      );
    } catch (_) {
      // Ignore unavailable target.
    }
  }

  String _buildPayload({
    required String id,
    required String name,
    required String platform,
    required String type,
  }) {
    return jsonEncode({
      'tag': AppConstants.protocolTag,
      'type': type,
      'id': id,
      'name': name,
      'platform': platform,
      'port': AppConstants.discoveryPort,
    });
  }

  void _handleIncomingPacket(
    Datagram datagram,
    String selfId,
  ) {
    try {
      final message = utf8.decode(
        datagram.data,
      );

      final json =
          jsonDecode(message)
              as Map<String, dynamic>;

      if (json['tag'] !=
          AppConstants.protocolTag) {
        return;
      }

      if (json['id'] == selfId) {
        return;
      }

      final device = DeviceModel.fromJson(
        json,
        datagram.address.address,
      );

      final type =
          json['type'] as String? ?? 'hello';

      // IMPORTANT:
      // Every valid device packet is immediately
      // sent to the UI.
      _deviceFoundController.add(device);

      if (type == 'connect_request') {
        _connectionRequestController.add(
          device,
        );
        return;
      }

      // Reply directly once.
      if (_acknowledgedIds.add(device.id)) {
        sendDirectHello(
          datagram.address.address,
        );
      }
    } catch (_) {
      // Ignore malformed UDP packets.
    }
  }

  void stop() {
    _broadcastTimer?.cancel();
    _broadcastTimer = null;

    _socket?.close();
    _socket = null;

    _acknowledgedIds.clear();
  }

  void dispose() {
    stop();

    _deviceFoundController.close();
    _connectionRequestController.close();
  }
}