"""nagma_core — pure domain logic for the NiceNagma lehra/nagma app.

Zero I/O beyond an optional CLI (see cli.py). Imports nothing from render or app.
Public surface:

    parse_nagma(text, taal=...) -> NagmaDoc
    compile_score(doc, bpm=..., sa=...) -> ExpressiveScore
"""

from __future__ import annotations

from .compiler import compile_score
from .models import Event, ExpressiveScore, Matra, NagmaDoc, Note
from .parser import NagmaParseError, parse_nagma
from .taal import TEENTAAL, Taal, get_taal

__all__ = [
    "compile_score",
    "parse_nagma",
    "NagmaParseError",
    "NagmaDoc",
    "ExpressiveScore",
    "Event",
    "Matra",
    "Note",
    "Taal",
    "TEENTAAL",
    "get_taal",
]

__version__ = "0.1.0"
