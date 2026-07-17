import pytest

from nagma_core.parser import NagmaParseError, parse_nagma

STOCK = """
# Bhairavi teentaal stock nagma
S r g m
P d P m
g m P d
P m g r
"""


def test_parses_teentaal_16_matras():
    doc = parse_nagma(STOCK)
    assert doc.taal == "teentaal"
    assert len(doc.matras) == 16
    assert [m.index for m in doc.matras] == list(range(16))


def test_single_line_pipe_separated():
    doc = parse_nagma("S r g m | P d P m | g m P d | P m g r")
    assert len(doc.matras) == 16
    assert doc.matras[0].notes[0].swar == "S"


def test_octave_markers():
    doc = parse_nagma("S. r g m | P d P m | g m P d | P m g r'")
    assert doc.matras[0].notes[0].octave == "mandra"
    assert doc.matras[15].notes[0].octave == "taar"


def test_split_matra_and_sustain():
    doc = parse_nagma("S,r g m - | P d P m | g m P d | P m g r")
    assert len(doc.matras[0].notes) == 2
    assert doc.matras[0].notes[1].swar == "r"
    assert doc.matras[3].notes[0].kind == "sustain"


def test_unknown_swar_errors():
    with pytest.raises(NagmaParseError, match="Unknown swar"):
        parse_nagma("S X g m | P d P m | g m P d | P m g r")


def test_wrong_vibhag_count_errors():
    with pytest.raises(NagmaParseError, match="4 vibhags"):
        parse_nagma("S r g m | P d P m | g m P d")


def test_wrong_matra_count_in_vibhag_errors():
    with pytest.raises(NagmaParseError, match="should have 4 matras"):
        parse_nagma("S r g | P d P m | g m P d | P m g r")


def test_too_many_notes_in_matra_errors():
    with pytest.raises(NagmaParseError, match="at most 2"):
        parse_nagma("S,r,g g m P | P d P m | g m P d | P m g r")


def test_leading_sustain_errors():
    with pytest.raises(NagmaParseError, match="cannot begin with a sustain"):
        parse_nagma("- r g m | P d P m | g m P d | P m g r")
