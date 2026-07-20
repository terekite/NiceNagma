// Widget tests for the nagma editor's "tap-outside applies" behavior.
//
// Tapping outside the text field dismisses focus and applies the draft *in
// place* (stays on the editor), reusing the same `setNagma` path as the Apply
// button — which instead returns to the player on success. A recording fake
// LoopRenderer captures each RenderRequest; the loop_player MethodChannel is
// mocked so the re-render + buffer swap never touch a real platform channel.
// The tanpura re-render (fired by setNagma) fails silently in tests — its
// path_provider call is unmocked and swallowed by the controller.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nicenagma/screens/nagma_editor_screen.dart';
import 'package:nicenagma/services/loop_player.dart';
import 'package:nicenagma/services/render_client.dart'; // re-exports LoopRenderer, RenderRequest, NagmaRejected
import 'package:nicenagma/state/player_controller.dart';

class _RecordingRenderer implements LoopRenderer {
  final List<RenderRequest> requests = [];
  bool reject = false;
  String rejectMessage = 'invalid swar at 2:3';

  @override
  Future<String> getLoop(RenderRequest req) async {
    requests.add(req);
    if (reject) throw NagmaRejected(rejectMessage);
    return '';
  }

  @override
  Future<bool> healthy() async => true;
}

const _newNagma = 'S R G m\nP - D P\nS R G m\nP - D P';

Future<PlayerController> _pumpEditor(
  WidgetTester tester,
  _RecordingRenderer renderer, {
  required void Function() onClose,
}) async {
  const channel = MethodChannel('nicenagma/loop');
  tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (_) async => null);
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));

  await tester.binding.setSurfaceSize(const Size(800, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final controller =
      PlayerController(client: renderer, player: LoopPlayer());
  addTearDown(controller.dispose);

  await tester.pumpWidget(MaterialApp(
    home: NagmaEditorScreen(controller: controller, onClose: onClose),
  ));
  await tester.pumpAndSettle();
  return controller;
}

// Taps a point outside the text field (the AppBar title), firing onTapOutside.
Future<void> _tapOutside(WidgetTester tester) async {
  await tester.tap(find.text('Edit lehra'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('editing then tapping outside applies the draft and stays on the editor',
      (tester) async {
    final renderer = _RecordingRenderer();
    var closed = false;
    await _pumpEditor(tester, renderer, onClose: () => closed = true);

    await tester.tap(find.byType(TextField)); // focus with a real pointer-down
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), _newNagma);
    await _tapOutside(tester);

    expect(renderer.requests, hasLength(1));
    expect(renderer.requests.single.nagmaText, _newNagma);
    expect(closed, isFalse, reason: 'auto-apply must not return to the player');
    expect(find.text('Edit lehra'), findsOneWidget);
  });

  testWidgets('tapping outside with unchanged text does not re-render',
      (tester) async {
    final renderer = _RecordingRenderer();
    await _pumpEditor(tester, renderer, onClose: () {});

    // Focus the field without changing its text, then tap away.
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await _tapOutside(tester);

    expect(renderer.requests, isEmpty);
  });

  testWidgets('an invalid nagma surfaces inline on auto-apply without thrashing',
      (tester) async {
    final renderer = _RecordingRenderer()..reject = true;
    var closed = false;
    await _pumpEditor(tester, renderer, onClose: () => closed = true);

    await tester.tap(find.byType(TextField)); // focus with a real pointer-down
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'X Y Z');
    await _tapOutside(tester);

    // Parser message shown inline; editor did not close.
    expect(find.text(renderer.rejectMessage), findsOneWidget);
    expect(closed, isFalse);
    expect(renderer.requests, hasLength(1));

    // Refocus and tap away again without editing: the same broken draft is
    // not re-applied (deduped on the last-applied text).
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await _tapOutside(tester);
    expect(renderer.requests, hasLength(1));
  });

  testWidgets('the Apply button applies and returns to the player',
      (tester) async {
    final renderer = _RecordingRenderer();
    var closed = false;
    await _pumpEditor(tester, renderer, onClose: () => closed = true);

    await tester.enterText(find.byType(TextField), _newNagma);
    await tester.tap(find.widgetWithText(TextButton, 'Apply'));
    await tester.pumpAndSettle();

    expect(renderer.requests, hasLength(1));
    expect(renderer.requests.single.nagmaText, _newNagma);
    expect(closed, isTrue, reason: 'Apply returns to the player on success');
  });
}
