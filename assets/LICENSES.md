# Asset Licenses

Every binary asset shipped in the app (soundfonts, tanpura loops) **must** have
its license recorded here before it lands. This is a Day-1 risk-control item
(spec §9): a soundfont with a non-commercial license blocks eventual monetization.

| File | Type | Source | License | Commercial OK? | Notes |
|------|------|--------|---------|----------------|-------|
| `soundfonts/harmonium.sf2` | Soundfont (built) | freesound #330410 | **CC0 / public domain** | ✅ yes, no strings | Built by `scripts/build_harmonium.py`. See below. |
| `soundfonts/sarangi.sf2` | Soundfont (built) | freesound #167023, #167088 | **CC0 / public domain** | ✅ yes, no strings | 39-zone bowed sarangi (C2–D5) from `scripts/build_sarangi.py`. Committed. See below. |
| `tanpura/harmonium_drone_*.wav` | Drone | freesound #330410 | **CC0 / public domain** | ✅ yes, no strings | The 3 drones from the same CC0 recording (not wired in yet). |
| `nagmas/*.nagma` | Text | Original (this repo) | Repo license | Yes | Stock/proposed lehras. |

## `soundfonts/harmonium.sf2` — source (CC0, no attribution required)

The harmonium is a **multisampled SF2 built in-repo** (one real sample per
semitone, C2–D5, with seamless crossfade loops) from a CC0 studio recording:

- **Source recording:** "Harmonium Samples – All Keys and Drones" by **Donya Quick**
- **URL:** https://freesound.org/people/donyaquick/sounds/330410/
- **License:** **Creative Commons 0 (CC0 1.0) — public domain.** Commercial use
  is allowed with **no attribution required and no restrictions.** (Credit is
  appreciated but not legally required.)
- **Build:** `./scripts/build_harmonium.py` fetches the CC0 HQ preview from the
  public freesound CDN, slices per-note samples, makes crossfade loops, and
  authors the SF2. For top quality, drop the lossless 96 kHz WAV (needs a free
  freesound login) into `assets/soundfonts/raw/` and rebuild.

> No in-app attribution screen is legally required (CC0). The previous CC-BY
> "Wetthasinghe" soundfont was replaced by this CC0 multisample.

## `soundfonts/sarangi.sf2` — source (CC0, no attribution required)

A **bowed-string sarangi**, authored in-repo as 39 looped zones (one per semitone,
C2–D5) from two CC0 single sustained sarangi notes:

- **Source recordings:** "Sarangi.wav" and "Sarangi -G3.wav" by a since-deleted
  freesound user (uploads survive on the public CDN under uploader id 1):
  - C4 (measured 262.5 Hz) — https://freesound.org/people/--DeletedUser--/sounds/167023/
  - G#4 (measured 412.2 Hz; the "G3" in the filename is mislabeled — the partials
    412/824/1236/1648 Hz fix the fundamental) — https://freesound.org/people/--DeletedUser--/sounds/167088/
- **License:** **Creative Commons 0 (CC0 1.0) — public domain.** Commercial use
  allowed with **no attribution required.** (Verified on each sound page.)
- **Nature of the sources:** each is a clean ~4.3s held tone — a real ~200ms
  attack plus a software-built steady sustain with filtered-noise string
  resonance (a hybrid design sample, CC0, not a pure field recording).
- **Build:** `./scripts/build_sarangi.py` fetches the CC0 HQ previews from the
  public freesound CDN, resamples the nearer source to each semitone (tune
  pre-compensated to exact 12-TET), and level-flattens a seamless crossfade
  sustain loop (samplemode=1, a bowed/singing envelope). Validated in fluidsynth
  (pitch exact ±8¢, loop seams click-free). See the script header for details.

> No in-app attribution screen is legally required (CC0). Timbre note: the sources
> are synthesized-hybrid and the low octaves are C4 shifted down up to two octaves,
> so the on-device "does it sing like a real sarangi" listen is still a TODO.

## Checklist before shipping a paid build
- [x] Soundfont license permits commercial use with no strings (CC0).
- [x] Sarangi license verified — both sarangi.sf2 sources are CC0.
- [ ] Tanpura loop license verified (drones above are CC0; final tanpura TBD).
- [ ] No YouTube-sourced audio anywhere in the pipeline (spec §6 Path 3, dropped).
- [ ] (Optional upgrade, spec §6 Path 2) self-record a harmonium for an even
      higher-quality, fully-owned library.
