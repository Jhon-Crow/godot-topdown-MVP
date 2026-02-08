#!/usr/bin/env python3
"""
Fix barrel seam on revolver_topdown.png
This script creates a seamless barrel extension by properly blending the barrel section.
"""

from PIL import Image
import numpy as np

# Load the original revolver (before extension)
original = Image.open('/tmp/original_revolver_topdown.png')
orig_data = np.array(original)

print(f"Original dimensions: {original.size}")

# The original barrel ends around x=22 (approximately)
# The cylinder is roughly at x=10-15
# We need to extend from x=22 to approximately x=33 (doubling the barrel from ~11px to ~22px)

# Create new image with extended width (45x14)
new_width = 45
new_height = 14
new_img = Image.new('RGBA', (new_width, new_height), (0, 0, 0, 0))
new_data = np.array(new_img)

# Copy the grip and cylinder part (first ~15 pixels)
new_data[:, :15] = orig_data[:, :15]

# For the barrel, we need to extend it smoothly
# The barrel section in the original goes from about x=15 to x=22
# We want to extend it to go from x=15 to x=33 (doubling the length)

# Find the barrel pixels in the original
barrel_start_x = 15
barrel_end_x = 22
original_barrel_length = barrel_end_x - barrel_start_x  # ~7 pixels

# Target barrel length (doubled)
new_barrel_length = original_barrel_length * 2  # ~14 pixels
new_barrel_end_x = barrel_start_x + new_barrel_length  # ~29

# Copy and stretch the barrel section
for x in range(barrel_start_x, new_barrel_end_x):
    # Map new x position to original x position
    orig_x = int(barrel_start_x + (x - barrel_start_x) * original_barrel_length / new_barrel_length)
    orig_x = min(orig_x, barrel_end_x - 1)
    new_data[:, x] = orig_data[:, orig_x]

# Copy the barrel tip (sight and end) from the original
# The tip is roughly the last 5 pixels of the original
tip_length = 5
tip_start_orig = orig_data.shape[1] - tip_length
new_data[:, new_barrel_end_x:new_barrel_end_x + tip_length] = orig_data[:, tip_start_orig:]

# Convert back to image
result = Image.fromarray(new_data, 'RGBA')

# Save the result
result.save('/tmp/gh-issue-solver-1770555685141/assets/sprites/weapons/revolver_topdown.png')
print(f"Saved seamless extended barrel: {result.size}")

# Also save a copy for comparison
result.save('/tmp/seamless_revolver_topdown.png')
print("Comparison copy saved to /tmp/seamless_revolver_topdown.png")
