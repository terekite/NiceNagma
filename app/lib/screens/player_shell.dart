// The app shell: hosts the player and the nagma editor as two horizontally
// swipeable pages sharing the single PlayerController. The top-right edit button
// and the editor's Apply/back all drive the same PageController, so the button
// animates to the same page the user could reach by swiping.
//
// Both child screens remain independently usable as standalone routes (their
// onEdit/onClose callbacks are optional); here we always supply them so page
// navigation stays in-shell rather than pushing/popping routes.

import 'package:flutter/material.dart';

import '../state/player_controller.dart';
import 'player_screen.dart';
import 'nagma_editor_screen.dart';

class PlayerShell extends StatefulWidget {
  final PlayerController controller;
  const PlayerShell({super.key, required this.controller});

  @override
  State<PlayerShell> createState() => _PlayerShellState();
}

class _PlayerShellState extends State<PlayerShell> {
  static const _playerPage = 0;
  static const _editorPage = 1;

  final PageController _pc = PageController();

  // Locked while the editor's text field is focused, so a stray horizontal drag
  // can't yank us off the editor or fight the cursor-drag gesture.
  bool _swipeLocked = false;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  void _goToPage(int i) => _pc.animateToPage(
        i,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );

  void _onPageChanged(int i) {
    // Settling back on the player: drop any lingering focus so the keyboard
    // hides and the swipe lock can't get stuck on.
    if (i == _playerPage) FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return PageView(
      controller: _pc,
      physics:
          _swipeLocked ? const NeverScrollableScrollPhysics() : null,
      onPageChanged: _onPageChanged,
      children: [
        PlayerScreen(
          controller: widget.controller,
          onEdit: () => _goToPage(_editorPage),
        ),
        NagmaEditorScreen(
          controller: widget.controller,
          onClose: () => _goToPage(_playerPage),
          onFocusChanged: (focused) {
            if (focused != _swipeLocked) {
              setState(() => _swipeLocked = focused);
            }
          },
        ),
      ],
    );
  }
}
