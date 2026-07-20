"""Tempo-stability guard: the STRUCTURAL beat grid must be machine-perfect.

The user practiced against a rendered loop and worried the tempo fluctuates —
that it might speed up at the start of the loop and slow down at the end. That is
exactly the failure this test forbids. Per the two non-negotiable invariants in
CLAUDE.md, matra boundaries and sam are mathematically exact, and micro-timing
jitter is applied ONLY to non-structural (ornament / split-slot) onsets. So the
ideal is a perfectly uniform structural grid at ``matra_dur_s = 60/bpm`` per
matra; only ornaments may wobble.

Why the thresholds below count as "imperceptible":
  - Human sensitivity to a note deviating from an isochronous pulse (the timing
    JND) is roughly 6-10 ms for ordinary listeners and ~10 ms even for trained
    musicians; the tempo-change JND is ~2-5%.
  - At 80 BPM one beat is 750 ms, so 1% of a beat is 7.5 ms.
  - We assert a 1 ms tolerance on the structural grid. That is well under both
    the per-onset JND and 1% of a beat, so any drift this test still permits is
    provably inaudible. In practice the compiler places structural onsets on the
    grid to within floating-point error (~1e-12 s), leaving a ~9-orders-of-
    magnitude margin: the test trips instantly if a regression ever adds timing
    jitter to a structural onset (the smallest such bug injects the full
    JITTER_S = 12 ms, 12x over tolerance).

The proposed-teentaal nagma is the canonical lehra and is used throughout.
"""

import math
from pathlib import Path

import pytest

from nagma_core.compiler import compile_score
from nagma_core.parser import parse_nagma

# 1 ms: far below the timing JND and 1% of a beat; see module docstring.
GRID_TOL_S = 1e-3
SPACING_TOL_S = 1e-3

_NAGMA_PATH = (
    Path(__file__).resolve().parents[2] / "assets" / "nagmas" / "proposed-teentaal.nagma"
)


def _doc():
    return parse_nagma(_NAGMA_PATH.read_text())


# --- pure metric helpers (shared by the real-score checks AND the injected-drift
# --- negative controls, so the guard exercises the identical code path) --------

def _ideal(avartan: int, matra: int, avartan_dur_s: float, matra_dur_s: float) -> float:
    """The mathematically-exact grid time for a structural onset."""
    return avartan * avartan_dur_s + matra * matra_dur_s


def _max_grid_deviation(times, ideals) -> float:
    """Max absolute deviation of onset times from their ideal grid positions."""
    return max(abs(t - i) for t, i in zip(times, ideals))


def _half_split_ioi_means(times, loop_length_s):
    """Mean inter-onset interval (IOI) of the structural onsets in the first vs
    second half of the loop. A loop that 'speeds up then slows down' shows a
    smaller first-half mean and a larger second-half mean."""
    times = sorted(times)
    iois = [(a, b - a) for a, b in zip(times, times[1:])]
    first = [d for start, d in iois if start < loop_length_s / 2]
    second = [d for start, d in iois if start >= loop_length_s / 2]
    assert first and second, "need structural onsets in both halves of the loop"
    return sum(first) / len(first), sum(second) / len(second)


def _structural(score):
    """Structural onsets sorted by time, with their ideal grid positions."""
    evs = sorted((e for e in score.events if e.structural), key=lambda e: e.start_s)
    times = [e.start_s for e in evs]
    ideals = [
        _ideal(e.avartan, e.matra, score.avartan_dur_s, score.matra_dur_s) for e in evs
    ]
    return times, ideals


# --- the guard: structural grid is exact across the whole loop -----------------

@pytest.mark.parametrize("bpm", [80, 120, 200])  # vilambit, madhya, drut paths
def test_structural_onsets_lie_on_the_exact_grid(bpm):
    # realize() picks the laya from bpm and reduces before compiling, so this
    # covers all three reduction paths. sam / taali / khaali stay struck in every
    # laya, so the taal skeleton always carries structural onsets to check.
    from nagma_core.compiler import realize

    score = realize(_doc(), bpm=bpm, sa="C", avartans=4, seed=7)
    times, ideals = _structural(score)
    assert times, "expected structural onsets"
    dev = _max_grid_deviation(times, ideals)
    assert dev < GRID_TOL_S, (
        f"structural grid drifted {dev * 1000:.4f} ms at {bpm} BPM "
        f"(tolerance {GRID_TOL_S * 1000:.1f} ms); the beat grid must be exact"
    )


def test_first_half_and_second_half_tempo_match():
    # Directly targets the user's concern: no speeding up early / slowing down
    # late. First-half and second-half mean matra spacing must be equal, and both
    # must equal the ideal matra duration.
    score = compile_score(_doc(), bpm=80, sa="C", avartans=4, seed=7)
    times, _ = _structural(score)
    first, second = _half_split_ioi_means(times, score.loop_length_s)
    assert abs(first - second) < SPACING_TOL_S, (
        f"loop speeds up/slows down: first-half matra spacing {first * 1000:.3f} ms "
        f"vs second-half {second * 1000:.3f} ms"
    )
    # In vilambit every matra is struck, so each IOI is exactly one matra.
    assert first == pytest.approx(score.matra_dur_s, abs=SPACING_TOL_S)
    assert second == pytest.approx(score.matra_dur_s, abs=SPACING_TOL_S)


# --- negative control: prove the guard is not a tautology ----------------------
# Warp the exact grid with a smooth "speed up then slow down" profile (a constant
# tempo acceleration: warped(t) = t + 0.5*k*t^2, so IOIs grow monotonically over
# the loop) and confirm BOTH metrics fire. This runs the identical metric code as
# the real checks, so it proves those checks would catch the regression.

_DRIFT_K = 2e-4  # gentle acceleration; still far over the 1 ms tolerance


def _warp(t: float) -> float:
    return t + 0.5 * _DRIFT_K * t * t


def test_negative_control_grid_deviation_is_detected():
    score = compile_score(_doc(), bpm=80, sa="C", avartans=4, seed=7)
    times, ideals = _structural(score)
    # sanity: the real grid passes
    assert _max_grid_deviation(times, ideals) < GRID_TOL_S
    # inject drift: the SAME metric must now trip
    warped = [_warp(t) for t in times]
    dev = _max_grid_deviation(warped, ideals)
    assert dev > GRID_TOL_S, (
        "negative control failed to detect injected tempo drift — the grid "
        "metric is tautological"
    )


def test_negative_control_half_split_is_detected():
    score = compile_score(_doc(), bpm=80, sa="C", avartans=4, seed=7)
    times, _ = _structural(score)
    warped = [_warp(t) for t in times]
    first, second = _half_split_ioi_means(warped, _warp(score.loop_length_s))
    assert abs(first - second) > SPACING_TOL_S, (
        "negative control failed to detect first-half/second-half tempo "
        "difference — the spacing metric is tautological"
    )
    # and the drift is a slow-down over the loop, matching the user's scenario
    assert second > first
