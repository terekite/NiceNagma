// The performance model — the "human" layer, pure code.
//
// Dart port of core/src/nagma_core/performance.py. Everything here is
// deterministic given a seed. The compiler calls these to turn exact grid times
// into phrasing that doesn't sound rubber-stamped, WITHOUT ever moving a
// structural onset (matra boundaries and sam stay mathematically exact).
//
// The Dart PRNG need not match Python's Mersenne Twister bit-for-bit; it only has
// to be deterministic within Dart (the render cache key is derived from the
// RenderRequest params, not the audio).

import 'dart:math' as math;

// --- tunables (conservative, harmonium-flavoured defaults) ------------------

/// Max absolute micro-timing jitter for a non-structural note, in seconds.
const double jitterS = 0.012;

/// Legato overlap added to every note's sounding duration, in seconds.
const double legatoOverlapS = 0.045;

/// Minimum silence before the SAME pitch sounds again.
const double rearticulationGapS = 0.05;

/// Floor on any note's sounding duration after clamping.
const double minNoteS = 0.06;

/// Base MIDI velocity before taal shaping.
const int baseVelocityConst = 82;

/// Per-avartan velocity noise amplitude (integer velocity units).
const int velocityNoise = 4;

const double bellowsRateHz = 0.25;
const double bellowsDepth = 0.09;

// Intra-note bellows swell.
const double swellMaxDepth = 0.20;
const double swellFullAtS = 0.8;

const int _velocityMin = 24;
const int _velocityMax = 122;

// Plucked lutes (sitar) don't take harmonium-style kan-swar grace notes — you
// don't flick those on a plucked string — so they render with grace density 0.
const Set<String> pluckedInstruments = {'sitar'};
bool isPlucked(String instrument) => pluckedInstruments.contains(instrument);

// --- plucked expression: the "human" layer that a resampled one-shot lacks ----
// Sources (see PR notes): sitar meend + per-note variation research brief.

/// Meend (pitch glide) parameters. A real sitarist glides *up* into a note from
/// the previous pitch on small ascending steps, especially approaching a point
/// of resolution (sam/taali); descending motion, leaps and repeats are re-plucked.
const double meendGlideS = 0.15;       // ~150 ms, kept ~constant across laya
const int meendMaxSemitones = 2;       // fits the default ±2-st pitch-bend range
const double meendProb = 0.72;         // chance an eligible step glides
const double meendProbStructural = 0.95; // higher when landing on sam/taali
const double meendMinNoteS = 0.12;     // don't glide notes shorter than this

/// Per-note static micro-detune (fake round-robin). Gaussian, SD in cents; most
/// notes land within a few cents so it reads as human, not out-of-tune.
const double microPitchCentsSd = 3.0;

/// Plucked micro-timing: Gaussian onset jitter (SD seconds) on non-structural
/// notes — a normal spread reads more human than uniform jitter. Sam/matra exact.
const double pluckedJitterSd = 0.014;
/// Plucked per-note velocity spread (Gaussian SD, velocity units).
const double pluckedVelocitySd = 6.0;

// Grace notes (kan swar).
const double graceDensity = 0.12;
const Map<String, double> graceDensityByLaya = {
  'vilambit': 0.14,
  'madhya': 0.09,
  'drut': 0.03,
};
const double graceDurS = 0.07;
const double graceLegatoS = 0.03;
const double graceMinMainS = 0.30;
const double graceVelScale = 0.68;

/// A deterministic RNG wrapper matching the Python draw operations used here.
class Rng {
  final math.Random _r;
  Rng(int seed) : _r = math.Random(seed);

  double uniform(double a, double b) => a + (b - a) * _r.nextDouble();

  /// Inclusive on both ends, like Python's random.randint(a, b).
  int randint(int a, int b) => a + _r.nextInt(b - a + 1);

  double random() => _r.nextDouble();

  /// Approx-Gaussian (mean 0) via sum of three uniforms; naturally clamped to
  /// ±3·sd. Good enough for micro-timing/detune humanization.
  double gaussian(double sd) =>
      sd * (uniform(-1, 1) + uniform(-1, 1) + uniform(-1, 1));
}

int _mask(int v) => v & 0x7FFFFFFF;

