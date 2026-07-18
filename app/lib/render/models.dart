// In-memory models mirroring the JSON contracts.
//
// Dart port of core/src/nagma_core/models.py. Only the fields the on-device
// compute path needs; contracts/*.schema.json remains the source of truth.

class Note {
  final String kind; // 'swar' | 'sustain'
  final String? swar; // required when kind == 'swar'
  final String octave;
  const Note({required this.kind, this.swar, this.octave = 'madhya'});

  factory Note.sustain() => const Note(kind: 'sustain');
  factory Note.swarNote(String swar, String octave) =>
      Note(kind: 'swar', swar: swar, octave: octave);
}

class Matra {
  final int index;
  final List<Note> notes;
  const Matra({required this.index, required this.notes});
}

class NagmaDoc {
  final String taal;
  final List<Matra> matras;
  final String raag;
  final String name;
  final String sourceText;
  const NagmaDoc({
    required this.taal,
    required this.matras,
    this.raag = 'bhairavi',
    this.name = '',
    this.sourceText = '',
  });
}

/// A single sounded note in the compiled super-loop. Absolute-second onset.
class Event {
  final double startS;
  double durS; // mutable: legato/re-articulation clamps adjust it in place
  final int midi;
  final int velocity;
  final int matra;
  final int avartan;
  final bool structural;
  final double swell; // intra-note bellows swell depth (0..1)
  Event({
    required this.startS,
    required this.durS,
    required this.midi,
    required this.velocity,
    required this.matra,
    required this.avartan,
    required this.structural,
    this.swell = 0.0,
  });
}

/// The compiled score: event list + exact timing metadata. Mirrors the fields
/// the native renderer + mastering need.
class ExpressiveScore {
  final int sampleRate;
  final double bpm;
  final int saMidi;
  final String instrument;
  final int avartans;
  final int matraCount;
  final double matraDurS;
  final double avartanDurS;
  final double loopLengthS;
  final int loopLengthSamples;
  final List<Event> events;
  final int seed;
  final Map<String, double> bellows;

  const ExpressiveScore({
    required this.sampleRate,
    required this.bpm,
    required this.saMidi,
    required this.instrument,
    required this.avartans,
    required this.matraCount,
    required this.matraDurS,
    required this.avartanDurS,
    required this.loopLengthS,
    required this.loopLengthSamples,
    required this.events,
    this.seed = 0,
    this.bellows = const {'rate_hz': 0.25, 'depth': 0.09},
  });
}
