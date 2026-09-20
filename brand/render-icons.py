#!/usr/bin/env python3
# Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
"""Renders OpenMila's raster artwork from the SVG sources beside this script.

    python3 brand/render-icons.py              # writes brand/icons/ and brand/social-preview.png
    python3 brand/render-icons.py --out DIR    # writes somewhere else

Standard library only (zlib, struct, xml.etree): the CI image has python3 and
the usual build tools, and no imaging package.

The SVG subset understood here is the one brand/mark.svg and brand/logo.svg are
written in: <rect> with rx, <circle> either filled or stroked (with an optional
dash pattern), <line>, <g transform="translate(..) scale(..)">, and a two-stop
vertical <linearGradient> in userSpaceOnUse coordinates. Shapes are opaque, so
a pixel is the topmost shape covering it and antialiasing comes from
supersampling. That is all the artwork needs; anything richer belongs in a real
renderer, not here.
"""

from __future__ import annotations

import argparse
import math
import os
import struct
import sys
import xml.etree.ElementTree as ET
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
SVG_NS = "{http://www.w3.org/2000/svg}"

ICON_SIZES = (16, 24, 32, 48, 64, 128, 256, 512)
ICO_SIZES = (16, 32, 48, 256)
FAVICON_SIZES = (16, 32, 48)
SOCIAL_SIZE = (1280, 640)
# At and below this size the simplified cut in brand/mark-small.svg is used.
SMALL_CUT_MAX = 16

# Social preview background and text colours (brand.md keeps the full table).
SOCIAL_TOP = (10, 23, 41)
SOCIAL_BOTTOM = (6, 12, 22)
SOCIAL_TEXT = (255, 255, 255)
SOCIAL_SUBTEXT = (147, 164, 188)
SOCIAL_LINE = "LOCAL TRANSCRIPTION FOR LINUX AND WINDOWS"


# --------------------------------------------------------------------------
# Paint
# --------------------------------------------------------------------------

class Solid:
    __slots__ = ("rgb",)

    def __init__(self, rgb):
        self.rgb = rgb

    def at(self, x, y):
        return self.rgb

    def transformed(self, tx, ty, s):
        return self

    def recoloured(self, rgb):
        return Solid(rgb)


class Gradient:
    """Two-stop linear gradient between two points in user space."""

    __slots__ = ("x1", "y1", "x2", "y2", "c1", "c2", "_len2")

    def __init__(self, x1, y1, x2, y2, c1, c2):
        self.x1, self.y1, self.x2, self.y2 = x1, y1, x2, y2
        self.c1, self.c2 = c1, c2
        self._len2 = (x2 - x1) ** 2 + (y2 - y1) ** 2 or 1.0

    def at(self, x, y):
        t = ((x - self.x1) * (self.x2 - self.x1) + (y - self.y1) * (self.y2 - self.y1)) / self._len2
        if t <= 0.0:
            return self.c1
        if t >= 1.0:
            return self.c2
        a, b = self.c1, self.c2
        return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t)

    def transformed(self, tx, ty, s):
        return Gradient(self.x1 * s + tx, self.y1 * s + ty,
                        self.x2 * s + tx, self.y2 * s + ty, self.c1, self.c2)

    def recoloured(self, rgb):
        return Solid(rgb)


# --------------------------------------------------------------------------
# Shapes. Every shape answers "is this point inside?" and "what colour here?".
# --------------------------------------------------------------------------

class Shape:
    """Shared behaviour. `covers_box` is an optimisation: a convex shape that
    covers all four corners of a pixel covers the whole pixel, so that pixel
    needs no supersampling. Non-convex shapes say no and get sampled."""

    def covers_box(self, x0, y0, x1, y1):
        return False


