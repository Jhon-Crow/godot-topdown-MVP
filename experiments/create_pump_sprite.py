#!/usr/bin/env python3
"""
Create a simple pump/foregrip sprite for the shotgun reload animation.
Issue #447: Add reload animation to shotgun.

The pump sprite represents the foregrip/pump handle that moves during
pump-action cycling. It's a small rectangular shape that sits on the
shotgun barrel.
"""

from PIL import Image, ImageDraw

def create_pump_sprite():
    """Create a simple pump/foregrip sprite for the shotgun."""
    # Pump dimensions (width x height in pixels)
    # The pump is wider than tall, positioned horizontally along the barrel
    width = 6
    height = 8

    # Create image with transparency
    img = Image.new('RGBA', (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Main pump body - dark gray metal color
    pump_color = (60, 60, 65, 255)  # Dark gray-blue steel
    draw.rectangle([0, 0, width-1, height-1], fill=pump_color)

    # Highlight on top edge for 3D effect
    highlight_color = (90, 90, 95, 255)
    draw.line([(0, 0), (width-1, 0)], fill=highlight_color)

    # Shadow on bottom edge
    shadow_color = (40, 40, 45, 255)
    draw.line([(0, height-1), (width-1, height-1)], fill=shadow_color)

    return img

def main():
    # Create pump sprite
    pump = create_pump_sprite()

    # Save to assets folder
    output_path = '../assets/sprites/weapons/shotgun_pump.png'
    pump.save(output_path)
    print(f"Created pump sprite: {output_path}")
    print(f"Size: {pump.size[0]}x{pump.size[1]} pixels")

    # Also save to experiments folder for reference
    pump.save('shotgun_pump.png')
    print("Also saved to experiments/shotgun_pump.png")

if __name__ == '__main__':
    main()
