#!/usr/bin/env python3
"""Build a multisampled harmonium SF2 from the CC0 donyaquick recording.

Source: freesound.org #330410 "Harmonium Samples - All Keys and Drones",
Donya Quick, CC0 / public domain (commercial use OK, no attribution required).
The recording is a chromatic run C2..D5 (39 notes held ~8-11s each) followed by
3 long drones. We slice one sample per semitone, make a seamless crossfade loop
in the steady sustain, and author a valid SF2 (one preset, one instrument, one
zone per note) that fluidsynth plays directly. This replaces the previous
single-sample phone SF2 - the core cause of the "cheap / not a real player" tone.

Usage:  .venv/bin/python scripts/build_harmonium.py
"""

from __future__ import annotations

import os
import struct
import sys

import numpy as np
import soundfile as sf

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW_DIR = os.path.join(ROOT, "assets", "soundfonts", "raw")
RAW_MP3 = os.path.join(RAW_DIR, "donyaquick_harmonium_330410.mp3")
RAW = os.path.join(RAW_DIR, "donyaquick_harmonium.wav")
OUT_SF2 = os.path.join(ROOT, "assets", "soundfonts", "harmonium.sf2")
DRONE_DIR = os.path.join(ROOT, "assets", "tanpura")

# CC0 source (public domain): freesound.org/people/donyaquick/sounds/330410/.
# The full-quality WAV needs a freesound login, but the HQ mp3 preview is on the
# public CDN and is plenty for a multisample. Drop the 96 kHz WAV into RAW_DIR
# and rebuild for top quality.
SOURCE_CDN = "https://cdn.freesound.org/previews/330/330410_1089898-hq.mp3"

BASE_MIDI = 36          # segment 0 == C2
N_NOTES = 39            # C2..D5
GLOBAL_TUNE_CENTS = -7  # recording sits ~+7c sharp; pull back to concert pitch
TARGET_RMS = 0.16       # per-note loudness normalization (even across keyboard)
XFADE = 2048            # crossfade-loop length (~46ms @44.1k)


# --------------------------------------------------------------------------- #
# audio slicing + seamless looping
# --------------------------------------------------------------------------- #
def detect_segments(mono: np.ndarray, sr: int) -> list[tuple[float, float]]:
    hop = int(0.02 * sr); win = int(0.04 * sr)
    env = np.array([np.sqrt(np.mean(mono[i:i + win] ** 2))
                    for i in range(0, len(mono) - win, hop)])
    thr = env.max() * 0.06
    active = env > thr
    segs = []; i = 0
    while i < len(active):
        if active[i]:
            j = i
            while j < len(active) and active[j]:
                j += 1
            t0, t1 = i * hop / sr, j * hop / sr
            if t1 - t0 > 0.25:
                segs.append((t0, t1))
            i = j
        else:
            i += 1
    return segs


def make_looped_sample(mono, sr, t0, t1, midi):
    """Return (int16 pcm, loop_start, loop_end) with a seamless crossfade loop."""
    onset = int(t0 * sr)
    end = int(t1 * sr)
    # skip the very first few ms (breath/mechanical) and fade in gently
    seg = mono[onset:end].astype(np.float64)
    fade_in = int(0.006 * sr)
    seg[:fade_in] *= np.linspace(0, 1, fade_in)

    # loop inside the steady sustain, away from attack and any tail decay
    s = int(1.2 * sr)                      # loop start ~1.2s in
    period = sr / (440.0 * 2 ** ((midi - 69) / 12.0))
    loop_len = int(round(0.5 * sr / period) * period)  # ~0.5s, whole periods
    e = s + loop_len
    if e + XFADE >= len(seg):              # short sample -> shrink the loop
        e = len(seg) - XFADE - 1
        s = max(int(0.6 * sr), e - loop_len)
    # crossfade the XFADE samples ending at e into those ending at s, so the
    # e -> s wrap is inaudible (equal-power).
    fi = np.sqrt(np.linspace(0, 1, XFADE))
    fo = np.sqrt(np.linspace(1, 0, XFADE))
    seg[e - XFADE:e] = seg[e - XFADE:e] * fo + seg[s - XFADE:s] * fi

    seg = seg[:e + 1]                      # keep attack..loop end
    # normalize to even loudness, then guard against clipping
    rms = np.sqrt(np.mean(seg ** 2)) or 1.0
    seg *= TARGET_RMS / rms
    peak = np.max(np.abs(seg))
    if peak > 0.98:
        seg *= 0.98 / peak

    pcm = np.clip(seg * 32767.0, -32768, 32767).astype("<i2")
    return pcm, s, e


