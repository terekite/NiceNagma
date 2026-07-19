// Compiler: NagmaDoc + (BPM, Sa) -> ExpressiveScore.
//
// Dart port of core/src/nagma_core/compiler.py. Enforces the two invariants:
//   1. Machine-perfect laya. matraDurS = 60/bpm exactly; every matra boundary and
//      sam sits on an exact multiple of it. loopLengthSamples is an exact integer.
//   2. Human timbre via pure code. The performance model perturbs only
//      non-structural onsets and shapes dynamics/legato/per-avartan variation.

import 'dart:math' as math;

import 'models.dart';
import 'performance.dart' as perf;
import 'reduce.dart';
import 'sargam.dart';
import 'taal.dart';

const int defaultSampleRate = 44100;
const int defaultAvartans = 4;

/// Mutable base (jitter-free, base-velocity) event for a single cycle.
class _BaseEvent {
  double startS;
  double durS;
  final int midi;
  final int matra;
  final bool structural;
  final String mark;
  _BaseEvent({
    required this.startS,
    required this.durS,
    required this.midi,
    required this.matra,
    required this.structural,
    required this.mark,
  });
}

List<_BaseEvent> _oneAvartanEvents(
  NagmaDoc doc,
  double matraDurS,
  int saMidi,
  List<String> marks,
) {
  final events = <_BaseEvent>[];
  _BaseEvent? last; // the most recent struck note, for sustain folding

  for (final matra in doc.matras) {
    final n = matra.notes.length;
    for (var slot = 0; slot < n; slot++) {
      final note = matra.notes[slot];
      final slotDur = matraDurS / n;
      final slotStart = matra.index * matraDurS + slot * slotDur;
      // The first slot of a matra lands on a matra boundary -> structural.
      final structural = slot == 0;

      if (note.kind == 'sustain') {
        if (last != null) last.durS += slotDur;
        // A sustain with no predecessor is silence (parser forbids it at sam).
        continue;
      }

      final midi = noteToMidi(note.swar!, note.octave, saMidi);
      final ev = _BaseEvent(
        startS: slotStart,
        durS: slotDur,
        midi: midi,
        matra: matra.index,
        structural: structural,
        mark: marks[matra.index],
      );
      events.add(ev);
      last = ev;
    }
  }

  return events;
}

