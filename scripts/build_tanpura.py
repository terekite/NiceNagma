#!/usr/bin/env python3
"""Build a plucked-string tanpura SF2 from CC0 single-note recordings.

Source: three CC0 (public-domain) tanpura string plucks by freesound user
luckylittleraven, pack "Tanpura C Sharp" (#23512). Each is one clean acoustic
pluck with the full jawari overtone bloom and natural decay:

  416605  Tanpura note C sharp      -> mid Sa   (C#3, MIDI 49)
  416598  Tanpura note G sharp      -> Pa string (G#2, MIDI 44 = Sa-5)
  416597  Tanpura note Low C sharp  -> kharaj    (C#2, MIDI 37 = Sa-12)

The three roots form a consistent C# tanpura (Pa = Sa-5, kharaj = Sa-12), so the
whole set transposes uniformly to any key by pitch-shifting in the sampler.

We slice each to a clean one-shot (keep the full decay — NO loop), loudness-match
them, and author a 3-zone NON-LOOPING SF2 (GEN_SAMPLEMODES=0) partitioned by pitch
at the root midpoints. The app's Dart tanpura sequencer (app/lib/render/tanpura.dart)
plays the 4-string Pa-Sa-Sa-kharaj cycle through this SF2 with humanized timing;
the native offline renderer masters it into a seamless loop.

Unlike the old build (a looped harmonium *drone* — the wrong instrument), this is a
real plucked tanpura. Reuses build_harmonium.build_sf2 (extended for one-shots).

Usage:  .venv/bin/python scripts/build_tanpura.py
"""

from __future__ import annotations

import os
import subprocess
import sys
import urllib.request

import numpy as np
import soundfile as sf

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_harmonium import build_sf2  # noqa: E402  (reuse the SF2 writer)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW_DIR = os.path.join(ROOT, "assets", "soundfonts", "raw")
OUT_SF2 = os.path.join(ROOT, "assets", "soundfonts", "tanpura.sf2")

# CC0 source previews (HQ mp3 on the public freesound CDN; uploader id 2112203).
# The strings, low -> high pitch: kharaj (C#2), Pa (G#2), mid Sa (C#3).
NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
STRINGS = [
    {"id": 416597, "role": "kharaj", "expect": 37},   # C#2
    {"id": 416598, "role": "Pa", "expect": 44},        # G#2
    {"id": 416605, "role": "midSa", "expect": 49},     # C#3
]
CDN = "https://cdn.freesound.org/previews/416/{id}_2112203-hq.mp3"

TARGET_RMS = 0.13     # per-sample loudness match (headroom for many overlapping voices)
FADE_IN_S = 0.025     # gentle onset (audible as a distinct note, but not plucky) —
                      # the mixer applies the per-note decay envelope on top of this
TAIL_FLOOR_DB = -46   # trim the sample once its natural decay falls below this


def fetch_decode(sid: int) -> tuple[np.ndarray, int]:
    """Fetch the CC0 preview mp3 (cached) and decode to 44.1k mono float."""
    os.makedirs(RAW_DIR, exist_ok=True)
    mp3 = os.path.join(RAW_DIR, f"tanpura_{sid}.mp3")
    wav = os.path.join(RAW_DIR, f"tanpura_{sid}.wav")
    if not os.path.exists(mp3):
        url = CDN.format(id=sid)
        print(f"fetching CC0 pluck {sid}: {url}")
        urllib.request.urlretrieve(url, mp3)
    if not os.path.exists(wav):
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", mp3,
                        "-ar", "44100", "-ac", "1", wav], check=True)
    x, sr = sf.read(wav)
    if x.ndim > 1:
        x = x.mean(axis=1)
    return x.astype(np.float64), sr


def measure_f0(x: np.ndarray, sr: int) -> float:
    """Autocorrelation fundamental — robust to the tanpura's strong upper partials
    (an FFT peak lands on a jawari overtone, not the string's true pitch)."""
    seg = x[int(0.4 * sr):int(1.4 * sr)].copy()
    seg -= seg.mean()
    corr = np.correlate(seg, seg, "full")[len(seg) - 1:]
    tmin, tmax = int(sr / 250), int(sr / 50)  # 50..250 Hz search
    lag = tmin + int(np.argmax(corr[tmin:tmax]))
    return sr / lag


