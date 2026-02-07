"""
Create an armory menu icon for the Makarov PM pistol.
Similar in style to the silenced_pistol_icon.png but without suppressor.
Icons are larger/more detailed versions of the top-down sprites.
"""
from PIL import Image

# Create a 60x24 icon (similar to mini_uzi_icon size)
width, height = 60, 24
img = Image.new('RGBA', (width, height), (0, 0, 0, 0))

pixels = img.load()

# Colors
barrel_dark = (60, 60, 60, 255)
slide_color = (80, 80, 80, 255)
slide_light = (100, 100, 100, 255)
slide_top = (110, 110, 110, 255)
grip_dark = (50, 40, 30, 255)
grip_color = (70, 55, 40, 255)
grip_light = (85, 70, 50, 255)
frame_color = (75, 75, 75, 255)
trigger_guard = (65, 65, 65, 255)
outline = (40, 40, 40, 255)
highlight = (120, 120, 120, 255)

# Draw the Makarov PM side view (profile) for icon
# Pointing right, standard pistol profile

# Slide (upper part) - x: 10-50, y: 4-11
for x in range(10, 51):
    for y in range(4, 12):
        if y == 4 or y == 11:
            pixels[x, y] = outline
        elif x == 10 or x == 50:
            pixels[x, y] = outline
        elif y == 5:
            pixels[x, y] = slide_top
        elif y == 6:
            pixels[x, y] = slide_light
        elif y >= 9:
            pixels[x, y] = barrel_dark
        else:
            pixels[x, y] = slide_color

# Barrel protrusion (front of slide) - x: 48-55, y: 6-10
for x in range(48, 56):
    for y in range(6, 11):
        if y == 6 or y == 10:
            pixels[x, y] = outline
        elif x == 55:
            pixels[x, y] = outline
        else:
            pixels[x, y] = slide_color

# Muzzle opening
pixels[55, 7] = barrel_dark
pixels[55, 8] = barrel_dark
pixels[55, 9] = barrel_dark

# Front sight
pixels[50, 3] = outline
pixels[50, 4] = slide_light
pixels[51, 3] = outline
pixels[51, 4] = slide_light

# Rear sight
pixels[12, 3] = outline
pixels[12, 4] = slide_light
pixels[13, 3] = outline
pixels[13, 4] = slide_light

# Ejection port
for x in range(28, 36):
    pixels[x, 5] = barrel_dark
    pixels[x, 6] = (55, 55, 55, 255)

# Frame/lower receiver - x: 10-42, y: 11-14
for x in range(10, 43):
    for y in range(11, 15):
        if y == 14:
            pixels[x, y] = outline
        elif x == 10 or x == 42:
            pixels[x, y] = outline
        else:
            pixels[x, y] = frame_color

# Trigger guard - x: 22-32, y: 14-18
for x in range(22, 33):
    if x == 22 or x == 32:
        for y in range(14, 19):
            pixels[x, y] = outline
    else:
        pixels[x, 14] = trigger_guard
        pixels[x, 18] = outline

# Trigger
pixels[27, 14] = outline
pixels[27, 15] = outline
pixels[27, 16] = outline
pixels[27, 17] = outline

# Grip - x: 10-22, y: 14-22
for x in range(10, 23):
    for y in range(14, 23):
        if y == 22:
            pixels[x, y] = outline
        elif x == 10:
            pixels[x, y] = outline
        elif x == 22:
            if y < 18:
                pixels[x, y] = outline
        elif y == 14:
            pixels[x, y] = grip_dark
        else:
            if x % 2 == 0 and y % 2 == 0:
                pixels[x, y] = grip_dark
            elif x % 2 == 1 and y % 2 == 1:
                pixels[x, y] = grip_dark
            else:
                pixels[x, y] = grip_color

# Magazine base plate
for x in range(11, 22):
    pixels[x, 22] = outline
    pixels[x, 21] = (55, 45, 35, 255)

# Grip backstrap
for y in range(15, 22):
    pixels[10, y] = outline
    pixels[11, y] = grip_light

# Hammer at rear of slide
pixels[11, 3] = outline
pixels[11, 4] = slide_color

# Slide serrations (rear)
for x in range(14, 20):
    if x % 2 == 0:
        pixels[x, 5] = barrel_dark

# Save
output_path = '/tmp/gh-issue-solver-1770470615069/assets/sprites/weapons/makarov_pm_icon.png'
img.save(output_path)
print(f"Icon saved to {output_path}")
print(f"Size: {width}x{height}")
