"""Decode bitmap upload payloads without guessing sprite or animation boundaries."""
import struct
import numpy as np
from PIL import Image


def decode_bitmap(data: bytes) -> tuple[Image.Image, dict]:
    if len(data) < 20:
        raise ValueError("Truncated bitmap payload")
    words = struct.unpack_from(">8H", data)
    width, height = (words[6] & 0x1fff) + 1, (words[7] & 0x0fff) + 1
    end = 16 + width * height * 2
    if end + 4 != len(data) or data[end:] != b"\xff\xff\xff\xff":
        raise ValueError(f"Bitmap size/trailer mismatch: {width}x{height}, {len(data)} bytes")
    pixels = np.frombuffer(data, dtype=">u2", offset=16, count=width * height).reshape(height, width)
    rgba = np.empty((height, width, 4), dtype=np.uint8)
    # Matches MAME's CV1000 upload path: 5-bit channels shifted by three.
    # Do not stretch to 255: the hardware reference uses a maximum of 248.
    for channel, shift in enumerate((10, 5, 0)):
        rgba[:, :, channel] = ((pixels >> shift) & 31) << 3
    rgba[:, :, 3] = np.where(pixels & 0x8000, 255, 0)
    image = Image.fromarray(rgba)
    return image, dict(width=width, height=height, header_words=list(words),
                       opaque_pixels=int(np.count_nonzero(pixels & 0x8000)),
                       alpha_bbox=image.getbbox(), pixel_format="ARGB1555 big-endian; RGB5 << 3")
