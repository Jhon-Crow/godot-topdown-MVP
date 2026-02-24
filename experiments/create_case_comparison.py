#!/usr/bin/env python3
"""Create a comparison image showing all three case icons side by side."""

from PIL import Image, ImageDraw, ImageFont

def create_comparison():
    # Load the three case icons
    weapon_case = Image.open('/tmp/gh-issue-solver-1771183327661/assets/sprites/weapons/weapon_case_icon.png')
    grenade_case = Image.open('/tmp/gh-issue-solver-1771183327661/assets/sprites/weapons/grenade_case_icon.png')
    item_case = Image.open('/tmp/gh-issue-solver-1771183327661/assets/sprites/weapons/item_case_icon.png')

    # Create comparison image (3 icons side by side with labels)
    icon_size = 64
    padding = 20
    label_height = 30

    width = (icon_size + padding) * 3 + padding
    height = icon_size + label_height + padding * 2

    comparison = Image.new('RGBA', (width, height), (40, 40, 45, 255))
    draw = ImageDraw.Draw(comparison)

    # Paste icons
    x_positions = [padding, padding * 2 + icon_size, padding * 3 + icon_size * 2]
    icons = [weapon_case, grenade_case, item_case]
    labels = ['Weapon Case', 'Grenade Case', 'Item Case']

    for i, (x, icon, label) in enumerate(zip(x_positions, icons, labels)):
        # Paste icon
        comparison.paste(icon, (x, padding), icon)

        # Draw label
        text_bbox = draw.textbbox((0, 0), label)
        text_width = text_bbox[2] - text_bbox[0]
        text_x = x + (icon_size - text_width) // 2
        text_y = padding + icon_size + 5

        draw.text((text_x, text_y), label, fill=(200, 200, 200, 255))

    return comparison

if __name__ == '__main__':
    comparison = create_comparison()
    output_path = '/tmp/gh-issue-solver-1771183327661/experiments/case_icons_comparison.png'
    comparison.save(output_path)
    print(f"Comparison image saved to {output_path}")
