enum TransferDirection { incoming, outgoing }

enum TransferStatus { inProgress, completed, failed }

/// One file transfer, in either direction, at some point in its
/// lifecycle. Mirrors DeviceModel's pattern: instances are effectively
/// immutable, and updates flow as new instances via [copyWith] pushed
/// through a stream, rather than mutating shared state.
class TransferTask {
  final String id;
  final String fileName;
  final int totalBytes;
  final int transferredBytes;
  final TransferDirection direction;
  final TransferStatus status;
  final String peerName;
  final String peerIp;
  final String? errorMessage;
  final String? savedPath;

  const TransferTask({
    required this.id,
    required this.fileName,
    required this.totalBytes,
    required this.transferredBytes,
    required this.direction,
    required this.status,
    required this.peerName,
    required this.peerIp,
    this.errorMessage,
    this.savedPath,
  });

  /// 0.0–1.0. Guards against divide-by-zero for the brief moment before
  /// we know the real size (shouldn't happen in practice since fileSize
  /// is always known up front, but zero-byte files are a real case).
  double get progress => totalBytes == 0 ? 1.0 : transferredBytes / totalBytes;

  TransferTask copyWith({
    int? transferredBytes,
    TransferStatus? status,
    String? errorMessage,
    String? savedPath,
  }) =>
      TransferTask(
        id: id,
        fileName: fileName,
        totalBytes: totalBytes,
        transferredBytes: transferredBytes ?? this.transferredBytes,
        direction: direction,
        status: status ?? this.status,
        peerName: peerName,
        peerIp: peerIp,
        errorMessage: errorMessage ?? this.errorMessage,
        savedPath: savedPath ?? this.savedPath,
      );
}
