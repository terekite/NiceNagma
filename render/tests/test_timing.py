"""Tempo-stability guards on the render side.

Two layers, matching how the pipeline actually flows:

1. MIDI (deterministic, always runs when ``mido`` is present). The score carries
   exact-second onsets; ``score_to_midi`` converts seconds -> ticks by rounding
   at 960 PPQ on a 120-BPM basis (1 tick = 520.8 us, so worst-case rounding of an
   onset is +/-260 us). This test recovers the earliest note-on at each structural
   matra boundary and asserts it stays on the exact grid to within 1 ms — proving
   the seconds->ticks conversion introduces no accumulating drift across the
   4-avartan super-loop.

2. Audio (lenient, END-TO-END, skipped cleanly). When numpy + soundfile +
   fluidsynth + a soundfont are all present, render the real loop and check that
   detected onsets do not drift grossly between the first and second half of the
   loop. Onset detection on a legato harmonium with grace notes and reverb is
   noisy, so this is a coarse net (~15 ms) — the deterministic MIDI/core tests are
   the real guard. Skips exactly like ``test_master.py`` when deps are missing.

The core-side ``test_timing_grid.py`` is the primary, exact guard on the score.
"""

import math
import shutil
from pathlib import Path

import pytest

mido = pytest.importorskip("mido")

from nagma_core.compiler import compile_score
from nagma_core.parser import parse_nagma
from nagma_render.midi import score_to_midi

_NAGMA_PATH = (
    Path(__file__).resolve().parents[2] / "assets" / "nagmas" / "proposed-teentaal.nagma"
)

# MIDI quantization ceiling is ~0.26 ms; 1 ms leaves generous headroom while
# still catching any real structural drift (see module docstring).
MIDI_TOL_S = 1e-3
# Coarse end-to-end net: only gross drift, not micro-timing.
AUDIO_HALF_SPLIT_TOL_S = 0.015


def _doc():
    return parse_nagma(_NAGMA_PATH.read_text())


def _first_note_on_seconds_by_tick(mid, score):
    """Absolute onset time (seconds) of the earliest note-on landing at each
    distinct tick, using the file's tempo/PPQ (constant here)."""
    tempo = 500_000  # score_to_midi writes a single set_tempo of 120 BPM
    tpb = mid.ticks_per_beat
    t = 0
    onsets = {}  # tick -> seconds (first seen wins; messages are time-ordered)
    for msg in mid.tracks[0]:
        t += msg.time
        if msg.type == "set_tempo":
            tempo = msg.tempo
        elif msg.type == "note_on" and msg.velocity > 0:
            onsets.setdefault(t, mido.tick2second(t, tpb, tempo))
    return onsets


def _structural_grid_times(score):
    """The set of exact structural grid times in the score, and the ideal-time
    lookup for each (avartan, matra)."""
    grid = {}
    for e in score.events:
        if e.structural:
            ideal = e.avartan * score.avartan_dur_s + e.matra * score.matra_dur_s
            grid[round(ideal, 9)] = ideal
    return grid


def test_midi_structural_onsets_stay_on_grid(tmp_path):
    score = compile_score(_doc(), bpm=80, sa="C", avartans=4, seed=7)
    path = tmp_path / "s.mid"
    score_to_midi(score, str(path))
    mid = mido.MidiFile(str(path))

    onset_secs = _first_note_on_seconds_by_tick(mid, score)
    grid = _structural_grid_times(score)
    assert grid, "expected structural grid points"

    worst = 0.0
    for ideal in grid.values():
        # nearest recovered onset to this ideal grid time
        nearest = min(onset_secs.values(), key=lambda s: abs(s - ideal))
        worst = max(worst, abs(nearest - ideal))
    assert worst < MIDI_TOL_S, (
        f"MIDI structural onsets drifted {worst * 1000:.4f} ms from the grid "
        f"(tolerance {MIDI_TOL_S * 1000:.1f} ms)"
    )


