"""`nagma-render` — the command from the spec:

    nagma-render score.json -o loop.wav --soundfont harmonium.sf2

Takes a compiled ExpressiveScore JSON (produced by `nagma-compile`) and writes a
gapless, exact-length loop WAV.
"""

from __future__ import annotations

import argparse
import json
import os
import sys

from nagma_core.models import ExpressiveScore

from .pipeline import render_score
from .sampler import SamplerNotAvailable

_DEFAULT_SF = os.environ.get("NAGMA_SOUNDFONT", "")


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(
        prog="nagma-render",
        description="Render an ExpressiveScore JSON to a gapless loop WAV.",
    )
    p.add_argument("score", help="Path to a compiled score.json (from nagma-compile).")
    p.add_argument("-o", "--output", required=True, help="Output WAV path.")
    p.add_argument(
        "--soundfont",
        default=_DEFAULT_SF,
        help="Path to the harmonium SF2/SF3 soundfont "
        "(or set NAGMA_SOUNDFONT).",
    )
    p.add_argument(
        "--keep-intermediates", action="store_true",
        help="Keep the intermediate MIDI/raw WAV for debugging.",
    )
    args = p.parse_args(argv)

    if not args.soundfont:
        print(
            "error: no soundfont given. Pass --soundfont PATH or set "
            "NAGMA_SOUNDFONT. Drop an SF2 into assets/soundfonts/ (see "
            "assets/LICENSES.md).",
            file=sys.stderr,
        )
        return 2
    if not os.path.exists(args.soundfont):
        print(f"error: soundfont not found: {args.soundfont}", file=sys.stderr)
        return 2

    with open(args.score) as f:
        score = ExpressiveScore.from_dict(json.load(f))

    try:
        render_score(
            score, args.soundfont, args.output,
            keep_intermediates=args.keep_intermediates,
        )
    except SamplerNotAvailable as e:
        print(f"error: {e}", file=sys.stderr)
        return 3

    print(
        f"wrote {args.output}  "
        f"({score.loop_length_samples} frames @ {score.sample_rate} Hz)",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
