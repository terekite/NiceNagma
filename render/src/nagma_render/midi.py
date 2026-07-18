"""ExpressiveScore -> Standard MIDI File.

The score already carries absolute-second onsets, so we pick a fixed tempo/PPQ
and convert seconds->ticks losslessly. fluidsynth then renders this MIDI. All
expressive timing/velocity is already baked into the score; MIDI is just a
transport format here.
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


def _sec_to_ticks(seconds: float) -> int:
    return round(seconds / _SEC_PER_BEAT * _TICKS_PER_BEAT)


def score_to_midi(score: ExpressiveScore, path: str, *, program: int = DEFAULT_PROGRAM) -> None:
    """Write the score to a MIDI file at `path`. Requires the `mido` package."""
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
    track.append(mido.Message("program_change", program=program, time=0))

    # Build an absolute-tick event list (note on/off), then delta-encode.
    abs_events: list[tuple[int, int, int, int]] = []  # (tick, prio, midi, velocity)
    for e in score.events:
        on = _sec_to_ticks(e.start_s)
        off = _sec_to_ticks(e.start_s + e.dur_s)
        if off <= on:
            off = on + 1
        # prio: note-off (0) before note-on (1) at the same tick so a repeated
        # pitch retriggers cleanly.
        abs_events.append((on, 1, e.midi, e.velocity))
        abs_events.append((off, 0, e.midi, 0))

    abs_events.sort(key=lambda x: (x[0], x[1]))

    prev_tick = 0
    for tick, prio, midi, vel in abs_events:
        delta = tick - prev_tick
        prev_tick = tick
        if prio == 1:
            track.append(mido.Message("note_on", note=midi, velocity=vel, time=delta))
        else:
            track.append(mido.Message("note_off", note=midi, velocity=0, time=delta))

    mid.save(path)
