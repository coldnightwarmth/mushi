# Status — 2026-11-22

**Native menus and all five Original-mode stages are playable on Apple Silicon
macOS.** The signed 0.5.1 app uses ahead-of-time compiled game code, native
peripheral services and Swift/AppKit. It has no MAME runtime, CPU interpreter,
or runtime compiler.

All four character/shot routes completed the entire campaign using ordinary
damage and paid continues, followed by the unskipped epilogue, ranking and return
to attract. The full runs total **360,048 native frames**. Each stage also passed
a 90-frame restart comparison of both pixels and audio: **20 checks**.
See [native-campaigns.json](evidence/native-campaigns.json).

| Native check | Result |
| --- | --- |
| Reco / Normal | All five stages; ending at 82511; attract at 90239 |
| Reco / Abnormal | All five stages; ending at 84410; attract at 92129 |
| Palm / Normal | All five stages; ending at 80729; attract at 87977 |
| Palm / Abnormal | All five stages; ending at 82465; attract at 89699 |
| Compiled arithmetic | 2,592 exact original-instruction comparisons |
| Compiled input / Swift input | 2,781 exact original-state comparisons each |
| Graphics | 1,045 draw cases, all 64 blend pairs, full VRAM byte exact |
| Restart stage | All 20 stage/character/shot combinations reproduce graphics and audio |
| Game over | Continue timeout, Game Over and return to attract exercised |
| Operator menu | Game configuration, Save & Exit, changed difficulty after relaunch |
| EEPROM | 256 words round-trip; repeated high-clock writes ignored |
| Bundle | Signed ARM64; headless macOS launch diagnostic |

![Native stages and epilogues](images/native-full-campaign.png)

Controls follow ESP Ra.De. R / Restart game starts the selected run over from
stage one. Tab → Restart stage restores the current stage. The menu shows the
current stage, and the public game adapter exposes named campaign phases and
completion state without leaking RAM addresses into the frontend.

This establishes full Original-mode native playability, not completed readable
source recovery. Hardware cycle/slowdown equivalence and other modes remain
unverified. Physical window/fullscreen interaction was not exercised on the
active desktop. All work in this milestone was headless; no MAME process was
needed for the full-game runs. Bundle identity is in
[native-bundle.json](evidence/native-bundle.json).

The 0.5.1 build replaces the draw-queue append with reviewed native code. A
90,240-frame comparison against the original AOT dispatcher matched registers,
RAM, IO, audio and interrupt counts through all five stages, ending and attract;
758 complete VRAM comparisons also matched. See
[recovered queue evidence](evidence/recovered-draw-queue.json).

## Custom menu

The native build includes the ESP Ra.De. custom menu, adapted to Futari: 45 actions,
all 45 art-effect variants, ten trail styles, Reco/Palm formation, combined and
endless stages, exploration, infinite bombs/credits, protection modes, expanded
view, playback speeds and rewind. Shared art code and game-specific simulation
remain separated for future combinations.

The 0.5.0 update adds independent effect banks, persistent presets, randomization,
Melt/Bloom Datamosh and target-specific trails. The updated menu passes 142,193
offscreen assertions; all four routes and combined-stage checks pass.

The [menu guide](CUSTOM_MENU.md) explains the adaptations and shortcuts.
[Custom-menu evidence](evidence/native-custom-menu.json) records native and
offscreen checks. The original four complete ordinary-damage campaign baselines
above remain separate from custom-option stress runs.

## Verified resource recovery

| Measure | Result |
| --- | ---: |
| Supplied ROM members verified | 4 / 4 |
| Directory-listed bitmap sheets decoded | 1,201 / 1,201 |
| Raw / compressed sheets | 929 / 272 |
| Decoded bitmap payload bytes | 157,441,492 |
| Unique bitmap payloads | 1,201 |
| Sheets matched exactly to original VRAM | 569 |
| Sheets matched exactly to native source pages | 1,091 |
| Observed draw rectangles exported | 64,458 |
| Original frame-directory entries | 49,589 |
| Sheets referenced by original frames | 947 |
| Distinct frame pixel images | 48,214 |
| Native stage coverage | All five stages, four routes |
| Screenshot / framebuffer comparisons | 21, all exact |
| Verified primary-layer animation sequences | 9 |
| Verified particle timing profiles | 102 |
| Sound-directory entries accounted for | 256 / 256 |
| Nonempty sound phrases decoded | 166 |
| Native audio samples compared exactly | 19,732,352 |
| Native decoder streams checked against original SH-3 | 273, all exact |
| Decoder output bytes compared | 38,602,880 |

