class AppConstants {
  AppConstants._();

  static const String appName = 'KnightSync';

  static const int discoveryPort = 45732;
  static const String protocolTag = 'KNIGHT_RASYNC_HELLO_V1';

  static const Duration broadcastInterval =
      Duration(seconds: 2);

  // Used when normal UDP broadcast is blocked by a mobile hotspot.
  static const Duration hotspotProbeInterval =
      Duration(seconds: 8);

  static const Duration deviceTimeout =
      Duration(seconds: 6);

  static const Duration socketRebindInterval =
      Duration(seconds: 15);

  static const int fileTransferPort = 45733;

  static const String downloadFolderName =
      'KnightSync';
}
