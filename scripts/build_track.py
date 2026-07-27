#!/usr/bin/env python3
"""Build the phase-locked demo soundtrack.

`simctl recordVideo` captures no audio, so the film is scored with separately
rendered harmonium loops. Because laya is machine-perfect, aligning one downbeat
(sam) per tempo segment to the on-screen cycle-wheel sam keeps the whole segment
locked. Sam anchor times are detected from the wheel sweep hand (see the sam
detector) and passed here as video-time grid anchors.

Each segment places its loop so loop-sample 0 (a downbeat) lands on its sam grid;
segments equal-power crossfade at the tempo/taal changes. The tanpura swells in
at the "Add the tanpura" beat. Output: demo/build/master.wav (video-length).

Usage: build_track.py <out.wav> <total_seconds>
"""
import sys
import numpy as np
import soundfile as sf

SR = 44100
OUT = sys.argv[1]
TOTAL = float(sys.argv[2])
A = "demo/audio"

n = int(round(TOTAL * SR))
t = np.arange(n) / SR
mix = np.zeros((n, 2), np.float32)


def load(name):
    d, sr = sf.read(f"{A}/{name}.wav", dtype="float32", always_2d=True)
    assert sr == SR, (name, sr)
    if d.shape[1] == 1:
        d = np.repeat(d, 2, axis=1)
    return d


def env(s, e, r):
    """Equal-power window over [s,e] with sqrt ramps of length r at both ends."""
    fin = np.clip((t - s) / r, 0, 1)
    fout = np.clip((e - t) / r, 0, 1)
    return (np.sqrt(fin) * np.sqrt(fout)).astype(np.float32)


def place(name, s, e, t0, r=0.45, gain=1.0):
    """Add loop `name` over [s,e], with loop-sample 0 landing on the grid t0
    (so a downbeat sits at t0, t0±period, …). Windowed with equal-power ramps."""
    loop = load(name)
    L = len(loop)
    global mix
    i0, i1 = max(0, int(s * SR)), min(n, int(e * SR))
    idx = np.arange(i0, i1)
    # sample offset into the loop for each output sample (t0 → loop[0])
    off = ((idx - int(t0 * SR)) % L)
    seg = loop[off] * env(s, e, r)[idx, None] * gain
    mix[i0:i1] += seg


# --- harmonium: one segment per on-screen (taal, tempo, key) state -------------
# windows overlap by the ramp so crossfades land on the re-render moments.
# Anchors are the wheel's sam times measured on the FINAL composite (the frame
# where the matra counter flips to 1). This already folds in the sweep-hand
# detector's ~1-frame lead and the composite's ~1-frame PTS offset, so the
# harmonium downbeat lands exactly on the wheel's beat 1 as the viewer sees it.
place("harm_tt_D80",  3.80, 20.55, 15.80)                 # Teentaal D vilambit (hero)
place("harm_tt_F80",  20.10, 25.95, 15.80)                # Teentaal F vilambit (Sa→F)
place("harm_tt_F300", 25.50, 39.15, 31.03)                # Teentaal F drut (tempo→drut)
place("harm_jt_F300", 38.70, TOTAL, 45.13)                # Jhaptaal F drut (taal→Jhaptaal)

# gentle master fade in at Play, out at the end (on top of the window ramps)
mfade = np.clip((t - 3.74) / 1.25, 0, 1) * np.clip((TOTAL - t) / 1.1, 0, 1)
mix *= mfade[:, None]

# --- tanpura F: enters at the "Add the tanpura" beat, drone (phase-agnostic) ----
tan = load("tanpura_F")
Lt = len(tan)
tstart = 30.0
tidx = np.arange(int(tstart * SR), n)
toff = (tidx - int(tstart * SR)) % Lt
tenv = (np.clip((t[tidx] - tstart) / 1.5, 0, 1) *
        np.clip((TOTAL - t[tidx]) / 1.1, 0, 1)).astype(np.float32)
mix[tidx] += tan[toff] * tenv[:, None] * 0.55

# --- master gain + soft limit --------------------------------------------------
mix *= 2.2
mix = np.tanh(mix * 0.8) / np.tanh(0.8)          # gentle soft clip, no hard peaks
peak = np.max(np.abs(mix))
if peak > 0.985:
    mix *= 0.985 / peak

sf.write(OUT, mix, SR)
print(f"wrote {OUT}  {TOTAL:.2f}s  peak={np.max(np.abs(mix)):.3f}")
