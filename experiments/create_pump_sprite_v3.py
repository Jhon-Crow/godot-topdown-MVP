#!/usr/bin/env python3
"""
Create a volumetric pump sprite with edge darkening.
Size: 20x8 pixels (increased length from 16 to 20)
Color: #533b23 (main body)
Style: Add darkening to edges for volumetric effect
"""

from PIL import Image, ImageDraw

# Create 20x8 image with transparency
width, height = 20, 8
img = Image.new('RGBA', (width, height), (0, 0, 0, 0))

# Define colors
main_color = (0x53, 0x3b, 0x23, 255)  # #533b23 - main brown
dark_edge = (0x3a, 0x28, 0x17, 255)   # Darker brown for edges (~30% darker)
highlight = (0x6a, 0x4d, 0x2d, 255)   # Lighter brown for highlight (~20% lighter)

pixels = img.load()

# Create volumetric effect:
# - Top and bottom edges: darker
# - Middle rows: main color
# - Slight highlight in the middle

for y in range(height):
    for x in range(width):
        # Skip first and last 2 pixels on each end to create rounded ends
        if (x < 2 or x >= width - 2):
            # Create rounded ends
            if y == 0 or y == height - 1:
                continue  # Transparent corners
            elif y == 1 or y == height - 2:
                if x == 0 or x == width - 1:
                    continue  # Round off corners
                pixels[x, y] = dark_edge
            else:
                pixels[x, y] = main_color if x == 1 or x == width - 2 else dark_edge
        else:
            # Main body
            if y == 0 or y == height - 1:
                # Top and bottom edges - darkest
                pixels[x, y] = dark_edge
            elif y == 1 or y == height - 2:
                # Second row from edges - dark transition
                pixels[x, y] = dark_edge
            elif y == height // 2 or y == height // 2 - 1:
                # Middle rows - slight highlight for roundness
                pixels[x, y] = highlight
            else:
                # Other rows - main color
                pixels[x, y] = main_color

# Save the sprite
output_path = 'assets/sprites/weapons/shotgun_pump.png'
img.save(output_path)
print(f"Created pump sprite: {output_path}")
print(f"Size: {width}x{height}")
print(f"Main color: #533b23")
print(f"Edge darkening: applied")

# Also save to experiments for reference
import os
os.makedirs('experiments/sprites', exist_ok=True)
img.save('experiments/sprites/shotgun_pump_v3.png')
print("Also saved to: experiments/sprites/shotgun_pump_v3.png")
