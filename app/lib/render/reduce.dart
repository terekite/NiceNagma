// Laya reduction: derive madhya/drut realizations from an authored vilambit doc.
//
// Dart port of core/src/nagma_core/reduce.py. The user authors the most
// elaborated (vilambit) version; faster layas are DERIVED by metric reduction,
// never elaboration. Reduction only keeps authored notes or holds across dropped
// ones, so it can never produce a wrong pitch.

import 'models.dart';
import 'taal.dart';

// Laya bands by BPM. Soft, tala-dependent thresholds.
const double vilambitMaxBpm = 85;
const double madhyaMaxBpm = 160;
const List<String> layas = ['vilambit', 'madhya', 'drut'];

String layaForBpm(double bpm) {
  if (bpm <= vilambitMaxBpm) return 'vilambit';
  if (bpm <= madhyaMaxBpm) return 'madhya';
  return 'drut';
}

Note _copy(Note n) => Note(kind: n.kind, swar: n.swar, octave: n.octave);

Note _sustain() => Note.sustain();

/// Pitch identity for equality comparisons; null for a sustain.
List<String?>? _pitch(Note n) =>
    n.kind == 'swar' ? <String?>[n.swar, n.octave] : null;

bool _pitchEq(List<String?>? a, List<String?>? b) {
  if (a == null || b == null) return false;
  return a[0] == b[0] && a[1] == b[1];
}

List<Matra> _reduceMadhya(NagmaDoc doc) {
  final out = <Matra>[];
  for (final m in doc.matras) {
    final n = m.notes.length;
    final keep = {0, n ~/ 2}; // downbeat + midpoint (caps struck slots at 2)
    final notes = [
      for (var i = 0; i < n; i++) keep.contains(i) ? _copy(m.notes[i]) : _sustain()
    ];
    out.add(Matra(index: m.index, notes: notes));
  }
  return out;
}

List<Matra> _reduceDrut(NagmaDoc doc, Taal taal) {
  final marks = taal.matraMarks();
  final out = <Matra>[];
  List<String?>? lastStruck;
  for (final m in doc.matras) {
    final slot0 = m.notes[0];
    final mark = marks[m.index];
    final pitch = _pitch(slot0);
    // Protect the taal outline; elsewhere omit a plain matra that just repeats.
    final strike = slot0.kind == 'swar' &&
        !(mark == 'plain' && pitch != null && _pitchEq(pitch, lastStruck));
    if (strike) {
      out.add(Matra(index: m.index, notes: [_copy(slot0)])); // whole-matra note
      lastStruck = pitch;
    } else {
      out.add(Matra(index: m.index, notes: [_sustain()])); // held through
    }
  }
  return out;
}

/// Return a NagmaDoc realized for `laya` ('vilambit'|'madhya'|'drut').
NagmaDoc reduceDoc(NagmaDoc doc, String laya) {
  if (laya == 'vilambit') {
    return NagmaDoc(
      taal: doc.taal,
      matras: [
        for (final m in doc.matras)
          Matra(index: m.index, notes: [for (final n in m.notes) _copy(n)])
      ],
      raag: doc.raag,
      name: doc.name,
      sourceText: doc.sourceText,
    );
  }
  final taal = getTaal(doc.taal);
  final List<Matra> matras;
  if (laya == 'madhya') {
    matras = _reduceMadhya(doc);
  } else if (laya == 'drut') {
    matras = _reduceDrut(doc, taal);
  } else {
    throw ArgumentError("unknown laya '$laya'; expected one of $layas");
  }
  return NagmaDoc(
    taal: doc.taal,
    matras: matras,
    raag: doc.raag,
    name: doc.name,
    sourceText: doc.sourceText,
  );
}
