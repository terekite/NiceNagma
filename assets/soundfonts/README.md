# Soundfonts

## `harmonium.sf2` — built multisample (CC0) ✅
A **multisampled** harmonium: one real recorded sample per semitone (C2–D5) with
seamless crossfade loops in the steady sustain. Single preset at **bank 0,
program 0**. This is the core of the app's sound and replaces the earlier
single-stretched-sample soundfont.

Built by [`../../scripts/build_harmonium.py`](../../scripts/build_harmonium.py) from a
**CC0 / public-domain** recording ("Harmonium Samples – All Keys and Drones" by
Donya Quick, [freesound #330410](https://freesound.org/people/donyaquick/sounds/330410/)).
No attribution required — see [`../LICENSES.md`](../LICENSES.md).

### Rebuild / upgrade quality
```bash
# Fetches the CC0 HQ preview from the public freesound CDN and builds the SF2:
.venv/bin/python scripts/build_harmonium.py
```
For top quality, download the lossless **96 kHz WAV** from freesound (needs a free
login) into `assets/soundfonts/raw/` and rebuild — the build prefers an existing
`raw/donyaquick_harmonium.wav` over the mp3 preview.

Room presence is added separately by the render mastering stage (convolution
reverb in `render/src/nagma_render/master.py`), so the SF2 itself is dry.

## Adding a different soundfont (spec §6)
Auditioning better harmoniums — or self-recording (spec §6 Path 2) for a
fully-owned, velocity-layered library — remains a quality-upgrade path. Record
the license of anything new in `../LICENSES.md`. Large binaries are git-ignored
except the committed `harmonium.sf2`.
