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
# Legato overlap added to every note's sounding duration, in seconds. This is
# musical between DIFFERENT pitches (harmonium keys bleed); it must NOT apply
# across a repeated pitch or the sampler retriggers mid-note and the repeat
# sounds cut off.
LEGATO_OVERLAP_S = 0.045
# Minimum silence before the SAME pitch sounds again, so repeated notes (e.g.
# Sa Sa Sa) re-articulate cleanly instead of tying into one cut-off blur.
REARTICULATION_GAP_S = 0.05
# Floor on any note's sounding duration after clamping.
MIN_NOTE_S = 0.06
# Base MIDI velocity before taal shaping.
BASE_VELOCITY = 82
# Per-avartan velocity noise amplitude (integer velocity units).
VELOCITY_NOISE = 4

BELLOWS_RATE_HZ = 0.25
BELLOWS_DEPTH = 0.09

# Intra-note bellows swell: a note starts softer and rises to full expression
# over its attack (the player's bellows building pressure). Depth scales with
# note length — longer notes breathe more; a fast note barely swells.
SWELL_MAX_DEPTH = 0.20
SWELL_FULL_AT_S = 0.8   # notes this long or longer get full depth

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


def base_velocity(matra: int, mark: str, matra_count: int, marks: list[str]) -> int:
    """Taal-shaped velocity before per-avartan noise.

    Swell toward sam across the cycle, with structural accents/dips layered on.
    `marks` is the taal's full per-matra mark list so the post-khaali dip lands
    on the matra after the *actual* khaali(s) — taals have khaali off-centre and
    some (Ektaal) have two, so the old `matra_count // 2` midpoint was wrong.
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

    # Slight slackening in the matra right after any khaali (derived from the
    # marks, not assumed at the cycle midpoint).
    if matra > 0 and marks[matra - 1] == "khaali":
        vel -= 4.0

    return int(round(vel))


def apply_velocity_noise(rng: random.Random, velocity: int) -> int:
    v = velocity + rng.randint(-VELOCITY_NOISE, VELOCITY_NOISE)
    return max(_VELOCITY_MIN, min(_VELOCITY_MAX, v))


# Grace notes (kan swar): a light, quick neighbour-swar flicked in just before a
# main note. Applied sparingly and varied per avartan so it never sounds
# rubber-stamped. The grace steals time from BEFORE the main onset, so matra
# boundaries stay exact.
GRACE_DENSITY = 0.12       # default fraction of eligible notes that get a kan
# Ornamentation thins as tempo rises (research: "reduce ornamentation" at drut).
GRACE_DENSITY_BY_LAYA = {"vilambit": 0.14, "madhya": 0.09, "drut": 0.03}
GRACE_DUR_S = 0.07         # sounding length of the grace
GRACE_LEGATO_S = 0.03      # extra overlap so the grace slurs into the main note
GRACE_MIN_MAIN_S = 0.30    # don't ornament very short notes (e.g. split halves)
GRACE_VEL_SCALE = 0.68     # grace is softer than the main note


def grace_rng(base_seed: int, avartan: int) -> random.Random:
    """RNG for ornament placement — separate from the timing/dynamics RNG so
    adding grace notes doesn't perturb the existing per-note feel."""
    return random.Random((base_seed * 2246822519) ^ (avartan * 3266489917) ^ 0x85EBCA77)


def kan_pitch(midi: int, pitch_set: list[int]) -> int | None:
    """The neighbour swar to grace with: nearest composition pitch above the
    main note (upper kan), else nearest below. In-mode by construction."""
    higher = [p for p in pitch_set if p > midi]
    if higher:
        return min(higher)
    lower = [p for p in pitch_set if p < midi]
    return max(lower) if lower else None


def swell_depth(rng: random.Random, dur_s: float, structural: bool) -> float:
    """Per-note intra-note swell depth in [0, ~0.5]. Longer notes breathe more."""
    d = SWELL_MAX_DEPTH * min(1.0, dur_s / SWELL_FULL_AT_S)
    if structural:
        d *= 0.8                      # accented onsets are a touch firmer
    d *= 0.85 + 0.3 * rng.random()    # per-note variation
    return round(max(0.0, min(0.5, d)), 3)


def bellows_params() -> dict[str, float]:
    return {"rate_hz": BELLOWS_RATE_HZ, "depth": BELLOWS_DEPTH}
