// Demo choreography driver — NOT a test (it makes no assertions).
//
// It launches the real app on a booted simulator and performs a paced,
// cinematic sequence of real taps/drags so the screen can be captured with
// `xcrun simctl io <udid> recordVideo`. The rendered footage is silent
// (recordVideo captures video only); a separately rendered harmonium+tanpura
// WAV is laid under it in post, phase-locked to the on-screen sam (beat 1) by
// detecting the cycle-wheel sweep hand — see scripts/make_demo.sh.
//
// Run:  flutter test integration_test/demo_drive.dart -d <sim-udid>
//
// Timing notes:
//  * The cycle wheel repaints ~60 Hz while playing and the "rendering…" spinner
//    animates during a render, so `pumpAndSettle()` would hang. Everything here
//    holds via `_hold`, which pumps frames while letting real wall time pass (so
//    native AVAudioEngine playback + the position stream advance and the wheel
//    sweeps on camera), paced by a real Stopwatch.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:nicenagma/main.dart' as app;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('demo choreography', (tester) async {
    app.main();
    await tester.pump();

    // 1. Boot — let the default lehra (Teentaal, Sa D, 80 BPM) render on device.
    await _hold(tester, 4.0);

    // 2. HERO — Play. A long, stable Teentaal hold so the sweep hand visibly
    //    returns to sam (top) with the harmonium downbeat — the whole point of
    //    "machine-perfect laya". No re-render here, so laya stays locked.
    await _tap(tester, find.widgetWithText(FilledButton, 'Play'));
    await _hold(tester, 14.0);

    // 3. Pick your Sa — transpose to a new key (tempo unchanged → same sweep rate).
    await _tap(tester, find.text('Sa D'));
    await _hold(tester, 1.4);
    await _tap(tester, find.widgetWithText(ChoiceChip, 'F'));
    await _hold(tester, 6.0);

    // 4. Set your tempo — drag up to drut; the wheel sweeps faster after the
    //    quick re-render, sam now every few seconds.
    await _drag(tester, find.byType(Slider).at(0), const Offset(260, 0));
    await _hold(tester, 6.0);

    // 5. Add the tanpura — raise the drone under the lehra (instant, no re-render).
    await _drag(tester, find.byType(Slider).at(2), const Offset(220, 0));
    await _hold(tester, 4.5);

    // 6. Any taal — switch to Jhaptaal (10 matras); the wheel redraws.
    await _tap(tester, find.text('Teentaal'));
    await _hold(tester, 1.4);
    await _tap(tester, find.text('Jhaptaal'));
    await _hold(tester, 6.0);

    // 7. Compose your own — open the sargam editor and rest on it (the pre-filled
    //    nagma, the swar legend, the example). Shown, not used: no typing/apply,
    //    just a calm view that you can input custom nagmas. Then back to the player.
    await _tap(tester, find.byTooltip('Edit lehra'));
    await _hold(tester, 5.5);
    await _tap(tester, find.byTooltip('Back to player'));
    await _hold(tester, 3.5);
  }, timeout: const Timeout(Duration(minutes: 3)));
}

/// Hold for [seconds] of REAL wall time, pumping ~30 fps so the wheel animates
/// live while native playback + the position stream advance. Paced by a real
/// Stopwatch so on-screen duration matches the intended timing exactly.
Future<void> _hold(WidgetTester tester, double seconds) async {
  const int frameMs = 33;
  final int totalMs = (seconds * 1000).round();
  final sw = Stopwatch()..start();
  int nextFrameDeadline = 0;
  while (sw.elapsedMilliseconds < totalMs) {
    await tester.pump(const Duration(milliseconds: frameMs));
    nextFrameDeadline += frameMs;
    final int behind = nextFrameDeadline - sw.elapsedMilliseconds;
    if (behind > 0) {
      await tester.runAsync(
        () => Future<void>.delayed(Duration(milliseconds: behind)),
      );
    }
  }
}

/// Tap [finder] and give the UI a beat to react (dialogs open, state settles).
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder.first);
  await _hold(tester, 0.5);
}

/// Drag [finder] by [offset] with a short settle after.
Future<void> _drag(WidgetTester tester, Finder finder, Offset offset) async {
  await tester.drag(finder.first, offset);
  await _hold(tester, 0.5);
}
