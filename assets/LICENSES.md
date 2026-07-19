# Asset Licenses

Every binary asset shipped in the app (soundfonts, tanpura loops) **must** have
its license recorded here before it lands. This is a Day-1 risk-control item
(spec §9): a soundfont with a non-commercial license blocks eventual monetization.

| File | Type | Source | License | Commercial OK? | Notes |
|------|------|--------|---------|----------------|-------|
| `soundfonts/harmonium.sf2` | Soundfont (built) | freesound #330410 | **CC0 / public domain** | ✅ yes, no strings | Built by `scripts/build_harmonium.py`. See below. |
| `soundfonts/tanpura.sf2` | Soundfont (built) | freesound #416597, #416598, #416605 | **CC0 / public domain** | ✅ yes, no strings | 3-zone plucked tanpura (kharaj C#2 / Pa G#2 / Sa C#3) from `scripts/build_tanpura.py`. Committed. See below. |
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

## `soundfonts/tanpura.sf2` — source (CC0, no attribution required)

A **3-zone plucked-string tanpura** built in-repo from three CC0 single-note
tanpura plucks (one real acoustic pluck per string, with the full jawari bloom):

- **Source recordings:** "Tanpura note Low C sharp / G sharp / C sharp" by
  **luckylittleraven**, pack "Tanpura C Sharp" (#23512):
  - kharaj C#2 — https://freesound.org/people/luckylittleraven/sounds/416597/
  - Pa G#2 — https://freesound.org/people/luckylittleraven/sounds/416598/
  - mid Sa C#3 — https://freesound.org/people/luckylittleraven/sounds/416605/
- **License:** **Creative Commons 0 (CC0 1.0) — public domain.** Commercial use
  allowed with **no attribution required.** (Credit appreciated, not required.)
- **Build:** `./scripts/build_tanpura.py` fetches the CC0 HQ previews from the
  public freesound CDN, slices each to a clean one-shot (full natural decay, no
  loop), loudness-matches them, and authors a non-looping SF2 partitioned by
  pitch. The app's Dart sequencer plays the Pa-Sa-Sa-kharaj cycle through it.

## Checklist before shipping a paid build
- [x] Soundfont license permits commercial use with no strings (CC0).
- [x] Tanpura license verified — plucked tanpura.sf2 sources are all CC0.
- [ ] No YouTube-sourced audio anywhere in the pipeline (spec §6 Path 3, dropped).
- [ ] (Optional upgrade, spec §6 Path 2) self-record a harmonium for an even
      higher-quality, fully-owned library.
