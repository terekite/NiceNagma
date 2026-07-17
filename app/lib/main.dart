// App shell. Scaffolding placeholder for the Day-2 player screen (cycle wheel,
// matra counter driven by audio clock, tempo + Sa controls, tanpura mix).

import 'package:flutter/material.dart';

void main() => runApp(const NiceNagmaApp());

class NiceNagmaApp extends StatelessWidget {
  const NiceNagmaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NiceNagma',
      theme: ThemeData(colorSchemeSeed: Colors.deepOrange, useMaterial3: true),
      home: const _PlayerPlaceholder(),
    );
  }
}

class _PlayerPlaceholder extends StatelessWidget {
  const _PlayerPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('NiceNagma')),
      body: const Center(
        child: Text(
          'Player screen — Day 2.\nDefaults: Bhairavi, D Sa, 80 BPM.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
