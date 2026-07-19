#!/usr/bin/env python3
"""Continuous monophonic SARANGI voice — the "flowing, bowed, singing" synth.

The SF2/note-on model can't do what a sarangi does: it re-attacks every note and
jumps between discrete pitches. A real sarangi is one continuous bow whose pitch
GLIDES between notes (meend, because it's fretless) and sustains without
re-articulating. So for the melodic lehra line — which is monophonic — we resynth
it as a single continuous voice:

  * PITCH is a continuous contour: hold each note, then glide (meend) into the
    next; plus delayed vibrato. Fretless => you pass through every microtone.
  * AMPLITUDE is a legato bow: soft onset, sustained, only a gentle dip at note
    boundaries for definition (so you still hear the right NUMBER of notes) — no
    hard per-note attack.
  * TIMBRE is the REAL sarangi's harmonic fingerprint, sampled from a clean
    sustained note of the CC0 recording (so the vocal formants + bowed richness
    are authentic), driven by an additive oscillator that follows the contour.
  * Then bow-friction noise + the raga-tuned sympathetic halo + room (sarangi_dsp).

This is the audition/quality path (offline numpy). The on-device SF2 path is a
separate, later problem. Run scripts/render_sarangi_audition.py.
"""
from __future__ import annotations
import os, sys
sys.path[:0] = ["core/src", "render/src", "scripts"]
import numpy as np
import soundfile as sf
from scipy import signal
import sarangi_dsp as D

SR = 44100
GRAIN_WAV = "assets/soundfonts/raw/sarangi_real_816125.wav"
GRAIN_T0, GRAIN_T1, GRAIN_F0 = 5.30, 7.60, 588.0  # ~2.3s of steady real D5 (grain pool)


def midi_to_freq(m):
    return 440.0 * 2 ** ((np.asarray(m) - 69) / 12.0)


def harmonic_profile(n_harm=32):
    """Relative magnitudes of the real sarangi's first n_harm harmonics — the
    authentic bowed/vocal spectral envelope (formants baked in)."""
    x, sr = sf.read(GRAIN_WAV)
    x = x if x.ndim == 1 else x.mean(1)
    seg = x[int(GRAIN_T0 * sr):int(GRAIN_T1 * sr)].astype(np.float64)
    seg *= np.hanning(len(seg))
    n = 1 << int(np.ceil(np.log2(len(seg))))
    mag = np.abs(np.fft.rfft(seg, n))
    amps = []
    for h in range(1, n_harm + 1):
        k = h * GRAIN_F0 * n / sr
        lo, hi = int(k - 3), int(k + 4)
        amps.append(mag[lo:hi].max() if hi < len(mag) else 0.0)
    amps = np.array(amps)
    return amps / amps.max()