class RoundRect(Shape):
    __slots__ = ("x", "y", "w", "h", "r", "paint", "x0", "y0", "x1", "y1")

    def __init__(self, x, y, w, h, r, paint):
        self.x, self.y, self.w, self.h, self.r, self.paint = x, y, w, h, r, paint
        self.x0, self.y0, self.x1, self.y1 = x, y, x + w, y + h

    def covers(self, px, py):
        if px < self.x0 or px > self.x1 or py < self.y0 or py > self.y1:
            return False
        r = self.r
        if r <= 0:
            return True
        cx = min(max(px, self.x0 + r), self.x1 - r)
        cy = min(max(py, self.y0 + r), self.y1 - r)
        return (px - cx) ** 2 + (py - cy) ** 2 <= r * r

    def covers_box(self, x0, y0, x1, y1):
        return (self.covers(x0, y0) and self.covers(x1, y0)
                and self.covers(x0, y1) and self.covers(x1, y1))

    def transformed(self, tx, ty, s):
        return RoundRect(self.x * s + tx, self.y * s + ty, self.w * s, self.h * s,
                         self.r * s, self.paint.transformed(tx, ty, s))

    def recoloured(self, rgb):
        return RoundRect(self.x, self.y, self.w, self.h, self.r, self.paint.recoloured(rgb))


class Disc(Shape):
    __slots__ = ("cx", "cy", "r", "paint", "x0", "y0", "x1", "y1", "_r2")

    def __init__(self, cx, cy, r, paint):
        self.cx, self.cy, self.r, self.paint = cx, cy, r, paint
        self._r2 = r * r
        self.x0, self.y0, self.x1, self.y1 = cx - r, cy - r, cx + r, cy + r

    def covers(self, px, py):
        return (px - self.cx) ** 2 + (py - self.cy) ** 2 <= self._r2

    def covers_box(self, x0, y0, x1, y1):
        return (self.covers(x0, y0) and self.covers(x1, y0)
                and self.covers(x0, y1) and self.covers(x1, y1))

    def transformed(self, tx, ty, s):
        return Disc(self.cx * s + tx, self.cy * s + ty, self.r * s, self.paint.transformed(tx, ty, s))

    def recoloured(self, rgb):
        return Disc(self.cx, self.cy, self.r, self.paint.recoloured(rgb))


class Arc(Shape):
    """A stroked circle, or a run of arcs of one when a dash pattern is set.

    `spans` are (start, end) angles in radians, measured the way SVG walks a
    circle: from three o'clock, increasing clockwise on screen. Ends are
    rounded, which is what every stroke in the artwork uses.
    """

    __slots__ = ("cx", "cy", "r", "w", "spans", "paint", "caps", "x0", "y0", "x1", "y1", "_in2", "_out2", "_c2")

    def __init__(self, cx, cy, r, w, spans, paint):
        self.cx, self.cy, self.r, self.w, self.paint = cx, cy, r, w, paint
        self.spans = spans
        half = w / 2.0
        self._in2 = max(r - half, 0.0) ** 2
        self._out2 = (r + half) ** 2
        self._c2 = half * half
        self.caps = []
        if spans is not None:
            for a0, a1 in spans:
                for a in (a0, a1):
                    self.caps.append((cx + r * math.cos(a), cy + r * math.sin(a)))
        reach = r + half
        self.x0, self.y0, self.x1, self.y1 = cx - reach, cy - reach, cx + reach, cy + reach

    def covers(self, px, py):
        dx, dy = px - self.cx, py - self.cy
        d2 = dx * dx + dy * dy
        if self._in2 <= d2 <= self._out2:
            if self.spans is None:
                return True
            a = math.atan2(dy, dx)
            if a < 0.0:
                a += 2.0 * math.pi
            for a0, a1 in self.spans:
                if a0 <= a <= a1:
                    return True
                # A span that wrapped past 2pi is stored unwrapped.
                if a1 > 2.0 * math.pi and a + 2.0 * math.pi <= a1 and a + 2.0 * math.pi >= a0:
                    return True
        for capx, capy in self.caps:
            if (px - capx) ** 2 + (py - capy) ** 2 <= self._c2:
                return True
        return False

    def transformed(self, tx, ty, s):
        return Arc(self.cx * s + tx, self.cy * s + ty, self.r * s, self.w * s,
                   self.spans, self.paint.transformed(tx, ty, s))

    def recoloured(self, rgb):
        return Arc(self.cx, self.cy, self.r, self.w, self.spans, self.paint.recoloured(rgb))


