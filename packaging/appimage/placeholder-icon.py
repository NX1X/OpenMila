#!/usr/bin/env python3
# Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
#
# Draws OpenMila's application icon: a rounded blue tile with a white
# microphone. Written with the standard library only, so packaging needs no
# imaging dependency. Replace with commissioned artwork when there is some.
import struct
import sys
import zlib

SIZE = 256
BG_TOP = (26, 115, 232)      # blue, lighter at the top
BG_BOTTOM = (10, 76, 170)
FG = (255, 255, 255)


def rounded(x, y, size, radius):
    """Inside the rounded square?"""
    cx = min(max(x, radius), size - radius)
    cy = min(max(y, radius), size - radius)
    return (x - cx) ** 2 + (y - cy) ** 2 <= radius ** 2


def microphone(x, y, size):
    """A capsule, a cradle arc and a stand, centred in the tile."""
    s = size / 256.0
    cx = size / 2.0
    # Capsule: rounded rectangle from y=64 to y=150, half width 26.
    if abs(x - cx) <= 26 * s and 64 * s <= y <= 150 * s:
        top, bottom = 90 * s, 124 * s
        if top <= y <= bottom:
            return True
        cy = top if y < top else bottom
        return (x - cx) ** 2 + (y - cy) ** 2 <= (26 * s) ** 2
    # Cradle: an arc of an annulus, open at the top.
    d = ((x - cx) ** 2 + (y - 124 * s) ** 2) ** 0.5
    if 56 * s <= d <= 68 * s and y >= 124 * s:
        return True
    # Stand and base.
    if abs(x - cx) <= 7 * s and 192 * s <= y <= 214 * s:
        return True
    if abs(x - cx) <= 38 * s and 214 * s <= y <= 226 * s:
        return True
    return False


def write_png(path, size=SIZE):
    rows = []
    for y in range(size):
        row = bytearray([0])
        t = y / max(size - 1, 1)
        bg = tuple(int(BG_TOP[i] + (BG_BOTTOM[i] - BG_TOP[i]) * t) for i in range(3))
        for x in range(size):
            if not rounded(x, y, size, size * 0.22):
                row += bytes((0, 0, 0, 0))
            elif microphone(x, y, size):
                row += bytes(FG + (255,))
            else:
                row += bytes(bg + (255,))
        rows.append(bytes(row))

    raw = b"".join(rows)

    def chunk(kind, data):
        return (struct.pack(">I", len(data)) + kind + data
                + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF))

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


if __name__ == "__main__":
    write_png(sys.argv[1], int(sys.argv[2]) if len(sys.argv) > 2 else SIZE)
