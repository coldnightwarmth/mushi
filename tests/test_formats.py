import struct
import unittest
from mushi.compression import decompress
from mushi.graphics import decode_bitmap
from mushi.nand import Nand, Resource, BLOCK_SIZE
from mushi.rom import swap_words
from mushi.blitter import commands


def stream(size, count, flags, tokens):
    return struct.pack(">III", size, count, 12 + len(flags)) + flags + tokens


class CompressionTests(unittest.TestCase):
    def test_overlapping_reference(self):
        # Three literals and a distance-three, length-nine copy.
        data = stream(12, 4, b"\x10", b"ABC" + struct.pack(">H", (3 << 5) | 6))
        result = decompress(data + b"padding")
        self.assertEqual(result.data, b"ABCABCABCABC")
        self.assertEqual(result.consumed, len(data))

    def test_flag_byte_boundary(self):
        self.assertEqual(decompress(stream(9, 9, b"\0\0", b"123456789")).data, b"123456789")

    def test_rejects_malformed_streams(self):
        cases = [b"", stream(4,1,b"\x80",b"\0\0"),  # zero distance
                 stream(4,1,b"\x80",b"\0\x20"),    # before start
                 stream(2,2,b"\x40",b"A\0\x20"),  # output overrun
                 stream(2,2,b"\0",b"A"),           # truncated literal
                 stream(2,1,b"\0",b"A"),           # short output
                 struct.pack(">III", 0xffffffff,1,13)+b"\0A",
                 struct.pack(">III",1,1,12)+b"A"]  # flags overlap tokens
        for data in cases:
            with self.subTest(data=data), self.assertRaises(ValueError):
                decompress(data)


class NandTests(unittest.TestCase):
    def test_read_crosses_multiple_bad_blocks(self):
        nand = Nand.__new__(Nand)
        nand.data = b"A" * BLOCK_SIZE + b"!" * BLOCK_SIZE * 2 + b"B" * BLOCK_SIZE + b"C" * BLOCK_SIZE
        nand.bad_blocks = {1, 2}
        resource = Resource(0,0,0,BLOCK_SIZE-2,BLOCK_SIZE+5,0)
        data, spans = nand.read(resource)
        self.assertEqual(data, b"AA" + b"B" * BLOCK_SIZE + b"CCC")
        self.assertEqual([s["block"] for s in spans], [0,3,4])

    def test_out_of_bounds_read(self):
        nand = Nand.__new__(Nand);nand.data = bytes(BLOCK_SIZE);nand.bad_blocks = set()
        with self.assertRaises(ValueError):
            nand.read(Resource(0,0,0,BLOCK_SIZE-1,2,0))


class GraphicsTests(unittest.TestCase):
    def test_channel_order_and_alpha(self):
        header = struct.pack(">8H", 0x14c1,0x4000,0,0,0x7ca9,0x1200,3,0)
        image, info = decode_bitmap(header + struct.pack(">4H", 0xfc00,0x83e0,0x801f,0x7fff) + b"\xff"*4)
        self.assertEqual(list(image.getdata()), [(248,0,0,255),(0,248,0,255),(0,0,248,255),(248,248,248,0)])
        self.assertEqual(info["opaque_pixels"], 3)

    def test_bad_trailer(self):
        with self.assertRaises(ValueError):
            decode_bitmap(bytes(20))

    def test_word_swap(self):
        self.assertEqual(swap_words(b"1234"), b"2143")
        with self.assertRaises(ValueError): swap_words(b"123")


class BlitterTests(unittest.TestCase):
    def test_clip_upload_and_draw_lengths(self):
        clip=struct.pack('>HH',0xc000,1)
        upload=struct.pack('>8H',0x2000,0,0,0,768,0,0,0)+b'\x80\0'
        draw=struct.pack('>10H',0x1100,0,768,0,32,32,0,0,0x80,0x8080)
        stream=clip+upload+draw+b'\xff\xff'
        result=list(commands(stream,0x0c000000))
        self.assertEqual([r['kind'] for r in result],['clip','upload','draw'])
        self.assertEqual(result[-1]['address'],0x0c000000+22)
        self.assertEqual(result[-1]['width'],1)

    def test_unknown_or_truncated_command(self):
        for data in (b'\x30\0',b'\xc0\0',b'\x10\0'):
            with self.subTest(data=data),self.assertRaises(ValueError):list(commands(data,0x0c000000))


if __name__ == "__main__":
    unittest.main()
