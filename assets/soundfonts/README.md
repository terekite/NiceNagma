# Soundfonts

## Bundled: `harmonium.sf2` ✅
A CC-BY 4.0 harmonium is committed here — "Wetthasinghe Harmonium General Midi
Version" (Musical Artifacts #2127), single preset "Harmonium" at bank 0 /
program 20 (matches `render`'s MIDI output). Full attribution and SHA-256 are in
[`../LICENSES.md`](../LICENSES.md). Re-fetch/verify with `./scripts/fetch_soundfont.sh`.

This unblocks the full render pipeline today. Auditioning better harmoniums (and
eventually self-recording, spec §6 Path 2) remains a quality-upgrade task.

## Adding/replacing a soundfont (spec §6, Path 1)
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
