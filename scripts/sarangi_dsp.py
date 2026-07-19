#!/usr/bin/env python3
"""Sarangi timbre DSP chain — the "make it sound bowed & vocal" post-processing.

Experimentation harness (NOT yet wired into render/master.py). Takes a DRY sarangi
render (real-sample SF2 through fluidsynth, no harmonium mastering) and applies the
chain the acoustics research prioritized:

  1. fixed (pitch-INDEPENDENT) vocal + body formants   -> kills the "wind/reed" read,
     adds the "closest to the human voice" quality
  2. sympathetic-string "halo": a resonator bank tuned to Sa + the raga swaras
     + a chromatic fill, driven by the dry signal, mixed low underneath -> the
     defining sarangi shimmer
  3. bow-friction noise, band-limited and correlated with the amplitude envelope
  4. gentle room reverb (presence)

Meend (pitch-glide) and per-note soft attack live in the render/MIDI stage (Stage 2),
not here. Run scripts/render_sarangi_audition.py to hear it.
"""

from __future__ import annotations

import numpy as np
from scipy import signal

# Bhairavi swaras as semitone offsets from Sa (komal re/ga/dha/ni): S r g m P d n
BHAIRAVI = [0, 1, 3, 5, 7, 8, 10]


# --------------------------------------------------------------------------- #
# biquads
# --------------------------------------------------------------------------- #
def _peaking(sr, f0, gain_db, q):
    """RBJ peaking-EQ biquad (fixed frequency, does NOT transpose with pitch)."""
    w0 = 2 * np.pi * f0 / sr
    a = 10 ** (gain_db / 40)
    alpha = np.sin(w0) / (2 * q)
    cw = np.cos(w0)
    b = [1 + alpha * a, -2 * cw, 1 - alpha * a]
    a_ = [1 + alpha / a, -2 * cw, 1 - alpha / a]
    return np.array(b) / a_[0], np.array(a_) / a_[0]


def formant_eq(x, sr):
    """Overlay fixed body + vowel ("aa") formants + a vocal-projection 'ring'.
    Frequencies stay put as pitch changes — that fixed-formant cue is what reads
    as a vocal tract rather than a transposed sample."""
    stages = [
        (300, 4.0, 3.5),    # wooden/skin body
        (700, 3.0, 3.5),    # body
        (830, 5.0, 4.5),    # vowel F1 (aa)
        (1170, 4.0, 5.0),   # vowel F2 (aa)
        (2700, 8.0, 2.0),   # the "ring" / singer's-formant band
        (5500, 3.0, 1.5),   # air / bow-scrape brightness (bowed vs. reed cue)
    ]
    y = x
    for f0, g, q in stages:
        b, a = _peaking(sr, f0, g, q)
        y = signal.lfilter(b, a, y)
    return y


# --------------------------------------------------------------------------- #
# sympathetic-string halo: a bank of high-Q two-pole resonators
# --------------------------------------------------------------------------- #
def _resonator(sr, f0, r):
    """Two-pole resonator H(z)=g/(1 - 2r cosθ z^-1 + r^2 z^-2), unity peak gain."""
    theta = 2 * np.pi * f0 / sr
    a = [1.0, -2 * r * np.cos(theta), r * r]
    g = (1 - r) * np.sqrt(1 - 2 * r * np.cos(2 * theta) + r * r)  # ~peak normalize
    return [g], a


def sympathetic(x, sr, sa_midi, wet=0.10, r=0.9994):
    """Raga-tuned sympathetic halo. Tarab strings ring in sympathy with what's
    played, blooming AFTER the bow and decaying slowly (r near 1 -> multi-second
    T60). One chromatic bank (something always answers) + emphasis on Sa and the
    Bhairavi swaras across the sarangi's registers. Retuned per Sa (this app
    re-renders per key, so the bank tracks the tonic exactly)."""
    def midi_to_f(m):
        return 440.0 * 2 ** ((m - 69) / 12.0)

    # string pitches: full chromatic octave around the mid register + raga swaras
    # emphasized over three octaves (duplicates fine — they just reinforce).
    strings = set()
    for m in range(sa_midi - 12, sa_midi + 13):          # chromatic fill
        strings.add(m)
    for octave in (-12, 0, 12, 24):                       # raga emphasis banks
        for off in BHAIRAVI:
            strings.add(sa_midi + octave + off)
    strings = [m for m in sorted(strings) if 30 <= m <= 96]

    halo = np.zeros_like(x)
    for m in strings:
        f0 = midi_to_f(m)
        # higher strings decay a touch faster (natural); nudge r down with pitch
        rr = r - min(0.0008, (m - sa_midi) * 0.00002) if m > sa_midi else r
        b, a = _resonator(sr, f0, max(0.99, rr))
        halo += signal.lfilter(b, a, x)
    halo /= max(1, np.sqrt(len(strings)))                 # tame the sum
    # one-pole damping so the halo isn't harsh on top
    halo = signal.lfilter(*signal.butter(1, 6000 / (sr / 2), "low"), halo)
    peak = np.max(np.abs(halo)) or 1.0
    halo *= (np.max(np.abs(x)) or 1.0) / peak             # match level, then mix low
    return (1 - wet) * x + wet * halo


# --------------------------------------------------------------------------- #
# bow-friction noise
# --------------------------------------------------------------------------- #
def bow_noise(x, sr, level_db=-30.0, seed=1):
    """Band-passed friction noise correlated with the amplitude envelope — a
    strong 'bowed, not blown' cue. Deterministic (seed) so renders stay cacheable."""
    rng = np.random.RandomState(seed)
    n = rng.standard_normal(len(x))
    b, a = signal.butter(2, [2000 / (sr / 2), 8000 / (sr / 2)], "band")
    n = signal.lfilter(b, a, n)
    # amplitude envelope of the tone (50 ms), slightly gritty (a little AM)
    env = np.abs(signal.lfilter(*signal.butter(1, 20 / (sr / 2), "low"), np.abs(x)))
    env /= (env.max() or 1.0)
    grit = 0.7 + 0.3 * (0.5 + 0.5 * np.sin(2 * np.pi * 47 * np.arange(len(x)) / sr))
    return x + n * env * grit * (10 ** (level_db / 20))


# --------------------------------------------------------------------------- #
# room reverb (simple exponential-noise IR convolution)
# --------------------------------------------------------------------------- #
def reverb(x, sr, seconds=0.6, wet=0.14, seed=2):
    rng = np.random.RandomState(seed)
    n = int(seconds * sr)
    ir = rng.standard_normal(n) * np.exp(-np.linspace(0, 6, n))
    ir[0] = 1.0
    wet_sig = signal.fftconvolve(x, ir)[: len(x)]
    wet_sig /= (np.max(np.abs(wet_sig)) or 1.0)
    wet_sig *= (np.max(np.abs(x)) or 1.0)
    return (1 - wet) * x + wet * wet_sig


def _normalize(x, peak=0.92):
    p = np.max(np.abs(x)) or 1.0
    return x * (peak / p)


def process(x, sr, sa_midi, *, formants=True, halo=True, bow=True, room=True):
    """Full chain. sa_midi = the tonic MIDI (for the raga-tuned halo)."""
    y = x.astype(np.float64)
    if formants:
        y = formant_eq(y, sr)
    if halo:
        y = sympathetic(y, sr, sa_midi)
    if bow:
        y = bow_noise(y, sr)
    if room:
        y = reverb(y, sr)
    return _normalize(y)
