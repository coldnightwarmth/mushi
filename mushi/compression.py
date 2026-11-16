"""Bounded decoder for the CV1000 flag-stream LZ format.

Format reference: buffis/cv1k_research/U4_Utils/compress.py. This implementation
validates the stream before allocation and supports overlapping backreferences.
The game routine is tracked separately in docs/REVERSE_ENGINEERING.md.
"""
from dataclasses import dataclass
import struct


@dataclass(frozen=True)
class DecodeResult:
    data: bytes
    consumed: int
    operations: int


def decompress(source: bytes, *, limit: int = 32 * 1024 * 1024) -> DecodeResult:
    if len(source) < 12:
        raise ValueError("Truncated compression header")
    size, count, cursor = struct.unpack_from(">III", source)
    flags_end = 12 + (count + 7) // 8
    if size > limit or count > size or flags_end > cursor or cursor > len(source):
        raise ValueError("Invalid output size, operation count, or token offset")
    out = bytearray()
    for op in range(count):
        reference = source[12 + op // 8] & (0x80 >> (op % 8))
        token_size = 2 if reference else 1
        if cursor + token_size > len(source):
            raise ValueError(f"Truncated token {op}")
        if reference:
            token = (source[cursor] << 8) | source[cursor + 1]
            distance, length = token >> 5, (token & 31) + 3
            if not 0 < distance <= len(out) or len(out) + length > size:
                raise ValueError(f"Invalid backreference at token {op}")
            # Index against the growing output: overlap is deliberate.
            for _ in range(length):
                out.append(out[-distance])
        else:
            if len(out) >= size:
                raise ValueError("Literal exceeds declared output size")
            out.append(source[cursor])
        cursor += token_size
    if len(out) != size:
        raise ValueError(f"Decoded {len(out)} bytes; header declares {size}")
    return DecodeResult(bytes(out), cursor, count)
