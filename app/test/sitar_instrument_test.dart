// Locks in the sitar wiring: it is exposed as a selectable bundled instrument and
// threads through RenderRequest.instrument (distinct cache key + serialization) so
// the render seam picks up sitar.sf2. Pure logic — no device/platform channels.

import 'package:flutter_test/flutter_test.dart';
import 'package:nicenagma/config.dart';
import 'package:nicenagma/render/compiler.dart';
import 'package:nicenagma/render/parser.dart';
import 'package:nicenagma/render/performance.dart' as perf;
import 'package:nicenagma/services/loop_renderer.dart';
import 'package:nicenagma/services/soundfont_provider.dart';

void main() {
  test('sitar is a selectable bundled instrument alongside harmonium', () {
    final names = SoundfontProvider.bundledInstruments.toList();
    expect(names, contains('harmonium'));
    expect(names, contains('sitar'));
  });

  RenderRequest req(String instrument) => RenderRequest(
        nagmaText: 'S R G m | P - D P | S R G m | P - D P',
        bpm: 90,
        sa: 'C',
        instrument: instrument,
      );

  test('instrument is serialized into the render request', () {
    expect(req('sitar').toJson()['instrument'], 'sitar');
  });

  test('choosing sitar yields a different cache key than harmonium', () {
    // Same nagma/bpm/sa — only the instrument differs, so the renderer must not
    // reuse the harmonium loop for a sitar render (and vice versa).
    expect(req('sitar').cacheKey(), isNot(equals(req('harmonium').cacheKey())));
  });

  test('sitar cache key is stable and a 24-char hex digest', () {
    final k = req('sitar').cacheKey();
    expect(k, matches(RegExp(r'^[0-9a-f]{24}$')));
    expect(k, equals(req('sitar').cacheKey()));
  });

  test('sitar is classified as plucked, harmonium is not', () {
    expect(perf.isPlucked('sitar'), isTrue);
    expect(perf.isPlucked('harmonium'), isFalse);
  });

  test('sitar renders no kan-swar grace notes; harmonium does', () {
    // Grace notes are the ONLY seed-dependent difference in event count between
    // the two instruments (jitter/clamping shift timing, never count). So: the
    // sitar count is invariant to seed (no graces), and harmonium exceeds it for
    // at least one seed (graces added). vilambit (60 BPM) => long, grace-eligible
    // notes and the highest grace density.
    final doc = parseNagma(Config.defaultNagma, taal: 'teentaal');
    int sitarCount(int seed) =>
        realize(doc, bpm: 60, sa: 'C', instrument: 'sitar', seed: seed)
            .events
            .length;
    int harmCount(int seed) =>
        realize(doc, bpm: 60, sa: 'C', instrument: 'harmonium', seed: seed)
            .events
            .length;

    final baseline = sitarCount(0);
    var harmoniumEverAddsGraces = false;
    for (var seed = 0; seed < 24; seed++) {
      expect(sitarCount(seed), equals(baseline),
          reason: 'sitar count must not vary with seed (no graces)');
      expect(harmCount(seed) >= baseline, isTrue);
      if (harmCount(seed) > baseline) harmoniumEverAddsGraces = true;
    }
    expect(harmoniumEverAddsGraces, isTrue,
        reason: 'harmonium should add grace notes for at least one seed');
  });
}
