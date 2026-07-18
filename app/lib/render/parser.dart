// Sargam text-grammar parser: raw text -> validated NagmaDoc.
//
// Dart port of core/src/nagma_core/parser.py. Error messages are user-facing and
// mirror the Python parser so the editor's inline validation reads the same.
//
// Grammar (v1): vibhags separated by newline OR '|'; matras whitespace-separated
// within a vibhag; a matra holds 1-4 slots split by ','; '-' is a sustain; a note
// is a swar optionally followed by an octave marker (' taar, . mandra).

import 'models.dart';
import 'sargam.dart';
import 'taal.dart';

/// Raised on any grammar or structural validation failure. The message is
/// user-facing and reads cleanly in the app's inline validation UI.
class NagmaParseError implements Exception {
  final String message;
  NagmaParseError(this.message);
  @override
  String toString() => message;
}

Note _parseNote(String token, {required int vibhagNo, required int matraNo}) {
  final tok = token.trim();
  if (tok.isEmpty) {
    throw NagmaParseError('Empty note in vibhag $vibhagNo, matra $matraNo.');
  }
  if (tok == '-') return Note.sustain();

  var octave = 'madhya';
  var core = tok;
  final marker = tok[tok.length - 1];
  if (octaveMarkers.containsKey(marker)) {
    octave = octaveMarkers[marker]!;
    core = tok.substring(0, tok.length - 1);
  }

  if (!validSwars.contains(core)) {
    throw NagmaParseError(
      "Unknown swar '$tok' in vibhag $vibhagNo, matra $matraNo. "
      'Valid swars: S r R g G m M P d D n N '
      "(add ' for taar / . for mandra).",
    );
  }
  return Note.swarNote(core, octave);
}

List<Note> _parseMatra(String cell, {required int vibhagNo, required int matraNo}) {
  // A matra may be subdivided into up to 4 equal slots via ','. '-' sustains a
  // slot. Faster layas are derived by reducing this authored density.
  final parts = cell.split(',');
  if (parts.length > 4) {
    throw NagmaParseError(
      'Matra $matraNo in vibhag $vibhagNo has ${parts.length} notes; '
      "a matra allows at most 4 subdivisions (split with ',').",
    );
  }
  return [
    for (final p in parts) _parseNote(p, vibhagNo: vibhagNo, matraNo: matraNo)
  ];
}

/// Parse text-grammar into a validated NagmaDoc for the given taal.
NagmaDoc parseNagma(
  String text, {
  String taal = 'teentaal',
  String raag = 'bhairavi',
  String name = '',
}) {
  final taalDef = getTaal(taal);

  // Strip comments/blank lines, then split into vibhags on newlines AND '|'.
  final cleanedLines = text
      .split('\n')
      .where((ln) => ln.trim().isNotEmpty && !ln.trimLeft().startsWith('#'))
      .toList();
  final joined = cleanedLines.join('\n');
  final vibhagStrs = joined
      .replaceAll('\n', '|')
      .split('|')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  final expectedVibhags = taalDef.vibhags.length;
  if (vibhagStrs.length != expectedVibhags) {
    throw NagmaParseError(
      '${taalDef.name} has $expectedVibhags vibhags but got '
      "${vibhagStrs.length}. Separate vibhags with a newline or '|'.",
    );
  }

  final matras = <Matra>[];
  var matraIndex = 0;
  for (var vi = 0; vi < vibhagStrs.length; vi++) {
    final vstr = vibhagStrs[vi];
    final vib = taalDef.vibhags[vi];
    final cells = vstr.split(RegExp(r'\s+')).where((c) => c.isNotEmpty).toList();
    if (cells.length != vib.length) {
      throw NagmaParseError(
        'Vibhag ${vi + 1} should have ${vib.length} matras but got '
        "${cells.length}: '$vstr'.",
      );
    }
    for (var mi = 0; mi < cells.length; mi++) {
      final notes = _parseMatra(cells[mi], vibhagNo: vi + 1, matraNo: mi + 1);
      matras.add(Matra(index: matraIndex, notes: notes));
      matraIndex += 1;
    }
  }

  // A leading sustain has nothing to hold, which is almost always a typo.
  final first = matras[0].notes[0];
  if (first.kind == 'sustain') {
    throw NagmaParseError(
      "The nagma cannot begin with a sustain '-' (nothing to hold at sam).",
    );
  }

  return NagmaDoc(
    taal: taalDef.name,
    matras: matras,
    raag: raag,
    name: name,
    sourceText: text.trim(),
  );
}
