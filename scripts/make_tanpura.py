#!/usr/bin/env python3
"""Generate a looping tanpura drone MIDI for the demo soundtrack.

Classic four-string cycle Pa - Sa - Sa - low Sa, each string plucked in turn and
ringing well past the next pluck so they overlap into a steady drone. Rendered to
WAV through assets/soundfonts/tanpura.sf2 by scripts/make_demo.sh.

Usage: make_tanpura.py <out.mid> [sa_midi]   (sa_midi default 50 = D3)
"""
import sys
import mido

sa = int(sys.argv[2]) if len(sys.argv) > 2 else 50  # default D3
notes = [sa - 5, sa, sa, sa - 12]  # Pa(A2), Sa, Sa, low Sa(D2)
tpb = 480
mid = mido.MidiFile(ticks_per_beat=tpb)
tr = mido.MidiTrack()
mid.tracks.append(tr)
tr.append(mido.Message("program_change", program=0, time=0))

pluck = int(tpb * 1.15)   # spacing between plucks
ring = int(tpb * 4.2)     # each string rings past the next pluck

events = []
t = 0
for _ in range(14):       # exceeds the film length; make_demo.sh loops/trims
    for n in notes:
        events.append((t, mido.Message("note_on", note=n, velocity=64)))
        events.append((t + ring, mido.Message("note_off", note=n, velocity=0)))
        t += pluck

events.sort(key=lambda e: e[0])
last = 0
for tick, msg in events:
    msg.time = tick - last
    last = tick
    tr.append(msg)

mid.save(sys.argv[1])
print(f"wrote {sys.argv[1]}")
