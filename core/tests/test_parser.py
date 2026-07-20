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


def test_up_to_four_subdivisions_ok():
    doc = parse_nagma("S,r,g,m R g m | P d P m | g m P d | P m g r")
    assert len(doc.matras[0].notes) == 4
    assert [n.swar for n in doc.matras[0].notes] == ["S", "r", "g", "m"]


def test_subdivision_with_sustain_ok():
    doc = parse_nagma("S,-,g,m R g m | P d P m | g m P d | P m g r")
    assert doc.matras[0].notes[1].kind == "sustain"


def test_too_many_notes_in_matra_errors():
    with pytest.raises(NagmaParseError, match="at most 4"):
        parse_nagma("S,r,g,m,P g m R | P d P m | g m P d | P m g r")


def test_leading_sustain_errors():
    with pytest.raises(NagmaParseError, match="cannot begin with a sustain"):
        parse_nagma("- r g m | P d P m | g m P d | P m g r")


# --- Non-teentaal taals: the parser validates against the passed taal's shape.

def test_parses_jhaptaal_ten_matras():
    # Jhaptaal vibhags 2+3+2+3.
    doc = parse_nagma("S r | g m P | d P | m g r", taal="jhaptaal")
    assert doc.taal == "jhaptaal"
    assert len(doc.matras) == 10
    assert [m.index for m in doc.matras] == list(range(10))


def test_parses_ektaal_twelve_matras_six_vibhags():
    doc = parse_nagma("S r\ng m\nP d\nn S'\nd P\nm g", taal="ektaal")
    assert len(doc.matras) == 12


def test_parses_dadra_six_matras():
    doc = parse_nagma("S r g | m g r", taal="dadra")
    assert len(doc.matras) == 6


def test_wrong_vibhag_count_for_taal_errors():
    # Teentaal-shaped text (4 vibhags) rejected against Jhaptaal (4 vibhags too,
    # but the matra lengths differ) -> per-vibhag length check fires.
    with pytest.raises(NagmaParseError, match="should have 2 matras"):
        parse_nagma("S r g m | P d P m | g m P d | P m g r", taal="jhaptaal")


def test_wrong_line_count_for_ektaal_errors():
    with pytest.raises(NagmaParseError, match="6 vibhags"):
        parse_nagma("S r | g m | P d", taal="ektaal")
