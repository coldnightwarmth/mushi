# Recovered formats and entry points

This document separates format recovery, original-instruction verification and
unreviewed decompiler output. Addresses refer to the exact supported revision.

## ROM regions

| Archive member | Size | Meaning |
| --- | ---: | --- |
| `futari15_u4` | 2,097,152 | Word-swapped SH-3 boot/program ROM |
| `futari15_u2` | 138,412,032 | NAND image, including spare bytes |
| `u23` | 4,194,304 | YMZ770 sound bank 0 |
| `u24` | 4,194,304 | YMZ770 sound bank 1 |

Expected hashes are in `mushi/rom.py`. All members are validated before decoding.
Futari uses CV1000-B, SH7709S big-endian code, an FPGA blitter, 8 MiB work RAM and
YMZ770 audio. The ESP Ra.De. 68000 bridge and palette/tile decoders cannot directly
execute or decode this program.

## U4 program expansion

Swap adjacent bytes in U4 to obtain the SH-3 big-endian instruction stream.
The first `0x51000` bytes are copied to RAM by the boot code. At swapped-ROM offset
`0x51000`, a flag-stream LZ payload expands to **2,945,856 bytes**. The boot caller
passes destination `0xac051000` and source `0xa0051000` to the decoder. The cached
RAM alias is `0x0c051000`. Program prefix and expanded payload are emitted as
`build/program/expanded.bin`, based at `0x0c000000` for analysis.

| Address | Evidence / status |
| --- | --- |
| `0x0c000000` | Boot-code copy viewed through the cached RAM alias |
| `0x0c000094` | Loads decoder destination into R4 and source into R5 |
| `0x0c00009a` | Calls the decoder address stored at `0x0c000198` |
| `0x0c002ac4` | Reviewed LZ decoder entry; native/Python/original output equality |
| `0x0c002b52` | Decoder RTS, followed by NOP delay slot |
| `0x0c051614` | Graphics initialization candidate, called through literal at `0x0c0630a4`; semantics not translated |
| `0x0c05176a` | Repeatedly observed waiting PC; not a stage identifier |
| `0x0c05dbd0` | Initial RAM-clear helper called from boot; not translated |
| `0x0c062fa0` | Main initialization/dispatch loop; not translated |

Decoder input consists of three big-endian u32s: decoded size, token count and
token-data offset. Flags start at byte 12, most significant bit first. A zero
flag copies one literal byte. A one flag consumes a big-endian u16: distance is
`token >> 5`, length is `(token & 31) + 3`. Copies advance through growing output,
so overlapping references are required. R0 returns the declared output size.

The native and Python services reject truncated streams, out-of-range references,
overruns and inconsistent sizes. Those checks intentionally add bounded behavior
for malformed inputs; they are not claims about how the original routine handles
malformed data. Exact equivalence was checked on every valid compressed stream
in the supplied ROMs.

## NAND directory

- 1,024 blocks, 64 physical pages per block, 2,112 bytes per page.
- The bad-block bitset occupies bytes 8–135; bit zero is the first block and
  **zero means bad**. This particular image reports no bad blocks.
- Directory records start at physical offset `0x840` (2,112).
- Each 16-byte record contains big-endian u32 block, offset within block, stored
  length, compression kind. A zero/all-ones length terminates the table.
- The header count at offset 4 agrees with all **1,201** parsed records.
- Kind `0` is raw (929 records); `0x02000000` is LZ (272 records).
- Resource reads span physical blocks, skipping any marked bad blocks. Spare
  bytes are part of the addressed stream; stripping 64 bytes per page is wrong.

Every resource in this revision decodes to a 256 × 256 bitmap payload: 16-byte
header, 131,072 bytes of pixels and a four-byte `ffffffff` terminator. The first
six header words are preserved as raw metadata; no unverified meaning is assigned
to them. Width/height minus one are at byte offsets 12 and 14.

