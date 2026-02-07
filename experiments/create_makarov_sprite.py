"""
Create a simple top-down pixel art sprite for the Makarov PM pistol.
The sprite should match the style of the existing silenced_pistol_topdown.png
but be shorter (no suppressor) and represent a compact Soviet pistol.
"""
from PIL import Image

# Create a 30x12 image (shorter than silenced pistol's 44x12 since no suppressor)
width, height = 30, 12
img = Image.new('RGBA', (width, height), (0, 0, 0, 0))

pixels = img.load()

# Colors for a simple top-down pistol (dark steel/gunmetal)
barrel_dark = (60, 60, 60, 255)      # Dark steel for barrel
slide_color = (80, 80, 80, 255)      # Slide/upper
slide_light = (100, 100, 100, 255)   # Slide highlight
grip_dark = (50, 40, 30, 255)        # Dark brown grip (bakelite)
grip_color = (70, 55, 40, 255)       # Brown grip
grip_light = (85, 70, 50, 255)       # Lighter grip edge
frame_color = (75, 75, 75, 255)      # Frame
trigger_guard = (65, 65, 65, 255)    # Trigger guard
outline = (40, 40, 40, 255)          # Outline

# Draw the Makarov PM from top-down view (pointing right)
# The pistol is viewed from above: barrel at right, grip at left-center

# Barrel (x: 20-29, y: 4-7) - the muzzle end
for x in range(20, 29):
    for y in range(4, 8):
        if y == 4 or y == 7:
            pixels[x, y] = outline
        elif y == 5:
            pixels[x, y] = slide_light
        else:
            pixels[x, y] = slide_color

# Muzzle tip
pixels[29, 5] = outline
pixels[29, 6] = outline

# Slide / upper receiver (x: 8-20, y: 3-8)
for x in range(8, 21):
    for y in range(3, 9):
        if y == 3 or y == 8:
            pixels[x, y] = outline
        elif x == 8:
            pixels[x, y] = outline
        elif y == 4:
            pixels[x, y] = slide_light
        elif y == 7:
            pixels[x, y] = slide_color
        else:
            pixels[x, y] = slide_color if y > 5 else slide_light

# Ejection port (top of slide, visible from top-down)
for x in range(14, 19):
    pixels[x, 4] = barrel_dark
    pixels[x, 5] = (55, 55, 55, 255)

# Grip (x: 2-10, y: 2-9) - wider part where hand holds
for x in range(2, 10):
    for y in range(2, 10):
        if y == 2 or y == 9:
            if 3 <= x <= 9:
                pixels[x, y] = outline
        elif x == 2:
            if 3 <= y <= 8:
                pixels[x, y] = outline
        elif x <= 7:
            if y == 3 or y == 8:
                pixels[x, y] = grip_dark
            elif y in (4, 7):
                pixels[x, y] = grip_color
            else:
                pixels[x, y] = grip_light

# Grip texture lines (bakelite grip panels)
for y in range(4, 8):
    if y % 2 == 0:
        pixels[4, y] = grip_dark
        pixels[6, y] = grip_dark

# Trigger guard area (x: 8-12, y: 8-9)
for x in range(9, 13):
    pixels[x, 8] = trigger_guard

# Front sight at muzzle
pixels[28, 5] = (90, 90, 90, 255)
pixels[28, 6] = (90, 90, 90, 255)

# Rear sight
pixels[9, 4] = (90, 90, 90, 255)
pixels[9, 7] = (90, 90, 90, 255)

# Magazine base plate visible at bottom of grip
for x in range(3, 7):
    pixels[x, 9] = (55, 45, 35, 255)

# Save the sprite
output_path = '/tmp/gh-issue-solver-1770470615069/assets/sprites/weapons/makarov_pm_topdown.png'
img.save(output_path)
print(f"Sprite saved to {output_path}")
print(f"Size: {width}x{height}")