# --------------------------------------------------------------------------- #
# minimal SF2 writer  (RIFF sfbk: INFO / sdta / pdta)
# --------------------------------------------------------------------------- #
def _chunk(tag: bytes, data: bytes) -> bytes:
    out = tag + struct.pack("<I", len(data)) + data
    if len(data) & 1:
        out += b"\x00"
    return out


def _list(tag: bytes, body: bytes) -> bytes:
    return _chunk(b"LIST", tag + body)


def _name(s: str, n: int = 20) -> bytes:
    b = s.encode("ascii", "ignore")[: n - 1]
    return b + b"\x00" * (n - len(b))


def build_sf2(samples, sr, path, inst_name="Harmonium", preset=0, bank=0,
              samplemode=1, release_s=0.35, sustain_full=False):
    """Author a minimal SF2 (one preset -> one instrument -> one zone per sample).

    samples: list of dict(pcm, root, loop_start, loop_end, name[, lo, hi]).
      pcm         int16 mono samples for this zone.
      root        MIDI key the sample plays at native rate.
      loop_start/loop_end  loop points in frames (used only when samplemode==1).
      lo/hi       optional inclusive MIDI key-range for the zone. When absent the
                  zones tile contiguously by root (harmonium's one-per-semitone
                  layout: first sample -> lo=0, last -> hi=127, else lo=hi=root).
                  Pass explicit lo/hi for a sparse multisample (nearest-sample
                  playback, e.g. plucked instruments spread across the keyboard).

    Additive, backward-compatible knobs (defaults reproduce the harmonium):
      samplemode    SF2 GEN_SAMPLEMODES: 1 = loop continuously (sustained reed),
                    0 = play once then stop (plucked one-shot, natural decay).
      release_s     volume-envelope release in seconds.
      sustain_full  when True, hold the note at full level (GEN_HOLDVOLENV) with
                    no envelope decay (GEN_SUSTAINVOLENV=0) so a sampler that
                    honours the volume envelope won't fade a long-held note.
    """
    # ---- sdta / smpl : concatenate int16, 46 zero guard samples between ----
    guard = np.zeros(46, dtype="<i2")
    smpl = bytearray()
    meta = []  # (start, end, loopstart, loopend) in sample frames
    for s in samples:
        start = len(smpl) // 2
        smpl += s["pcm"].tobytes()
        end = len(smpl) // 2
        smpl += guard.tobytes()
        meta.append((start, end, start + s["loop_start"], start + s["loop_end"]))

    # ---- pdta : shdr ----
    shdr = bytearray()
    for s, (start, end, ls, le) in zip(samples, meta):
        shdr += _name(s["name"])
        shdr += struct.pack("<IIII", start, end, ls, le)
        shdr += struct.pack("<I", sr)
        shdr += struct.pack("<BbHH", s["root"], GLOBAL_TUNE_CENTS, 0, 1)  # pitch, corr, link, type=mono
    shdr += _name("EOS") + struct.pack("<IIIIIBbHH", 0, 0, 0, 0, 0, 0, 0, 0, 0)

    # ---- igen : one zone per sample ----
    GEN_KEYRANGE, GEN_RELEASE, GEN_FINETUNE = 43, 38, 52
    GEN_SAMPLEMODES, GEN_ROOTKEY, GEN_SAMPLEID = 54, 58, 53
    GEN_HOLDVOLENV, GEN_SUSTAINVOLENV = 35, 37
    release_tc = int(round(1200 * np.log2(max(release_s, 1e-3))))  # release, timecents
    hold_tc = 4300  # ~12s full-level hold before any decay (sustain_full)

    def gen(op, amount_bytes):
        return struct.pack("<H", op) + amount_bytes

    igen = bytearray()
    ibag = bytearray()
    gen_ndx = 0
    n_gens = 6 if sustain_full else 4
    for i, s in enumerate(samples):
        ibag += struct.pack("<HH", gen_ndx, 0)
        lo = s.get("lo", 0 if i == 0 else s["root"])
        hi = s.get("hi", 127 if i == len(samples) - 1 else s["root"])
        igen += gen(GEN_KEYRANGE, struct.pack("<BB", lo, hi))    # MUST be first
        if sustain_full:
            igen += gen(GEN_HOLDVOLENV, struct.pack("<h", hold_tc))
            igen += gen(GEN_SUSTAINVOLENV, struct.pack("<h", 0))  # 0 cB attenuation
        igen += gen(GEN_RELEASE, struct.pack("<h", release_tc))
        igen += gen(GEN_SAMPLEMODES, struct.pack("<H", samplemode))
        igen += gen(GEN_SAMPLEID, struct.pack("<H", i))          # MUST be last
        gen_ndx += n_gens
    ibag += struct.pack("<HH", gen_ndx, 0)                       # terminal bag
    igen += gen(0, struct.pack("<H", 0))                         # terminal gen
    imod = struct.pack("<HHhHH", 0, 0, 0, 0, 0)                  # terminal mod

    # ---- inst ----
    inst = _name(inst_name) + struct.pack("<H", 0)
    inst += _name("EOI") + struct.pack("<H", len(samples))      # terminal -> ibag count

    # ---- preset layer : phdr/pbag/pmod/pgen ----
    GEN_INSTRUMENT = 41
    pgen = gen(GEN_INSTRUMENT, struct.pack("<H", 0)) + gen(0, struct.pack("<H", 0))
    pmod = struct.pack("<HHhHH", 0, 0, 0, 0, 0)
    pbag = struct.pack("<HH", 0, 0) + struct.pack("<HH", 1, 0)  # 1 real + terminal
    phdr = _name(inst_name) + struct.pack("<HHHIII", preset, bank, 0, 0, 0, 0)
    phdr += _name("EOP") + struct.pack("<HHHIII", 0, 0, 1, 0, 0, 0)

    pdta = _list(b"pdta",
                 _chunk(b"phdr", phdr) + _chunk(b"pbag", pbag) +
                 _chunk(b"pmod", pmod) + _chunk(b"pgen", pgen) +
                 _chunk(b"inst", inst) + _chunk(b"ibag", bytes(ibag)) +
                 _chunk(b"imod", imod) + _chunk(b"igen", bytes(igen)) +
                 _chunk(b"shdr", bytes(shdr)))

    info = _list(b"INFO",
                 _chunk(b"ifil", struct.pack("<HH", 2, 1)) +
                 _chunk(b"isng", _name("EMU8000", 8)) +
                 _chunk(b"INAM", _name(f"NiceNagma {inst_name} (CC0)", 32)))
    sdta = _list(b"sdta", _chunk(b"smpl", bytes(smpl)))

    riff = _chunk(b"RIFF", b"sfbk" + info + sdta + pdta)
    with open(path, "wb") as f:
        f.write(riff)


