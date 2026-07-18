"""Sargam text-grammar parser: raw text -> validated NagmaDoc.

Grammar (v1)
------------
- Vibhags are separated by a newline OR a ``|``. Both work, so either
  "one line per vibhag" or a single ``S R G m | P - D P | ...`` line parses.
- Within a vibhag, matras are whitespace-separated.
- A matra holds 1 or 2 notes; two notes are separated by ``,`` and split the
  matra into equal halves (max 2 in v1).
- A note is a swar symbol optionally followed by an octave marker:
    ``'`` -> taar (upper),  ``.`` -> mandra (lower),  none -> madhya.
- ``-`` is a sustain: the previous note continues through this slot.
- Lines beginning with ``#`` are comments; blank lines are ignored.

Validation is strict but the error messages point at the offending token/vibhag
so the app can surface them inline.
"""

from __future__ import annotations

from .models import Matra, NagmaDoc, Note
from .sargam import OCTAVE_MARKERS, VALID_SWARS
from .taal import get_taal


class NagmaParseError(ValueError):
    """Raised on any grammar or structural validation failure.

    The message is user-facing and should read cleanly in the app's inline
    validation UI.
    """


def _parse_note(token: str, *, vibhag_no: int, matra_no: int) -> Note:
    tok = token.strip()
    if not tok:
        raise NagmaParseError(
            f"Empty note in vibhag {vibhag_no}, matra {matra_no}."
        )
    if tok == "-":
        return Note(kind="sustain")

    octave = "madhya"
    core = tok
    marker = tok[-1]
    if marker in OCTAVE_MARKERS:
        octave = OCTAVE_MARKERS[marker]
        core = tok[:-1]

    if core not in VALID_SWARS:
        raise NagmaParseError(
            f"Unknown swar {tok!r} in vibhag {vibhag_no}, matra {matra_no}. "
            f"Valid swars: S r R g G m M P d D n N "
            f"(add ' for taar / . for mandra)."
        )
    return Note(kind="swar", swar=core, octave=octave)


def _parse_matra(cell: str, *, vibhag_no: int, matra_no: int) -> list[Note]:
    # A matra may be subdivided into up to 4 equal slots (chaugun) via ',' — this
    # is the density a slow (vilambit) lehra needs. '-' sustains a slot, which
    # covers uneven rhythms (e.g. 'S,-,g,m'). Faster layas are derived by reducing
    # this authored density (see reduce.py), so authoring is done at max density.
    parts = [p for p in cell.split(",")]
    if len(parts) > 4:
        raise NagmaParseError(
            f"Matra {matra_no} in vibhag {vibhag_no} has {len(parts)} notes; "
            f"a matra allows at most 4 subdivisions (split with ',')."
        )
    return [
        _parse_note(p, vibhag_no=vibhag_no, matra_no=matra_no) for p in parts
    ]


def parse_nagma(
    text: str,
    *,
    taal: str = "teentaal",
    raag: str = "bhairavi",
    name: str = "",
) -> NagmaDoc:
    """Parse text-grammar into a validated NagmaDoc for the given taal."""
    taal_def = get_taal(taal)

    # Strip comments/blank lines, then split into vibhags on newlines AND '|'.
    cleaned_lines = [
        ln for ln in text.splitlines()
        if ln.strip() and not ln.lstrip().startswith("#")
    ]
    joined = "\n".join(cleaned_lines)
    vibhag_strs = [
        seg.strip()
        for seg in joined.replace("\n", "|").split("|")
        if seg.strip()
    ]

    expected_vibhags = len(taal_def.vibhags)
    if len(vibhag_strs) != expected_vibhags:
        raise NagmaParseError(
            f"{taal_def.name} has {expected_vibhags} vibhags but got "
            f"{len(vibhag_strs)}. Separate vibhags with a newline or '|'."
        )

    matras: list[Matra] = []
    matra_index = 0
    for vi, (vstr, vib) in enumerate(zip(vibhag_strs, taal_def.vibhags), start=1):
        cells = vstr.split()
        if len(cells) != vib.length:
            raise NagmaParseError(
                f"Vibhag {vi} should have {vib.length} matras but got "
                f"{len(cells)}: {vstr!r}."
            )
        for mi, cell in enumerate(cells, start=1):
            notes = _parse_matra(cell, vibhag_no=vi, matra_no=mi)
            matras.append(Matra(index=matra_index, notes=notes))
            matra_index += 1

    # A leading sustain has nothing to hold, which is almost always a typo.
    first = matras[0].notes[0]
    if first.kind == "sustain":
        raise NagmaParseError(
            "The nagma cannot begin with a sustain '-' (nothing to hold at sam)."
        )

    return NagmaDoc(
        taal=taal_def.name,
        matras=matras,
        raag=raag,
        name=name,
        source_text=text.strip(),
    )
