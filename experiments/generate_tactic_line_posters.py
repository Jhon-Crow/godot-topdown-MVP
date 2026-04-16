#!/usr/bin/env python3
"""Generate poster variants for issue #1815.

The script builds deterministic promotional art from existing repository
sprites and fonts. It intentionally does not touch any Godot scene or game
resource reference; the output PNG files are standalone assets.
"""

from __future__ import annotations

import math
import os
import random
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "assets" / "posters"

W = 1232
H = 706
TITLE = "Tactic Line"

FONT_TITLE = ROOT / "assets" / "fonts" / "neon" / "Comfortaa-Bold.ttf"
FONT_NEON = ROOT / "assets" / "fonts" / "neon" / "Beon-Regular.ttf"
FONT_ACCENT = ROOT / "assets" / "fonts" / "rye" / "Rye-Regular.ttf"

SPRITES = ROOT / "assets" / "sprites"
M16 = SPRITES / "weapons" / "m16_rifle_topdown.png"
SHOTGUN = SPRITES / "weapons" / "shotgun_topdown.png"
REVOLVER = SPRITES / "weapons" / "revolver_topdown.png"
ASVK = SPRITES / "weapons" / "asvk_topdown.png"
AK_GL = SPRITES / "weapons" / "ak_gl_topdown.png"
PKM = SPRITES / "weapons" / "pkm_topdown.png"
RPG = SPRITES / "weapons" / "rpg_topdown.png"
MINI_UZI = SPRITES / "weapons" / "mini_uzi_topdown.png"
SILENCED_PISTOL = SPRITES / "weapons" / "silenced_pistol_topdown.png"
MAKAROV = SPRITES / "weapons" / "makarov_pm_topdown.png"
MACHETE = SPRITES / "weapons" / "machete_topdown.png"
FRAG_GRENADE = SPRITES / "weapons" / "frag_grenade.png"
FLASHBANG = SPRITES / "weapons" / "flashbang.png"
CASING_RIFLE = SPRITES / "effects" / "casing_rifle.png"
CASING_PISTOL = SPRITES / "effects" / "casing_pistol.png"
CASING_SHOTGUN = SPRITES / "effects" / "casing_shotgun.png"
FLASHLIGHT = SPRITES / "effects" / "flashlight_cone_18deg.png"


@dataclass(frozen=True)
class Palette:
    bg: tuple[int, int, int]
    floor: tuple[int, int, int]
    wall: tuple[int, int, int]
    accent: tuple[int, int, int]
    accent2: tuple[int, int, int]
    text: tuple[int, int, int]
    dark: tuple[int, int, int]


NEON = Palette(
    bg=(5, 8, 11),
    floor=(15, 26, 28),
    wall=(43, 62, 58),
    accent=(232, 61, 72),
    accent2=(74, 226, 188),
    text=(245, 246, 230),
    dark=(3, 5, 7),
)

BLUEPRINT = Palette(
    bg=(4, 13, 24),
    floor=(10, 31, 46),
    wall=(34, 78, 99),
    accent=(244, 171, 54),
    accent2=(80, 210, 229),
    text=(235, 248, 252),
    dark=(2, 8, 14),
)

CQB = Palette(
    bg=(11, 9, 7),
    floor=(29, 29, 22),
    wall=(74, 62, 40),
    accent=(215, 54, 48),
    accent2=(218, 185, 86),
    text=(249, 236, 201),
    dark=(5, 4, 3),
)

RED_BLACK = Palette(
    bg=(0, 0, 0),
    floor=(15, 0, 0),
    wall=(63, 0, 0),
    accent=(255, 0, 0),
    accent2=(255, 0, 0),
    text=(255, 0, 0),
    dark=(0, 0, 0),
)


def font(path: Path, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(path), size)


def rgba(color: tuple[int, int, int], alpha: int = 255) -> tuple[int, int, int, int]:
    return color[0], color[1], color[2], alpha


def lerp(a: int, b: int, t: float) -> int:
    return int(a + (b - a) * t)


