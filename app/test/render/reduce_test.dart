// Mirrors core/tests/test_reduce.py.

import 'package:flutter_test/flutter_test.dart';
import 'package:nicenagma/render/models.dart';
import 'package:nicenagma/render/parser.dart';
import 'package:nicenagma/render/reduce.dart';
import 'package:nicenagma/render/taal.dart';

// Dense vilambit: 4- and 2-slot matras; slot-0 = Bhairavi skeleton.
const vilambit =
    "S,r,g,r r,g g,m,P,m m,P | P,m,g,m m,g g,r r,S | "
    "P,d,n,d d,n n,S' S',n | n,d d,P P,m,g,m m,g";

List<Note> _struck(NagmaDoc doc) =>
    [for (final m in doc.matras) for (final n in m.notes) if (n.kind == 'swar') n];

Set<String> _authoredPitches(NagmaDoc doc) =>
    {for (final n in _struck(doc)) '${n.swar}/${n.octave}'};

void main() {
  test('laya for bpm thresholds', () {
    expect(layaForBpm(60), 'vilambit');
    expect(layaForBpm(85), 'vilambit');
    expect(layaForBpm(86), 'madhya');
    expect(layaForBpm(160), 'madhya');
    expect(layaForBpm(161), 'drut');
    expect(layaForBpm(240), 'drut');
  });

  test('vilambit is identity', () {
    final doc = parseNagma(vilambit);
    final red = reduceDoc(doc, 'vilambit');
    expect([for (final n in _struck(red)) '${n.swar}/${n.octave}'],
        [for (final n in _struck(doc)) '${n.swar}/${n.octave}']);
  });

  test('madhya reduces density and caps at two per matra', () {
    final doc = parseNagma(vilambit);
    final red = reduceDoc(doc, 'madhya');
    expect(_struck(red).length, lessThan(_struck(doc).length));
    for (final m in red.matras) {
      expect(m.notes.where((n) => n.kind == 'swar').length, lessThanOrEqualTo(2));
    }
  });

  test('drut is at most one per matra and sparser than madhya', () {
    final doc = parseNagma(vilambit);
    final madhya = reduceDoc(doc, 'madhya');
    final drut = reduceDoc(doc, 'drut');
    for (final m in drut.matras) {
      expect(m.notes.where((n) => n.kind == 'swar').length, lessThanOrEqualTo(1));
    }
    expect(_struck(drut).length, lessThanOrEqualTo(_struck(madhya).length));
  });

  test('drut protects sam and vibhag heads', () {
    final doc = parseNagma(vilambit);
    final drut = reduceDoc(doc, 'drut');
    final marks = getTaal(doc.taal).matraMarks();
    for (final m in drut.matras) {
      if (marks[m.index] != 'plain') {
        expect(m.notes[0].kind, 'swar',
            reason: 'matra ${m.index} (${marks[m.index]}) must stay struck');
      }
    }
  });

  test('drut omits repeated plain matras', () {
    final doc = parseNagma("S S S m | P m g r | P d n S' | n d P m");
    final drut = reduceDoc(doc, 'drut');
    expect(drut.matras[0].notes[0].kind, 'swar'); // sam Sa struck
    expect(drut.matras[1].notes[0].kind, 'sustain'); // repeat -> held
    expect(drut.matras[2].notes[0].kind, 'sustain'); // repeat -> held
    expect(drut.matras[4].notes[0].kind, 'swar'); // taali P struck
  });

  test('drut protects structural heads for non-teentaal (pancham sawari)', () {
    final doc =
        parseNagma('S r g\nm P m g\nr S r g\nm P d n', taal: 'pancham_sawari');
    final drut = reduceDoc(doc, 'drut');
    final marks = getTaal('pancham_sawari').matraMarks();
    expect(drut.matras.length, 15);
    for (final m in drut.matras) {
      if (marks[m.index] != 'plain') {
        expect(m.notes[0].kind, 'swar',
            reason: 'matra ${m.index} (${marks[m.index]}) must stay struck');
      }
    }
  });

  for (final laya in ['vilambit', 'madhya', 'drut']) {
    test('reduction never invents pitches ($laya)', () {
      final doc = parseNagma(vilambit);
      final allowed = _authoredPitches(doc);
      final red = reduceDoc(doc, laya);
      for (final n in _struck(red)) {
        expect(allowed.contains('${n.swar}/${n.octave}'), isTrue);
      }
    });
  }
}
