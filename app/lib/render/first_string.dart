// Auto-select the tanpura's first-string tuning from the nagma.
//
// On a 4-string tanpura the second, third and fourth strings are always Sa, Sa
// and kharaj-Sa. Only the FIRST string varies, tuned to a note that is consonant
// and present in the raga — Pa for most raags, or Ma / tivra-Ma / Ni for raags
// that omit Pa. Since the user enters the melody (not a raga name), we derive the
// first string from which swars actually appear in the nagma.
//
// The result is a swar symbol (see sargam.dart's swarSemitones), so the sequencer
// turns it into a semitone offset with no special-casing — Pa, shuddha Ma, tivra
// Ma and Ni all fall out of the same map.

import 'models.dart';

/// Priority order for the first string: Pa, then shuddha Ma, then tivra Ma, then
/// shuddha Ni. Pa is the default (a plain fifth) when none are present.
const List<String> _firstStringPriority = ['P', 'm', 'M', 'N'];

/// Choose the first-string swar from the set of swars present in the nagma.
/// Returns the highest-priority swar that appears, else 'P' (fallback).
String selectFirstStringSwar(Set<String> swarsPresent) {
  for (final swar in _firstStringPriority) {
    if (swarsPresent.contains(swar)) return swar;
  }
  return 'P';
}

/// The set of swar symbols that appear in a parsed nagma (ignoring octave and
/// sustain notes).
Set<String> swarsInDoc(NagmaDoc doc) {
  final swars = <String>{};
  for (final matra in doc.matras) {
    for (final note in matra.notes) {
      if (note.kind == 'swar' && note.swar != null) swars.add(note.swar!);
    }
  }
  return swars;
}
