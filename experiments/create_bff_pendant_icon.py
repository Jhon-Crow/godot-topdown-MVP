#!/usr/bin/env python3
"""Create a BFF pendant icon for the armory menu.

Creates a 64x48 pixel PNG icon with transparent background,
depicting a heart-shaped pendant with "BFF" text - matching
the style of other armory icons (simple outlines on transparent bg).
"""

from PIL import Image, ImageDraw, ImageFont
import os

def create_bff_pendant_icon():
    """Create a BFF pendant icon as a 64x48 PNG with transparency."""
    width, height = 64, 48
    img = Image.new('RGBA', (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Colors - using a warm gold/amber tone for the pendant
    pendant_color = (220, 180, 60, 255)  # Gold
    chain_color = (180, 150, 50, 255)    # Darker gold for chain
    heart_color = (200, 60, 80, 255)     # Red-pink for heart
    text_color = (255, 255, 255, 255)    # White for BFF text

    # Draw chain (top part - small loops)
    cx = width // 2
    # Chain links going up from pendant
    for i in range(3):
        y = 6 + i * 4
        draw.ellipse([cx - 3, y, cx + 3, y + 4], outline=chain_color, width=1)

    # Draw heart shape for the pendant body (centered, lower portion)
    heart_cx = cx
    heart_cy = 28

    # Heart made with two circles and a triangle
    r = 7
    # Left bump
    draw.ellipse([heart_cx - r - 3, heart_cy - r, heart_cx - 3 + r, heart_cy + r],
                 fill=heart_color, outline=pendant_color, width=1)
    # Right bump
    draw.ellipse([heart_cx + 3 - r, heart_cy - r, heart_cx + 3 + r, heart_cy + r],
                 fill=heart_color, outline=pendant_color, width=1)
    # Bottom triangle of heart
    draw.polygon([
        (heart_cx - r - 3, heart_cy + 2),
        (heart_cx + r + 3, heart_cy + 2),
        (heart_cx, heart_cy + r + 8)
    ], fill=heart_color, outline=pendant_color, width=1)

    # Fill center gap in heart
    draw.rectangle([heart_cx - 3, heart_cy - 2, heart_cx + 3, heart_cy + 4],
                   fill=heart_color)

    # Draw "BFF" text on the heart
    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 8)
    except (OSError, IOError):
        font = ImageFont.load_default()

    # Get text bounding box for centering
    bbox = draw.textbbox((0, 0), "BFF", font=font)
    text_w = bbox[2] - bbox[0]
    text_h = bbox[3] - bbox[1]
    text_x = heart_cx - text_w // 2
    text_y = heart_cy - text_h // 2 + 1

    draw.text((text_x, text_y), "BFF", fill=text_color, font=font)

    # Draw a small ring at top connecting chain to pendant
    draw.ellipse([cx - 3, 18, cx + 3, 23], outline=pendant_color, width=1)

    # Save the icon
    output_path = os.path.join(os.path.dirname(os.path.dirname(__file__)),
                                'assets', 'sprites', 'weapons', 'bff_pendant_icon.png')
    img.save(output_path)
    print(f"Icon saved to {output_path}")

    # Also save a copy in experiments
    exp_path = os.path.join(os.path.dirname(__file__), 'bff_pendant_icon.png')
    img.save(exp_path)
    print(f"Copy saved to {exp_path}")


if __name__ == "__main__":
    create_bff_pendant_icon()
