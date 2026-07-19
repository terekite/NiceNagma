#!/usr/bin/env python3
"""Build a warm plucked sitar SF2 from a single CC0 sitar note, de-twanged.

Source: freesound.org #42192 "sitar01.flac" — a clean single plucked note on the
main (baaj) string of a real sitar. CC0 / public domain (commercial use OK, no
attribution required). See assets/LICENSES.md.

Timbre goal — warm/round, "closer to a sarod," NOT bright/mandolin-ish. A sitar's
jawari (curved buzzing bridge) pumps energy into a 2.5-4 kHz "twang" band + a
fizzy top; a sarod has no jawari, so it's warmer. We can't source a sarod: real
CC0 *isolated* sarod notes don't exist, and the one CC0 sarod recording (#9610) is
a riff whose drone/sympathetic strings ring UNDER the melody note — two pitches a
whole-tone apart — so resampling it across the keyboard mistunes every key. So we
keep this clean, correctly-tuned sitar note and pull it toward the sarod tone with
a warmth EQ: cut the twang formant, roll off the fizz, add body. (A true sarod
would need a licensed clean multisample; noted in assets/LICENSES.md.)

Like the tanpura font this authors a **plucked one-shot** SF2 (samplemode=0, no
loop): the sampler plays the real attack + decay and lets it ring out. The
keyboard is covered by resampling this one note to a spread of anchor pitches
(every 2 semitones) tiled by nearest-sample key ranges. The pitch is measured by
Harmonic Product Spectrum (robust to the jawari overtones that fool autocorr).

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
# The HQ mp3 preview on the public CDN is enough for a plucked multisample.
SOURCE_CDN = "https://cdn.freesound.org/previews/42/42192_229898-hq.mp3"

MAX_DUR_S = 5.0       # cap on a down-pitched (time-stretched) anchor
NOTE_MAX_S = 3.5      # cap the extracted note (its natural decay window)
NOTE_TAIL_S = 0.5     # decay tail to keep past a note when it's the last segment
FADE_IN_S = 0.014     # attack softening: rounds the pluck (~14ms, still a pluck)
FADE_OUT_S = 0.08     # anti-click tail fade
TARGET_RMS = 0.14     # per-anchor loudness normalization (plucked headroom)
ANCHOR_STEP = 2       # author one resampled anchor every N semitones
ANCHOR_SPAN_DN = 12   # author anchors from src-12 ..
ANCHOR_SPAN_UP = 15   # .. to src+15 semitones (≈1 octave down, 1.25 up)
# build_sf2 bakes GLOBAL_TUNE_CENTS into every sample's pitch-correction byte
# (the harmonium recording sits sharp). Our anchors are resampled to exact equal
# temperament, so pre-compensate by the same amount to land back on concert pitch.
TUNE_COMP_CENTS = -GLOBAL_TUNE_CENTS

# --- Warmth EQ (de-twang the jawari sitar toward a sarod-like tone) --------- #
# Kill the 2.5-4 kHz jawari "twang" formant, roll off the fizzy top, add low-mid
# body, and high-pass the boom. Zero-phase FFT-domain EQ (numpy only). Tuned by
# ear + a spectral-centroid target (render centroid ~1900 Hz, down from ~2600).
EQ_ENABLE = True
EQ_HPF_HZ = 80.0            # 2nd-order high-pass: drop sub-body boom
EQ_BODY_HZ = 220.0          # low-shelf centre: warmth/body band
EQ_BODY_DB = 3.5
EQ_TWANG_HZ = 3100.0        # peaking cut: the jawari "twang" formant (2.5-4 kHz)
EQ_TWANG_DB = -7.5
EQ_TWANG_OCT = 0.55         # bell half-width in octaves (~Q 2)
EQ_FIZZ_HZ = 5000.0         # high-shelf: roll off the fizzy jawari top hard
EQ_FIZZ_DB = -10.0

NAMES = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B']


# --------------------------------------------------------------------------- #
# pitch detection + note extraction + resampling + EQ
# --------------------------------------------------------------------------- #
def hps_f0(seg: np.ndarray, sr: int, fmin: float = 120.0, fmax: float = 450.0,
           harmonics: int = 5) -> float:
    """Fundamental via Harmonic Product Spectrum.

    The sarod note has partials (e.g. a strong ~290 Hz overtone above its ~256 Hz
    fundamental) that make plain autocorrelation lock onto the wrong period. HPS
    multiplies harmonically-downsampled copies of the magnitude spectrum, so the
    TRUE fundamental — whose 2f/3f/… all land on real partials — wins.
    """
    seg = seg.astype(np.float64)
    if not np.any(seg):
        return 0.0
    w = seg * np.hanning(len(seg))
    n = 1 << int(np.ceil(np.log2(len(w) * 8)))     # zero-pad for bin resolution
    mag = np.abs(np.fft.rfft(w, n))
    freqs = np.fft.rfftfreq(n, 1.0 / sr)
    span = len(mag) // harmonics
    hps = mag[:span].copy()
    for h in range(2, harmonics + 1):
        hps *= mag[::h][:span]
    fb = freqs[:span]
    band = (fb >= fmin) & (fb <= fmax)
    idx = np.where(band)[0]
    if idx.size == 0:
        return 0.0
    return float(fb[idx][int(np.argmax(hps[idx]))])


def extract_note(riff: np.ndarray, sr: int) -> tuple[np.ndarray, float]:
    """Pull the cleanest STEADY melodic note (+ its decay window) from the source.

    General enough for either a single sustained recording (#42192 → one long
    segment) or a phrase: score each onset-segment and pick the longest one that
    is (a) in a melodic f0 range and (b) near-constant pitch (small first-half vs
    second-half glide), keep its decay (capped at NOTE_MAX_S), and measure the
    fundamental on its STEADY SUSTAIN (skip the bright attack, which can bias HPS).
    """
    hop, win = int(0.02 * sr), int(0.04 * sr)
    env = np.array([np.sqrt(np.mean(riff[i:i + win] ** 2))
                    for i in range(0, len(riff) - win, hop)])
    thr = env.max() * 0.10
    active = env > thr
    segs, i = [], 0
    while i < len(active):
        if active[i]:
            j = i
            while j < len(active) and active[j]:
                j += 1
            if (j - i) * hop > 0.20 * sr:
                segs.append((i * hop, j * hop))
            i = j
        else:
            i += 1

    best = None  # (duration, start, end, f0)
    for idx, (s, e) in enumerate(segs):
        seg = riff[s:e]
        h = len(seg) // 2
        f1 = hps_f0(seg[:h], sr)
        f2 = hps_f0(seg[h:], sr)
        if f1 <= 0 or f2 <= 0:
            continue
        glide_cents = abs(1200 * np.log2(f2 / f1))
        f0 = hps_f0(seg, sr)
        if not (150.0 <= f0 <= 400.0) or glide_cents > 40.0:
            continue
        # keep the natural decay up to the next onset (or a fixed tail)
        end = segs[idx + 1][0] if idx + 1 < len(segs) else min(len(riff),
                                                               e + int(NOTE_TAIL_S * sr))
        if best is None or (e - s) > best[0]:
            best = (e - s, s, end, f0)
    if best is None:
        raise RuntimeError("no clean steady note found in the source recording")
    _, start, end, _ = best
    start = max(0, start - int(0.005 * sr))  # tiny pre-onset margin
    end = min(end, start + int(NOTE_MAX_S * sr))  # cap the decay window
    note = riff[start:end].astype(np.float64)
    # measure the fundamental on the steady sustain, skipping the bright attack
    a0 = int(0.15 * sr)
    sustain = note[a0:a0 + int(0.6 * sr)] if len(note) > a0 + 4096 else note
    return note, hps_f0(sustain, sr)


def shape_pluck(seg: np.ndarray, sr: int) -> np.ndarray:
    """Fade the extracted note's ends (attack softening + anti-click tail)."""
    seg = seg.copy()
    fi, fo = int(FADE_IN_S * sr), int(FADE_OUT_S * sr)
    seg[:fi] *= np.linspace(0, 1, fi)
    seg[-fo:] *= np.linspace(1, 0, fo)
    return seg


