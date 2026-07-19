// Tanpura sequencer: build a humanized 4-string pluck loop as an ExpressiveScore.
//
// A tanpura is a plucked drone: a continuous cycle of 4 strings — first (Pa/Ma/…),
// Sa, Sa, kharaj-Sa(low) — plucked one after another, loosely and NOT on the beat,
// each ringing long so several sustains overlap into a continuous bloom. This
// produces the note events for that; scoreToMidi + the native renderer turn them
// into a seamless loop, exactly like the lehra path.
//
// Pitch: the bundled tanpura.sf2 is a C# tanpura (mid Sa = C#3/49, Pa = G#2/44,
// kharaj = C#2/37). The whole set transposes uniformly by pitch-shifting in the
// sampler, so we place the tanpura's mid Sa at the octave of the current Sa's
// pitch class NEAREST the C#3 sample root — keeping every per-key shift within
// ~6 semitones (small, and on transient-rich plucks it holds up well), and one
// octave below the lehra's Sa (the natural low drone register).

import 'models.dart';
import 'performance.dart' show avartanRng;
import 'sargam.dart' show swarSemitones;

const int _defaultSampleRate = 44100;

/// MIDI root of the mid-Sa sample in tanpura.sf2 (C#3). Keep in sync with
/// scripts/build_tanpura.py.
const int _midSaSampleRoot = 49;

/// Fraction of the cycle at which each string is plucked, in pluck order
/// [first, Sa, Sa, kharaj]. The four strokes fall in the first ~half of the cycle
/// (fairly even, the two Sa strings close together so they connect); the kharaj
/// (4th) then rings out for a long hold before the cycle repeats.
const List<double> _pluckFrac = [0.06, 0.22, 0.36, 0.52];

/// Per-string base velocity (mid-Sa strings sit loudest; kharaj a touch under).
const List<int> _baseVel = [85, 90, 90, 82];

/// Per-string ring time (seconds), in pluck order [first, Sa, Sa, kharaj]. Each
/// note blooms then decays over this — so you hear the four distinct pitches move,
/// not one flat drone — with the kharaj (bass) ringing longest to hold the low Sa
/// through the cycle. The mixer applies the decay envelope; overlap keeps it
/// continuous.
const List<double> _stringDurS = [4.5, 4.5, 4.5, 7.0];

/// How far a whole phrase's start drifts, cycle to cycle (seconds). The internal
/// stroke spacing (1-2, 2-3, 3-4) stays FIXED every run — a tanpura player keeps a
/// consistent pattern — only the run's start time moves a little.
const double _phraseDriftS = 0.35;

/// Place the tanpura's mid Sa: the octave of Sa's pitch class nearest the C#3
/// sample root, so the sampler's per-key pitch shift stays small.
int tanpuraMidSa(int saMidi) {
  final pc = saMidi % 12;
  return pc + 12 * ((_midSaSampleRoot - pc) / 12).round();
}

/// Build the tanpura score for a key + first-string tuning.
///
/// [saMidi] is the lehra's Sa (as from saToMidi). [firstStringSwar] is the
/// auto-selected first string (see first_string.dart) — its offset comes from
/// swarSemitones, placed an octave below the tanpura's mid Sa. [seed] reseeds the
/// per-cycle jitter so the [cycleCount]-cycle super-loop never rubber-stamps.
ExpressiveScore tanpuraScore({
  required int saMidi,
  required String firstStringSwar,
  int seed = 0,
  int sampleRate = _defaultSampleRate,
  double cycleLengthS = 7.0, // slow, meditative; the tanpura never tracks BPM
  int cycleCount = 4,
}) {
  final saT = tanpuraMidSa(saMidi);
  final firstOff = swarSemitones[firstStringSwar] ?? 7; // fallback Pa
  final stringMidi = <int>[
    saT + firstOff - 12, // first string, octave below mid Sa (Pa -> saT-5)
    saT, // Sa
    saT, // Sa
    saT - 12, // kharaj (low Sa)
  ];

  final T = cycleLengthS;
  final spacing = T / 4;
  final events = <Event>[];

  for (var c = 0; c < cycleCount; c++) {
    final rng = avartanRng(seed, c);
    // One offset for the whole phrase: the run starts a little earlier/later, but
    // the strokes keep their fixed internal spacing. Only dynamics vary per note.
    final phraseStart = c * T + rng.uniform(-_phraseDriftS, _phraseDriftS);
    for (var i = 0; i < 4; i++) {
      var start = phraseStart + _pluckFrac[i] * T;
      if (start < 0) start = 0;
      final vel = (_baseVel[i] + rng.randint(-8, 8)).clamp(1, 127);
      events.add(Event(
        startS: start,
        durS: _stringDurS[i],
        midi: stringMidi[i],
        velocity: vel,
        matra: i,
        avartan: c,
        structural: false,
        swell: 0.0,
      ));
    }
  }

  final loopLengthS = cycleCount * T;
  final loopLengthSamples = (loopLengthS * sampleRate).round();

  return ExpressiveScore(
    sampleRate: sampleRate,
    bpm: 60.0,
    saMidi: saMidi,
    instrument: 'tanpura',
    avartans: cycleCount,
    matraCount: 4,
    matraDurS: spacing,
    avartanDurS: T,
    loopLengthS: loopLengthS,
    loopLengthSamples: loopLengthSamples,
    events: events,
    seed: seed,
    bellows: const {'rate_hz': 0.0, 'depth': 0.0}, // no harmonium bellows on plucks
  );
}