class Segment(Shape):
    """A straight stroke with round ends."""

    __slots__ = ("ax", "ay", "bx", "by", "w", "paint", "x0", "y0", "x1", "y1", "_dx", "_dy", "_len2", "_h2")

    def __init__(self, ax, ay, bx, by, w, paint):
        self.ax, self.ay, self.bx, self.by, self.w, self.paint = ax, ay, bx, by, w, paint
        self._dx, self._dy = bx - ax, by - ay
        self._len2 = self._dx ** 2 + self._dy ** 2 or 1e-9
        half = w / 2.0
        self._h2 = half * half
        self.x0, self.y0 = min(ax, bx) - half, min(ay, by) - half
        self.x1, self.y1 = max(ax, bx) + half, max(ay, by) + half

    def covers(self, px, py):
        t = ((px - self.ax) * self._dx + (py - self.ay) * self._dy) / self._len2
        if t < 0.0:
            t = 0.0
        elif t > 1.0:
            t = 1.0
        qx, qy = self.ax + self._dx * t, self.ay + self._dy * t
        return (px - qx) ** 2 + (py - qy) ** 2 <= self._h2

    def transformed(self, tx, ty, s):
        return Segment(self.ax * s + tx, self.ay * s + ty, self.bx * s + tx, self.by * s + ty,
                       self.w * s, self.paint.transformed(tx, ty, s))

    def recoloured(self, rgb):
        return Segment(self.ax, self.ay, self.bx, self.by, self.w, self.paint.recoloured(rgb))


def transformed(shapes, tx, ty, scale):
    return [s.transformed(tx, ty, scale) for s in shapes]


def recoloured(shapes, rgb):
    return [s.recoloured(rgb) for s in shapes]


# --------------------------------------------------------------------------
# The SVG subset
# --------------------------------------------------------------------------

def parse_colour(text):
    text = text.strip()
    if text.startswith("#"):
        text = text[1:]
        if len(text) == 3:
            text = "".join(c * 2 for c in text)
        return (int(text[0:2], 16), int(text[2:4], 16), int(text[4:6], 16))
    if text in ("white", "currentColor"):
        return (255, 255, 255)
    if text == "black":
        return (0, 0, 0)
    raise ValueError("unsupported colour: %r" % text)


def parse_transform(text):
    """translate(x[,y]) and scale(s), applied left to right. Returns (tx, ty, s)."""
    tx, ty, scale = 0.0, 0.0, 1.0
    for name, args in _transform_ops(text):
        values = [float(v) for v in args.replace(",", " ").split()]
        if name == "translate":
            dx = values[0]
            dy = values[1] if len(values) > 1 else 0.0
            tx += dx * scale
            ty += dy * scale
        elif name == "scale":
            if len(values) > 1 and values[0] != values[1]:
                raise ValueError("only uniform scale is supported")
            scale *= values[0]
        else:
            raise ValueError("unsupported transform: %s" % name)
    return tx, ty, scale


def _transform_ops(text):
    ops = []
    for part in text.split(")"):
        part = part.strip()
        if not part:
            continue
        name, _, args = part.partition("(")
        ops.append((name.strip(), args))
    return ops


def _dash_spans(circumference, dasharray, dashoffset):
    """Turn an SVG dash pattern on a circle into (start, end) angle spans."""
    if not dasharray or dasharray == "none":
        return None
    pattern = [float(v) for v in dasharray.replace(",", " ").split()]
    if len(pattern) % 2:
        pattern = pattern * 2
    period = sum(pattern)
    if period <= 0:
        return None
    offset = float(dashoffset or 0.0)
    spans = []
    # Walk the pattern from before the start of the path until past its end.
    start = -offset
    while start > -period:
        start -= period
    position = start
    index = 0
    while position < circumference:
        length = pattern[index % len(pattern)]
        if index % 2 == 0 and length > 0:
            a, b = max(position, 0.0), min(position + length, circumference)
            if b > a:
                spans.append((a, b))
        position += length
        index += 1
    k = 2.0 * math.pi / circumference
    return [(a * k, b * k) for a, b in spans]


def _style(element, inherited):
    style = dict(inherited)
    for key in ("fill", "stroke", "stroke-width", "stroke-linecap",
                "stroke-dasharray", "stroke-dashoffset"):
        value = element.get(key)
        if value is not None:
            style[key] = value
    return style


def _paint(value, gradients, tx, ty, scale):
    if value is None or value == "none":
        return None
    if value.startswith("url(#"):
        gradient = gradients[value[5:].rstrip(")")]
        return gradient.transformed(tx, ty, scale)
    return Solid(parse_colour(value))


