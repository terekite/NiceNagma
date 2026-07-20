"""Taal definitions.

MVP ships Teentaal only, but the structure is taal-agnostic so adding Jhaptaal,
Ektaal, etc. later is pure data. A taal is a sequence of vibhags (measures);
each vibhag has a matra count and a clap type (taali/khaali). Sam is matra 0.
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class Vibhag:
    """One section of a taal cycle."""
    length: int          # number of matras in this vibhag
    clap: str            # 'taali', 'khaali', or 'sam' (sam is the first taali)


@dataclass(frozen=True)
class Taal:
    name: str
    vibhags: tuple[Vibhag, ...]
    # Rupak's cycle starts ON a khaali: matra 0 is the origin (sam) for timing,
    # velocity swell, and the wheel's sweep, but it is *displayed* as an open
    # (khaali) beat. The engine still treats matra 0 as 'sam'; only the UI reads
    # this flag to render the sam dot as an open/khaali dot.
    sam_is_khaali: bool = False

    @property
    def matra_count(self) -> int:
        return sum(v.length for v in self.vibhags)

    @property
    def vibhag_lengths(self) -> tuple[int, ...]:
        return tuple(v.length for v in self.vibhags)

    def matra_marks(self) -> list[str]:
        """Per-matra structural label: 'sam' | 'taali' | 'khaali' | 'plain'.

        The first matra of each vibhag carries its clap; the rest are 'plain'.
        Matra 0 is always 'sam'.
        """
        marks: list[str] = []
        for v in self.vibhags:
            marks.append(v.clap)
            marks.extend("plain" for _ in range(v.length - 1))
        return marks


# Teentaal: 16 matras, 4 vibhags of 4. Taali on 1/5/13, khaali on 9
# (0-based: sam=0, taali=4, khaali=8, taali=12).
TEENTAAL = Taal(
    name="teentaal",
    vibhags=(
        Vibhag(length=4, clap="sam"),
        Vibhag(length=4, clap="taali"),
        Vibhag(length=4, clap="khaali"),
        Vibhag(length=4, clap="taali"),
    ),
)

# --- Additional taals (all standard thekas; 0-based marks noted per taal) -----

# Dadra: 6 matras, 3+3. Taali on 1, khaali on 4 (0-based: sam=0, khaali=3).
DADRA = Taal(
    name="dadra",
    vibhags=(
        Vibhag(length=3, clap="sam"),
        Vibhag(length=3, clap="khaali"),
    ),
)

# Rupak: 7 matras, 3+2+2. The sam is a KHAALI (open) — matra 1 is both the
# cycle origin and an open beat; taali on 4 and 6. (0-based: sam/khaali=0,
# taali=3, taali=5.) sam_is_khaali drives only the wheel's display.
RUPAK = Taal(
    name="rupak",
    vibhags=(
        Vibhag(length=3, clap="sam"),
        Vibhag(length=2, clap="taali"),
        Vibhag(length=2, clap="taali"),
    ),
    sam_is_khaali=True,
)

# Jhaptaal: 10 matras, 2+3+2+3. Taali on 1/3, khaali on 6, taali on 8
# (0-based: sam=0, taali=2, khaali=5, taali=7).
JHAPTAAL = Taal(
    name="jhaptaal",
    vibhags=(
        Vibhag(length=2, clap="sam"),
        Vibhag(length=3, clap="taali"),
        Vibhag(length=2, clap="khaali"),
        Vibhag(length=3, clap="taali"),
    ),
)

# Ektaal: 12 matras, 6 vibhags of 2. Taali on 1/5/9/11, khaali on 3/7
# (0-based: sam=0, khaali=2, taali=4, khaali=6, taali=8, taali=10).
EKTAAL = Taal(
    name="ektaal",
    vibhags=(
        Vibhag(length=2, clap="sam"),
        Vibhag(length=2, clap="khaali"),
        Vibhag(length=2, clap="taali"),
        Vibhag(length=2, clap="khaali"),
        Vibhag(length=2, clap="taali"),
        Vibhag(length=2, clap="taali"),
    ),
)

# Dhamar: 14 matras, 5+2+3+4. Taali on 1/6, khaali on 8, taali on 11
# (0-based: sam=0, taali=5, khaali=7, taali=10).
DHAMAR = Taal(
    name="dhamar",
    vibhags=(
        Vibhag(length=5, clap="sam"),
        Vibhag(length=2, clap="taali"),
        Vibhag(length=3, clap="khaali"),
        Vibhag(length=4, clap="taali"),
    ),
)

# Pancham Sawari: 15 matras, 3+4+4+4. Taali on 1/4/12, khaali on 8
# (0-based: sam=0, taali=3, khaali=7, taali=11).
PANCHAM_SAWARI = Taal(
    name="pancham_sawari",
    vibhags=(
        Vibhag(length=3, clap="sam"),
        Vibhag(length=4, clap="taali"),
        Vibhag(length=4, clap="khaali"),
        Vibhag(length=4, clap="taali"),
    ),
)

TAALS: dict[str, Taal] = {
    t.name: t
    for t in (
        TEENTAAL,
        DADRA,
        RUPAK,
        JHAPTAAL,
        EKTAAL,
        DHAMAR,
        PANCHAM_SAWARI,
    )
}


def get_taal(name: str) -> Taal:
    try:
        return TAALS[name]
    except KeyError:
        raise ValueError(
            f"Unknown taal {name!r}. Available: {', '.join(sorted(TAALS))}"
        ) from None
