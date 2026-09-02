import 'dart:io';

/// Small helper to find "what's my own local IP" — needed so we can show
/// it on screen for manual/hotspot pairing (the other person types this
/// IP in on their device).
class NetworkUtils {
  NetworkUtils._();

  /// Returns the first non-loopback IPv4 address of this device, or null
  /// if we can't find one (e.g. no active network interface at all).
  static Future<String?> getLocalIPv4() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    } catch (_) {
      // No permission / no network — caller just shows "unknown".
    }
    return null;
  }
}