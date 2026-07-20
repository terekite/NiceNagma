import pytest

from nagma_core.parser import parse_nagma
from nagma_core.reduce import laya_for_bpm, reduce_doc
from nagma_core.taal import get_taal

# Dense vilambit: 4- and 2-slot matras; slot-0 = Bhairavi skeleton.
VILAMBIT = (
    "S,r,g,r r,g g,m,P,m m,P | P,m,g,m m,g g,r r,S | "
    "P,d,n,d d,n n,S' S',n | n,d d,P P,m,g,m m,g"
)


def _struck(doc):
    return [n for m in doc.matras for n in m.notes if n.kind == "swar"]


def _authored_pitches(doc):
    return {(n.swar, n.octave) for n in _struck(doc)}


def test_laya_for_bpm_thresholds():
    assert laya_for_bpm(60) == "vilambit"
    assert laya_for_bpm(85) == "vilambit"
    assert laya_for_bpm(86) == "madhya"
    assert laya_for_bpm(160) == "madhya"
    assert laya_for_bpm(161) == "drut"
    assert laya_for_bpm(240) == "drut"


def test_vilambit_is_identity():
    doc = parse_nagma(VILAMBIT)
    red = reduce_doc(doc, "vilambit")
    assert [(n.swar, n.octave) for n in _struck(red)] == \
           [(n.swar, n.octave) for n in _struck(doc)]


def test_madhya_reduces_density_and_caps_at_two_per_matra():
    doc = parse_nagma(VILAMBIT)
    red = reduce_doc(doc, "madhya")
    assert len(_struck(red)) < len(_struck(doc))
    for m in red.matras:
        assert sum(1 for n in m.notes if n.kind == "swar") <= 2


def test_drut_is_at_most_one_per_matra_and_sparser_than_madhya():
    doc = parse_nagma(VILAMBIT)
    madhya = reduce_doc(doc, "madhya")
    drut = reduce_doc(doc, "drut")
    for m in drut.matras:
        assert sum(1 for n in m.notes if n.kind == "swar") <= 1
    assert len(_struck(drut)) <= len(_struck(madhya))


def test_drut_protects_sam_and_vibhag_heads():
    doc = parse_nagma(VILAMBIT)
    drut = reduce_doc(doc, "drut")
    marks = get_taal(doc.taal).matra_marks()
    for m in drut.matras:
        if marks[m.index] != "plain":  # sam / taali / khaali
            assert m.notes[0].kind == "swar", f"matra {m.index} ({marks[m.index]}) must stay struck"


def test_drut_omits_repeated_plain_matras():
    # matras 2 and 3 repeat Sa on plain beats -> held (omitted) at drut.
    doc = parse_nagma("S S S m | P m g r | P d n S' | n d P m")
    drut = reduce_doc(doc, "drut")
    assert drut.matras[0].notes[0].kind == "swar"   # sam Sa struck
    assert drut.matras[1].notes[0].kind == "sustain"  # repeat -> held
    assert drut.matras[2].notes[0].kind == "sustain"  # repeat -> held
    assert drut.matras[4].notes[0].kind == "swar"   # taali P struck


def test_drut_protects_structural_heads_non_teentaal():
    # Reduction is data-driven off matra_marks, so it protects sam/taali/khaali
    # for any taal — here Pancham Sawari (15 matras, 3+4+4+4).
    doc = parse_nagma("S r g\nm P m g\nr S r g\nm P d n", taal="pancham_sawari")
    drut = reduce_doc(doc, "drut")
    marks = get_taal("pancham_sawari").matra_marks()
    assert len(drut.matras) == 15
    for m in drut.matras:
        if marks[m.index] != "plain":
            assert m.notes[0].kind == "swar", \
                f"matra {m.index} ({marks[m.index]}) must stay struck"


@pytest.mark.parametrize("laya", ["vilambit", "madhya", "drut"])
def test_reduction_never_invents_pitches(laya):
    doc = parse_nagma(VILAMBIT)
    allowed = _authored_pitches(doc)
    red = reduce_doc(doc, laya)
    for n in _struck(red):
        assert (n.swar, n.octave) in allowed