def resample(x: np.ndarray, ratio: float) -> np.ndarray:
    """Linear-interpolate resample. ratio>1 => higher pitch (and shorter)."""
    n_out = int(len(x) / ratio)
    idx = np.arange(n_out) * ratio
    return np.interp(idx, np.arange(len(x)), x)


def warm_eq(x: np.ndarray, sr: int) -> np.ndarray:
    """Zero-phase FFT-domain EQ that warms/rounds the tone (numpy only).

    Product of gentle shapes: a 2nd-order high-pass, a low-shelf body boost, a
    peaking cut on the residual brightness formant, and a high-shelf on the top.
    Applied per anchor so the bands sit at fixed absolute frequencies.
    """
    if not EQ_ENABLE:
        return x
    n = len(x)
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(n, 1.0 / sr)
    lg = np.log2(np.maximum(f, 1.0))
    bell = EQ_TWANG_DB * np.exp(-0.5 * ((lg - np.log2(EQ_TWANG_HZ)) / EQ_TWANG_OCT) ** 2)
    body = EQ_BODY_DB * 0.5 * (1.0 - np.tanh((lg - np.log2(EQ_BODY_HZ)) / 0.7))
    fizz = EQ_FIZZ_DB * 0.5 * (1.0 + np.tanh((lg - np.log2(EQ_FIZZ_HZ)) / 0.6))
    gain = 10.0 ** ((bell + body + fizz) / 20.0)
    r = (f / EQ_HPF_HZ) ** 2                       # 2nd-order high-pass magnitude
    gain *= r / np.sqrt(1.0 + r ** 2)
    return np.fft.irfft(X * gain, n)


