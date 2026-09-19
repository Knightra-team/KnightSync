import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';

import '../data/history_repository.dart';
import '../models/transfer_history_entry.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _repository = HistoryRepository();
  late Future<List<TransferHistoryEntry>> _historyFuture;

  @override
  void initState() {
    super.initState();
    _historyFuture = _repository.load();
  }

  Future<void> _openFile(TransferHistoryEntry entry) async {
    if (!await File(entry.savedPath).exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The file is no longer available.')),
      );
      return;
    }

    final result = await OpenFile.open(entry.savedPath);
    if (!mounted || result.type == ResultType.done) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
      ),
      body: FutureBuilder<List<TransferHistoryEntry>>(
        future: _historyFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          final entries = snapshot.data ?? const <TransferHistoryEntry>[];
          if (entries.isEmpty) {
            return const Center(
              child: Text('No received files yet.'),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: entries.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final entry = entries[index];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.insert_drive_file_outlined),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              entry.fileName,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Open file',
                            onPressed: () => _openFile(entry),
                            icon: const Icon(Icons.open_in_new),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text('From: ${entry.peerName} (${entry.peerIp})'),
                      const SizedBox(height: 4),
                      Text('Size: ${_formatSize(entry.sizeBytes)}'),
                      const SizedBox(height: 4),
                      Text('Received: ${entry.receivedAt.toLocal()}'),
                      const SizedBox(height: 4),
                      Text(
                        'Saved to: ${entry.savedPath}',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                          onPressed: () => _openFile(entry),
                          icon: const Icon(Icons.open_in_new),
                          label: const Text('Open'),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
