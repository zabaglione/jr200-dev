# SPDX-License-Identifier: BSD-3-Clause
import hashlib
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from png_rgba import PngError, chunk, decode_rgba, encode_rgba


class PngRgbaTests(unittest.TestCase):
    def test_deterministic_roundtrip(self):
        pixels = bytes(range(64))
        first = encode_rgba(4, 4, pixels)
        second = encode_rgba(4, 4, pixels)
        self.assertEqual(first, second)
        self.assertEqual(decode_rgba(first), (4, 4, pixels))
        self.assertEqual(
            hashlib.sha256(first).hexdigest(),
            '1f30608ff112a7ff5f07da8f10cd2d158def69d8c839d590d487ca7a9ebf9cce')

    def test_rejects_corrupt_checksum(self):
        value = bytearray(encode_rgba(1, 1, b'\0\0\0\xff'))
        value[-5] ^= 1
        with self.assertRaisesRegex(PngError, 'checksum'):
            decode_rgba(bytes(value))

    def test_rejects_trailing_data(self):
        with self.assertRaisesRegex(PngError, 'Incomplete'):
            decode_rgba(encode_rgba(1, 1, b'\0\0\0\xff') + b'extra')

    def test_rejects_metadata_chunks(self):
        value = encode_rgba(1, 1, b'\0\0\0\xff')
        marker = value.rfind(b'\0\0\0\0IEND')
        value = value[:marker] + chunk(b'tEXt', b'private=value') + value[marker:]
        with self.assertRaisesRegex(PngError, 'Unsupported PNG chunk'):
            decode_rgba(value)


if __name__ == '__main__':
    unittest.main()
