# Lehra / Nagma Practice App — Planning Document & Product Spec

**Working title:** NiceNagma (placeholder)
**Platform:** Mobile (iOS + Android)
**Status:** Draft v0.3 — 3-day sprint scope, monorepo
**Date:** July 2026

---

## 0. What Changed in v0.2

- **MVP radically narrowed:** Teentaal only, one raag, harmonium only.
- **Timeline compressed to a 3-day sprint** (stretch: 5 days). Everything is re-planned around that.
- **Sound sourcing replanned** for speed: no commissioned recordings, no neural training in v1. Fast options analyzed in §6.
- **New in v0.3: monorepo, not multi-repo.** Given the timeline, everything lives in one repository, but organized as four isolated packages with the same clean contracts (§7). One package's job is still to *output the rendered audio*.
- The original long-horizon material (neural refinement, sarangi, listening panels, business model) is preserved but moved to **Post-Sprint Roadmap** (§10).

---

## 1. Vision & Problem Statement (unchanged)

Tabla students practice against a *lehra/nagma*: a melodic phrase exactly one taal cycle long, looped continuously. Existing apps are either **recorded loops** (beautiful timbre, wavy laya, fixed tempo/key, no custom input) or **robotic MIDI** (perfect timing, dead sound).

**Core thesis:** A lehra is a fixed loop at a fixed tempo, so synthesis never needs to be real-time. Render offline with as much expressive processing as we can afford, then loop the rendered audio with sample accuracy on device. Human-sounding timbre, machine-perfect laya.

**Two product pillars:**
- **P1 — Sounds like a person playing, in perfect laya.**
- **P2 — Users can input their own nagmas.**

---

## 2. Sprint MVP Scope (3 days, stretch 5)

