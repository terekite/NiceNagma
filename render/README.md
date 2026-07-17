# render/ — the package that outputs the recording

Imports `nagma_core`; **nothing imports `nagma_render`.** Turns an
`ExpressiveScore` into a gapless, exact-sample-length loop WAV.

## Pipeline
```
ExpressiveScore → MIDI (midi.py) → raw WAV (sampler.py, fluidsynth)
               → mastered loop (master.py: seam wrap + bellows LFO + loudness)
```
`master_loop` asserts the output is exactly `loop_length_samples` frames — the
gapless guarantee. fluidsynth is isolated in `sampler.py` (swap for sfizz or an
on-device lib by touching one file).

## Requirements
- `fluidsynth` on PATH (macOS: `brew install fluid-synth`).
- A harmonium soundfont (see `../assets/soundfonts/README.md`).
- Python deps: `numpy`, `soundfile`, `mido`; optional `pyloudnorm` (better
  loudness, falls back to peak-normalize).

## CLI
```bash
nagma-render score.json -o loop.wav --soundfont ../assets/soundfonts/harmonium.sf2
# or set NAGMA_SOUNDFONT and omit --soundfont
```

## HTTP service (production seam)
```bash
NAGMA_SOUNDFONT=../assets/soundfonts/harmonium.sf2 \
    uv run uvicorn nagma_render.service.app:app --port 8000
# POST /render { RenderRequest } -> audio/wav ; GET /health
```
Docker: `docker build -f service/Dockerfile ..` (build context = repo root).

## Test
```bash
pytest -q          # mastering tests; skip cleanly without numpy/soundfile
```
