# Status — 2026-11-16

**Native menus/stage-one milestone: unfinished.** Current playable behavior runs
the original game under a clearly identified MAME reference. No native gameplay,
enemy AI, collision, menu state machine or audio engine is claimed complete.

## Verified resource recovery

| Measure | Result |
| --- | ---: |
| Supplied ROM members verified | 4 / 4 |
| Directory-listed bitmap sheets decoded | 1,201 / 1,201 |
| Raw / compressed sheets | 929 / 272 |
| Decoded bitmap payload bytes | 157,441,492 |
| Unique bitmap payloads | 1,201 |
| Sheets matched exactly to original VRAM | 569 |
| Observed draw rectangles exported | 3,965 |
| Screenshot / framebuffer comparisons | 21, all exact |
| Verified animation sequences | 0 |
| Native decoder streams checked against original SH-3 | 273, all exact |
| Decoder output bytes compared | 38,602,880 |

See [coverage](evidence/catalog-coverage.json),
[drawing observations](evidence/graphics-observations.json),
[catalog validation](evidence/catalog-validation.json),
[native decoder results](evidence/native-decoder.json), and
[original-instruction results](evidence/original-decoder.json).

The 3,965 regions are distinct resource rectangles, not a unique-art or animation
count. Some are glyphs, background tiles, partial UI pieces or partial sprites.
Draws from dynamic/cross-page VRAM sources are retained as unmapped counts.

## Reference playthroughs

The input replays select Original mode and exercise all four choices. They use
normal input ports, ordinary deaths, bomb presses, inserted credits and paid
continues. No invulnerability, altered life bank, stage skip or other RAM cheat
is applied. MAME's existing CV1000 driver remains responsible for emulation.

| Route | Menu/shot evidence | Stage-one progression evidence |
| --- | --- | --- |
| Reco / Normal | `reco-normal`, frames 3000–3400 | Boss defeat at 10000–10400, results at 10800, stage-two scenery at 11400 in `stage-clear` |
| Reco / Abnormal | `reco-abnormal`, frames 3000–3400 | Boss defeat at 10200, clear transition at 10800, stage two at 11400 in `reco-abnormal-clear` |
| Palm / Normal | `palm-normal`, frames 2890–3400 | Results at 10800, stage two at 11400 in `palm-normal-clear` |
| Palm / Abnormal | `palm-abnormal`, frames 2890–3400 | Results at 10800, stage two at 11400 in `palm-abnormal-clear` |

![Verified stage-one results in the reference](images/stage-one-clear.png)
![Subsequent stage-two scenery in the reference](images/stage-two.png)

The local capture directories include original screenshots, RAM snapshots, input
scripts, runtime arguments, exact ROM identities and frame logs. These large
artifacts stay under ignored `build/`; compact evidence and images accompany the
source. Detailed capture parameters are in [reference runs](evidence/reference-runs.json).

Reference audio was captured as 48 kHz, signed 16-bit mono: 14,394,241 samples,
12,378,466 nonzero samples, peak absolute amplitude 15,388. This verifies that
the reference produces audio; listening quality and native audio equivalence are
not established by these numerical checks.

## Checks and limits

- Ten targeted format tests pass: overlapping references, flag boundaries,
  malformed streams, bad-block spanning, bounds, colors, word swapping and
  command lengths.
- Clang builds the native decoder with `-Wall -Wextra -Werror`; all compressed
  resources and the program match Python and the isolated original decoder.
- Every exported PNG and metadata link exists. Every observed-region PNG exactly
  equals its recorded crop of the source sheet.
- The local macOS reference launcher starts the graphical/audio runtime and exits
  successfully in a bounded smoke test. It depends on local emulator and ROM paths.
  It explicitly selects SDL audio: this MAME build's default CoreAudio backend
  hung during shutdown on this Mac, while SDL audio completed the same test.
- The browser automation connection was unavailable in this session. Catalog
  images/contact sheets and source data were inspected, and JavaScript syntax
  checked; interactive browser layout and keyboard behavior need a live UI pass.
- Automatic decompiler output remains unreviewed. It is never counted as native
  implementation coverage.

Next: recover menu scene/task dispatch and the descriptor tables behind the
observed draw regions, then implement and differentially validate those services.
