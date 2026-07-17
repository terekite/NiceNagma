# app/ — Flutter mobile app (iOS-first)

The player. **Speaks only JSON-over-HTTP to the render service and plays audio
files.** It never imports `core` or `render` — that isolation is a review gate
(spec §7).

## Status: scaffolding
Flutter isn't set up in this environment yet. This directory holds the intended
structure and the key architectural seam (`lib/services/render_client.dart`).
Bootstrap the real project on Day 2:

```bash
# From the repo root, with Flutter + Xcode installed:
cd app
flutter create --org app.nicenagma --platforms=ios --project-name nicenagma .
# then restore the lib/ files tracked here (flutter create won't overwrite them
# if present; otherwise merge).
flutter run                     # on a connected device / simulator
```

`--platforms=ios` keeps this iOS-only for now (spec decision). Android can be
added later with `flutter create --platforms=android .` — the Dart code is
unchanged.

## Planned structure
```
lib/
  main.dart                  app shell + player screen
  models/
    render_request.dart      mirrors contracts/render-request.schema.json
  services/
    render_client.dart       POST /render, cache by (hash,bpm,sa,instrument,avartans,seed)
    loop_player.dart         gapless native loop playback (see below)
  screens/
    player_screen.dart       cycle wheel, matra counter, tempo + Sa, tanpura mix
    nagma_editor_screen.dart text-grammar entry with inline validation
```

## The two hard native pieces (Day 2 risks, spec §9)
1. **Gapless looping.** Decide by a 30-min soak test on a physical device:
   a vetted Flutter gapless-loop plugin vs. straight FFI to a native player.
   Fall back to FFI on any audible seam or drift. The loop WAV from `render` is
   already an exact-sample-length loop, so the player just has to not insert gaps.
2. **Audio-clock → UI sync.** The matra counter is driven from the audio
   playback position, never a UI timer, so the wheel never drifts from the sound.

## Config
`RenderClient` needs the render service base URL. For local dev, run the service
(`render/`) and point the app at `http://<your-mac-ip>:8000`.
