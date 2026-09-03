import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'features/discovery/presentation/discovery_screen.dart';
import 'features/file_transfer/controller/file_transfer_controller.dart';
import 'services/local_device_service.dart';

void main() {
  runApp(const KnightRaSyncApp());
}

class KnightRaSyncApp extends StatelessWidget {
  const KnightRaSyncApp({super.key});

  @override
  Widget build(BuildContext context) {
    // The provider MUST live above MaterialApp, not around a single
    // screen. Every route pushed via Navigator (DiscoveryScreen,
    // FileTransferScreen, ...) is its own subtree next to the Navigator,
    // not a descendant of whichever screen pushed it — so a provider
    // placed inside one screen is invisible to routes pushed after it.
    // Putting it here, above MaterialApp/Navigator entirely, means every
    // route can see it.
    return ChangeNotifierProvider(
      create: (_) => FileTransferController(),
      child: const _App(),
    );
  }
}

class _App extends StatefulWidget {
  const _App();

  @override
  State<_App> createState() => _AppState();
}

class _AppState extends State<_App> {
  late final Future<void> _initFuture;

  @override
  void initState() {
    super.initState();
    _initFuture = _init();
  }

  /// Starts the file-transfer server once, before any screen is shown,
  /// so this device can receive files even if the user never opens the
  /// transfer screen themselves.
  Future<void> _init() async {
    final selfId = await LocalDeviceService.getOrCreateDeviceId();
    final selfName = await LocalDeviceService.getDeviceName();
    if (!mounted) return;
    await context.read<FileTransferController>().init(
          selfId: selfId,
          selfName: selfName,
        );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KnightSync',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
      ),
      home: FutureBuilder<void>(
        future: _initFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          return const DiscoveryScreen();
        },
      ),
    );
  }
}
