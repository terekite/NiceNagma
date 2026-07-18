#!/usr/bin/env bash
# One command to run NiceNagma on the physical iPhone with live hot reload.
#
#   ./run-iphone.sh
#
# It: (1) starts the render service if it isn't already up, (2) points the app
# at this Mac's CURRENT Wi-Fi IP (so it keeps working when your IP changes), and
# (3) launches on the iPhone with hot reload attached. Press `r` to hot-reload
# Dart changes, `R` to hot-restart, `q` to quit.
#
# One-time prereqs (already done once): Xcode signing set up (Personal Team),
# the developer cert trusted on the phone, and Local Network permission granted
# to your terminal / Claude app. iPhone + Mac on the same Wi-Fi.
#
# To run WITHOUT the USB cable: enable wireless debugging once in Xcode —
# Window > Devices and Simulators > your iPhone > tick "Connect via network".
# After that this script finds the phone over Wi-Fi with no cable.
set -euo pipefail
cd "$(dirname "$0")"

IPHONE_UDID="00008120-00043CC600E14032"   # this iPhone; re-check with: flutter devices
PORT=8000

# Reach this Mac by its stable Bonjour name so a changed Wi-Fi IP can't break
# the app. Falls back to the numeric IP if .local resolution isn't available.
HOST="$(scutil --get LocalHostName 2>/dev/null).local"
if [ -z "$HOST" ] || [ "$HOST" = ".local" ]; then
  HOST="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true)"
fi
if [ -z "${HOST:-}" ]; then
  echo "error: could not determine this Mac's address — are you on Wi-Fi?" >&2
  exit 1
fi

# Start the render service only if it isn't already answering.
if curl -sf "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
  echo "==> render service already running"
else
  echo "==> starting render service on 0.0.0.0:$PORT (log: /tmp/nagma-render.log)"
  NAGMA_SOUNDFONT=assets/soundfonts/harmonium.sf2 \
    uv run uvicorn nagma_render.service.app:app --host 0.0.0.0 --port "$PORT" \
    >/tmp/nagma-render.log 2>&1 &
  for _ in $(seq 1 20); do
    curl -sf "http://127.0.0.1:$PORT/health" >/dev/null 2>&1 && break
    sleep 1
  done
fi

if ! curl -sf "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
  echo "error: render service didn't come up — see /tmp/nagma-render.log" >&2
  exit 1
fi

echo "==> app will fetch renders from http://$HOST:$PORT"
cd app
exec flutter run --dart-define=RENDER_URL="http://$HOST:$PORT" -d "$IPHONE_UDID"
