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


def test_swell_set_and_scales_with_duration():
    # matra index 3 ("m,P") splits into two half-length notes; the full-length
    # matras hold longer and should swell more than the split halves.
    doc = parse_nagma("S R g m,P | P m g r | P d n S' | n d P m")
    score = compile_score(doc, bpm=70, sa="C", avartans=1, seed=1)
    for e in score.events:
        assert 0.0 <= e.swell <= 0.5
    full = [e for e in score.events if e.matra == 0]        # whole matra
    split = [e for e in score.events if e.matra == 3]       # split -> half length
    assert len(split) == 2
    assert sum(e.swell for e in full) / len(full) > sum(e.swell for e in split) / len(split)


def test_grace_notes_ornament_without_disturbing_the_grid():
    doc = parse_nagma(STOCK)
    score = compile_score(doc, bpm=70, sa="C", avartans=4, seed=42)
    pitch_set = sorted({e.midi for e in score.events if e.structural})
    graces = [e for e in score.events
              if not e.structural and e.swell == 0.0 and e.dur_s < 0.12]
    assert graces, "expected some kan grace notes at the default density"
    for g in graces:
        assert not g.structural                       # ornaments never structural
        assert g.midi in pitch_set                    # kan is in-scale (composition pitches)
    # Structural (matra-boundary) onsets must remain exact despite ornaments.
    md = score.matra_dur_s
    for e in score.events:
        if e.structural:
            expected = e.avartan * score.avartan_dur_s + e.matra * md
            assert e.start_s == pytest.approx(expected, abs=1e-9)


def test_wrong_matra_count_rejected():
    doc = parse_nagma(STOCK)
    doc.matras = doc.matras[:15]
    with pytest.raises(ValueError, match="requires 16"):
        compile_score(doc, bpm=80, sa="D")


# --- Non-teentaal taals compile with the right length and exact boundaries ----

@pytest.mark.parametrize("text,taal,matra_count", [
    ("S r g | m g r", "dadra", 6),
    ("S g m | P m | g r", "rupak", 7),
    ("S r | g m P | d P | m g r", "jhaptaal", 10),
    ("S r\ng m\nP d\nn S'\nd P\nm g", "ektaal", 12),
    ("S r g m P\nd P\nm g r\nS r g m", "dhamar", 14),
    ("S r g\nm P m g\nr S r g\nm P d n", "pancham_sawari", 15),
])
def test_non_teentaal_loop_length_and_boundaries(text, taal, matra_count):
    doc = parse_nagma(text, taal=taal)
    score = compile_score(doc, bpm=95, sa="D", avartans=3, seed=5)
    assert score.matra_count == matra_count
    assert score.avartan_dur_s == pytest.approx(matra_count * (60.0 / 95), abs=1e-12)
    assert score.loop_length_samples == round(score.loop_length_s * score.sample_rate)
    # Every structural onset sits exactly on the grid.
    md = score.matra_dur_s
    for e in score.events:
        if e.structural:
            expected = e.avartan * score.avartan_dur_s + e.matra * md
            assert e.start_s == pytest.approx(expected, abs=1e-12)


def test_post_khaali_dip_follows_actual_khaali_not_midpoint():
    # Ektaal has khaali at matras 2 and 6 (not the 12//2=6 midpoint alone). The
    # post-khaali dip must land on matras 3 and 7 (right after each khaali).
    from nagma_core import performance as perf
    from nagma_core.taal import get_taal
    marks = get_taal("ektaal").matra_marks()
    # matra 3 follows a khaali (dip -4) while matra 5 does not; matra 3's swell
    # term is smaller too, so it must be strictly softer than matra 5.
    v3 = perf.base_velocity(3, marks[3], 12, marks)
    v5 = perf.base_velocity(5, marks[5], 12, marks)  # not after a khaali
    assert v3 < v5
    # Sanity: matra 7 (after khaali@6) is also dipped relative to its neighbour 9.
    v7 = perf.base_velocity(7, marks[7], 12, marks)
    v9 = perf.base_velocity(9, marks[9], 12, marks)
    assert v7 < v9