# --------------------------------------------------------------------------- #
def ensure_source() -> None:
    """Fetch + decode the CC0 source if the WAV isn't present (reproducible build)."""
    if os.path.exists(RAW):
        return
    os.makedirs(RAW_DIR, exist_ok=True)
    if not os.path.exists(RAW_MP3):
        import urllib.request
        print(f"fetching CC0 source: {SOURCE_CDN}")
        urllib.request.urlretrieve(SOURCE_CDN, RAW_MP3)
    import subprocess
    print("decoding to 44.1k wav (ffmpeg)")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", RAW_MP3,
                    "-ar", "44100", "-ac", "2", RAW], check=True)


def main() -> int:
    ensure_source()
    if not os.path.exists(RAW):
        print(f"missing raw source: {RAW}", file=sys.stderr)
        return 2
    a, sr = sf.read(RAW, always_2d=True)
    mono = a.mean(axis=1)
    segs = detect_segments(mono, sr)
    notes = segs[:N_NOTES]
    drones = segs[N_NOTES:]
    print(f"source: {len(segs)} segments -> {len(notes)} notes + {len(drones)} drones @ {sr}Hz")

    samples = []
    for i, (t0, t1) in enumerate(notes):
        midi = BASE_MIDI + i
        pcm, ls, le = make_looped_sample(mono, sr, t0, t1, midi)
        names = ['C','C#','D','D#','E','F','F#','G','G#','A','A#','B']
        samples.append({"pcm": pcm, "root": midi, "loop_start": ls,
                        "loop_end": le, "name": f"Harm_{names[midi%12]}{midi//12-1}"})

    build_sf2(samples, sr, OUT_SF2)
    sz = os.path.getsize(OUT_SF2)
    print(f"wrote {OUT_SF2}  ({sz//1024} KB, {len(samples)} note zones, "
          f"C2..D5, tune {GLOBAL_TUNE_CENTS}c)")

    # stash the 3 drones as CC0 tanpura/drone material for later (not wired in)
    os.makedirs(DRONE_DIR, exist_ok=True)
    for k, (t0, t1) in enumerate(drones):
        seg = a[int(t0 * sr):int(t1 * sr)]
        sf.write(os.path.join(DRONE_DIR, f"harmonium_drone_{k}.wav"), seg, sr)
    if drones:
        print(f"saved {len(drones)} CC0 drones -> assets/tanpura/")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
