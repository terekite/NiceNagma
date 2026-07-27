#!/bin/bash
# Assemble the NiceNagma product demo film (9:16 vertical mp4) from:
#   * demo/build/raw3.mov     — screen capture of the driven app (integration_test/demo_drive.dart)
#   * demo/build/phone.mp4    — CFR, trimmed working video (derived from raw3.mov)
#   * demo/build/bg,mask,cap_* (scripts/demo_assets.py) — branded overlays
#   * demo/build/master.wav   — phase-locked harmonium + tanpura (scripts/build_track.py)
#
# Layout: the phone (rounded + shadowed) sits on a dark warm gradient with a
# wordmark above and a big caption band below. The soundtrack is phase-locked so
# the harmonium sam (beat 1) lands on the wheel's beat 1.
#
# ~24s film (Rupak, the user's adapted nagma): compose → play → tempo → tanpura.
# The choreography does the Rupak/nagma setup off-camera; SRC_SS trims to the
# visible start (the sargam editor showing the committed nagma).
#
# Re-run end to end with:  ./scripts/make_demo.sh   (DRAFT=1 for a fast preview)
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD=demo/build
AUDIO=demo/audio
SF=assets/soundfonts

SRC=raw3.mov      # driven capture
SRC_SS=16.2       # trim to the visible start (2nd editor-open, showing the nagma)
DUR=24.0          # visible length (before the springboard tail)

if [ "${DRAFT:-0}" = "1" ]; then
  VPRESET=ultrafast; VCRF=30; SCALE_OUT="scale=540:960"; OUT=demo/NiceNagma-draft.mp4
else
  VPRESET=medium; VCRF=19; SCALE_OUT="null"; OUT=demo/NiceNagma-demo.mp4
fi

# ---- 1. CFR working video (idempotent) ---------------------------------------
# simctl capture is variable-frame-rate; normalise to CFR 30 once so the phone
# layer never truncates in alphamerge AND the detected sam grid (build_track.py)
# lines up with the composite frame timing.
if [ ! -f "$BUILD/phone.mp4" ]; then
  ffmpeg -y -hide_banner -loglevel error -ss "$SRC_SS" -i "$BUILD/$SRC" \
    -vf "fps=30,setpts=PTS-STARTPTS" -t "$DUR" -c:v libx264 -crf 16 -pix_fmt yuv420p \
    "$BUILD/phone.mp4"
fi

# ---- 2. overlays + phase-locked soundtrack (idempotent inputs) ----------------
python3 scripts/demo_assets.py "$BUILD" >/dev/null
python3 scripts/build_track.py "$BUILD/master.wav" "$DUR" >/dev/null

# ---- 3. caption windows (working-video time, seconds) ------------------------
#   Beat times from the choreography (demo_drive.dart) + detection on phone.mp4.
CAPS=(
  "0 0.3  4.4"     # Compose your own nagma (editor view, ~0-4.8s)
  "1 5.2  12.8"    # Play your lehra (Rupak hero)
  "2 13.6 18.3"    # Set the tempo (→ drut)
  "3 19.1 23.6"    # Add the tanpura
)

# ---- 4. build the filtergraph ------------------------------------------------
F="$BUILD/filter.txt"
{
  # Leave the phone UNTOUCHED so its timeline stays aligned to the detected sam
  # grid (any fps/setpts re-processing shifts it a frame and breaks sam sync).
  # Only the mask needs forcing to CFR 30: it's a looped PNG that otherwise runs
  # at 25 fps, starving framesync and truncating the phone (froze at 56*25/30).
  echo "[0:v]scale=690:1500,setsar=1[ph];"
  echo "[2:v]fps=30,setpts=PTS-STARTPTS,scale=690:1500,format=gray[mk];"
  echo "[ph][mk]alphamerge[phm];"
  echo "[1:v]scale=1080:1920,setsar=1[bg];"
  echo "[bg][phm]overlay=195:118:format=auto[base];"
  prev="base"; idx=3
  for c in "${CAPS[@]}"; do
    read -r ci t0 t1 <<<"$c"
    fo=$(echo "$t1 - 0.4" | bc)
    echo "[${idx}:v]format=rgba,fade=t=in:st=${t0}:d=0.4:alpha=1,fade=t=out:st=${fo}:d=0.4:alpha=1[c${ci}];"
    echo "[${prev}][c${ci}]overlay=0:0:enable='between(t\,${t0}\,${t1})'[b${ci}];"
    prev="b${ci}"; idx=$((idx+1))
  done
  # grain is baked into bg.png (demo_assets.py) — no per-frame blend (which alone
  # pushed the encode past 25 min). Just vignette + fades here.
  echo "[${prev}]vignette=PI/6,fade=t=in:st=0:d=0.6,fade=t=out:st=$(echo "$DUR - 0.9"|bc):d=0.9,${SCALE_OUT},format=yuv420p[v];"
  # audio is the pre-built phase-locked master; just guard the peak + length.
  echo "[7:a]alimiter=limit=0.97,aresample=44100,atrim=0:${DUR},asetpts=PTS-STARTPTS[a]"
} > "$F"

# ---- 5. render ---------------------------------------------------------------
ffmpeg -y -hide_banner -loglevel error \
  -i "$BUILD/phone.mp4" \
  -loop 1 -t "$DUR" -i "$BUILD/bg.png" \
  -loop 1 -t "$DUR" -i "$BUILD/mask.png" \
  -loop 1 -t "$DUR" -i "$BUILD/cap_00.png" \
  -loop 1 -t "$DUR" -i "$BUILD/cap_01.png" \
  -loop 1 -t "$DUR" -i "$BUILD/cap_02.png" \
  -loop 1 -t "$DUR" -i "$BUILD/cap_03.png" \
  -i "$BUILD/master.wav" \
  -filter_complex_script "$F" \
  -map "[v]" -map "[a]" \
  -r 30 -c:v libx264 -crf "$VCRF" -preset "$VPRESET" -pix_fmt yuv420p -movflags +faststart \
  -c:a aac -b:a 192k \
  "$OUT"
echo "wrote $OUT"
