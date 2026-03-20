#!/usr/bin/env python3
"""
Create unique pixel-art icon for Experimental Sample active item.
Concept: a glowing flask/beaker with a "?" inside the liquid,
colorful sparks around it = random/experimental effects.
64x64 RGBA PNG, consistent with other item icons in the project.
"""
from PIL import Image, ImageDraw

SIZE = 64
img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
draw = ImageDraw.Draw(img)

# Palette
OUTLINE     = (15,  8, 25, 255)
GLASS_FILL  = (200, 235, 255, 180)
GLASS_SHINE = (240, 250, 255, 220)
GLASS_DARK  = (100, 160, 210, 160)
LIQ_MID    = (130,  40, 200, 255)
LIQ_LITE   = (190,  80, 255, 255)
LIQ_DARK   = ( 80,  20, 140, 255)
CORK_MAIN  = (185, 135,  70, 255)
CORK_DARK  = (120,  80,  30, 255)
CORK_LITE  = (220, 175, 105, 255)
SPARK_YEL  = (255, 230,  40, 255)
SPARK_PNK  = (255,  60, 200, 255)
SPARK_CYN  = ( 50, 220, 255, 255)
SPARK_GRN  = ( 50, 255, 130, 255)
QMARK_COL  = (255, 255, 200, 255)
QMARK_OUT  = ( 40,  10,  60, 255)
BUBBLE_YEL = (255, 215,  50, 230)
BUBBLE_ORG = (255, 130,  30, 230)


def px(x, y, color):
    draw.point((x, y), fill=color)

def hline(x1, x2, y, color):
    draw.rectangle([x1, y, x2, y], fill=color)

def vline(x, y1, y2, color):
    draw.rectangle([x, y1, x, y2], fill=color)

def rect_fill(x1, y1, x2, y2, color):
    draw.rectangle([x1, y1, x2, y2], fill=color)


# ── FLASK BODY ────────────────────────────────────────────────
# Neck: columns 27–36, rows 12–22
# Body: columns 14–49, rows 23–50

# -- neck fill (glass) --
rect_fill(28, 13, 35, 22, GLASS_FILL)
hline(28, 35, 12, OUTLINE)   # neck top
vline(27, 13, 22, OUTLINE)   # neck left wall
vline(36, 13, 22, OUTLINE)   # neck right wall

# -- shoulder (rows 22-26, widening) --
shoulder_spans = [(27, 36), (24, 39), (21, 42), (18, 45), (15, 48)]
for i, (xl, xr) in enumerate(shoulder_spans):
    y = 22 + i
    rect_fill(xl+1, y, xr-1, y, GLASS_FILL)
    px(xl, y, OUTLINE)
    px(xr, y, OUTLINE)

# -- body fill --
rect_fill(15, 27, 48, 50, GLASS_FILL)
# body sides
vline(14, 27, 50, OUTLINE)
vline(49, 27, 50, OUTLINE)
# body bottom
hline(14, 49, 51, OUTLINE)

# -- liquid (lower 60% of body) --
LIQ_TOP = 34
rect_fill(15, LIQ_TOP, 48, 50, LIQ_MID)
# liquid highlight (left-center band)
rect_fill(16, LIQ_TOP+1, 24, 49, LIQ_LITE)
# liquid surface waviness
for x in range(15, 49):
    wave = LIQ_TOP + (1 if (x % 4 < 2) else 0)
    px(x, wave, LIQ_DARK)

# Bubble 1 (yellow, right side)
rect_fill(38, 43, 40, 45, BUBBLE_YEL)
hline(38, 40, 42, OUTLINE); hline(38, 40, 46, OUTLINE)
vline(37, 43, 45, OUTLINE); vline(41, 43, 45, OUTLINE)
px(39, 43, (255, 245, 180, 255))  # shine

# Bubble 2 (orange, left)
rect_fill(20, 46, 22, 48, BUBBLE_ORG)
hline(20, 22, 45, OUTLINE); hline(20, 22, 49, OUTLINE)
vline(19, 46, 48, OUTLINE); vline(23, 46, 48, OUTLINE)

# Glass shine strips
rect_fill(16, 28, 17, 50, GLASS_SHINE)   # body left shine
rect_fill(29, 13, 30, 22, GLASS_SHINE)   # neck shine

