# Asset Licenses

Every binary asset shipped in the app (soundfonts, tanpura loops) **must** have
its license recorded here before it lands. This is a Day-1 risk-control item
(spec §9): a soundfont with a non-commercial license blocks eventual monetization.

| File | Type | Source | License | Commercial OK? | Notes |
|------|------|--------|---------|----------------|-------|
| `soundfonts/harmonium.sf2` | Soundfont (built) | freesound #330410 | **CC0 / public domain** | ✅ yes, no strings | Built by `scripts/build_harmonium.py`. See below. |
| `soundfonts/sitar.sf2` | Soundfont (built) | freesound #42192 | **CC0 / public domain** | ✅ yes, no strings | Built by `scripts/build_sitar.py`. See below. |
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

## `soundfonts/sitar.sf2` — source (CC0, no attribution required)

The sitar is a **plucked one-shot SF2 built in-repo** (`scripts/build_sitar.py`)
from a single CC0 sitar recording:

- **Source recording:** "sitar01.flac" — a clean single plucked note on the main
  (baaj) string, jawari buzz + sympathetic (tarab) strings ringing.
- **URL:** https://freesound.org/s/42192/ (uploader account since deleted)
- **License:** **Creative Commons 0 (CC0 1.0) — public domain.** Commercial use
  allowed with **no attribution required and no restrictions.**
- **Build:** `scripts/build_sitar.py` fetches the CC0 HQ preview from the public
  freesound CDN, detects the source pitch by **Harmonic Product Spectrum** (robust
  to the jawari overtones that fool autocorrelation), slices the pluck (attack +
  natural decay), applies a **warmth EQ** (see below), then **resamples that one
  note to a spread of anchor pitches** (every 2 semitones, ~1 octave either side of
  the source) tiled by nearest-sample key ranges. `samplemode=0` (plucked one-shot,
  no loop) so the real attack+decay rings out — like the tanpura, not the
  looped-sustain harmonium.
- **Warmth / de-twang (why it's not just the raw sitar):** the goal tone is warm
  and round, "closer to a sarod," not the bright mandolin-ish jawari twang. A
  zero-phase FFT EQ cuts the 2.5–4 kHz jawari twang formant, rolls off the fizzy
  top, and adds low-mid body, pulling the render spectral centroid from ~2600 Hz
  (raw) down to ~1950 Hz (about the harmonium's warmth) while keeping tuning exact.
- **Why not an actual sarod:** real CC0 *isolated* sarod notes don't exist, and
  the one CC0 sarod recording (freesound #9610, bluedotproductions, CC0) is a riff
  whose drone/sympathetic strings ring *under* the melody note (two pitches a
  whole-tone apart), so resampling it across the keyboard mistunes every key. A
  true sarod voice would need a **licensed clean sarod multisample** (a paid
  library or a self-recorded set) — same build/seam.
- **Known limitation / upgrade path:** one note resampled across the keyboard, so
  formants stretch with pitch; a real per-semitone plucked multisample would
  improve the extremes.

> **On-device verification:** fluidsynth CLI — tuning within ±3c across the anchor
> range (E2–F#4, HPS-measured), clean plucked decay (−23 dB attack→1.5s), no seam
> clicks. **AVAudioUnitSampler ignores SF2 loop points and imposes its own
> envelope decay**, so the on-device timbre is not identical; listened-to on the
> simulator. Ornaments: plucked instruments render with **no kan-swar grace
> notes** (see `performance.is_plucked`). Still open: a plucked-instrument
> `OfflineRenderer` mastering preset (the bellows LFO is a reed gesture), and
> optional **meend** (pitch-glide between notes) for less-robotic phrasing — both
> deferred.

## Checklist before shipping a paid build
- [x] Soundfont license permits commercial use with no strings (CC0 — harmonium + sitar).
- [ ] Tanpura loop license verified (drones above are CC0; final tanpura TBD).
- [ ] No YouTube-sourced audio anywhere in the pipeline (spec §6 Path 3, dropped).
- [ ] (Optional upgrade, spec §6 Path 2) self-record a harmonium for an even
      higher-quality, fully-owned library.
