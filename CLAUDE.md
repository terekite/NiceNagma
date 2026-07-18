# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Status

**Phase 1 landed: render pipeline is real and tested.** The design of record is `nagma-app-planning-spec.md` (Draft v0.3) — a 3-day-sprint plan for a tabla-practice lehra/nagma app. iOS-first (TestFlight); Android deferred. Current state of the monorepo:

- `contracts/` — the three JSON Schemas (`NagmaDoc`, `ExpressiveScore`, `RenderRequest`) are written and frozen.
- `core/` — **implemented and tested** (18 tests, pure stdlib): taal defs, sargam parser, compiler, performance model, `nagma-compile` CLI.
- `render/` — **implemented and renders end-to-end**; tested. `master.py`: seam-wrap + bellows LFO + **double-reed shimmer (chorus)** + **circular-convolution room reverb** + loudness. `midi.py`: **multi-channel allocator with per-note CC11 bellows swell** (Phase B). fluidsynth call isolated behind `sampler.py` (its reverb/chorus off). `nagma-render` CLI + FastAPI service + Dockerfile present. `./scripts/smoke.sh` produces a real WAV, exact loop length.
  - **Schema note:** the frozen `ExpressiveScore` gained an optional per-note `swell` field in Phase B (justified: intra-note dynamics). Contracts otherwise stay frozen — call out any further change.
