#!/usr/bin/env python3
"""Build a plucked sitar SF2 from a single CC0 sitar recording.

Source: freesound.org #42192 "sitar01.flac" — a clean single plucked note on the
main (baaj) string of a real sitar, with the jawari buzz and audible sympathetic
(tarab) strings ringing. CC0 / public domain (commercial use OK, no attribution
required). See assets/LICENSES.md.

A sitar is a *plucked* string: a sharp attack, a bright buzzing sustain, and a
natural decay — much closer to the tanpura's character than the harmonium's reed.
So, like the tanpura font, this authors a **plucked one-shot** SF2 (samplemode=0,
no loop): the sampler plays the real recorded attack + decay and lets it ring out
under its own envelope, rather than looping a steady sustain.

We only have ONE clean CC0 sitar note, so — unlike the harmonium's real
per-semitone chromatic run — the keyboard is covered by *resampling* that one
note to a spread of anchor pitches (every 2 semitones, ~1 octave either side of
the source) and tiling them by nearest-sample key ranges. Resampling shifts the
formants with the pitch, so anchors far from the source sound progressively less
natural; the anchors are kept close to the source and the outer zones fall back
to the nearest anchor. A future upgrade is a real multi-note sitar recording
(like the harmonium run) — see the TODO in assets/LICENSES.md.

Reuses build_sf2() from build_harmonium.py (samplemode=0 for the pluck).

Usage:  .venv/bin/python scripts/build_sitar.py
"""

from __future__ import annotations

import os
import sys

import numpy as np
import soundfile as sf

# Reuse the SF2 writer + the shared global tune correction from the harmonium
# build. build_sf2's samplemode/lo/hi knobs let us author a plucked, sparse
# multisample without duplicating the RIFF authoring.
from build_harmonium import GLOBAL_TUNE_CENTS, build_sf2

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW_DIR = os.path.join(ROOT, "assets", "soundfonts", "raw")
RAW_MP3 = os.path.join(RAW_DIR, "sitar_42192.mp3")
RAW = os.path.join(RAW_DIR, "sitar_42192.wav")
OUT_SF2 = os.path.join(ROOT, "assets", "soundfonts", "sitar.sf2")

# CC0 source (public domain): freesound.org/people/deleted_user_229898/sounds/42192/.
# The lossless FLAC needs a freesound login; the HQ mp3 preview on the public CDN
# is plenty for a plucked multisample. Drop the FLAC into RAW_DIR and rebuild for
# top quality.
SOURCE_CDN = "https://cdn.freesound.org/previews/42/42192_229898-hq.mp3"

BASE_DUR_S = 3.5      # window taken from the pluck onset (attack + natural decay)
MAX_DUR_S = 5.0       # cap on a down-pitched (time-stretched) anchor
FADE_IN_S = 0.008     # gentle attack fade (kills any pre-onset click)
FADE_OUT_S = 0.08     # anti-click tail fade
TARGET_RMS = 0.14     # per-anchor loudness normalization (plucked headroom)
ANCHOR_STEP = 2       # author one resampled anchor every N semitones
ANCHOR_SPAN_DN = 12   # author anchors from src-12 ..
ANCHOR_SPAN_UP = 15   # .. to src+15 semitones (≈1 octave down, 1.25 up)
# build_sf2 bakes GLOBAL_TUNE_CENTS into every sample's pitch-correction byte
# (the harmonium recording sits sharp). Our anchors are resampled to exact equal
# temperament, so pre-compensate by the same amount to land back on concert pitch.
TUNE_COMP_CENTS = -GLOBAL_TUNE_CENTS

NAMES = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B']


# --------------------------------------------------------------------------- #
# pitch detection + pluck slicing + resampling
# --------------------------------------------------------------------------- #
def measure_f0(x: np.ndarray, sr: int, fmin: float = 70.0, fmax: float = 500.0) -> float:
    """Fundamental via autocorrelation.

    Like the tanpura, a sitar's jawari overtones can be stronger than the
    fundamental, so an FFT peak-pick misfires; autocorrelation is robust here.
    Measured over a steady window just after the attack.
    """
    a = int(0.10 * sr)
    b = min(len(x), a + int(0.6 * sr))
    seg = x[a:b].astype(np.float64)
    seg = seg - seg.mean()
    if not np.any(seg):
        raise ValueError("silent source window")
    corr = np.correlate(seg, seg, "full")[len(seg) - 1:]
    lo = int(sr / fmax)
    hi = min(len(corr) - 1, int(sr / fmin))
    peak = lo + int(np.argmax(corr[lo:hi]))
    return sr / peak


