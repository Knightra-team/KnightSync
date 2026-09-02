import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/network_utils.dart';
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

  /// Fallback for when auto-discovery (broadcast) finds nothing — e.g.
  /// hotspot setups that limit broadcast traffic. The user types the
  /// other device's IP (shown on that device's own screen as "Your IP"),
  /// and we ping it directly.
  void connectManually(String ip) {
    final trimmed = ip.trim();
    if (trimmed.isEmpty) return;
    _discoveryService.sendDirectHello(trimmed);
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

    // Self-heal from the "socket goes deaf after network change" issue —
    // no user action (closing/reopening the app) should be needed.
    _rebindTimer = Timer.periodic(AppConstants.socketRebindInterval, (_) {
      _discoveryService.restart();
    });
  }

  @override
  void dispose() {
    _cleanupTimer?.cancel();
    _rebindTimer?.cancel();
    _subscription?.cancel();
    _discoveryService.dispose();
    super.dispose();
  }
}