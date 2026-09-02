import 'package:flutter/material.dart';

import 'features/discovery/presentation/discovery_screen.dart';

void main() {
  runApp(const KnightRaSyncApp());
}

class KnightRaSyncApp extends StatelessWidget {
  const KnightRaSyncApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KnightRaSync',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
      ),
      home: const DiscoveryScreen(),
    );
  }
}
