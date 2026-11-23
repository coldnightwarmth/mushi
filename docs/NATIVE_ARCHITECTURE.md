# Native build and future combined game

The requested deliverable is a native macOS game like the ESP Ra.De development
build: a Swift/AppKit frontend with native game services. The current MAME
reference app does not satisfy that deliverable. A new launcher around MAME,
a renamed emulator, or a capture-playback window cannot close the native milestone.

The native app now runs the menus and all five stages in Original mode with
Reco/Palm and Normal/Abnormal. Four native input replays defeat every boss,
complete the epilogue/ranking flow and return to attract. The user explicitly approved ahead-of-time
recompilation while readable gameplay source is recovered.

## Ahead-of-time game code

`tools/recompile_program.py` emits fixed C++ statements for each supported
instruction address and operand combination. Clang compiles those functions
into ARM64 code before packaging. Indirect branches dispatch to native functions;
there is no runtime instruction fetch/decode, CPU interpreter or JIT fallback.
Unsupported addresses stop with an error. The three interrupt stubs copied at
boot have separate compiled RAM forms; ROM startup remains distinct.

`CompiledState.hpp` is the calling/state ABI between generated functions.
`Board.cpp` supplies memory, NAND, DMA, serial EEPROM, input ports, timers and
interrupt delivery. `Graphics.cpp` implements command-list rendering, and
`Audio.cpp` provides native YMZ770C sequencing/mixing with an independent AMM
codec. BSD references and the vendored codec are credited in
[third-party notices](../native/THIRD_PARTY_NOTICES.md).

`NativeGame.h` exposes frames, pixels, samples, scene category, settings and
checkpoints to Swift. Immutable program/resource/audio data is shared; a restart
checkpoint copies simulation state, RAM, graphics memory and audio decoder state.
At every stage entry, a 90-frame input sequence reproduces identical graphics
and audio after restart: 20 checks across the four full campaigns. Run restart
and current-stage restart retain separate checkpoints; they share the same
checkpoint at stage one to avoid a redundant graphics-memory copy.
The serial EEPROM samples clock edges; tests cover all 256 words, repeated writes
at the same clock level, and an operator difficulty change displayed after relaunch.
The frontend has no access to Futari RAM addresses. This interface is also the
boundary for eventual combinations with the ESP Ra.De build.

The separately recovered Swift input implementation remains an independently
verified replacement candidate. The AOT game currently calls its compiled input
routines; the shared Swift physical controls and Futari port adapter are integrated.
This is native recompilation, not a complete readable-source decompilation.
Peripheral timing is functional but complete cycle/slowdown accuracy is unproven.

## Custom menu and reviewed extension points

The shared ESP Ra.De. art engine, menu vocabulary and bitmap font are under
`native/shared/`. `FutariVisuals` supplies native scenery, actors, HUD and impact
layers; it does not read game RAM. `FutariTrails` is a bounded, render-only sprite
history. The C adapter exposes custom options, status, layers, multiple worlds
and rewind. See [the custom menu guide](CUSTOM_MENU.md) for the adaptations.

Eight optional, compile-time call sites cover movement at `0x0c07900e`, left/right
limits at `0x0c07902a` and `0x0c079036`, protected contact at `0x0c079e86`, and
scenery integration at `0x0c09b912`, and the scrolling controller's matching
left/right bounds at `0x0c09c712`, `0x0c09c6fe` and `0x0c09c706`. The original statements still execute with
options disabled. Other hooks observe writes to recovered player, credit and
stage-clock fields; no runtime instruction decoder is added.

`NativePresentation` records command headers in both alternating list buffers,
recovers sorted draw priorities, and retains both completed display buffers.
Selection follows the actual display registers, including repeated buffers
during busy frames and camera offsets. Layer
zero is checked against the actual native framebuffer. Tilemaps and native
foreground shading form scenery; priorities 236+ form HUD; explosion/impact
priorities 150–153 feed the art effects. These are presentation categories,
not complete semantic object/animation recovery. The 0.5 presentation adapter
splits visible actors into disjoint FX, player/weapon, enemy/projectile and
other-actor planes, retaining original occlusion. The renderer selects a separate
shared effect engine for each resolved target combination. Broader/narrower banks
resolve to one variant per effect per group; child histories share a bounded
budget. Saved presets use the same named schema as ESP Ra.De. in a separate
Futari Application Support directory.

`NativeHistory` saves changed 4 KiB RAM pages and 32×32 VRAM tiles before their
first write each frame, plus an independent device/audio checkpoint. Records use
Apple's LZ4 compression and a per-world limit. Formation pulse and absorption
counters rewind with simulation state. EEPROM settings remain outside gameplay
rewind. Restarts restore the separate native run/stage snapshots.

Combined play instantiates the original stage loader three times, with initial
stage indices 0/1/2. Each instance retains a distinct native board and collision
state while sharing immutable ROM/resource/audio data. Rewind advances all
worlds together; endless resets only the world that completed its opening.

## Campaign state and extraction

`CampaignState.hpp` names the paid-game context at `0x0c38a530`, its phase word,
stage index and all-clear flag. Its layout comes from the dispatcher at
`0x0c067a70`, gameplay callback `0x0c0694e0`, and observed transitions in all four
runs. `FutariStatus` exposes phase, mode, stage and restart availability without
putting addresses in the frontend. This is reviewed state-layout recovery,
not a replacement claim for the compiled stage/boss algorithms.