def parse_svg(path, group_id=None):
    """Returns the shapes of a file (or of one group in it), in user units."""
    root = ET.parse(path).getroot()
    gradients = {}
    for gradient in root.iter(SVG_NS + "linearGradient"):
        stops = [s for s in gradient if s.tag == SVG_NS + "stop"]
        if len(stops) != 2:
            raise ValueError("only two-stop gradients are supported")
        gradients[gradient.get("id")] = Gradient(
            float(gradient.get("x1", 0)), float(gradient.get("y1", 0)),
            float(gradient.get("x2", 0)), float(gradient.get("y2", 0)),
            parse_colour(stops[0].get("stop-color")), parse_colour(stops[1].get("stop-color")))

    shapes = []

    def walk(node, tx, ty, scale, style, emit):
        for child in node:
            tag = child.tag
            if tag == SVG_NS + "defs":
                continue
            ctx = _style(child, style)
            ntx, nty, nscale = tx, ty, scale
            if child.get("transform"):
                dx, dy, ds = parse_transform(child.get("transform"))
                ntx, nty, nscale = tx + dx * scale, ty + dy * scale, scale * ds
            if tag == SVG_NS + "g":
                walk(child, ntx, nty, nscale, ctx,
                     emit or group_id is None or child.get("id") == group_id)
                continue
            if not emit and group_id is not None:
                continue
            _emit(child, tag, ntx, nty, nscale, ctx)

    def _emit(child, tag, tx, ty, scale, ctx):
        def place(x, y):
            return x * scale + tx, y * scale + ty

        fill = _paint(ctx.get("fill"), gradients, tx, ty, scale)
        stroke = _paint(ctx.get("stroke"), gradients, tx, ty, scale)
        width = float(ctx.get("stroke-width", 1)) * scale
        if tag == SVG_NS + "rect":
            if fill is None:
                return
            x, y = place(float(child.get("x", 0)), float(child.get("y", 0)))
            shapes.append(RoundRect(x, y, float(child.get("width")) * scale,
                                    float(child.get("height")) * scale,
                                    float(child.get("rx", 0)) * scale, fill))
        elif tag == SVG_NS + "circle":
            cx, cy = place(float(child.get("cx")), float(child.get("cy")))
            radius = float(child.get("r"))
            r = radius * scale
            if fill is not None:
                shapes.append(Disc(cx, cy, r, fill))
            if stroke is not None and width > 0:
                # Dash lengths are in the element's own units, and the spans
                # they produce are angles, so this is computed before scaling.
                spans = _dash_spans(2.0 * math.pi * radius,
                                    ctx.get("stroke-dasharray"),
                                    float(ctx.get("stroke-dashoffset", 0)))
                shapes.append(Arc(cx, cy, r, width, spans, stroke))
        elif tag == SVG_NS + "line":
            if stroke is None or width <= 0:
                return
            ax, ay = place(float(child.get("x1")), float(child.get("y1")))
            bx, by = place(float(child.get("x2")), float(child.get("y2")))
            shapes.append(Segment(ax, ay, bx, by, width, stroke))

    walk(root, 0.0, 0.0, 1.0, {}, group_id is None)
    if not shapes:
        raise ValueError("nothing to draw in %s" % path)
    return shapes


def viewbox(path):
    root = ET.parse(path).getroot()
    return [float(v) for v in root.get("viewBox").replace(",", " ").split()]


# --------------------------------------------------------------------------
# Rasteriser
# --------------------------------------------------------------------------

