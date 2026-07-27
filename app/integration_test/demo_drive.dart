// Demo choreography driver — NOT a test (it makes no assertions).
//
// Launches the real app on a booted simulator and performs a paced sequence of
// real taps/drags so the screen can be captured with `xcrun simctl io
// recordVideo`. Footage is silent (recordVideo captures video only); a phase-
// locked harmonium + tanpura track is dubbed under it in post (scripts/).
//
// Shape of the film (Rupak, the user's adapted nagma):
//   [off-camera prep] switch to Rupak, enter the nagma, apply it.
//   [visible, trimmed to here] compose view → play → tempo → tanpura.
//
// The prep runs first so the film can OPEN on the sargam editor showing the
// user's committed nagma cleanly (no typing on camera). scripts/make_demo.sh
// trims the working video to the second editor-open (VIS_MARK below).
//
// Timing: the cycle wheel repaints ~60 Hz and the render spinner animates, so
// pumpAndSettle would hang. Everything holds via `_hold` (pumps frames while real
// wall time passes, Stopwatch-paced) so native playback advances on camera.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:nicenagma/main.dart' as app;

// The user's Bhairavi phrase adapted to Rupak (7 = 3+2+2): opens on the N.,S
// lower-ni gesture, ascends S g m P d, resolves m g r -> S (sam).
const _nagma = 'N.,S g m\nP d,P\nm g,r';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('demo choreography', (tester) async {
    app.main();
    await tester.pump();

    // ---- off-camera prep: Rupak + the user's nagma, committed ----------------
    await _hold(tester, 3.0);
    await _tap(tester, find.text('Teentaal'));          // open taal dialog
    await _hold(tester, 1.0);
    await _tap(tester, find.text('Rupak'));             // → Rupak default nagma
    await _hold(tester, 4.0);
    await _tap(tester, find.byTooltip('Edit lehra'));   // editor (default nagma)
    await _hold(tester, 0.8);
    await tester.enterText(find.byType(TextField), _nagma);
    await _hold(tester, 0.8);
    await _tap(tester, find.widgetWithText(TextButton, 'Apply')); // commit → player
    await _hold(tester, 4.0);

    // ================= VIS_MARK: visible film starts here ======================
    // 1. Compose your own nagma — open the editor onto the committed nagma and
    //    rest on it (swar legend + example). Shown, not typed.
    await _tap(tester, find.byTooltip('Edit lehra'));
    await _hold(tester, 5.0);
    await _tap(tester, find.byTooltip('Back to player'));
    await _hold(tester, 0.8);

    // 2. Play — the Rupak lehra loops; the 7-matra wheel sweeps and returns to sam.
    await _tap(tester, find.widgetWithText(FilledButton, 'Play'));
    await _hold(tester, 7.0);

    // 3. Set the tempo — drag up to drut; the wheel sweeps faster after re-render.
    await _drag(tester, find.byType(Slider).at(0), const Offset(260, 0));
    await _hold(tester, 4.5);

    // 4. Add the tanpura — raise the drone under the lehra (instant, no re-render).
    await _drag(tester, find.byType(Slider).at(2), const Offset(220, 0));
    await _hold(tester, 4.5);

    await _hold(tester, 1.0);
  }, timeout: const Timeout(Duration(minutes: 3)));
}

/// Hold for [seconds] of REAL wall time at ~30 fps, Stopwatch-paced so on-screen
/// duration matches the intended timing while native playback advances.
Future<void> _hold(WidgetTester tester, double seconds) async {
  const int frameMs = 33;
  final int totalMs = (seconds * 1000).round();
  final sw = Stopwatch()..start();
  int next = 0;
  while (sw.elapsedMilliseconds < totalMs) {
    await tester.pump(const Duration(milliseconds: frameMs));
    next += frameMs;
    final int behind = next - sw.elapsedMilliseconds;
    if (behind > 0) {
      await tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: behind)));
    }
  }
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder.first);
  await _hold(tester, 0.5);
}

Future<void> _drag(WidgetTester tester, Finder finder, Offset offset) async {
  await tester.drag(finder.first, offset);
  await _hold(tester, 0.5);
}
