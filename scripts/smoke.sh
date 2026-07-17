#!/usr/bin/env bash
# End-to-end smoke test: text nagma -> ExpressiveScore -> WAV, asserting the
# loop length is EXACT. This is the primary correctness gate for the render
# pipeline (spec §7) and runs in CI and locally.
#
# The score stage always runs (pure stdlib). The render/WAV stage runs only when
# fluidsynth is installed AND a soundfont is available (NAGMA_SOUNDFONT or
# assets/soundfonts/harmonium.sf2); otherwise it's skipped with a clear notice
# so the gate still passes pre-soundfont.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

export PYTHONPATH="core/src:render/src${PYTHONPATH:+:$PYTHONPATH}"
PY="${PYTHON:-python3}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
SCORE="$WORK/score.json"
LOOP="$WORK/loop.wav"

NAGMA="assets/nagmas/bhairavi-teentaal.nagma"
BPM="${BPM:-80}"
SA="${SA:-D}"
AVARTANS="${AVARTANS:-4}"

echo "==> compile: $NAGMA  (BPM=$BPM Sa=$SA avartans=$AVARTANS)"
"$PY" -m nagma_core.cli "$NAGMA" --bpm "$BPM" --sa "$SA" --avartans "$AVARTANS" -o "$SCORE"

echo "==> assert score loop length (self-consistency)"
"$PY" scripts/assert_loop_length.py "$SCORE"

# Resolve a soundfont.
SF="${NAGMA_SOUNDFONT:-}"
if [ -z "$SF" ] && [ -f "assets/soundfonts/harmonium.sf2" ]; then
  SF="assets/soundfonts/harmonium.sf2"
fi

if command -v fluidsynth >/dev/null 2>&1 && [ -n "$SF" ] && [ -f "$SF" ]; then
  echo "==> render: $SCORE -> $LOOP  (soundfont: $SF)"
  "$PY" -m nagma_render.cli "$SCORE" -o "$LOOP" --soundfont "$SF"
  echo "==> assert rendered WAV is EXACT loop length"
  "$PY" scripts/assert_loop_length.py "$SCORE" --wav "$LOOP"
  echo "SMOKE PASS (full pipeline: text -> score -> WAV)"
else
  echo "==> SKIP render stage:"
  command -v fluidsynth >/dev/null 2>&1 || echo "     - fluidsynth not installed (brew install fluid-synth)"
  { [ -n "$SF" ] && [ -f "$SF" ]; } || echo "     - no soundfont (set NAGMA_SOUNDFONT or add assets/soundfonts/harmonium.sf2)"
  echo "SMOKE PASS (score stage; render stage skipped, see above)"
fi
