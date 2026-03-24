#!/usr/bin/env python3
"""Create an item case icon for locked active items in the armory.

The icon shows a closed item/equipment case (rugged protective storage case):
- Rectangular protective case shape (like a Pelican case)
- Black/dark body with orange/red accents
- Prominent latches on sides
- Bright colored handle on top
- Rugged, heavy-duty appearance

Size: 64x64 pixels, RGBA mode.
This icon will be used for locked/unavailable active items (special equipment).
"""

from PIL import Image, ImageDraw


def create_item_case_icon():
    size = 64
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Colors - black case with orange/red accents (from reference image)
    case_body_black = (25, 30, 35, 255)        # Black case body
    case_body_dark = (15, 20, 25, 255)         # Darker black shadows
    case_body_light = (40, 45, 50, 255)        # Lighter highlights
    orange_accent = (220, 85, 40, 255)         # Orange/red accent color
    orange_dark = (180, 65, 30, 255)           # Darker orange
    orange_light = (240, 105, 60, 255)         # Lighter orange
    metal_latch = (60, 65, 70, 255)            # Dark metal latches
    metal_highlight = (100, 105, 110, 255)     # Metal highlight
    case_edge = (35, 40, 45, 255)              # Edge detail

    # Case dimensions (rectangular, professional equipment case)
    case_left = 8
    case_right = 56
    case_top = 18
    case_bottom = 50

    # Draw main case body (black rectangle)
    draw.rectangle([case_left, case_top, case_right, case_bottom],
                   fill=case_body_black)

    # Add edge details (raised edges like on Pelican cases)
    edge_width = 2
    # Top edge
    draw.rectangle([case_left, case_top, case_right, case_top + edge_width],
                   fill=case_edge)
    # Bottom edge
    draw.rectangle([case_left, case_bottom - edge_width, case_right, case_bottom],
                   fill=case_edge)
    # Left edge
    draw.rectangle([case_left, case_top, case_left + edge_width, case_bottom],
                   fill=case_edge)
    # Right edge
    draw.rectangle([case_right - edge_width, case_top, case_right, case_bottom],
                   fill=case_edge)

    # Add ribbed/reinforced sections (horizontal ribs)
    for y in range(case_top + 8, case_bottom - 6, 6):
        draw.line([(case_left + 3, y), (case_right - 3, y)],
                  fill=case_body_dark, width=1)
        draw.line([(case_left + 3, y + 2), (case_right - 3, y + 2)],
                  fill=case_body_light, width=1)

    # Draw corner reinforcements (orange accent corners)
    corner_size = 5
    corner_positions = [
        (case_left, case_top),                              # Top-left
        (case_right - corner_size, case_top),               # Top-right
        (case_left, case_bottom - corner_size),             # Bottom-left
        (case_right - corner_size, case_bottom - corner_size),  # Bottom-right
    ]

    for x, y in corner_positions:
        # Orange accent corner piece
        draw.rectangle([x, y, x + corner_size, y + corner_size],
                       fill=orange_accent)
        draw.rectangle([x, y, x + 2, y + 2], fill=orange_light)
        draw.rectangle([x + corner_size - 2, y + corner_size - 2,
                        x + corner_size, y + corner_size],
                       fill=orange_dark)

    # Draw side latches (prominent orange/red latches)
    latch_y = size // 2 - 4
    latch_height = 8
    latch_width = 4

    # Left latch (orange accent)
    draw.rectangle([case_left - 2, latch_y,
                    case_left + latch_width - 2, latch_y + latch_height],
                   fill=orange_accent)
    draw.rectangle([case_left - 2, latch_y,
                    case_left, latch_y + 2],
                   fill=orange_light)
    draw.rectangle([case_left + latch_width - 3, latch_y + latch_height - 2,
                    case_left + latch_width - 2, latch_y + latch_height],
                   fill=orange_dark)

    # Right latch (orange accent)
    draw.rectangle([case_right - latch_width + 2, latch_y,
                    case_right + 2, latch_y + latch_height],
                   fill=orange_accent)
    draw.rectangle([case_right, latch_y,
                    case_right + 2, latch_y + 2],
                   fill=orange_light)
    draw.rectangle([case_right - latch_width + 2, latch_y + latch_height - 2,
                    case_right - latch_width + 4, latch_y + latch_height],
                   fill=orange_dark)

    # Draw handle on top (bright orange/red handle - prominent feature)
    handle_width = 16
    handle_height = 6
    handle_x = size // 2 - handle_width // 2
    handle_y = case_top - handle_height

    # Handle base attachments (metal)
    draw.rectangle([handle_x + 2, case_top - 2,
                    handle_x + 5, case_top + 1],
                   fill=metal_latch)
    draw.rectangle([handle_x + handle_width - 5, case_top - 2,
                    handle_x + handle_width - 2, case_top + 1],
                   fill=metal_latch)

    # Handle body (bright orange)
    draw.rectangle([handle_x, handle_y,
                    handle_x + handle_width, handle_y + 4],
                   fill=orange_accent)
    # Handle highlight (top)
    draw.rectangle([handle_x + 1, handle_y,
                    handle_x + handle_width - 1, handle_y + 1],
                   fill=orange_light)
    # Handle shadow (bottom)
    draw.rectangle([handle_x + 1, handle_y + 3,
                    handle_x + handle_width - 1, handle_y + 4],
                   fill=orange_dark)

    # Handle side pieces connecting to case
    draw.rectangle([handle_x, handle_y + 2,
                    handle_x + 3, case_top],
                   fill=orange_accent)
    draw.rectangle([handle_x + handle_width - 3, handle_y + 2,
                    handle_x + handle_width, case_top],
                   fill=orange_accent)

    # Add central logo/badge area (subtle dark rectangle)
    badge_width = 18
    badge_height = 10
    badge_x = size // 2 - badge_width // 2
    badge_y = size // 2 - badge_height // 2 + 2

    draw.rectangle([badge_x, badge_y,
                    badge_x + badge_width, badge_y + badge_height],
                   fill=case_body_dark,
                   outline=case_body_light, width=1)

    return img


if __name__ == '__main__':
    # Create item case icon (64x64)
    icon = create_item_case_icon()
    output_path = '/tmp/gh-issue-solver-1771183327661/assets/sprites/weapons/item_case_icon.png'
    icon.save(output_path)
    print(f"Item case icon saved to {output_path}")

    # Also save preview to experiments folder
    preview_path = '/tmp/gh-issue-solver-1771183327661/experiments/item_case_icon_preview.png'
    icon.save(preview_path)
    print(f"Preview saved to {preview_path}")
