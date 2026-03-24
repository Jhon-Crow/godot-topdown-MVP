#!/usr/bin/env python3
"""Create a blue backpack PNG sprite for the teleporter enemy (Issue #752).

The backpack is a 16x20 pixel image designed for top-down view:
- Main bag: blue rectangle (8x12) centered
- Straps: two thin vertical strips on the left side
- Top handle: small rectangle at top
Uses blue tones matching the teleporter theme (Color #4A9EFF, #2472CC, #1A5FA0).
"""

import struct
import zlib
import sys

def make_png(width, height, pixels_rgba):
    """Create PNG bytes from RGBA pixel data (list of (R,G,B,A) tuples, row-major)."""
    def chunk(name, data):
        c = name + data
        return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xFFFFFFFF)

    # PNG signature
    sig = b'\x89PNG\r\n\x1a\n'

    # IHDR
    ihdr_data = struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0)  # 8-bit RGB — use 6 for RGBA
    # Actually use color type 6 = RGBA
    ihdr_data = struct.pack('>II', width, height) + bytes([8, 6, 0, 0, 0])
    ihdr = chunk(b'IHDR', ihdr_data)

    # IDAT - build raw image data
    raw = bytearray()
    for y in range(height):
        raw.append(0)  # filter type none
        for x in range(width):
            r, g, b, a = pixels_rgba[y * width + x]
            raw.extend([r, g, b, a])
    idat = chunk(b'IDAT', zlib.compress(bytes(raw), 9))

    # IEND
    iend = chunk(b'IEND', b'')

    return sig + ihdr + idat + iend


# --- Design the backpack (16x20 pixels, RGBA) ---
W, H = 16, 20
TRANSPARENT = (0, 0, 0, 0)

# Color palette
BLUE_MAIN  = (74, 158, 255, 255)   # bright blue body
BLUE_DARK  = (36, 114, 204, 255)   # darker blue for depth/shadow
BLUE_SHADOW= (26, 95, 160, 255)    # darkest for bottom shadow
BLUE_STRAP = (55, 130, 210, 255)   # strap color (slightly lighter)
BLUE_HILIT = (120, 190, 255, 255)  # highlight on top-left

pixels = [TRANSPARENT] * (W * H)

def px(x, y, color):
    if 0 <= x < W and 0 <= y < H:
        pixels[y * W + x] = color

# Main backpack body: columns 4-11, rows 4-17 (8x14)
for y in range(4, 17):
    for x in range(4, 12):
        c = BLUE_MAIN
        if x == 11:  # right edge shadow
            c = BLUE_DARK
        if y == 16:  # bottom shadow
            c = BLUE_SHADOW
        if x == 4 and y == 4:  # top-left highlight
            c = BLUE_HILIT
        px(x, y, c)

# Top flap: columns 4-11, rows 2-4 (slightly narrower top)
for y in range(2, 5):
    for x in range(5, 11):
        c = BLUE_DARK
        if y == 2:
            c = BLUE_HILIT
        px(x, y, c)

# Left strap: column 3, rows 3-15
for y in range(3, 16):
    px(3, y, BLUE_STRAP)

# Right strap: column 12, rows 3-15
for y in range(3, 16):
    px(12, y, BLUE_STRAP)

# Strap buckle at bottom: row 16-17, columns 3 and 12
for x in [3, 4, 11, 12]:
    px(x, 16, BLUE_DARK)
    px(x, 17, BLUE_DARK)

# Top handle: columns 7-8, rows 0-2
for y in range(0, 3):
    px(7, y, BLUE_DARK)
    px(8, y, BLUE_DARK)

# Small pocket detail: columns 6-9, rows 9-12
for y in range(9, 13):
    for x in range(6, 10):
        if x == 6 or x == 9 or y == 9 or y == 12:
            px(x, y, BLUE_SHADOW)

png_data = make_png(W, H, pixels)

out_path = "assets/sprites/characters/enemy/teleporter_backpack.png"
with open(out_path, 'wb') as f:
    f.write(png_data)

print(f"Wrote {len(png_data)} bytes to {out_path}")
print(f"Image: {W}x{H} RGBA")
