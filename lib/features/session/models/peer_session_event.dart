import '../../../models/device_model.dart';

enum PeerSessionEventType {
  connected,
  peerLeft,
  disconnected,
}

class PeerSessionEvent {
  const PeerSessionEvent({
    required this.type,
    required this.device,
  });

  final PeerSessionEventType type;
  final DeviceModel device;
}
