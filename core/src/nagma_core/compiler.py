"""Compiler: NagmaDoc + (BPM, Sa) -> ExpressiveScore.

This is where the two non-negotiable invariants are enforced:

  1. Machine-perfect laya. matra_dur_s = 60/bpm exactly; every matra boundary
     and sam sits on an exact multiple of it. loop_length_samples is an exact
     integer so the on-device loop restarts with zero drift.
  2. Human timbre via pure code. The performance model perturbs only
     non-structural onsets and shapes dynamics/legato/per-avartan variation.

The compiler expands the one-avartan NagmaDoc into a super-loop of `avartans`
cycles, each with its own RNG seed.
"""

from __future__ import annotations

from .models import Event, ExpressiveScore, NagmaDoc
from . import performance as perf
from .reduce import laya_for_bpm, reduce_doc
from .sargam import note_to_midi, sa_to_midi
from .taal import get_taal

DEFAULT_SAMPLE_RATE = 44100
DEFAULT_AVARTANS = 4


def _one_avartan_events(
    doc: NagmaDoc, matra_dur_s: float, sa_midi: int, marks: list[str]
) -> list[dict]:
    """Build the base (jitter-free, base-velocity) events for a single cycle.

    Sustains fold into the preceding note's duration. Returns plain dicts with
    the fields the expansion pass needs.
    """
    events: list[dict] = []
    last: dict | None = None  # the most recent struck note, for sustain folding

    for matra in doc.matras:
        n = len(matra.notes)
        # Slot width: whole matra for a single note, half each for a pair.
        for slot, note in enumerate(matra.notes):
            slot_dur = matra_dur_s / n
            slot_start = matra.index * matra_dur_s + slot * slot_dur
            # The first slot of a matra lands on a matra boundary -> structural.
            structural = slot == 0

            if note.kind == "sustain":
                if last is not None:
                    last["dur_s"] += slot_dur
                # A sustain with no predecessor is silence (parser forbids it
                # at sam; mid-piece it just yields a rest).
                continue

            midi = note_to_midi(note.swar, note.octave, sa_midi)
            ev = {
                "start_s": slot_start,
                "dur_s": slot_dur,
                "midi": midi,
                "matra": matra.index,
                "structural": structural,
                "mark": marks[matra.index],
            }
            events.append(ev)
            last = ev

    return events


