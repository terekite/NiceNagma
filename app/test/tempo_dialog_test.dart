// Widget regression test for the tap-to-enter tempo dialog.
//
// The dialog owns a TextEditingController. An earlier version disposed it
// synchronously right after `await showDialog`, which races the dialog's exit
// transition — the TextField rebuilds one more frame against the disposed
// controller and throws "A TextEditingController was used after being disposed."
// It crashed most visibly on *invalid* input (Set closes the dialog without
// changing the tempo). These tests drive that exact path — including the dismiss
// transition, pumped frame by frame — and assert no exception escapes.
//
// Uses a fake LoopRenderer and mocks the loop_player MethodChannel so the
// debounced re-render (fired when a valid tempo is applied) doesn't hit a real
// platform channel.

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

// Pumps the screen in a viewport tall enough that the BPM chip (low in the
// control column) is on-screen and tappable. Swallows loop_player channel calls
// so the debounced re-render can't throw. Resets state on teardown.
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

// Opens the dialog by tapping the BPM chip, types [input], and taps [action].
Future<void> _openTypeAndTap(
    WidgetTester tester, String input, String action) async {
  await tester.tap(find.ancestor(
    of: find.text('${Config.defaultBpm.round()} BPM'),
    matching: find.byType(InkWell),
  ));
  await tester.pumpAndSettle();
  expect(find.text('Set tempo'), findsOneWidget);

  await tester.enterText(find.byType(TextField), input);
  await tester.tap(
      find.widgetWithText(action == 'Set' ? FilledButton : TextButton, action));
  await _pumpDismiss(tester);
}

void main() {
  testWidgets('invalid input then Set dismisses without crashing', (tester) async {
    final controller = _makeController();
    addTearDown(controller.dispose);

    await _pumpScreen(tester, controller);
    await _openTypeAndTap(tester, 'abc', 'Set');

    expect(tester.takeException(), isNull);
    expect(find.text('Set tempo'), findsNothing); // dialog gone
    expect(controller.bpm, Config.defaultBpm); // invalid input ignored
  });

  testWidgets('valid input then Set applies the tempo and dismisses cleanly',
      (tester) async {
    final controller = _makeController();
    addTearDown(controller.dispose);

    await _pumpScreen(tester, controller);
    await _openTypeAndTap(tester, '123', 'Set');

    expect(tester.takeException(), isNull);
    expect(find.text('Set tempo'), findsNothing);
    expect(controller.bpm, 123);
  });

  testWidgets('Cancel dismisses without crashing or changing tempo',
      (tester) async {
    final controller = _makeController();
    addTearDown(controller.dispose);

    await _pumpScreen(tester, controller);
    await _openTypeAndTap(tester, '200', 'Cancel');

    expect(tester.takeException(), isNull);
    expect(find.text('Set tempo'), findsNothing);
    expect(controller.bpm, Config.defaultBpm); // Cancel never commits
  });
}
