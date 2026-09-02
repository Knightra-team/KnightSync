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
  final Set<String> _acknowledgedIds = {};

  /// Emits a DeviceModel every time we hear from someone on the network
  /// (including repeated "still here" pings from a device we already know).
  Stream<DeviceModel> get onDeviceFound => _deviceFoundController.stream;

  // Kept so restart() can rebind with the same identity without the
  // caller having to pass everything in again.
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

    _broadcastTimer = Timer.periodic(AppConstants.broadcastInterval, (_) {
      _sendHello(selfId, selfName, selfPlatform);
    });
    // Don't make the user wait a full interval for the first ping.
    _sendHello(selfId, selfName, selfPlatform);
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
      _handleIncomingPacket(datagram, _selfId ?? '');
    });
  }

  /// Closes and reopens the UDP socket, keeping the same broadcast timer
  /// running. Fixes the case where Android/Windows silently stops
  /// delivering broadcasts after a network change (join/leave hotspot,
  /// Wi-Fi reconnect) without requiring the user to restart the app.
  Future<void> restart() async {
    if (_selfId == null) return; // start() was never called
    await _bindSocket();
  }

  void _sendHello(String id, String name, String platform) {
    final data = utf8.encode(_buildPayload(id, name, platform));
    _socket?.send(data, InternetAddress('255.255.255.255'), AppConstants.discoveryPort);
  }

  /// Sends the same "hello" packet, but straight to one specific IP
  /// instead of broadcasting to the whole subnet. Used for manual
  /// connect: some hotspot setups filter/limit broadcast traffic but
  /// still allow plain unicast UDP between two known addresses, so this
  /// is the fallback when auto-discovery finds nothing.
  void sendDirectHello(String targetIp) {
    if (_selfId == null || _selfName == null || _selfPlatform == null) return;
    final data = utf8.encode(_buildPayload(_selfId!, _selfName!, _selfPlatform!));
    _socket?.send(data, InternetAddress(targetIp), AppConstants.discoveryPort);
  }

  String _buildPayload(String id, String name, String platform) => jsonEncode({
        'tag': AppConstants.protocolTag,
        'id': id,
        'name': name,
        'platform': platform,
        'port': AppConstants.discoveryPort,
      });

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

      // First time we've heard from this id: ping it directly back once.
      // This means only ONE side needs to type the other's IP manually —
      // the other side auto-discovers via this reply.
      if (_acknowledgedIds.add(device.id)) {
        sendDirectHello(datagram.address.address);
      }
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