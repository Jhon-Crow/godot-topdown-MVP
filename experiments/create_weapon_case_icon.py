#!/usr/bin/env python3
"""Create a weapon case icon for locked items in the armory.

The icon shows a closed weapon case (like those in the reference images):
- Rectangular case shape (rifle case style)
- Dark body (dark gray/black)
- Metal frame/corners (silver/aluminum)
- Handle on top
- Lock clasp in the center

Size: 64x64 pixels, RGBA mode.
This icon will be used for locked/unavailable weapons, grenades, and items.
"""

from PIL import Image, ImageDraw


def create_weapon_case_icon():
    size = 64
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Colors
    case_body_dark = (30, 35, 45, 255)        # Dark case body
    case_body_light = (45, 50, 60, 255)       # Case body highlight
    metal_frame = (150, 155, 165, 255)        # Silver/aluminum frame
    metal_dark = (100, 105, 115, 255)         # Darker metal
    metal_highlight = (180, 185, 195, 255)    # Metal highlight
    handle_dark = (70, 75, 85, 255)           # Handle dark
    handle_light = (90, 95, 105, 255)         # Handle light
    lock_gold = (180, 150, 60, 255)           # Lock/clasp gold color
    lock_dark = (140, 110, 40, 255)           # Lock dark shade

    # Case dimensions (centered, rectangular like a rifle case)
    # The case is horizontal (wider than tall)
    case_left = 4
    case_right = 60
    case_top = 18
    case_bottom = 50
    corner_size = 5
    frame_width = 2

    # Draw main case body (dark rectangle)
    draw.rectangle([case_left + frame_width, case_top + frame_width,
                    case_right - frame_width, case_bottom - frame_width],
                   fill=case_body_dark)

    # Add subtle gradient/highlight on case body (top lighter)
    draw.rectangle([case_left + frame_width + 1, case_top + frame_width + 1,
                    case_right - frame_width - 1, case_top + 12],
                   fill=case_body_light)

    # Draw metal frame (outline)
    # Top edge
    draw.rectangle([case_left + corner_size, case_top,
                    case_right - corner_size, case_top + frame_width],
                   fill=metal_frame)
    # Bottom edge
    draw.rectangle([case_left + corner_size, case_bottom - frame_width,
                    case_right - corner_size, case_bottom],
                   fill=metal_frame)
    # Left edge
    draw.rectangle([case_left, case_top + corner_size,
                    case_left + frame_width, case_bottom - corner_size],
                   fill=metal_frame)
    # Right edge
    draw.rectangle([case_right - frame_width, case_top + corner_size,
                    case_right, case_bottom - corner_size],
                   fill=metal_frame)

    # Draw corner pieces (metal corners)
    # Top-left corner
    draw.rectangle([case_left, case_top,
                    case_left + corner_size, case_top + corner_size],
                   fill=metal_frame)
    draw.rectangle([case_left, case_top,
                    case_left + 2, case_top + 2],
                   fill=metal_highlight)

    # Top-right corner
    draw.rectangle([case_right - corner_size, case_top,
                    case_right, case_top + corner_size],
                   fill=metal_frame)
    draw.rectangle([case_right - 2, case_top,
                    case_right, case_top + 2],
                   fill=metal_highlight)

    # Bottom-left corner
    draw.rectangle([case_left, case_bottom - corner_size,
                    case_left + corner_size, case_bottom],
                   fill=metal_frame)
    draw.rectangle([case_left, case_bottom - 2,
                    case_left + 2, case_bottom],
                   fill=metal_dark)

    # Bottom-right corner
    draw.rectangle([case_right - corner_size, case_bottom - corner_size,
                    case_right, case_bottom],
                   fill=metal_frame)
    draw.rectangle([case_right - 2, case_bottom - 2,
                    case_right, case_bottom],
                   fill=metal_dark)

    # Draw handle on top
    handle_width = 16
    handle_height = 6
    handle_x = size // 2 - handle_width // 2
    handle_y = case_top - handle_height + 2

    # Handle base (attaches to case)
    draw.rectangle([handle_x + 2, case_top - 2,
                    handle_x + 5, case_top],
                   fill=metal_frame)
    draw.rectangle([handle_x + handle_width - 5, case_top - 2,
                    handle_x + handle_width - 2, case_top],
                   fill=metal_frame)

    # Handle arch
    draw.rectangle([handle_x, handle_y,
                    handle_x + handle_width, handle_y + 3],
                   fill=handle_dark)
    draw.rectangle([handle_x + 1, handle_y,
                    handle_x + handle_width - 1, handle_y + 1],
                   fill=handle_light)

    # Handle side pieces
    draw.rectangle([handle_x, handle_y,
                    handle_x + 3, case_top - 1],
                   fill=handle_dark)
    draw.rectangle([handle_x + handle_width - 3, handle_y,
                    handle_x + handle_width, case_top - 1],
                   fill=handle_dark)

    # Draw lock/clasp in center
    lock_size = 6
    lock_x = size // 2 - lock_size // 2
    lock_y = size // 2 - lock_size // 2 + 2

    # Lock base (square)
    draw.rectangle([lock_x, lock_y,
                    lock_x + lock_size, lock_y + lock_size],
                   fill=lock_gold)
    draw.rectangle([lock_x, lock_y,
                    lock_x + 2, lock_y + 2],
                   fill=(200, 170, 80, 255))  # Highlight
    draw.rectangle([lock_x + lock_size - 2, lock_y + lock_size - 2,
                    lock_x + lock_size, lock_y + lock_size],
                   fill=lock_dark)  # Shadow

    # Keyhole in center of lock
    draw.ellipse([lock_x + 2, lock_y + 1,
                  lock_x + 4, lock_y + 3],
                 fill=case_body_dark)
    draw.line([(lock_x + 3, lock_y + 3), (lock_x + 3, lock_y + 5)],
              fill=case_body_dark, width=1)

    # Add subtle edge highlights on case
    draw.line([(case_left + corner_size, case_top + frame_width),
               (case_right - corner_size, case_top + frame_width)],
              fill=(60, 65, 75, 255), width=1)

    return img


