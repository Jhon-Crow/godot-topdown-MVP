#!/usr/bin/env python3
"""
Create a top-down view M16 rifle sprite for a 2D top-down shooter game.

In a top-down game, you're looking at the weapon from ABOVE (bird's eye view).
The rifle appears as a long thin shape showing the top of the barrel, stock,
and some details like the magazine sticking out.

The sprite should be oriented pointing RIGHT (0 degrees) as the default direction,
and the game code will rotate it to match the aim direction.
"""

from PIL import Image, ImageDraw

def create_topdown_m16(width=64, height=16):
    """
    Create a top-down M16 rifle sprite.

    From above, an M16 looks like:
    - Long thin barrel
    - Rectangular receiver/body
    - Stock at the back
    - Magazine sticking down (visible as a small rectangle)
    - Carry handle / optic rail on top

    Args:
        width: Total width of the sprite (length of rifle)
        height: Total height of the sprite (width of rifle from above)

    Returns:
        PIL Image with the top-down M16 sprite
    """
    # Create transparent image
    img = Image.new('RGBA', (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Colors (military dark gray/gunmetal)
    barrel_color = (60, 60, 60, 255)  # Dark gray for barrel
    body_color = (70, 70, 70, 255)    # Slightly lighter for body
    stock_color = (50, 40, 30, 255)   # Dark brown for stock
    magazine_color = (45, 45, 45, 255) # Black for magazine
    highlight_color = (90, 90, 90, 255) # Highlight for top details
    outline_color = (30, 30, 30, 255)  # Near-black outline

    # Calculate dimensions based on total width
    center_y = height // 2

    # Barrel (long thin part at the front/right) - about 40% of length
    barrel_length = int(width * 0.4)
    barrel_width = max(2, height // 4)
    barrel_start_x = width - barrel_length
    barrel_y1 = center_y - barrel_width // 2
    barrel_y2 = center_y + barrel_width // 2

    # Receiver/body (middle section) - about 35% of length
    body_length = int(width * 0.35)
    body_width = max(4, height // 2)
    body_start_x = barrel_start_x - body_length
    body_y1 = center_y - body_width // 2
    body_y2 = center_y + body_width // 2

    # Stock (back section/left) - about 25% of length
    stock_length = body_start_x
    stock_width = max(3, int(height * 0.4))
    stock_y1 = center_y - stock_width // 2
    stock_y2 = center_y + stock_width // 2

    # Draw stock first (back/left)
    draw.rectangle([0, stock_y1, stock_length, stock_y2], fill=stock_color, outline=outline_color)

    # Draw body/receiver (middle)
    draw.rectangle([body_start_x, body_y1, barrel_start_x, body_y2], fill=body_color, outline=outline_color)

    # Draw barrel (front/right)
    draw.rectangle([barrel_start_x, barrel_y1, width-1, barrel_y2], fill=barrel_color, outline=outline_color)

    # Draw magazine (below body, visible as small protrusion in top-down view)
    mag_width = int(body_length * 0.3)
    mag_height = max(2, height // 4)
    mag_x = body_start_x + body_length // 3
    mag_y = center_y + body_width // 2 - 1  # Slight overlap with body
    draw.rectangle([mag_x, mag_y, mag_x + mag_width, mag_y + mag_height],
                   fill=magazine_color, outline=outline_color)

    # Draw carry handle / rail (top detail, visible as highlight strip)
    rail_width = int(body_length * 0.6)
    rail_x = body_start_x + (body_length - rail_width) // 2
    rail_y = body_y1 + 1
    draw.line([(rail_x, rail_y), (rail_x + rail_width, rail_y)], fill=highlight_color, width=1)

    # Add muzzle detail at the tip (small bright point)
    draw.point((width-1, center_y), fill=(100, 100, 100, 255))

    return img


def create_simple_topdown_m16(width=48, height=12):
    """
    Create a simpler/smaller top-down M16 for smaller resolutions.
    """
    img = Image.new('RGBA', (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    center_y = height // 2

    # Simple version: just barrel, body, stock
    barrel_color = (60, 60, 60, 255)
    body_color = (70, 70, 70, 255)
    stock_color = (50, 40, 30, 255)
    outline = (30, 30, 30, 255)

    # Stock (left 20%)
    stock_end = int(width * 0.2)
    stock_h = max(2, height // 3)
    draw.rectangle([0, center_y - stock_h//2, stock_end, center_y + stock_h//2],
                   fill=stock_color, outline=outline)

    # Body (middle 35%)
    body_start = stock_end
    body_end = int(width * 0.55)
    body_h = max(3, height // 2)
    draw.rectangle([body_start, center_y - body_h//2, body_end, center_y + body_h//2],
                   fill=body_color, outline=outline)

    # Barrel (right 45%)
    barrel_h = max(2, height // 4)
    draw.rectangle([body_end, center_y - barrel_h//2, width-1, center_y + barrel_h//2],
                   fill=barrel_color, outline=outline)

    return img


if __name__ == "__main__":
    import os

    output_dir = "/tmp/gh-issue-solver-1768999124131/assets/sprites/weapons"

    # Create main top-down M16 (64x16)
    m16_main = create_topdown_m16(64, 16)
    m16_main.save(os.path.join(output_dir, "m16_rifle_topdown.png"))
    print(f"Created m16_rifle_topdown.png (64x16)")

    # Create medium top-down M16 (48x12)
    m16_medium = create_simple_topdown_m16(48, 12)
    m16_medium.save(os.path.join(output_dir, "m16_topdown_medium.png"))
    print(f"Created m16_topdown_medium.png (48x12)")

    # Create small top-down M16 (32x8)
    m16_small = create_simple_topdown_m16(32, 8)
    m16_small.save(os.path.join(output_dir, "m16_topdown_small.png"))
    print(f"Created m16_topdown_small.png (32x8)")

    print("\nTop-down M16 sprites created successfully!")
    print("These sprites show the rifle from ABOVE (bird's eye view)")
    print("pointing to the RIGHT as the default direction.")
