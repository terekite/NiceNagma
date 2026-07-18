import math

import pytest

from nagma_core.compiler import compile_score
from nagma_core.parser import parse_nagma

STOCK = "S r g m | P d P m | g m P d | P m g r"


def _doc():
    return parse_nagma(STOCK)


@pytest.mark.parametrize("bpm,avartans,sr", [
    (80, 4, 44100),
    (120, 8, 44100),
    (137, 4, 48000),   # non-divisor bpm
    (60, 1, 44100),
])
def test_loop_length_is_exact(bpm, avartans, sr):
    score = compile_score(_doc(), bpm=bpm, sa="D", avartans=avartans, sample_rate=sr)
    assert score.matra_dur_s == 60.0 / bpm
    assert score.avartan_dur_s == 16 * (60.0 / bpm)
    assert score.loop_length_s == avartans * 16 * (60.0 / bpm)
    assert score.loop_length_samples == round(score.loop_length_s * sr)
    assert isinstance(score.loop_length_samples, int)


def test_sam_onsets_are_exact_no_jitter():
    bpm, avartans = 137, 4  # non-divisor bpm stresses the exactness claim
    score = compile_score(_doc(), bpm=bpm, sa="D", avartans=avartans, seed=99)
    avartan_dur = score.avartan_dur_s
    sam_events = [e for e in score.events if e.matra == 0 and e.structural]
    assert len(sam_events) == avartans
    for e in sam_events:
        # Sam must sit exactly on an avartan boundary.
        assert e.start_s == pytest.approx(e.avartan * avartan_dur, abs=1e-12)


def test_all_matra_boundaries_exact():
    score = compile_score(_doc(), bpm=93, sa="C#", avartans=2, seed=7)
    md = score.matra_dur_s
    for e in score.events:
        if e.structural:
            expected = e.avartan * score.avartan_dur_s + e.matra * md
            assert e.start_s == pytest.approx(expected, abs=1e-12)


def test_per_avartan_variation_differs():
    score = compile_score(_doc(), bpm=100, sa="D", avartans=4, seed=42)
    # Non-structural notes across avartans should not be byte-identical in
    # velocity for every event (the whole point of per-avartan seeds).
    by_av = {}
    for e in score.events:
        by_av.setdefault(e.avartan, []).append(e.velocity)
    assert by_av[0] != by_av[1]


def test_transposition_changes_pitch_not_timing():
    d = compile_score(_doc(), bpm=100, sa="D", avartans=1)
    cs = compile_score(_doc(), bpm=100, sa="C#", avartans=1)
    # C# is one semitone below D.
    for ed, ec in zip(d.events, cs.events):
        assert ed.midi - ec.midi == 1
        assert ed.start_s == ec.start_s


def test_repeated_pitch_rearticulates_not_tied():
    # "Sa Sa Sa ..." — three identical notes must not overlap, or the sampler
    # retriggers mid-note and the repeat sounds cut off.
    from nagma_core import performance as perf
    doc = parse_nagma("S S S S | P m g r | P d n S' | n d P m")
    score = compile_score(doc, bpm=90, sa="C", avartans=1)
    sa = [e for e in sorted(score.events, key=lambda e: e.start_s)
          if e.midi == score.sa_midi and e.matra < 4]
    assert len(sa) == 4
    for a, b in zip(sa, sa[1:]):
        gap = b.start_s - (a.start_s + a.dur_s)
        # a clean gap of at least (nearly) REARTICULATION_GAP_S, never overlap
        assert gap >= perf.REARTICULATION_GAP_S - 1e-6, f"repeated Sa overlaps: gap={gap}"


def test_distinct_pitches_keep_legato_overlap():
    # Different consecutive pitches SHOULD overlap (harmonium bleed) — the fix
    # must not strip legato everywhere.
    doc = parse_nagma("S r g m | P m g r | P d n S' | n d P m")
    score = compile_score(doc, bpm=90, sa="C", avartans=1)
    evs = sorted([e for e in score.events if e.avartan == 0], key=lambda e: e.start_s)
    a, b = evs[0], evs[1]  # S then r — distinct pitches
    assert a.start_s + a.dur_s > b.start_s, "distinct-pitch legato overlap was lost"


def test_wrong_matra_count_rejected():
    doc = parse_nagma(STOCK)
    doc.matras = doc.matras[:15]
    with pytest.raises(ValueError, match="requires 16"):
        compile_score(doc, bpm=80, sa="D")