/// Deterministic RNG unique to (baseSeed, avartan) so each cycle varies.
Rng avartanRng(int baseSeed, int avartan) =>
    Rng(_mask((baseSeed * 2654435761) ^ (avartan * 40503) ^ 0x9E3779B9));

/// RNG for ornament placement — separate stream so graces don't perturb feel.
Rng graceRng(int baseSeed, int avartan) =>
    Rng(_mask((baseSeed * 2246822519) ^ (avartan * 3266489917) ^ 0x85EBCA77));

/// RNG for plucked expression (micro-detune, meend decisions) — a separate
/// stream so adding it doesn't perturb the existing timing/dynamics feel.
Rng pluckRng(int baseSeed, int avartan) =>
    Rng(_mask((baseSeed * 2891336453) ^ (avartan * 2654435761) ^ 0x27D4EB2F));

/// Seconds to add to an onset. Always 0 for structural notes.
double timingJitter(Rng rng, bool structural) =>
    structural ? 0.0 : rng.uniform(-jitterS, jitterS);

/// Gaussian onset jitter for plucked instruments (0 for structural notes).
double timingJitterGaussian(Rng rng, bool structural) =>
    structural ? 0.0 : rng.gaussian(pluckedJitterSd);

/// The pitch to glide (meend) INTO the current note from, or null to re-pluck.
/// Real rule: glide small ascending steps, especially into resolution notes.
int? meendFrom(Rng rng, int? prevMidi, int midi, bool targetStructural) {
  if (prevMidi == null) return null;
  final step = midi - prevMidi;
  if (step < 1 || step > meendMaxSemitones) return null; // ascending steps only
  final p = targetStructural ? meendProbStructural : meendProb;
  return rng.random() < p ? prevMidi : null;
}

/// Static per-note micro-detune in cents (fake round-robin).
double microDetuneCents(Rng rng) => rng.gaussian(microPitchCentsSd);

/// Taal-shaped velocity before per-avartan noise. Swell toward sam across the
/// cycle, with structural accents/dips layered on.
int baseVelocity(int matra, String mark, int matraCount) {
  var vel = baseVelocityConst.toDouble();

  // Gentle swell that peaks approaching sam.
  final pos = matra / matraCount;
  vel += 10.0 * pos;

  if (mark == 'sam') {
    vel += 22.0;
  } else if (mark == 'taali') {
    vel += 10.0;
  } else if (mark == 'khaali') {
    vel -= 12.0;
  }

  // Slight slackening in the matra right after khaali.
  final khaaliStart = matraCount ~/ 2; // 8 in Teentaal
  if (matra == khaaliStart + 1) {
    vel -= 4.0;
  }

  return vel.round();
}

int applyVelocityNoise(Rng rng, int velocity) {
  final v = velocity + rng.randint(-velocityNoise, velocityNoise);
  return math.max(_velocityMin, math.min(_velocityMax, v));
}

/// Wider Gaussian velocity spread for plucked instruments (~±1-2 dB per note),
/// so no two plucks hit at the same level.
int applyVelocityNoisePlucked(Rng rng, int velocity) {
  final v = velocity + rng.gaussian(pluckedVelocitySd).round();
  return math.max(_velocityMin, math.min(_velocityMax, v));
}

/// The neighbour swar to grace with: nearest composition pitch above the main
/// note (upper kan), else nearest below. In-mode by construction.
int? kanPitch(int midi, List<int> pitchSet) {
  final higher = pitchSet.where((p) => p > midi).toList();
  if (higher.isNotEmpty) return higher.reduce(math.min);
  final lower = pitchSet.where((p) => p < midi).toList();
  return lower.isNotEmpty ? lower.reduce(math.max) : null;
}

/// Per-note intra-note swell depth in [0, ~0.5]. Longer notes breathe more.
double swellDepth(Rng rng, double durS, bool structural) {
  var d = swellMaxDepth * math.min(1.0, durS / swellFullAtS);
  if (structural) d *= 0.8; // accented onsets are a touch firmer
  d *= 0.85 + 0.3 * rng.random(); // per-note variation
  final clamped = math.max(0.0, math.min(0.5, d));
  return (clamped * 1000).round() / 1000; // round(., 3)
}

Map<String, double> bellowsParams() =>
    {'rate_hz': bellowsRateHz, 'depth': bellowsDepth};
