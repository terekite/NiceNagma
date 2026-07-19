#!/usr/bin/env python3
"""Render sarangi audition WAVs the HARMONIUM way: real discrete multisample →
MIDI → fluidsynth(sarangi.sf2) → sarangi mastering preset. No synthesis, no meend.

Outputs to audition/ and copies to ~/Desktop/sarangi_audition/ for A/B listening
against REAL_TARGET_*.wav.
"""
from __future__ import annotations
import os, sys, shutil
sys.path[:0] = ["core/src", "render/src"]
import numpy as np
import soundfile as sf

from nagma_core.parser import parse_nagma
from nagma_core.compiler import realize
from nagma_render.pipeline import render_score

OUT = "audition"
SF2 = "assets/soundfonts/sarangi.sf2"
NAGMA = open("assets/nagmas/proposed-teentaal.nagma").read()
DESKTOP = os.path.expanduser("~/Desktop/sarangi_audition")


def render(bpm, name):
    doc = parse_nagma(NAGMA, taal="teentaal")
    score = realize(doc, bpm=bpm, sa="D", avartans=4, seed=0, instrument="sarangi")
    tmp = f"/tmp/{name}.wav"
    render_score(score, SF2, tmp)                       # midi -> fluidsynth -> master
    x, sr = sf.read(tmp, always_2d=True)
    x = np.tile(x, (2, 1))                              # 2x so the loop seam is audible
    out = os.path.join(OUT, name + ".wav")
    sf.write(out, x, sr)
    print(f"  wrote {name} ({len(x)/sr:.1f}s, peak={np.max(np.abs(x)):.3f})")
    return out


def main():
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(DESKTOP, exist_ok=True)
    for bpm, tag in ((80, "madhya"), (55, "vilambit")):
        out = render(bpm, f"40_sarangi_SAMPLED_{tag}")
        shutil.copy(out, DESKTOP)
    print("done ->", DESKTOP)


if __name__ == "__main__":
    main()
