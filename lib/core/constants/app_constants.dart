class AppConstants {
  AppConstants._();

  static const String appName = 'KnightSync';

  static const int discoveryPort = 45732;
  static const String protocolTag = 'KNIGHT_RASYNC_HELLO_V1';

  static const Duration broadcastInterval =
      Duration(seconds: 2);

  // Hotspots can block UDP broadcast. Unicast probing is the fallback.
  static const Duration hotspotProbeInterval =
      Duration(seconds: 4);

  static const Duration deviceTimeout =
      Duration(seconds: 10);

  static const Duration socketRebindInterval =
      Duration(seconds: 15);

  static const int fileTransferPort = 45733;

  // Persistent connection/session control channel. File transfers continue to
  // use fileTransferPort; this port only handles connection liveness.
  static const int sessionPort = 45734;

  static const Duration socketConnectTimeout =
      Duration(seconds: 8);

  static const Duration connectionRequestTimeout =
      Duration(seconds: 45);

  static const Duration sessionHandshakeTimeout =
      Duration(seconds: 8);

  static const String downloadFolderName =
      'KnightSync';
}
