#!/usr/bin/env python3
"""Build a bowed-string sarangi SF2 from CC0 single-note recordings.

A sarangi is a bowed, fretless Indian string instrument — a continuous, singing,
sustained tone (not plucked like the tanpura, not a reed like the harmonium). So,
like the harmonium, its SF2 wants a LOOPED sustain (samplemode=1): a short attack
plus a seamless crossfade loop in the steady bow, which the sampler holds for the
note's duration.

Source: two CC0 (public-domain) single sustained sarangi notes by a since-deleted
freesound user (uploader id 1). Each is a clean ~4.3s held tone — a real ~200ms
attack from footage, then a software-built steady sustain with filtered-noise
string resonance (a hybrid design sample, not a pure field recording, but a clean
single note and, crucially, CC0):

  167023  "Sarangi.wav"      -> C4  (measured f0 262.5 Hz, midi 60)
  167088  "Sarangi -G3.wav"  -> G#4 (measured f0 412.2 Hz, midi 68; the "G3" in
                                the filename is mislabeled — the partials
                                412/824/1236/1648 Hz fix the fundamental at 412)

Two source pitches can't span the app's C2..D5 keyboard without heavy pitch-shift,
and the repo's committed `build_sf2` gives each middle zone a one-key range (no
key-range tiling), so — exactly like the harmonium — we author ONE looped zone per
semitone (C2..D5, midi 36..74). For each target semitone we resample the NEAREST
source note to that pitch (down-shift for the low reaches, mild up-shift with a
short anti-alias pre-filter for the few notes above the top source),
pre-compensating `build_harmonium.GLOBAL_TUNE_CENTS` so the sounding pitch is exact
12-TET. A level-flattened crossfade loop (`make_looped_sarangi`) turns the source's
noisy sustain into a steady, seamless bow, and `build_sf2` (reused untouched)
authors the looping SF2.

Timbre caveat: the sources are synthesized-hybrid, and the low octaves are C4 shifted
down up to two octaves, so formants drift dark. It reads as a bowed sustain in
fluidsynth; the on-device "does it sing like a sarangi" listen is a documented TODO
(and note AVAudioUnitSampler ignores SF2 loop points — see the handoff).

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
# Reuse the SF2 writer + tuning/loudness constants verbatim (no edits to the shared
# script — keeps the merge surface with the harmonium/tanpura work empty). The loop
# slicer is sarangi-specific (level-flattened, below) to tame the noisy sustain.
from build_harmonium import build_sf2, GLOBAL_TUNE_CENTS, TARGET_RMS, XFADE  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW_DIR = os.path.join(ROOT, "assets", "soundfonts", "raw")
OUT_SF2 = os.path.join(ROOT, "assets", "soundfonts", "sarangi.sf2")

NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

# CC0 source previews (HQ mp3 on the public freesound CDN; deleted uploader id 1).
SOURCES = [
    {"id": 167023, "expect_midi": 60},  # C4
    {"id": 167088, "expect_midi": 68},  # G#4 (filename "G3" is wrong)
]
CDN = "https://cdn.freesound.org/previews/167/{id}_1-hq.mp3"

# The authored keyboard: match the harmonium's C2..D5 so any lehra note resolves.
LO_MIDI = 36   # C2
HI_MIDI = 74   # D5

LOOP_START_S = 1.2   # carve the loop from steady sustain, past the attack
LOOP_LEN_S = 0.6     # longer window -> slower repeat than the harmonium's 0.5s


def midi_to_freq(m: float) -> float:
    return 440.0 * 2 ** ((m - 69) / 12.0)


def fetch_decode(sid: int) -> tuple[np.ndarray, int]:
    """Fetch the CC0 preview mp3 (cached) and decode to 44.1k mono float."""
    os.makedirs(RAW_DIR, exist_ok=True)
    mp3 = os.path.join(RAW_DIR, f"sarangi_{sid}.mp3")
    wav = os.path.join(RAW_DIR, f"sarangi_{sid}.wav")
    if not os.path.exists(mp3):
        url = CDN.format(id=sid)
        print(f"fetching CC0 sarangi note {sid}: {url}")
        urllib.request.urlretrieve(url, mp3)
    if not os.path.exists(wav):
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", mp3,
                        "-ar", "44100", "-ac", "1", wav], check=True)
    x, sr = sf.read(wav)
    if x.ndim > 1:
        x = x.mean(axis=1)
    return x.astype(np.float64), sr


def measure_f0(x: np.ndarray, sr: int) -> float:
    """Autocorrelation fundamental over the steady sustain (robust to strong
    upper partials — an FFT peak can land on a harmonic, not the true pitch)."""
    seg = x[int(0.8 * sr):int(2.8 * sr)].copy()
    seg -= seg.mean()
    corr = np.correlate(seg, seg, "full")[len(seg) - 1:]
    tmin, tmax = int(sr / 500), int(sr / 60)  # 60..500 Hz search
    lag = tmin + int(np.argmax(corr[tmin:tmax]))
    return sr / lag


def resample_to_freq(x: np.ndarray, f0_src: float, f0_tgt: float) -> np.ndarray:
    """Resample x (played back at the same sr) so its fundamental becomes f0_tgt.

    new_len = len * f0_src / f0_tgt: fewer output samples raises pitch, more lowers
    it. Down-shift only lengthens (no aliasing), but the handful of notes above the
    top source up-shift (decimate) — pre-smooth those with a short moving average
    so the fold-down of high partials stays inaudible."""
    if f0_tgt > f0_src:  # up-shift -> anti-alias pre-filter
        k = max(1, int(round(f0_tgt / f0_src)))
        if k > 1:
            x = np.convolve(x, np.ones(k) / k, "same")
    n_out = int(round(len(x) * f0_src / f0_tgt))
    idx = np.linspace(0, len(x) - 1, n_out)
    return np.interp(idx, np.arange(len(x)), x)


def make_looped_sarangi(seg: np.ndarray, sr: int, midi: int):
    """Carve a steady, seamless sustain loop for a bowed tone (samplemode=1).

    Like build_harmonium.make_looped_sample, but first LEVEL-FLATTENS the loop
    window: the sources bake in a filtered-noise string resonance whose slow
    amplitude wander, looped as-is, pulses audibly once per loop. Dividing the
    window (plus its crossfade pre-roll) by its own smoothed envelope holds the bow
    at a constant level, so the repeat is inaudible. Returns (int16 pcm, loop_start,
    loop_end); we keep attack..loop_end and let the sampler loop [start,end]."""
    seg = seg.astype(np.float64).copy()
    fade_in = int(0.006 * sr)
    seg[:fade_in] *= np.linspace(0, 1, fade_in)

    period = sr / midi_to_freq(midi)
    s = int(LOOP_START_S * sr)
    loop_len = int(round(LOOP_LEN_S * sr / period) * period)  # whole periods
    e = s + loop_len
    if e + XFADE >= len(seg):                 # short (mild down-shift) -> shrink loop
        e = len(seg) - XFADE - 1
        s = max(int(0.6 * sr), e - loop_len)

    # flatten amplitude across the pre-roll..loop-end span to a constant level
    a = s - XFADE
    sm = np.convolve(np.abs(seg), np.ones(int(0.05 * sr)) / int(0.05 * sr), "same")
    sm = np.maximum(sm, 1e-6)
    seg[a:e] *= sm[a] / sm[a:e]

    # equal-power crossfade so the e -> s wrap is seamless
    fi = np.sqrt(np.linspace(0, 1, XFADE))
    fo = np.sqrt(np.linspace(1, 0, XFADE))
    seg[e - XFADE:e] = seg[e - XFADE:e] * fo + seg[s - XFADE:s] * fi

    seg = seg[:e + 1]
    rms = np.sqrt(np.mean(seg ** 2)) or 1.0
    seg *= TARGET_RMS / rms
    peak = np.max(np.abs(seg))
    if peak > 0.98:
        seg *= 0.98 / peak
    pcm = np.clip(seg * 32767.0, -32768, 32767).astype("<i2")
    return pcm, s, e


def main() -> int:
    srcs = []
    for s in SOURCES:
        x, sr = fetch_decode(s["id"])
        f0 = measure_f0(x, sr)
        midi = round(69 + 12 * np.log2(f0 / 440))
        note = f"{NAMES[midi % 12]}{midi // 12 - 1}"
        if midi != s["expect_midi"]:
            print(f"  WARNING: {s['id']} measured {note} (midi {midi}), "
                  f"expected midi {s['expect_midi']}", file=sys.stderr)
        srcs.append({"id": s["id"], "x": x, "sr": sr, "f0": f0, "midi": midi})
        print(f"  {s['id']}: {note} (midi {midi}), f0={f0:.1f}Hz, {len(x)/sr:.2f}s")

    sr = srcs[0]["sr"]
    # Pre-compensate the global pitch correction baked into build_sf2's shdr so
    # the SOUNDING pitch lands on exact 12-TET (shdr applies GLOBAL_TUNE_CENTS to
    # every zone; resample each note that many cents sharp to cancel it).
    precomp = 2 ** (-GLOBAL_TUNE_CENTS / 1200.0)

    samples = []
    for midi in range(LO_MIDI, HI_MIDI + 1):
        f_tgt = midi_to_freq(midi) * precomp
        # nearest source by pitch = smallest shift = least formant drift
        src = min(srcs, key=lambda s: abs(np.log2(s["f0"] / f_tgt)))
        res = resample_to_freq(src["x"], src["f0"], f_tgt)
        pcm, ls, le = make_looped_sarangi(res, sr, midi)
        samples.append({"pcm": pcm, "root": midi, "loop_start": ls,
                        "loop_end": le,
                        "name": f"Srng_{NAMES[midi % 12]}{midi // 12 - 1}"})

    # samplemode=1 (build_sf2's default): loop the sustain continuously, held for
    # the note's duration — the right envelope for a bowed, singing tone.
    build_sf2(samples, sr, OUT_SF2, inst_name="Sarangi")
    kb = os.path.getsize(OUT_SF2) // 1024
    print(f"wrote {OUT_SF2}  ({kb} KB, {len(samples)} looped zones, "
          f"C2..D5, tune {GLOBAL_TUNE_CENTS}c)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
