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

  // Must be longer than the hotspot probe interval.
  static const Duration deviceTimeout =
      Duration(seconds: 10);

  static const Duration socketRebindInterval =
      Duration(seconds: 15);

  static const int fileTransferPort = 45733;

  // How long we wait for the raw TCP connect() itself to succeed —
  // this only measures "is the socket reachable", not whether a
  // human has answered yet.
  static const Duration socketConnectTimeout =
      Duration(seconds: 8);

  // How long the requester waits for the peer to actually
  // accept/decline, and how long the peer's device waits for its
  // user to tap Accept/Decline before auto-declining. Needs to be
  // long enough for a person to notice their phone and respond.
  static const Duration connectionRequestTimeout =
      Duration(seconds: 45);

  static const String downloadFolderName =
      'KnightSync';
}