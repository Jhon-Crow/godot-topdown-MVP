#!/usr/bin/env python3
"""Generate Tactic Line poster variants for issue #1815.

The script builds deterministic promotional art from existing repository
armory sprites and fonts. It intentionally does not touch Godot scenes or
runtime resources; the output PNG files are standalone review assets.
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
WEAPON_SPRITES = SPRITES / "weapons"
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


@dataclass(frozen=True)
class WeaponSpec:
    key: str
    label: str
    path: Path
    single_scale: int
    multi_scale: int
    accent: tuple[int, int, int]


@dataclass(frozen=True)
class PosterSpec:
    filename: str
    label: str


NEON = Palette(
    bg=(5, 8, 11),
    floor=(14, 27, 29),
    wall=(47, 67, 61),
    accent=(224, 55, 68),
    accent2=(68, 214, 184),
    text=(245, 246, 230),
    dark=(3, 5, 7),
)

BLUEPRINT = Palette(
    bg=(4, 13, 24),
    floor=(10, 31, 46),
    wall=(36, 82, 103),
    accent=(238, 168, 56),
    accent2=(78, 198, 220),
    text=(235, 248, 252),
    dark=(2, 8, 14),
)

CQB = Palette(
    bg=(11, 9, 7),
    floor=(28, 29, 22),
    wall=(76, 64, 42),
    accent=(218, 185, 86),
    accent2=(64, 196, 160),
    text=(249, 236, 201),
    dark=(5, 4, 3),
)

STEEL = Palette(
    bg=(8, 10, 12),
    floor=(22, 25, 29),
    wall=(65, 70, 76),
    accent=(232, 188, 86),
    accent2=(130, 194, 196),
    text=(238, 239, 232),
    dark=(4, 5, 6),
)

GREEN = Palette(
    bg=(6, 12, 9),
    floor=(18, 32, 25),
    wall=(54, 76, 58),
    accent=(232, 180, 88),
    accent2=(118, 214, 124),
    text=(236, 242, 220),
    dark=(3, 6, 4),
)

RED_ACCENT = Palette(
    bg=(0, 0, 0),
    floor=(12, 12, 12),
    wall=(42, 42, 42),
    accent=(210, 22, 32),
    accent2=(160, 160, 160),
    text=(238, 238, 232),
    dark=(0, 0, 0),
)

# The ASVK path is the current armory menu path. The file name says "topdown",
# but the sprite itself is a side-profile armory-style icon.
ARMORY_WEAPONS: list[WeaponSpec] = [
    WeaponSpec("asvk", "ASVK", WEAPON_SPRITES / "asvk_topdown.png", 11, 7, (92, 216, 190)),
    WeaponSpec("m16", "M16", WEAPON_SPRITES / "m16_rifle.png", 10, 6, (92, 210, 236)),
    WeaponSpec("shotgun", "Shotgun", WEAPON_SPRITES / "shotgun_icon.png", 10, 6, (238, 178, 76)),
    WeaponSpec("mini_uzi", "Mini UZI", WEAPON_SPRITES / "mini_uzi_icon.png", 13, 8, (112, 222, 128)),
    WeaponSpec("silenced_pistol", "Silenced Pistol", WEAPON_SPRITES / "silenced_pistol_icon.png", 10, 6, (186, 186, 210)),
    WeaponSpec("revolver", "RSh-12", WEAPON_SPRITES / "revolver_icon.png", 10, 6, (228, 196, 96)),
    WeaponSpec("ak_gl", "AK + GL", WEAPON_SPRITES / "ak_gl_icon.png", 10, 6, (226, 138, 84)),
    WeaponSpec("makarov_pm", "Makarov PM", WEAPON_SPRITES / "makarov_pm_icon.png", 12, 7, (176, 200, 220)),
]

WEAPONS = {weapon.key: weapon for weapon in ARMORY_WEAPONS}

POSTERS: list[PosterSpec] = [
    PosterSpec("tactic_line_single_asvk.png", "Single: ASVK"),
    PosterSpec("tactic_line_single_m16.png", "Single: M16"),
    PosterSpec("tactic_line_single_shotgun.png", "Single: Shotgun"),
    PosterSpec("tactic_line_single_mini_uzi.png", "Single: Mini UZI"),
    PosterSpec("tactic_line_single_silenced_pistol.png", "Single: Silenced Pistol"),
    PosterSpec("tactic_line_single_revolver.png", "Single: RSh-12"),
    PosterSpec("tactic_line_single_ak_gl.png", "Single: AK + GL"),
    PosterSpec("tactic_line_single_makarov_pm.png", "Single: Makarov PM"),
    PosterSpec("tactic_line_multi_primary_rifles.png", "Multi: Primary Rifles"),
    PosterSpec("tactic_line_multi_sidearms.png", "Multi: Sidearms"),
    PosterSpec("tactic_line_multi_full_armory.png", "Multi: Full Armory"),
    PosterSpec("tactic_line_multi_precision_cell.png", "Multi: Precision Cell"),
    PosterSpec("tactic_line_multi_breach_cell.png", "Multi: Breach Cell"),
    PosterSpec("tactic_line_multi_quiet_entry.png", "Multi: Quiet Entry"),
    PosterSpec("tactic_line_multi_heavy_wall.png", "Multi: Heavy Wall"),
    PosterSpec("tactic_line_multi_compact_sweep.png", "Multi: Compact Sweep"),
    PosterSpec("tactic_line_multi_unlock_progression.png", "Multi: Unlock Progression"),
    PosterSpec("tactic_line_multi_balanced_loadout.png", "Multi: Balanced Loadout"),
    PosterSpec("tactic_line_red_black_asvk.png", "Red/Black: ASVK"),
    PosterSpec("tactic_line_red_black_loadout.png", "Red/Black: Loadout"),
]

LEGACY_POSTERS = [
    "tactic_line_poster_neon_crossfire.png",
    "tactic_line_poster_red_black.png",
    "tactic_line_poster_blueprint.png",
    "tactic_line_poster_close_quarters.png",
]


def font(path: Path, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(path), size)


def rgba(color: tuple[int, int, int], alpha: int = 255) -> tuple[int, int, int, int]:
    return color[0], color[1], color[2], alpha


def lerp(a: int, b: int, t: float) -> int:
    return int(a + (b - a) * t)


def blend(a: tuple[int, int, int], b: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    return lerp(a[0], b[0], t), lerp(a[1], b[1], t), lerp(a[2], b[2], t)


def make_base(pal: Palette, seed: int, *, red_black: bool = False) -> Image.Image:
    rng = random.Random(seed)
    img = Image.new("RGBA", (W, H), rgba(pal.bg))
    pix = img.load()
    center_x = W * 0.52
    center_y = H * 0.54
    max_dist = math.hypot(center_x, center_y)

    for y in range(H):
        gy = y / H
        for x in range(W):
            gx = x / W
            t = gx * 0.45 + gy * 0.55
            base = blend(pal.bg, pal.floor, min(1.0, t * 1.18))
            d = math.hypot(x - center_x, y - center_y) / max_dist
            shade = max(0.32, 1.0 - d * 0.92)
            noise = rng.randint(-5, 5)
            if red_black:
                noise = rng.randint(-3, 3)
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
    *,
    blur: int = 10,
    alpha: int = 180,
) -> None:
    points = list(xy)
    glow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.line(points, fill=rgba(color, alpha), width=width + blur, joint="curve")
    glow = glow.filter(ImageFilter.GaussianBlur(blur))
    overlay(img, glow, 0.5)
    draw = ImageDraw.Draw(img)
    draw.line(points, fill=rgba(color, alpha), width=width, joint="curve")


def draw_room_grid(img: Image.Image, pal: Palette, seed: int, *, red_black: bool = False) -> None:
    rng = random.Random(seed)
    draw = ImageDraw.Draw(img, "RGBA")
    floor_alpha = 164 if red_black else 190
    wall_alpha = 132 if red_black else 205
    line_alpha = 18 if red_black else 28

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
        draw.rectangle(rect, fill=rgba(pal.floor, floor_alpha))

    for rect in rooms:
        draw.rectangle(rect, outline=rgba(pal.wall, wall_alpha), width=8)
    for rect in corridors:
        draw.rectangle(rect, outline=rgba(pal.wall, max(70, wall_alpha - 70)), width=3)

    for x in range(72, W, 44):
        draw.line((x, 62, x, H - 52), fill=rgba(pal.accent2, line_alpha), width=1)
    for y in range(66, H, 44):
        draw.line((54, y, W - 54, y), fill=rgba(pal.accent2, line_alpha), width=1)

    for _ in range(28):
        x = rng.randrange(80, W - 80)
        y = rng.randrange(96, H - 70)
        w = rng.randrange(14, 56)
        h = rng.randrange(8, 26)
        draw.rectangle((x, y, x + w, y + h), fill=rgba(pal.wall, rng.randrange(52, 122)))


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
    route_color = pal.accent if red_black else pal.accent2
    alt_color = pal.accent2 if red_black else pal.accent
    alpha = 42 if red_black else 66
    node_alpha = 86 if red_black else 128
    routes = [
        [(140, 500), (246, 462), (342, 472), (430, 392), (566, 398), (668, 314), (808, 332), (940, 250)],
        [(250, 204), (376, 234), (520, 216), (636, 284), (760, 260), (880, 310), (1018, 284)],
        [(190, 596), (324, 552), (480, 562), (626, 512), (762, 540), (936, 474), (1070, 506)],
        [(130, 142), (286, 164), (428, 132), (566, 172), (718, 136), (878, 178), (1054, 146)],
    ]
    for i, path in enumerate(routes):
        shifted = []
        for x, y in path:
            shifted.append((x + rng.randrange(-9, 10), y + rng.randrange(-7, 8) + variant * (i % 2) * 4))
        color = route_color if i % 2 == 0 else alt_color
        draw.line(shifted, fill=rgba(color, alpha), width=2)
        for x, y in shifted:
            radius = 5 if i == variant % len(routes) else 4
            draw.ellipse((x - radius, y - radius, x + radius, y + radius), outline=rgba(color, node_alpha), width=2)
            draw.ellipse((x - 2, y - 2, x + 2, y + 2), fill=rgba(color, node_alpha))


def add_scanlines(img: Image.Image, color: tuple[int, int, int], *, alpha: int = 18, step: int = 7) -> None:
    draw = ImageDraw.Draw(img, "RGBA")
    for y in range(0, H, step):
        draw.line((0, y, W, y), fill=rgba(color, alpha), width=1)


def add_corner_frame(img: Image.Image, pal: Palette, *, thick: int = 4, red_black: bool = False) -> None:
    draw = ImageDraw.Draw(img, "RGBA")
    pad = 28
    length = 122
    alpha = 126 if red_black else 172
    for sx in (pad, W - pad):
        for sy in (pad, H - pad):
            xsign = 1 if sx == pad else -1
            ysign = 1 if sy == pad else -1
            draw.line((sx, sy, sx + xsign * length, sy), fill=rgba(pal.accent, alpha), width=thick)
            draw.line((sx, sy, sx, sy + ysign * length), fill=rgba(pal.accent, alpha), width=thick)


def draw_title(
    img: Image.Image,
    pal: Palette,
    xy: tuple[int, int],
    size: int,
    *,
    align: str = "left",
    red_black: bool = False,
    font_path: Path = FONT_TITLE,
) -> None:
    title_font = font(font_path, size)
    draw = ImageDraw.Draw(img, "RGBA")
    bbox = draw.textbbox((0, 0), TITLE, font=title_font, stroke_width=3)
    text_w = bbox[2] - bbox[0]
    x, y = xy
    if align == "center":
        x -= text_w // 2
    elif align == "right":
        x -= text_w

    glow_alpha = 42 if red_black else 72
    glow_layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow_layer)
    for off in range(12, 0, -3):
        gd.text(
            (x, y),
            TITLE,
            font=title_font,
            fill=rgba(pal.accent, glow_alpha),
            stroke_width=3 + off // 3,
            stroke_fill=rgba(pal.accent, glow_alpha),
        )
    glow_layer = glow_layer.filter(ImageFilter.GaussianBlur(8))
    overlay(img, glow_layer, 0.62)

    fill = pal.accent if red_black else pal.text
    draw.text(
        (x, y),
        TITLE,
        font=title_font,
        fill=rgba(fill),
        stroke_width=3,
        stroke_fill=rgba(pal.dark),
    )

    underline_y = y + bbox[3] - bbox[1] + 16
    glow_line(
        img,
        [(x + 8, underline_y), (x + text_w - 8, underline_y)],
        pal.accent,
        width=max(4, size // 20),
        blur=9,
        alpha=166 if red_black else 205,
    )


def draw_focus_field(
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
    fill = rgba(pal.dark, 120 if not red_black else 170)
    outline = rgba(pal.accent if red_black else pal.accent2, 80 if red_black else 100)
    draw.ellipse((cx - w // 2, cy - h // 2, cx + w // 2, cy + h // 2), fill=fill, outline=outline, width=3)
    blurred = layer.filter(ImageFilter.GaussianBlur(18))
    overlay(img, blurred, 0.72)
    overlay(img, layer, 0.82)


def load_weapon_sprite(path: Path, scale: int, angle: float = 0) -> Image.Image:
    sprite = Image.open(path).convert("RGBA")
    alpha = sprite.getchannel("A")
    rgb = ImageEnhance.Brightness(sprite.convert("RGB")).enhance(1.22)
    rgb = ImageEnhance.Contrast(rgb).enhance(1.08)
    sprite = rgb.convert("RGBA")
    sprite.putalpha(alpha)
    sprite = sprite.resize((sprite.width * scale, sprite.height * scale), Image.Resampling.NEAREST)
    if angle:
        sprite = sprite.rotate(angle, expand=True, resample=Image.Resampling.NEAREST)
    return sprite


def paste_weapon(
    img: Image.Image,
    weapon: WeaponSpec,
    center: tuple[int, int],
    scale: int,
    *,
    angle: float = 0,
    alpha: int = 255,
    glow: tuple[int, int, int] | None = None,
    red_outline: bool = False,
) -> None:
    sprite = load_weapon_sprite(weapon.path, scale, angle)
    if alpha != 255:
        a = sprite.getchannel("A")
        sprite.putalpha(a.point(lambda v: int(v * alpha / 255)))

    x = int(center[0] - sprite.width / 2)
    y = int(center[1] - sprite.height / 2)
    mask = sprite.getchannel("A")

    if glow is not None:
        glow_layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
        glow_sprite = Image.new("RGBA", sprite.size, rgba(glow, 0))
        glow_sprite.putalpha(mask.filter(ImageFilter.GaussianBlur(15)).point(lambda v: int(v * 0.7)))
        glow_layer.alpha_composite(glow_sprite, (x, y))
        overlay(img, glow_layer, 0.84)

    shadow = Image.new("RGBA", sprite.size, (0, 0, 0, 0))
    shadow.putalpha(mask.filter(ImageFilter.GaussianBlur(6)).point(lambda v: int(v * 0.62)))
    img.alpha_composite(shadow, (x + 10, y + 15))

    if red_outline:
        outline = Image.new("RGBA", sprite.size, (0, 0, 0, 0))
        outline_mask = mask.filter(ImageFilter.MaxFilter(5))
        outline.putalpha(outline_mask.point(lambda v: min(120, v)))
        red = Image.new("RGBA", sprite.size, rgba(RED_ACCENT.accent, 0))
        red.putalpha(outline.getchannel("A"))
        img.alpha_composite(red, (x, y))

    img.alpha_composite(sprite, (x, y))


def draw_weapon_label(
    img: Image.Image,
    pal: Palette,
    label: str,
    *,
    red_black: bool = False,
    y: int = 596,
) -> None:
    label_font = font(FONT_NEON if red_black else FONT_TITLE, 34)
    draw = ImageDraw.Draw(img, "RGBA")
    bbox = draw.textbbox((0, 0), label, font=label_font, stroke_width=2)
    w = bbox[2] - bbox[0]
    x = W // 2 - w // 2
    fill = pal.accent if red_black else pal.text
    draw.text((x, y), label, font=label_font, fill=rgba(fill, 232), stroke_width=2, stroke_fill=rgba(pal.dark, 240))


def scatter_casings(img: Image.Image, pal: Palette, seed: int, *, sparse: bool = True) -> None:
    rng = random.Random(seed)
    count = 8 if sparse else 16
    casing_paths = [CASING_RIFLE, CASING_PISTOL, CASING_SHOTGUN]
    for i in range(count):
        path = casing_paths[i % len(casing_paths)]
        x = rng.randrange(130, W - 130)
        y = rng.randrange(145, H - 88)
        if 330 < x < 900 and 250 < y < 520:
            y += 160 if y < H // 2 else -160
        weapon = WeaponSpec("casing", "Casing", path, 1, 1, pal.accent)
        paste_weapon(img, weapon, (x, y), rng.choice([2, 3]), angle=rng.randrange(0, 180), alpha=rng.randrange(96, 150))


def add_flashlight_wash(img: Image.Image, pal: Palette, *, alpha: float = 0.18) -> None:
    cone = Image.open(FLASHLIGHT).convert("RGBA")
    cone = cone.resize((620, 620), Image.Resampling.BILINEAR)
    cone = cone.rotate(-35, expand=True, resample=Image.Resampling.BILINEAR)
    cone = ImageEnhance.Color(cone).enhance(0.3)
    cone = ImageEnhance.Brightness(cone).enhance(1.35)
    a = cone.getchannel("A").point(lambda v: int(v * alpha))
    cone.putalpha(a)
    img.alpha_composite(cone, (170, 126))


def prepare_canvas(pal: Palette, seed: int, *, red_black: bool = False, route_variant: int = 0) -> Image.Image:
    img = make_base(pal, seed, red_black=red_black)
    draw_room_grid(img, pal, seed + 1, red_black=red_black)
    draw_tactical_routes(img, pal, seed + 2, red_black=red_black, variant=route_variant)
    if not red_black and seed % 2 == 0:
        add_flashlight_wash(img, pal, alpha=0.14)
    add_scanlines(img, pal.accent2, alpha=7 if red_black else 9, step=8)
    return img


def single_poster(weapon: WeaponSpec, pal: Palette, seed: int, *, red_black: bool = False) -> Image.Image:
    img = prepare_canvas(pal, seed, red_black=red_black, route_variant=seed % 4)
    draw_focus_field(img, (W // 2, 392), (900, 285), pal, red_black=red_black)
    draw_title(img, pal, (66, 54), 104, red_black=red_black, font_path=FONT_TITLE if not red_black else FONT_NEON)
    glow = pal.accent if red_black else weapon.accent
    paste_weapon(
        img,
        weapon,
        (W // 2, 386),
        weapon.single_scale,
        glow=glow,
        red_outline=red_black,
    )
    draw_weapon_label(img, pal, weapon.label, red_black=red_black)
    scatter_casings(img, pal, seed + 9, sparse=True)
    add_corner_frame(img, pal, red_black=red_black, thick=5 if red_black else 4)
    return img


def draw_multi_row(
    img: Image.Image,
    weapons: list[WeaponSpec],
    centers: list[tuple[int, int]],
    pal: Palette,
    *,
    red_black: bool = False,
    highlight: str | None = None,
) -> None:
    for weapon, center in zip(weapons, centers):
        scale = weapon.multi_scale
        is_highlight = highlight == weapon.key
        paste_weapon(
            img,
            weapon,
            center,
            scale + (1 if is_highlight else 0),
            alpha=255 if is_highlight else 232,
            glow=pal.accent if red_black else (weapon.accent if is_highlight else pal.accent2),
            red_outline=red_black and is_highlight,
        )


def multi_poster(
    keys: list[str],
    pal: Palette,
    seed: int,
    label: str,
    *,
    layout: str = "stack",
    red_black: bool = False,
    highlight: str | None = None,
) -> Image.Image:
    img = prepare_canvas(pal, seed, red_black=red_black, route_variant=seed % 4)
    draw_focus_field(img, (W // 2, 405), (960, 370), pal, red_black=red_black)
    draw_title(img, pal, (66, 52), 100, red_black=red_black, font_path=FONT_NEON if red_black else FONT_TITLE)
    weapons = [WEAPONS[key] for key in keys]

    if layout == "full":
        centers = [
            (448, 288),
            (780, 288),
            (448, 372),
            (780, 372),
            (448, 456),
            (780, 456),
            (448, 540),
            (780, 540),
        ]
        draw_multi_row(img, weapons, centers, pal, red_black=red_black, highlight=highlight)
    elif layout == "line":
        centers = [(W // 2, 286), (W // 2, 376), (W // 2, 466), (W // 2, 556)]
        draw_multi_row(img, weapons, centers[: len(weapons)], pal, red_black=red_black, highlight=highlight)
    elif layout == "two_column":
        centers = [(430, 330), (800, 330), (430, 470), (800, 470)]
        draw_multi_row(img, weapons, centers[: len(weapons)], pal, red_black=red_black, highlight=highlight)
    else:
        start_y = 302 if len(weapons) <= 3 else 278
        step = 94 if len(weapons) <= 3 else 82
        centers = [(W // 2, start_y + i * step) for i in range(len(weapons))]
        draw_multi_row(img, weapons, centers, pal, red_black=red_black, highlight=highlight)

    draw_weapon_label(img, pal, label, red_black=red_black, y=602)
    scatter_casings(img, pal, seed + 11, sparse=True)
    add_corner_frame(img, pal, red_black=red_black, thick=5 if red_black else 4)
    return img


def save_rgb(img: Image.Image, name: str) -> Path:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    path = OUT_DIR / name
    img.convert("RGB").save(path, optimize=True)
    return path


def make_contact_sheet(paths: list[Path]) -> Path:
    thumb_w = 300
    thumb_h = int(thumb_w * H / W)
    pad = 22
    label_h = 42
    cols = 5
    rows = 4
    sheet = Image.new("RGB", (thumb_w * cols + pad * (cols + 1), (thumb_h + label_h) * rows + pad * (rows + 1)), (8, 8, 8))
    draw = ImageDraw.Draw(sheet)
    label_font = font(FONT_TITLE, 18)

    for i, path in enumerate(paths):
        row = i // cols
        col = i % cols
        x = pad + col * (thumb_w + pad)
        y = pad + row * (thumb_h + label_h + pad)
        poster = Image.open(path).convert("RGB").resize((thumb_w, thumb_h), Image.Resampling.LANCZOS)
        sheet.paste(poster, (x, y))
        draw.rectangle((x, y, x + thumb_w, y + thumb_h), outline=(160, 44, 50), width=2)
        label = POSTERS[i].label
        if len(label) > 28:
            label = label[:25] + "..."
        draw.text((x, y + thumb_h + 10), label, font=label_font, fill=(236, 236, 218))

    out = OUT_DIR / "tactic_line_poster_contact_sheet.png"
    sheet.save(out, optimize=True)
    return out


def remove_legacy_outputs() -> None:
    for filename in LEGACY_POSTERS:
        path = OUT_DIR / filename
        if path.exists():
            path.unlink()


def generate_posters() -> list[Path]:
    outputs = [
        save_rgb(single_poster(WEAPONS["asvk"], NEON, 181601), "tactic_line_single_asvk.png"),
        save_rgb(single_poster(WEAPONS["m16"], BLUEPRINT, 181602), "tactic_line_single_m16.png"),
        save_rgb(single_poster(WEAPONS["shotgun"], CQB, 181603), "tactic_line_single_shotgun.png"),
        save_rgb(single_poster(WEAPONS["mini_uzi"], GREEN, 181604), "tactic_line_single_mini_uzi.png"),
        save_rgb(single_poster(WEAPONS["silenced_pistol"], STEEL, 181605), "tactic_line_single_silenced_pistol.png"),
        save_rgb(single_poster(WEAPONS["revolver"], CQB, 181606), "tactic_line_single_revolver.png"),
        save_rgb(single_poster(WEAPONS["ak_gl"], NEON, 181607), "tactic_line_single_ak_gl.png"),
        save_rgb(single_poster(WEAPONS["makarov_pm"], BLUEPRINT, 181608), "tactic_line_single_makarov_pm.png"),
        save_rgb(
            multi_poster(["asvk", "m16", "ak_gl"], BLUEPRINT, 181609, "Primary Rifles", layout="line", highlight="asvk"),
            "tactic_line_multi_primary_rifles.png",
        ),
        save_rgb(
            multi_poster(["makarov_pm", "silenced_pistol", "revolver", "mini_uzi"], STEEL, 181610, "Sidearms", layout="two_column"),
            "tactic_line_multi_sidearms.png",
        ),
        save_rgb(
            multi_poster([w.key for w in ARMORY_WEAPONS], GREEN, 181611, "Full Armory", layout="full", highlight="asvk"),
            "tactic_line_multi_full_armory.png",
        ),
        save_rgb(
            multi_poster(["asvk", "revolver", "silenced_pistol"], NEON, 181612, "Precision Cell", layout="line", highlight="asvk"),
            "tactic_line_multi_precision_cell.png",
        ),
        save_rgb(
            multi_poster(["shotgun", "ak_gl", "m16"], CQB, 181613, "Breach Cell", layout="line", highlight="shotgun"),
            "tactic_line_multi_breach_cell.png",
        ),
        save_rgb(
            multi_poster(["silenced_pistol", "makarov_pm", "mini_uzi"], BLUEPRINT, 181614, "Quiet Entry", layout="line", highlight="silenced_pistol"),
            "tactic_line_multi_quiet_entry.png",
        ),
        save_rgb(
            multi_poster(["asvk", "revolver", "ak_gl"], STEEL, 181615, "Heavy Wall", layout="line", highlight="revolver"),
            "tactic_line_multi_heavy_wall.png",
        ),
        save_rgb(
            multi_poster(["mini_uzi", "makarov_pm", "shotgun"], GREEN, 181616, "Compact Sweep", layout="line", highlight="mini_uzi"),
            "tactic_line_multi_compact_sweep.png",
        ),
        save_rgb(
            multi_poster(["makarov_pm", "m16", "shotgun", "asvk"], NEON, 181617, "Unlock Progression", layout="line", highlight="asvk"),
            "tactic_line_multi_unlock_progression.png",
        ),
        save_rgb(
            multi_poster(["m16", "shotgun", "silenced_pistol", "revolver"], CQB, 181618, "Balanced Loadout", layout="two_column"),
            "tactic_line_multi_balanced_loadout.png",
        ),
        save_rgb(single_poster(WEAPONS["asvk"], RED_ACCENT, 181619, red_black=True), "tactic_line_red_black_asvk.png"),
        save_rgb(
            multi_poster(["asvk", "m16", "revolver"], RED_ACCENT, 181620, "Redline Loadout", layout="line", red_black=True, highlight="asvk"),
            "tactic_line_red_black_loadout.png",
        ),
    ]
    make_contact_sheet(outputs)
    return outputs


def main() -> None:
    os.chdir(ROOT)
    remove_legacy_outputs()
    outputs = generate_posters()
    for path in outputs + [OUT_DIR / "tactic_line_poster_contact_sheet.png"]:
        print(path.relative_to(ROOT))


if __name__ == "__main__":
    main()
