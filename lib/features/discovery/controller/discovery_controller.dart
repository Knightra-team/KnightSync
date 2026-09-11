import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/network_utils.dart';
import '../../../models/device_model.dart';
import '../../../services/local_device_service.dart';
import '../data/discovery_service.dart';

class DiscoveryController extends ChangeNotifier {
  final DiscoveryService _discoveryService =
      DiscoveryService();

  final Map<String, DeviceModel> _devices = {};

  StreamSubscription<DeviceModel>?
      _deviceSubscription;

  Timer? _cleanupTimer;
  Timer? _rebindTimer;

  String? selfId;
  String selfName = '...';
  String selfPlatform = '...';
  String? selfIp;

  bool isReady = false;

  Stream<DeviceModel> get onConnectionRequest =>
      _discoveryService.onConnectionRequest;

  List<DeviceModel> get devices =>
      _devices.values.toList()
        ..sort(
          (a, b) => a.name.compareTo(b.name),
        );

  Future<void> init() async {
    selfId =
        await LocalDeviceService.getOrCreateDeviceId();

    selfName =
        await LocalDeviceService.getDeviceName();

    selfPlatform =
        LocalDeviceService.getPlatformName();

    selfIp =
        await NetworkUtils.getLocalIPv4();

    isReady = true;
    notifyListeners();

    await _startDiscovery();
  }

  void connect(DeviceModel device) {
    _discoveryService.sendConnectionRequest(
      device.ip,
    );
  }

  /// Manual IP is a direct TCP fallback.
  ///
  /// We do not depend on the UDP discovery request here. If the user
  /// already knows the peer IP, the transfer screen can connect directly
  /// to port 45733. This makes manual pairing useful even when hotspot
  /// UDP discovery is blocked.
  DeviceModel? connectManually(String ip) {
    final trimmed = ip.trim();

    if (trimmed.isEmpty || !_isValidIPv4(trimmed)) {
      return null;
    }

    _discoveryService.sendConnectionRequest(trimmed);

    return DeviceModel(
      id: 'manual:$trimmed',
      name: 'Manual device',
      platform: 'unknown',
      ip: trimmed,
      port: AppConstants.fileTransferPort,
      lastSeen: DateTime.now(),
    );
  }

  bool _isValidIPv4(String value) {
    final parts = value.split('.');

    if (parts.length != 4) return false;

    for (final part in parts) {
      final number = int.tryParse(part);

      if (number == null ||
          number < 0 ||
          number > 255) {
        return false;
      }
    }

    return true;
  }

  Future<void> _startDiscovery() async {
    _deviceSubscription =
        _discoveryService.onDeviceFound.listen(
      (device) {
        _devices[device.id] = device;
        notifyListeners();
      },
    );

    await _discoveryService.start(
      selfId: selfId!,
      selfName: selfName,
      selfPlatform: selfPlatform,
    );

    _cleanupTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) {
        final now = DateTime.now();

        final staleIds = _devices.entries
            .where(
              (e) =>
                  now.difference(e.value.lastSeen) >
                  AppConstants.deviceTimeout,
            )
            .map((e) => e.key)
            .toList();

        if (staleIds.isNotEmpty) {
          for (final id in staleIds) {
            _devices.remove(id);
          }

          notifyListeners();
        }
      },
    );

    _rebindTimer = Timer.periodic(
      AppConstants.socketRebindInterval,
      (_) {
        _discoveryService.restart();
      },
    );
  }

  @override
  void dispose() {
    _cleanupTimer?.cancel();
    _rebindTimer?.cancel();
    _deviceSubscription?.cancel();

    _discoveryService.dispose();

    super.dispose();
  }
}
