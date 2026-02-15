#!/usr/bin/env python3
"""Create a grenade case icon for locked grenades in the armory.

The icon shows a closed grenade case (compact military grenade storage box):
- Rectangular compact case shape (smaller/squarer than weapon case)
- Olive/tan military color scheme
- Metal latches on sides
- Handle on top
- Military-style rugged appearance

Size: 64x64 pixels, RGBA mode.
This icon will be used for locked/unavailable grenades.
"""

from PIL import Image, ImageDraw


def create_grenade_case_icon():
    size = 64
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Colors - olive/tan military style (from reference image)
    case_body_base = (75, 80, 70, 255)         # Olive/tan base
    case_body_light = (95, 100, 85, 255)       # Lighter olive
    case_body_dark = (55, 60, 50, 255)         # Dark olive shadow
    metal_latch = (100, 105, 110, 255)         # Dark metal latches
    metal_highlight = (140, 145, 150, 255)     # Metal highlight
    handle_dark = (60, 65, 55, 255)            # Handle dark
    handle_light = (85, 90, 75, 255)           # Handle light
    corner_metal = (90, 95, 100, 255)          # Corner reinforcement

    # Case dimensions (more square/compact than weapon case)
    # Grenade cases are smaller and more cube-like
    case_left = 10
    case_right = 54
    case_top = 20
    case_bottom = 52
    corner_size = 4

    # Draw main case body (olive/tan rectangle)
    draw.rectangle([case_left, case_top, case_right, case_bottom],
                   fill=case_body_base)

    # Add gradient/shading (top lighter, bottom darker)
    draw.rectangle([case_left + 1, case_top + 1,
                    case_right - 1, case_top + 10],
                   fill=case_body_light)
    draw.rectangle([case_left + 1, case_bottom - 8,
                    case_right - 1, case_bottom - 1],
                   fill=case_body_dark)

    # Add ribbed/textured sections (horizontal lines for rugged appearance)
    for y in range(case_top + 12, case_bottom - 10, 8):
        draw.line([(case_left + 2, y), (case_right - 2, y)],
                  fill=case_body_dark, width=1)
        draw.line([(case_left + 2, y + 1), (case_right - 2, y + 1)],
                  fill=case_body_light, width=1)

    # Draw corner reinforcements (metal corners)
    corner_positions = [
        (case_left, case_top),           # Top-left
        (case_right - corner_size, case_top),      # Top-right
        (case_left, case_bottom - corner_size),    # Bottom-left
        (case_right - corner_size, case_bottom - corner_size),  # Bottom-right
    ]

    for x, y in corner_positions:
        draw.rectangle([x, y, x + corner_size, y + corner_size],
                       fill=corner_metal)
        # Add highlight to top-left of each corner
        draw.rectangle([x, y, x + 1, y + 1], fill=metal_highlight)

    # Draw side latches (characteristic of grenade cases)
    latch_y = size // 2 - 3
    latch_height = 6
    latch_width = 3

    # Left latch
    draw.rectangle([case_left - 1, latch_y,
                    case_left + latch_width - 1, latch_y + latch_height],
                   fill=metal_latch)
    draw.line([(case_left - 1, latch_y), (case_left - 1, latch_y + 1)],
              fill=metal_highlight, width=1)

    # Right latch
    draw.rectangle([case_right - latch_width + 1, latch_y,
                    case_right + 1, latch_y + latch_height],
                   fill=metal_latch)
    draw.line([(case_right + 1, latch_y), (case_right + 1, latch_y + 1)],
              fill=metal_highlight, width=1)

    # Draw handle on top (smaller than weapon case handle)
    handle_width = 12
    handle_height = 5
    handle_x = size // 2 - handle_width // 2
    handle_y = case_top - handle_height + 1

    # Handle base attachments
    draw.rectangle([handle_x + 2, case_top - 2,
                    handle_x + 4, case_top],
                   fill=corner_metal)
    draw.rectangle([handle_x + handle_width - 4, case_top - 2,
                    handle_x + handle_width - 2, case_top],
                   fill=corner_metal)

    # Handle arch
    draw.rectangle([handle_x, handle_y,
                    handle_x + handle_width, handle_y + 3],
                   fill=handle_dark)
    draw.rectangle([handle_x + 1, handle_y,
                    handle_x + handle_width - 1, handle_y + 1],
                   fill=handle_light)

    # Handle side pieces
    draw.rectangle([handle_x, handle_y,
                    handle_x + 2, case_top],
                   fill=handle_dark)
    draw.rectangle([handle_x + handle_width - 2, handle_y,
                    handle_x + handle_width, case_top],
                   fill=handle_dark)

    # Add central label area (darker rectangle, like military stencil area)
    label_width = 20
    label_height = 8
    label_x = size // 2 - label_width // 2
    label_y = size // 2 - label_height // 2 + 2

    draw.rectangle([label_x, label_y,
                    label_x + label_width, label_y + label_height],
                   fill=case_body_dark,
                   outline=corner_metal, width=1)

    return img


if __name__ == '__main__':
    # Create grenade case icon (64x64)
    icon = create_grenade_case_icon()
    output_path = '/tmp/gh-issue-solver-1771183327661/assets/sprites/weapons/grenade_case_icon.png'
    icon.save(output_path)
    print(f"Grenade case icon saved to {output_path}")

    # Also save preview to experiments folder
    preview_path = '/tmp/gh-issue-solver-1771183327661/experiments/grenade_case_icon_preview.png'
    icon.save(preview_path)
    print(f"Preview saved to {preview_path}")