def create_weapon_case_icon_small():
    """Create a smaller, simpler version for grenade slots (48x48)."""
    size = 48
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Colors
    case_body_dark = (30, 35, 45, 255)
    case_body_light = (45, 50, 60, 255)
    metal_frame = (150, 155, 165, 255)
    metal_highlight = (180, 185, 195, 255)
    lock_gold = (180, 150, 60, 255)

    # Smaller case dimensions (more square for grenade-sized items)
    case_left = 6
    case_right = 42
    case_top = 10
    case_bottom = 38

    # Main body
    draw.rectangle([case_left + 2, case_top + 2,
                    case_right - 2, case_bottom - 2],
                   fill=case_body_dark)
    draw.rectangle([case_left + 3, case_top + 3,
                    case_right - 3, case_top + 10],
                   fill=case_body_light)

    # Metal frame
    draw.rectangle([case_left, case_top, case_right, case_top + 2], fill=metal_frame)
    draw.rectangle([case_left, case_bottom - 2, case_right, case_bottom], fill=metal_frame)
    draw.rectangle([case_left, case_top, case_left + 2, case_bottom], fill=metal_frame)
    draw.rectangle([case_right - 2, case_top, case_right, case_bottom], fill=metal_frame)

    # Corner highlights
    draw.rectangle([case_left, case_top, case_left + 3, case_top + 3], fill=metal_highlight)
    draw.rectangle([case_right - 3, case_top, case_right, case_top + 3], fill=metal_highlight)

    # Lock
    lock_x, lock_y = size // 2 - 2, size // 2
    draw.rectangle([lock_x, lock_y, lock_x + 4, lock_y + 4], fill=lock_gold)

    return img


if __name__ == '__main__':
    # Create main weapon case icon (64x64)
    icon = create_weapon_case_icon()
    output_path = '/tmp/gh-issue-solver-1771181889622/assets/sprites/weapons/weapon_case_icon.png'
    icon.save(output_path)
    print(f"Main icon saved to {output_path}")

    # Also save preview to experiments folder
    preview_path = '/tmp/gh-issue-solver-1771181889622/experiments/weapon_case_icon_preview.png'
    icon.save(preview_path)
    print(f"Preview saved to {preview_path}")

    # Create small version (48x48)
    icon_small = create_weapon_case_icon_small()
    small_path = '/tmp/gh-issue-solver-1771181889622/assets/sprites/weapons/weapon_case_icon_small.png'
    icon_small.save(small_path)
    print(f"Small icon saved to {small_path}")
