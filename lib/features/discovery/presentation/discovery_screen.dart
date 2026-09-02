import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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

class _DiscoveryView extends StatelessWidget {
  const _DiscoveryView();

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
                  const SizedBox(height: 24),
                  Expanded(
                    child: controller.devices.isEmpty
                        ? const Center(child: Text('Waiting for devices on the same Wi-Fi...'))
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
                                    // Pairing feature (next milestone) will
                                    // implement what happens here.
                                    onPressed: () {},
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
