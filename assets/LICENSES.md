# Asset Licenses

Every binary asset shipped in the app (soundfonts, tanpura loops) **must** have
its license recorded here before it lands. This is a Day-1 risk-control item
(spec §9): a soundfont with a non-commercial license blocks eventual monetization.

| File | Type | Source | License | Commercial OK? | Notes |
|------|------|--------|---------|----------------|-------|
| `soundfonts/harmonium.sf2` | Soundfont | Musical Artifacts #2127 | **CC-BY 4.0** | ✅ yes (with attribution) | See attribution below. |
| `tanpura/*.wav` | Loop | _TBD_ | _TBD_ | _verify_ | Per-key loops or one pitch-shifted loop (open question §11.4). |
| `nagmas/bhairavi-teentaal.nagma` | Text | Original (this repo) | Repo license | Yes | Stock Bhairavi lehra. |

## `soundfonts/harmonium.sf2` — attribution (CC-BY 4.0)

CC-BY requires we credit the author, name the work, link it, state the license,
and indicate any changes. All satisfied here:

- **Work:** "Wetthasinghe Harmonium General Midi Version"
- **Author:** W. D. Tharinda Perera (harmonium sampled by Duwindu Tharinda from
  his grandfather's "Sarapina" harmonium); General MIDI layout by *Mike77154*.
- **Source:** https://musical-artifacts.com/artifacts/2127
- **License:** Creative Commons Attribution 4.0 International (CC-BY 4.0) —
  https://creativecommons.org/licenses/by/4.0/
- **Changes made:** renamed the file to `harmonium.sf2`. The audio/soundfont
  data is unmodified. Single preset "Harmonium" at bank 0, program 20.
- **SHA-256:** `458d43f6e1ba670ad9b2995724c84343faf8565a9c82b16d82f3e6e97f9a53f8`

Reproduce the download (verifies the hash): `./scripts/fetch_soundfont.sh`.

> The in-app "Credits/Licenses" screen must surface this attribution before a
> public release (CC-BY obligation).

## Checklist before shipping a paid build
- [x] Soundfont license permits commercial use (CC-BY 4.0 — attribution required).
- [ ] CC-BY attribution shown in an in-app credits screen.
- [ ] Tanpura loop license verified.
- [ ] No YouTube-sourced audio anywhere in the pipeline (spec §6 Path 3, dropped).
- [ ] (Optional upgrade, spec §6 Path 2) swap to self-recorded harmonium samples
      for a fully-owned library.
