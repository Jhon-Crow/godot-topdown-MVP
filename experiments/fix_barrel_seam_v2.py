#!/usr/bin/env python3
"""
Fix barrel seam on revolver_topdown.png - Version 2
This script creates a seamless barrel extension by repeating barrel texture.
"""

from PIL import Image
import numpy as np

# Load the original revolver (before extension)
original = Image.open('/tmp/original_revolver_topdown.png')
orig_data = np.array(original)

print(f"Original dimensions: {original.size}")
print(f"Original shape: {orig_data.shape}")

# Analyze the structure:
# - Grip/handle: x=0 to ~9
# - Cylinder: x=9 to ~15
# - Barrel: x=15 to ~29 (the main barrel section)
# - Front sight/tip: x=29 to 33 (end cap)

# Create new image with extended width (45x14)
new_width = 45
new_height = 14
new_img = Image.new('RGBA', (new_width, new_height), (0, 0, 0, 0))
new_data = np.array(new_img)

# Copy the grip and cylinder part (first ~15 pixels)
grip_cylinder_end = 15
new_data[:, :grip_cylinder_end] = orig_data[:, :grip_cylinder_end]

# Define the barrel section that we'll extend
# Looking at the original, the barrel texture is from about x=15 to x=29
barrel_texture_start = 15
barrel_texture_end = 29
barrel_texture_length = barrel_texture_end - barrel_texture_start  # ~14 pixels

# The original barrel is ~14 pixels long
# We want to double it to ~28 pixels long
# So we need to add another 14 pixels

# Copy the original barrel section
new_data[:, grip_cylinder_end:grip_cylinder_end + barrel_texture_length] = orig_data[:, barrel_texture_start:barrel_texture_end]

# Now repeat/tile the middle part of the barrel to extend it
# Use the middle section of the barrel as the repeating pattern
barrel_middle_start = 18  # A few pixels into the barrel
barrel_middle_end = 26    # Before the barrel end
barrel_middle_pattern = orig_data[:, barrel_middle_start:barrel_middle_end]

# Extend with the middle barrel pattern
extension_start = grip_cylinder_end + barrel_texture_length
extension_length = barrel_texture_length  # Add another 14 pixels
for i in range(extension_length):
    pattern_x = i % (barrel_middle_end - barrel_middle_start)
    new_data[:, extension_start + i] = barrel_middle_pattern[:, pattern_x]

# Copy the barrel tip/front sight (last ~5 pixels of original)
tip_start_orig = 29
tip_end_orig = 34
tip_length = tip_end_orig - tip_start_orig
tip_start_new = extension_start + extension_length
new_data[:, tip_start_new:tip_start_new + tip_length] = orig_data[:, tip_start_orig:tip_end_orig]

# Convert back to image
result = Image.fromarray(new_data, 'RGBA')

# Save the result
result.save('/tmp/gh-issue-solver-1770555685141/assets/sprites/weapons/revolver_topdown.png')
print(f"Saved seamless extended barrel: {result.size}")

# Also save a copy for comparison
result.save('/tmp/seamless_revolver_topdown_v2.png')
print("Comparison copy saved to /tmp/seamless_revolver_topdown_v2.png")