- `app/` — **Stage 1 verified on the iOS Simulator (Xcode 26.6 / iPhone 17 Pro): the default lehra renders on boot, plays as a clean gapless loop, and the cycle wheel tracks the audio clock. `flutter analyze` clean; 6 unit tests pass.** The Xcode project is generated (`app/ios/` exists, committed) and `bootstrap.sh` (re-runnable, idempotent) drives it: flutter create → restore authored `lib/` → install native players → patch Info.plist → pub get. Implemented: native gapless loop player (`native/AppDelegate.swift` holds the `LoopPlayer` — AVAudioEngine `scheduleBuffer(…, .loops)` + tanpura bus; `native/SceneDelegate.swift` wires its `MethodChannel`/`EventChannel` under Flutter 3.44's **UIScene lifecycle**, where the FlutterViewController is created on scene-connect, not in AppDelegate); Dart `loop_player.dart` (+ `LoopPosition` matra math, unit-tested in `test/widget_test.dart`), `player_controller.dart` (params → debounced re-render → load → playback), `cycle_wheel.dart` (audio-clock-driven sweep hand), `player_screen.dart` (tempo/Sa/tanpura + transport), `nagma_editor_screen.dart`, and `render_client.dart` (cache key byte-identical to the server's — see below). Info.plist patched for ATS local-networking (LAN render service over HTTP), the local-network permission string, and background audio.
  - **Route-change fix (landed):** `LoopPlayer` observes `AVAudioEngineConfigurationChange` — a headphone plug/unplug stops the engine and clears its scheduled buffers, so the handler resets the `armed` flag, restarts the engine, and resumes if it was playing. Without it, audio went permanently silent after a route change. Verified on-device (swaps survive, seam clean).
  - **Next: Stage 2** (Tempo slider + Sa ChoiceChips → debounced live re-render) and **Stage 3** (nagma editor + tanpura mix) — the Dart/UI is already written and wired; they need on-device verification (drag tempo → new WAV + laya label updates; pick Sa → transposed re-render; edit nagma → 422 path; tanpura slider).
  - **Service note:** the render `_cache_key` (`render/service/app.py`) now uses compact JSON separators so the server key equals the app's Dart `jsonEncode` key — verified byte-identical. Running the service needs the `render[service]` extra (`fastapi`, `uvicorn`); CocoaPods is installed (Homebrew) for the iOS build. Simulator reaches the service at `127.0.0.1:8000`; a physical iPhone needs `flutter run --dart-define=RENDER_URL=http://<mac-ip>:8000`.
  - **On-device rendering (default, no Mac/service needed):** the whole render pipeline now runs on the phone, behind the same `RenderRequest → WAV path` seam. `lib/services/loop_renderer.dart` defines the `LoopRenderer` interface; `Config.renderer` (`--dart-define=RENDERER=local|http`, default `local`) picks the impl. `LocalRenderer` (`lib/services/local_renderer.dart`) parses+compiles the nagma in Dart (`lib/render/` — a faithful port of `core/` + `render/midi.py`: sargam/taal/models/parser/reduce/performance/compiler/midi, producing a Standard MIDI File) then calls the native `nicenagma/render` channel; `OfflineRenderer` (in `native/AppDelegate.swift`) renders the SMF via **`AVAudioUnitSampler` + `AVAudioSequencer` in offline manual-rendering mode** (Apple's built-in sampler replaces fluidsynth — 0 bytes added) and applies a Swift port of `master.py`'s mastering (seam-wrap, bellows LFO, chorus, native room reverb, peak normalize), trimming to exactly `loopLengthSamples`. The harmonium `.sf2` is bundled (~5.6 MB) via `SoundfontProvider`; future instruments download on demand, not into the binary. `HttpRenderClient` (renamed from `RenderClient`) remains the cloud/LAN path — the shared cache key means switching between local and HTTP never re-renders a cached loop. The Dart port has mirrored unit tests under `app/test/render/` (37 tests). On-device output is **not** byte-identical to fluidsynth (different sampler + a Dart PRNG); the mastering constants in `OfflineRenderer` are re-tuned by ear.
- `assets/` — `LICENSES.md` + stock/proposed nagmas + **committed multisample `soundfonts/harmonium.sf2`** (CC0, built by `scripts/build_harmonium.py` from freesound #330410; one sample per semitone C2–D5, preset bank 0/program 0). Timbre + room presence are the Phase-A realism work (see `.claude/plans/`).

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
- `app` never imports `core` or `render` (the Python packages). It reaches audio through the `RenderRequest → WAV path` seam only. **Exception (deliberate):** on-device rendering *reimplements* `core` + `render/midi.py` in Dart (`app/lib/render/`) and `render/master.py` + the sampler in Swift (`OfflineRenderer`). This is a port, not an import — the Python packages stay independent, and both renderers sit behind the same `LoopRenderer` seam and cache key, so the cloud path (`HttpRenderClient` → the Python service) remains a drop-in swap. Keep the Dart/Swift port faithful to `core`/`render`; the frozen `contracts/` + mirrored tests are the guard against drift.
- `render` imports `core`; **nothing** imports `render`.
- `contracts/` is the only shared surface. Any schema change after Day-1 morning must be called out explicitly.

The pipeline: notation → **ExpressiveScore** (exact-time note events + dynamics/legato annotations) → performance-model pass → sampler render → loop mastering (exact sample-length loop, seam crossfade, loudness normalize) → cached audio per (nagma, BPM, Sa, instrument).

## Two non-negotiable invariants

These are the product's entire reason to exist — do not compromise them for convenience:
1. **Machine-perfect laya.** Matra boundaries and *sam* (beat 1) are mathematically exact. Micro-timing jitter is applied only to non-structural notes.
2. **Human timbre via pure code.** The "human" layer is the win and needs no ML: micro-timing jitter, taal-shaped dynamics (swell toward sam), legato overlap between notes, slow bellows-style amplitude undulation, and per-avartan variation (render a 4–8 cycle super-loop with different seeds per cycle so it isn't rubber-stamped). Neural refinement is explicitly deferred (roadmap only).

## Commands

- Compile text nagma → score: `PYTHONPATH=core/src python3 -m nagma_core.cli assets/nagmas/proposed-teentaal.nagma --bpm 80 --sa C -o score.json` (or `nagma-compile ...` once installed). Auto-selects the laya realization from `--bpm` (`--laya` to force one).
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
