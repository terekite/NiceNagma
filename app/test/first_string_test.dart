// First-string auto-selection priority: Pa > shuddha Ma > tivra Ma > Ni, else Pa.

import 'package:flutter_test/flutter_test.dart';
import 'package:nicenagma/render/first_string.dart';
import 'package:nicenagma/render/models.dart';

void main() {
  test('Pa wins whenever it is present', () {
    expect(selectFirstStringSwar({'S', 'P', 'm', 'M', 'N'}), 'P');
    expect(selectFirstStringSwar({'r', 'g', 'P', 'd'}), 'P');
  });

  test('shuddha Ma when Pa absent', () {
    expect(selectFirstStringSwar({'S', 'm', 'M', 'N'}), 'm');
  });

  test('tivra Ma when Pa and shuddha Ma absent', () {
    expect(selectFirstStringSwar({'S', 'M', 'N'}), 'M');
  });

  test('Ni when Pa/Ma absent', () {
    expect(selectFirstStringSwar({'S', 'r', 'g', 'N'}), 'N');
  });

  test('fallback to Pa when none of the candidates appear', () {
    expect(selectFirstStringSwar({'S', 'r', 'g', 'd', 'n'}), 'P');
    expect(selectFirstStringSwar({}), 'P');
  });

  test('Bhairavi-style nagma (has P) selects Pa', () {
    // S r g m P d n — Bhairavi contains Pancham.
    final doc = NagmaDoc(taal: 'teentaal', matras: [
      Matra(index: 0, notes: [Note.swarNote('S', 'madhya')]),
      Matra(index: 1, notes: [Note.swarNote('P', 'madhya')]),
      Matra(index: 2, notes: [Note.swarNote('m', 'madhya')]),
      Matra(index: 3, notes: [Note.sustain()]),
    ]);
    expect(selectFirstStringSwar(swarsInDoc(doc)), 'P');
  });

  test('swarsInDoc ignores sustains and collects distinct swars', () {
    final doc = NagmaDoc(taal: 'teentaal', matras: [
      Matra(index: 0, notes: [Note.swarNote('S', 'madhya'), Note.sustain()]),
      Matra(index: 1, notes: [Note.swarNote('m', 'mandra')]),
      Matra(index: 2, notes: [Note.swarNote('S', 'taar')]), // duplicate swar
    ]);
    expect(swarsInDoc(doc), {'S', 'm'});
  });
}
