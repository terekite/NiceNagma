#!/usr/bin/env bash
# Fetch the CC-BY 4.0 harmonium soundfont and verify its SHA-256.
#
# Source of record: Musical Artifacts #2127, "Wetthasinghe Harmonium General
# Midi Version" by W. D. Tharinda Perera (GM layout by Mike77154), CC-BY 4.0:
#   https://musical-artifacts.com/artifacts/2127
# Attribution is recorded in assets/LICENSES.md (a CC-BY obligation).
#
# The live musical-artifacts.com file endpoint is behind a Cloudflare JS
# challenge that blocks non-browser clients, so we pull the byte-identical
# archived copy from the Wayback Machine and verify it against the SHA-256 the
# site's JSON API publishes. If the hash matches, the bytes are identical.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/assets/soundfonts/harmonium.sf2"
EXPECT="458d43f6e1ba670ad9b2995724c84343faf8565a9c82b16d82f3e6e97f9a53f8"

if [ -f "$OUT" ] && [ "$(shasum -a 256 "$OUT" | awk '{print $1}')" = "$EXPECT" ]; then
  echo "harmonium.sf2 already present and verified ✅"
  exit 0
fi

FILE="https://musical-artifacts.com/artifacts/2127/Wetthasinghe_Harmnium_GM_Ver.sf2"
MIRRORS=(
  "https://web.archive.org/web/20260606032127id_/$FILE"
  "https://web.archive.org/web/20220813124117id_/$FILE"
)

mkdir -p "$(dirname "$OUT")"
for attempt in 1 2 3 4 5; do
  for u in "${MIRRORS[@]}"; do
    echo "==> fetching (attempt $attempt): $u"
    if curl -sSL --retry 2 --max-time 90 "$u" -o "$OUT"; then
      if head -c 4 "$OUT" | grep -q "RIFF"; then
        GOT="$(shasum -a 256 "$OUT" | awk '{print $1}')"
        if [ "$GOT" = "$EXPECT" ]; then
          echo "OK: harmonium.sf2 verified (sha256 $GOT) ✅"
          exit 0
        fi
        echo "   hash mismatch (got $GOT); retrying"
      fi
    fi
  done
  sleep 3
done

echo "ERROR: could not fetch a verified harmonium.sf2." >&2
echo "Fallback: download it manually from $FILE in a browser," >&2
echo "save to $OUT, and check sha256 == $EXPECT" >&2
exit 1
