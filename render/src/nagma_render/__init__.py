"""nagma_render — the package that outputs the recording.

Imports nagma_core; NOTHING imports nagma_render. Exposes a CLI (nagma-render)
and an HTTP service (service/app.py) the app calls in production.
"""

from __future__ import annotations

from .pipeline import render_request, render_score
from .sampler import SamplerNotAvailable, fluidsynth_available

__all__ = [
    "render_score",
    "render_request",
    "fluidsynth_available",
    "SamplerNotAvailable",
]

__version__ = "0.1.0"
