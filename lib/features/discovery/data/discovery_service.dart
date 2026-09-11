import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../core/constants/app_constants.dart';
import '../../../models/device_model.dart';

class DiscoveryService {
  RawDatagramSocket? _socket;

  Timer? _broadcastTimer;
  Timer? _hotspotProbeTimer;

  final StreamController<DeviceModel> _deviceFoundController =
      StreamController<DeviceModel>.broadcast();

  final StreamController<DeviceModel> _connectionRequestController =
      StreamController<DeviceModel>.broadcast();

  final Set<String> _acknowledgedIds = <String>{};

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

  // ---------------------------------------------------------------------------
  // START
  // ---------------------------------------------------------------------------

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
      (_) {
        _sendHelloToNetwork();
      },
    );

    _hotspotProbeTimer = Timer.periodic(
      AppConstants.hotspotProbeInterval,
      (_) {
        _probeLocalSubnets();
      },
    );

    _sendHelloToNetwork();
    _probeLocalSubnets();
  }

  // ---------------------------------------------------------------------------
  // SOCKET
  // ---------------------------------------------------------------------------

  Future<void> _bindSocket() async {
    if (_isBinding) {
      return;
    }

    _isBinding = true;

    try {
      _socket?.close();
      _socket = null;

      final RawDatagramSocket socket =
          await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        AppConstants.discoveryPort,
        reuseAddress: true,
      );

      socket.broadcastEnabled = true;

      _socket = socket;

      socket.listen(
        (RawSocketEvent event) {
          if (event != RawSocketEvent.read) {
            return;
          }

          while (true) {
            final Datagram? datagram = socket.receive();

            if (datagram == null) {
              break;
            }

            _handleIncomingPacket(
              datagram,
              _selfId ?? '',
            );
          }
        },
        onError: (_) {
          // Ignore socket errors.
        },
      );
    } catch (_) {
      _socket = null;
    } finally {
      _isBinding = false;
    }
  }

  Future<void> restart() async {
    if (_selfId == null) {
      return;
    }

    await _bindSocket();

    _sendHelloToNetwork();
    _probeLocalSubnets();
  }

  // ---------------------------------------------------------------------------
  // DISCOVERY
  // ---------------------------------------------------------------------------

  void _sendHelloToNetwork() {
    final List<int>? data = _helloData();
    final RawDatagramSocket? socket = _socket;

    if (data == null || socket == null) {
      return;
    }

    // Global broadcast.
    _sendUdp(
      socket,
      data,
      InternetAddress('255.255.255.255'),
    );

    // Interface-specific broadcasts.
    _sendSubnetBroadcasts(
      socket,
      data,
    );
  }

  Future<void> _sendSubnetBroadcasts(
    RawDatagramSocket socket,
    List<int> data,
  ) async {
    if (_isSendingSubnetBroadcasts) {
      return;
    }

    _isSendingSubnetBroadcasts = true;

    try {
      final List<NetworkInterface> interfaces =
          await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );

      final Set<String> sent = <String>{};

      for (final NetworkInterface networkInterface
          in interfaces) {
        for (final address
            in networkInterface.addresses) {
          if (_isLoopbackAddress(address)) {
            continue;
          }

          final String? broadcast =
              _broadcastAddress(address);

          if (broadcast == null) {
            continue;
          }

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

  // ---------------------------------------------------------------------------
  // HOTSPOT / DIRECT PROBE
  // ---------------------------------------------------------------------------

  Future<void> _probeLocalSubnets() async {
    if (_isProbingHotspot) {
      return;
    }

    final RawDatagramSocket? socket = _socket;
    final List<int>? data = _helloData();

    if (socket == null || data == null) {
      return;
    }

    _isProbingHotspot = true;

    try {
      final List<NetworkInterface> interfaces =
          await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );

      final Set<String> ranges = <String>{};

      for (final NetworkInterface networkInterface
          in interfaces) {
        for (final address
            in networkInterface.addresses) {
          if (_isLoopbackAddress(address)) {
            continue;
          }

          final String? range =
              _smallSubnetRange(address);

          if (range != null) {
            ranges.add(range);
          }
        }
      }

      for (final String range in ranges) {
        final List<String> parts =
            range.split(':');

        if (parts.length != 2) {
          continue;
        }

        final String network = parts[0];

        final int? hostCount =
            int.tryParse(parts[1]);

        if (hostCount == null ||
            hostCount <= 1) {
          continue;
        }

        for (int host = 1;
            host < hostCount;
            host++) {
          _sendUdp(
            socket,
            data,
            InternetAddress(
              '$network.$host',
            ),
          );
        }
      }
    } catch (_) {
      // A failed probe must never stop discovery.
    } finally {
      _isProbingHotspot = false;
    }
  }

  // ---------------------------------------------------------------------------
  // NETWORK HELPERS
  //
  // IMPORTANT:
  // We intentionally do NOT use InterfaceAddress here.
  // ---------------------------------------------------------------------------

  bool _isLoopbackAddress(dynamic address) {
    try {
      return address.isLoopback == true;
    } catch (_) {
      return false;
    }
  }

  String? _broadcastAddress(dynamic address) {
    try {
      final dynamic broadcast =
          address.broadcast;

      if (broadcast == null) {
        return null;
      }

      final dynamic value =
          broadcast.address;

      if (value is! String ||
          value.isEmpty) {
        return null;
      }

      return value;
    } catch (_) {
      return null;
    }
  }

  String? _smallSubnetRange(dynamic address) {
    try {
      final dynamic addressValue =
          address.address;

      final dynamic prefixValue =
          address.prefixLength;

      if (addressValue is! String) {
        return null;
      }

      if (prefixValue is! int) {
        return null;
      }

      final String ip = addressValue;
      final int prefixLength = prefixValue;

      final List<String> parts =
          ip.split('.');

      if (parts.length != 4) {
        return null;
      }

      final List<int?> numbers =
          parts.map<int?>(
        (String value) {
          return int.tryParse(value);
        },
      ).toList();

      if (numbers.any(
        (int? value) => value == null,
      )) {
        return null;
      }

      // Only probe reasonably small networks.
      //
      // /23 = 512 addresses
      // /24 = 256 addresses
      // /25 = 128 addresses
      // /26 = 64 addresses
      // /27 = 32 addresses
      // /28 = 16 addresses
      // /29 = 8 addresses
      // /30 = 4 addresses
      if (prefixLength < 23 ||
          prefixLength > 30) {
        return null;
      }

      final int hostBits =
          32 - prefixLength;

      final int hostCount =
          1 << hostBits;

      final int ipValue =
          (numbers[0]! << 24) |
          (numbers[1]! << 16) |
          (numbers[2]! << 8) |
          numbers[3]!;

      final int mask =
          (0xFFFFFFFF >> hostBits) <<
              hostBits;

      final int networkValue =
          ipValue & mask;

      final String network = [
        (networkValue >> 24) & 0xFF,
        (networkValue >> 16) & 0xFF,
        (networkValue >> 8) & 0xFF,
      ].join('.');

      return '$network:$hostCount';
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // HELLO DATA
  // ---------------------------------------------------------------------------

  List<int>? _helloData() {
    final String? id = _selfId;
    final String? name = _selfName;
    final String? platform = _selfPlatform;

    if (id == null ||
        name == null ||
        platform == null) {
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

  // ---------------------------------------------------------------------------
  // UDP
  // ---------------------------------------------------------------------------

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
      // Ignore unavailable interfaces/addresses.
    }
  }

  // ---------------------------------------------------------------------------
  // CONNECTION REQUEST
  // ---------------------------------------------------------------------------

  void sendConnectionRequest(
    String targetIp,
  ) {
    final List<int>? data =
        _connectionRequestData();

    if (data == null) {
      return;
    }

    final RawDatagramSocket? socket =
        _socket;

    if (socket == null) {
      return;
    }

    try {
      socket.send(
        data,
        InternetAddress(targetIp),
        AppConstants.discoveryPort,
      );
    } catch (_) {
      // Ignore unavailable target.
    }
  }

  // ---------------------------------------------------------------------------
  // DIRECT HELLO
  // ---------------------------------------------------------------------------

  void sendDirectHello(
    String targetIp,
  ) {
    final List<int>? data =
        _helloData();

    if (data == null) {
      return;
    }

    final RawDatagramSocket? socket =
        _socket;

    if (socket == null) {
      return;
    }

    try {
      socket.send(
        data,
        InternetAddress(targetIp),
        AppConstants.discoveryPort,
      );
    } catch (_) {
      // Ignore unavailable target.
    }
  }

  // ---------------------------------------------------------------------------
  // CONNECTION REQUEST DATA
  // ---------------------------------------------------------------------------

  List<int>? _connectionRequestData() {
    final String? id = _selfId;
    final String? name = _selfName;
    final String? platform = _selfPlatform;

    if (id == null ||
        name == null ||
        platform == null) {
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

  // ---------------------------------------------------------------------------
  // PAYLOAD
  // ---------------------------------------------------------------------------

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

  // ---------------------------------------------------------------------------
  // RECEIVE
  // ---------------------------------------------------------------------------

  void _handleIncomingPacket(
    Datagram datagram,
    String selfId,
  ) {
    try {
      final String message =
          utf8.decode(datagram.data);

      final dynamic decoded =
          jsonDecode(message);

      if (decoded
          is! Map<String, dynamic>) {
        return;
      }

      final Map<String, dynamic> json =
          decoded;

      if (json['tag'] !=
          AppConstants.protocolTag) {
        return;
      }

      if (json['id'] == selfId) {
        return;
      }

      final DeviceModel device =
          DeviceModel.fromJson(
        json,
        datagram.address.address,
      );

      final String type =
          json['type'] as String? ??
              'hello';

      // Every valid packet refreshes the device.
      _deviceFoundController.add(
        device,
      );

      if (type == 'connect_request') {
        _connectionRequestController
            .add(device);

        return;
      }

      // Answer the peer once.
      //
      // This is useful when broadcast is blocked
      // but unicast UDP still works.
      if (_acknowledgedIds.add(
        device.id,
      )) {
        sendDirectHello(
          datagram.address.address,
        );
      }
    } catch (_) {
      // Ignore malformed UDP packets.
    }
  }

  // ---------------------------------------------------------------------------
  // STOP
  // ---------------------------------------------------------------------------

  void stop() {
    _broadcastTimer?.cancel();
    _broadcastTimer = null;

    _hotspotProbeTimer?.cancel();
    _hotspotProbeTimer = null;

    _socket?.close();
    _socket = null;

    _acknowledgedIds.clear();

    _isSendingSubnetBroadcasts = false;
    _isProbingHotspot = false;
  }

  // ---------------------------------------------------------------------------
  // DISPOSE
  // ---------------------------------------------------------------------------

  void dispose() {
    stop();

    _deviceFoundController.close();
    _connectionRequestController.close();
  }
}