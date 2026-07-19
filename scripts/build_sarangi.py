#!/usr/bin/env python3
"""Build a bowed-string sarangi SF2 from REAL CC0 sarangi recordings — the
HARMONIUM approach: a discrete multisample of real recorded sustain, played
per-note (no synthesis, no meend), pitch-matched by the sampler.

Source: two CC0 studio recordings of a LIVE sarangi player by freesound user
sarman1234 (Rode mic, treated room):
  816125  https://freesound.org/people/sarman1234/sounds/816125/   (CC0)
  816126  https://freesound.org/people/sarman1234/sounds/816126/   (CC0)

These are raga phrases; the only LONG, clean, pitch-stable sustained tone the
player holds is D5 (~588 Hz, up to ~3 s). We take those D5 runs as the real
timbral source and resample each to every target semitone (tune pre-compensated
to exact 12-TET). Because the source is long, every note is filled with a smooth,
CONTINUOUS real bow — no short-loop re-articulation (the earlier build's "bowed
twice" pulse) and no crossfade-tiling artifacts. The player's own subtle andolan
rides along (authentic), and we assign different D5 runs across the keyboard so
notes don't all wobble identically. A soft bow onset + gentle release are shaped
on top; a long tail loop covers the rare note held past the baked length.

Honest limitation: with only D5 as clean material, low notes are down-shifted up
to ~3 octaves, so their formants drift dark. This is the thin-free-source reality
(no CC0 sarangi multisample exists) and part of the go/no-go evaluation.

Usage:  .venv/bin/python scripts/build_sarangi.py
"""

from __future__ import annotations

import os
import subprocess
import sys
import urllib.request

import numpy as np
import soundfile as sf

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
# Reuse the SF2 writer + tuning/loudness constants verbatim (build_sf2 untouched —
# keeps the merge surface with the harmonium/tanpura work empty).
from build_harmonium import build_sf2, GLOBAL_TUNE_CENTS, TARGET_RMS, XFADE  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW_DIR = os.path.join(ROOT, "assets", "soundfonts", "raw")
OUT_SF2 = os.path.join(ROOT, "assets", "soundfonts", "sarangi.sf2")
NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

CDN = "https://cdn.freesound.org/previews/816/{id}_17630533-hq.mp3"
# Long, clean, pitch-stable D5 sustain runs (id, t0, t1) found by a steadiness scan.
D5_RUNS = [
    ("816125", 5.30, 8.34),   # 3.0 s
    ("816126", 3.94, 5.80),   # 1.9 s
    ("816126", 11.05, 12.58),  # 1.5 s
]
SRC_F0 = 588.0  # measured D5

LO_MIDI, HI_MIDI = 36, 74     # C2..D5 (match the harmonium keyboard)
SUSTAIN_S = 2.5               # baked note length (notes rarely exceed this)
ATTACK_S = 0.075             # soft bow onset
RELEASE_S = 0.30             # gentle tail release
DECAY_DB = -2.0              # very slight natural decay across the note


def midi_to_freq(m: float) -> float:
    return 440.0 * 2 ** ((m - 69) / 12.0)


def fetch_decode(sid: str) -> tuple[np.ndarray, int]:
    os.makedirs(RAW_DIR, exist_ok=True)
    mp3 = os.path.join(RAW_DIR, f"sarangi_real_{sid}.mp3")
    wav = os.path.join(RAW_DIR, f"sarangi_real_{sid}.wav")
    if not os.path.exists(mp3):
        print(f"fetching CC0 sarangi take {sid}: {CDN.format(id=sid)}")
        urllib.request.urlretrieve(CDN.format(id=sid), mp3)
    if not os.path.exists(wav):
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", mp3,
                        "-ar", "44100", "-ac", "1", wav], check=True)
    x, sr = sf.read(wav)
    if x.ndim > 1:
        x = x.mean(axis=1)
    return x.astype(np.float64), sr


def resample_to_freq(x: np.ndarray, f0_src: float, f0_tgt: float) -> np.ndarray:
    if f0_tgt > f0_src:                              # up-shift: anti-alias pre-filter
        k = max(1, int(round(f0_tgt / f0_src)))
        if k > 1:
            x = np.convolve(x, np.ones(k) / k, "same")
    n_out = int(round(len(x) * f0_src / f0_tgt))
    idx = np.linspace(0, len(x) - 1, n_out)
    return np.interp(idx, np.arange(len(x)), x)


def make_baked_note(run: np.ndarray, sr: int, midi: int):
    """Resample a real D5 sustain run to `midi` and shape it into a smooth baked
    note: level-flatten the source's own dynamics, apply a soft bow onset + slight
    decay + gentle release. Returns (int16 pcm, loop_start, loop_end). The loop
    covers a whole-period tail region for any note held past SUSTAIN_S."""
    precomp = 2 ** (-GLOBAL_TUNE_CENTS / 1200.0)      # cancel build_sf2's shdr tune
    seg = resample_to_freq(run, SRC_F0, midi_to_freq(midi) * precomp)
    target = int(SUSTAIN_S * sr)
    if len(seg) < target:                             # (shouldn't happen: D5 downshifts grow)
        seg = np.pad(seg, (0, target - len(seg)), mode="reflect")
    seg = seg[:target].copy()

    # flatten the source's own slow amplitude drift so our envelope is what shapes it
    w = int(0.04 * sr)
    env = np.convolve(np.abs(seg), np.ones(w) / w, "same")
    seg *= np.median(env) / np.maximum(env, 1e-6)

    # soft bow onset, slight natural decay, gentle release
    a = int(ATTACK_S * sr)
    seg[:a] *= np.linspace(0, 1, a) ** 2
    seg *= np.linspace(1.0, 10 ** (DECAY_DB / 20), len(seg))
    r = int(RELEASE_S * sr)
    seg[-r:] *= np.linspace(1, 0, r)

    # loop a whole-period region in the steady tail (before the release)
    period = sr / midi_to_freq(midi)
    le = len(seg) - r - int(0.02 * sr)
    ls = le - int(round(0.4 * sr / period) * period)
    ls = max(a + int(0.02 * sr), ls)

    rms = np.sqrt(np.mean(seg ** 2)) or 1.0
    seg *= TARGET_RMS / rms
    peak = np.max(np.abs(seg))
    if peak > 0.98:
        seg *= 0.98 / peak
    pcm = np.clip(seg * 32767.0, -32768, 32767).astype("<i2")
    return pcm, ls, le


def main() -> int:
    runs = []
    for sid, t0, t1 in D5_RUNS:
        x, sr = fetch_decode(sid)
        runs.append(x[int(t0 * sr):int(t1 * sr)])
    sr = 44100
    print(f"loaded {len(runs)} real D5 sustain runs "
          f"({', '.join(f'{len(r)/sr:.1f}s' for r in runs)})")

    samples = []
    for i, midi in enumerate(range(LO_MIDI, HI_MIDI + 1)):
        run = runs[i % len(runs)]                     # vary source so notes differ
        pcm, ls, le = make_baked_note(run, sr, midi)
        samples.append({"pcm": pcm, "root": midi, "loop_start": ls, "loop_end": le,
                        "name": f"Srng_{NAMES[midi % 12]}{midi // 12 - 1}"})

    build_sf2(samples, sr, OUT_SF2, inst_name="Sarangi")
    kb = os.path.getsize(OUT_SF2) // 1024
    print(f"wrote {OUT_SF2}  ({kb} KB, {len(samples)} baked-sustain zones, C2..D5, "
          f"real CC0 D5 source, tune {GLOBAL_TUNE_CENTS}c)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