def make_anchor(base: np.ndarray, sr: int, f_src: float, midi: int) -> np.ndarray:
    """Resample the source note to `midi`, warm-EQ, normalize, cap length, int16."""
    f_tgt = 440.0 * 2 ** ((midi - 69) / 12.0) * 2 ** (TUNE_COMP_CENTS / 1200.0)
    seg = resample(base, f_tgt / f_src)
    maxlen = int(MAX_DUR_S * sr)
    if len(seg) > maxlen:
        seg = seg[:maxlen].copy()
    seg = warm_eq(seg, sr)              # polish toward a rounder tone
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

    src, sr = sf.read(RAW)
    if src.ndim > 1:
        src = src.mean(axis=1)

    note, f_src = extract_note(src, sr)
    src_midi = int(round(69 + 12 * np.log2(f_src / 440.0)))
    print(f"source: {len(src)/sr:.1f}s recording -> extracted {len(note)/sr:.2f}s note, "
          f"f0={f_src:.1f}Hz -> {NAMES[src_midi%12]}{src_midi//12-1} (MIDI {src_midi})")

    base = shape_pluck(note, sr)

    roots = list(range(src_midi - ANCHOR_SPAN_DN, src_midi + ANCHOR_SPAN_UP + 1,
                        ANCHOR_STEP))
    roots = [m for m in roots if 12 <= m <= 108]

    samples = []
    for i, midi in enumerate(roots):
        pcm = make_anchor(base, sr, f_src, midi)
        lo = 0 if i == 0 else (roots[i - 1] + midi) // 2 + 1
        hi = 127 if i == len(roots) - 1 else (midi + roots[i + 1]) // 2
        samples.append({"pcm": pcm, "root": midi, "lo": lo, "hi": hi,
                        "loop_start": 1, "loop_end": len(pcm) - 1,
                        "name": f"Sitar_{NAMES[midi%12]}{midi//12-1}"})

    # samplemode=0: plucked one-shot, no loop — play the real attack+decay.
    build_sf2(samples, sr, OUT_SF2, inst_name="Sitar", samplemode=0, release_s=0.4)

    sz = os.path.getsize(OUT_SF2)
    lo_n = f"{NAMES[roots[0]%12]}{roots[0]//12-1}"
    hi_n = f"{NAMES[roots[-1]%12]}{roots[-1]//12-1}"
    print(f"wrote {OUT_SF2}  ({sz//1024} KB, {len(samples)} plucked zones, "
          f"anchors {lo_n}..{hi_n}, tune {GLOBAL_TUNE_CENTS + TUNE_COMP_CENTS:+d}c net)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
