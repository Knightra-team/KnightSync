import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Everything related to "who am I on this network".
/// Static/stateless on purpose — there is exactly one local device,
/// no need to instantiate this like a normal service.
class LocalDeviceService {
  LocalDeviceService._();

  static const _idKey = 'knight_device_id';
  static const _uuid = Uuid();

  /// Returns a UUID that stays the same across app restarts, generating
  /// one on first launch. This is what lets a device be "remembered".
  static Future<String> getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? id = prefs.getString(_idKey);
    if (id == null) {
      id = _uuid.v4();
      await prefs.setString(_idKey, id);
    }
    return id;
  }

  /// Human-friendly name shown to the other device, e.g.
  /// "Samsung Galaxy S23" or "DESKTOP-AB12CD".
  static Future<String> getDeviceName() async {
    final infoPlugin = DeviceInfoPlugin();
    try {
      if (Platform.isAndroid) {
        final info = await infoPlugin.androidInfo;
        return '${info.manufacturer} ${info.model}';
      } else if (Platform.isWindows) {
        final info = await infoPlugin.windowsInfo;
        return info.computerName;
      }
    } catch (_) {
      // Fall through to the generic fallback below.
    }
    return Platform.operatingSystem;
  }

  static String getPlatformName() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isWindows) return 'windows';
    return Platform.operatingSystem;
  }
}
