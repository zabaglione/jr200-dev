#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Encode and inspect deterministic 8-bit RGBA PNG files without dependencies."""
from __future__ import annotations

import binascii
import struct
import zlib


SIGNATURE = b'\x89PNG\r\n\x1a\n'


class PngError(ValueError):
    """Expected deterministic PNG contract failure."""


def chunk(kind: bytes, payload: bytes) -> bytes:
    return (struct.pack('>I', len(payload)) + kind + payload
            + struct.pack('>I', binascii.crc32(kind + payload) & 0xffffffff))


def encode_rgba(width: int, height: int, pixels: bytes) -> bytes:
    if (type(width) is not int or type(height) is not int
            or not 1 <= width <= 4096 or not 1 <= height <= 4096
            or width * height > 16_777_216
            or len(pixels) != width * height * 4):
        raise PngError('Invalid RGBA image dimensions or payload')
    stride = width * 4
    scanlines = b''.join(
        b'\0' + pixels[offset:offset + stride]
        for offset in range(0, len(pixels), stride)
    )
    header = struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0)
    return (SIGNATURE + chunk(b'IHDR', header)
            + chunk(b'IDAT', zlib.compress(scanlines, level=9))
            + chunk(b'IEND', b''))


def decode_rgba(data: bytes) -> tuple[int, int, bytes]:
    if (not isinstance(data, bytes) or len(data) > 20_000_000
            or not data.startswith(SIGNATURE)):
        raise PngError('Invalid PNG signature')
    offset = len(SIGNATURE)
    width = height = None
    compressed = bytearray()
    seen_idat = False
    seen_iend = False
    while offset < len(data):
        if offset + 12 > len(data):
            raise PngError('Truncated PNG chunk')
        size = struct.unpack('>I', data[offset:offset + 4])[0]
        kind = data[offset + 4:offset + 8]
        end = offset + 12 + size
        if end > len(data):
            raise PngError('Truncated PNG payload')
        payload = data[offset + 8:offset + 8 + size]
        actual_crc = struct.unpack('>I', data[offset + 8 + size:end])[0]
        if (binascii.crc32(kind + payload) & 0xffffffff) != actual_crc:
            raise PngError('PNG chunk checksum mismatch')
        if kind == b'IHDR':
            if width is not None or offset != len(SIGNATURE) or size != 13:
                raise PngError('Invalid PNG header placement')
            width, height, depth, color, compression, filtering, interlace = struct.unpack(
                '>IIBBBBB', payload)
            if (not 1 <= width <= 4096 or not 1 <= height <= 4096
                    or width * height > 16_777_216
                    or (depth, color, compression, filtering, interlace)
                    != (8, 6, 0, 0, 0)):
                raise PngError('PNG must be non-interlaced 8-bit RGBA')
        elif kind == b'IDAT':
            if width is None or seen_iend:
                raise PngError('Invalid PNG image data placement')
            seen_idat = True
            compressed.extend(payload)
        elif kind == b'IEND':
            if size != 0 or not seen_idat or seen_iend:
                raise PngError('Invalid PNG end marker')
            seen_iend = True
            offset = end
            break
        else:
            raise PngError(f'Unsupported PNG chunk: {kind!r}')
        offset = end
    if width is None or height is None or not seen_iend or offset != len(data):
        raise PngError('Incomplete PNG file')
    expected_size = height * (1 + width * 4)
    inflater = zlib.decompressobj()
    raw = inflater.decompress(bytes(compressed), expected_size + 1)
    if inflater.unconsumed_tail or len(raw) > expected_size:
        raise PngError('Invalid or oversized PNG image data')
    raw += inflater.flush()
    if (len(raw) != expected_size or not inflater.eof
            or inflater.unused_data or inflater.unconsumed_tail):
        raise PngError('Invalid or oversized PNG image data')
    stride = width * 4
    pixels = bytearray()
    for row in range(height):
        start = row * (stride + 1)
        if raw[start] != 0:
            raise PngError('PNG must use deterministic filter type 0')
        pixels.extend(raw[start + 1:start + 1 + stride])
    return width, height, bytes(pixels)