def blend(a: tuple[int, int, int], b: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    return lerp(a[0], b[0], t), lerp(a[1], b[1], t), lerp(a[2], b[2], t)


def make_base(pal: Palette, seed: int, vignette: bool = True) -> Image.Image:
    rng = random.Random(seed)
    img = Image.new("RGBA", (W, H), rgba(pal.bg))
    pix = img.load()
    center_x = W * 0.54
    center_y = H * 0.50
    max_dist = math.hypot(center_x, center_y)

    for y in range(H):
        gy = y / H
        for x in range(W):
            gx = x / W
            t = (gx * 0.56 + gy * 0.44)
            base = blend(pal.bg, pal.floor, min(1.0, t * 1.25))
            noise = rng.randint(-7, 7)
            if vignette:
                d = math.hypot(x - center_x, y - center_y) / max_dist
                shade = max(0.35, 1.0 - d * 0.95)
            else:
                shade = 1.0
            pix[x, y] = (
                max(0, min(255, int(base[0] * shade) + noise)),
                max(0, min(255, int(base[1] * shade) + noise)),
                max(0, min(255, int(base[2] * shade) + noise)),
                255,
            )

    return img


def overlay(img: Image.Image, layer: Image.Image, alpha: float = 1.0) -> None:
    if alpha < 1.0:
        layer = layer.copy()
        a = layer.getchannel("A")
        layer.putalpha(a.point(lambda v: int(v * alpha)))
    img.alpha_composite(layer)


def glow_line(
    img: Image.Image,
    xy: Iterable[tuple[float, float]],
    color: tuple[int, int, int],
    width: int,
    blur: int = 12,
    alpha: int = 255,
) -> None:
    points = list(xy)
    glow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.line(points, fill=rgba(color, alpha), width=width + blur, joint="curve")
    glow = glow.filter(ImageFilter.GaussianBlur(blur))
    overlay(img, glow, 0.65)
    draw = ImageDraw.Draw(img)
    draw.line(points, fill=rgba(color, alpha), width=width, joint="curve")


def draw_room_grid(img: Image.Image, pal: Palette, seed: int, red_black: bool = False) -> None:
    rng = random.Random(seed)
    draw = ImageDraw.Draw(img, "RGBA")

    if red_black:
        floor_fill = (10, 0, 0, 255)
        wall_fill = (105, 0, 0, 255)
        line_fill = (255, 0, 0, 45)
    else:
        floor_fill = rgba(pal.floor, 198)
        wall_fill = rgba(pal.wall, 210)
        line_fill = rgba(pal.accent2, 30)

    rooms = [
        (86, 112, 350, 308),
        (312, 92, 618, 214),
        (574, 148, 882, 358),
        (805, 94, 1122, 288),
        (170, 350, 452, 610),
        (505, 395, 741, 620),
        (764, 365, 1115, 612),
    ]
    corridors = [
        (333, 181, 600, 232),
        (380, 275, 654, 329),
        (644, 280, 840, 335),
        (306, 326, 382, 430),
        (668, 336, 720, 438),
        (806, 311, 860, 432),
    ]

    for rect in rooms + corridors:
        draw.rectangle(rect, fill=floor_fill)

    for rect in rooms:
        draw.rectangle(rect, outline=wall_fill, width=8)
    for rect in corridors:
        draw.rectangle(rect, outline=rgba(pal.wall, 120), width=3)

    for x in range(72, W, 44):
        draw.line((x, 62, x, H - 52), fill=line_fill, width=1)
    for y in range(66, H, 44):
        draw.line((54, y, W - 54, y), fill=line_fill, width=1)

    for _ in range(34):
        x = rng.randrange(80, W - 80)
        y = rng.randrange(90, H - 70)
        w = rng.randrange(14, 56)
        h = rng.randrange(8, 26)
        fill = rgba(pal.wall if not red_black else (120, 0, 0), rng.randrange(92, 170))
        draw.rectangle((x, y, x + w, y + h), fill=fill)


def draw_tactical_routes(
    img: Image.Image,
    pal: Palette,
    seed: int,
    *,
    red_black: bool = False,
    variant: int = 0,
) -> None:
    rng = random.Random(seed)
    draw = ImageDraw.Draw(img, "RGBA")
    route_color = (255, 0, 0) if red_black else pal.accent2
    alt_color = (255, 0, 0) if red_black else pal.accent
    alpha = 76 if red_black else 82
    node_alpha = 145 if red_black else 155
    routes = [
        [(150, 500), (246, 462), (342, 472), (430, 392), (566, 398), (668, 314), (808, 332), (940, 250)],
        [(250, 204), (376, 234), (520, 216), (636, 284), (760, 260), (880, 310), (1018, 284)],
        [(190, 596), (324, 552), (480, 562), (626, 512), (762, 540), (936, 474), (1070, 506)],
        [(130, 142), (286, 164), (428, 132), (566, 172), (718, 136), (878, 178), (1054, 146)],
    ]
    for i, path in enumerate(routes):
        shifted = []
        for x, y in path:
            jitter_x = rng.randrange(-10, 11)
            jitter_y = rng.randrange(-8, 9)
            shifted.append((x + jitter_x, y + jitter_y + variant * (i % 2) * 7))
        color = route_color if i % 2 == 0 else alt_color
        width = 2 if i != variant % len(routes) else 3
        draw.line(shifted, fill=rgba(color, alpha), width=width)
        for x, y in shifted:
            radius = 5 if i == variant % len(routes) else 4
            draw.ellipse((x - radius, y - radius, x + radius, y + radius), outline=rgba(color, node_alpha), width=2)
            draw.ellipse((x - 2, y - 2, x + 2, y + 2), fill=rgba(color, node_alpha))


def paste_sprite(
    img: Image.Image,
    path: Path,
    center: tuple[int, int],
    scale: int,
    angle: float,
    tint: tuple[int, int, int] | None = None,
    alpha: int = 255,
    glow: tuple[int, int, int] | None = None,
    glow_alpha: int = 115,
) -> None:
    sprite = Image.open(path).convert("RGBA")
    if tint is not None:
        alpha_channel = sprite.getchannel("A")
        gray = sprite.convert("L")
        tinted = Image.new("RGBA", sprite.size, rgba(tint, 0))
        tinted.putalpha(alpha_channel.point(lambda v: min(alpha, v)))
        sprite = Image.composite(tinted, sprite, gray.point(lambda v: 255 if v > 8 else 0))
    elif alpha != 255:
        a = sprite.getchannel("A")
        sprite.putalpha(a.point(lambda v: int(v * alpha / 255)))

    sprite = sprite.resize((sprite.width * scale, sprite.height * scale), Image.Resampling.NEAREST)
    sprite = sprite.rotate(angle, expand=True, resample=Image.Resampling.NEAREST)

    x = int(center[0] - sprite.width / 2)
    y = int(center[1] - sprite.height / 2)
    if glow is not None:
        glow_layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
        glow_sprite = Image.new("RGBA", sprite.size, rgba(glow, 0))
        glow_sprite.putalpha(sprite.getchannel("A").filter(ImageFilter.GaussianBlur(13)).point(lambda v: int(v * glow_alpha / 255)))
        glow_layer.alpha_composite(glow_sprite, (x, y))
        overlay(img, glow_layer, 1.0)

    shadow = Image.new("RGBA", sprite.size, (0, 0, 0, 0))
    shadow.putalpha(sprite.getchannel("A").filter(ImageFilter.GaussianBlur(6)))
    img.alpha_composite(shadow, (x + 10, y + 16))
    img.alpha_composite(sprite, (x, y))


def draw_soft_weapon_plinth(
    img: Image.Image,
    center: tuple[int, int],
    size: tuple[int, int],
    pal: Palette,
    *,
    red_black: bool = False,
) -> None:
    cx, cy = center
    w, h = size
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer, "RGBA")
    fill = (255, 0, 0, 52) if red_black else rgba(pal.dark, 132)
    outline = (255, 0, 0, 128) if red_black else rgba(pal.accent2, 86)
    draw.rounded_rectangle((cx - w // 2, cy - h // 2, cx + w // 2, cy + h // 2), radius=8, fill=fill, outline=outline, width=2)
    blurred = layer.filter(ImageFilter.GaussianBlur(12))
    overlay(img, blurred, 0.5)
    overlay(img, layer, 1.0)


def scatter_casings(img: Image.Image, pal: Palette, seed: int, *, red_black: bool = False) -> None:
    rng = random.Random(seed)
    casing_paths = [CASING_RIFLE, CASING_PISTOL, CASING_SHOTGUN]
    tint = (255, 0, 0) if red_black else None
    for i in range(18):
        path = casing_paths[i % len(casing_paths)]
        x = rng.randrange(120, W - 120)
        y = rng.randrange(120, H - 80)
        if 420 < x < 820 and 230 < y < 500:
            x += 230 if x < W // 2 else -230
        alpha = 180 if red_black else rng.randrange(112, 172)
        paste_sprite(img, path, (x, y), rng.choice([2, 3]), rng.randrange(0, 180), tint=tint, alpha=alpha)


def draw_armory_cross(
    img: Image.Image,
    pal: Palette,
    *,
    red_black: bool = False,
    compact: bool = False,
) -> None:
    tint = (255, 0, 0) if red_black else None
    glow = (255, 0, 0) if red_black else pal.accent2
    draw_soft_weapon_plinth(img, (620, 396), (620, 250 if compact else 300), pal, red_black=red_black)
    paste_sprite(img, ASVK, (622, 348), 9 if compact else 10, -16, tint=tint, glow=glow, glow_alpha=150)
    paste_sprite(img, AK_GL, (618, 424), 9 if compact else 10, 18, tint=tint, glow=pal.accent if not red_black else glow, glow_alpha=130)
    paste_sprite(img, SHOTGUN, (414, 492), 7, -8, tint=tint, alpha=235, glow=glow, glow_alpha=80)
    paste_sprite(img, M16, (840, 498), 7, 9, tint=tint, alpha=235, glow=glow, glow_alpha=80)
    paste_sprite(img, REVOLVER, (424, 276), 7, 21, tint=tint, alpha=230)
    paste_sprite(img, MINI_UZI, (820, 260), 7, -24, tint=tint, alpha=230)


def draw_armory_knolling(
    img: Image.Image,
    pal: Palette,
    *,
    red_black: bool = False,
) -> None:
    tint = (255, 0, 0) if red_black else None
    glow = (255, 0, 0) if red_black else pal.accent2
    draw_soft_weapon_plinth(img, (670, 410), (720, 310), pal, red_black=red_black)
    items = [
        (ASVK, (640, 276), 8, 0),
        (PKM, (640, 350), 8, 0),
        (M16, (640, 424), 8, 0),
        (SHOTGUN, (640, 500), 8, 0),
        (REVOLVER, (322, 354), 7, 0),
        (SILENCED_PISTOL, (332, 430), 7, 0),
        (MAKAROV, (335, 500), 7, 0),
        (RPG, (958, 350), 7, 0),
        (MACHETE, (956, 478), 7, 0),
    ]
    for idx, (path, center, scale, angle) in enumerate(items):
        paste_sprite(img, path, center, scale, angle, tint=tint, alpha=238, glow=glow if idx in (0, 1, 7) else None, glow_alpha=100)
    paste_sprite(img, FRAG_GRENADE, (492, 585), 5, 0, tint=tint, alpha=224)
    paste_sprite(img, FLASHBANG, (750, 585), 5, 0, tint=tint, alpha=224)


def draw_title(
    img: Image.Image,
    pal: Palette,
    xy: tuple[int, int],
    size: int,
    align: str = "left",
    glow: bool = True,
    font_path: Path = FONT_TITLE,
    stroke: int = 3,
) -> None:
    title_font = font(font_path, size)
    draw = ImageDraw.Draw(img, "RGBA")
    bbox = draw.textbbox((0, 0), TITLE, font=title_font, stroke_width=stroke)
    text_w = bbox[2] - bbox[0]
    x, y = xy
    if align == "center":
        x -= text_w // 2
    elif align == "right":
        x -= text_w

    if glow:
        glow_layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
        gd = ImageDraw.Draw(glow_layer)
        for off in range(14, 0, -3):
            gd.text(
                (x, y),
                TITLE,
                font=title_font,
                fill=rgba(pal.accent, 20 + off * 8),
                stroke_width=stroke + off // 3,
                stroke_fill=rgba(pal.accent, 20 + off * 8),
            )
        glow_layer = glow_layer.filter(ImageFilter.GaussianBlur(8))
        overlay(img, glow_layer, 0.8)

    draw.text(
        (x, y),
        TITLE,
        font=title_font,
        fill=rgba(pal.text),
        stroke_width=stroke,
        stroke_fill=rgba(pal.dark),
    )

    underline_y = y + bbox[3] - bbox[1] + 18
    glow_line(
        img,
        [(x + 8, underline_y), (x + text_w - 8, underline_y)],
        pal.accent,
        width=max(4, size // 18),
        blur=10,
        alpha=220,
    )


def add_scanlines(img: Image.Image, color: tuple[int, int, int], alpha: int = 28, step: int = 5) -> None:
    draw = ImageDraw.Draw(img, "RGBA")
    for y in range(0, H, step):
        draw.line((0, y, W, y), fill=rgba(color, alpha), width=1)


def add_corner_frame(img: Image.Image, pal: Palette, thick: int = 5) -> None:
    draw = ImageDraw.Draw(img, "RGBA")
    pad = 26
    length = 130
    for sx in (pad, W - pad):
        for sy in (pad, H - pad):
            xsign = 1 if sx == pad else -1
            ysign = 1 if sy == pad else -1
            draw.line((sx, sy, sx + xsign * length, sy), fill=rgba(pal.accent, 190), width=thick)
            draw.line((sx, sy, sx, sy + ysign * length), fill=rgba(pal.accent, 190), width=thick)


def poster_neon_crossfire() -> Image.Image:
    img = make_base(NEON, 181501)
    draw_room_grid(img, NEON, 181502)
    draw_tactical_routes(img, NEON, 181521, variant=0)

    glow_line(img, [(122, 574), (320, 570), (520, 580), (720, 566), (960, 590), (1120, 574)], NEON.accent2, 2, 8, 90)
    draw_armory_cross(img, NEON)
    scatter_casings(img, NEON, 181522)
    paste_sprite(img, FRAG_GRENADE, (1020, 180), 5, 0, alpha=220, glow=NEON.accent, glow_alpha=90)
    paste_sprite(img, FLASHBANG, (190, 430), 5, 0, alpha=210, glow=NEON.accent2, glow_alpha=70)

    add_scanlines(img, NEON.accent2, 8, 8)
    draw_title(img, NEON, (72, 54), 108, "left", True)
    add_corner_frame(img, NEON)
    return img


def poster_red_black() -> Image.Image:
    img = Image.new("RGBA", (W, H), (0, 0, 0, 255))
    draw_room_grid(img, RED_BLACK, 181503, red_black=True)
    draw = ImageDraw.Draw(img, "RGBA")

    for x in range(-250, W + 250, 80):
        draw.line((x, 0, x + 390, H), fill=(80, 0, 0, 54), width=8)
    for y in range(85, H, 75):
        draw.line((0, y, W, y), fill=(255, 0, 0, 30), width=1)

    draw_tactical_routes(img, RED_BLACK, 181523, red_black=True, variant=1)
    draw_armory_cross(img, RED_BLACK, red_black=True, compact=True)
    scatter_casings(img, RED_BLACK, 181524, red_black=True)
    paste_sprite(img, RPG, (944, 602), 6, 0, tint=RED_BLACK.accent, alpha=230)
    paste_sprite(img, MACHETE, (283, 600), 7, 0, tint=RED_BLACK.accent, alpha=230)

    title_font = font(FONT_TITLE, 118)
    bbox = draw.textbbox((0, 0), TITLE, font=title_font, stroke_width=2)
    title_w = bbox[2] - bbox[0]
    title_x = (W - title_w) // 2
    title_y = 62
    for off in (18, 12, 7):
        draw.text(
            (title_x, title_y),
            TITLE,
            font=title_font,
            fill=(255, 0, 0, 30),
            stroke_width=off,
            stroke_fill=(255, 0, 0, 24),
        )
    draw.text(
        (title_x, title_y),
        TITLE,
        font=title_font,
        fill=(255, 0, 0, 255),
        stroke_width=3,
        stroke_fill=(0, 0, 0, 255),
    )
    draw.rectangle((title_x + 4, title_y + 136, title_x + title_w - 4, title_y + 148), fill=(255, 0, 0, 255))

    add_corner_frame(img, RED_BLACK, thick=7)
    img = to_red_black(img)
    return img


def poster_blueprint() -> Image.Image:
    img = make_base(BLUEPRINT, 181504, vignette=False)
    draw_room_grid(img, BLUEPRINT, 181505)
    draw = ImageDraw.Draw(img, "RGBA")

    for r in (78, 128, 182, 246, 318):
        draw.ellipse((W // 2 - r, H // 2 - r, W // 2 + r, H // 2 + r), outline=rgba(BLUEPRINT.accent2, 36), width=2)
    for angle in range(0, 360, 15):
        a = math.radians(angle)
        draw.line(
            (W // 2, H // 2, W // 2 + math.cos(a) * 620, H // 2 + math.sin(a) * 620),
            fill=rgba(BLUEPRINT.accent2, 22),
            width=1,
        )

    draw_tactical_routes(img, BLUEPRINT, 181525, variant=2)
    draw_armory_knolling(img, BLUEPRINT)
    paste_sprite(img, FRAG_GRENADE, (496, 596), 5, 0, alpha=230, glow=BLUEPRINT.accent, glow_alpha=80)
    paste_sprite(img, FLASHBANG, (744, 596), 5, 0, alpha=220, glow=BLUEPRINT.accent2, glow_alpha=80)

    add_scanlines(img, BLUEPRINT.accent2, 9, 7)
    draw_title(img, BLUEPRINT, (616, 52), 102, "center", True, FONT_NEON, stroke=2)
    add_corner_frame(img, BLUEPRINT, thick=4)
    return img


def poster_close_quarters() -> Image.Image:
    img = make_base(CQB, 181506)
    draw_room_grid(img, CQB, 181507)
    draw_tactical_routes(img, CQB, 181526, variant=3)

    cone = Image.open(FLASHLIGHT).convert("RGBA")
    cone = cone.resize((640, 640), Image.Resampling.BILINEAR)
    cone = cone.rotate(-34, expand=True, resample=Image.Resampling.BILINEAR)
    cone = ImageEnhance.Color(cone).enhance(0.4)
    cone = ImageEnhance.Brightness(cone).enhance(1.55)
    a = cone.getchannel("A").point(lambda v: int(v * 0.25))
    cone.putalpha(a)
    img.alpha_composite(cone, (166, 120))

    draw_armory_cross(img, CQB)
    paste_sprite(img, PKM, (606, 178), 8, 6, alpha=230, glow=CQB.accent2, glow_alpha=70)
    paste_sprite(img, SILENCED_PISTOL, (955, 546), 8, -18, alpha=235)
    paste_sprite(img, MAKAROV, (270, 548), 8, 22, alpha=235)
    scatter_casings(img, CQB, 181527)

    draw_title(img, CQB, (70, 55), 106, "left", True, FONT_ACCENT, stroke=4)
    add_corner_frame(img, CQB, thick=5)
    return img


def to_red_black(img: Image.Image) -> Image.Image:
    result = Image.new("RGBA", img.size, (0, 0, 0, 255))
    src = img.convert("RGBA").load()
    dst = result.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = src[x, y]
            if a == 0:
                dst[x, y] = (0, 0, 0, 255)
                continue
            if r > 28 or (r + g + b) > 45:
                dst[x, y] = (255, 0, 0, 255)
            else:
                dst[x, y] = (0, 0, 0, 255)
    return result


def save_rgb(img: Image.Image, name: str) -> Path:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    path = OUT_DIR / name
    img.convert("RGB").save(path, optimize=True)
    return path


def make_contact_sheet(paths: list[Path]) -> Path:
    thumb_w = 560
    thumb_h = int(thumb_w * H / W)
    pad = 34
    label_h = 46
    sheet = Image.new("RGB", (thumb_w * 2 + pad * 3, (thumb_h + label_h) * 2 + pad * 3), (8, 8, 8))
    draw = ImageDraw.Draw(sheet)
    label_font = font(FONT_TITLE, 24)
    labels = [
        "Neon Arsenal",
        "Red / Black",
        "Blueprint Loadout",
        "Close Quarters Armory",
    ]
    for i, path in enumerate(paths):
        row = i // 2
        col = i % 2
        x = pad + col * (thumb_w + pad)
        y = pad + row * (thumb_h + label_h + pad)
        poster = Image.open(path).convert("RGB").resize((thumb_w, thumb_h), Image.Resampling.LANCZOS)
        sheet.paste(poster, (x, y))
        draw.rectangle((x, y, x + thumb_w, y + thumb_h), outline=(210, 40, 50), width=2)
        draw.text((x, y + thumb_h + 12), labels[i], font=label_font, fill=(236, 236, 218))
    out = OUT_DIR / "tactic_line_poster_contact_sheet.png"
    sheet.save(out, optimize=True)
    return out


def main() -> None:
    os.chdir(ROOT)
    outputs = [
        save_rgb(poster_neon_crossfire(), "tactic_line_poster_neon_crossfire.png"),
        save_rgb(poster_red_black(), "tactic_line_poster_red_black.png"),
        save_rgb(poster_blueprint(), "tactic_line_poster_blueprint.png"),
        save_rgb(poster_close_quarters(), "tactic_line_poster_close_quarters.png"),
    ]
    outputs.append(make_contact_sheet(outputs))
    for path in outputs:
        print(path.relative_to(ROOT))


if __name__ == "__main__":
    main()
