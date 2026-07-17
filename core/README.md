# core/ — pure domain logic

Zero I/O (bar the `nagma-compile` CLI). No dependency on `render` or `app`, and
no third-party runtime deps — just the stdlib, so its tests run anywhere.

## What's here
- `taal.py` — taal definitions (Teentaal now; structure is taal-agnostic).
- `sargam.py` — swar→semitone map, Sa key→MIDI, octave markers.
- `parser.py` — sargam text grammar → validated `NagmaDoc`, with friendly errors.
- `compiler.py` — `NagmaDoc` + (BPM, Sa) → `ExpressiveScore`. Enforces exact laya.
- `performance.py` — the "human" layer: jitter, dynamics, legato, per-avartan variation.
- `models.py` — dataclasses mirroring `../contracts/*.schema.json`.
- `cli.py` — `nagma-compile`.

## Grammar (v1)
`S R G m | P - D P | ...` — vibhags split on newline or `|`; matras are
space-separated; `,` splits a matra into two notes (max 2); `-` sustains; a
trailing `'` = taar (upper octave), `.` = mandra (lower).

## Test
```bash
PYTHONPATH=src pytest -q
```
