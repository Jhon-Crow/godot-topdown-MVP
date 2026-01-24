#!/usr/bin/env python3
"""
Create a simple M16 rifle sprite for the top-down 2D game.
The sprite is a recognizable silhouette suitable for the game's visual style.
"""

from PIL import Image, ImageDraw

def create_m16_sprite():
    """Create an M16 rifle sprite as a PNG image."""

    # Image dimensions - rifle viewed from the side (top-down perspective shows side view)
    width = 64
    height = 20

    # Create image with transparency
    img = Image.new('RGBA', (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Colors (dark gray for rifle body, darker for details)
    body_color = (60, 60, 60, 255)  # Dark gray
    detail_color = (40, 40, 40, 255)  # Darker gray
    highlight_color = (80, 80, 80, 255)  # Lighter gray for highlights

    # M16 rifle shape (simplified side view)
    # Drawing from left (stock) to right (muzzle)

    # Stock (buttstock) - left side
    # Rectangular stock
    draw.rectangle([0, 5, 12, 14], fill=body_color)

    # Receiver/body - main body of the rifle
    draw.rectangle([10, 4, 40, 14], fill=body_color)

    # Pistol grip - below receiver
    draw.rectangle([22, 12, 28, 19], fill=body_color)

    # Magazine - in front of pistol grip
    draw.rectangle([28, 10, 34, 18], fill=detail_color)

    # Barrel - extends from receiver to muzzle
    draw.rectangle([38, 7, 62, 11], fill=body_color)

    # Flash hider/muzzle - at the end
    draw.rectangle([60, 6, 64, 12], fill=detail_color)

    # Carrying handle (distinctive M16 feature) - on top of receiver
    draw.rectangle([18, 1, 35, 5], fill=body_color)
    draw.rectangle([20, 0, 33, 3], fill=detail_color)

    # Handguard detail line
    draw.line([40, 9, 55, 9], fill=detail_color, width=1)

    # Front sight - small post near muzzle
    draw.rectangle([55, 4, 58, 8], fill=detail_color)

    # Trigger guard
    draw.arc([20, 12, 30, 20], start=0, end=180, fill=detail_color)

    # Add some highlight lines for depth
    draw.line([12, 4, 38, 4], fill=highlight_color, width=1)
    draw.line([38, 7, 60, 7], fill=highlight_color, width=1)

    return img

def create_m16_sprite_v2():
    """Create an improved M16 rifle sprite with better proportions."""

    # Larger image for better detail
    width = 80
    height = 24

    # Create image with transparency
    img = Image.new('RGBA', (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Colors
    body_color = (50, 50, 55, 255)  # Dark gunmetal
    detail_color = (35, 35, 40, 255)  # Darker for details
    highlight_color = (70, 70, 75, 255)  # Highlights
    black = (20, 20, 25, 255)  # Very dark for outlines

    # M16 profile from side

    # 1. Stock (buttstock) - collapsible style
    stock_points = [(0, 7), (0, 16), (14, 16), (16, 14), (16, 9), (14, 7)]
    draw.polygon(stock_points, fill=body_color, outline=black)

    # 2. Lower receiver
    receiver_points = [(14, 6), (14, 17), (44, 17), (44, 6)]
    draw.polygon(receiver_points, fill=body_color, outline=black)

    # 3. Upper receiver with carrying handle
    upper_points = [(14, 6), (14, 2), (42, 2), (42, 6)]
    draw.polygon(upper_points, fill=body_color, outline=black)

    # 4. Carrying handle detail (raised section)
    draw.rectangle([18, 0, 38, 3], fill=detail_color, outline=black)

    # 5. Pistol grip
    grip_points = [(24, 16), (24, 23), (30, 23), (32, 17)]
    draw.polygon(grip_points, fill=body_color, outline=black)

    # 6. Magazine (curved STANAG style)
    draw.rectangle([34, 14, 42, 23], fill=detail_color, outline=black)

    # 7. Barrel and handguard
    draw.rectangle([42, 7, 72, 13], fill=body_color, outline=black)

    # 8. Barrel extension (thinner)
    draw.rectangle([70, 8, 78, 12], fill=detail_color, outline=black)

    # 9. Flash hider
    draw.rectangle([76, 7, 80, 13], fill=black)

    # 10. Front sight post
    draw.rectangle([68, 3, 72, 8], fill=detail_color, outline=black)

    # 11. Handguard vents (detail lines)
    for x in range(46, 68, 4):
        draw.line([(x, 8), (x, 12)], fill=detail_color, width=1)

    # 12. Trigger guard
    draw.arc([22, 15, 34, 23], start=0, end=180, fill=black)

    # 13. Trigger
    draw.line([(28, 17), (28, 20)], fill=black, width=2)

    # 14. Ejection port (detail)
    draw.rectangle([30, 4, 36, 6], fill=detail_color)

    # 15. Charging handle
    draw.rectangle([16, 3, 20, 5], fill=detail_color)

    # Highlight lines for 3D effect
    draw.line([(16, 6), (42, 6)], fill=highlight_color, width=1)
    draw.line([(44, 8), (70, 8)], fill=highlight_color, width=1)

    return img

def create_simple_m16_sprite():
    """Create a very simple M16 silhouette for placeholder-style graphics."""

    width = 48
    height = 16

    img = Image.new('RGBA', (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Simple dark color to match game's minimalist style
    color = (40, 45, 50, 230)  # Dark gray, slightly transparent
    outline = (30, 35, 40, 255)

    # Very simplified M16 shape
    # Main body
    draw.rectangle([0, 4, 35, 10], fill=color, outline=outline)

    # Barrel
    draw.rectangle([33, 5, 48, 9], fill=color, outline=outline)

    # Stock
    draw.rectangle([0, 3, 8, 11], fill=color, outline=outline)

    # Pistol grip
    draw.rectangle([12, 9, 18, 15], fill=color, outline=outline)

    # Magazine
    draw.rectangle([20, 9, 26, 15], fill=color, outline=outline)

    # Carrying handle (distinctive M16 feature)
    draw.rectangle([10, 1, 28, 5], fill=color, outline=outline)

    return img

if __name__ == "__main__":
    # Create all versions
    sprites = {
        "m16_rifle.png": create_m16_sprite_v2(),
        "m16_simple.png": create_simple_m16_sprite(),
        "m16_basic.png": create_m16_sprite()
    }

    base_path = "/tmp/gh-issue-solver-1768997049995/assets/sprites/weapons/"

    for filename, sprite in sprites.items():
        filepath = base_path + filename
        sprite.save(filepath, "PNG")
        print(f"Created: {filepath} ({sprite.width}x{sprite.height})")

    print("\nSprite creation complete!")
