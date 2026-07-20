import pytest

from nagma_core.taal import TAALS, get_taal

# Expected per-matra structural marks (0-based) for every shipped taal. This is
# the authoritative table the Dart port (app/lib/render/taal.dart + taal.dart)
# and cycle wheel must agree with.
S, T, K, P = "sam", "taali", "khaali", "plain"

EXPECTED = {
    "teentaal": {
        "matra_count": 16,
        "vibhag_lengths": (4, 4, 4, 4),
        "marks": [S, P, P, P, T, P, P, P, K, P, P, P, T, P, P, P],
        "sam_is_khaali": False,
    },
    "dadra": {
        "matra_count": 6,
        "vibhag_lengths": (3, 3),
        "marks": [S, P, P, K, P, P],
        "sam_is_khaali": False,
    },
    "rupak": {
        "matra_count": 7,
        "vibhag_lengths": (3, 2, 2),
        "marks": [S, P, P, T, P, T, P],
        "sam_is_khaali": True,
    },
    "jhaptaal": {
        "matra_count": 10,
        "vibhag_lengths": (2, 3, 2, 3),
        "marks": [S, P, T, P, P, K, P, T, P, P],
        "sam_is_khaali": False,
    },
    "ektaal": {
        "matra_count": 12,
        "vibhag_lengths": (2, 2, 2, 2, 2, 2),
        "marks": [S, P, K, P, T, P, K, P, T, P, T, P],
        "sam_is_khaali": False,
    },
    "dhamar": {
        "matra_count": 14,
        "vibhag_lengths": (5, 2, 3, 4),
        "marks": [S, P, P, P, P, T, P, K, P, P, T, P, P, P],
        "sam_is_khaali": False,
    },
    "pancham_sawari": {
        "matra_count": 15,
        "vibhag_lengths": (3, 4, 4, 4),
        "marks": [S, P, P, T, P, P, P, K, P, P, P, T, P, P, P],
        "sam_is_khaali": False,
    },
}


def test_registry_has_exactly_the_shipped_taals():
    assert set(TAALS) == set(EXPECTED)


@pytest.mark.parametrize("name", sorted(EXPECTED))
def test_taal_structure(name):
    taal = get_taal(name)
    exp = EXPECTED[name]
    assert taal.name == name
    assert taal.matra_count == exp["matra_count"]
    assert taal.vibhag_lengths == exp["vibhag_lengths"]
    assert taal.matra_marks() == exp["marks"]
    assert taal.sam_is_khaali == exp["sam_is_khaali"]
    # Marks length always equals the matra count.
    assert len(taal.matra_marks()) == taal.matra_count


@pytest.mark.parametrize("name", sorted(EXPECTED))
def test_matra_zero_is_always_sam_origin(name):
    # Even Rupak (sam_is_khaali) keeps matra 0 as the 'sam' mark so the engine
    # treats it as the cycle origin; the khaali display is a separate flag.
    assert get_taal(name).matra_marks()[0] == "sam"


def test_unknown_taal_raises():
    with pytest.raises(ValueError, match="Unknown taal"):
        get_taal("nonexistent")
