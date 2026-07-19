"""Loop mastering: turn a raw fluidsynth render into a gapless, exact-length loop.

Three jobs, in order:
  1. Seam wrap. fluidsynth renders past the musical end (release + reverb tail).
     We trim to exactly `loop_length_samples` and mix the overhang back onto the
     head, so the tail of cycle N resolves into the sam of cycle 1 with no click.
  2. Bellows LFO. A slow gain undulation, snapped to an integer number of cycles
     across the loop so it too is seamless.
  3. Loudness normalize. -16 LUFS via pyloudnorm when available, else peak.

The output length is asserted to equal loop_length_samples exactly — this is the
render pipeline's primary correctness gate.
"""

from __future__ import annotations

import math

from nagma_core.models import ExpressiveScore

# Max overhang (seconds) to wrap from the tail onto the head.
_MAX_WRAP_S = 0.6

# Convolution room reverb: subtle "in the room with you" presence. Applied
# circularly so the loop stays exact-length and seamless. seed keeps it
# deterministic/cacheable. Set wet=0 to disable.
REVERB = {"seconds": 0.5, "wet": 0.08, "seed": 1}

# Double-reed shimmer: real harmoniums have 2-3 slightly-detuned reeds per note
# that beat against each other. We fake it with a subtle chorus (modulated
# fractional delay), read circularly so the loop stays exact/seamless. Each LFO
# runs a whole number of cycles across the loop. Set wet=0 to disable.
CHORUS = {
    "wet": 0.2,
    "voices": [
        {"base_ms": 12.0, "depth_ms": 2.5, "rate_hz": 0.7, "phase": 0.0},
        {"base_ms": 19.0, "depth_ms": 3.0, "rate_hz": 1.1, "phase": 1.7},
    ],
}

# Bowed strings want room, not reed-beating: the sarangi preset uses a wetter,
# slightly longer room and DROPS the harmonium's double-reed chorus + bellows LFO.
SARANGI_REVERB = {"seconds": 0.7, "wet": 0.16, "seed": 1}


def _lazy_imports():
    try:
        import numpy as np
        import soundfile as sf
    except ModuleNotFoundError as e:  # pragma: no cover - env-dependent
        raise RuntimeError(
            "numpy and soundfile are required for mastering. Install render "
            "deps: `uv pip install -e render[dev]`."
        ) from e
    return np, sf


def master_loop(in_wav: str, out_wav: str, score: ExpressiveScore) -> int:
    """Master `in_wav` into a seamless loop at `out_wav`. Returns frame count."""
    np, sf = _lazy_imports()

    audio, sr = sf.read(in_wav, always_2d=True, dtype="float64")
    if sr != score.sample_rate:
        raise ValueError(
            f"Rendered sample rate {sr} != score sample rate {score.sample_rate}."
        )

    # Bowed strings master differently from the reed harmonium (see SARANGI_REVERB).
    sarangi = getattr(score, "instrument", "") == "sarangi"

    n = score.loop_length_samples
    m = audio.shape[0]

    if m < n:
        pad = np.zeros((n - m, audio.shape[1]), dtype=audio.dtype)
        body = np.concatenate([audio, pad], axis=0)
    else:
        body = audio[:n].copy()
        # Wrap the natural overhang (tail past the loop point) onto the head.
        wrap = min(m - n, int(_MAX_WRAP_S * sr), n)
        if wrap > 0:
            tail = audio[n:n + wrap]
            # Equal-power fade of the wrapped tail so it dies into the head.
            fade = np.cos(np.linspace(0, math.pi / 2, wrap)) ** 2
            body[:wrap] += tail * fade[:, None]

    # --- bellows LFO, snapped to whole cycles for seamlessness --------------
    depth = 0.0 if sarangi else float(score.bellows.get("depth", 0.0))
    rate = float(score.bellows.get("rate_hz", 0.25))
    if depth > 0:
        cycles = max(1, round(rate * score.loop_length_s))
        t = np.arange(n) / sr
        lfo = (1.0 - depth) + depth * (0.5 + 0.5 * np.sin(
            2 * math.pi * cycles / score.loop_length_s * t
        ))
        body *= lfo[:, None]

    # --- double-reed shimmer (harmonium chorus), before the room ------------
    # Skip it for the sarangi — a bowed string has no paired reeds to beat.
    if CHORUS["wet"] > 0 and not sarangi:
        body = _chorus(np, body, sr, CHORUS)

    # --- room presence: convolution reverb, circular so the loop stays exact -
    rev = SARANGI_REVERB if sarangi else REVERB
    if rev["wet"] > 0:
        body = _apply_reverb(np, body, sr, rev)

    # --- loudness normalize -------------------------------------------------
    body = _normalize(np, body, sr)

    sf.write(out_wav, body, sr, subtype="PCM_16")
    assert body.shape[0] == n, "mastered loop length must equal loop_length_samples"
    return body.shape[0]


