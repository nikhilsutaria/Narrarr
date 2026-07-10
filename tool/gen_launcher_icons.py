#!/usr/bin/env python3
"""Generate Narrarr's launcher icon resources from the brand artwork —
pure Python stdlib, no PIL.

Source of truth: assets/icon/narrarr_source.png (the bookshelf-"N" logo;
must be an 8-bit RGBA non-interlaced PNG). Produces:
  - assets/icon/narrarr_icon.png        1024 square master (iOS later)
  - assets/icon/narrarr_foreground.png  1024 transparent adaptive foreground
  - android .../mipmap-*/ic_launcher.png            legacy icons (pre-API-26)
  - android .../mipmap-*/ic_launcher_foreground.png  adaptive foreground
  - android .../mipmap-anydpi-v26/ic_launcher.xml    adaptive-icon descriptor
  - android .../drawable/ic_launcher_background.xml  solid background drawable
  - android .../drawable-*dpi/splash_icon.png   Android-12+ splash icon (the
        full logo inset to survive the system's circular mask)
  - android .../drawable-*dpi/splash_logo.png   pre-12 launch-screen logo
  - android .../values/splash_colors.xml        splash background colour

flutter_launcher_icons isn't used because its current releases require
`image ^4`, which conflicts with epubx's `image ^3`. Re-run after swapping in
final artwork (replace assets/icon/narrarr_source.png):

    python tool/gen_launcher_icons.py
"""
import os
import struct
import zlib

SOURCE = "assets/icon/narrarr_source.png"
ANDROID_RES = "android/app/src/main/res"
# Legacy square launcher icon, per density (px).
LEGACY = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
# Adaptive foreground is a 108dp canvas, per density (px).
FOREGROUND = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}
# The artwork spans the adaptive icon's 72dp visible area; the outer 108dp
# bleed is the solid background colour (sampled from the art's corners).
FOREGROUND_SCALE = 72 / 108
# Android 12+ splash icons are masked to a 192dp circle on a 288dp canvas;
# inscribe the square logo in that circle so none of it gets cropped.
SPLASH_ICON_DP = 288
SPLASH_ICON_SCALE = (192 / 288) / 2 ** 0.5
# Pre-12 launch screens have no mask — show the full logo at 200dp.
SPLASH_LOGO_DP = 200
DENSITY = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
SS = 3  # supersample factor per axis when resampling


def read_png(path):
    """Decode an 8-bit RGBA non-interlaced PNG to (bytearray RGBA, w, h)."""
    data = open(path, "rb").read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit(f"{path}: not a PNG")
    pos, idat, w, h = 8, b"", 0, 0
    while pos < len(data):
        ln = struct.unpack(">I", data[pos:pos + 4])[0]
        tag = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + ln]
        if tag == b"IHDR":
            w, h, depth, ctype, _, _, interlace = struct.unpack(">IIBBBBB", body)
            if (depth, ctype, interlace) != (8, 6, 0):
                raise SystemExit(f"{path}: must be 8-bit RGBA, non-interlaced")
        elif tag == b"IDAT":
            idat += body
        pos += 12 + ln
    raw = zlib.decompress(idat)
    stride = w * 4
    px = bytearray(w * h * 4)
    prev = bytearray(stride)
    p = 0
    for y in range(h):
        filt = raw[p]
        p += 1
        line = bytearray(raw[p:p + stride])
        p += stride
        if filt == 1:    # Sub
            for i in range(4, stride):
                line[i] = (line[i] + line[i - 4]) & 255
        elif filt == 2:  # Up
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 255
        elif filt == 3:  # Average
            for i in range(stride):
                a = line[i - 4] if i >= 4 else 0
                line[i] = (line[i] + ((a + prev[i]) >> 1)) & 255
        elif filt == 4:  # Paeth
            for i in range(stride):
                a = line[i - 4] if i >= 4 else 0
                b = prev[i]
                c = prev[i - 4] if i >= 4 else 0
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                pred = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
                line[i] = (line[i] + pred) & 255
        px[y * stride:(y + 1) * stride] = line
        prev = line
    return px, w, h


def crop_square(px, w, h):
    """Centre-crop to the largest square."""
    s = min(w, h)
    x0, y0 = (w - s) // 2, (h - s) // 2
    out = bytearray(s * s * 4)
    for y in range(s):
        src = ((y0 + y) * w + x0) * 4
        out[y * s * 4:(y + 1) * s * 4] = px[src:src + s * 4]
    return out, s