def rasterise(shapes, width, height, samples=4, origin=(0.0, 0.0), unit=1.0):
    """Renders `shapes` (user units) into straight-alpha RGBA rows.

    `origin` is the user-space point at device (0, 0) and `unit` the size of
    one device pixel in user units.
    """
    rows = []
    step = unit / samples
    first = step / 2.0
    total = samples * samples
    ox, oy = origin
    for j in range(height):
        top = oy + j * unit
        band = [s for s in shapes if s.y0 <= top + unit and s.y1 >= top]
        band.reverse()  # topmost first
        row = bytearray()
        if not band:
            row += bytes(4 * width)
            rows.append(bytes(row))
            continue
        ys = [top + first + k * step for k in range(samples)]
        for i in range(width):
            left = ox + i * unit
            candidates = [s for s in band if s.x0 <= left + unit and s.x1 >= left]
            if not candidates:
                row += b"\x00\x00\x00\x00"
                continue
            if candidates[0].covers_box(left, top, left + unit, top + unit):
                colour = candidates[0].paint.at(left + unit / 2.0, top + unit / 2.0)
                row += bytes((int(colour[0] + 0.5), int(colour[1] + 0.5), int(colour[2] + 0.5), 255))
                continue
            r = g = b = 0.0
            hits = 0
            xs = [left + first + k * step for k in range(samples)]
            for py in ys:
                for px in xs:
                    for shape in candidates:
                        if shape.covers(px, py):
                            colour = shape.paint.at(px, py)
                            r += colour[0]
                            g += colour[1]
                            b += colour[2]
                            hits += 1
                            break
            if hits == 0:
                row += b"\x00\x00\x00\x00"
            else:
                row += bytes((int(r / hits + 0.5), int(g / hits + 0.5), int(b / hits + 0.5),
                              int(255.0 * hits / total + 0.5)))
        rows.append(bytes(row))
    return rows


def render_svg(path, size, samples=4, group_id=None):
    shapes = parse_svg(path, group_id)
    vb = viewbox(path)
    return rasterise(shapes, size, size, samples, origin=(vb[0], vb[1]), unit=vb[2] / size)


# --------------------------------------------------------------------------
# PNG and ICO
# --------------------------------------------------------------------------

def png_bytes(rows, width, height):
    raw = b"".join(b"\x00" + row for row in rows)

    def chunk(kind, data):
        return (struct.pack(">I", len(data)) + kind + data
                + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF))

    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9))
            + chunk(b"IEND", b""))


def write_png(path, rows, width, height):
    with open(path, "wb") as handle:
        handle.write(png_bytes(rows, width, height))
    return path


