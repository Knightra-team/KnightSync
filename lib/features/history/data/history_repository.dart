import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/transfer_history_entry.dart';

class HistoryRepository {
  static const _storageKey = 'knightsync_received_history_v1';
  static const _maxEntries = 200;

  Future<List<TransferHistoryEntry>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_storageKey) ?? <String>[];
    final entries = <TransferHistoryEntry>[];

    for (final value in raw) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map<String, dynamic>) {
          entries.add(TransferHistoryEntry.fromJson(decoded));
        }
      } catch (_) {
        // Ignore one malformed history item instead of breaking the whole
        // history screen.
      }
    }

    entries.sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    return entries;
  }

  Future<void> add(TransferHistoryEntry entry) async {
    final entries = await load();
    entries.removeWhere((item) => item.id == entry.id);
    entries.insert(0, entry);

    final trimmed = entries.take(_maxEntries).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _storageKey,
      trimmed
          .map((item) => jsonEncode(item.toJson()))
          .toList(),
    );
  }
}
