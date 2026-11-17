# Native build and future combined game

The requested deliverable is a native macOS game like the ESP Ra.De development
build: a Swift/AppKit frontend with native game services. The current MAME
reference app does not satisfy that deliverable. A new launcher around MAME,
a renamed emulator, or a capture-playback window cannot close the native milestone.

The native app now runs the menus and first stage in Original mode with
Reco/Palm and Normal/Abnormal. Four native input replays defeat the first boss,
display results and reach stage two. The user explicitly approved ahead-of-time
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
A 90-frame input sequence reproduces identical graphics and audio after restart.
The serial EEPROM samples clock edges; tests cover all 256 words, repeated writes
at the same clock level, and an operator difficulty change displayed after relaunch.
The frontend has no access to Futari RAM addresses. This interface is also the
boundary for eventual combinations with the ESP Ra.De build.

The separately recovered Swift input implementation remains an independently
verified replacement candidate. The AOT game currently calls its compiled input
routines; the shared Swift physical controls and Futari port adapter are integrated.
This is native recompilation, not a complete readable-source decompilation.
Peripheral timing is functional but complete cycle/slowdown accuracy is unproven.

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

Host commands are modeled separately from arcade buttons. Pause/menu stop the
simulation; mute/filtering/zoom affect presentation. R restores the selected run's
stage-entry checkpoint; Escape returns to title/attract. Focus loss clears input.
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
full native route runs, separately from the input-service differential checks.

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
