"""Dataclasses mirroring the JSON contracts in ../contracts.

These are the in-memory representations; `to_dict`/`from_dict` produce and
consume the exact JSON shapes the contracts define. Keep these in lockstep with
contracts/*.schema.json — that directory is the single source of truth.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

SCHEMA_VERSION = "1.0.0"


# ---------------------------------------------------------------------------
# NagmaDoc
# ---------------------------------------------------------------------------
@dataclass
class Note:
    kind: str                      # 'swar' | 'sustain'
    swar: str | None = None        # required when kind == 'swar'
    octave: str = "madhya"

    def to_dict(self) -> dict[str, Any]:
        if self.kind == "sustain":
            return {"kind": "sustain"}
        return {"kind": "swar", "swar": self.swar, "octave": self.octave}

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> "Note":
        return cls(kind=d["kind"], swar=d.get("swar"), octave=d.get("octave", "madhya"))


@dataclass
class Matra:
    index: int
    notes: list[Note]

    def to_dict(self) -> dict[str, Any]:
        return {"index": self.index, "notes": [n.to_dict() for n in self.notes]}

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> "Matra":
        return cls(index=d["index"], notes=[Note.from_dict(n) for n in d["notes"]])


@dataclass
class NagmaDoc:
    taal: str
    matras: list[Matra]
    raag: str = "bhairavi"
    name: str = ""
    source_text: str = ""
    schema_version: str = SCHEMA_VERSION

    def to_dict(self) -> dict[str, Any]:
        return {
            "schema_version": self.schema_version,
            "taal": self.taal,
            "raag": self.raag,
            "name": self.name,
            "source_text": self.source_text,
            "matras": [m.to_dict() for m in self.matras],
        }

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> "NagmaDoc":
        return cls(
            taal=d["taal"],
            matras=[Matra.from_dict(m) for m in d["matras"]],
            raag=d.get("raag", "bhairavi"),
            name=d.get("name", ""),
            source_text=d.get("source_text", ""),
            schema_version=d.get("schema_version", SCHEMA_VERSION),
        )


# ---------------------------------------------------------------------------
# ExpressiveScore
# ---------------------------------------------------------------------------
@dataclass
class Event:
    start_s: float
    dur_s: float
    midi: int
    velocity: int
    matra: int
    avartan: int
    structural: bool
    swell: float = 0.0  # intra-note bellows swell depth (0..1); see contract

    def to_dict(self) -> dict[str, Any]:
        return {
            "start_s": self.start_s,
            "dur_s": self.dur_s,
            "midi": self.midi,
            "velocity": self.velocity,
            "matra": self.matra,
            "avartan": self.avartan,
            "structural": self.structural,
            "swell": self.swell,
        }

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> "Event":
        return cls(
            start_s=d["start_s"], dur_s=d["dur_s"], midi=d["midi"],
            velocity=d["velocity"], matra=d["matra"], avartan=d["avartan"],
            structural=d["structural"], swell=d.get("swell", 0.0),
        )


@dataclass
class ExpressiveScore:
    sample_rate: int
    bpm: float
    sa_midi: int
    instrument: str
    avartans: int
    matra_count: int
    matra_dur_s: float
    avartan_dur_s: float
    loop_length_s: float
    loop_length_samples: int
    events: list[Event]
    seed: int = 0
    bellows: dict[str, float] = field(default_factory=lambda: {"rate_hz": 0.25, "depth": 0.09})
    schema_version: str = SCHEMA_VERSION

    def to_dict(self) -> dict[str, Any]:
        return {
            "schema_version": self.schema_version,
            "sample_rate": self.sample_rate,
            "bpm": self.bpm,
            "sa_midi": self.sa_midi,
            "instrument": self.instrument,
            "avartans": self.avartans,
            "matra_count": self.matra_count,
            "matra_dur_s": self.matra_dur_s,
            "avartan_dur_s": self.avartan_dur_s,
            "loop_length_s": self.loop_length_s,
            "loop_length_samples": self.loop_length_samples,
            "seed": self.seed,
            "bellows": self.bellows,
            "events": [e.to_dict() for e in self.events],
        }

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> "ExpressiveScore":
        return cls(
            sample_rate=d["sample_rate"], bpm=d["bpm"], sa_midi=d["sa_midi"],
            instrument=d["instrument"], avartans=d["avartans"],
            matra_count=d["matra_count"], matra_dur_s=d["matra_dur_s"],
            avartan_dur_s=d["avartan_dur_s"], loop_length_s=d["loop_length_s"],
            loop_length_samples=d["loop_length_samples"],
            events=[Event.from_dict(e) for e in d["events"]],
            seed=d.get("seed", 0),
            bellows=d.get("bellows", {"rate_hz": 0.25, "depth": 0.09}),
            schema_version=d.get("schema_version", SCHEMA_VERSION),
        )
