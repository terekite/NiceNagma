"""Multi-channel MIDI allocator + CC11 swell tests."""

import pytest

mido = pytest.importorskip("mido")

from nagma_core.compiler import compile_score
from nagma_core.parser import parse_nagma
from nagma_render.midi import score_to_midi

STOCK = "S r g m | P m g r | P d n S' | n d P m"


def _midi(tmp_path, bpm=70, avartans=2):
    score = compile_score(parse_nagma(STOCK), bpm=bpm, sa="C", avartans=avartans, seed=3)
    path = tmp_path / "s.mid"
    score_to_midi(score, str(path))
    return mido.MidiFile(str(path)), score


def _note_intervals_by_channel(mid):
    """Return {channel: [(on_tick, off_tick), ...]} from absolute-timed messages."""
    t = 0
    open_notes = {}  # (channel, note) -> on_tick
    intervals = {}
    for msg in mid.tracks[0]:
        t += msg.time
        if msg.type == "note_on" and msg.velocity > 0:
            open_notes[(msg.channel, msg.note)] = t
        elif msg.type == "note_off" or (msg.type == "note_on" and msg.velocity == 0):
            key = (msg.channel, msg.note)
            if key in open_notes:
                intervals.setdefault(msg.channel, []).append((open_notes.pop(key), t))
    return intervals


def test_no_overlapping_notes_share_a_channel(tmp_path):
    mid, _ = _midi(tmp_path)
    by_ch = _note_intervals_by_channel(mid)
    for ch, ivs in by_ch.items():
        ivs.sort()
        for (s0, e0), (s1, e1) in zip(ivs, ivs[1:]):
            assert s1 >= e0, f"channel {ch} has overlapping notes: {(s0, e0)} & {(s1, e1)}"


def test_channel_9_never_used(tmp_path):
    mid, _ = _midi(tmp_path)
    for msg in mid.tracks[0]:
        if msg.type in ("note_on", "note_off"):
            assert msg.channel != 9, "channel 9 (GM drums) must not be used"


def test_cc11_swell_emitted(tmp_path):
    mid, score = _midi(tmp_path)
    cc11 = [m for m in mid.tracks[0] if m.type == "control_change" and m.control == 11]
    assert cc11, "expected CC11 expression events for swells"
    # at least one note should start below full expression (a real swell)
    assert any(m.value < 127 for m in cc11), "swell should dip expression below full"


def test_program_change_on_used_channels(tmp_path):
    mid, _ = _midi(tmp_path)
    progs = {m.channel for m in mid.tracks[0] if m.type == "program_change"}
    notes = {m.channel for m in mid.tracks[0]
             if m.type == "note_on" and m.velocity > 0}
    assert notes.issubset(progs), "every channel that plays notes needs a program_change"