The native frontend uses a graphics observer for custom layers and rewind.
The separate extraction observer hashes a
complete 256×256 source page before recording a contained draw rectangle. Any
upload or draw to a page invalidates its cached identity, including wraparound
uploads and writes through a copied/dynamic page. The tooling matches SHA-256
against all 1,201 decoded resource pages and records stage, inputs, frame range,
attributes and usage count. It does not infer animation boundaries or stitch
multipart art. Original reference observations remain separately attributed.

`NativeInspection.hpp` is a tooling-only interface. The Swift frontend imports
only the public C adapter. Full campaign verification uses that same adapter,
ordinary cabinet inputs, normal damage and paid continues. Extra restart checks
run on restored checkpoints and then restore again before the recorded route
continues; they neither grant invulnerability nor skip stages.

## Code boundaries

The user intends to combine elements of the two native games eventually. Keep
these boundaries while recovering Futari; do not rewrite the working ESP Ra.De
project as part of this foundation work.

- `native/platform/`: physical keyboard layout and game-independent button
  actions. Future window, camera and presentation code belongs on this side of
  the boundary. It must not read a game RAM address or know a hardware port bit.
- `native/core/`: Futari-specific original memory layout, input clocks, rendering
  formats, scheduler, player/enemy behavior, collisions and audio sequencing.
  `FutariInputPorts` adapts shared actions to this game's cabinet wiring.
- Native verification harnesses compare services to original instructions using
  explicit state records. Original-code execution is an oracle, not part of
  the native runtime. Generated AOT functions are tracked separately from the
  count of hand-recovered readable services.

When adding presentation and object interfaces, retain each game's simulation
rate and coordinate space in its adapter. A shared camera must not silently
change simulation bounds, input timing or damage rules. Render-facing assets
need a game namespace, source object/frame IDs, original anchor, dimensions and
layer order. Their palette/ARGB decoding remains game-specific. These boundaries
allow later compositing or deliberate gameplay combinations without treating
ESP Ra.De's 68000 RAM and Futari's SH-3 RAM as a shared object model.

No cross-game character, weapon, stage or effect combination is implemented yet.

## Shared controls

The logical button values match ESP Ra.De's `FirstStageView.bit` mask. Physical
key aliases are tracked independently, short taps survive until the next game
tick, and focus/menu/title transitions can clear held and pending inputs.

| Key | Shared action | Futari meaning |
| --- | --- | --- |
| Arrows / WASD | Move | Move / select |
| J | Primary attack | Shot / held laser / confirm |
| K or X | Secondary attack | Full auto |
| L | Special attack | Bomb |
| Return | Start | Start / continue |
| Backslash | Credit | Insert credit |
| Space | Host pause | Pause / resume |
| Tab | Host menu | Open / close native menu |
| M | Host mute | Toggle game audio |
| Escape | Host title | Return to title; do not quit the app |
| R | Host restart | Restart the current run |
| P | Host filtering | Toggle image filtering |
| Z | Camera zoom | Hold centered 2× presentation zoom; never shoot |
| Shift | Quick boost | Hold 2.5× movement speed when enabled |
| Q / E | Time controls | Hold 2× rewind / temporary 4× playback |
| I / − / + | Custom shortcuts | Protection / background / HUD |

Host commands are modeled separately from arcade buttons. Pause/menu stop the
simulation; mute/filtering/zoom affect presentation. R restores the selected run's
first-stage checkpoint; the menu also restores the current stage. Escape returns
to title/attract. Focus loss clears input.
The native menu also supplies the two-second operator-switch hold and fullscreen.

## Implemented input services

`InputState.swift` translates six routines: initialization (`0x0c05c4f0`), frame
advance (`0x0c05c62c`), held/edge/repeat queries (`0x0c05ca18`, `0x0c05ca30`,
`0x0c05ca48`), and cabinet output-pulse enqueue (`0x0c05caa0`).

Both 68-byte records, all nine repeat bits, custom delays, unsigned wrapping,
and nonzero player selectors match the original in 2,781 cases, including
81 captured game states. Initialization deliberately preserves the edge latch
at offset `0x10`, as the original does. Native keyboard checks cover overlapping
aliases, short taps, focus reset, host-command repeat suppression, and the
different physical ordering of Futari's bomb/full-auto buttons.

The IRQ sampler, coin/credit controller, menus, scheduler and stage logic execute
as compiled native functions. Their playable scope is established by the four
full five-stage native campaigns, separately from the input-service differential checks.

## Headless reference policy

All capture and differential-test runs force SDL's **dummy** video and audio
drivers, disable desktop input providers, and disable INI loading. If the dummy
backend is unavailable, startup must fail; there is no fallback to Cocoa.
MAME's `-video none` alone was insufficient to prevent desktop interference on
this machine. Native services and their tests have no MAME runtime dependency;
MAME is used only when generating original-instruction comparison results.

The completed input run logs `Current Videodriver: dummy`. Its compact results
are in [native-input.json](evidence/native-input.json).

```sh
.venv/bin/python tools/verify_native_input.py \
  --rom /path/to/futari15.zip \
  --mame /path/to/mame \
  --frameworks /path/to/frameworks
```
