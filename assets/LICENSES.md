# Asset Licenses

Every binary asset shipped in the app (soundfonts, tanpura loops) **must** have
its license recorded here before it lands. This is a Day-1 risk-control item
(spec §9): a soundfont with a non-commercial license blocks eventual monetization.

| File | Type | Source | License | Commercial OK? | Notes |
|------|------|--------|---------|----------------|-------|
| `soundfonts/harmonium.sf2` | Soundfont | _TBD — audition Day 1_ | _TBD_ | _verify_ | Not yet added. See `soundfonts/README.md`. |
| `tanpura/*.wav` | Loop | _TBD_ | _TBD_ | _verify_ | Per-key loops or one pitch-shifted loop (open question §11.4). |
| `nagmas/bhairavi-teentaal.nagma` | Text | Original (this repo) | Repo license | Yes | Stock Bhairavi lehra. |

## Checklist before shipping a paid build
- [ ] Every soundfont license permits commercial use, OR swap to self-recorded
      samples (spec §6 Path 2).
- [ ] Tanpura loop license verified.
- [ ] No YouTube-sourced audio anywhere in the pipeline (spec §6 Path 3, dropped).
