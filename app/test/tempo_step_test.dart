// Widget tests for the -5 / +5 tempo step buttons that flank the tempo slider.
//
// The buttons drive the same controller.setBpm the slider and tap-to-type dialog
// use, so clamping (Config.minBpm/maxBpm), the laya-label update, and the
// debounced re-render all come for free. These tests assert the step arithmetic
// and that the buttons disable (and never overshoot) at the bounds.
//
// Uses a fake LoopRenderer and mocks the loop_player MethodChannel so the
// debounced re-render (fired when the tempo changes) doesn't hit a real channel.

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

// Pumps the screen in a viewport tall enough that the tempo controls are
// on-screen and tappable. Swallows loop_player channel calls so the debounced
// re-render can't throw. Resets state on teardown.
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

Finder _plusButton() => find.widgetWithIcon(IconButton, Icons.add);
Finder _minusButton() => find.widgetWithIcon(IconButton, Icons.remove);

// A tempo change starts a 350ms debounce Timer (controller._scheduleReRender).
// Drain it (and the ensuing fake re-render) so no Timer is pending at teardown.
Future<void> _drainReRender(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('+ raises tempo by exactly 5', (tester) async {
    final controller = _makeController();
    addTearDown(controller.dispose);

    await _pumpScreen(tester, controller);
    expect(controller.bpm, Config.defaultBpm); // 80

    await tester.tap(_plusButton());
    await _drainReRender(tester);

    expect(controller.bpm, Config.defaultBpm + 5); // 85
    expect(tester.takeException(), isNull);
  });

  testWidgets('- lowers tempo by exactly 5', (tester) async {
    final controller = _makeController();
    addTearDown(controller.dispose);

    await _pumpScreen(tester, controller);

    await tester.tap(_minusButton());
    await _drainReRender(tester);

    expect(controller.bpm, Config.defaultBpm - 5); // 75
    expect(tester.takeException(), isNull);
  });

  testWidgets('+ is disabled and cannot overshoot at maxBpm', (tester) async {
    final controller = _makeController();
    addTearDown(controller.dispose);

    controller.setBpm(Config.maxBpm);
    await _pumpScreen(tester, controller);
    await _drainReRender(tester); // drain the setBpm(maxBpm) debounce
    expect(controller.bpm, Config.maxBpm);

    // Button disabled at the ceiling.
    final plus = tester.widget<IconButton>(_plusButton());
    expect(plus.onPressed, isNull);

    // Even if pressed, setBpm clamps — never exceeds maxBpm.
    await tester.tap(_plusButton(), warnIfMissed: false);
    await _drainReRender(tester);
    expect(controller.bpm, Config.maxBpm);
    expect(tester.takeException(), isNull);
  });

  testWidgets('- is disabled and cannot undershoot at minBpm', (tester) async {
    final controller = _makeController();
    addTearDown(controller.dispose);

    controller.setBpm(Config.minBpm);
    await _pumpScreen(tester, controller);
    await _drainReRender(tester); // drain the setBpm(minBpm) debounce
    expect(controller.bpm, Config.minBpm);

    final minus = tester.widget<IconButton>(_minusButton());
    expect(minus.onPressed, isNull);

    await tester.tap(_minusButton(), warnIfMissed: false);
    await _drainReRender(tester);
    expect(controller.bpm, Config.minBpm);
    expect(tester.takeException(), isNull);
  });
}
