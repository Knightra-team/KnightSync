import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/constants/app_constants.dart';
import '../../../models/device_model.dart';
import '../../../services/local_device_service.dart';
import '../data/discovery_service.dart';

/// The bridge between raw networking (DiscoveryService) and the widget
/// tree. Widgets never talk to sockets directly — they watch this
/// ChangeNotifier and rebuild when it calls notifyListeners().
class DiscoveryController extends ChangeNotifier {
  final DiscoveryService _discoveryService = DiscoveryService();
  final Map<String, DeviceModel> _devices = {};

  StreamSubscription<DeviceModel>? _subscription;
  Timer? _cleanupTimer;

  String? selfId;
  String selfName = '...';
  String selfPlatform = '...';
  bool isReady = false;

  List<DeviceModel> get devices => _devices.values.toList()
    ..sort((a, b) => a.name.compareTo(b.name));

  Future<void> init() async {
    selfId = await LocalDeviceService.getOrCreateDeviceId();
    selfName = await LocalDeviceService.getDeviceName();
    selfPlatform = LocalDeviceService.getPlatformName();
    isReady = true;
    notifyListeners();

    await _startDiscovery();
  }

  Future<void> _startDiscovery() async {
    _subscription = _discoveryService.onDeviceFound.listen((device) {
      _devices[device.id] = device;
      notifyListeners();
    });

    await _discoveryService.start(
      selfId: selfId!,
      selfName: selfName,
      selfPlatform: selfPlatform,
    );

    // Periodically drop devices we haven't heard from in a while
    // (they probably closed the app or left the Wi-Fi).
    _cleanupTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      final now = DateTime.now();
      final staleIds = _devices.entries
          .where((e) => now.difference(e.value.lastSeen) > AppConstants.deviceTimeout)
          .map((e) => e.key)
          .toList();

      if (staleIds.isNotEmpty) {
        staleIds.forEach(_devices.remove);
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _cleanupTimer?.cancel();
    _subscription?.cancel();
    _discoveryService.dispose();
    super.dispose();
  }
}
