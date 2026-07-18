// Sargam <-> pitch mapping and Sa (tonic) key parsing.
//
// Dart port of core/src/nagma_core/sargam.py. Pure data + functions. Semitone
// offsets are relative to Sa (the tonic), so the same NagmaDoc transposes to any
// key by changing `saMidi`.

/// Semitone offset of each swar above Sa. Lowercase = komal (flat), uppercase =
/// shuddha/tivra. Covers all twelve chromatic degrees.
const Map<String, int> swarSemitones = {
  'S': 0, // Shadja
  'r': 1, // komal Re
  'R': 2, // shuddha Re
  'g': 3, // komal Ga
  'G': 4, // shuddha Ga
  'm': 5, // shuddha Ma
  'M': 6, // tivra Ma
  'P': 7, // Pancham
  'd': 8, // komal Dha
  'D': 9, // shuddha Dha
  'n': 10, // komal Ni
  'N': 11, // shuddha Ni
};

final Set<String> validSwars = swarSemitones.keys.toSet();

const Map<String, int> octaveOffset = {
  'mandra': -12,
  'madhya': 0,
  'taar': 12,
};

/// Text-grammar octave markers appended to a swar token.
const Map<String, String> octaveMarkers = {
  "'": 'taar', //  S'  -> upper octave
  '.': 'mandra', // S.  -> lower octave
};

/// Sa key name -> semitone above C. Sa is placed in MIDI octave 4 (C4 = 60),
/// which puts a harmonium lehra in a comfortable madhya-saptak range.
const Map<String, int> _keySemitone = {
  'C': 0, 'C#': 1, 'Db': 1, 'D': 2, 'D#': 3, 'Eb': 3, 'E': 4,
  'F': 5, 'F#': 6, 'Gb': 6, 'G': 7, 'G#': 8, 'Ab': 8, 'A': 9,
  'A#': 10, 'Bb': 10, 'B': 11,
};

/// MIDI note of C in the octave Sa lives in (C4 = 60).
const int _saBaseMidi = 60;

/// Map a Sa key name ('C#', 'D', ...) to its MIDI note number.
int saToMidi(String key) {
  final k = key.trim();
  final semi = _keySemitone[k];
  if (semi == null) {
    final keys = _keySemitone.keys.toList()..sort();
    throw ArgumentError("Unknown Sa key '$key'. Expected one of: ${keys.join(', ')}");
  }
  return _saBaseMidi + semi;
}

/// Resolve a (swar, octave) pair to an absolute MIDI note for a given Sa.
int noteToMidi(String swar, String octave, int saMidi) {
  final semi = swarSemitones[swar];
  if (semi == null) throw ArgumentError("Unknown swar '$swar'");
  final oct = octaveOffset[octave];
  if (oct == null) throw ArgumentError("Unknown octave '$octave'");
  return saMidi + semi + oct;
}
