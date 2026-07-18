#!/usr/bin/env python3
"""Render the same nagma with different performance-model settings for A/B listening.

The point of the app's first pillar is that a sampled harmonium *sounds like a
person playing*. That "human feel" lives in core/performance.py, whose knobs
(jitter, legato, bellows, dynamics) were set by reason, not by ear. This tool
renders one nagma many times — SAME seed, so every audible difference is the
knob and not RNG — into renders/ so you can play them back-to-back and decide
which direction each knob should move. Bake the winners into performance.py.

Run (needs fluidsynth + render deps in the venv):
    .venv/bin/python scripts/render_variants.py
"""

from __future__ import annotations

import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "core", "src"))
sys.path.insert(0, os.path.join(ROOT, "render", "src"))

import nagma_core.performance as perf  # noqa: E402
from nagma_core.compiler import compile_score  # noqa: E402
from nagma_core.parser import parse_nagma  # noqa: E402
from nagma_render.pipeline import render_score  # noqa: E402

SOUNDFONT = os.path.join(ROOT, "assets", "soundfonts", "harmonium.sf2")
OUTDIR = os.path.join(ROOT, "renders")
# Defaults; override on the command line:
#   render_variants.py [nagma_file] [--bpm N] [--sa KEY] [--seed N]
DEFAULT_NAGMA = os.path.join(ROOT, "assets", "nagmas", "proposed-teentaal.nagma")
SEED = 42

# Capture the shipped defaults so each variant starts from a known baseline.
DEF_JITTER = perf.JITTER_S
DEF_LEGATO = perf.LEGATO_OVERLAP_S
DEF_VELNOISE = perf.VELOCITY_NOISE
DEF_BASE_VEL = perf.base_velocity
DEF_BELLOWS_DEPTH = perf.BELLOWS_DEPTH
DEF_BELLOWS_RATE = perf.BELLOWS_RATE_HZ

# Each variant: filename, human note, and the knob overrides. Anything omitted
# falls back to the shipped default. `flat_velocity` swaps the taal-shaped
# dynamics for a constant (the robotic anchor).
VARIANTS = [
    dict(name="00_robotic", note="dead-MIDI anchor: no jitter, min legato, no bellows, flat dynamics",
         jitter=0.0, legato=0.004, bellows_depth=0.0, velnoise=0, flat_velocity=True),
    dict(name="01_baseline", note="shipped defaults"),
    dict(name="02_more_legato", note="legato 0.045 -> 0.090 (notes bleed more)",
         legato=0.090),
    dict(name="03_less_jitter", note="jitter 0.012 -> 0.006 (tighter)",
         jitter=0.006),
    dict(name="04_more_jitter", note="jitter 0.012 -> 0.020 (looser/human, risk sloppy)",
         jitter=0.020),
    dict(name="05_stronger_bellows", note="bellows depth 0.09 -> 0.16 (more breathing)",
         bellows_depth=0.16),
    dict(name="06_subtle_bellows", note="bellows depth 0.09 -> 0.05 (barely-there)",
         bellows_depth=0.05),
    dict(name="07_expressive_max", note="more legato + more jitter + stronger bellows combined",
         legato=0.080, jitter=0.018, bellows_depth=0.15),
    dict(name="08_superloop8", note="baseline knobs, 8 avartans instead of 4 (less repetitive?)",
         avartans=8),
]


def apply(v: dict) -> dict:
    """Set module knobs for this variant; return the bellows dict to stamp on the score."""
    perf.JITTER_S = v.get("jitter", DEF_JITTER)
    perf.LEGATO_OVERLAP_S = v.get("legato", DEF_LEGATO)
    perf.VELOCITY_NOISE = v.get("velnoise", DEF_VELNOISE)
    if v.get("flat_velocity"):
        perf.base_velocity = lambda matra, mark, matra_count: 92
    else:
        perf.base_velocity = DEF_BASE_VEL
    return {"rate_hz": v.get("bellows_rate", DEF_BELLOWS_RATE),
            "depth": v.get("bellows_depth", DEF_BELLOWS_DEPTH)}


def main(argv: list[str] | None = None) -> int:
    import argparse
    ap = argparse.ArgumentParser(description="Render performance-model A/B variants of a nagma.")
    ap.add_argument("nagma", nargs="?", default=DEFAULT_NAGMA, help="path to a .nagma file")
    ap.add_argument("--bpm", type=float, default=90)
    ap.add_argument("--sa", default="C")
    ap.add_argument("--seed", type=int, default=SEED)
    args = ap.parse_args(argv)
    NAGMA, BPM, SA, seed = args.nagma, args.bpm, args.sa, args.seed

    if not os.path.exists(SOUNDFONT):
        print(f"missing soundfont: {SOUNDFONT} (run scripts/build_harmonium.py)", file=sys.stderr)
        return 2
    os.makedirs(OUTDIR, exist_ok=True)
    text = open(NAGMA).read()

    print(f"Rendering {len(VARIANTS)} variants  ({os.path.basename(NAGMA)}, "
          f"{SA} Sa, {BPM:g} BPM, seed {seed})\n")
    rows = []
    for v in VARIANTS:
        bellows = apply(v)
        avartans = v.get("avartans", 4)
        doc = parse_nagma(text)
        score = compile_score(doc, bpm=BPM, sa=SA, avartans=avartans, seed=seed)
        score.bellows = bellows
        out = os.path.join(OUTDIR, f"{v['name']}.wav")
        render_score(score, SOUNDFONT, out)
        dur = score.loop_length_samples / score.sample_rate
        rows.append((v["name"], dur, v["note"]))
        print(f"  ✓ {v['name']:<20} {dur:5.1f}s  — {v['note']}")

    print(f"\nWrote {len(rows)} files to renders/. Suggested listen order:")
    print("  00_robotic  (hear the robot)  ->  01_baseline  ->  the rest.")
    print("Tell me which knob directions feel more human and I'll bake them in.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