def _dib_bytes(rows, size):
    """A 32-bit BGRA DIB with an empty AND mask: the icon format Windows
    expects for the small sizes."""
    header = struct.pack("<IiiHHIIiiII", 40, size, size * 2, 1, 32, 0, size * size * 4, 0, 0, 0, 0)
    pixels = bytearray()
    for row in reversed(rows):
        for i in range(0, len(row), 4):
            r, g, b, a = row[i], row[i + 1], row[i + 2], row[i + 3]
            pixels += bytes((b, g, r, a))
    mask_stride = ((size + 31) // 32) * 4
    return header + bytes(pixels) + bytes(mask_stride * size)


def write_ico(path, images):
    """`images` is a list of (size, rows). Sizes up to 48 go in as DIBs, which
    every Windows version reads; 256 goes in as PNG, which is how large icons
    have been stored since Vista."""
    entries, blobs = [], []
    offset = 6 + 16 * len(images)
    for size, rows in images:
        blob = png_bytes(rows, size, size) if size >= 256 else _dib_bytes(rows, size)
        entries.append(struct.pack("<BBBBHHII", 0 if size >= 256 else size,
                                   0 if size >= 256 else size, 0, 0, 1, 32, len(blob), offset))
        offset += len(blob)
        blobs.append(blob)
    with open(path, "wb") as handle:
        handle.write(struct.pack("<HHH", 0, 1, len(images)))
        for entry in entries:
            handle.write(entry)
        for blob in blobs:
            handle.write(blob)
    return path


# --------------------------------------------------------------------------
# A monoline capitals alphabet, for the one line on the social preview.
# Glyphs live in a box one unit tall: y=0 is the cap line, y=1 the baseline.
# 'l' is a polyline, 'a' an arc (centre, radius, start and end angle in
# degrees, measured from three o'clock and increasing clockwise).
# --------------------------------------------------------------------------

CAPS = {
    " ": (0.34, []),
    "-": (0.30, [("l", [(0.0, 0.55), (0.30, 0.55)])]),
    ".": (0.16, [("l", [(0.06, 1.0), (0.06, 1.0)])]),
    "A": (0.64, [("l", [(0.0, 1.0), (0.32, 0.0), (0.64, 1.0)]), ("l", [(0.10, 0.70), (0.54, 0.70)])]),
    "B": (0.52, [("l", [(0.0, 0.0), (0.0, 1.0)]), ("a", 0.25, 0.25, 0.25, -90, 90), ("a", 0.25, 0.75, 0.25, -90, 90)]),
    "C": (1.00, [("a", 0.5, 0.5, 0.5, 55, 305)]),
    "D": (0.68, [("l", [(0.0, 0.0), (0.0, 1.0)]), ("a", 0.18, 0.5, 0.5, -90, 90)]),
    "E": (0.52, [("l", [(0.0, 0.0), (0.0, 1.0)]), ("l", [(0.0, 0.0), (0.50, 0.0)]),
                 ("l", [(0.0, 0.5), (0.42, 0.5)]), ("l", [(0.0, 1.0), (0.50, 1.0)])]),
    "F": (0.52, [("l", [(0.0, 0.0), (0.0, 1.0)]), ("l", [(0.0, 0.0), (0.50, 0.0)]),
                 ("l", [(0.0, 0.5), (0.42, 0.5)])]),
    "G": (1.00, [("a", 0.5, 0.5, 0.5, 0, 305), ("l", [(0.62, 0.5), (1.00, 0.5)])]),
    "H": (0.56, [("l", [(0.0, 0.0), (0.0, 1.0)]), ("l", [(0.56, 0.0), (0.56, 1.0)]),
                 ("l", [(0.0, 0.5), (0.56, 0.5)])]),
    "I": (0.04, [("l", [(0.02, 0.0), (0.02, 1.0)])]),
    "J": (0.54, [("l", [(0.50, 0.0), (0.50, 0.75)]), ("a", 0.25, 0.75, 0.25, 0, 180)]),
    "K": (0.56, [("l", [(0.0, 0.0), (0.0, 1.0)]), ("l", [(0.52, 0.0), (0.02, 0.55)]),
                 ("l", [(0.16, 0.42), (0.54, 1.0)])]),
    "L": (0.48, [("l", [(0.0, 0.0), (0.0, 1.0), (0.46, 1.0)])]),
    "M": (0.68, [("l", [(0.0, 1.0), (0.0, 0.0), (0.34, 0.72), (0.68, 0.0), (0.68, 1.0)])]),
    "N": (0.56, [("l", [(0.0, 1.0), (0.0, 0.0), (0.56, 1.0), (0.56, 0.0)])]),
    "O": (1.00, [("a", 0.5, 0.5, 0.5, 0, 360)]),
    "P": (0.50, [("l", [(0.0, 0.0), (0.0, 1.0)]), ("a", 0.20, 0.27, 0.27, -90, 90)]),
    "Q": (1.04, [("a", 0.5, 0.5, 0.5, 0, 360), ("l", [(0.64, 0.70), (1.00, 1.04)])]),
    "R": (0.56, [("l", [(0.0, 0.0), (0.0, 1.0)]), ("a", 0.20, 0.27, 0.27, -90, 90),
                 ("l", [(0.20, 0.54), (0.54, 1.0)])]),
    "S": (0.58, [("a", 0.29, 0.25, 0.25, 90, 350), ("a", 0.29, 0.75, 0.25, 270, 530)]),
    "T": (0.56, [("l", [(0.0, 0.0), (0.56, 0.0)]), ("l", [(0.28, 0.0), (0.28, 1.0)])]),
    "U": (0.56, [("l", [(0.0, 0.0), (0.0, 0.72)]), ("a", 0.28, 0.72, 0.28, 0, 180),
                 ("l", [(0.56, 0.0), (0.56, 0.72)])]),
    "V": (0.60, [("l", [(0.0, 0.0), (0.30, 1.0), (0.60, 0.0)])]),
    "W": (0.84, [("l", [(0.0, 0.0), (0.18, 1.0), (0.42, 0.24), (0.66, 1.0), (0.84, 0.0)])]),
    "X": (0.56, [("l", [(0.0, 0.0), (0.56, 1.0)]), ("l", [(0.56, 0.0), (0.0, 1.0)])]),
    "Y": (0.56, [("l", [(0.0, 0.0), (0.28, 0.52), (0.56, 0.0)]), ("l", [(0.28, 0.52), (0.28, 1.0)])]),
    "Z": (0.56, [("l", [(0.0, 0.0), (0.54, 0.0), (0.0, 1.0), (0.54, 1.0)])]),
}


def text_shapes(text, x, baseline, cap_height, stroke, tracking, colour):
    """Draws `text` in the monoline capitals above. Returns shapes and the width."""
    paint = Solid(colour)
    shapes = []
    pen = x
    for character in text.upper():
        advance, elements = CAPS[character]
        for element in elements:
            if element[0] == "l":
                points = element[1]
                for index in range(len(points) - 1):
                    ax, ay = points[index]
                    bx, by = points[index + 1]
                    shapes.append(Segment(pen + ax * cap_height, baseline - cap_height + ay * cap_height,
                                          pen + bx * cap_height, baseline - cap_height + by * cap_height,
                                          stroke, paint))
            else:
                _, cx, cy, r, a0, a1 = element
                spans = [(math.radians(a0 % 360.0), math.radians(a0 % 360.0) + math.radians(a1 - a0))]
                shapes.append(Arc(pen + cx * cap_height, baseline - cap_height + cy * cap_height,
                                  r * cap_height, stroke, spans, paint))
        pen += advance * cap_height + tracking
    return shapes, pen - tracking - x


# --------------------------------------------------------------------------
# The social preview
# --------------------------------------------------------------------------

def social_preview(brand_dir, samples=3):
    width, height = SOCIAL_SIZE
    background = RoundRect(0, 0, width, height, 0,
                           Gradient(0, 0, 0, height, SOCIAL_TOP, SOCIAL_BOTTOM))

    mark_size = 200.0
    mark = transformed(parse_svg(os.path.join(brand_dir, "mark.svg")), 0, 0, mark_size / 256.0)
    wordmark_scale = 0.9
    wordmark = recoloured(parse_svg(os.path.join(brand_dir, "logo.svg"), group_id="wordmark"),
                          SOCIAL_TEXT)
    # The wordmark group in logo.svg is already offset; normalise it back to 0.
    wordmark = transformed(wordmark, -184.0 * wordmark_scale, 0.0, wordmark_scale)
    wordmark_width = 568.0 * wordmark_scale

    gap = 44.0
    lockup_width = mark_size + gap + wordmark_width
    left = (width - lockup_width) / 2.0
    centre = 290.0
    mark = transformed(mark, left, centre - mark_size / 2.0, 1.0)
    # The wordmark's optical centre sits at y=100 in its own coordinates.
    wordmark = transformed(wordmark, left + mark_size + gap, centre - 100.0 * wordmark_scale, 1.0)

    cap = 26.0
    tracking = 8.0
    stroke = 4.0
    _, line_width = text_shapes(SOCIAL_LINE, 0, 0, cap, stroke, tracking, SOCIAL_SUBTEXT)
    line, _ = text_shapes(SOCIAL_LINE, (width - line_width) / 2.0, 470.0, cap, stroke, tracking,
                          SOCIAL_SUBTEXT)

    shapes = [background] + mark + wordmark + line
    rows = rasterise(shapes, width, height, samples)
    return rows, width, height


# --------------------------------------------------------------------------

def main(argv=None):
    parser = argparse.ArgumentParser(description="Render OpenMila's raster brand artwork.")
    parser.add_argument("--out", default=HERE, help="output directory (default: brand/)")
    parser.add_argument("--samples", type=int, default=4,
                        help="supersampling per axis for the icons (default: 4)")
    arguments = parser.parse_args(argv)

    out = os.path.abspath(arguments.out)
    icons = os.path.join(out, "icons")
    os.makedirs(icons, exist_ok=True)
    mark = os.path.join(HERE, "mark.svg")
    small = os.path.join(HERE, "mark-small.svg")

    written = []
    rendered = {}
    for size in ICON_SIZES:
        samples = arguments.samples if size <= 256 else max(2, arguments.samples - 1)
        rows = render_svg(small if size <= SMALL_CUT_MAX else mark, size, samples)
        rendered[size] = rows
        written.append(write_png(os.path.join(icons, "openmila-%d.png" % size), rows, size, size))

    written.append(write_ico(os.path.join(icons, "openmila.ico"),
                             [(size, rendered[size]) for size in ICO_SIZES]))
    written.append(write_ico(os.path.join(icons, "favicon.ico"),
                             [(size, rendered[size]) for size in FAVICON_SIZES]))

    rows, width, height = social_preview(HERE)
    written.append(write_png(os.path.join(out, "social-preview.png"), rows, width, height))

    for path in written:
        print("%9d  %s" % (os.path.getsize(path), os.path.relpath(path, os.path.dirname(out))))
    print("openmila-512.png is also the website's 512px PNG; favicon.ico is its favicon.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
