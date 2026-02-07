#!/usr/bin/env python3
"""Inspect pixel values at specific coordinates in the Gothic font image."""

from PIL import Image
import numpy as np

INPUT = "/tmp/claude-1000/-tmp-gh-issue-solver-1770414816582/c8973e13-2f20-4f66-98bb-680b0c0e8078/scratchpad/gothic_font_image.png"

img = Image.open(INPUT).convert('L')
gray = np.array(img)

# Check the digit row more carefully
# The numbers row is around y=410-510
print("=== Digit Row Analysis ===")
print(f"\nHorizontal projection for digit area (y=400-520):")
for y in range(400, 520, 5):
    dark_count = np.sum(gray[y, :] < 140)
    bar = '#' * (dark_count // 3)
    print(f"  y={y:3d}: {dark_count:3d} dark pixels {bar}")

print(f"\nVertical projection for 8 area (x=355-425, y=410-510):")
for x in range(355, 425, 5):
    dark_count = np.sum(gray[410:510, x] < 140)
    bar = '#' * (dark_count // 2)
    print(f"  x={x:3d}: {dark_count:3d} dark pixels {bar}")

print(f"\nVertical projection for 9 area (x=395-460, y=410-510):")
for x in range(395, 460, 5):
    dark_count = np.sum(gray[410:510, x] < 140)
    bar = '#' * (dark_count // 2)
    print(f"  x={x:3d}: {dark_count:3d} dark pixels {bar}")

print(f"\nVertical projection for 0 area (x=65-140, y=410-510):")
for x in range(65, 140, 5):
    dark_count = np.sum(gray[410:510, x] < 140)
    bar = '#' * (dark_count // 2)
    print(f"  x={x:3d}: {dark_count:3d} dark pixels {bar}")

print(f"\n=== Letter A Area Analysis ===")
print(f"\nVertical projection for A area (x=45-115, y=120-235):")
for x in range(45, 115, 3):
    dark_count = np.sum(gray[120:235, x] < 140)
    bar = '#' * (dark_count // 2)
    print(f"  x={x:3d}: {dark_count:3d} dark pixels {bar}")

print(f"\nHorizontal projection for A area (x=45-115, y=120-235):")
for y in range(120, 235, 3):
    dark_count = np.sum(gray[y, 45:115] < 140)
    bar = '#' * (dark_count)
    print(f"  y={y:3d}: {dark_count:3d} dark pixels {bar}")

# Check the Z area
print(f"\n=== Z area analysis ===")
print(f"\nHorizontal projection for Z area (x=425-470, y=310-430):")
for y in range(310, 430, 5):
    dark_count = np.sum(gray[y, 425:470] < 140)
    bar = '#' * (dark_count)
    print(f"  y={y:3d}: {dark_count:3d} dark pixels {bar}")
