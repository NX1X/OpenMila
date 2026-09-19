#!/usr/bin/env python3
# Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
# Writes a 256x256 placeholder icon (flat blue disc with a white bar) without
# any imaging library. Replaced by the real artwork before release.
import struct, sys, zlib

def png(path, size=256):
    cx = cy = size / 2
    rows = []
    for y in range(size):
        row = bytearray([0])
        for x in range(size):
            d = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5
            inside = d <= size * 0.46
            bar = inside and abs(x - cx) < size * 0.07 and abs(y - cy) < size * 0.22
            if bar: row += bytes([255, 255, 255, 255])
            elif inside: row += bytes([0, 122, 255, 255])
            else: row += bytes([0, 0, 0, 0])
        rows.append(bytes(row))
    raw = b"".join(rows)
    def chunk(t, d): return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    data = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
    data += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    open(path, "wb").write(data)

png(sys.argv[1])
