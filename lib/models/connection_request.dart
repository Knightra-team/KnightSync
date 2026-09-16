import 'device_model.dart';

/// An incoming request from [device] asking to connect.
///
/// The peer is left waiting on the other end of the socket until this
/// is answered (or it times out), so the UI should show this to the
/// user immediately and call [respond] as soon as they decide.
class ConnectionRequest {
  ConnectionRequest({
    required this.device,
    required void Function(bool accepted) onRespond,
  }) : _onRespond = onRespond;

  final DeviceModel device;
  final void Function(bool accepted) _onRespond;

  bool _answered = false;

  /// True once this request has already been answered (by the user,
  /// or by timing out). Calling [respond] again after this is a
  /// harmless no-op.
  bool get isAnswered => _answered;

  void respond(bool accepted) {
    if (_answered) return;
    _answered = true;
    _onRespond(accepted);
  }
}

enum ConnectionRequestStatus {
  /// The peer answered and accepted.
  accepted,

  /// The peer answered and declined.
  declined,

  /// No usable answer arrived in time — could be offline, an
  /// unreachable address, or (very commonly on hotspots) a firewall
  /// or AP-isolation setting silently dropping the connection.
  unreachable,
}

class ConnectionRequestResult {
  const ConnectionRequestResult({
    required this.status,
    this.device,
  });

  final ConnectionRequestStatus status;

  /// The peer's confirmed identity. Only set when [status] is
  /// [ConnectionRequestStatus.accepted].
  final DeviceModel? device;
}
