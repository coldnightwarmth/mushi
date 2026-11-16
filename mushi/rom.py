"""Revision-locked ROM loading. No game data is distributed with this project."""
from dataclasses import dataclass, asdict
from hashlib import sha1, sha256
from pathlib import Path
from zipfile import ZipFile
import zlib


@dataclass(frozen=True)
class RomSpec:
    size: int
    crc32: str
    sha1: str
    role: str


# MAME cv1k.cpp, cd9a88ea5e3bf7d91804b05ee93fa4f67e8ecab3.
SPECS = {
    "futari15_u4": RomSpec(0x200000, "e8c5f128", "45fb8066fdbecb83fdc2e14555c460d0c652cd5f", "SH-3 program"),
    "futari15_u2": RomSpec(0x8400000, "b9eae1fc", "410f8e7cfcbfd271b41fb4f8d049a13a3191a1f9", "NAND graphics/resources"),
    "u23": RomSpec(0x400000, "39f1e1f4", "53d12f59a56df35c705408c76e6e02118da656f1", "YMZ770 sound bank 0"),
    "u24": RomSpec(0x400000, "c631a766", "8bb6934a2f5b8a9841c3dcf85192b1743773dd8b", "YMZ770 sound bank 1"),
}


def load_roms(path: Path) -> tuple[dict[str, bytes], dict]:
    result, entries = {}, []
    with ZipFile(path) as archive:
        names = archive.namelist()
        for name, spec in SPECS.items():
            if names.count(name) != 1:
                raise ValueError(f"Expected exactly one archive member named {name}")
            if archive.getinfo(name).file_size != spec.size:
                raise ValueError(f"{name}: wrong size for supported Futari 1.5 revision")
            data = archive.read(name)
            crc, digest = f"{zlib.crc32(data):08x}", sha1(data).hexdigest()
            if crc != spec.crc32 or digest != spec.sha1:
                raise ValueError(f"{name}: unsupported revision or corrupt data ({crc}, {digest})")
            result[name] = data
            entries.append(dict(name=name, **asdict(spec), sha256=sha256(data).hexdigest(), verified=True))
    return result, dict(set="futari15", revision="2006/12/8 MAST VER. 1.54", entries=entries)


def swap_words(data: bytes) -> bytes:
    if len(data) % 2:
        raise ValueError("Word-swapped data must contain an even number of bytes")
    out = bytearray(len(data))
    out[::2], out[1::2] = data[1::2], data[::2]
    return bytes(out)
