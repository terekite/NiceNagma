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
}

int _mask(int v) => v & 0x7FFFFFFF;

/// Deterministic RNG unique to (baseSeed, avartan) so each cycle varies.
Rng avartanRng(int baseSeed, int avartan) =>
    Rng(_mask((baseSeed * 2654435761) ^ (avartan * 40503) ^ 0x9E3779B9));

/// RNG for ornament placement — separate stream so graces don't perturb feel.
Rng graceRng(int baseSeed, int avartan) =>
    Rng(_mask((baseSeed * 2246822519) ^ (avartan * 3266489917) ^ 0x85EBCA77));

/// Seconds to add to an onset. Always 0 for structural notes.
double timingJitter(Rng rng, bool structural) =>
    structural ? 0.0 : rng.uniform(-jitterS, jitterS);

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
