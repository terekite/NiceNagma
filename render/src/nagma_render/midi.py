"""ExpressiveScore -> Standard MIDI File.

The score carries absolute-second onsets, so we pick a fixed tempo/PPQ and
convert seconds->ticks losslessly. fluidsynth then renders this MIDI.

Beyond note on/off, this emits per-note **CC11 (expression) swells** — a note
starts at (1-swell) of full and rises to full over its attack, modeling a
harmonium player's bellows building pressure. Because CC is per-CHANNEL, notes
are spread across the 16 MIDI channels by a greedy allocator so one note's swell
never bleeds onto an overlapping note (the multi-channel keystone).
"""

from __future__ import annotations

from nagma_core.models import ExpressiveScore

# Fixed conversion basis. 500000 us/beat = 120 BPM = 0.5 s/beat.
_US_PER_BEAT = 500_000
_SEC_PER_BEAT = _US_PER_BEAT / 1_000_000.0
_TICKS_PER_BEAT = 960

# Our multisampled harmonium SF2 (scripts/build_harmonium.py) puts its single
# preset at bank 0, program 0. Select it explicitly.
DEFAULT_PROGRAM = 0

# Channels a note may use — all except 9 (GM percussion).
_CHANNELS = [c for c in range(16) if c != 9]
# A voice keeps sounding for ~this long after note-off (SF2 release env), so a
# channel isn't reused until then, or the reused channel's CC11 would bend the
# previous note's release tail.
_RELEASE_TAIL_S = 0.35
# Fraction of a note over which the swell rises to full; capped in seconds.
_SWELL_ATTACK_FRAC = 0.5
_SWELL_ATTACK_MAX_S = 0.6
_SWELL_STEPS = 8


def _sec_to_ticks(seconds: float) -> int:
    return round(seconds / _SEC_PER_BEAT * _TICKS_PER_BEAT)


def _allocate_channel(free_at: dict[int, float], start_s: float, end_s: float) -> int:
    """Greedy interval colouring: lowest channel free at start_s; else the one
    that frees earliest. Updates free_at for the chosen channel."""
    ch = next((c for c in _CHANNELS if free_at[c] <= start_s + 1e-9), None)
    if ch is None:
        ch = min(_CHANNELS, key=lambda c: free_at[c])
    free_at[ch] = end_s + _RELEASE_TAIL_S
    return ch


def _swell_cc(on: int, off: int, depth: float) -> list[tuple[int, int]]:
    """CC11 (tick, value) pairs: start at (1-depth)*127, ramp to 127 over the
    attack, then hold. Empty depth -> a single full-level set."""
    start = int(round(127 * (1.0 - depth)))
    pairs = [(on, start)]
    if depth <= 0:
        return pairs
    attack = min(int((off - on) * _SWELL_ATTACK_FRAC), _sec_to_ticks(_SWELL_ATTACK_MAX_S))
    for k in range(1, _SWELL_STEPS + 1):
        t = on + attack * k // _SWELL_STEPS
        v = int(round(start + (127 - start) * k / _SWELL_STEPS))
        pairs.append((t, v))
    return pairs


def score_to_midi(score: ExpressiveScore, path: str, *, program: int = DEFAULT_PROGRAM) -> None:
    """Write the score to a multi-channel MIDI file. Requires the `mido` package."""
    try:
        import mido
    except ModuleNotFoundError as e:  # pragma: no cover - env-dependent
        raise RuntimeError(
            "mido is required to build MIDI. Install render deps: "
            "`uv pip install -e render[dev]` or `pip install mido`."
        ) from e

    mid = mido.MidiFile(ticks_per_beat=_TICKS_PER_BEAT)
    track = mido.MidiTrack()
    mid.tracks.append(track)
    track.append(mido.MetaMessage("set_tempo", tempo=_US_PER_BEAT, time=0))

    # (tick, order, kind, channel, a, b) — order sequences same-tick messages:
    # 0 note_off / program, 1 control_change, 2 note_on (so a note's start-level
    # CC and any prior note-off land before its note_on).
    events: list[tuple[int, int, str, int, int, int]] = []
    free_at = {c: -1e9 for c in _CHANNELS}
    used: set[int] = set()

    for e in sorted(score.events, key=lambda ev: ev.start_s):
        on = _sec_to_ticks(e.start_s)
        off = _sec_to_ticks(e.start_s + e.dur_s)
        if off <= on:
            off = on + 1
        ch = _allocate_channel(free_at, e.start_s, e.start_s + e.dur_s)
        used.add(ch)
        for t, v in _swell_cc(on, off, getattr(e, "swell", 0.0) or 0.0):
            events.append((t, 1, "cc", ch, 11, v))
        events.append((on, 2, "on", ch, e.midi, e.velocity))
        events.append((off, 0, "off", ch, e.midi, 0))

    for ch in sorted(used):
        events.append((0, 0, "prog", ch, program, 0))

    events.sort(key=lambda x: (x[0], x[1]))
    prev = 0
    for tick, _order, kind, ch, a, b in events:
        dt = tick - prev
        prev = tick
        if kind == "prog":
            track.append(mido.Message("program_change", channel=ch, program=a, time=dt))
        elif kind == "cc":
            track.append(mido.Message("control_change", channel=ch, control=a, value=b, time=dt))
        elif kind == "on":
            track.append(mido.Message("note_on", channel=ch, note=a, velocity=b, time=dt))
        else:
            track.append(mido.Message("note_off", channel=ch, note=a, velocity=0, time=dt))

    mid.save(path)