/// Compile a NagmaDoc into an ExpressiveScore super-loop.
ExpressiveScore compileScore(
  NagmaDoc doc, {
  required double bpm,
  required Object sa, // String key or int MIDI
  int sampleRate = defaultSampleRate,
  int avartans = defaultAvartans,
  int seed = 0,
  String instrument = 'harmonium',
  double? graceDensity,
}) {
  graceDensity ??= perf.graceDensity;
  if (bpm <= 0) throw ArgumentError('bpm must be positive');
  if (avartans < 1) throw ArgumentError('avartans must be >= 1');

  final taalDef = getTaal(doc.taal);
  final marks = taalDef.matraMarks();
  final matraCount = taalDef.matraCount;
  if (doc.matras.length != matraCount) {
    throw ArgumentError(
      'NagmaDoc has ${doc.matras.length} matras but ${taalDef.name} '
      'requires $matraCount.',
    );
  }

  final saMidi = sa is int ? sa : saToMidi(sa as String);

  // --- exact timing (invariant #1) --------------------------------------
  final matraDurS = 60.0 / bpm;
  final avartanDurS = matraCount * matraDurS;
  final loopLengthS = avartans * avartanDurS;
  final loopLengthSamples = (loopLengthS * sampleRate).round();

  final base = _oneAvartanEvents(doc, matraDurS, saMidi, marks);

  // Add legato overlap once on the base durations.
  for (final ev in base) {
    ev.durS += perf.legatoOverlapS;
  }

  // --- expand across avartans with per-cycle variation (invariant #2) ---
  final pitchSet = (base.map((e) => e.midi).toSet().toList())..sort();

  final plucked = perf.isPlucked(instrument);
  final events = <Event>[];
  for (var a = 0; a < avartans; a++) {
    final rng = perf.avartanRng(seed, a);
    final grng = perf.graceRng(seed, a); // separate stream
    final prng = perf.pluckRng(seed, a); // plucked expression stream
    final cycleOffset = a * avartanDurS;
    int? prevMidi; // previous struck pitch this avartan, for meend
    for (final ev in base) {
      final jitter = plucked
          ? perf.timingJitterGaussian(rng, ev.structural)
          : perf.timingJitter(rng, ev.structural);
      final start = cycleOffset + ev.startS + jitter;
      var vel = perf.baseVelocity(ev.matra, ev.mark, matraCount);
      vel = plucked
          ? perf.applyVelocityNoisePlucked(rng, vel)
          : perf.applyVelocityNoise(rng, vel);
      // A pluck attacks then decays — no reed-style swell. Instead give it
      // per-note micro-detune (round-robin) and meend glides into the note.
      final swell = plucked ? 0.0 : perf.swellDepth(rng, ev.durS, ev.structural);
      double microCents = 0.0;
      int? glideFrom;
      double glideS = 0.0;
      if (plucked) {
        microCents = perf.microDetuneCents(prng);
        if (ev.durS >= perf.meendMinNoteS) {
          glideFrom = perf.meendFrom(prng, prevMidi, ev.midi, ev.structural);
          if (glideFrom != null) glideS = math.min(perf.meendGlideS, 0.6 * ev.durS);
        }
      }
      prevMidi = ev.midi;
      events.add(Event(
        startS: start,
        durS: ev.durS,
        midi: ev.midi,
        velocity: vel,
        matra: ev.matra,
        avartan: a,
        structural: ev.structural,
        swell: swell,
        microCents: microCents,
        glideFromMidi: glideFrom,
        glideS: glideS,
      ));
      // Kan swar: sparingly flick a neighbour swar in just before this note.
      // It steals time from BEFORE the exact onset, so the grid is untouched.
      if (ev.durS >= perf.graceMinMainS && grng.random() < graceDensity) {
        final kan = perf.kanPitch(ev.midi, pitchSet);
        final gstart = start - perf.graceDurS;
        if (kan != null && kan != ev.midi && gstart >= cycleOffset) {
          events.add(Event(
            startS: gstart,
            durS: perf.graceDurS + perf.graceLegatoS,
            midi: kan,
            velocity: math.max(1, (vel * perf.graceVelScale).toInt()),
            matra: ev.matra,
            avartan: a,
            structural: false,
            swell: 0.0,
          ));
        }
      }
    }
  }

  events.sort((a, b) => a.startS.compareTo(b.startS));

  // Same-pitch re-articulation: legato must not sustain a note into the next
  // onset of the SAME pitch. Clamp each note to end a small gap before the next
  // same-pitch onset. Different-pitch overlap (harmonium bleed) is left alone.
  final byPitch = <int, List<Event>>{};
  for (final e in events) {
    byPitch.putIfAbsent(e.midi, () => []).add(e);
  }
  for (final group in byPitch.values) {
    for (var i = 0; i + 1 < group.length; i++) {
      final a = group[i];
      final b = group[i + 1];
      final latestEnd = b.startS - perf.rearticulationGapS;
      if (a.startS + a.durS > latestEnd) {
        a.durS = math.max(perf.minNoteS, latestEnd - a.startS);
      }
    }
  }

  return ExpressiveScore(
    sampleRate: sampleRate,
    bpm: bpm,
    saMidi: saMidi,
    instrument: instrument,
    avartans: avartans,
    matraCount: matraCount,
    matraDurS: matraDurS,
    avartanDurS: avartanDurS,
    loopLengthS: loopLengthS,
    loopLengthSamples: loopLengthSamples,
    events: events,
    seed: seed,
    bellows: perf.bellowsParams(),
  );
}

/// Author-once entry point: pick a laya from `bpm`, REDUCE the authored
/// (vilambit) doc to that laya, then compile — with ornament density scaled to
/// the laya. Pass `laya` to override the automatic BPM->laya selection.
ExpressiveScore realize(
  NagmaDoc doc, {
  required double bpm,
  required Object sa,
  String? laya,
  int sampleRate = defaultSampleRate,
  int avartans = defaultAvartans,
  int seed = 0,
  String instrument = 'harmonium',
}) {
  laya ??= layaForBpm(bpm);
  final reduced = reduceDoc(doc, laya);
  return compileScore(
    reduced,
    bpm: bpm,
    sa: sa,
    sampleRate: sampleRate,
    avartans: avartans,
    seed: seed,
    instrument: instrument,
    // Plucked instruments (sitar) take no kan-swar graces.
    graceDensity: perf.isPlucked(instrument)
        ? 0.0
        : (perf.graceDensityByLaya[laya] ?? perf.graceDensity),
  );
}
