// Mirrors core/tests/test_compiler.py.

import 'package:flutter_test/flutter_test.dart';
import 'package:nicenagma/render/compiler.dart';
import 'package:nicenagma/render/models.dart';
import 'package:nicenagma/render/parser.dart';
import 'package:nicenagma/render/performance.dart' as perf;

const stock = 'S r g m | P d P m | g m P d | P m g r';

NagmaDoc doc() => parseNagma(stock);

void main() {
  group('loop length is exact', () {
    final cases = [
      [80.0, 4, 44100],
      [120.0, 8, 44100],
      [137.0, 4, 48000], // non-divisor bpm
      [60.0, 1, 44100],
    ];
    for (final c in cases) {
      final bpm = c[0] as double;
      final avartans = c[1] as int;
      final sr = c[2] as int;
      test('bpm=$bpm avartans=$avartans sr=$sr', () {
        final score = compileScore(doc(),
            bpm: bpm, sa: 'D', avartans: avartans, sampleRate: sr);
        expect(score.matraDurS, 60.0 / bpm);
        expect(score.avartanDurS, 16 * (60.0 / bpm));
        expect(score.loopLengthS, avartans * 16 * (60.0 / bpm));
        expect(score.loopLengthSamples, (score.loopLengthS * sr).round());
      });
    }
  });

  test('sam onsets are exact, no jitter', () {
    const bpm = 137.0, avartans = 4; // non-divisor bpm stresses exactness
    final score = compileScore(doc(), bpm: bpm, sa: 'D', avartans: avartans, seed: 99);
    final sam = score.events.where((e) => e.matra == 0 && e.structural).toList();
    expect(sam.length, avartans);
    for (final e in sam) {
      expect(e.startS, closeTo(e.avartan * score.avartanDurS, 1e-9));
    }
  });

  test('all matra boundaries exact', () {
    final score = compileScore(doc(), bpm: 93, sa: 'C#', avartans: 2, seed: 7);
    final md = score.matraDurS;
    for (final e in score.events) {
      if (e.structural) {
        final expected = e.avartan * score.avartanDurS + e.matra * md;
        expect(e.startS, closeTo(expected, 1e-9));
      }
    }
  });

  test('per-avartan variation differs', () {
    final score = compileScore(doc(), bpm: 100, sa: 'D', avartans: 4, seed: 42);
    final byAv = <int, List<int>>{};
    for (final e in score.events) {
      byAv.putIfAbsent(e.avartan, () => []).add(e.velocity);
    }
    expect(byAv[0], isNot(equals(byAv[1])));
  });

  test('transposition changes pitch not timing', () {
    final d = compileScore(doc(), bpm: 100, sa: 'D', avartans: 1);
    final cs = compileScore(doc(), bpm: 100, sa: 'C#', avartans: 1);
    expect(d.events.length, cs.events.length);
    for (var i = 0; i < d.events.length; i++) {
      expect(d.events[i].midi - cs.events[i].midi, 1);
      expect(d.events[i].startS, cs.events[i].startS);
    }
  });

  test('repeated pitch rearticulates, not tied', () {
    final doc = parseNagma("S S S S | P m g r | P d n S' | n d P m");
    final score = compileScore(doc, bpm: 90, sa: 'C', avartans: 1);
    final sa = (score.events.toList()..sort((a, b) => a.startS.compareTo(b.startS)))
        .where((e) => e.midi == score.saMidi && e.matra < 4)
        .toList();
    expect(sa.length, 4);
    for (var i = 0; i + 1 < sa.length; i++) {
      final gap = sa[i + 1].startS - (sa[i].startS + sa[i].durS);
      expect(gap, greaterThanOrEqualTo(perf.rearticulationGapS - 1e-6));
    }
  });

  test('distinct pitches keep legato overlap', () {
    final doc = parseNagma("S r g m | P m g r | P d n S' | n d P m");
    final score = compileScore(doc, bpm: 90, sa: 'C', avartans: 1);
    final evs = (score.events.where((e) => e.avartan == 0).toList()
      ..sort((a, b) => a.startS.compareTo(b.startS)));
    final a = evs[0], b = evs[1]; // S then r — distinct pitches
    expect(a.startS + a.durS, greaterThan(b.startS));
  });

  test('swell set and scales with duration', () {
    final doc = parseNagma("S R g m,P | P m g r | P d n S' | n d P m");
    final score = compileScore(doc, bpm: 70, sa: 'C', avartans: 1, seed: 1);
    for (final e in score.events) {
      expect(e.swell, inInclusiveRange(0.0, 0.5));
    }
    final full = score.events.where((e) => e.matra == 0).toList();
    final split = score.events.where((e) => e.matra == 3).toList();
    expect(split.length, 2);
    final fullAvg = full.map((e) => e.swell).reduce((a, b) => a + b) / full.length;
    final splitAvg = split.map((e) => e.swell).reduce((a, b) => a + b) / split.length;
    expect(fullAvg, greaterThan(splitAvg));
  });

  test('grace notes ornament without disturbing the grid', () {
    final doc = parseNagma(stock);
    final score = compileScore(doc, bpm: 70, sa: 'C', avartans: 4, seed: 42);
    final pitchSet =
        (score.events.where((e) => e.structural).map((e) => e.midi).toSet());
    final graces = score.events
        .where((e) => !e.structural && e.swell == 0.0 && e.durS < 0.12)
        .toList();
    expect(graces, isNotEmpty, reason: 'expected some kan grace notes');
    for (final g in graces) {
      expect(g.structural, isFalse);
      expect(pitchSet.contains(g.midi), isTrue);
    }
    final md = score.matraDurS;
    for (final e in score.events) {
      if (e.structural) {
        final expected = e.avartan * score.avartanDurS + e.matra * md;
        expect(e.startS, closeTo(expected, 1e-9));
      }
    }
  });

  test('wrong matra count rejected', () {
    final d = parseNagma(stock);
    final trimmed = NagmaDoc(taal: d.taal, matras: d.matras.sublist(0, 15));
    expect(() => compileScore(trimmed, bpm: 80, sa: 'D'),
        throwsA(predicate((e) => e.toString().contains('requires 16'))));
  });

  // --- Non-teentaal taals compile with the right length and exact boundaries.

  group('non-teentaal loop length and boundaries', () {
    final cases = [
      ['S r g | m g r', 'dadra', 6],
      ['S g m | P m | g r', 'rupak', 7],
      ['S r | g m P | d P | m g r', 'jhaptaal', 10],
      ["S r\ng m\nP d\nn S'\nd P\nm g", 'ektaal', 12],
      ['S r g m P\nd P\nm g r\nS r g m', 'dhamar', 14],
      ['S r g\nm P m g\nr S r g\nm P d n', 'pancham_sawari', 15],
    ];
    for (final c in cases) {
      final text = c[0] as String;
      final taal = c[1] as String;
      final matraCount = c[2] as int;
      test(taal, () {
        final doc = parseNagma(text, taal: taal);
        final score = compileScore(doc, bpm: 95, sa: 'D', avartans: 3, seed: 5);
        expect(score.matraCount, matraCount);
        expect(score.avartanDurS, closeTo(matraCount * (60.0 / 95), 1e-9));
        expect(score.loopLengthSamples,
            (score.loopLengthS * score.sampleRate).round());
        final md = score.matraDurS;
        for (final e in score.events) {
          if (e.structural) {
            final expected = e.avartan * score.avartanDurS + e.matra * md;
            expect(e.startS, closeTo(expected, 1e-9));
          }
        }
      });
    }
  });

  test('post-khaali dip follows actual khaali, not midpoint (ektaal)', () {
    // Ektaal khaali at matras 2 and 6; the dip lands on matras 3 and 7.
    final marks = ['sam', 'plain', 'khaali', 'plain', 'taali', 'plain',
        'khaali', 'plain', 'taali', 'plain', 'taali', 'plain'];
    final v3 = perf.baseVelocity(3, marks[3], 12, marks);
    final v5 = perf.baseVelocity(5, marks[5], 12, marks);
    expect(v3, lessThan(v5));
    final v7 = perf.baseVelocity(7, marks[7], 12, marks);
    final v9 = perf.baseVelocity(9, marks[9], 12, marks);
    expect(v7, lessThan(v9));
  });
}
