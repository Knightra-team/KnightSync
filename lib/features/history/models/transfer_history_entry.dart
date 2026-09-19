class TransferHistoryEntry {
  const TransferHistoryEntry({
    required this.id,
    required this.fileName,
    required this.peerName,
    required this.peerIp,
    required this.savedPath,
    required this.sizeBytes,
    required this.receivedAt,
  });

  final String id;
  final String fileName;
  final String peerName;
  final String peerIp;
  final String savedPath;
  final int sizeBytes;
  final DateTime receivedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'fileName': fileName,
        'peerName': peerName,
        'peerIp': peerIp,
        'savedPath': savedPath,
        'sizeBytes': sizeBytes,
        'receivedAt': receivedAt.toIso8601String(),
      };

  factory TransferHistoryEntry.fromJson(Map<String, dynamic> json) {
    return TransferHistoryEntry(
      id: json['id'] as String,
      fileName: json['fileName'] as String,
      peerName: json['peerName'] as String,
      peerIp: json['peerIp'] as String,
      savedPath: json['savedPath'] as String,
      sizeBytes: (json['sizeBytes'] as num).toInt(),
      receivedAt: DateTime.parse(json['receivedAt'] as String),
    );
  }
}
