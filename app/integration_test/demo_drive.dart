// Demo choreography driver — NOT a test (it makes no assertions).
//
// It launches the real app on a booted simulator and performs a paced,
// cinematic sequence of real taps/drags so the screen can be captured with
// `xcrun simctl io <udid> recordVideo`. The rendered footage is silent
// (recordVideo captures video only); a separately rendered harmonium+tanpura
// WAV is laid under it in post (see scripts/make_demo.sh).
//
// Run:  flutter test integration_test/demo_drive.dart -d <sim-udid>
//
// Timing notes:
//  * The cycle wheel repaints ~60 Hz while playing and the "rendering…" spinner
//    animates during a render, so `pumpAndSettle()` would hang. Everything here
//    holds via `_hold`, which pumps a frame every ~16 ms while letting real wall
//    time pass (so the native AVAudioEngine playback + position EventChannel
//    actually advance and the wheel sweeps on camera).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:nicenagma/main.dart' as app;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Render every frame to the device as fast as it can — smooth capture.
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('demo choreography', (tester) async {
    app.main();
    await tester.pump();

    // 1. Boot — let the default lehra (Teentaal, Sa D, 80 BPM) render on device.
    //    The wheel shows a brief "rendering…" then settles, ready to play.
    await _hold(tester, 4.5);

    // 2. HERO — Play. Wheel sweep hand rotates, matra counter climbs 1→16,
    //    "avartan 1/4" advances, harmonium loops in machine-perfect laya.
    await _tap(tester, find.widgetWithText(FilledButton, 'Play'));
    await _hold(tester, 9.0);

    // 3. Pick your Sa — tap the Sa chip, choose a new key from the 12-key grid.
    //    The lehra + tanpura re-render, transposed, without a gap.
    await _tap(tester, find.text('Sa D'));
    await _hold(tester, 1.4);
    await _tap(tester, find.widgetWithText(ChoiceChip, 'F'));
    await _hold(tester, 5.0);

    // 4. Set your tempo — drag the Tempo slider up. Laya flips madhya → drut and
    //    the wheel sweeps faster after the quick re-render.
    await _drag(tester, find.byType(Slider).at(0), const Offset(260, 0));
    await _hold(tester, 5.0);

    // 5. Add the tanpura — raise the Tanpura mix slider; the drone fades in
    //    under the lehra (instant, no re-render).
    await _drag(tester, find.byType(Slider).at(2), const Offset(220, 0));
    await _hold(tester, 4.5);

    // 6. Any taal — tap the taal chip, switch to Jhaptaal (10 matras). The wheel
    //    redraws with the new matra count + clap pattern and re-renders.
    await _tap(tester, find.text('Teentaal'));
    await _hold(tester, 1.4);
    await _tap(tester, find.text('Jhaptaal'));
    await _hold(tester, 5.0);

    // 7. Write your own — open the editor, type a new lehra, Apply. It renders
    //    and plays back on return to the player.
    await _tap(tester, find.byTooltip('Edit lehra'));
    await _hold(tester, 1.2);
    // A deliberately simple, always-valid Jhaptaal lehra (4 lines / vibhags).
    await tester.enterText(
      find.byType(TextField),
      'S r\ng m P\nd P\nm g r',
    );
    await _hold(tester, 1.6);
    await _tap(tester, find.widgetWithText(TextButton, 'Apply'));
    await _hold(tester, 6.0);

    // 8. Rest on the playing wheel.
    await _hold(tester, 2.5);
  }, timeout: const Timeout(Duration(minutes: 3)));
}

/// Hold for [seconds] of REAL wall time, pumping frames (~30 fps) so the wheel
/// animates live while native playback + the position stream advance. Paced by a
/// real Stopwatch so the on-screen duration matches the intended timing exactly,
/// independent of per-frame render cost (raw pump/runAsync overhead otherwise
/// stretched it ~3×, making the film far too long/slow).
Future<void> _hold(WidgetTester tester, double seconds) async {
  const int frameMs = 33; // ~30 fps
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
