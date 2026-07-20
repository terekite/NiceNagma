// Widget tests for the tap-to-pick Sa (key) dialog.
//
// The Sa chip in the laya readout is tappable: it opens an AlertDialog with the
// 12 keys as a ChoiceChip grid (current Sa pre-selected). Tapping a key routes
// through controller.setSa and pops; Cancel dismisses without change. This is
// the ONLY way to change Sa — the old always-visible ChoiceChip row was removed.
//
// Mirrors tempo_dialog_test.dart: a fake LoopRenderer and a mocked loop_player
// MethodChannel so the debounced re-render (fired when Sa changes) never hits a
// real platform channel. The dismiss transition is pumped frame by frame and no
// exception may escape.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nicenagma/config.dart';
import 'package:nicenagma/screens/player_screen.dart';
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

Widget _screen(PlayerController c) => MaterialApp(home: PlayerScreen(controller: c));

// Pumps the screen in a viewport tall/wide enough that the Sa chip in the readout
// row is on-screen and tappable. Swallows loop_player channel calls so the
// debounced re-render can't throw. Resets state on teardown.
Future<void> _pumpScreen(WidgetTester tester, PlayerController c) async {
  const channel = MethodChannel('nicenagma/loop');
  tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (_) async => null);
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));

  await tester.binding.setSurfaceSize(const Size(1200, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(_screen(c));
  await tester.pumpAndSettle();
}

// Advances 1s in 50ms steps: renders the dialog dismiss transition frame by
// frame (the crash window) and fires the 350ms re-render debounce.
Future<void> _pumpDismiss(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

// Opens the dialog by tapping the Sa chip (label 'Sa <key>') in the readout row.
Future<void> _openSaDialog(WidgetTester tester, PlayerController c) async {
  await tester.tap(find.ancestor(
    of: find.text('Sa ${c.sa}'),
    matching: find.byType(InkWell),
  ));
  await tester.pumpAndSettle();
  expect(find.text('Set Sa (key)'), findsOneWidget);
}

void main() {
  testWidgets('the always-visible Sa key ChoiceChip row is gone', (tester) async {
    final controller = _makeController();
    addTearDown(controller.dispose);

    await _pumpScreen(tester, controller);

    // The old row rendered a 'Sa (key)' label next to every key chip. With the
    // row removed, nothing shows the keys until the dialog is opened.
    expect(find.text('Sa (key)'), findsNothing);
    expect(find.widgetWithText(ChoiceChip, 'C#'), findsNothing);
  });

  testWidgets('tapping a key applies the Sa and dismisses cleanly', (tester) async {
    final controller = _makeController();
    addTearDown(controller.dispose);
    expect(controller.sa, Config.defaultSa); // 'D'

    await _pumpScreen(tester, controller);
    await _openSaDialog(tester, controller);

    // Pick a different key from the grid inside the dialog.
    await tester.tap(find.widgetWithText(ChoiceChip, 'F#'));
    await _pumpDismiss(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Set Sa (key)'), findsNothing); // dialog gone
    expect(controller.sa, 'F#');
  });

  testWidgets('Cancel dismisses without crashing or changing Sa', (tester) async {
    final controller = _makeController();
    addTearDown(controller.dispose);

    await _pumpScreen(tester, controller);
    await _openSaDialog(tester, controller);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await _pumpDismiss(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Set Sa (key)'), findsNothing);
    expect(controller.sa, Config.defaultSa); // unchanged
  });
}
