import '../core/constants/app_constants.dart';

/// Represents one device (phone or PC) seen on the local network.
///
/// `id` is a stable UUID generated once per install and stored locally —
/// NOT the IP address, because IPs can change (DHCP) but we still want
/// to recognize "this is the same laptop I paired with yesterday".
class DeviceModel {
  final String id;
  final String name;
  final String platform; // 'android' | 'windows'
  final String ip;
  final int port;
  final DateTime lastSeen;

  const DeviceModel({
    required this.id,
    required this.name,
    required this.platform,
    required this.ip,
    required this.port,
    required this.lastSeen,
  });

  /// Builds a DeviceModel from an incoming discovery packet.
  /// `ip` comes from the UDP datagram's sender address, not from the
  /// JSON payload itself (a device can't reliably know its own IP as
  /// seen by others, especially behind NAT/VPN adapters).
  factory DeviceModel.fromJson(Map<String, dynamic> json, String ip) {
    return DeviceModel(
      id: json['id'] as String,
      name: json['name'] as String,
      platform: json['platform'] as String,
      ip: ip,
      port: json['port'] as int,
      lastSeen: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'tag': AppConstants.protocolTag,
        'id': id,
        'name': name,
        'platform': platform,
        'port': port,
      };

  DeviceModel copyWith({DateTime? lastSeen}) => DeviceModel(
        id: id,
        name: name,
        platform: platform,
        ip: ip,
        port: port,
        lastSeen: lastSeen ?? this.lastSeen,
      );
}
