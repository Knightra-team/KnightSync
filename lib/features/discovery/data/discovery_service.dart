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

    _broadcastTimer =
        Timer.periodic(AppConstants.broadcastInterval, (_) {
      _sendHello(
        selfId,
        selfName,
        selfPlatform,
      );
    });

    _sendHello(
      selfId,
      selfName,
      selfPlatform,
    );
  }

  Future<void> _bindSocket() async {
    _socket?.close();

    _socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      AppConstants.discoveryPort,
    );

    _socket!.broadcastEnabled = true;

    _socket!.listen((RawSocketEvent event) {
      if (event != RawSocketEvent.read) return;

      final datagram = _socket!.receive();

      if (datagram == null) return;

      _handleIncomingPacket(
        datagram,
        _selfId ?? '',
      );
    });
  }

  Future<void> restart() async {
    if (_selfId == null) return;

    await _bindSocket();
  }

  void _sendHello(
    String id,
    String name,
    String platform,
  ) {
    final data = utf8.encode(
      _buildPayload(
        id: id,
        name: name,
        platform: platform,
        type: 'hello',
      ),
    );

    _socket?.send(
      data,
      InternetAddress('255.255.255.255'),
      AppConstants.discoveryPort,
    );
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

    _socket?.send(
      data,
      InternetAddress(targetIp),
      AppConstants.discoveryPort,
    );
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

    _socket?.send(
      data,
      InternetAddress(targetIp),
      AppConstants.discoveryPort,
    );
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
      final message = utf8.decode(datagram.data);

      final json =
          jsonDecode(message) as Map<String, dynamic>;

      if (json['tag'] != AppConstants.protocolTag) {
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

      if (type == 'connect_request') {
        _deviceFoundController.add(device);
        _connectionRequestController.add(device);
        return;
      }

      _deviceFoundController.add(device);

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
  }

  void dispose() {
    stop();

    _deviceFoundController.close();
    _connectionRequestController.close();
  }
}