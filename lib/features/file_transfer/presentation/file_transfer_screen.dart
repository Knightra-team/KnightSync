import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:provider/provider.dart';

import '../../../models/device_model.dart';
import '../../session/models/peer_session_event.dart';
import '../controller/file_transfer_controller.dart';
import '../models/transfer_task.dart';

class FileTransferScreen extends StatefulWidget {
  const FileTransferScreen({
    super.key,
    required this.device,
  });

  final DeviceModel device;

  @override
  State<FileTransferScreen> createState() => _FileTransferScreenState();
}

class _FileTransferScreenState extends State<FileTransferScreen> {
  late final FileTransferController _controller;
  StreamSubscription<PeerSessionEvent>? _sessionSubscription;
  bool _openingSession = true;
  bool _connectionDialogShowing = false;

  @override
  void initState() {
    super.initState();

    _controller = context.read<FileTransferController>();

    _sessionSubscription = _controller.onSessionEvent.listen(
      _handleSessionEvent,
    );

    // Register the route after the current build/mount cycle. The controller
    // uses this flag to reject a second incoming connection while this screen
    // is open; scheduling it avoids mutating Provider state during build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _controller.enterTransferScreen(widget.device.id);
      unawaited(_openSession());
    });
  }

  Future<void> _openSession() async {
    final connected = await _controller.openSession(widget.device);
    if (!mounted) return;

    setState(() => _openingSession = false);

    if (!connected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The connection session could not be established. Try reconnecting.',
          ),
        ),
      );
    }
  }

  void _handleSessionEvent(PeerSessionEvent event) {
    if (!mounted || event.device.id != widget.device.id) return;

    if (event.type == PeerSessionEventType.peerLeft ||
        event.type == PeerSessionEventType.disconnected) {
      _showPeerLeftDialog(event.device);
    }
  }

  Future<void> _showPeerLeftDialog(DeviceModel device) async {
    if (!mounted || _connectionDialogShowing) return;
    _connectionDialogShowing = true;

    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) {
      _connectionDialogShowing = false;
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Connection ended'),
        content: Text(
          '${device.name} has left the connection. You can no longer send files. '
          'Go back and reconnect to start a new session.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );

    _connectionDialogShowing = false;
  }

  Future<bool> _confirmExit() async {
    final connected = _controller.isSessionConnected(widget.device.id);

    if (!connected) {
      return true;
    }

    final shouldLeave = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Leave connection?'),
            content: const Text(
              'Leaving this page will disconnect both devices. '
              'The other device will be notified and file sending will stop.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Stay'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Leave'),
              ),
            ],
          ),
        ) ??
        false;

    if (!shouldLeave) return false;

    await _controller.disconnectSession(widget.device);
    return true;
  }

  Future<void> _openFile(String? path) async {
    if (path == null || path.isEmpty) return;

    if (!await File(path).exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The file is no longer available.')),
      );
      return;
    }

    final result = await OpenFile.open(path);
    if (!mounted || result.type == ResultType.done) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message)),
    );
  }

  @override
  void dispose() {
    _sessionSubscription?.cancel();
    // Do not access Provider through context here. During dispose the
    // element may already be deactivated, so looking up an inherited
    // provider is unsafe. Use the controller reference captured in initState.
    _controller.leaveTransferScreen(widget.device.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<FileTransferController>();
    final isConnected = controller.isSessionConnected(widget.device.id);

    return WillPopScope(
      onWillPop: _confirmExit,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.device.name),
          actions: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isConnected
                        ? Icons.link
                        : Icons.link_off,
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isConnected ? 'Connected' : 'Disconnected',
                  ),
                ],
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: !isConnected || _openingSession
              ? null
              : () => controller.pickAndSendFile(widget.device),
          icon: const Icon(Icons.upload_file),
          label: const Text('Send file'),
        ),
        body: Column(
          children: [
            if (_openingSession)
              const LinearProgressIndicator(minHeight: 2),
            if (!isConnected && !_openingSession)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest,
                ),
                child: const Row(
                  children: [
                    Icon(Icons.link_off),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'This session has ended. Go back and reconnect to send files again.',
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: controller.tasks.isEmpty
                  ? const Center(
                      child: Text(
                        'No transfers in this session yet — tap "Send file" to start.',
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 80),
                      itemCount: controller.tasks.length,
                      itemBuilder: (context, index) {
                        return _TransferTile(
                          task: controller.tasks[index],
                          onOpen: _openFile,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TransferTile extends StatelessWidget {
  const _TransferTile({
    required this.task,
    required this.onOpen,
  });

  final TransferTask task;
  final Future<void> Function(String? path) onOpen;

  @override
  Widget build(BuildContext context) {
    final isIncoming = task.direction == TransferDirection.incoming;
    final isCompleted = task.status == TransferStatus.completed;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: ListTile(
          leading: Icon(
            isIncoming ? Icons.download : Icons.upload,
          ),
          title: Text(
            task.fileName,
            overflow: TextOverflow.ellipsis,
          ),
          isThreeLine: true,
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${isIncoming ? 'From' : 'To'} ${task.peerName} (${task.peerIp})',
              ),
              const SizedBox(height: 6),
              if (task.status == TransferStatus.inProgress)
                LinearProgressIndicator(value: task.progress)
              else
                Text(
                  isCompleted
                      ? isIncoming
                          ? 'Received successfully'
                          : 'Sent successfully — receiver confirmed the file'
                      : 'Failed: ${task.errorMessage ?? 'unknown error'}',
                  style: TextStyle(
                    color: isCompleted ? Colors.green : Colors.red,
                  ),
                ),
              if (isIncoming && isCompleted && task.savedPath != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Saved to: ${task.savedPath}',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () => onOpen(task.savedPath),
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Open'),
                  ),
                ),
              ],
            ],
          ),
          trailing: task.status == TransferStatus.inProgress
              ? Text('${(task.progress * 100).toStringAsFixed(0)}%')
              : null,
        ),
      ),
    );
  }
}
