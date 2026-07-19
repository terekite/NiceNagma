#!/usr/bin/env bash
# One-shot iOS bootstrap. Run this ONCE after installing Flutter + Xcode, from
# the app/ directory. It is safe to re-run (idempotent).
#
#   cd app && ./bootstrap.sh && flutter run
#
# What it does, and why each step is needed:
#   1. `flutter create` generates the iOS Runner project (ios/, .pbxproj, pods).
#      It SKIPS files that already exist, so our authored lib/ and pubspec.yaml
#      survive untouched.
#   2. Overwrites the generated ios/Runner/AppDelegate.swift with ours — the
#      native gapless loop player. The .pbxproj already compiles AppDelegate.swift,
#      so no Xcode project surgery is needed.
#   3. Patches Info.plist: allow cleartext HTTP to the LAN render service, prompt
#      for local-network access, and keep audio playing when the screen locks.
#   4. `flutter pub get`.

set -euo pipefail
cd "$(dirname "$0")"

if ! command -v flutter >/dev/null 2>&1; then
  echo "error: flutter not on PATH. Install Flutter + Xcode first." >&2
  exit 1
fi

echo "==> snapshotting authored sources (belt-and-suspenders around flutter create)"
SNAP="$(mktemp -d)"
cp -R lib pubspec.yaml "$SNAP/"

echo "==> flutter create (generates iOS platform files)"
flutter create --org app.nicenagma --platforms=ios --project-name nicenagma .

echo "==> restoring authored lib/ + pubspec.yaml"
rm -rf lib
cp -R "$SNAP/lib" lib
cp "$SNAP/pubspec.yaml" pubspec.yaml
rm -rf "$SNAP"

RUNNER="ios/Runner"
echo "==> installing native audio (gapless loop player + on-device renderer) -> $RUNNER/{AppDelegate,SceneDelegate}.swift"
# AppDelegate.swift holds both LoopPlayer and OfflineRenderer; SceneDelegate wires
# their MethodChannels. Both files are already compiled by the generated .pbxproj,
# so overwriting them needs no Xcode project surgery.
cp native/AppDelegate.swift "$RUNNER/AppDelegate.swift"
cp native/SceneDelegate.swift "$RUNNER/SceneDelegate.swift"

echo "==> materializing bundled soundfont (on-device rendering) -> assets/soundfonts/"
# Flutter can only bundle assets inside the package dir, so copy the canonical
# soundfont out of the repo assets/. It is git-ignored here (see .gitignore) to
# avoid duplicating ~5.6 MB into the app package.
mkdir -p assets/soundfonts
cp ../assets/soundfonts/harmonium.sf2 assets/soundfonts/harmonium.sf2
# Plucked sitar SF2 (scripts/build_sitar.py): jawari buzz + sympathetic ring.
cp ../assets/soundfonts/sitar.sf2 assets/soundfonts/sitar.sf2

PLIST="$RUNNER/Info.plist"
PB=/usr/libexec/PlistBuddy
echo "==> patching $PLIST (ATS local networking, local-network prompt, background audio)"

# Idempotent add-or-set helper.
set_bool() { $PB -c "Set :$1 $2" "$PLIST" 2>/dev/null || $PB -c "Add :$1 bool $2" "$PLIST"; }
set_str()  { $PB -c "Set :$1 $2" "$PLIST" 2>/dev/null || $PB -c "Add :$1 string $2" "$PLIST"; }

# App Transport Security: permit HTTP to LAN hosts/IPs (the local render service).
$PB -c "Add :NSAppTransportSecurity dict" "$PLIST" 2>/dev/null || true
set_bool "NSAppTransportSecurity:NSAllowsLocalNetworking" true

# iOS 14+ prompts before touching the local network.
set_str "NSLocalNetworkUsageDescription" \
  "NiceNagma fetches rendered lehra loops from the render service on your Mac over the local network."

# Keep the loop playing with the screen locked / app backgrounded.
$PB -c "Add :UIBackgroundModes array" "$PLIST" 2>/dev/null || true
if ! $PB -c "Print :UIBackgroundModes" "$PLIST" 2>/dev/null | grep -q audio; then
  $PB -c "Add :UIBackgroundModes: string audio" "$PLIST"
fi

echo "==> flutter pub get"
flutter pub get

cat <<'EOF'

Bootstrap complete. Next:
  1. Start the render service on this Mac (from the repo root):
       NAGMA_SOUNDFONT=assets/soundfonts/harmonium.sf2 \
         uv run uvicorn nagma_render.service.app:app --host 0.0.0.0 --port 8000
  2. Find your Mac's LAN IP (System Settings -> Wi-Fi -> Details -> IP Address).
  3. Run on a connected iPhone (same Wi-Fi as the Mac):
       flutter run --dart-define=RENDER_URL=http://<mac-ip>:8000
     Or on the Simulator (reaches the Mac at 127.0.0.1):
       flutter run
EOF
