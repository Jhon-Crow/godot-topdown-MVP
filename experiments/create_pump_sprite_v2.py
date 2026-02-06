#!/usr/bin/env python3
"""
Create a new shotgun pump sprite for Issue #447 / PR #480.

Requirements from user feedback:
1. Same brown color as the shotgun's wooden element
2. 2x longer than current (current is 6x8, new should be 12x8)

The pump sprite represents the foregrip/pump handle of a pump-action shotgun
in a top-down 2D game.
"""

from PIL import Image
import os

# Output paths
OUTPUT_DIR = "/tmp/gh-issue-solver-1770215589225/assets/sprites/weapons"
OUTPUT_FILE = os.path.join(OUTPUT_DIR, "shotgun_pump.png")
BACKUP_FILE = os.path.join(OUTPUT_DIR, "shotgun_pump_old.png")

# Dimensions: 2x longer than original 6x8
WIDTH = 12  # 2x the original 6
HEIGHT = 8

# Colors extracted from shotgun_topdown.png wooden elements
# The wooden stock has colors ranging from dark brown to medium brown
WOOD_DARK = (89, 54, 24)      # Dark brown edge
WOOD_MAIN = (139, 90, 43)     # Main brown color
WOOD_LIGHT = (165, 115, 55)   # Lighter brown highlight

# Create new image with transparency
img = Image.new('RGBA', (WIDTH, HEIGHT), (0, 0, 0, 0))
pixels = img.load()

# Fill with main wood color, add simple shading
for y in range(HEIGHT):
    for x in range(WIDTH):
        # Top edge (y=0): lighter
        if y == 0:
            color = WOOD_LIGHT + (255,)
        # Bottom edge (y=7): darker
        elif y == HEIGHT - 1:
            color = WOOD_DARK + (255,)
        # Left and right edges: darker
        elif x == 0 or x == WIDTH - 1:
            color = WOOD_DARK + (255,)
        # Main body
        else:
            color = WOOD_MAIN + (255,)

        pixels[x, y] = color

# Add a subtle highlight line near the top
for x in range(1, WIDTH - 1):
    pixels[x, 1] = WOOD_LIGHT + (255,)

# Save the image
os.makedirs(OUTPUT_DIR, exist_ok=True)

# Backup old sprite if it exists
if os.path.exists(OUTPUT_FILE):
    import shutil
    shutil.copy(OUTPUT_FILE, BACKUP_FILE)
    print(f"Backed up old sprite to: {BACKUP_FILE}")

img.save(OUTPUT_FILE)
print(f"Created new pump sprite: {OUTPUT_FILE}")
print(f"Dimensions: {WIDTH}x{HEIGHT} pixels")
print(f"Colors: main={WOOD_MAIN}, light={WOOD_LIGHT}, dark={WOOD_DARK}")

# Also save to experiments folder for reference
experiments_output = "/tmp/gh-issue-solver-1770215589225/experiments/shotgun_pump_v2.png"
img.save(experiments_output)
print(f"Also saved to: {experiments_output}")

# Verify the image
verification = Image.open(OUTPUT_FILE)
print(f"Verification: {verification.size[0]}x{verification.size[1]}, mode={verification.mode}")
