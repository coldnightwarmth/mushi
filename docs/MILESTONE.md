# First native milestone

Target fixed by the request: macOS, Futari 1.5, Original mode, Reco and Palm,
both Normal and Abnormal. First-stage completion includes the boss and results.

The first native playable target is implemented and verified by headless native
playthroughs. This uses the user-approved ahead-of-time recompilation approach;
readable-source recovery remains a separate, ongoing task.

## Native menu and stage-one implementation

- [x] Compile original game functions ahead of time into ARM64 code.
- [x] Native boot, interrupts/timers, task dispatch and scene progression.
- [x] Native NAND/resource reads, DMA uploads and original sprite descriptors.
- [x] Rendering, clipping, transparency, all blend modes and draw order.
- [x] Title/attract, credits/start, mode/character/shot selection.
- [x] Original operator menu, game configuration and persisted EEPROM settings.
- [x] Reco and Palm movement, original weapons, power levels and bombs.
- [x] First-stage map, scrolling, waves, score and pickups.
- [x] Original collisions, damage, death, respawn, continue and game over paths.
- [x] Midboss/boss patterns, phases, defeat and results.
- [x] Native YMZ770C sequencing, mixing and AMM playback.
- [x] Swift/AppKit frontend with shared controls, pause/menu/mute/filtering,
  zoom, fullscreen support, focus input clearing and run restart.
- [x] All four Original-mode routes reach stage-one clear and stage two using
  ordinary damage and paid continues in 15,000-frame native runs.
- [x] Headless bundle startup and deterministic 90-frame restart checks.
- [ ] Exercise physical window/focus/fullscreen interaction on an idle desktop.
- [ ] Establish complete cycle/slowdown equivalence with the original hardware.

Evidence: [native playthroughs](evidence/native-playthroughs.json),
[arithmetic](evidence/native-aot-alu.json), [graphics](evidence/native-graphics.json),
[input](evidence/native-input.json). The app has no MAME/CPU-interpreter dependency.
The original state machines are compiled; marking them playable does not claim
that their generated C++ is readable recovered source.

## Readable source recovery

- [x] Six hand-translated Swift input routines and original-instruction checks.
- [x] Hand-translated C resource decompressor, all 273 streams checked.
- [ ] Replace compiled scheduler/menu/player/enemy functions with reviewed source.
- [ ] Publish game-level interfaces for cross-game object/weapon combinations.

## Comprehensive semantic asset catalog

- [ ] Recover descriptor tables and assign stable logical object/frame IDs.
- [ ] Assemble multipart sprites using original anchors and layer order.
- [ ] Recover animation sequences, durations, loops and transition conditions.
- [ ] Classify players, weapons, enemies, bosses, pickups, effects, UI and scenery.
- [ ] Audit every resource against code references and unexplained regions.
- [ ] Validate unobserved paths; runtime sampling alone cannot prove completeness.

Future replacements must preserve the native replay evidence and the
[shared frontend/game adapter boundary](NATIVE_ARCHITECTURE.md).
