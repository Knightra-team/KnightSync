import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../file_transfer/presentation/file_transfer_screen.dart';
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

  @override
  void dispose() {
    _ipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<DiscoveryController>();

    return Scaffold(
      appBar: AppBar(title: const Text('KnightRaSync')),
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
                        controller.devices.isEmpty ? Icons.search : Icons.check_circle,
                        size: 16,
                        color: controller.devices.isEmpty ? Colors.orange : Colors.green,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        controller.devices.isEmpty
                            ? 'Searching devices...'
                            : '${controller.devices.length} device(s) found',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Fallback for hotspot setups where broadcast doesn't
                  // reach the other device: type its IP directly.
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _ipController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Or enter partner\'s IP (hotspot)',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () => controller.connectManually(_ipController.text),
                        child: const Text('Connect'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Expanded(
                    child: controller.devices.isEmpty
                        ? const Center(child: Text('Waiting for devices on the same network...'))
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
                                  subtitle: Text('${device.ip} • ${device.platform}'),
                                  trailing: FilledButton(
                                    // Pairing/trust step isn't built yet
                                    // (next milestone) — for now, tapping
                                    // Connect goes straight to sending
                                    // files with this device.
                                    onPressed: () => Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => FileTransferScreen(device: device),
                                      ),
                                    ),
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