"""Laya reduction: derive madhya/drut realizations from an authored vilambit doc.

A lehra is one tempo-independent melody realized at different densities. The user
authors the most-elaborated (vilambit) version; faster layas are DERIVED by
metric reduction — never elaboration (which would need raga-specific note
generation). Reduction only ever keeps authored notes or holds across dropped
ones, so it can never produce an unmusical/wrong pitch.

Pure NagmaDoc -> NagmaDoc and instrument-agnostic: the same skeleton logic will
serve sarangi/violin later; only the render layer is instrument-specific.

Rules (v1, automatic salience — no author tags):
  - vilambit : identity (as authored).
  - madhya   : each matra keeps its downbeat + midpoint slot ({0, n//2}); finer
               subdivisions become sustains. ~<=2 struck notes/matra (dugun).
  - drut     : keep the downbeat skeleton note of each matra (barabar), then thin
               'plain' matras that merely repeat the previous struck pitch into a
               held note (omit repetitions). sam / taali / khaali (vibhag-head)
               matras are always struck to protect the taal outline. Dropped
               matras become a whole-matra sustain — the line stays gapless.
"""

from __future__ import annotations

from copy import deepcopy

from .models import Matra, NagmaDoc, Note
from .taal import Taal, get_taal

# Laya bands by BPM. Soft, tala-dependent thresholds (user-specified); tweak here.
VILAMBIT_MAX_BPM = 85
MADHYA_MAX_BPM = 160
LAYAS = ("vilambit", "madhya", "drut")


def laya_for_bpm(bpm: float) -> str:
    if bpm <= VILAMBIT_MAX_BPM:
        return "vilambit"
    if bpm <= MADHYA_MAX_BPM:
        return "madhya"
    return "drut"


def _copy(note: Note) -> Note:
    return Note(kind=note.kind, swar=note.swar, octave=note.octave)


def _sustain() -> Note:
    return Note(kind="sustain")


def _pitch(note: Note):
    return (note.swar, note.octave) if note.kind == "swar" else None


def _reduce_madhya(doc: NagmaDoc) -> list[Matra]:
    out = []
    for m in doc.matras:
        n = len(m.notes)
        keep = {0, n // 2}  # downbeat + midpoint (caps struck slots at 2)
        notes = [_copy(m.notes[i]) if i in keep else _sustain() for i in range(n)]
        out.append(Matra(index=m.index, notes=notes))
    return out


def _reduce_drut(doc: NagmaDoc, taal: Taal) -> list[Matra]:
    marks = taal.matra_marks()
    out = []
    last_struck = None
    for m in doc.matras:
        slot0 = m.notes[0]
        mark = marks[m.index]
        pitch = _pitch(slot0)
        # Protect the taal outline; elsewhere omit a plain matra that just repeats.
        strike = slot0.kind == "swar" and not (
            mark == "plain" and pitch is not None and pitch == last_struck
        )
        if strike:
            out.append(Matra(index=m.index, notes=[_copy(slot0)]))  # whole-matra note
            last_struck = pitch
        else:
            out.append(Matra(index=m.index, notes=[_sustain()]))    # held through
    return out


def reduce_doc(doc: NagmaDoc, laya: str) -> NagmaDoc:
    """Return a NagmaDoc realized for `laya` ('vilambit'|'madhya'|'drut')."""
    if laya == "vilambit":
        return deepcopy(doc)
    taal = get_taal(doc.taal)
    if laya == "madhya":
        matras = _reduce_madhya(doc)
    elif laya == "drut":
        matras = _reduce_drut(doc, taal)
    else:
        raise ValueError(f"unknown laya {laya!r}; expected one of {LAYAS}")
    return NagmaDoc(
        taal=doc.taal,
        matras=matras,
        raag=doc.raag,
        name=doc.name,
        source_text=doc.source_text,
    )