def make_pluck(x: np.ndarray, sr: int) -> np.ndarray:
    """Trim to the pluck: skip pre-onset silence, take a fixed window, fade ends."""
    thr = 0.02 * np.max(np.abs(x))
    onset = int(np.argmax(np.abs(x) > thr))
    onset = max(0, onset - int(0.005 * sr))
    seg = x[onset:onset + int(BASE_DUR_S * sr)].astype(np.float64)
    fi, fo = int(FADE_IN_S * sr), int(FADE_OUT_S * sr)
    seg[:fi] *= np.linspace(0, 1, fi)
    seg[-fo:] *= np.linspace(1, 0, fo)
    return seg


def resample(x: np.ndarray, ratio: float) -> np.ndarray:
    """Linear-interpolate resample. ratio>1 => higher pitch (and shorter)."""
    n_out = int(len(x) / ratio)
    idx = np.arange(n_out) * ratio
    return np.interp(idx, np.arange(len(x)), x)


def make_anchor(base: np.ndarray, sr: int, f_src: float, midi: int) -> np.ndarray:
    """Resample the source pluck to `midi`, normalize, cap length, int16."""
    f_tgt = 440.0 * 2 ** ((midi - 69) / 12.0) * 2 ** (TUNE_COMP_CENTS / 1200.0)
    seg = resample(base, f_tgt / f_src)
    maxlen = int(MAX_DUR_S * sr)
    if len(seg) > maxlen:
        seg = seg[:maxlen].copy()
    fo = int(FADE_OUT_S * sr)
    seg[-fo:] *= np.linspace(1, 0, fo)  # re-taper (resample/cap moved the tail)
    rms = np.sqrt(np.mean(seg ** 2)) or 1.0
    seg *= TARGET_RMS / rms
    peak = np.max(np.abs(seg))
    if peak > 0.98:
        seg *= 0.98 / peak
    return np.clip(seg * 32767.0, -32768, 32767).astype("<i2")


# --------------------------------------------------------------------------- #
def ensure_source() -> None:
    if os.path.exists(RAW):
        return
    os.makedirs(RAW_DIR, exist_ok=True)
    if not os.path.exists(RAW_MP3):
        import urllib.request
        print(f"fetching CC0 source: {SOURCE_CDN}")
        urllib.request.urlretrieve(SOURCE_CDN, RAW_MP3)
    import subprocess
    print("decoding to 44.1k mono wav (ffmpeg)")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", RAW_MP3,
                    "-ar", "44100", "-ac", "1", RAW], check=True)


def main() -> int:
    ensure_source()
    if not os.path.exists(RAW):
        print(f"missing raw source: {RAW}", file=sys.stderr)
        return 2

    mono, sr = sf.read(RAW)
    if mono.ndim > 1:
        mono = mono.mean(axis=1)

    f_src = measure_f0(mono, sr)
    src_midi = int(round(69 + 12 * np.log2(f_src / 440.0)))
    print(f"source: {len(mono)/sr:.1f}s @ {sr}Hz, "
          f"f0={f_src:.1f}Hz -> {NAMES[src_midi%12]}{src_midi//12-1} (MIDI {src_midi})")

    base = make_pluck(mono, sr)

    roots = list(range(src_midi - ANCHOR_SPAN_DN, src_midi + ANCHOR_SPAN_UP + 1,
                        ANCHOR_STEP))
    roots = [m for m in roots if 12 <= m <= 108]

    samples = []
    for i, midi in enumerate(roots):
        pcm = make_anchor(base, sr, f_src, midi)
        # nearest-sample key ranges: split the gap between adjacent anchors at the
        # midpoint; the end zones extend to the keyboard edges.
        lo = 0 if i == 0 else (roots[i - 1] + midi) // 2 + 1
        hi = 127 if i == len(roots) - 1 else (midi + roots[i + 1]) // 2
        samples.append({"pcm": pcm, "root": midi, "lo": lo, "hi": hi,
                        "loop_start": 1, "loop_end": len(pcm) - 1,
                        "name": f"Sitar_{NAMES[midi%12]}{midi//12-1}"})

    # samplemode=0: plucked one-shot, no loop — play the real attack+decay and let
    # it ring out. release_s a touch longer than the harmonium for a natural pluck.
    build_sf2(samples, sr, OUT_SF2, inst_name="Sitar", samplemode=0, release_s=0.4)

    sz = os.path.getsize(OUT_SF2)
    lo_n = f"{NAMES[roots[0]%12]}{roots[0]//12-1}"
    hi_n = f"{NAMES[roots[-1]%12]}{roots[-1]//12-1}"
    print(f"wrote {OUT_SF2}  ({sz//1024} KB, {len(samples)} plucked zones, "
          f"anchors {lo_n}..{hi_n}, tune {GLOBAL_TUNE_CENTS + TUNE_COMP_CENTS:+d}c net)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
