"""End-to-end render orchestration: ExpressiveScore -> gapless loop WAV.

    score -> MIDI (midi.py) -> raw WAV (sampler.py) -> mastered loop (master.py)

Also provides the compile+render convenience used by the HTTP service:
    render_request(...) -> WAV path, driving core's parser/compiler first.
"""

from __future__ import annotations

import os
import tempfile

from nagma_core.compiler import compile_score
from nagma_core.models import ExpressiveScore
from nagma_core.parser import parse_nagma

from .master import master_loop
from .midi import score_to_midi
from .sampler import render_midi_to_wav


def render_score(
    score: ExpressiveScore,
    soundfont_path: str,
    out_wav: str,
    *,
    keep_intermediates: bool = False,
) -> str:
    """Render a compiled score to a mastered, gapless loop WAV."""
    tmpdir = tempfile.mkdtemp(prefix="nagma-render-")
    midi_path = os.path.join(tmpdir, "score.mid")
    raw_wav = os.path.join(tmpdir, "raw.wav")

    score_to_midi(score, midi_path)
    render_midi_to_wav(
        midi_path, soundfont_path, raw_wav, sample_rate=score.sample_rate
    )
    master_loop(raw_wav, out_wav, score)

    if not keep_intermediates:
        for p in (midi_path, raw_wav):
            try:
                os.remove(p)
            except OSError:
                pass
        try:
            os.rmdir(tmpdir)
        except OSError:
            pass
    return out_wav


def render_request(
    *,
    nagma_text: str,
    bpm: float,
    sa: str,
    soundfont_path: str,
    out_wav: str,
    taal: str = "teentaal",
    avartans: int = 4,
    seed: int = 0,
    instrument: str = "harmonium",
) -> str:
    """Parse -> compile -> render, the path the HTTP service takes."""
    doc = parse_nagma(nagma_text, taal=taal)
    score = compile_score(
        doc, bpm=bpm, sa=sa, avartans=avartans, seed=seed, instrument=instrument
    )
    return render_score(score, soundfont_path, out_wav)