def build_contours(events, total_s, seed=0):
    """Continuous pitch (MIDI) + amplitude contours from the score events."""
    rng = np.random.RandomState(seed)
    n = int(total_s * SR)
    t = np.arange(n) / SR
    evs = sorted(events, key=lambda e: e.start_s)

    # --- pitch: SELECTIVE meend. Measured from the reference: only ~30% of the
    # time is truly gliding, ~40% is held. So glide on a MINORITY of transitions
    # (small intervals are likelier to be connected by a slide; big leaps and a
    # random share are ARTICULATED with a clean, quick re-bow) and vary the glide
    # length — a uniform glide-on-every-note is the "sci-fi portamento" tell. ----
    pitch = np.zeros(n)
    glide_at = np.zeros(n, dtype=bool)   # mark glide spans (for texturing later)
    starts = [e.start_s for e in evs] + [total_s]
    for i, e in enumerate(evs):
        pitch[int(e.start_s * SR):int(starts[i + 1] * SR)] = e.midi
    pitch[: int(evs[0].start_s * SR)] = evs[0].midi
    p = pitch.copy()
    for i in range(len(evs) - 1):
        tr = int(starts[i + 1] * SR)
        a, b = evs[i].midi, evs[i + 1].midi
        if a == b or tr + 1 >= n:
            continue
        interval = abs(b - a)
        this_dur = starts[i + 1] - evs[i].start_s
        next_dur = starts[i + 2] - starts[i + 1] if i + 2 < len(starts) else 1.0
        # probability of a connective glide: high for small steps, low for leaps
        pglide = 0.75 if interval <= 2 else (0.4 if interval <= 4 else 0.12)
        # a glide must fit inside BOTH the outgoing and incoming notes, and never
        # into an ultra-short (grace) note — that was the "slid too far / cut" glitch
        room = min(this_dur, next_dur)
        if rng.rand() < pglide and room > 0.12:       # MEEND: slide, varied length
            gl = int(min(0.05 + 0.09 * rng.rand(), 0.4 * room) * SR)
            if gl < 8 or tr - gl < 0:
                continue
            k = np.linspace(0, 1, gl)
            ease = k * k * (3 - 2 * k)                 # smoothstep: lands exactly on b
            p[tr - gl:tr] = a + (b - a) * ease
            glide_at[tr - gl:tr] = True
        else:                                         # ARTICULATE: quick clean move
            st = min(int(0.018 * SR), max(1, int(0.4 * room * SR)))
            if tr - st >= 0:
                p[tr - st:tr] = np.linspace(a, b, st)
    # --- vibrato: WIDE andolan on held notes (reference: ±40-60c, 5-6.5Hz,
    # delayed, varied) — a big part of the sarangi identity, and it animates the
    # otherwise-static held pitch so it doesn't read as an organ. Suppressed
    # during glides (you don't shake while sliding). --------------------------
    vib = np.zeros(n)
    for i, e in enumerate(evs):
        s0, s1 = int(e.start_s * SR), int(starts[i + 1] * SR)
        dur = (s1 - s0) / SR
        if dur < 0.30:
            continue
        # A MASTER (Ram Narayan et al.) holds a rock-steady, in-tune note and adds
        # only occasional, CONTROLLED andolan — not a wide wobble on every note
        # (that read as "out of tune and shaky, a beginner"). So: only ~40% of long
        # held notes get vibrato, subtle (±8-18c), slow, gently faded in.
        if dur < 0.45 or rng.rand() > 0.4:
            continue
        seg = np.arange(s1 - s0) / SR
        delay = 0.20 + 0.30 * rng.rand()                     # late, varied onset
        ramp = 0.25 + 0.20 * rng.rand()
        onset = np.clip((seg - delay) / ramp, 0, 1) ** 2
        rate = 4.3 + 1.2 * rng.rand()                        # ~4.3-5.5 Hz (unhurried)
        depth = 0.08 + 0.10 * rng.rand()                     # ±8-18c (tasteful)
        vib[s0:s1] = depth * onset * np.sin(2 * np.pi * rate * seg + rng.rand() * 6.28)
    vib[glide_at] *= 0.15
    p = p + vib

    # --- amplitude: legato bow (soft onset, sustained, boundary dip) ---------
    amp = np.zeros(n)
    for i, e in enumerate(evs):
        s0, s1 = int(e.start_s * SR), int(starts[i + 1] * SR)
        lvl = 0.55 + 0.45 * (e.velocity / 110.0)
        seg = np.ones(s1 - s0) * lvl
        att = min(int(0.05 * SR), (s1 - s0) // 2)
        if att > 0:
            seg[:att] *= (np.linspace(0, 1, att) ** 1.5)
        amp[s0:s1] = seg
    # deeper dip at ARTICULATED boundaries (re-bow), gentle at glides (connected)
    for i in range(1, len(evs)):
        bnd = int(evs[i].start_s * SR)
        w = int(0.028 * SR)
        if bnd - w < 0 or bnd + w >= n:
            continue
        floor = 0.75 if glide_at[max(0, bnd - w)] else 0.45
        dip = np.concatenate([np.linspace(1, floor, w), np.linspace(floor, 1, w)])
        amp[bnd - w:bnd + w] *= dip
    amp *= 1.0 - 0.06 * (0.5 + 0.5 * np.sin(2 * np.pi * 0.5 * t))
    return p, amp


_GRAIN_POOL = None


def _grain_pool():
    """A clean, pitch-stable slice of the REAL recording, mean-removed and lightly
    level-flattened, used as the granular texture source."""
    global _GRAIN_POOL
    if _GRAIN_POOL is None:
        x, sr = sf.read(GRAIN_WAV)
        x = x if x.ndim == 1 else x.mean(1)
        pool = x[int(GRAIN_T0 * sr):int(GRAIN_T1 * sr)].astype(np.float64)
        pool -= pool.mean()
        # gently flatten slow level drift so grains have consistent loudness
        env = np.convolve(np.abs(pool), np.ones(int(0.02 * sr)) / int(0.02 * sr), "same")
        pool = pool * (np.median(env) / np.maximum(env, 1e-6))
        _GRAIN_POOL = pool / (np.max(np.abs(pool)) or 1.0)
    return _GRAIN_POOL


def grain_synth(pitch, amp, seed=0, grain_ms=62.0, overlap=3):
    """Overlap-add grains of the real sarangi sustain, each resampled to the
    contour's instantaneous pitch. Grain source positions are period-quantized (so
    overlapping grains stay phase-coherent — no warble) and slowly drift through the
    pool with occasional jumps (so the texture never obviously repeats — no loop
    'bowed twice' pulse). This carries the REAL timbre while we own the pitch."""
    src = _grain_pool()
    rng = np.random.RandomState(seed + 11)
    n = len(pitch)
    Lg = int(grain_ms / 1000 * SR)
    Ho = max(1, Lg // overlap)
    win = np.hanning(Lg)
    P = SR / GRAIN_F0                                  # source pitch period (samples)
    f = midi_to_freq(pitch)
    out = np.zeros(n + Lg)
    base = rng.rand() * (len(src) - Lg * 4)            # drifting read pointer
    src_idx = np.arange(len(src))
    for og in range(0, n - 1, Ho):
        step = f[min(og + Lg // 2, n - 1)] / GRAIN_F0  # resample ratio -> target pitch
        span = Lg * step
        maxsp = len(src) - int(span) - 2
        if maxsp < 1:
            step = (len(src) - 2) / Lg
            span = Lg * step
            maxsp = 1
        # period-quantize the source start for phase-coherent overlap
        sp = int(min(base, maxsp) // P) * P
        idx = sp + np.arange(Lg) * step
        grain = np.interp(idx, src_idx, src) * win
        out[og:og + Lg] += grain
        base += 1.5 * P                                # drift ~1.5 periods per hop
        if base > maxsp or rng.rand() < 0.04:          # wrap / occasional jump
            base = rng.rand() * max(1, maxsp)
    out = out[:n]
    # normalize the raw grain sum, then apply the bow amplitude envelope
    out *= 1.0 / (np.sqrt(overlap) * (np.max(np.abs(win)) or 1.0))
    return out * amp


def synth(events, total_s, sa_midi, seed=0):
    p, amp = build_contours(events, total_s, seed)
    # GRANULAR resynthesis from the REAL recording — this is the whole point: the
    # timbre is actual bowed audio (real bow noise, formants, sympathetic ring),
    # not synthesized, so it can't read as a sine-swept "ghost". Pitch is fully
    # ours (meend + vibrato) via the contour; grains supply only texture.
    y = grain_synth(p, amp, seed)
    # real grains already carry bow noise/formants; add only a whisper of extra bite
    y = D.bow_noise(y, SR, level_db=-36)
    # sympathetic halo (raga-tuned) + room
    y = D.sympathetic(y, SR, sa_midi, wet=0.08)
    y = D.reverb(y, SR, wet=0.13)
    # seamless loop wrap: crossfade a short tail overhang onto the head
    w = int(0.035 * SR)
    fo = np.sqrt(np.linspace(1, 0, w)); fi = np.sqrt(np.linspace(0, 1, w))
    y[:w] = y[:w] * fi + y[-w:] * fo
    y = y[:-w]
    return D._normalize(y, 0.92)