Pixels are big-endian ARGB1555: bit 15 controls opacity, red occupies 14–10,
green 9–5 and blue 4–0. Each five-bit channel is shifted left three, matching the
reference upload path (maximum 248, not stretched to 255). Transparent pixels'
RGB values are preserved. Previews rotate 90 degrees counterclockwise; downloadable
source PNGs preserve board orientation and source coordinates.

## Blitter observations

### Original frame directory

The table at `0x0c20bf14` contains 49,589 ten-byte records; its u32 count is at
`0x0c285028`. `RecoveredSpriteFrames.hpp` expresses the reviewed read/coordinate
contract consumed by original wrapper `0x0c063740`:

| Byte offset | Field |
| --- | --- |
| 0 | u16 resource-directory ID |
| 2, 3 | u8 upright x, y |
| 4, 6 | u16 upright width, height |
| 8 | u16 frame ID, equal to the record index |

The wrapper passes board source rectangle `(256-y-height, x, height, width)`
to `0x0c05df30`, with destination axes exchanged from the 16.16 input positions.
All 49,589 entries and four unsigned out-of-range IDs were compared against the
original compiled wrapper. A booted native board also confirms that its 1,201
16-byte resource entries are an exact copy of the NAND directory, preserving IDs.
The table spans 947 resource sheets. All crop bounds are inside their 256-square
source page; the table ends at `0x0c285026`, before the aligned count word.

`tools/extract_frames.py` exports upright RGBA PNGs and exact descriptor bytes,
addresses, source rectangles and pixel hashes. All crops are compared pixel for
pixel, including transparent RGB channels. The 49,589 entries correspond to
49,538 distinct source rectangles and 48,214 distinct dimension/pixel hashes.
This table supplies frame boundaries, not animation links or duration fields.

### Runtime drawing observations

Reference VRAM is 8,192 × 4,096, exported as little-endian u32 values on this
arm64 MAME build. A decoded source pixel is represented as
`(opacity << 29) | (red << 16) | (green << 8) | blue`.

The matcher hashes complete 256 × 256 VRAM pages and compares them to decoded
ROM sheets. Exact matches establish page ownership at the captured instant.
Only draw rectangles wholly inside a matched page are exported. Cross-page draws,
dynamic buffers and composite sources remain explicitly unmapped.

Command lists have draw (`0x1`, 20 bytes), upload (`0x2`, 16-byte header plus
pixels), clip (`0xc`, four bytes), and terminate (`0x0`/`0xf`) operations. Source
coordinates and dimensions are masked to the hardware widths. Attributes, command
address, capture, frame, selected character and shot type accompany each region.
Repeated uses of the same source rectangle are grouped without claiming animation
timing. A live command buffer can describe a pending backbuffer; its snapshot frame
is an observation timestamp, not proof of the visible animation phase.

## Paid-game context and full campaign

The paid-game context begins at `0x0c38a530`. These fields were reviewed against
the original dispatcher and checked in all four complete native routes:

| Address / offset | Recovered meaning |
| --- | --- |
| `0x0c38a4b4` (outside context) | Outer scene: 3 attract, 5 paid game, 6 operator menu |
| Context `+0x48` | Paid-game phase: 0–2 setup/selections, 3 loading, 4 gameplay, 5 game-over sequence, 6 ranking, 7 epilogue, 8 teardown |
| Context `+0x4a` | Substate within the paid-game phase |
| Context `+0x50` | Mode; 0 selects Original in the verified routes |
| Context `+0x56` | Zero-based stage index, 0 through 4 |
| Context `+0x144` | All-clear flag, read by the gameplay callback before scheduling the epilogue |

`0x0c067a70` dispatches the paid-game phases. Its gameplay callback is
`0x0c0694e0`; it schedules the epilogue task at `0x0c11a560` when the all-clear
condition is met. The game-over and ranking callbacks are `0x0c069580` and
`0x0c069610`. The compiled originals still execute these transitions.
`CampaignState.hpp` provides a readable, non-mutating view of their state for
the frontend, extraction tools and verification.