def _room_ir(np, sr: int, seconds: float, seed: int):
    """Procedurally generate a small stereo room impulse response (CC0-free).

    A few early reflections + a decorrelated, low-passed, exponentially-decaying
    diffuse tail per channel. Deterministic given the seed, so renders stay
    byte-reproducible (cacheable).
    """
    length = int(seconds * sr)
    rng = np.random.default_rng(seed)
    ir = np.zeros((length, 2))

    # sparse early reflections (ms -> samples), slightly different per channel
    for ch in range(2):
        taps = [(0.011, 0.6), (0.019, 0.45), (0.027, 0.5), (0.038, 0.32),
                (0.053, 0.28), (0.071, 0.22)]
        for t_s, g in taps:
            idx = int((t_s + rng.uniform(-0.002, 0.002)) * sr)
            if 0 < idx < length:
                ir[idx, ch] += g * (1.0 + rng.uniform(-0.15, 0.15))

    # diffuse tail: decorrelated noise * exponential decay, gently low-passed
    t = np.arange(length) / sr
    decay = np.exp(-t / (seconds * 0.33))
    for ch in range(2):
        noise = rng.standard_normal(length) * decay * 0.5
        k = np.hanning(9); k /= k.sum()           # mild high-freq rolloff (room absorbs highs)
        ir[:, ch] += np.convolve(noise, k, mode="same")

    ir[0, :] = 1.0                                 # keep the direct sound (dry) intact
    return ir


def _chorus(np, audio, sr: int, params: dict):
    """Subtle double-reed shimmer via modulated fractional delay (chorus).

    Each voice reads the signal at a slowly-modulated delay; the pitch wobble it
    creates beats against the dry signal like a harmonium's paired reeds. Reads
    are circular (mod N) and each LFO completes a whole number of cycles across
    the loop, so the output stays exactly loop-length and seamless.
    """
    wet = float(params["wet"])
    n = audio.shape[0]
    loop_s = n / sr
    idx = np.arange(n)
    chorused = np.zeros_like(audio)
    voices = params["voices"]
    for v in voices:
        cycles = max(1, round(v["rate_hz"] * loop_s))         # whole cycles -> seamless
        lfo = np.sin(2 * math.pi * cycles * idx / n + v["phase"])
        delay = (v["base_ms"] + v["depth_ms"] * lfo) * sr / 1000.0
        read = (idx - delay) % n
        i0 = np.floor(read).astype(np.int64)
        frac = (read - i0)[:, None]
        i1 = (i0 + 1) % n
        chorused += audio[i0] * (1.0 - frac) + audio[i1] * frac
    chorused /= len(voices)
    return (1.0 - wet) * audio + wet * chorused


def _apply_reverb(np, audio, sr: int, params: dict):
    """Add convolution reverb via CIRCULAR convolution (length-preserving).

    Circular convolution means the reverb tail from the end of the loop folds
    into its head — exactly right for a seamless loop, and it keeps the output
    length == input length so the exact-loop-length gate still holds.
    """
    n = audio.shape[0]
    ir = _room_ir(np, sr, params["seconds"], params["seed"])
    wet = float(params["wet"])
    out = audio.copy()
    for ch in range(audio.shape[1]):
        ir_ch = ir[:, ch % ir.shape[1]]
        irp = np.zeros(n)
        m = min(len(ir_ch), n)
        irp[:m] = ir_ch[:m]
        conv = np.fft.irfft(np.fft.rfft(audio[:, ch]) * np.fft.rfft(irp), n=n)
        out[:, ch] = (1.0 - wet) * audio[:, ch] + wet * conv
    return out


def _normalize(np, audio, sr: int):
    """Normalize to -16 LUFS (pyloudnorm) or peak to -1 dBFS as fallback."""
    try:
        import pyloudnorm as pyln

        meter = pyln.Meter(sr)
        loudness = meter.integrated_loudness(audio)
        if math.isfinite(loudness):
            gained = pyln.normalize.loudness(audio, loudness, -16.0)
            peak = float(np.max(np.abs(gained))) or 1.0
            if peak > 0.999:  # guard against clipping after LUFS gain
                gained *= 0.999 / peak
            return gained
    except ModuleNotFoundError:
        pass

    peak = float(np.max(np.abs(audio))) or 1.0
    target = 10 ** (-1.0 / 20.0)  # -1 dBFS
    return audio * (target / peak)