# Glass dark edge (right side)
rect_fill(46, 28, 47, 50, GLASS_DARK)

# ── CORK ────────────────────────────────────────────────────
rect_fill(28,  8, 35, 12, CORK_MAIN)
px(27, 9, CORK_MAIN); px(27,10, CORK_MAIN); px(27,11, CORK_MAIN)
px(36, 9, CORK_MAIN); px(36,10, CORK_MAIN); px(36,11, CORK_MAIN)
# cork outline
hline(28, 35,  7, OUTLINE)
vline(27,  8, 12, OUTLINE)
vline(36,  8, 12, OUTLINE)
hline(27, 36, 13, OUTLINE)   # bottom edge shared with neck
# cork shine
hline(29, 33,  8, CORK_LITE)
hline(29, 33,  9, CORK_LITE)
# cork dark band
hline(28, 35, 11, CORK_DARK)

# ── QUESTION MARK (centered in liquid zone) ─────────────────
# 7-pixel-tall "?" centered around x=31,y=36..47
# Drawn in white/cream for visibility over dark liquid
Q = QMARK_COL
QO = QMARK_OUT

# Top arc of "?"
arc = [
    # row 37
    (29,37),(30,37),(31,37),(32,37),(33,37),
    # row 38
    (28,38),(34,38),
    # row 39
    (28,39),(34,39),
    # row 40 - right side curls down
    (33,40),(34,40),
    # row 41
    (32,41),(33,41),
    # row 42 - stem
    (31,42),(32,42),
    # row 43
    (31,43),
    # gap row 44
    # dot rows 45-46
    (31,45),(32,45),
    (31,46),(32,46),
]
# outline Q mark pixels (dark halo)
arc_set = set(arc)
for (ax, ay) in arc:
    for (dx, dy) in [(-1,0),(1,0),(0,-1),(0,1),(-1,-1),(1,-1),(-1,1),(1,1)]:
        nx, ny = ax+dx, ay+dy
        if (nx,ny) not in arc_set:
            if img.getpixel((nx,ny))[3] > 50:  # only draw outline over opaque pixels
                px(nx, ny, QO)

# draw Q mark pixels on top
for (ax, ay) in arc:
    px(ax, ay, Q)

# ── SPARKLES around flask ────────────────────────────────────
def star4(cx, cy, color):
    """4-point cross star."""
    px(cx, cy, color)
    px(cx-1, cy, color); px(cx+1, cy, color)
    px(cx, cy-1, color); px(cx, cy+1, color)
    px(cx-2, cy, color); px(cx+2, cy, color)
    px(cx, cy-2, color); px(cx, cy+2, color)
    # outline
    for (dx,dy) in [(-3,0),(3,0),(0,-3),(0,3),
                    (-1,-1),(1,-1),(-1,1),(1,1),
                    (-2,-1),(2,-1),(-2,1),(2,1),
                    (-1,-2),(1,-2),(-1,2),(1,2)]:
        nx,ny = cx+dx, cy+dy
        if img.getpixel((nx,ny))[3] < 30:
            px(nx, ny, OUTLINE)

def star2(cx, cy, color):
    """Small 2px cross star."""
    px(cx, cy, color)
    px(cx-1, cy, color); px(cx+1, cy, color)
    px(cx, cy-1, color); px(cx, cy+1, color)

star4(6,  19, SPARK_YEL)
star4(57, 17, SPARK_PNK)
star4(5,  43, SPARK_CYN)
star4(57, 44, SPARK_GRN)

star2(11,  6, SPARK_PNK)
star2(52,  7, SPARK_CYN)
star2( 9, 56, SPARK_GRN)
star2(54, 57, SPARK_YEL)
star2( 4, 30, SPARK_YEL)
star2(59, 31, SPARK_PNK)

# tiny single pixels (scatter)
px(13, 52, SPARK_CYN)
px(50, 53, SPARK_YEL)
px( 7, 50, SPARK_GRN)
px(56, 50, SPARK_PNK)

# ── SAVE ─────────────────────────────────────────────────────
output = "/tmp/gh-issue-solver-1773808878814/assets/sprites/weapons/experimental_sample_icon.png"
img.save(output, "PNG")
print(f"Saved: {output}  size={img.size}  mode={img.mode}")
