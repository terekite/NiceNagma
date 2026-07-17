"""Tiny HTTP render service — the production seam the app talks to.

POST /render  { RenderRequest }  ->  audio/wav

Renders are cached on disk by (nagma_hash, bpm, sa, instrument, avartans, seed),
mirroring the app-side cache key, so a repeat request is a file read. This is the
~100-line wrapper the spec (§5, option B) calls for.

Run locally:
    NAGMA_SOUNDFONT=assets/soundfonts/harmonium.sf2 \
        uv run uvicorn nagma_render.service.app:app --reload
"""

from __future__ import annotations

import hashlib
import json
import os

from nagma_core.parser import NagmaParseError, parse_nagma

from ..pipeline import render_request
from ..sampler import SamplerNotAvailable, fluidsynth_available

try:
    from fastapi import FastAPI, HTTPException
    from fastapi.responses import FileResponse
    from pydantic import BaseModel
except ModuleNotFoundError as e:  # pragma: no cover - env-dependent
    raise RuntimeError(
        "fastapi + uvicorn required to run the service. "
        "Install: `uv pip install -e render[service]`."
    ) from e

SOUNDFONT = os.environ.get("NAGMA_SOUNDFONT", "")
CACHE_DIR = os.environ.get("NAGMA_CACHE_DIR", "/tmp/nagma-cache")
os.makedirs(CACHE_DIR, exist_ok=True)

app = FastAPI(title="NiceNagma Render Service", version="0.1.0")


class RenderBody(BaseModel):
    schema_version: str = "1.0.0"
    nagma_text: str
    bpm: float
    sa: str
    instrument: str = "harmonium"
    taal: str = "teentaal"
    avartans: int = 4
    seed: int = 0
    format: str = "wav"


def _cache_key(body: RenderBody) -> str:
    h = hashlib.sha256()
    h.update(
        json.dumps(
            {
                "nagma": body.nagma_text.strip(),
                "bpm": body.bpm,
                "sa": body.sa,
                "instrument": body.instrument,
                "taal": body.taal,
                "avartans": body.avartans,
                "seed": body.seed,
            },
            sort_keys=True,
        ).encode()
    )
    return h.hexdigest()[:24]


@app.get("/health")
def health() -> dict:
    return {
        "ok": True,
        "fluidsynth": fluidsynth_available(),
        "soundfont": bool(SOUNDFONT) and os.path.exists(SOUNDFONT),
    }


@app.post("/render")
def render(body: RenderBody) -> FileResponse:
    if not SOUNDFONT or not os.path.exists(SOUNDFONT):
        raise HTTPException(503, "render service has no soundfont configured")

    key = _cache_key(body)
    out = os.path.join(CACHE_DIR, f"{key}.wav")
    if not os.path.exists(out):
        try:
            parse_nagma(body.nagma_text, taal=body.taal)  # fail fast, 422 on typo
        except NagmaParseError as e:
            raise HTTPException(422, f"nagma parse error: {e}") from None
        try:
            render_request(
                nagma_text=body.nagma_text,
                bpm=body.bpm,
                sa=body.sa,
                soundfont_path=SOUNDFONT,
                out_wav=out,
                taal=body.taal,
                avartans=body.avartans,
                seed=body.seed,
                instrument=body.instrument,
            )
        except SamplerNotAvailable as e:
            raise HTTPException(503, str(e)) from None

    return FileResponse(out, media_type="audio/wav", filename=f"{key}.wav")
