import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../core/constants/app_constants.dart';
import '../../../models/device_model.dart';

/// Bidirectional LAN discovery.
///
/// The original implementation relied heavily on UDP broadcast. Broadcast /
/// multicast delivery can be filtered by Wi-Fi access points and Android's
/// Wi-Fi stack, so this service keeps broadcast for fast discovery but also
/// performs direct unicast probes across each local IPv4 subnet.
///
/// This means both peers actively search for each other instead of depending
/// on one peer receiving the other's broadcast packet.
class ReliableDiscoveryService {
  RawDatagramSocket? _socket;

  Timer? _broadcastTimer;
  Timer? _probeTimer;

  final StreamController<DeviceModel> _deviceFoundController =
      StreamController<DeviceModel>.broadcast();

  /// Last time we replied directly to a peer. A short cooldown prevents two
  /// peers from creating a UDP response storm while they are probing each
  /// other repeatedly.
  final Map<String, DateTime> _lastResponseAt = <String, DateTime>{};

  String? _selfId;
  String? _selfName;
  String? _selfPlatform;

  bool _isBinding = false;
  bool _isProbing = false;
  bool _disposed = false;

  Stream<DeviceModel> get onDeviceFound => _deviceFoundController.stream;

  Future<void> start({
    required String selfId,
    required String selfName,
    required String selfPlatform,
  }) async {
    _disposed = false;
    _selfId = selfId;
    _selfName = selfName;
    _selfPlatform = selfPlatform;

    await _bindSocket();
    _startTimers();

    // First discovery pass happens immediately. We do not wait for a timer
    // tick, so the UI can show both peers as soon as possible.
    _sendHelloToNetwork();
    await _probeLocalSubnets();
  }

  Future<void> restart() async {
    if (_disposed || _selfId == null) return;

    await _bindSocket();
    _sendHelloToNetwork();
    await _probeLocalSubnets();
  }

  void _startTimers() {
    _broadcastTimer?.cancel();
    _probeTimer?.cancel();

    // Keep broadcast for the fast/common case.
    _broadcastTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _sendHelloToNetwork(),
    );

