# app/ — Flutter mobile app (iOS-first)

The player. **Speaks only JSON-over-HTTP to the render service and plays audio
files.** It never imports `core` or `render` — that isolation is a review gate
(spec §7).

## Bootstrap (after installing Flutter + Xcode)

The Dart code and the native player are authored and tracked here, and the
generated `ios/` Xcode project is now committed too. One script does the whole
setup and is **safe to re-run** (idempotent) — run it after a fresh clone or to
re-apply the native players / Info.plist patches:

```bash
cd app
./bootstrap.sh          # flutter create + install native players + patch Info.plist + pub get
```

Then start the render service on this Mac (from the repo root):

```bash
NAGMA_SOUNDFONT=assets/soundfonts/harmonium.sf2 \
  uv run uvicorn nagma_render.service.app:app --host 0.0.0.0 --port 8000
```

And run the app:

```bash
# On a connected iPhone (same Wi-Fi as the Mac); use the Mac's LAN IP:
flutter run --dart-define=RENDER_URL=http://<mac-ip>:8000
# On the Simulator (reaches the Mac at 127.0.0.1):
flutter run
```

The first frame paints immediately; the default lehra (proposed Teentaal, D Sa,
80 BPM) renders in the background and starts on **Play**. If the service is
unreachable a banner explains why and offers Retry.

## Structure

```
lib/
  main.dart                     app shell; owns the PlayerController, kicks off startup render
  config.dart                   render URL (--dart-define=RENDER_URL), defaults, 12 keys, default lehra
  taal.dart                     Teentaal structure for the UI (mirror of core/taal.py; app never imports core)
  state/
    player_controller.dart      params -> re-render -> load -> playback; coarse state + 60 Hz position notifier
  services/
    render_client.dart          POST /render, cache by (nagma,bpm,sa,instrument,avartans,seed) — matches server key
    loop_player.dart            MethodChannel/EventChannel to the native player; LoopPosition math (matra/phase)
  screens/
    player_screen.dart          cycle wheel, laya/BPM/Sa chips, tempo slider, Sa chips, tanpura mix, transport
    nagma_editor_screen.dart    text-grammar entry; validation is server-authoritative (422 shown inline)
  widgets/
    cycle_wheel.dart            CustomPainter ring; sweep hand driven by the audio clock
native/
  AppDelegate.swift             plugin registration + the LoopPlayer (AVAudioEngine gapless loop + tanpura bus)
  SceneDelegate.swift           wires the Method/Event channels on scene-connect (Flutter 3.44 UIScene lifecycle)
bootstrap.sh                    one-shot iOS setup
```

## The two hard native pieces (spec §9) — how they're solved

1. **Gapless looping.** `native/AppDelegate.swift` reads the rendered loop WAV
   into a PCM buffer and schedules it with
   `AVAudioPlayerNode.scheduleBuffer(_:at:options:.loops)` — sample-accurate,
   zero-gap wraparound. The WAV from `render/` is already an exact-sample-length
   loop, so the player just has to not insert gaps. (No third-party plugin; the
   `just_audio` option is dropped.)
2. **Audio-clock → UI sync.** The matra counter and cycle-wheel hand are driven
   from `playerTime.sampleTime` (the audio render clock), streamed to Dart over
   an EventChannel at ~60 Hz. Never a UI timer, so the wheel cannot drift from
   the sound.

**Route changes** (headphones in/out) fire `AVAudioEngineConfigurationChange`,
which stops the engine and clears its scheduled buffers. `LoopPlayer` observes
it, resets the `armed` flag, restarts the engine, and resumes if it was playing
— otherwise audio would go permanently silent after the first plug/unplug.

Any tempo/Sa/nagma change is a **re-render** (a new WAV from the service, cached
by key), never a time-stretch or pitch-shift — the core thesis.

## Native staging note

The native surface is two files that `flutter create` already generates and the
`.pbxproj` already compiles, so there is no Xcode project surgery — `bootstrap.sh`
just overwrites them: `AppDelegate.swift` (plugin registration + the `LoopPlayer`)
and `SceneDelegate.swift` (channel wiring on scene-connect, required by Flutter
3.44's UIScene lifecycle where the FlutterViewController isn't available in
AppDelegate). It also patches `Info.plist` (ATS local networking for the LAN
service, the local-network permission string, and the background-audio mode).
```
