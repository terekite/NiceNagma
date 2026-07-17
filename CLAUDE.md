# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Status

**Phase 1 landed: render pipeline is real and tested.** The design of record is `nagma-app-planning-spec.md` (Draft v0.3) — a 3-day-sprint plan for a tabla-practice lehra/nagma app. iOS-first (TestFlight); Android deferred. Current state of the monorepo:

- `contracts/` — the three JSON Schemas (`NagmaDoc`, `ExpressiveScore`, `RenderRequest`) are written and frozen.
- `core/` — **implemented and tested** (18 tests, pure stdlib): taal defs, sargam parser, compiler, performance model, `nagma-compile` CLI.
- `render/` — **implemented and renders end-to-end**; mastering tested (`master.py`, seam-wrap + bellows + loudness). fluidsynth call isolated behind `sampler.py`. `nagma-render` CLI + FastAPI service + Dockerfile present. `./scripts/smoke.sh` produces a real WAV (verified: Bhairavi/D/80 BPM/4 avartans → exactly 2,116,800 frames, RMS 0.107).
- `app/` — **scaffolded only** (Flutter). Real project not bootstrapped yet (Flutter/Xcode not installed). The render HTTP client (`lib/services/render_client.dart`) is the one implemented seam.
- `assets/` — dir structure + `LICENSES.md` + stock Bhairavi nagma + **bundled CC-BY 4.0 `soundfonts/harmonium.sf2`** (Musical Artifacts #2127, preset at bank 0/program 20; re-fetch via `./scripts/fetch_soundfont.sh`).

The audio stage needs `fluidsynth` on PATH (macOS: `brew install fluid-synth`) plus the Python render deps (`mido`, `numpy`, `soundfile`); the soundfont is now committed. Treat the spec as source of truth and keep this file current as packages evolve.

## What the product is

Tabla students practice against a *lehra/nagma*: a melodic phrase exactly one taal cycle long, looped continuously. Existing apps are either recorded loops (good timbre, imperfect timing, no custom input) or robotic MIDI (perfect timing, dead sound).

**Core thesis — the whole architecture follows from this:** a lehra is a fixed loop at a fixed tempo, so synthesis never needs to be real-time. Render *offline* with heavy expressive processing, then loop the rendered audio with sample accuracy on device. Any change to tempo or Sa (key) is a **re-render** (seconds), never time-stretch or pitch-shift of existing audio.

MVP scope is deliberately tiny: Teentaal only, one raag (Bhairavi), harmonium only, tempo + Sa control, and custom nagma entry via a text grammar.

## Architecture — monorepo, four isolated packages

One repo, four packages that communicate **only** through versioned JSON contracts and audio artifacts — never by importing each other's internals.

```
contracts/   JSON Schemas: NagmaDoc, ExpressiveScore, RenderRequest. Single source
             of truth. Frozen after Day-1 morning; schema changes must be justified.
core/        Pure domain logic, zero I/O (Python). Taal defs, sargam text-grammar
             parser -> NagmaDoc, compiler (NagmaDoc + BPM + Sa -> ExpressiveScore),
             performance model (jitter, dynamics, legato, per-avartan variation).
render/      THE package that outputs the recording. Sampler wrapper
             (fluidsynth/sfizz) + loop mastering. Exposes a CLI and an HTTP service
             (Docker). Imports core; nothing imports render.
app/         Flutter mobile app. Player UI, text-grammar entry, local library,
             native gapless loop playback (FFI), audio-clock -> UI sync. Talks to
             render over HTTP; caches by (nagma-hash, BPM, Sa, instrument). Knows
             nothing about synthesis.
assets/      Soundfonts, tanpura loops, stock nagmas. LICENSES.md per file.
```

**Isolation rules — the discipline that keeps the seams clean (enforce these in review):**
- `app` never imports `core` or `render`. It speaks only JSON-over-HTTP and plays audio files.
- `render` imports `core`; **nothing** imports `render`.
- `contracts/` is the only shared surface. Any schema change after Day-1 morning must be called out explicitly.

The pipeline: notation → **ExpressiveScore** (exact-time note events + dynamics/legato annotations) → performance-model pass → sampler render → loop mastering (exact sample-length loop, seam crossfade, loudness normalize) → cached audio per (nagma, BPM, Sa, instrument).

## Two non-negotiable invariants

These are the product's entire reason to exist — do not compromise them for convenience:
1. **Machine-perfect laya.** Matra boundaries and *sam* (beat 1) are mathematically exact. Micro-timing jitter is applied only to non-structural notes.
2. **Human timbre via pure code.** The "human" layer is the win and needs no ML: micro-timing jitter, taal-shaped dynamics (swell toward sam), legato overlap between notes, slow bellows-style amplitude undulation, and per-avartan variation (render a 4–8 cycle super-loop with different seeds per cycle so it isn't rubber-stamped). Neural refinement is explicitly deferred (roadmap only).

## Commands

- Compile text nagma → score: `PYTHONPATH=core/src python3 -m nagma_core.cli assets/nagmas/bhairavi-teentaal.nagma --bpm 80 --sa D -o score.json` (or `nagma-compile ...` once installed).
- Render a loop from a score: `nagma-render score.json -o loop.wav --soundfont assets/soundfonts/harmonium.sf2` (or set `NAGMA_SOUNDFONT`). Needs fluidsynth + a soundfont.
- End-to-end smoke test (**the primary correctness gate**): `./scripts/smoke.sh`. Text nagma → score → WAV, asserting **exact loop length** via `scripts/assert_loop_length.py`. The score stage runs on pure stdlib; the WAV stage runs only when fluidsynth + a soundfont are present, else it skips with a notice. Wired into `.github/workflows/ci.yml`.
- Tests: `cd core && PYTHONPATH=src pytest -q` (no deps); `cd render && pytest -q` (needs numpy/soundfile).
- Python deps via `uv sync` (workspace root ties `core` + `render` together).

## Key domain terms

| Term | Meaning |
|---|---|
| Taal / Matra / Sam | Rhythmic cycle / beat / beat 1 (point of resolution). |
| Taali / Khaali | Structural beats. Teentaal (16 matras): taali 1/5/13, khaali 9. |
| Lehra / Nagma | Fixed melodic loop, one avartan (cycle) long — the time reference. |
| Sargam | Swars S r R g G m M P d D n N across three octaves. |
| Sa / key | The pitch the tabla is tuned to; the lehra transposes to match. |

**Nagma text grammar (v1):** one line per vibhag, e.g. `S R G m | P - D P | ...`, where `-` = sustain and `,` splits a matra in two. Max 2 notes per matra in v1.

## Decisions still open (see spec §11)

Bhairavi vs. Yaman for the stock nagma; Flutter gapless-loop plugin vs. straight FFI; render-service hosting; tanpura pitch-shift vs. per-key loops; super-loop length (4 vs. 8 avartans). Don't hard-code around these without checking the spec/user.
