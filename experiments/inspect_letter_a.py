#!/usr/bin/env python3
"""Find the actual A character boundaries in the Gothic image."""
from PIL import Image
import numpy as np

INPUT = "/tmp/claude-1000/-tmp-gh-issue-solver-1770414816582/c8973e13-2f20-4f66-98bb-680b0c0e8078/scratchpad/gothic_font_image.png"
img = Image.open(INPUT).convert('L')
gray = np.array(img)

# The A is the leftmost character. Look at wider area
print("=== A area: x=45-115, y=120-245, checking all pixels ===")
print("\nVertical projection (all columns):")
for x in range(45, 115, 1):
    dark_count = np.sum(gray[120:245, x] < 140)
    if dark_count > 0:
        bar = '#' * dark_count
        print(f"  x={x:3d}: {dark_count:3d} {bar}")

print("\nHorizontal projection (all rows):")
for y in range(120, 245, 1):
    dark_count = np.sum(gray[y, 45:115] < 140)
    if dark_count > 0:
        bar = '#' * dark_count
        print(f"  y={y:3d}: {dark_count:3d} {bar}")

# Let's look at A more broadly - maybe it extends further left
print("\n=== A extended: x=40-120, y=120-250 ===")
print("\nVertical projection:")
for x in range(40, 120, 1):
    dark_count = np.sum(gray[120:250, x] < 140)
    if dark_count > 0:
        bar = '#' * dark_count
        print(f"  x={x:3d}: {dark_count:3d} {bar}")
