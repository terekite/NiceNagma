#!/usr/bin/env python3
"""The correctness gate: assert a score (and optional rendered WAV) loop exactly.

Usage:
    assert_loop_length.py score.json [--wav loop.wav]

Checks:
  1. loop_length_samples == round(loop_length_s * sample_rate)   (score self-consistency)
  2. avartan_dur_s == matra_count * matra_dur_s and matra_dur_s == 60/bpm
  3. every structural (matra-boundary) onset sits exactly on the grid — no jitter
  4. if --wav given: the WAV frame count == loop_length_samples EXACTLY

Uses only the stdlib so it runs anywhere, no fluidsynth/numpy needed for (1)-(3).
"""

from __future__ import annotations

import argparse
import json
import sys
import wave


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("score")
    ap.add_argument("--wav")
    args = ap.parse_args(argv)

    with open(args.score) as f:
        s = json.load(f)

    sr = s["sample_rate"]
    bpm = s["bpm"]
    mc = s["matra_count"]
    problems: list[str] = []

    expected_matra = 60.0 / bpm
    if abs(s["matra_dur_s"] - expected_matra) > 1e-12:
        problems.append(
            f"matra_dur_s {s['matra_dur_s']} != 60/bpm {expected_matra}"
        )
    if abs(s["avartan_dur_s"] - mc * s["matra_dur_s"]) > 1e-9:
        problems.append("avartan_dur_s != matra_count * matra_dur_s")
    expected_samples = round(s["loop_length_s"] * sr)
    if s["loop_length_samples"] != expected_samples:
        problems.append(
            f"loop_length_samples {s['loop_length_samples']} != "
            f"round(loop_length_s*sr) {expected_samples}"
        )

    # Structural onsets must be exact (no jitter) on the matra grid.
    for e in s["events"]:
        if e["structural"]:
            exp = e["avartan"] * s["avartan_dur_s"] + e["matra"] * s["matra_dur_s"]
            if abs(e["start_s"] - exp) > 1e-9:
                problems.append(
                    f"structural onset off-grid: matra {e['matra']} "
                    f"avartan {e['avartan']} start {e['start_s']} != {exp}"
                )
                break

    if args.wav:
        with wave.open(args.wav, "rb") as w:
            frames = w.getnframes()
            wav_sr = w.getframerate()
        if wav_sr != sr:
            problems.append(f"wav sample rate {wav_sr} != score {sr}")
        if frames != s["loop_length_samples"]:
            problems.append(
                f"WAV frame count {frames} != loop_length_samples "
                f"{s['loop_length_samples']} (loop would drift!)"
            )

    if problems:
        print("LOOP LENGTH CHECK FAILED:", file=sys.stderr)
        for p in problems:
            print(f"  - {p}", file=sys.stderr)
        return 1

    tail = f", wav={args.wav} frames match" if args.wav else " (score only)"
    print(
        f"OK: {s['loop_length_samples']} frames @ {sr} Hz, {bpm} BPM, "
        f"{s['avartans']} avartans{tail}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
