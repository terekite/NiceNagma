// Locks in the sitar wiring: it is exposed as a selectable bundled instrument and
// threads through RenderRequest.instrument (distinct cache key + serialization) so
// the render seam picks up sitar.sf2. Pure logic — no device/platform channels.

import 'package:flutter_test/flutter_test.dart';
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
}
