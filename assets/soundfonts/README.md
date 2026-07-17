# Soundfonts

Drop the harmonium soundfont here as `harmonium.sf2` (or `.sf3`).

## Day-1 task (spec §6, Path 1)
Audition 3–5 free harmonium SF2/SFZ sets and pick the best:
- [Musical Artifacts](https://musical-artifacts.com/) — search "harmonium".
- [Polyphone soundfont library](https://www.polyphone-soundfonts.com/).
- Any free sampled-harmonium instrument that exports SF2.

**Before committing any file, record its license in `../LICENSES.md`.** Many are
CC / free-for-use; some are non-commercial (blocks a paid build — spec §9).

## Using it
```bash
export NAGMA_SOUNDFONT="$(pwd)/assets/soundfonts/harmonium.sf2"
nagma-render score.json -o loop.wav          # picks up NAGMA_SOUNDFONT
# or explicitly:
nagma-render score.json -o loop.wav --soundfont assets/soundfonts/harmonium.sf2
```

Large binaries are git-ignored by default (see repo `.gitignore`); decide per
project whether to commit the chosen soundfont or fetch it in CI/deploy.
