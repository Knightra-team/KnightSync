import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/network_utils.dart';
import '../../../models/device_model.dart';
import '../../../services/local_device_service.dart';
import '../data/reliable_discovery_service.dart';

class DiscoveryController extends ChangeNotifier {
  final ReliableDiscoveryService _discoveryService =
      ReliableDiscoveryService();

  final Map<String, DeviceModel> _devices = {};
  StreamSubscription<DeviceModel>? _deviceSubscription;

  Timer? _cleanupTimer;
  Timer? _rebindTimer;

  String? selfId;
  String selfName = '...';
  String selfPlatform = '...';
  String? selfIp;

  bool isReady = false;

  List<DeviceModel> get devices => _devices.values.toList()
    ..sort((a, b) => a.name.compareTo(b.name));

  Future<void> init() async {
    selfId = await LocalDeviceService.getOrCreateDeviceId();
    selfName = await LocalDeviceService.getDeviceName();
    selfPlatform = LocalDeviceService.getPlatformName();
    selfIp = await NetworkUtils.getLocalIPv4();

    isReady = true;
    notifyListeners();

    await _startDiscovery();
  }

  String? validateManualIp(String ip) {
    final trimmed = ip.trim();
    return _isValidIPv4(trimmed) ? trimmed : null;
  }

  bool _isValidIPv4(String value) {
    final parts = value.split('.');
    if (parts.length != 4) return false;

    for (final part in parts) {
      final number = int.tryParse(part);
      if (number == null || number < 0 || number > 255) {
        return false;
      }
    }

    return true;
  }

  Future<void> _startDiscovery() async {
    _deviceSubscription = _discoveryService.onDeviceFound.listen((device) {
      _devices[device.id] = device;
      notifyListeners();
    });

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
              (entry) =>
                  now.difference(entry.value.lastSeen) >
                  AppConstants.deviceTimeout,
            )
            .map((entry) => entry.key)
            .toList();

        if (staleIds.isEmpty) return;

        for (final id in staleIds) {
          _devices.remove(id);
        }
        notifyListeners();
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