Every native campaign reached stages 0–4 in order, set the all-clear flag,
entered phase 7, completed the epilogue/ranking flow and returned to outer
scene 3. Inputs after epilogue entry are released; confirmation presses are
used only during ranking. No damage rules, stage indices, lives or enemy HP
are patched. The input transcripts and state timelines are reproducible with
`tools/verify_native_campaign.py`; compact results are tracked in
[evidence/native-campaigns.json](evidence/native-campaigns.json).

The native graphics observer matches complete source pages to decoded ROM
sheets using SHA-256. It invalidates page identities on every destination write,
then records contained source rectangles with stage and frame ranges. Across
four full runs it matched 1,091 sheets; merging the original reference evidence
yielded 64,458 nonblank regions. Cropped tile/glyph variants remain distinct,
and these are not claims of 64,458 independent sprites or verified animations.

## Ghidra

Run `tools/analyze_program.py --ghidra /path/to/ghidra --java-home /path/to/jdk`.
The script seeds reviewed entries and uses `SuperH4:BE:32:default` as the available
instruction-set superset for SH-3 analysis. The actual CPU is SH-3. SH4-only
interpretations, calling conventions and automatically inferred functions require
manual review. Function ID is disabled because generic library signature scans
do not establish game-specific semantics. Exports live under ignored `build/`.

Pseudocode is an analysis aid, not buildable original source, and never counts
toward native gameplay completion. Neither source-region observations nor
repeated PC samples establish an object scheduler, hitbox or stage state machine.

## Sound directory and native PCM extraction

The concatenated u23/u24 bank is word-swapped, producing 8 MiB. Table 0 contains
256 four-byte phrase entries: the high nibble selects the AMM parameter table;
the lower 24 bits are a byte offset. Decoding begins at offset × 8 and ends on
the original short/empty AMM packet. The extractor bounds each phrase by the
next distinct directory offset, and all 167 unique entries terminate within
that bound. One is empty; 166 produce 19,732,352 mono samples. Every nonempty
packet reports 16 kHz. The native mixer at unity volume produces exactly the
same signed PCM samples, then silence at the extracted end.

The sequence directory starts at bank offset 0x400. All 256 pointers resolve
to 23 distinct streams of register/value byte pairs terminated by register
0x0f. Register 0x0e represents the native sequencer's delay operation. These
streams are exported without guessing song names. Another pointer table at
0x800 remains to be semantically reviewed; the published sequence coverage
refers specifically to the 0x400 table. Sound-name recovery and original-hardware
audio equivalence are separate from the native decoder consistency check.

Reproduce with `tools/extract_audio.py --rom /path/to/futari15.zip`. The tool
never starts an audio device or emulator. WAV files, alias metadata and sequence
commands are included in the GitHub Pages sound archive.

## Reviewed stable-priority graphics queue

`RecoveredDrawQueue.hpp` expresses the append routine at 0x0c05c394 as a readable
FIFO operation. The control record at 0x0c058338 stores a node-pool pointer and
byte cursor; 512 head/tail buckets begin at 0x0c058340. Each 16-byte node stores
next at +0, callback at +4 and payload at +8. Priorities are masked to nine bits.
The 0x17700-byte pool admits 6,000 entries. A full pool rejects an append without
writing queue state; the append leaves new-node next untouched, relying on the
original initialization/drain contract.

The accompanying exact ABI adapter and test compare every priority with empty,
nonempty and full conditions: 1,536 cases. All RAM bytes, ordered writes,
registers, status flags and the 17/28-instruction paths match compiled originals.
This reviewed service is not yet enabled in the installed app: full replay and
interrupt-boundary integration checks are the next step. See
[evidence/recovered-draw-queue.json](evidence/recovered-draw-queue.json).
