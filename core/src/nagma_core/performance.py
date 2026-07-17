"""The performance model — the "human" layer, pure code.

Everything here is deterministic given a seed. The compiler calls these to turn
exact grid times into a phrasing that doesn't sound rubber-stamped, WITHOUT ever
moving a structural onset (matra boundaries and sam stay mathematically exact).

The five levers from the spec:
  1. micro-timing jitter on non-structural notes only
  2. taal-shaped dynamics (swell toward sam, accents on taali, dip on khaali)
  3. legato overlap between consecutive notes
  4. bellows-style slow amplitude undulation (emitted as score-level LFO params)
  5. per-avartan variation (a fresh seed per cycle)
"""

from __future__ import annotations

import random

# --- tunables (conservative, harmonium-flavoured defaults) ------------------

# Max absolute micro-timing jitter for a non-structural note, in seconds.
JITTER_S = 0.012
# Legato overlap added to every note's sounding duration, in seconds.
LEGATO_OVERLAP_S = 0.045
# Base MIDI velocity before taal shaping.
BASE_VELOCITY = 82
# Per-avartan velocity noise amplitude (integer velocity units).
VELOCITY_NOISE = 4

BELLOWS_RATE_HZ = 0.25
BELLOWS_DEPTH = 0.09

_VELOCITY_MIN = 24
_VELOCITY_MAX = 122


def avartan_rng(base_seed: int, avartan: int) -> random.Random:
    """Deterministic RNG unique to (base_seed, avartan) so each cycle varies."""
    return random.Random((base_seed * 2654435761) ^ (avartan * 40503) ^ 0x9E3779B9)


def timing_jitter(rng: random.Random, structural: bool) -> float:
    """Seconds to add to an onset. Always 0 for structural notes."""
    if structural:
        return 0.0
    return rng.uniform(-JITTER_S, JITTER_S)


def base_velocity(matra: int, mark: str, matra_count: int) -> int:
    """Taal-shaped velocity before per-avartan noise.

    Swell toward sam across the cycle, with structural accents/dips layered on.
    """
    vel = float(BASE_VELOCITY)

    # Gentle swell that peaks approaching sam (end of the cycle resolving to 0).
    # position 0 at sam, rising to ~1 just before the next sam.
    pos = matra / matra_count
    vel += 10.0 * pos

    # Structural accents.
    if mark == "sam":
        vel += 22.0
    elif mark == "taali":
        vel += 10.0
    elif mark == "khaali":
        vel -= 12.0

    # Slight slackening in the matra right after khaali.
    khaali_start = matra_count // 2  # 8 in Teentaal
    if matra == khaali_start + 1:
        vel -= 4.0

    return int(round(vel))


def apply_velocity_noise(rng: random.Random, velocity: int) -> int:
    v = velocity + rng.randint(-VELOCITY_NOISE, VELOCITY_NOISE)
    return max(_VELOCITY_MIN, min(_VELOCITY_MAX, v))


def bellows_params() -> dict[str, float]:
    return {"rate_hz": BELLOWS_RATE_HZ, "depth": BELLOWS_DEPTH}
