import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../models/connection_request.dart';
import '../../../models/device_model.dart';
import '../../file_transfer/controller/file_transfer_controller.dart';
import '../../file_transfer/presentation/file_transfer_screen.dart';
import '../../history/presentation/history_screen.dart';
import '../controller/discovery_controller.dart';

class DiscoveryScreen extends StatelessWidget {
  const DiscoveryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => DiscoveryController()..init(),
      child: const _DiscoveryView(),
    );
  }
}

class _DiscoveryView extends StatefulWidget {
  const _DiscoveryView();

  @override
  State<_DiscoveryView> createState() => _DiscoveryViewState();
}

class _DiscoveryViewState extends State<_DiscoveryView> {
  final _ipController = TextEditingController();

  StreamSubscription<ConnectionRequest>? _connectionSubscription;
  String? _pendingRequestDeviceId;
  bool _connecting = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_connectionSubscription != null) return;

    final fileTransferController =
        context.read<FileTransferController>();
    _connectionSubscription = fileTransferController
        .onConnectionRequest
        .listen(_showIncomingRequest);
  }

  void _showIncomingRequest(ConnectionRequest request) {
    if (!mounted) return;

    final fileTransferController = context.read<FileTransferController>();

    // A user must leave the current transfer screen before a new connection
    // request can be accepted. This prevents stacked sessions and ensures a
    // reconnect always starts with an empty transfer list.
    if (fileTransferController.hasTransferScreenOpen) {
      request.respond(false);
      return;
    }

    if (_pendingRequestDeviceId == request.device.id) return;
    _pendingRequestDeviceId = request.device.id;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        request.respond(false);
        return;
      }

      BuildContext? dialogContext;
      final autoDismiss = Timer(
        AppConstants.connectionRequestTimeout,
        () {
          if (dialogContext != null) {
            Navigator.of(dialogContext!).pop(false);
          }
        },
      );

      final accepted = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          dialogContext = ctx;
          return AlertDialog(
            title: const Text('Connection request'),
            content: Text(
              '${request.device.name} (${request.device.ip}) wants to connect.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Decline'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Accept'),
              ),
            ],
          );
        },
      );
      autoDismiss.cancel();

      request.respond(accepted ?? false);

      if (!mounted) return;

      if (accepted == true) {
        fileTransferController.enterTransferScreen(request.device.id);
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => FileTransferScreen(device: request.device),
          ),
        );
      }

      if (mounted && _pendingRequestDeviceId == request.device.id) {
        _pendingRequestDeviceId = null;
      }
    });
  }

  Future<void> _connectTo(
    BuildContext context,
    DeviceModel device,
  ) async {
    if (_connecting) return;

    final fileTransferController = context.read<FileTransferController>();
    if (fileTransferController.hasTransferScreenOpen) return;

    setState(() => _connecting = true);

    final result = await fileTransferController.requestConnection(device.ip);

    if (!mounted) return;
    setState(() => _connecting = false);

    final displayName = device.name.isEmpty ? device.ip : device.name;

    switch (result.status) {
      case ConnectionRequestStatus.declined:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$displayName declined the connection.')),
        );
        return;
      case ConnectionRequestStatus.unreachable:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Couldn't reach $displayName. Make sure both devices are on "
              'the same network/hotspot. On Windows, also check Windows '
              'Defender Firewall allows this app on Private/Public networks.',
            ),
            duration: const Duration(seconds: 8),
          ),
        );
        return;
      case ConnectionRequestStatus.accepted:
        final confirmed = result.device!;
        final resolvedDevice = DeviceModel(
          id: confirmed.id,
          name: confirmed.name,
          platform: confirmed.platform,
          ip: device.ip,
          port: confirmed.port,
          lastSeen: DateTime.now(),
        );

        fileTransferController.enterTransferScreen(resolvedDevice.id);

        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => FileTransferScreen(device: resolvedDevice),
          ),
        );
    }
  }

  void _connectManually(
    BuildContext context,
    DiscoveryController controller,
  ) {
    final ip = controller.validateManualIp(_ipController.text);
    if (ip == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid IPv4 address.')),
      );
      return;
    }

    _connectTo(
      context,
      DeviceModel(
        id: 'manual:$ip',
        name: '',
        platform: 'unknown',
        ip: ip,
        port: 0,
        lastSeen: DateTime.now(),
      ),
    );
  }

  @override
  void dispose() {
    _connectionSubscription?.cancel();
    _ipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<DiscoveryController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('KnightSync'),
        actions: [
          IconButton(
            tooltip: 'History',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const HistoryScreen(),
                ),
              );
            },
            icon: const Icon(Icons.history),
          ),
        ],
      ),
      body: !controller.isReady
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Device: ${controller.selfName}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Your IP: ${controller.selfIp ?? 'unknown'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        controller.devices.isEmpty
                            ? Icons.search
                            : Icons.check_circle,
                        size: 16,
                        color: controller.devices.isEmpty
                            ? Colors.orange
                            : Colors.green,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        controller.devices.isEmpty
                            ? 'Searching devices...'
                            : '${controller.devices.length} device(s) found',
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Devices on the same Wi-Fi/hotspot should appear automatically. '
                    'You can also enter the other device IP below.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _ipController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Partner IP (manual fallback)',
                            hintText: 'Example: 192.168.43.1',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _connecting
                            ? null
                            : () => _connectManually(context, controller),
                        child: _connecting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Connect'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Expanded(
                    child: controller.devices.isEmpty
                        ? const Center(
                            child: Text(
                              'Waiting for devices on the same network...',
                            ),
                          )
                        : ListView.builder(
                            itemCount: controller.devices.length,
                            itemBuilder: (context, index) {
                              final device = controller.devices[index];
                              return Card(
                                child: ListTile(
                                  leading: Icon(
                                    device.platform == 'android'
                                        ? Icons.phone_android
                                        : Icons.desktop_windows,
                                  ),
                                  title: Text(device.name),
                                  subtitle: Text(
                                    '${device.ip} • ${device.platform}',
                                  ),
                                  trailing: FilledButton(
                                    onPressed: _connecting
                                        ? null
                                        : () => _connectTo(context, device),
                                    child: const Text('Connect'),
                                  ),
                                ),
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