def compile_score(
    doc: NagmaDoc,
    *,
    bpm: float,
    sa: str | int,
    sample_rate: int = DEFAULT_SAMPLE_RATE,
    avartans: int = DEFAULT_AVARTANS,
    seed: int = 0,
    instrument: str = "harmonium",
    grace_density: float | None = None,
) -> ExpressiveScore:
    """Compile a NagmaDoc into an ExpressiveScore super-loop."""
    if grace_density is None:
        grace_density = perf.GRACE_DENSITY
    if bpm <= 0:
        raise ValueError("bpm must be positive")
    if avartans < 1:
        raise ValueError("avartans must be >= 1")

    taal_def = get_taal(doc.taal)
    marks = taal_def.matra_marks()
    matra_count = taal_def.matra_count
    if len(doc.matras) != matra_count:
        raise ValueError(
            f"NagmaDoc has {len(doc.matras)} matras but {taal_def.name} "
            f"requires {matra_count}."
        )

    sa_midi = sa if isinstance(sa, int) else sa_to_midi(sa)

    # --- exact timing (invariant #1) --------------------------------------
    matra_dur_s = 60.0 / bpm
    avartan_dur_s = matra_count * matra_dur_s
    loop_length_s = avartans * avartan_dur_s
    loop_length_samples = round(loop_length_s * sample_rate)

    base = _one_avartan_events(doc, matra_dur_s, sa_midi, marks)

    # Add legato overlap once on the base durations.
    for ev in base:
        ev["dur_s"] += perf.LEGATO_OVERLAP_S

    # --- expand across avartans with per-cycle variation (invariant #2) ---
    pitch_set = sorted({ev["midi"] for ev in base})

    events: list[Event] = []
    for a in range(avartans):
        rng = perf.avartan_rng(seed, a)
        grng = perf.grace_rng(seed, a)  # separate stream: graces don't perturb feel
        cycle_offset = a * avartan_dur_s
        for ev in base:
            jitter = perf.timing_jitter(rng, ev["structural"])
            start = cycle_offset + ev["start_s"] + jitter
            vel = perf.base_velocity(ev["matra"], ev["mark"], matra_count)
            vel = perf.apply_velocity_noise(rng, vel)
            swell = perf.swell_depth(rng, ev["dur_s"], ev["structural"])
            events.append(
                Event(
                    start_s=start,
                    dur_s=ev["dur_s"],
                    midi=ev["midi"],
                    velocity=vel,
                    matra=ev["matra"],
                    avartan=a,
                    structural=ev["structural"],
                    swell=swell,
                )
            )
            # Kan swar: sparingly flick a neighbour swar in just before this note.
            # It steals time from BEFORE the exact onset, so the grid is untouched.
            if ev["dur_s"] >= perf.GRACE_MIN_MAIN_S and grng.random() < grace_density:
                kan = perf.kan_pitch(ev["midi"], pitch_set)
                gstart = start - perf.GRACE_DUR_S
                if kan is not None and kan != ev["midi"] and gstart >= cycle_offset:
                    events.append(
                        Event(
                            start_s=gstart,
                            dur_s=perf.GRACE_DUR_S + perf.GRACE_LEGATO_S,
                            midi=kan,
                            velocity=max(1, int(vel * perf.GRACE_VEL_SCALE)),
                            matra=ev["matra"],
                            avartan=a,
                            structural=False,
                            swell=0.0,
                        )
                    )

    events.sort(key=lambda e: e.start_s)

    # Same-pitch re-articulation: legato must not sustain a note into the next
    # onset of the SAME pitch (that retriggers the sampler mid-note and the
    # repeat sounds cut off — e.g. "Sa Sa Sa" blurs into one). Clamp each note
    # to end a small gap before the next same-pitch onset. Different-pitch
    # overlap (the harmonium bleed) is left untouched.
    by_pitch: dict[int, list[Event]] = {}
    for e in events:
        by_pitch.setdefault(e.midi, []).append(e)
    for group in by_pitch.values():
        for a, b in zip(group, group[1:]):  # already start-sorted (events were)
            latest_end = b.start_s - perf.REARTICULATION_GAP_S
            if a.start_s + a.dur_s > latest_end:
                a.dur_s = max(perf.MIN_NOTE_S, latest_end - a.start_s)

    return ExpressiveScore(
        sample_rate=sample_rate,
        bpm=bpm,
        sa_midi=sa_midi,
        instrument=instrument,
        avartans=avartans,
        matra_count=matra_count,
        matra_dur_s=matra_dur_s,
        avartan_dur_s=avartan_dur_s,
        loop_length_s=loop_length_s,
        loop_length_samples=loop_length_samples,
        events=events,
        seed=seed,
        bellows=perf.bellows_params(),
    )


def realize(
    doc: NagmaDoc,
    *,
    bpm: float,
    sa: str | int,
    laya: str | None = None,
    sample_rate: int = DEFAULT_SAMPLE_RATE,
    avartans: int = DEFAULT_AVARTANS,
    seed: int = 0,
    instrument: str = "harmonium",
) -> ExpressiveScore:
    """Author-once entry point: pick a laya from `bpm`, REDUCE the authored
    (vilambit) doc to that laya, then compile — with ornament density scaled to
    the laya. Pass `laya` to override the automatic BPM->laya selection.
    """
    if laya is None:
        laya = laya_for_bpm(bpm)
    reduced = reduce_doc(doc, laya)
    return compile_score(
        reduced,
        bpm=bpm,
        sa=sa,
        sample_rate=sample_rate,
        avartans=avartans,
        seed=seed,
        instrument=instrument,
        # Plucked instruments (sitar) take no kan-swar graces.
        grace_density=0.0
        if perf.is_plucked(instrument)
        else perf.GRACE_DENSITY_BY_LAYA.get(laya, perf.GRACE_DENSITY),
    )
