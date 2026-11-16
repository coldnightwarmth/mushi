"""CV1000 resource directory and bad-block-aware reads.

The resource offsets address all 2112 bytes of each physical NAND page, including
the spare area. Do not remove 64 bytes per page before reading this directory.
"""
from dataclasses import dataclass
import struct
from .compression import decompress

PAGE_SIZE = 2112
BLOCK_SIZE = PAGE_SIZE * 64


@dataclass(frozen=True)
class Resource:
    index: int
    table_offset: int
    block: int
    offset: int
    length: int
    compression: int

    @property
    def physical_offset(self):
        return self.block * BLOCK_SIZE + self.offset


class Nand:
    def __init__(self, data: bytes):
        if len(data) != BLOCK_SIZE * 1024:
            raise ValueError("Expected a 1024-block CV1000 NAND image")
        self.data = data
        self.bad_blocks = frozenset(i for i in range(1024) if not data[8 + i // 8] & (1 << (i % 8)))
        self.resources = []
        for at in range(PAGE_SIZE, BLOCK_SIZE, 16):
            block, offset, length, compression = struct.unpack_from(">4I", data, at)
            if length in (0, 0xffffffff):
                self.directory_end = at
                break
            if block >= 1024 or offset >= BLOCK_SIZE or block in self.bad_blocks:
                raise ValueError(f"Invalid NAND directory entry at {at:#x}")
            if compression not in (0, 0x02000000):
                raise ValueError(f"Unsupported compression {compression:#x} at {at:#x}")
            self.resources.append(Resource(len(self.resources), at, block, offset, length, compression))
        else:
            raise ValueError("Unterminated NAND resource directory")
        self.header_count = struct.unpack_from(">I", data, 4)[0]
        if self.header_count != len(self.resources):
            raise ValueError("NAND header count does not match resource directory")

    def read(self, resource: Resource) -> tuple[bytes, list[dict]]:
        block, offset, remaining = resource.block, resource.offset, resource.length
        parts, spans = [], []
        while remaining:
            if block >= len(self.data) // BLOCK_SIZE:
                raise ValueError(f"Resource {resource.index} extends beyond NAND")
            if block in self.bad_blocks:
                block += 1
                continue
            take = min(remaining, BLOCK_SIZE - offset)
            at = block * BLOCK_SIZE + offset
            parts.append(self.data[at:at + take])
            spans.append(dict(offset=at, length=take, block=block))
            remaining -= take
            block, offset = block + 1, 0
        return b"".join(parts), spans

    def decode(self, resource: Resource) -> tuple[bytes, list[dict], int]:
        raw, spans = self.read(resource)
        if resource.compression:
            result = decompress(raw)
            return result.data, spans, result.consumed
        return raw, spans, len(raw)
