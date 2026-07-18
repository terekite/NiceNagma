"""`nagma-compile` — text nagma -> ExpressiveScore JSON.

Keeps `core` usable standalone (and drives the smoke test's first stage).
The render package consumes the score.json this produces.
"""

from __future__ import annotations

import argparse
import json
import sys

from .compiler import realize
from .parser import NagmaParseError, parse_nagma
from .reduce import laya_for_bpm


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(
        prog="nagma-compile",
        description="Compile a text-grammar nagma into an ExpressiveScore JSON.",
    )
    p.add_argument("nagma", help="Path to a .nagma text file, or '-' for stdin.")
    p.add_argument("--taal", default="teentaal")
    p.add_argument("--raag", default="bhairavi")
    p.add_argument("--bpm", type=float, required=True)
    p.add_argument("--sa", default="D", help="Sa key name, e.g. C#, D.")
    p.add_argument("--avartans", type=int, default=4)
    p.add_argument("--seed", type=int, default=0)
    p.add_argument("--sample-rate", type=int, default=44100)
    p.add_argument(
        "--laya", choices=["vilambit", "madhya", "drut"],
        help="Force a laya realization (default: auto-selected from --bpm).",
    )
    p.add_argument("-o", "--output", help="Output score.json path (default stdout).")
    args = p.parse_args(argv)

    text = sys.stdin.read() if args.nagma == "-" else open(args.nagma).read()

    try:
        doc = parse_nagma(text, taal=args.taal, raag=args.raag)
    except NagmaParseError as e:
        print(f"nagma parse error: {e}", file=sys.stderr)
        return 2

    score = realize(
        doc,
        bpm=args.bpm,
        sa=args.sa,
        laya=args.laya,
        avartans=args.avartans,
        seed=args.seed,
        sample_rate=args.sample_rate,
    )

    payload = json.dumps(score.to_dict(), indent=2)
    if args.output:
        with open(args.output, "w") as f:
            f.write(payload)
        laya = args.laya or laya_for_bpm(args.bpm)
        print(
            f"wrote {args.output}  [{laya}]  "
            f"({score.loop_length_samples} frames @ {score.sample_rate} Hz, "
            f"{len(score.events)} events)",
            file=sys.stderr,
        )
    else:
        print(payload)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
