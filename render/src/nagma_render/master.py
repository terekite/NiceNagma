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
    depth = float(score.bellows.get("depth", 0.0))
    rate = float(score.bellows.get("rate_hz", 0.25))
    if depth > 0:
        cycles = max(1, round(rate * score.loop_length_s))
        t = np.arange(n) / sr
        lfo = (1.0 - depth) + depth * (0.5 + 0.5 * np.sin(
            2 * math.pi * cycles / score.loop_length_s * t
        ))
        body *= lfo[:, None]

    # --- loudness normalize -------------------------------------------------
    body = _normalize(np, body, sr)

    sf.write(out_wav, body, sr, subtype="PCM_16")
    assert body.shape[0] == n, "mastered loop length must equal loop_length_samples"
    return body.shape[0]


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
