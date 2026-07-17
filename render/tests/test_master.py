"""Mastering tests. Skipped cleanly if numpy/soundfile aren't installed yet."""

import math

import pytest

np = pytest.importorskip("numpy")
sf = pytest.importorskip("soundfile")

from nagma_core.compiler import compile_score
from nagma_core.parser import parse_nagma
from nagma_render.master import master_loop

STOCK = "S r g m | P d P m | g m P d | P m g r"


def _score(bpm=137, avartans=2, sr=44100):
    # 137 BPM is a deliberate non-divisor so the loop length isn't a round number.
    return compile_score(parse_nagma(STOCK), bpm=bpm, sa="D", avartans=avartans, sample_rate=sr)


def _write_fake_render(path, score, overhang_s=0.4):
    """Simulate a fluidsynth render: loop_length + a decaying reverb tail."""
    n = score.loop_length_samples
    extra = int(overhang_s * score.sample_rate)
    t = np.arange(n + extra) / score.sample_rate
    sig = 0.3 * np.sin(2 * math.pi * 220 * t)
    # Fade the overhang so it reads like a natural tail.
    env = np.ones(n + extra)
    env[n:] = np.linspace(1, 0, extra)
    sig *= env
    sf.write(path, sig, score.sample_rate, subtype="PCM_16")


def test_mastered_loop_is_exact_length(tmp_path):
    score = _score()
    raw = tmp_path / "raw.wav"
    out = tmp_path / "loop.wav"
    _write_fake_render(str(raw), score)

    frames = master_loop(str(raw), str(out), score)
    assert frames == score.loop_length_samples

    data, sr = sf.read(str(out), always_2d=True)
    assert sr == score.sample_rate
    assert data.shape[0] == score.loop_length_samples


def test_short_render_is_padded_to_exact_length(tmp_path):
    score = _score(avartans=1)
    raw = tmp_path / "raw.wav"
    out = tmp_path / "loop.wav"
    # Render shorter than the loop -> must be zero-padded up to exact length.
    n = score.loop_length_samples
    sf.write(str(raw), np.zeros(n - 500), score.sample_rate, subtype="PCM_16")

    frames = master_loop(str(raw), str(out), score)
    assert frames == n
