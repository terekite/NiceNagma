# Product demo film pipeline

Reproducible tooling that turns the live app into a polished 9:16 vertical
product film (`demo/NiceNagma-demo.mp4`). The generated media under `demo/` is
gitignored; only this pipeline is committed.

## What it does

1. **Drives the real app** — `app/integration_test/demo_drive.dart` launches the
   app on a booted simulator and performs a paced, cinematic sequence (Play →
   pick Sa → set tempo → add tanpura → switch taal → write a lehra). It makes no
   assertions; it exists purely to choreograph the screen for capture. The cycle
   wheel repaints ~60 Hz forever, so it holds via a real-time `_hold` loop rather
   than `pumpAndSettle` (which would hang).
2. **Records** the simulator screen with `xcrun simctl io … recordVideo` while
   the driver runs (see the recording snippet below).
3. **Renders the soundtrack** from the app's own sound — the harmonium lehra loop
   (`nagma-compile` → `nagma-render`) plus a tanpura drone
   (`scripts/make_tanpura.py` → fluidsynth). No external/licensed audio.
4. **Composites & masters** in ffmpeg (`scripts/make_demo.sh`): the phone screen,
   rounded + shadowed, floats on a branded dark-warm gradient with a wordmark and
   lower-third feature captions (`scripts/demo_assets.py`); vignette + subtle
   grain; harmonium enters on Play and the tanpura swells in when it's added.

## Prerequisites

- Flutter + Xcode + a booted iPhone simulator
- `ffmpeg`, `fluidsynth`, Python (`mido`, `numpy`, `soundfile`, `Pillow`)
- The harmonium/tanpura soundfonts under `assets/soundfonts/`

## Run

```bash
# 1. build once, then record the driven run (uses the default on-device renderer)
UDID=$(xcrun simctl list devices booted | grep -oE '[0-9A-F-]{36}' | head -1)
cd app && flutter build ios --simulator --debug
# start recording, run the driver, stop recording — see the record.sh pattern in
# scripts/ history, or drive manually:
xcrun simctl io "$UDID" recordVideo --codec h264 ../demo/build/raw.mov &
flutter test integration_test/demo_drive.dart -d "$UDID"
kill -INT %1   # stop the recording

# 2. build the film (overlays + soundtrack are generated idempotently)
cd .. && ./scripts/make_demo.sh          # → demo/NiceNagma-demo.mp4
DRAFT=1 ./scripts/make_demo.sh           # fast low-res preview for timing checks
```

## Notes

- `raw.mov` from simctl is **variable-frame-rate**; `make_demo.sh` forces the
  phone + mask streams to constant 30 fps before `alphamerge`, otherwise
  framesync truncates the phone layer and it freezes mid-film.
- Caption windows (the `CAPS` array in `make_demo.sh`) are in trimmed-video time;
  retune them if the choreography's pacing in `demo_drive.dart` changes.
