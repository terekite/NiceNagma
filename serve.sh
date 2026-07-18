#!/usr/bin/env bash
# Everyday use: start the render service on this Mac, then just tap the
# NiceNagma icon on your iPhone (same Wi-Fi). The installed app fetches its
# lehra loops from here. Leave this running while you practice; Ctrl-C to stop.
#
#   ./serve.sh
#
# The app reaches this Mac by its Bonjour name (Omars-Laptop.local), so it keeps
# working even if your Wi-Fi IP changes.
set -euo pipefail
cd "$(dirname "$0")"

PORT=8000
if curl -sf "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
  echo "render service is already running on :$PORT"
  exit 0
fi

echo "==> starting render service on 0.0.0.0:$PORT"
echo "    (reachable at http://$(scutil --get LocalHostName).local:$PORT — leave this window open)"
exec env NAGMA_SOUNDFONT=assets/soundfonts/harmonium.sf2 \
  uv run uvicorn nagma_render.service.app:app --host 0.0.0.0 --port "$PORT"