def test_midi_negative_control_detects_drift(tmp_path):
    # Prove the MIDI check is not a tautology: warp recovered onsets with a
    # 'speed up then slow down' acceleration and confirm the same comparison trips.
    score = compile_score(_doc(), bpm=80, sa="C", avartans=4, seed=7)
    path = tmp_path / "s.mid"
    score_to_midi(score, str(path))
    mid = mido.MidiFile(str(path))
    onset_secs = list(_first_note_on_seconds_by_tick(mid, score).values())
    grid = _structural_grid_times(score)

    k = 2e-4
    warped = [t + 0.5 * k * t * t for t in onset_secs]
    worst = 0.0
    for ideal in grid.values():
        nearest = min(warped, key=lambda s: abs(s - ideal))
        worst = max(worst, abs(nearest - ideal))
    assert worst > MIDI_TOL_S, "negative control did not detect injected drift"


# --- optional, lenient, end-to-end audio onset guard ---------------------------
# numpy/soundfile/fluidsynth are gated INSIDE the audio test so the deterministic
# MIDI guards above still run whenever mido alone is present.


def _soundfont():
    import os

    env = os.environ.get("NAGMA_SOUNDFONT")
    if env and Path(env).is_file():
        return env
    default = _NAGMA_PATH.parents[1] / "soundfonts" / "harmonium.sf2"
    return str(default) if default.is_file() else None


def _detect_onsets(sig, sr):
    """Lightweight amplitude-envelope onset detector (no librosa): rectify,
    smooth, then pick local peaks in the positive first difference."""
    import numpy as np

    if sig.ndim > 1:
        sig = sig.mean(axis=1)
    env = np.abs(sig)
    win = max(1, int(0.01 * sr))  # 10 ms smoothing
    kernel = np.ones(win) / win
    env = np.convolve(env, kernel, mode="same")
    d = np.diff(env, prepend=env[:1])
    d[d < 0] = 0.0
    thresh = 0.25 * d.max() if d.max() > 0 else 0.0
    min_gap = int(0.08 * sr)  # notes at least 80 ms apart
    onsets = []
    last = -min_gap
    for i in range(1, len(d) - 1):
        if d[i] >= thresh and d[i] >= d[i - 1] and d[i] > d[i + 1] and i - last >= min_gap:
            onsets.append(i / sr)
            last = i
    return onsets


def test_audio_onsets_do_not_drift_across_the_loop(tmp_path):
    np = pytest.importorskip("numpy", reason="numpy not installed")
    sf = pytest.importorskip("soundfile", reason="soundfile not installed")
    fluidsynth = shutil.which("fluidsynth")
    sfont = _soundfont()
    if not fluidsynth or not sfont:
        pytest.skip(
            "audio onset guard needs fluidsynth + a soundfont "
            f"(fluidsynth={'yes' if fluidsynth else 'no'}, soundfont={'yes' if sfont else 'no'})"
        )

    from nagma_render.pipeline import render_score  # imported lazily; render dep

    score = compile_score(_doc(), bpm=80, sa="C", avartans=4, seed=7)
    out = tmp_path / "loop.wav"
    render_score(score, sfont, str(out))

    sig, sr = sf.read(str(out), always_2d=True)
    onsets = _detect_onsets(sig, sr)
    if len(onsets) < 8:
        pytest.skip(f"onset detector found too few onsets ({len(onsets)}) to judge drift")

    iois = [(a, b - a) for a, b in zip(onsets, onsets[1:])]
    mid_t = score.loop_length_s / 2
    first = [d for s, d in iois if s < mid_t]
    second = [d for s, d in iois if s >= mid_t]
    assert first and second
    diff = abs(np.median(first) - np.median(second))
    assert diff < AUDIO_HALF_SPLIT_TOL_S, (
        f"rendered loop drifts: first-half median IOI {np.median(first) * 1000:.1f} ms "
        f"vs second-half {np.median(second) * 1000:.1f} ms (tol "
        f"{AUDIO_HALF_SPLIT_TOL_S * 1000:.0f} ms)"
    )
