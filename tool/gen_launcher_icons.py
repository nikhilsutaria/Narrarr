#!/usr/bin/env python3
"""Generate Narrarr's launcher icon resources — pure Python stdlib, no PIL.

Produces, from a single brand definition (warm-brown gradient + white "N"
monogram):
  - assets/icon/narrarr_icon.png        1024 master (source art / iOS later)
  - assets/icon/narrarr_foreground.png  1024 transparent foreground
  - android .../mipmap-*/ic_launcher.png            legacy icons (pre-API-26)
  - android .../mipmap-*/ic_launcher_foreground.png  adaptive foreground
  - android .../mipmap-anydpi-v26/ic_launcher.xml    adaptive-icon descriptor
  - android .../drawable/ic_launcher_background.xml  gradient background

flutter_launcher_icons isn't used because its current releases require
`image ^4`, which conflicts with epubx's `image ^3`. Re-run after swapping in
final artwork (adjust GLYPH/colors or replace this renderer):

    python tool/gen_launcher_icons.py
"""
import math
import os
import struct
import zlib

# Brand: warm brown (theme seed #8D6E63), vertical gradient top->bottom.
TOP = (158, 123, 110)   # #9E7B6E
BOT = (111, 87, 78)     # #6F574E
SS = 3                  # supersample factor per axis

ANDROID_RES = "android/app/src/main/res"
# Legacy square launcher icon, per density (px).
LEGACY = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
# Adaptive foreground is a 108dp canvas, per density (px).
FOREGROUND = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}


def glyph_tester(size, frac):
    """Return inside(x, y) for an 'N' of height `frac*size`, centred in `size`."""
    gh = size * frac
    sw = gh * 0.205          # stroke width
    gw = gh * 0.80           # glyph width
    c = size / 2
    x0, xR = c - gw / 2, c + gw / 2
    yT, yB = c - gh / 2, c + gh / 2
    p1 = (x0 + sw / 2, yT)
    p2 = (xR - sw / 2, yB)
    dx, dy = p2[0] - p1[0], p2[1] - p1[1]
    dlen = math.hypot(dx, dy)

    def inside(x, y):
        if yT <= y <= yB:
            if x0 <= x <= x0 + sw or xR - sw <= x <= xR:
                return True
            if abs(dx * (p1[1] - y) - (p1[0] - x) * dy) / dlen <= sw / 2:
                return True
        return False
    return inside


def render(size, foreground_only):
    frac = 0.42 if foreground_only else 0.46
    inside = glyph_tester(size, frac)
    n = SS * SS
    raw = bytearray()
    for oy in range(size):
        raw.append(0)  # PNG scanline filter: none
        t = oy / size
        br = int(TOP[0] + (BOT[0] - TOP[0]) * t)
        bg = int(TOP[1] + (BOT[1] - TOP[1]) * t)
        bb = int(TOP[2] + (BOT[2] - TOP[2]) * t)
        for ox in range(size):
            cov = 0
            for syi in range(SS):
                for sxi in range(SS):
                    if inside(ox + (sxi + 0.5) / SS, oy + (syi + 0.5) / SS):
                        cov += 1
            f = cov / n
            if foreground_only:
                raw += bytes((255, 255, 255, round(255 * f)))
            else:
                raw += bytes((
                    round(255 * f + br * (1 - f)),
                    round(255 * f + bg * (1 - f)),
                    round(255 * f + bb * (1 - f)),
                    255,
                ))
    return bytes(raw), size


def write_png(path, rendered):
    raw, size = rendered

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data +
                struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff))

    ihdr = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)  # 8-bit RGBA
    png = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) +
           chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(png)
    print("wrote", path)


def write_text(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
    print("wrote", path)


def main():
    # Source masters (1024) — kept as the canonical art.
    write_png("assets/icon/narrarr_icon.png", render(1024, False))
    write_png("assets/icon/narrarr_foreground.png", render(1024, True))

    # Android legacy + adaptive foreground, per density.
    for d, px in LEGACY.items():
        write_png(f"{ANDROID_RES}/mipmap-{d}/ic_launcher.png", render(px, False))
    for d, px in FOREGROUND.items():
        write_png(f"{ANDROID_RES}/mipmap-{d}/ic_launcher_foreground.png",
                  render(px, True))

    # Adaptive-icon descriptor (API 26+) + gradient background drawable.
    write_text(f"{ANDROID_RES}/mipmap-anydpi-v26/ic_launcher.xml",
               '<?xml version="1.0" encoding="utf-8"?>\n'
               '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
               '    <background android:drawable="@drawable/ic_launcher_background"/>\n'
               '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
               '</adaptive-icon>\n')
    write_text(f"{ANDROID_RES}/drawable/ic_launcher_background.xml",
               '<?xml version="1.0" encoding="utf-8"?>\n'
               '<shape xmlns:android="http://schemas.android.com/apk/res/android"\n'
               '    android:shape="rectangle">\n'
               '    <gradient\n'
               '        android:angle="270"\n'
               '        android:startColor="#9E7B6E"\n'
               '        android:endColor="#6F574E"/>\n'
               '</shape>\n')
    print("done")


if __name__ == "__main__":
    main()
