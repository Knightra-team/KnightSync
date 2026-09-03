/// Constants shared across the whole app.
/// Keeping magic numbers/strings here means when we tune the protocol
/// later (e.g. change the port), we touch exactly one file.
class AppConstants {
  AppConstants._();

  static const String appName = 'KnightRaSync';

  /// UDP port both Android and Windows listen on for discovery broadcasts.
  /// Must be the same on both platforms, and ideally >1024 so it doesn't
  /// need special permissions on either OS.
  static const int discoveryPort = 45732;

  /// A short tag we stamp on every discovery packet so we can safely
  /// ignore random UDP broadcast noise from other apps on the network.
  static const String protocolTag = 'KNIGHT_RASYNC_HELLO_V1';

  /// How often each device shouts "I'm here" on the network.
  static const Duration broadcastInterval = Duration(seconds: 2);

  /// If we haven't heard from a device in this long, we assume it left
  /// the network (closed the app, disconnected Wi-Fi, etc.) and remove
  /// it from the list.
  static const Duration deviceTimeout = Duration(seconds: 6);

  /// On Android especially, a UDP socket can go "deaf" after the OS
  /// switches Wi-Fi networks (join hotspot, rejoin router, etc.) — it
  /// stays open but silently stops receiving broadcasts. Rebinding the
  /// socket periodically is a cheap way to self-heal from that without
  /// needing the user to restart the app.
  static const Duration socketRebindInterval = Duration(seconds: 15);

  /// TCP port used for actual file transfer (separate from the UDP
  /// discovery port above — one device can be discoverable without a
  /// transfer in progress, and vice versa).
  static const int fileTransferPort = 45733;

  /// Subfolder (inside the app's own documents directory) where files
  /// received from other devices are saved. App-private storage means
  /// no extra runtime permission is needed on Android for this MVP.
  static const String downloadFolderName = 'KnightRaSyncReceived';
}