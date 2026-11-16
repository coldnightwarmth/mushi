# Research sources

Inputs to this project are the user-supplied `futari15.zip` and the existing local
ESP Ra.De. reconstruction as a workflow reference. ESP Ra.De. game-specific
code, captures, palettes and recovered object tables are not reused for Futari.

- [MAME CV1000 driver](https://github.com/mamedev/mame/blob/cd9a88ea5e3bf7d91804b05ee93fa4f67e8ecab3/src/mame/cave/cv1k.cpp):
  supported ROM identities, CPU, memory map and input wiring.
- [MAME CV1000 blitter](https://github.com/mamedev/mame/blob/cd9a88ea5e3bf7d91804b05ee93fa4f67e8ecab3/src/mame/cave/cv1k_v.cpp):
  bitmap upload representation, commands, coordinates and display-memory layout.
  MAME credits David Haywood, Luca Elia and MetalliC for these BSD-3-Clause files.
- [buffis CV1000 research](https://github.com/buffis/cv1k_research/tree/a4b675885ddb6e41c7ac55cb4d9a3cca153f1829):
  NAND directory/bad-block layout, bitmap headers, compression format and blitter
  research. Especially `U2_ExtractData`, `U4_Utils`, and `Blitter_Utils`.
- [MAME Lua memory API](https://docs.mamedev.org/luascript/ref-mem.html) and
  [device API](https://docs.mamedev.org/luascript/ref-devices.html): reference
  capture and isolated-original-routine harnesses.

The local comparison runtime is MAME **0.286**, distinct from the newer pinned
source revision consulted for documentation. Native timing accuracy is not
claimed from this reference setup. Decompiler output is generated locally with
Ghidra **12.1.4** and remains unreviewed unless a specific routine is documented.

The repository's Python and C resource implementations are newly written,
bounded implementations of the recovered formats. Downloaded upstream research
copies are ignored, and upstream code is not bundled into the source tree.
