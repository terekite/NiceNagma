// Widget tests for the swipeable PlayerShell. Uses a fake LoopRenderer so nothing
// touches the render service or native player — the controller is never init()'d,
// so no platform channels are exercised.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nicenagma/screens/player_shell.dart';
import 'package:nicenagma/services/loop_player.dart';
import 'package:nicenagma/services/render_client.dart'; // re-exports LoopRenderer, RenderRequest
import 'package:nicenagma/state/player_controller.dart';

class _FakeRenderer implements LoopRenderer {
  @override
  Future<String> getLoop(RenderRequest req) async => '';
  @override
  Future<bool> healthy() async => true;
}

PlayerController _makeController() =>
    PlayerController(client: _FakeRenderer(), player: LoopPlayer());

Widget _shell(PlayerController c) => MaterialApp(home: PlayerShell(controller: c));

void main() {
  testWidgets('edit button navigates to the editor and back returns to player',
      (tester) async {
    final controller = _makeController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(_shell(controller));
    await tester.pumpAndSettle();

    // Starts on the player page; the editor page isn't built yet.
    expect(find.text('NiceNagma'), findsOneWidget);
    expect(find.text('Edit lehra'), findsNothing);

    // Top-right edit button animates the PageView to the editor page.
    await tester.tap(find.byIcon(Icons.edit_note));
    await tester.pumpAndSettle();
    expect(find.text('Edit lehra'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back), findsOneWidget); // embedded back affordance

    // The embedded back arrow returns to the player page.
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('NiceNagma'), findsOneWidget);
    expect(find.byIcon(Icons.edit_note), findsOneWidget);
  });

  testWidgets('an unapplied editor draft survives leaving and returning',
      (tester) async {
    final controller = _makeController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(_shell(controller));
    await tester.pumpAndSettle();

    // Go to the editor and type a draft without hitting Apply.
    await tester.tap(find.byIcon(Icons.edit_note));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'DRAFT S R G m');
    await tester.pumpAndSettle();

    // Leave to the player, then come back to the editor.
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.edit_note));
    await tester.pumpAndSettle();

    // The kept-alive editor state preserved the unapplied text.
    expect(find.text('DRAFT S R G m'), findsOneWidget);
  });
}
