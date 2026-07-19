// App shell. Owns the single PlayerController, kicks off the startup render, and
// shows the player screen. Stage 1 (plays the default lehra), Stage 2 (tempo/Sa
// re-render), and Stage 3 (editor + tanpura) are all wired here through the one
// controller.

import 'package:flutter/material.dart';

import 'state/player_controller.dart';
import 'screens/player_shell.dart';

void main() => runApp(const NiceNagmaApp());

class NiceNagmaApp extends StatefulWidget {
  const NiceNagmaApp({super.key});

  @override
  State<NiceNagmaApp> createState() => _NiceNagmaAppState();
}

class _NiceNagmaAppState extends State<NiceNagmaApp> {
  final PlayerController _controller = PlayerController();

  @override
  void initState() {
    super.initState();
    // Fire-and-forget: the controller flips `rendering`/`serviceHealthy` and the
    // UI reacts. No await here so the first frame paints immediately.
    _controller.init();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NiceNagma',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.deepOrange,
        brightness: Brightness.light,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.deepOrange,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: PlayerShell(controller: _controller),
    );
  }
}