def make_natural(x: np.ndarray, sr: int):
    """Keep the REAL recorded pluck: trim pre-attack silence, a gentle fade-in, and
    the full NATURAL jawari decay — no looping/tiling/flattening. Faking sustain by
    looping a window adds a periodic ~1 s tremolo and sounds processed; the actual
    recording rings and shimmers naturally. The mixer shapes the per-note decay and
    relies on overlap for continuity. Trims the near-silent tail. Returns int16 PCM."""
    env = np.abs(x)
    thr = env.max() * 0.02
    onset = int(np.argmax(env > thr))
    onset = max(0, onset - int(0.003 * sr))
    seg = x[onset:].copy()

    fade = int(FADE_IN_S * sr)
    if fade > 0:
        seg[:fade] *= np.linspace(0, 1, fade)

    # Trim once the natural decay falls below the floor (drop noisy near-silent tail).
    sm = np.convolve(np.abs(seg), np.ones(int(0.05 * sr)) / int(0.05 * sr), "same")
    floor = sm.max() * 10 ** (TAIL_FLOOR_DB / 20)
    above = np.where(sm > floor)[0]
    if len(above):
        end = min(len(seg), above[-1] + int(0.1 * sr))
        seg = seg[:end]
    seg[-int(0.05 * sr):] *= np.linspace(1, 0, int(0.05 * sr))  # anti-click tail

    rms = np.sqrt(np.mean(seg ** 2)) or 1.0
    seg *= TARGET_RMS / rms
    peak = np.max(np.abs(seg))
    if peak > 0.98:
        seg *= 0.98 / peak

    return np.clip(seg * 32767.0, -32768, 32767).astype("<i2")


def main() -> int:
    processed = []
    for s in STRINGS:
        x, sr = fetch_decode(s["id"])
        f0 = measure_f0(x, sr)
        midi = round(69 + 12 * np.log2(f0 / 440))
        note = f"{NAMES[midi % 12]}{midi // 12 - 1}"
        if midi != s["expect"]:
            print(f"  WARNING: {s['id']} measured {note} (midi {midi}), "
                  f"expected midi {s['expect']}", file=sys.stderr)
        pcm = make_natural(x, sr)
        processed.append({
            "id": s["id"], "role": s["role"], "root": midi, "note": note,
            "pcm": pcm, "sr": sr, "dur": len(pcm) / sr,
        })
        print(f"  {s['id']} {s['role']:>6}: {note} (midi {midi}), "
              f"natural {len(pcm) / sr:.1f}s, f0={f0:.1f}Hz")

    processed.sort(key=lambda p: p["root"])  # ascending root for key-range tiling
    sr = processed[0]["sr"]

    # Partition the keyboard at the midpoints between adjacent roots so any
    # requested note picks the nearest-pitched sample (smallest pitch shift).
    samples = []
    for i, p in enumerate(processed):
        lo = 0 if i == 0 else (processed[i - 1]["root"] + p["root"]) // 2 + 1
        hi = 127 if i == len(processed) - 1 else (p["root"] + processed[i + 1]["root"]) // 2
        samples.append({
            "pcm": p["pcm"], "root": p["root"], "lo": lo, "hi": hi,
            "loop_start": 1, "loop_end": len(p["pcm"]) - 1,  # unused (samplemode 0)
            "name": f"Tanpura_{p['note']}",
        })

    # The SF2 is only a container for the natural sample DATA now — the tanpura is
    # synthesized by the Dart mixer (tanpura_mixer.dart), not this sampler.
    build_sf2(samples, sr, OUT_SF2, inst_name="Tanpura", samplemode=0)
    kb = os.path.getsize(OUT_SF2) // 1024
    roots = ", ".join(f"{s['name']}({s['root']}) keys {s['lo']}-{s['hi']}" for s in samples)
    print(f"wrote {OUT_SF2}  ({kb} KB, {len(samples)} natural zones)")
    print(f"  zones: {roots}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
