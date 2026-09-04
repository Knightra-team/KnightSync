import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/device_model.dart';
import '../controller/file_transfer_controller.dart';
import '../models/transfer_task.dart';

class FileTransferScreen
    extends StatelessWidget {
  const FileTransferScreen({
    super.key,
    required this.device,
  });

  final DeviceModel device;

  @override
  Widget build(BuildContext context) {
    final controller =
        context.watch<FileTransferController>();

    return Scaffold(
      appBar: AppBar(
        title: Text(device.name),
      ),
      floatingActionButton:
          FloatingActionButton.extended(
        onPressed: () =>
            controller.pickAndSendFile(
          device,
        ),
        icon: const Icon(
          Icons.upload_file,
        ),
        label: const Text(
          'Send file',
        ),
      ),
      body: controller.tasks.isEmpty
          ? const Center(
              child: Text(
                'No transfers yet — tap '
                '"Send file" to start.',
              ),
            )
          : ListView.builder(
              padding:
                  const EdgeInsets.only(
                bottom: 80,
              ),
              itemCount:
                  controller.tasks.length,
              itemBuilder:
                  (context, index) {
                return _TransferTile(
                  task:
                      controller.tasks[index],
                );
              },
            ),
    );
  }
}

class _TransferTile
    extends StatelessWidget {
  const _TransferTile({
    required this.task,
  });

  final TransferTask task;

  @override
  Widget build(BuildContext context) {
    final isIncoming =
        task.direction ==
            TransferDirection.incoming;

    final isCompleted =
        task.status ==
            TransferStatus.completed;

    return Card(
      margin:
          const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 6,
      ),
      child: ListTile(
        leading: Icon(
          isIncoming
              ? Icons.download
              : Icons.upload,
        ),
        title: Text(
          task.fileName,
          overflow:
              TextOverflow.ellipsis,
        ),
        isThreeLine: true,
        subtitle: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Text(
              '${isIncoming ? 'From' : 'To'} '
              '${task.peerName} '
              '(${task.peerIp})',
            ),

            const SizedBox(height: 6),

            if (task.status ==
                TransferStatus.inProgress)
              LinearProgressIndicator(
                value: task.progress,
              )
            else
              Text(
                isCompleted
                    ? isIncoming
                        ? 'Received successfully'
                        : 'Sent successfully — '
                            'receiver confirmed '
                            'the file'
                    : 'Failed: '
                        '${task.errorMessage ?? 'unknown error'}',
                style: TextStyle(
                  color: isCompleted
                      ? Colors.green
                      : Colors.red,
                ),
              ),

            // ---------------------------------------------------------
            // Show the REAL saved path on Android.
            // ---------------------------------------------------------

            if (isIncoming &&
                isCompleted &&
                task.savedPath != null) ...[
              const SizedBox(height: 4),
              Text(
                'Saved to:',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(
                      fontWeight:
                          FontWeight.bold,
                    ),
              ),
              Text(
                task.savedPath!,
                maxLines: 3,
                overflow:
                    TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall,
              ),
            ],
          ],
        ),
        trailing:
            task.status ==
                    TransferStatus.inProgress
                ? Text(
                    '${(task.progress * 100).toStringAsFixed(0)}%',
                  )
                : null,
      ),
    );
  }
}