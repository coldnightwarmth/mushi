# First native milestone

Target fixed by the request: macOS, Futari 1.5, Original mode, Reco and Palm,
both Normal and Abnormal. First-stage completion includes the boss and results.

The current reference app provides a playable comparison target. It does not
close any native gameplay checkbox below.

## Completed foundation

- [x] Revision-locked ROM ingestion and complete resource directory inventory.
- [x] Native resource decoder with original-instruction differential checks.
- [x] Bitmap decoding with source offsets, hashes and coverage reporting.
- [x] Runtime command capture and exact resource-to-VRAM matching.
- [x] macOS reference launcher, keyboard controls, audio and input replays.
- [x] Reference menu-to-stage entry exercised for all four character/shot choices.
- [x] Reference stage-one boss defeat/clear followed into stage two for all four choices.

## Native menu and stage-one implementation

- [ ] Recover scheduler, frame timing, task dispatch and scene state.
- [ ] Recover original resource upload/lifetime and sprite descriptor tables.
- [ ] Implement native rendering, clipping, transparency, blending and draw order.
- [ ] Implement title/attract, credits/start, mode/character/shot selection.
- [ ] Recover and implement operator/service menus and their stored settings.
- [ ] Implement both players' movement, all power levels, shots, lasers and bombs.
- [ ] Recover first-stage map, scroll, waves, enemies and score/pickup rules.
- [ ] Translate collision, damage, death, respawn, continue and game over.
- [ ] Translate midboss/boss movement, patterns, phases, defeat and results.
- [ ] Implement audio event routing/playback and validate timing.
- [ ] Build a native macOS frontend and verify focus, pause, input and fullscreen.
- [ ] Compare deterministic native replays with the original across all four routes.
- [ ] Verify title → stage-one clear with ordinary damage and paid continues.

## Comprehensive semantic asset catalog

- [ ] Recover descriptor tables and assign stable logical object/frame IDs.
- [ ] Assemble multipart sprites using original anchors and layer order.
- [ ] Recover animation sequences, durations, loops and transition conditions.
- [ ] Classify players, weapons, enemies, bosses, pickups, effects, UI and scenery.
- [ ] Audit every resource against code references and unexplained regions.
- [ ] Validate unobserved paths; runtime sampling alone cannot prove completeness.

Next implementation entry: trace the main loop at `0x0c062fa0` into scene/task
dispatch and identify the sprite descriptor/resource tables used by the menu.
Promote one reviewed service at a time to native code, with original-instruction
or deterministic replay evidence attached to that service.
