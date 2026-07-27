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
3. **Renders the soundtrack** from the app's own sound — one harmonium loop per
   on-screen state (Teentaal/Jhaptaal × key × tempo, via `nagma-compile` →
   `nagma-render`) plus a tanpura drone (`scripts/make_tanpura.py` → fluidsynth).
   No external/licensed audio.
4. **Phase-locks the audio to the wheel** (`scripts/detect_sam.py` +
   `scripts/build_track.py`). `simctl` captures no audio, so the film is dubbed;
   because laya is machine-perfect, aligning one downbeat (sam) per tempo segment
   to the on-screen cycle-wheel sam keeps the whole segment locked. The sam times
   are detected from the sweep hand and each loop is placed sample-accurately so
   its downbeat lands on the wheel's beat 1; segments crossfade at the tempo/taal
   changes and the tanpura swells in when it's added.
5. **Composites & masters** in ffmpeg (`scripts/make_demo.sh`): the phone screen,
   rounded + shadowed, floats on a branded dark-warm gradient with a wordmark and
   lower-third feature captions (`scripts/demo_assets.py`), plus vignette + grain.

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

- `raw2.mov` from simctl is **variable-frame-rate**. `make_demo.sh` first bakes a
  constant-frame-rate, trimmed working video `phone.mp4`; run `detect_sam.py` and
  the compositor against *that*, so the detected sam grid lines up with the frames
  the viewer sees. The looped-PNG mask is forced to 30 fps before `alphamerge`
  (otherwise framesync starves at 25 fps and freezes the phone at ~46 s), but the
  phone stream itself is left untouched so its timeline stays sam-aligned.
- The sam anchors in `build_track.py` are the frames where the matra counter flips
  to 1 **in the final composite** (folding in the detector's ~1-frame lead and the
  composite's ~1-frame PTS offset). If the choreography or geometry changes,
  re-measure: run `detect_sam.py phone.mp4`, then confirm against the composite and
  nudge. Swapping only the audio is a fast `-c:v copy` re-mux (no re-encode).
- Caption windows (the `CAPS` array in `make_demo.sh`) are in working-video time;
  retune them if the pacing in `demo_drive.dart` changes.