    // Unicast probing is the important fallback for Android/hotspots.
    _probeTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _probeLocalSubnets(),
    );
  }

  Future<void> _bindSocket() async {
    if (_isBinding || _disposed) return;

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

      socket.listen(
        (RawSocketEvent event) {
          if (event != RawSocketEvent.read) return;

          while (true) {
            final datagram = socket.receive();
            if (datagram == null) break;
            _handleIncomingPacket(datagram);
          }
        },
        onError: (_) {
          // Keep discovery alive; the periodic restart/probe will recover.
        },
      );
    } catch (_) {
      _socket = null;
    } finally {
      _isBinding = false;
    }
  }

  void _sendHelloToNetwork() {
    final socket = _socket;
    final data = _helloData();

    if (socket == null || data == null || _disposed) return;

    // Standard broadcast.
    _sendUdp(
      socket,
      data,
      InternetAddress('255.255.255.255'),
    );

    // Interface-specific broadcasts are useful on routers that suppress
    // global broadcast packets.
    _sendInterfaceBroadcasts(socket, data);
  }

  Future<void> _sendInterfaceBroadcasts(
    RawDatagramSocket socket,
    List<int> data,
  ) async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: true,
      );

      final sent = <String>{};

      for (final networkInterface in interfaces) {
        for (final address in networkInterface.addresses) {
          final ip = address.address;
          if (!_isUsableIPv4(address, ip)) continue;

          final broadcast = _broadcastAddress(address);
          if (broadcast != null && sent.add(broadcast)) {
            _sendUdp(socket, data, InternetAddress(broadcast));
          }
        }
      }
    } catch (_) {
      // Global broadcast already happened.
    }
  }

  Future<void> _probeLocalSubnets() async {
    if (_disposed || _isProbing) return;

    final socket = _socket;
    final data = _helloData();
    if (socket == null || data == null) return;

    _isProbing = true;
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: true,
      );

      final targets = <String>{};

      for (final networkInterface in interfaces) {
        for (final address in networkInterface.addresses) {
          final ip = address.address;
          if (!_isUsableIPv4(address, ip)) continue;

          targets.addAll(_buildProbeTargets(address, ip));
        }
      }

      // Every device actively sends a hello to every likely peer. This is the
      // part that removes the one-way-discovery problem caused by broadcast
      // filtering.
      for (final target in targets) {
        _sendUdp(socket, data, InternetAddress(target));
      }
    } catch (_) {
      // Discovery must never crash the app because an interface disappears.
    } finally {
      _isProbing = false;
    }
  }

  bool _isUsableIPv4(dynamic address, String ip) {
    try {
      if (address.type != InternetAddressType.IPv4) return false;
      if (address.isLoopback == true) return false;
      if (address.isLinkLocal == true && !ip.startsWith('169.254.')) {
        return false;
      }
    } catch (_) {
      // Keep the fallback below useful for platform implementations that do
      // not expose all InterfaceAddress metadata.
      if (ip.startsWith('127.')) return false;
    }

    final parts = ip.split('.');
    if (parts.length != 4) return false;

    for (final part in parts) {
      final value = int.tryParse(part);
      if (value == null || value < 0 || value > 255) return false;
    }

    return true;
  }

  String? _broadcastAddress(dynamic address) {
    try {
      final dynamic broadcast = address.broadcast;
      if (broadcast == null) return null;

      final value = broadcast.address;
      if (value is String && value.isNotEmpty) return value;
    } catch (_) {
      // Some platform implementations do not expose broadcast metadata.
    }

    return null;
  }

  Set<String> _buildProbeTargets(dynamic address, String ip) {
    final targets = <String>{};
    final numbers = ip.split('.').map(int.parse).toList();

    // Prefer the real subnet prefix when the platform exposes it.
    int? prefixLength;
    try {
      final dynamic prefix = address.prefixLength;
      if (prefix is int) prefixLength = prefix;
    } catch (_) {
      prefixLength = null;
    }

    if (prefixLength != null && prefixLength >= 23 && prefixLength <= 30) {
      final hostBits = 32 - prefixLength;
      final hostCount = 1 << hostBits;
      final ipValue = (numbers[0] << 24) |
          (numbers[1] << 16) |
          (numbers[2] << 8) |
          numbers[3];
      final mask = (0xFFFFFFFF << hostBits) & 0xFFFFFFFF;
      final networkValue = ipValue & mask;

      for (var host = 1; host < hostCount - 1; host++) {
        final value = networkValue + host;
        targets.add(_ipv4FromInt(value));
      }
      return targets;
    }

    // Safe fallback for normal home routers / Android hotspots. Most of these
    // use /24 networks, and this also works when InterfaceAddress metadata is
    // unavailable on a particular platform build.
    final prefix = '${numbers[0]}.${numbers[1]}.${numbers[2]}';
    for (var host = 1; host <= 254; host++) {
      targets.add('$prefix.$host');
    }

    return targets;
  }

  String _ipv4FromInt(int value) {
    return '${(value >> 24) & 0xFF}.'
        '${(value >> 16) & 0xFF}.'
        '${(value >> 8) & 0xFF}.'
        '${value & 0xFF}';
  }

  List<int>? _helloData() {
    final id = _selfId;
    final name = _selfName;
    final platform = _selfPlatform;

    if (id == null || name == null || platform == null) return null;

    return utf8.encode(
      jsonEncode({
        'tag': AppConstants.protocolTag,
        'type': 'hello',
        'id': id,
        'name': name,
        'platform': platform,
        'port': AppConstants.discoveryPort,
      }),
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
      // Ignore unavailable interfaces/targets.
    }
  }

  void _handleIncomingPacket(Datagram datagram) {
    try {
      final decoded = jsonDecode(utf8.decode(datagram.data));
      if (decoded is! Map<String, dynamic>) return;

      final json = decoded;
      if (json['tag'] != AppConstants.protocolTag) return;
      if (json['type'] != 'hello') return;
      if (json['id'] == _selfId) return;

      final device = DeviceModel.fromJson(
        json,
        datagram.address.address,
      );

      _deviceFoundController.add(device);

      // Respond directly as a second path. If a peer could not receive our
      // broadcast, its subnet probe can still receive this unicast response.
      final now = DateTime.now();
      final lastResponse = _lastResponseAt[device.id];
      if (lastResponse == null ||
          now.difference(lastResponse) >= const Duration(seconds: 2)) {
        _lastResponseAt[device.id] = now;
        final data = _helloData();
        final socket = _socket;
        if (data != null && socket != null) {
          _sendUdp(socket, data, datagram.address);
        }
      }
    } catch (_) {
      // Ignore malformed or unrelated UDP packets.
    }
  }

  void stop() {
    _broadcastTimer?.cancel();
    _broadcastTimer = null;

    _probeTimer?.cancel();
    _probeTimer = null;

    _socket?.close();
    _socket = null;

    _lastResponseAt.clear();
    _isProbing = false;
  }

  Future<void> dispose() async {
    _disposed = true;
    stop();
    await _deviceFoundController.close();
  }
}
