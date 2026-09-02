import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../core/constants/app_constants.dart';
import '../../../models/device_model.dart';

/// The actual networking. No Flutter/UI imports here on purpose —
/// this class should be testable and reusable even outside a widget tree.
///
/// How it works (UDP broadcast — no server, no internet needed):
/// 1. Every device opens a UDP socket on [AppConstants.discoveryPort].
/// 2. Every [AppConstants.broadcastInterval], it broadcasts a small
///    JSON "hello" packet to 255.255.255.255 on that same port.
/// 3. Every device is ALSO listening on that port, so it receives the
///    hello packets every other device on the same Wi-Fi sends.
/// 4. Whoever receives a packet now knows: this id/name/platform exists
///    at this IP address.
class DiscoveryService {
  RawDatagramSocket? _socket;
  Timer? _broadcastTimer;
  final _deviceFoundController = StreamController<DeviceModel>.broadcast();

  /// Emits a DeviceModel every time we hear from someone on the network
  /// (including repeated "still here" pings from a device we already know).
  Stream<DeviceModel> get onDeviceFound => _deviceFoundController.stream;

  Future<void> start({
    required String selfId,
    required String selfName,
    required String selfPlatform,
  }) async {
    _socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      AppConstants.discoveryPort,
    );
    _socket!.broadcastEnabled = true;

    _socket!.listen((RawSocketEvent event) {
      if (event != RawSocketEvent.read) return;
      final datagram = _socket!.receive();
      if (datagram == null) return;
      _handleIncomingPacket(datagram, selfId);
    });

    _broadcastTimer = Timer.periodic(AppConstants.broadcastInterval, (_) {
      _sendHello(selfId, selfName, selfPlatform);
    });
    // Don't make the user wait a full interval for the first ping.
    _sendHello(selfId, selfName, selfPlatform);
  }

  void _sendHello(String id, String name, String platform) {
    final payload = jsonEncode({
      'tag': AppConstants.protocolTag,
      'id': id,
      'name': name,
      'platform': platform,
      'port': AppConstants.discoveryPort,
    });
    final data = utf8.encode(payload);
    _socket?.send(data, InternetAddress('255.255.255.255'), AppConstants.discoveryPort);
  }

  void _handleIncomingPacket(Datagram datagram, String selfId) {
    try {
      final message = utf8.decode(datagram.data);
      final json = jsonDecode(message) as Map<String, dynamic>;

      // Ignore anything that isn't our protocol (random UDP noise) and
      // ignore our own broadcast bouncing back to us.
      if (json['tag'] != AppConstants.protocolTag) return;
      if (json['id'] == selfId) return;

      final device = DeviceModel.fromJson(json, datagram.address.address);
      _deviceFoundController.add(device);
    } catch (_) {
      // Malformed packet — just drop it, never crash discovery over it.
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
  }
}
