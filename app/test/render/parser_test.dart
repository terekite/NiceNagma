// Mirrors core/tests/test_parser.py.

import 'package:flutter_test/flutter_test.dart';
import 'package:nicenagma/render/parser.dart';

const stock = '''
# Bhairavi teentaal stock nagma
S r g m
P d P m
g m P d
P m g r
''';

void main() {
  test('parses teentaal 16 matras', () {
    final doc = parseNagma(stock);
    expect(doc.taal, 'teentaal');
    expect(doc.matras.length, 16);
    expect([for (final m in doc.matras) m.index], List.generate(16, (i) => i));
  });

  test('single line pipe separated', () {
    final doc = parseNagma('S r g m | P d P m | g m P d | P m g r');
    expect(doc.matras.length, 16);
    expect(doc.matras[0].notes[0].swar, 'S');
  });

  test('octave markers', () {
    final doc = parseNagma("S. r g m | P d P m | g m P d | P m g r'");
    expect(doc.matras[0].notes[0].octave, 'mandra');
    expect(doc.matras[15].notes[0].octave, 'taar');
  });

  test('split matra and sustain', () {
    final doc = parseNagma('S,r g m - | P d P m | g m P d | P m g r');
    expect(doc.matras[0].notes.length, 2);
    expect(doc.matras[0].notes[1].swar, 'r');
    expect(doc.matras[3].notes[0].kind, 'sustain');
  });

  test('unknown swar errors', () {
    expect(() => parseNagma('S X g m | P d P m | g m P d | P m g r'),
        throwsA(predicate((e) => e is NagmaParseError && e.message.contains('Unknown swar'))));
  });

  test('wrong vibhag count errors', () {
    expect(() => parseNagma('S r g m | P d P m | g m P d'),
        throwsA(predicate((e) => e is NagmaParseError && e.message.contains('4 vibhags'))));
  });

  test('wrong matra count in vibhag errors', () {
    expect(() => parseNagma('S r g | P d P m | g m P d | P m g r'),
        throwsA(predicate((e) => e is NagmaParseError && e.message.contains('should have 4 matras'))));
  });

  test('up to four subdivisions ok', () {
    final doc = parseNagma('S,r,g,m R g m | P d P m | g m P d | P m g r');
    expect(doc.matras[0].notes.length, 4);
    expect([for (final n in doc.matras[0].notes) n.swar], ['S', 'r', 'g', 'm']);
  });

  test('subdivision with sustain ok', () {
    final doc = parseNagma('S,-,g,m R g m | P d P m | g m P d | P m g r');
    expect(doc.matras[0].notes[1].kind, 'sustain');
  });

  test('too many notes in matra errors', () {
    expect(() => parseNagma('S,r,g,m,P g m R | P d P m | g m P d | P m g r'),
        throwsA(predicate((e) => e is NagmaParseError && e.message.contains('at most 4'))));
  });

  test('leading sustain errors', () {
    expect(() => parseNagma('- r g m | P d P m | g m P d | P m g r'),
        throwsA(predicate((e) => e is NagmaParseError && e.message.contains('cannot begin with a sustain'))));
  });
}
