"""
Fix the barrel seam in revolver_topdown.png

The initial 2x barrel extension (commit b7839a54) copied the barrel section
but left a visible vertical seam at column 33 (the outline pixels from the
original barrel end). This script removes that seam by replacing the outline
pixels at column 33 with the correct barrel body colors, making the barrel
appear as one continuous unit.

Usage:
    python3 experiments/fix_barrel_seam_final.py
"""
from PIL import Image

# Load the extended barrel sprite (from commit b7839a54)
img = Image.open('assets/sprites/weapons/revolver_topdown.png')

# Column 33 is the seam - it has outline color (30,30,30) where it should
# have barrel body colors. The barrel body rows are 5-8:
#   Row 5: highlight (70, 70, 75)  = 0x46464b
#   Row 6: body     (50, 50, 55)  = 0x323237
#   Row 7: body     (50, 50, 55)  = 0x323237
#   Row 8: shadow   (35, 35, 40)  = 0x232328
# Rows 4 and 9 are outlines (30,30,30) which are correct as-is.

seam_fixes = {
    5: (0x46, 0x46, 0x4b, 255),  # barrel highlight
    6: (0x32, 0x32, 0x37, 255),  # barrel body
    7: (0x32, 0x32, 0x37, 255),  # barrel body
    8: (0x23, 0x23, 0x28, 255),  # barrel bottom shadow
}

for y, color in seam_fixes.items():
    img.putpixel((33, y), color)

img.save('assets/sprites/weapons/revolver_topdown.png')
print(f"Fixed barrel seam at column 33. Sprite size: {img.size}")
