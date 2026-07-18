# NiceNagma

A tabla-practice **lehra/nagma** app: a melodic loop exactly one taal cycle long,
looped continuously so a tabla student can practice against it. The bet
(spec §1): a lehra is a fixed loop at a fixed tempo, so synthesis never needs to
be real-time — **render offline with heavy expressive processing, then loop the
rendered audio with sample accuracy on device.** Human-sounding harmonium,
machine-perfect laya. Any tempo/Sa change is a *re-render* (seconds), never a
time-stretch or pitch-shift.

MVP scope: Teentaal, Bhairavi, harmonium, tempo + Sa control, custom nagma via a
text grammar. iOS-first (TestFlight). See `nagma-app-planning-spec.md` (design of
record) and `CLAUDE.md`.

## Monorepo layout — four isolated packages

Packages communicate **only** through versioned JSON contracts and audio files —
never by importing each other's internals (enforced in review, spec §7).

| Package | What it is | Deps |
|---|---|---|
| `contracts/` | JSON Schemas: `NagmaDoc`, `ExpressiveScore`, `RenderRequest`. Single source of truth. | — |
| `core/` | Pure Python domain logic: taal defs, sargam text-grammar parser, compiler, performance model. Zero I/O. | none (stdlib) |
| `render/` | **The package that outputs the recording.** Sampler (fluidsynth) + loop mastering. CLI + HTTP service. Imports `core`; nothing imports `render`. | fluidsynth, numpy, soundfile |
| `app/` | Flutter app (iOS-first). Player UI, text entry, gapless loop playback. Talks to `render` over HTTP; caches renders. Knows nothing about synthesis. | Flutter |
| `assets/` | Soundfonts, tanpura loops, stock nagmas + `LICENSES.md`. | — |

The pipeline:
```
text nagma → NagmaDoc → ExpressiveScore (exact-time events + dynamics/legato)
           → performance model → sampler render → loop mastering (exact
             sample-length loop, seam wrap, loudness normalize) → cached WAV
```

## Two non-negotiable invariants (spec §)
1. **Machine-perfect laya.** Matra boundaries and *sam* are mathematically exact;
   micro-timing jitter is applied only to non-structural notes.
2. **Human timbre via pure code.** Jitter, taal-shaped dynamics, legato overlap,
   bellows amplitude undulation, and per-avartan variation — no ML in v1.

## Quickstart (Python pipeline)

```bash
# 1. Compile a text nagma to a score (pure stdlib, works today):
PYTHONPATH=core/src python3 -m nagma_core.cli \
    assets/nagmas/proposed-teentaal.nagma --bpm 80 --sa C --avartans 4 -o score.json

# 2. Render to a gapless loop WAV (needs fluidsynth + a soundfont):
brew install fluid-synth          # one-time
#   drop a harmonium SF2 into assets/soundfonts/ (see assets/soundfonts/README.md)
PYTHONPATH=core/src:render/src NAGMA_SOUNDFONT=assets/soundfonts/harmonium.sf2 \
    python3 -m nagma_render.cli score.json -o loop.wav

# End-to-end smoke test (the primary correctness gate — asserts EXACT loop length):
./scripts/smoke.sh
```

With `uv` (recommended once deps are needed):
```bash
uv sync                           # installs the workspace (core + render)
uv run nagma-compile assets/nagmas/proposed-teentaal.nagma --bpm 80 --sa C -o score.json
uv run nagma-render score.json -o loop.wav --soundfont assets/soundfonts/harmonium.sf2
```

## Tests
```bash
cd core   && PYTHONPATH=src pytest -q     # domain logic (no external deps)
cd render && pytest -q                    # mastering (needs numpy/soundfile)
./scripts/smoke.sh                        # end-to-end gate
```

## Status
`contracts` + `core` are implemented and tested. `render` is implemented; its
audio stage needs `fluidsynth` + a soundfont (both pending locally). `app` is
scaffolded (Flutter/Xcode not yet installed). See `CLAUDE.md` for current state.
