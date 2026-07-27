#!/bin/bash
# Assemble the NiceNagma product demo film (9:16 vertical mp4) from:
#   * demo/build/raw.mov      — screen capture of the driven app (integration_test/demo_drive.dart)
#   * demo/build/bg.png,mask.png,cap_*.png  — branded overlays (scripts/demo_assets.py)
#   * demo/audio/*.wav         — harmonium lehra + tanpura drone (fluidsynth)
#
# Layout: the phone screen sits fit-height, rounded + shadowed, on a dark warm
# gradient; a lower-third caption fades in per feature beat; harmonium enters on
# "Play" and the tanpura swells in at the "Add the tanpura" beat.
#
# Re-run end to end with:  ./scripts/make_demo.sh
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD=demo/build
AUDIO=demo/audio
OUT=demo/NiceNagma-demo.mp4
SF=assets/soundfonts
FONT=/System/Library/Fonts/HelveticaNeue.ttc

SS=0.30          # trim: first clean app frame
DUR=51.0         # usable footage length (before springboard at ~51.5s)

# DRAFT=1 → fast, low-res preview for checking timing/layout (not for delivery).
if [ "${DRAFT:-0}" = "1" ]; then
  VPRESET=ultrafast; VCRF=30; SCALE_OUT="scale=540:960"; OUT=demo/NiceNagma-draft.mp4
else
  VPRESET=medium; VCRF=19; SCALE_OUT="null"; OUT=demo/NiceNagma-demo.mp4
fi

# ---- 1. overlays (idempotent) -------------------------------------------------
python3 scripts/demo_assets.py "$BUILD" >/dev/null

# ---- 2. soundtrack (idempotent) ----------------------------------------------
if [ ! -f "$AUDIO/harm_tt_D80.wav" ]; then
  export PYTHONPATH=core/src:render/src
  printf 'S S S N.,S\ng R N. S\nM. P. g. R.,S.\ng. M. P. N.\n' > "$BUILD/teentaal.nagma"
  python3 -m nagma_core.cli "$BUILD/teentaal.nagma" --taal teentaal --bpm 80 --sa D \
    --avartans 4 --seed 7 -o "$BUILD/score_tt_D80.json"
  python3 -m nagma_render.cli "$BUILD/score_tt_D80.json" -o "$AUDIO/harm_tt_D80.wav" \
    --soundfont "$SF/harmonium.sf2"
fi
if [ ! -f "$AUDIO/tanpura_D.wav" ]; then
  python3 scripts/make_tanpura.py "$BUILD/tanpura_D.mid"
  fluidsynth -ni -F "$AUDIO/tanpura_D.wav" -r 44100 -g 0.7 "$SF/tanpura.sf2" "$BUILD/tanpura_D.mid"
fi

# ---- 3. caption windows (trimmed time, seconds) ------------------------------
#         cap index : t0 t1   (fade 0.4s each edge)
CAPS=(
  "0 0.8 4.3"      # intro tagline
  "1 5.0 11.5"     # Play a lehra
  "2 12.2 18.0"    # Pick your Sa
  "3 19.2 24.9"    # Set your tempo
  "4 25.2 30.4"    # Add the tanpura
  "5 30.9 38.3"    # Switch the taal
  "6 38.7 41.4"    # Write your own
  "7 42.4 50.4"    # outro line
)

# ---- 4. build the filtergraph ------------------------------------------------
F="$BUILD/filter.txt"
{
  # raw.mov from simctl is variable-frame-rate; alphamerge's framesync mis-syncs
  # VFR video against the CFR mask and truncates the phone stream (froze at ~23s).
  # Force both to constant 30 fps with reset PTS so alphamerge runs full length.
  echo "[0:v]fps=30,setpts=PTS-STARTPTS,scale=754:1640,setsar=1[ph];"
  echo "[2:v]fps=30,setpts=PTS-STARTPTS,scale=754:1640,format=gray[mk];"
  echo "[ph][mk]alphamerge[phm];"
  echo "[1:v]scale=1080:1920,setsar=1[bg];"
  echo "[bg][phm]overlay=163:140:format=auto[base];"
  prev="base"; idx=3
  for c in "${CAPS[@]}"; do
    read -r ci t0 t1 <<<"$c"
    fo=$(echo "$t1 - 0.4" | bc)
    echo "[${idx}:v]format=rgba,fade=t=in:st=${t0}:d=0.4:alpha=1,fade=t=out:st=${fo}:d=0.4:alpha=1[c${ci}];"
    echo "[${prev}][c${ci}]overlay=0:0:enable='between(t\,${t0}\,${t1})'[b${ci}];"
    prev="b${ci}"; idx=$((idx+1))
  done
  # Subtle static grain (grain_overlay.png, screen-blended) instead of the per-frame
  # noise filter, which defeated interframe compression (5.6h encode, 340 MB file).
  echo "[${prev}][13:v]blend=all_mode=screen:all_opacity=0.05[gr];"
  echo "[gr]vignette=PI/6,fade=t=in:st=0:d=0.6,fade=t=out:st=$(echo "$DUR - 0.8"|bc):d=0.8,${SCALE_OUT},format=yuv420p[v];"
  # ---- audio: harmonium enters on Play (~4.7s); tanpura swells at ~26s ----
  echo "[11:a]afade=t=in:st=4.7:d=1.6,afade=t=out:st=49.4:d=1.4,volume=0.92[harm];"
  echo "[12:a]volume='max(0\,min(1\,t/1.6))*max(0\,min(1\,(50.2-t)/1.4))*(0.13+0.42*max(0\,min(1\,(t-26)/4)))':eval=frame[tanp];"
  # amix in ffmpeg 4.2 averages inputs (no 'normalize'); boost back up post-mix.
  echo "[harm][tanp]amix=inputs=2:duration=first[mx];"
  echo "[mx]volume=2.3,alimiter=limit=0.97,aresample=44100,atrim=0:${DUR},asetpts=PTS-STARTPTS[a]"
} > "$F"

# ---- 5. render ---------------------------------------------------------------
ffmpeg -y -hide_banner -loglevel error \
  -ss "$SS" -t "$DUR" -i "$BUILD/raw.mov" \
  -loop 1 -t "$DUR" -i "$BUILD/bg.png" \
  -loop 1 -t "$DUR" -i "$BUILD/mask.png" \
  -loop 1 -t "$DUR" -i "$BUILD/cap_00.png" \
  -loop 1 -t "$DUR" -i "$BUILD/cap_01.png" \
  -loop 1 -t "$DUR" -i "$BUILD/cap_02.png" \
  -loop 1 -t "$DUR" -i "$BUILD/cap_03.png" \
  -loop 1 -t "$DUR" -i "$BUILD/cap_04.png" \
  -loop 1 -t "$DUR" -i "$BUILD/cap_05.png" \
  -loop 1 -t "$DUR" -i "$BUILD/cap_06.png" \
  -loop 1 -t "$DUR" -i "$BUILD/cap_07.png" \
  -stream_loop -1 -t "$DUR" -i "$AUDIO/harm_tt_D80.wav" \
  -stream_loop -1 -t "$DUR" -i "$AUDIO/tanpura_D.wav" \
  -loop 1 -t "$DUR" -i "$BUILD/grain.png" \
  -filter_complex_script "$F" \
  -map "[v]" -map "[a]" \
  -r 30 -c:v libx264 -crf "$VCRF" -preset "$VPRESET" -pix_fmt yuv420p -movflags +faststart \
  -c:a aac -b:a 192k \
  "$OUT"
echo "wrote $OUT"
