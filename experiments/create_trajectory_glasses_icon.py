#!/usr/bin/env python3
"""
Create a pixel art icon for Trajectory Glasses active item.
The icon should show glasses with green lenses and a crosshair on one lens.
Size: 64x48 pixels (matching other weapon/item icons)
"""

from PIL import Image, ImageDraw

def create_trajectory_glasses_icon():
    # Create a transparent 64x48 image
    img = Image.new('RGBA', (64, 48), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Colors
    frame_dark = (40, 40, 40, 255)      # Dark frame outline
    frame_light = (80, 80, 80, 255)     # Lighter frame
    lens_green = (0, 180, 0, 200)       # Green lens (semi-transparent)
    lens_green_light = (100, 255, 100, 180)  # Lighter green highlight
    crosshair_color = (255, 50, 50, 255)  # Red crosshair for contrast
    bridge_color = (60, 60, 60, 255)    # Bridge between lenses

    # Center the glasses
    cx, cy = 32, 24

    # Lens dimensions
    lens_w, lens_h = 18, 14
    lens_gap = 4  # Gap between lenses

    # Left lens position
    left_x = cx - lens_gap//2 - lens_w
    left_y = cy - lens_h//2

    # Right lens position
    right_x = cx + lens_gap//2
    right_y = cy - lens_h//2

    # Draw left lens (green fill)
    draw.rectangle([left_x, left_y, left_x + lens_w, left_y + lens_h],
                   fill=lens_green, outline=frame_dark)

    # Draw right lens (green fill)
    draw.rectangle([right_x, right_y, right_x + lens_w, right_y + lens_h],
                   fill=lens_green, outline=frame_dark)

    # Add lighter highlight to lenses (top-left corner effect)
    draw.rectangle([left_x + 2, left_y + 2, left_x + 6, left_y + 5],
                   fill=lens_green_light)
    draw.rectangle([right_x + 2, right_y + 2, right_x + 6, right_y + 5],
                   fill=lens_green_light)

    # Draw bridge between lenses
    bridge_y = cy - 1
    draw.rectangle([left_x + lens_w, bridge_y, right_x, bridge_y + 2],
                   fill=bridge_color)

    # Draw temple arms (sides of glasses)
    arm_y = cy - 2
    # Left arm
    draw.rectangle([left_x - 8, arm_y, left_x, arm_y + 3], fill=frame_dark)
    # Right arm
    draw.rectangle([right_x + lens_w, arm_y, right_x + lens_w + 8, arm_y + 3], fill=frame_dark)

    # Draw crosshair on LEFT lens (more visible)
    crosshair_cx = left_x + lens_w // 2
    crosshair_cy = left_y + lens_h // 2

    # Vertical line
    draw.line([crosshair_cx, left_y + 3, crosshair_cx, left_y + lens_h - 3],
              fill=crosshair_color, width=1)
    # Horizontal line
    draw.line([left_x + 3, crosshair_cy, left_x + lens_w - 3, crosshair_cy],
              fill=crosshair_color, width=1)
    # Small circle in center
    draw.ellipse([crosshair_cx - 2, crosshair_cy - 2, crosshair_cx + 2, crosshair_cy + 2],
                 outline=crosshair_color)

    # Add frame thickness at bottom
    draw.rectangle([left_x, left_y + lens_h, left_x + lens_w, left_y + lens_h + 2],
                   fill=frame_light)
    draw.rectangle([right_x, right_y + lens_h, right_x + lens_w, right_y + lens_h + 2],
                   fill=frame_light)

    return img


if __name__ == '__main__':
    icon = create_trajectory_glasses_icon()

    # Save to experiments folder
    icon.save('/tmp/gh-issue-solver-1770755120690/experiments/trajectory_glasses_icon.png')
    print("Saved to experiments/trajectory_glasses_icon.png")

    # Also save directly to assets folder
    icon.save('/tmp/gh-issue-solver-1770755120690/assets/sprites/weapons/trajectory_glasses_icon.png')
    print("Saved to assets/sprites/weapons/trajectory_glasses_icon.png")