### In
- **Teentaal only** (16 matras; taali 1/5/13, khaali 9).
- **One raag** — recommend **Bhairavi** (the default lehra raag for tabla solo; most universally useful) with one well-crafted stock nagma. (Yaman is the alternate if the chosen nagma sits better there.)
- **Harmonium only.**
- Tempo control (per-matra BPM, ~40–240), **Sa selection** (12 keys — with a sampler this is just rendering different pitches, so it's nearly free and it's table stakes for tabla players).
- **Custom nagma input, minimal form:** text-grammar entry, not a fancy grid editor. One line per vibhag, e.g. `S R G m | P - D P | ...` with `-` = sustain and `,` for splitting a matra in two. Max 2 notes per matra in v1. This keeps P2 alive inside the sprint at maybe 10% of the UI cost of a visual editor.
- Seamless, drift-free looping for hours; audio-clock-driven matra display with sam/taali/khaali marks.
- Bundled static **tanpura loop** with a mix knob (cheap: it's just a second audio bus playing a pre-made loop in the selected key — ship loops in all 12 keys or pitch-shift one good loop).

### Out (deferred, see §10)
- All other taals and raag presets; sarangi/violin; neural refinement; visual grid editor; meend marks; gradual tempo ramp; sharing; accounts/sync; export; practice logs; monetization.

### Definition of done (Day 3)
A tabla player can open the app, pick tempo and Sa, hear a harmonium lehra in Teentaal that is steady and non-robotic *enough to practice with*, loop it indefinitely, and type in their own nagma and hear it.

---

## 3. Domain Background

(Unchanged from v0.1 — glossary of taal, matra, sam, taali/khaali, lehra, laya, sargam, meend, Sa. Retained for team reference.)

| Term | Meaning |
|---|---|
| **Taal / Matra / Sam** | Rhythmic cycle / beat / beat 1 (point of resolution). |
| **Taali / Khaali** | Clapped vs. waved structural beats. Teentaal: taali 1, 5, 13; khaali 9. |
| **Lehra / Nagma** | Fixed melodic loop, one avartan long, used as the time reference. |
| **Sargam** | S r R g G m M P d D n N across three octaves (mandra/madhya/taar). |
| **Sa / key** | Tabla is tuned to a pitch (C#, D, …); the lehra must transpose to match. |

---

## 4. The Realism Strategy Under a 3-Day Constraint

The v0.1 quality stack was: great samples → performance model → neural refinement. In 3 days, the honest version is:

1. **Timbre comes from an existing sample set** (see §6) — good, not world-class. Acceptable because harmonium realism is mostly about *behavior*, not exotic timbre.
2. **The "human" layer is where we win, and it's pure code** — no data collection, no training, buildable in a day:
   - Micro-timing jitter of a few ms on non-structural notes (matra boundaries and sam stay mathematically exact).
   - Velocity/volume phrasing shaped by the taal — natural swell toward sam, slight slackening after khaali.
   - Legato overlap between consecutive notes (harmonium keys overlap; hard note-off/note-on gaps are the #1 robotic tell).
   - Bellows-style slow amplitude undulation across the phrase (an LFO-ish gain contour, subtly randomized).
   - **Per-avartan variation:** render a super-loop of 4–8 cycles where each cycle draws different jitter/dynamics seeds, so the loop doesn't sound rubber-stamped.
3. **Neural refinement is deferred entirely.** Training a model in 3 days from scraped audio is not realistic — models in this space need clean solo-instrument data and days of iteration even when the code exists. It stays on the roadmap (§10) where it belongs.

This "sampler + performance model, rendered offline" tier was already Option C in v0.1; the sprint simply ships Option C alone and pushes Option D out.

---

## 5. Rendering & Playback Architecture (unchanged in principle)

- Notation → **Expressive Score** (exact-time note events + dynamics/legato annotations) → performance-model pass → sampler render → loop mastering (exact sample-length loop, seam crossfade, loudness normalize) → cached WAV/FLAC per (nagma, BPM, Sa, instrument).
- Tempo or Sa change = **re-render** (seconds), not time-stretching or pitch-shifting audio.
- Playback is a dumb, sample-accurate native loop player. UI matra counter is driven by the audio clock, not a UI timer.

**Where does rendering run in the sprint build?** Two options:

| | A: On-device sampler (FFI) | B: Tiny cloud render service |
|---|---|---|
| Effort in 3 days | High — compiling/binding fluidsynth or sfizz for iOS+Android is fiddly | Low — a ~100-line HTTP wrapper around the render CLI in Docker |
| Offline | Fully offline | Cached renders play offline; *new* renders need connectivity |
| Fits module boundaries | Blurs app/audio boundary | Cleanly: the render package *is* the service |

**Recommendation: B for the sprint.** The render repo exposes both a CLI and a small HTTP endpoint; the app calls it and caches results. On-device rendering becomes a post-sprint port of the same repo. (If even a tiny server is unwanted, fallback: pre-render a tempo/key matrix of the stock nagma and restrict custom-nagma rendering to when-online — but B is genuinely only a few hours of work.)

---

## 6. Sourcing the Harmonium Sound — Fast Paths

Ranked by speed-to-quality for this sprint. The v0.1 plan (commissioned recording session) moves to the roadmap.

### Path 1 (recommended): Existing free sample libraries / soundfonts
Free harmonium sample sets exist — SF2/SFZ soundfonts on community repositories (e.g., Musical Artifacts, Polyphone's library) and free sampled-harmonium instruments from Indian-music VST makers. Same for tanpura loops/samples.
- **Speed:** usable within the hour. Render via `fluidsynth` (SF2) or `sfizz` (SFZ) from the CLI.
- **Legality:** check each license (many are CC/free-for-use; some are non-commercial — verify before shipping paid).
- **Quality:** varies; audition 3–5 candidates in the first hours of Day 1 and pick the best. Our performance-model layer does a lot of lifting on top of even a mediocre soundfont.

### Path 2: Record it yourself (if you have access to a harmonium)
A phone/USB-mic recording of a chromatic scale — each note held ~4–6 s at two dynamic levels — chopped into samples and mapped into an SFZ file is a few hours of work and gives you **owned, licensed-forever** samples with exactly the harmonium character you want. Strong option if an instrument is within reach; also the best long-term foundation.

### Path 3: YouTube-sourced audio — analyzed honestly
Two flavors were floated; neither is the right sprint move:
- **As training data for a model:** not feasible in 3 days regardless of source (see §4.3), so the sourcing question is moot for now.
- **As sample material:** performance recordings rarely contain clean, isolated single notes; extracting usable multisamples from mixed performances is slow, and the result underperforms Path 1. There's also a real rights problem: downloading and redistributing others' recordings inside a shipped app is copyright infringement territory, and it's a bad foundation for something you may later monetize.

**Verdict:** Path 1 on Day 1 morning; upgrade to Path 2 whenever a harmonium is available. Path 3 dropped.

---

## 7. Code Architecture — Monorepo, Isolated Packages

One repository (`nagma`), four packages that don't touch each other's internals — communication only through versioned data contracts (JSON) and artifacts (audio files). This keeps the clean seams of a multi-repo design without the sprint-killing overhead of cross-repo versioning, tagging, and packaging.

```
nagma/
├── contracts/        # JSON Schemas: NagmaDoc, ExpressiveScore, RenderRequest
│                     # The single source of truth. Frozen after Day 1 morning.
├── core/             # Pure domain logic, zero I/O (Python)
│                     #  - taal definitions (Teentaal now, schema supports any)
│                     #  - sargam text-grammar parser → validated NagmaDoc
│                     #  - compiler: NagmaDoc + (BPM, Sa) → ExpressiveScore
│                     #  - performance model (jitter, dynamics, legato, variation)
├── render/           # THE PACKAGE THAT OUTPUTS THE RECORDING
│                     #  - sampler wrapper (fluidsynth/sfizz) + loop mastering
│                     #  - CLI:  nagma-render score.json -o loop.wav
│                     #  - HTTP service (Dockerfile) the app calls in production
│                     #  - imports `core`; nothing imports `render`
├── app/              # Flutter mobile app
│                     #  - player UI, text-grammar nagma entry, local library
│                     #  - native loop playback (FFI); audio-clock → UI sync
│                     #  - talks to render service over HTTP; caches by
│                     #    (nagma-hash, BPM, Sa, instrument)
│                     #  - knows nothing about synthesis
└── assets/           # soundfonts, tanpura loops, stock nagmas
                      #  - LICENSES.md documenting the license of every file
```

**Isolation rules (the discipline that keeps modules clean):**
- `app` never imports `core` or `render` code — it speaks only JSON-over-HTTP and plays audio files. (A Dart port of just the parser for instant input validation is a post-sprint nicety.)
- `render` imports `core`; nothing imports `render`.
- `contracts/` is the only shared surface. Any change to a schema after Day 1 morning must be justified out loud.
- A single end-to-end smoke script (text nagma → score → WAV, asserts exact loop length) runs in CI and locally.

This structure extracts to separate repositories later with near-zero rework if the project grows — the boundaries are already real.

## 8. Three-Day Sprint Plan

**Day 1 — Sound first (the existential risk)**
- Morning: audition free harmonium soundfonts/sample sets; pick one. Stand up the `core` package (taal def, parser, score compiler) and the `render` CLI (fluidsynth/sfizz render + loop mastering).
- Afternoon: performance-model pass (jitter, taal-shaped dynamics, legato overlap, per-avartan variation). **Gate by end of day:** a Teentaal Bhairavi loop WAV that you would personally practice to. Iterate here until true — nothing downstream matters otherwise.
- Evening: wrap the render CLI in the HTTP service; Docker; deploy to any small host.

**Day 2 — The app**
- Flutter shell; native loop player via FFI (or, pragmatically, the best-available Flutter gapless-loop plugin *if* it proves seamless on test devices — verify with a 30-min soak, fall back to FFI if any seam/drift).
- Player screen: cycle wheel with sam/taali/khaali, matra counter driven from audio position, tempo + Sa controls (trigger re-render, show brief "rendering…" state, cache result), tanpura bus + mix.
- Background audio + interruption handling (calls) — promoted into MVP because riyaz happens screen-off.

**Day 3 — Custom nagma + polish**
- Text-grammar input screen with inline validation errors (wrong matra count, unknown swar); save/name/edit user nagmas (local SQLite).
- Loop-seam and long-run soak test on 2–3 physical devices; fix drift/seam issues.
- App icon, empty states, sensible defaults (Bhairavi stock nagma, D Sa, 80 BPM). Build/sign for TestFlight + Play internal track.

**Days 4–5 (stretch buffer)**
- Whatever slipped; plus the highest-value cheap wins: tap-tempo, sam tick toggle, 2–3 extra stock nagma presets, gradual tempo ramp (cheap given the re-render architecture).

---

## 9. Risks (sprint edition)

| Risk | Severity | Mitigation |
|---|---|---|
| Free soundfont sounds cheap even with performance modeling | **Existential** | Time-boxed Day-1 gate; audition several sources; Path 2 (self-record) as upgrade; the performance layer is where most "robotic" perception dies. |
| Seamless looping flaky on some devices via Flutter plugins | High | FFI/native player fallback decided by a Day-2 soak test, not hope. |
| Render service adds a moving part | Low | ~100 lines + Docker; pre-rendered tempo/key matrix as emergency fallback. |
| Custom-input grammar confuses users | Medium | Show a filled-in example nagma as the editable default; strict, friendly validation messages. |
| Soundfont license unsuitable for eventual paid app | Medium | Record license per asset in `nagma-assets` on Day 1; swap to self-recorded samples before monetizing. |

---

## 10. Post-Sprint Roadmap (v0.1 material, preserved)

1. **More taals & presets:** Jhaptaal, Ektaal, Rupak, Dadra, Keherwa; Yaman/Kafi preset lehras.
2. **Sound quality ladder:** commissioned harmonium & sarangi recording session (dual-purpose: owned sample library + neural training data) → DDSP/MIDI-DDSP-style expressive model for sarangi, or sampler-output + diffusion-refinement pass (no aligned-MIDI training data required) → cloud "HQ render" tier.
3. **Editor v2:** visual grid editor, up to 4 subdivisions per matra, meend/ornament marks, ornament-density dial, variation-depth control.
4. **On-device rendering:** port the `render` package to a mobile-linkable library for fully-offline custom renders.
5. **Practice tools:** gradual tempo ramp (if not done in stretch days), avartan counter, session log; vilambit support with dense ornamentation (hardest realism case — deliberately later).
6. **Sharing & teachers:** share nagmas via link/QR; teacher sets; then community library.
7. **Business:** freemium (extra taals/instruments/HQ renders behind Pro); teacher tier; distribution through tabla/kathak teachers and schools.
8. **Listening-panel validation:** the blind A/B quality gate from v0.1 (≥70% prefer ours over existing apps) runs as soon as there are users to recruit — post-launch rather than pre-build.

---

## 11. Open Questions (updated)

1. Which raag for the single stock nagma — Bhairavi (recommended) or Yaman? Pick by which available nagma composition sounds best on Day 1.
2. Flutter gapless-loop plugin vs. straight-to-FFI on Day 2 — decided by soak test, but pre-read the FFI approach so it's not a cold start.
3. Hosting for the render service (anything with Docker works; cheapest always-on vs. scale-to-zero cold-start tradeoff — cold starts of a few seconds are probably fine for a "Generate" action).
4. Tanpura: pitch-shift one good loop across 12 keys (fast, slight quality loss at extremes) or source per-key loops (better, more asset hunting)?
5. Super-loop length: 4 vs. 8 avartans — decide by ear on Day 1.
