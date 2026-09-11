import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../core/constants/app_constants.dart';
import '../../../models/device_model.dart';

class DiscoveryService {
  RawDatagramSocket? _socket;
  Timer? _broadcastTimer;
  Timer? _hotspotProbeTimer;

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
  bool _isSendingSubnetBroadcasts = false;
  bool _isProbingHotspot = false;

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
    _hotspotProbeTimer?.cancel();

    _broadcastTimer = Timer.periodic(
      AppConstants.broadcastInterval,
      (_) => _sendHelloToNetwork(),
    );

    // Broadcast is enough on most routers, but some mobile hotspots
    // isolate or drop broadcast traffic. The probe sends the same
    // discovery hello directly to all possible peers on the local /24
    // subnet, so discovery still works over a two-device hotspot.
    _hotspotProbeTimer = Timer.periodic(
      AppConstants.hotspotProbeInterval,
      (_) => _probeLocalSubnets(),
    );

    // Announce and probe immediately.
    _sendHelloToNetwork();
    _probeLocalSubnets();
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

          if (datagram == null) break;

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

    // Re-announce after rebinding.
    _sendHelloToNetwork();
    _probeLocalSubnets();
  }

  void _sendHelloToNetwork() {
    final data = _helloData();
    final socket = _socket;

    if (data == null || socket == null) return;

    // Global broadcast.
    _sendUdp(
      socket,
      data,
      InternetAddress('255.255.255.255'),
    );

    // Local subnet broadcasts.
    _sendSubnetBroadcasts(socket, data);
  }

  Future<void> _sendSubnetBroadcasts(
    RawDatagramSocket socket,
    List<int> data,
  ) async {
    if (_isSendingSubnetBroadcasts) return;
    _isSendingSubnetBroadcasts = true;

    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );

      final sent = <String>{};

      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (address.isLoopback) continue;

          final subnet = _subnetPrefix(address.address);
          if (subnet == null) continue;

          final broadcast = '$subnet.255';

          if (sent.add(broadcast)) {
            _sendUdp(
              socket,
              data,
              InternetAddress(broadcast),
            );
          }
        }
      }
    } catch (_) {
      // Global broadcast was already attempted.
    } finally {
      _isSendingSubnetBroadcasts = false;
    }
  }

  Future<void> _probeLocalSubnets() async {
    if (_isProbingHotspot) return;

    final socket = _socket;
    final data = _helloData();

    if (socket == null || data == null) return;

    _isProbingHotspot = true;

    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );

      final prefixes = <String>{};

      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (address.isLoopback) continue;

          final prefix = _subnetPrefix(address.address);
          if (prefix != null) {
            prefixes.add(prefix);
          }
        }
      }

      for (final prefix in prefixes) {
        for (var host = 1; host <= 254; host++) {
          final target = '$prefix.$host';

          _sendUdp(
            socket,
            data,
            InternetAddress(target),
          );
        }
      }
    } catch (_) {
      // A failed probe must never stop normal broadcast discovery.
    } finally {
      _isProbingHotspot = false;
    }
  }

  String? _subnetPrefix(String ip) {
    final parts = ip.split('.');

    if (parts.length != 4) return null;

    final numbers = parts.map(int.tryParse).toList();

    if (numbers.any((value) => value == null)) {
      return null;
    }

    return '${parts[0]}.${parts[1]}.${parts[2]}';
  }

  List<int>? _helloData() {
    final id = _selfId;
    final name = _selfName;
    final platform = _selfPlatform;

    if (id == null || name == null || platform == null) {
      return null;
    }

    return utf8.encode(
      _buildPayload(
        id: id,
        name: name,
        platform: platform,
        type: 'hello',
      ),
    );
  }

  void _sendUdp(
    RawDatagramSocket socket,
    List<int> data,
    InternetAddress address,
  ) {
    try {
      socket.send(
        data,
        address,
        AppConstants.discoveryPort,
      );
    } catch (_) {
      // Ignore unreachable interfaces/addresses.
    }
  }

  void sendConnectionRequest(String targetIp) {
    final data = _connectionRequestData();

    if (data == null) return;

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
    final data = _helloData();

    if (data == null) return;

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

  List<int>? _connectionRequestData() {
    final id = _selfId;
    final name = _selfName;
    final platform = _selfPlatform;

    if (id == null || name == null || platform == null) {
      return null;
    }

    return utf8.encode(
      _buildPayload(
        id: id,
        name: name,
        platform: platform,
        type: 'connect_request',
      ),
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

      // Every valid hello refreshes the device in the UI.
      _deviceFoundController.add(device);

      if (type == 'connect_request') {
        _connectionRequestController.add(device);
        return;
      }

      // Reply directly once. This helps devices that cannot receive
      // hotspot/router broadcasts but can receive normal unicast UDP.
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

    _hotspotProbeTimer?.cancel();
    _hotspotProbeTimer = null;

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
