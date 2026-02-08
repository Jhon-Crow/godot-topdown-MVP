#!/usr/bin/env python3
"""
Fix barrel seam on revolver_topdown.png - Version 3
This script creates a seamless barrel extension with proper dimension handling.
"""

from PIL import Image
import numpy as np

# Load the original revolver (before extension)
original = Image.open('/tmp/original_revolver_topdown.png')
orig_data = np.array(original)

print(f"Original dimensions: {original.size}")
print(f"Original shape: {orig_data.shape}")

# Let me first analyze the original pixel by pixel
print("\nAnalyzing original structure...")

# Create new image with extended width
# Original: 34 pixels wide
# Target: 45 pixels wide (adding 11 pixels)
new_width = 45
new_height = 14
new_img = Image.new('RGBA', (new_width, new_height), (0, 0, 0, 0))
new_data = np.array(new_img)

# Strategy:
# 1. Copy grip+cylinder: x=0 to 15
# 2. Copy barrel start section: x=15 to 20
# 3. Extend barrel middle by repeating pattern: add ~11 pixels
# 4. Copy barrel end section: x=20 to 29
# 5. Copy front sight/tip: x=29 to 34

# Copy the grip and cylinder (0-15)
new_data[:, :15] = orig_data[:, :15]

# Copy the first part of barrel (15-20)
new_data[:, 15:20] = orig_data[:, 15:20]

# For the barrel extension, use a repeating pattern from the middle of the barrel
# Let's use pixels 18-22 as the repeating pattern
barrel_pattern = orig_data[:, 18:22]  # 4 pixels wide pattern
pattern_width = 4

# Insert the extension (11 pixels)
extension_length = 11
current_x = 20
for i in range(extension_length):
    pattern_x = i % pattern_width
    new_data[:, current_x + i] = barrel_pattern[:, pattern_x]

# Now copy the end of the barrel (20-29 in original)
current_x = 20 + extension_length  # = 31
barrel_end_section = orig_data[:, 20:29]  # 9 pixels
new_data[:, current_x:current_x + 9] = barrel_end_section

# Copy the front sight/tip (29-34 in original, 5 pixels)
current_x = current_x + 9  # = 40
tip_section = orig_data[:, 29:34]  # 5 pixels
new_data[:, current_x:current_x + 5] = tip_section

# Convert back to image
result = Image.fromarray(new_data, 'RGBA')

print(f"\nNew dimensions: {result.size}")
print(f"Barrel extended by: {new_width - original.size[0]} pixels")

# Save the result
result.save('/tmp/gh-issue-solver-1770555685141/assets/sprites/weapons/revolver_topdown.png')
print(f"✓ Saved seamless extended barrel")

# Also save a copy for comparison
result.save('/tmp/seamless_revolver_topdown_v3.png')
print("✓ Comparison copy saved to /tmp/seamless_revolver_topdown_v3.png")
