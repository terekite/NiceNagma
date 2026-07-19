// Tanpura sequencer: string pitches, exact loop length, humanized-but-bounded
// timing, per-seed determinism, and per-cycle reseeding.

import 'package:flutter_test/flutter_test.dart';
import 'package:nicenagma/render/sargam.dart' show saToMidi;
import 'package:nicenagma/render/tanpura.dart';

void main() {
  const sr = 44100;
  const T = 4.0;
  const cycles = 6;

  test('C# tanpura maps to the sample roots exactly (zero pitch shift)', () {
    // Sa=C# -> saT=C#3(49), so Pa=G#2(44), kharaj=C#2(37): the SF2 roots.
    final s = tanpuraScore(saMidi: saToMidi('C#'), firstStringSwar: 'P');
    expect(s.events[0].midi, 44); // first string (Pa)
    expect(s.events[1].midi, 49); // Sa
    expect(s.events[2].midi, 49); // Sa
    expect(s.events[3].midi, 37); // kharaj
  });

  test('pitch math: first = saT+off-12, Sa = saT, kharaj = saT-12', () {
    final saMidi = saToMidi('D');
    final saT = tanpuraMidSa(saMidi); // 50 for D
    final s = tanpuraScore(saMidi: saMidi, firstStringSwar: 'm'); // shuddha Ma = +5
    expect(s.events[0].midi, saT + 5 - 12);
    expect(s.events[1].midi, saT);
    expect(s.events[3].midi, saT - 12);
  });

  test('mid-Sa stays near the C#3 sample root for every key (small shift)', () {
    for (final k in ['C', 'C#', 'D', 'E', 'F', 'F#', 'G', 'G#', 'A', 'B']) {
      final saT = tanpuraMidSa(saToMidi(k));
      expect((saT - 49).abs(), lessThanOrEqualTo(6), reason: 'Sa $k shift');
    }
  });

  test('event count and exact loop length', () {
    final s = tanpuraScore(
        saMidi: saToMidi('D'), firstStringSwar: 'P',
        sampleRate: sr, cycleLengthS: T, cycleCount: cycles);
    expect(s.events.length, 4 * cycles);
    expect(s.loopLengthSamples, (cycles * T * sr).round());
  });

  test('internal stroke spacing is identical across every cycle', () {
    final s = tanpuraScore(
        saMidi: saToMidi('D'), firstStringSwar: 'P',
        cycleLengthS: T, cycleCount: cycles);
    // spacings within cycle 0
    final ref = [
      for (var i = 1; i < 4; i++) s.events[i].startS - s.events[i - 1].startS
    ];
    for (var c = 0; c < cycles; c++) {
      for (var i = 1; i < 4; i++) {
        final gap = s.events[c * 4 + i].startS - s.events[c * 4 + i - 1].startS;
        expect(gap, closeTo(ref[i - 1], 1e-9),
            reason: 'cycle $c gap $i differs from the fixed phrase');
      }
    }
  });

  test('phrases start at different times (human drift, not a grid)', () {
    final s = tanpuraScore(
        saMidi: saToMidi('D'), firstStringSwar: 'P',
        cycleLengthS: T, cycleCount: cycles);
    // first-stroke offset from the exact cycle grid should vary across cycles
    final offsets = [
      for (var c = 0; c < cycles; c++) s.events[c * 4].startS - c * T
    ];
    expect(offsets.toSet().length, greaterThan(1));
  });

  test('deterministic for a given seed', () {
    final a = tanpuraScore(saMidi: saToMidi('D'), firstStringSwar: 'P', seed: 7);
    final b = tanpuraScore(saMidi: saToMidi('D'), firstStringSwar: 'P', seed: 7);
    for (var i = 0; i < a.events.length; i++) {
      expect(a.events[i].startS, b.events[i].startS);
      expect(a.events[i].velocity, b.events[i].velocity);
    }
  });

  test('cycles are reseeded (adjacent cycles differ, not rubber-stamped)', () {
    final s = tanpuraScore(saMidi: saToMidi('D'), firstStringSwar: 'P', seed: 1);
    // Relative onsets within cycle 0 vs cycle 1 should not all be identical.
    final c0 = [for (var i = 0; i < 4; i++) s.events[i].startS - 0 * T];
    final c1 = [for (var i = 0; i < 4; i++) s.events[4 + i].startS - 1 * T];
    expect(c0, isNot(equals(c1)));
  });
}