See [coverage](evidence/catalog-coverage.json),
[drawing observations](evidence/graphics-observations.json),
[catalog validation](evidence/catalog-validation.json),
[native decoder results](evidence/native-decoder.json), and
[original-instruction results](evidence/original-decoder.json).

The 64,458 regions are distinct resource rectangles, not a unique-art or animation
count. Many are cropped glyphs, background strips, partial UI pieces or partial sprites.
The browser supports stage filtering and uses a compact index; complete evidence
is retained in per-region JSON and the downloadable compressed manifest.
Draws from dynamic/cross-page VRAM sources are retained as unmapped counts.

The separate [original-frame browser](https://coldnightwarmth.github.io/mushi/frames/)
contains the complete program frame directory. All 49,589 descriptors were checked
against the compiled original drawing wrapper, including its rotated source
coordinates. Every upright PNG matches its source crop. There are 1,375 repeated
pixel images and 260 transparent entries; both remain cataloged. Consecutive IDs
are not assumed to be an animation sequence. See [frame evidence](evidence/frame-extraction.json).

Three green-burst tracks now have verified order and duration from callback
`0x0c07bf60`: eight frames, one active update tick each, then termination. Four
reachable variants share these tracks and use different secondary glow images.
All 256 countdown-delay byte values were checked against original code in 1,024
fixtures / 239,360 callback ticks. The [sequence browser](https://coldnightwarmth.github.io/mushi/animations/)
previews the primary layer; final glow blending and motion are not claimed as a
pixel-exact animation reconstruction. See [animation evidence](evidence/animation-extraction.json).

Six additional particle tracks cover types 0 and 5 across three original frame
tables. Every initial fade (239–255), table choice and flip was compared through
termination: 204 complete cases, 8,808 updates and 8,604 draw submissions. The
fast tracks last 23 updates; slow tracks last 59–63 depending on fade. The browser
exposes all 102 timing profiles, without counting parameter choices as new
animation families. Source frames and durations are previewed; original fade
blending, motion and offscreen culling are recorded or excluded explicitly.

The random helper, polar velocity, both initializers and sequencing body now
have readable implementations and original-code comparisons. They support
verified extraction and have not replaced their original native AOT routines.
See [particle recovery](evidence/recovered-particles.json).

## Sound recovery

The [sound archive](https://coldnightwarmth.github.io/mushi/audio/) adds every
nonempty phrase in the verified u23/u24 directory as 16 kHz mono WAV, with source
ranges, hashes and aliases. There are 167 unique entries: 166 nonempty and one
empty; 89 additional slots alias an existing entry. Every extracted PCM sample
matches the native audio path at unity gain. The 256-entry sequence directory
has 23 distinct terminated command streams, preserved in compressed JSON.
Names, gameplay roles and assembled soundtrack arrangements remain unverified.
See [audio evidence](evidence/audio-extraction.json).

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
- The installed 0.5.1 bundle passes code-signature verification and a Launch
  Services diagnostic that executes 120 native frames without opening a window
  or audio device. Resources are bundled locally and writable settings use
  Application Support. The earlier MAME launcher has been replaced entirely.
- A hidden-browser pass verified resource/region switching, stage filtering,
  combined stage/text searching and region detail provenance. Stage five has
  339 matched sheets and 16,524 observed regions. The complete browser index also
  matches the full extraction manifest. Keyboard-only navigation and physical
  game-window/fullscreen interaction remain untested.
- Automatic decompiler output remains unreviewed. It is never counted as native
  implementation coverage.

Next readable-source work: replace generated game functions with reviewed
services while preserving native replay behavior; recover semantic sprite
assemblies, object identities, animation order and timing.