def resample(px, size, dst):
    """Box-filter resample a square RGBA image (premultiplied averaging)."""
    n = SS * SS
    out = bytearray(dst * dst * 4)
    for oy in range(dst):
        for ox in range(dst):
            r = g = b = a = 0
            for syi in range(SS):
                for sxi in range(SS):
                    sx = int((ox + (sxi + 0.5) / SS) * size / dst)
                    sy = int((oy + (syi + 0.5) / SS) * size / dst)
                    i = (sy * size + sx) * 4
                    al = px[i + 3]
                    r += px[i] * al
                    g += px[i + 1] * al
                    b += px[i + 2] * al
                    a += al
            o = (oy * dst + ox) * 4
            if a:
                out[o] = round(r / a)
                out[o + 1] = round(g / a)
                out[o + 2] = round(b / a)
            out[o + 3] = round(a / n)
    return out


def compose_foreground(px, size, canvas, scale=FOREGROUND_SCALE):
    """Centre the art at `scale` of the canvas, transparent elsewhere."""
    inner = round(canvas * scale)
    art = resample(px, size, inner)
    off = (canvas - inner) // 2
    out = bytearray(canvas * canvas * 4)
    for y in range(inner):
        dst = ((off + y) * canvas + off) * 4
        out[dst:dst + inner * 4] = art[y * inner * 4:(y + 1) * inner * 4]
    return out


def corner_colour(px, size):
    """Average RGB of the four corner blocks — the adaptive background."""
    block = max(2, size // 32)
    r = g = b = n = 0
    for cy in (range(block), range(size - block, size)):
        for cx in (range(block), range(size - block, size)):
            for y in cy:
                for x in cx:
                    i = (y * size + x) * 4
                    r += px[i]
                    g += px[i + 1]
                    b += px[i + 2]
                    n += 1
    return "#%02X%02X%02X" % (round(r / n), round(g / n), round(b / n))


def write_png(path, raw, size):
    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data +
                struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff))

    scan = bytearray()
    for y in range(size):
        scan.append(0)  # PNG scanline filter: none
        scan += raw[y * size * 4:(y + 1) * size * 4]
    ihdr = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)  # 8-bit RGBA
    png = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) +
           chunk(b"IDAT", zlib.compress(bytes(scan), 9)) + chunk(b"IEND", b""))
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
    px, w, h = read_png(SOURCE)
    px, size = crop_square(px, w, h)

    # Source masters (1024) — kept as the canonical processed art.
    write_png("assets/icon/narrarr_icon.png", resample(px, size, 1024), 1024)
    write_png("assets/icon/narrarr_foreground.png",
              compose_foreground(px, size, 1024), 1024)

    # Android legacy + adaptive foreground, per density.
    for d, target in LEGACY.items():
        write_png(f"{ANDROID_RES}/mipmap-{d}/ic_launcher.png",
                  resample(px, size, target), target)
    for d, target in FOREGROUND.items():
        write_png(f"{ANDROID_RES}/mipmap-{d}/ic_launcher_foreground.png",
                  compose_foreground(px, size, target), target)

    # Splash-screen assets: Android-12+ masked icon + pre-12 full logo.
    for d, mul in DENSITY.items():
        canvas = round(SPLASH_ICON_DP * mul)
        write_png(f"{ANDROID_RES}/drawable-{d}/splash_icon.png",
                  compose_foreground(px, size, canvas, SPLASH_ICON_SCALE),
                  canvas)
        logo = round(SPLASH_LOGO_DP * mul)
        write_png(f"{ANDROID_RES}/drawable-{d}/splash_logo.png",
                  resample(px, size, logo), logo)
    write_text(f"{ANDROID_RES}/values/splash_colors.xml",
               '<?xml version="1.0" encoding="utf-8"?>\n'
               '<resources>\n'
               f'    <color name="splash_background">{corner_colour(px, size)}</color>\n'
               '</resources>\n')

    # Adaptive-icon descriptor (API 26+) + solid background drawable.
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
               f'    <solid android:color="{corner_colour(px, size)}"/>\n'
               '</shape>\n')
    print("done")


if __name__ == "__main__":
    main()
