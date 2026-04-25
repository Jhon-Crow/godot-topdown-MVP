#!/usr/bin/env python3
"""Generate 40 experimental Tactic Line poster variants for issue #1815.

The output is deterministic promotional artwork built from existing
repository assets. It intentionally does not touch Godot scenes or runtime
resources; the PNG files are standalone review assets.
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

FONT_TITLE = ROOT / "assets" / "fonts" / "rye" / "Rye-Regular.ttf"
FONT_SANS = ROOT / "assets" / "fonts" / "neon" / "Comfortaa-Bold.ttf"

SPRITES = ROOT / "assets" / "sprites"
WEAPON_SPRITES = SPRITES / "weapons"
RIFLE = WEAPON_SPRITES / "asvk_topdown.png"
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
class TitleLayout:
    anchor: tuple[int, int]
    align: str
    size: int
    layer: str
    tone: str = "cream"
    underline: str = "full"
    stroke: int = 4
    glow_alpha: int = 96


@dataclass(frozen=True)
class PosterVariant:
    filename: str
    label: str
    seed: int
    center: tuple[int, int]
    scale: int
    angle: float
    glow: tuple[int, int, int]
    route_variant: int
    route_alpha: int
    node_alpha: int
    light_alpha: float
    title: TitleLayout
    brightness: float = 1.18
    contrast: float = 1.08
    grid_alpha: int = 30
    frame_alpha: int = 190
    route_shift: tuple[int, int] = (0, 0)
    background_darkness: float = 1.0


CQB = Palette(
    bg=(11, 9, 7),
    floor=(29, 29, 22),
    wall=(74, 62, 40),
    accent=(215, 54, 48),
    accent2=(218, 185, 86),
    text=(249, 236, 201),
    dark=(5, 4, 3),
)


def title(anchor: tuple[int, int], align: str, size: int, layer: str, tone: str = "cream", underline: str = "full") -> TitleLayout:
    return TitleLayout(anchor, align, size, layer, tone, underline)


POSTER_VARIANTS: tuple[PosterVariant, ...] = (
    PosterVariant("tactic_line_poster_close_quarters.png", "01 Top Left Classic", 181801, (620, 382), 12, 0, CQB.accent2, 0, 58, 128, 0.20, title((70, 55), "left", 106, "under_weapon")),
    PosterVariant("tactic_line_experiment_02.png", "02 Top Center", 181802, (620, 386), 12, -1, CQB.accent2, 1, 54, 118, 0.16, title((W // 2, 44), "center", 108, "under_weapon")),
    PosterVariant("tactic_line_experiment_03.png", "03 Center Over", 181803, (620, 382), 12, 1, CQB.accent2, 2, 46, 112, 0.22, title((W // 2, 262), "center", 132, "over_weapon", "cream", "short")),
    PosterVariant("tactic_line_experiment_04.png", "04 Center Under", 181804, (618, 380), 12, 0, CQB.accent, 3, 48, 112, 0.14, title((W // 2, 278), "center", 144, "under_weapon", "cream", "none")),
    PosterVariant("tactic_line_experiment_05.png", "05 Bottom Center", 181805, (618, 318), 12, 0, CQB.accent2, 0, 56, 126, 0.18, title((W // 2, 520), "center", 108, "over_weapon")),
    PosterVariant("tactic_line_experiment_06.png", "06 Tight Left", 181806, (636, 390), 13, -2, (236, 214, 132), 1, 42, 108, 0.12, title((64, 64), "left", 96, "under_weapon", "gold")),
    PosterVariant("tactic_line_experiment_07.png", "07 Top Right", 181807, (602, 388), 12, 2, CQB.accent, 2, 62, 136, 0.20, title((1166, 52), "right", 98, "under_weapon")),
    PosterVariant("tactic_line_experiment_08.png", "08 Low Left", 181808, (696, 334), 12, -4, CQB.accent2, 3, 50, 116, 0.17, title((78, 482), "left", 98, "over_weapon", "gold", "short")),
    PosterVariant("tactic_line_experiment_09.png", "09 Tall Center", 181809, (616, 390), 11, 2, CQB.accent, 0, 42, 106, 0.11, title((W // 2, 182), "center", 154, "under_weapon", "cream", "none"), background_darkness=0.94),
    PosterVariant("tactic_line_experiment_10.png", "10 Gold Center", 181810, (618, 392), 12, -1, (232, 204, 116), 1, 64, 142, 0.22, title((W // 2, 304), "center", 124, "under_weapon", "gold", "full")),
    PosterVariant("tactic_line_experiment_11.png", "11 Small Title", 181811, (628, 374), 13, 0, CQB.accent2, 2, 36, 96, 0.10, title((74, 74), "left", 78, "under_weapon", "cream", "short"), background_darkness=0.90),
    PosterVariant("tactic_line_experiment_12.png", "12 Midline Front", 181812, (618, 380), 12, 0, CQB.accent, 3, 52, 122, 0.24, title((W // 2, 326), "center", 110, "over_weapon", "cream", "full")),
    PosterVariant("tactic_line_experiment_13.png", "13 Bottom Right", 181813, (588, 336), 11, 4, CQB.accent2, 0, 44, 108, 0.14, title((1148, 508), "right", 88, "over_weapon", "gold", "short")),
    PosterVariant("tactic_line_experiment_14.png", "14 Behind Rifle", 181814, (620, 386), 13, 0, (236, 214, 132), 1, 40, 102, 0.16, title((W // 2, 244), "center", 164, "under_weapon", "cream", "none")),
    PosterVariant("tactic_line_experiment_15.png", "15 Red Glow", 181815, (620, 382), 12, -1, CQB.accent, 2, 58, 130, 0.20, title((W // 2, 50), "center", 104, "under_weapon", "cream", "full"), frame_alpha=220),
    PosterVariant("tactic_line_experiment_16.png", "16 Low Gold", 181816, (624, 316), 12, 1, CQB.accent2, 3, 70, 148, 0.18, title((W // 2, 534), "center", 100, "over_weapon", "gold", "full")),
    PosterVariant("tactic_line_experiment_17.png", "17 Split Line", 181817, (620, 392), 12, 0, CQB.accent2, 0, 46, 110, 0.15, title((72, 58), "left", 104, "under_weapon", "cream", "split")),
    PosterVariant("tactic_line_experiment_18.png", "18 Clean Center", 181818, (618, 382), 12, 0, (190, 160, 78), 1, 28, 88, 0.06, title((W // 2, 282), "center", 132, "under_weapon", "cream", "none"), background_darkness=0.88),
    PosterVariant("tactic_line_experiment_19.png", "19 Heavy Frame", 181819, (622, 384), 12, -2, CQB.accent, 2, 52, 118, 0.18, title((76, 56), "left", 104, "under_weapon"), frame_alpha=235),
    PosterVariant("tactic_line_experiment_20.png", "20 Dim Map", 181820, (640, 380), 12, 2, CQB.accent2, 3, 34, 96, 0.08, title((W // 2, 56), "center", 112, "under_weapon", "gold", "short"), background_darkness=0.84),
    PosterVariant("tactic_line_experiment_21.png", "21 High Rifle", 181821, (620, 310), 12, 0, CQB.accent2, 0, 56, 126, 0.21, title((W // 2, 512), "center", 116, "over_weapon", "cream", "full")),
    PosterVariant("tactic_line_experiment_22.png", "22 Low Rifle", 181822, (620, 438), 12, 0, CQB.accent, 1, 50, 116, 0.13, title((W // 2, 52), "center", 116, "under_weapon", "cream", "short")),
    PosterVariant("tactic_line_experiment_23.png", "23 Diagonal Down", 181823, (626, 386), 12, -6, CQB.accent2, 2, 58, 132, 0.18, title((72, 66), "left", 94, "under_weapon", "gold", "full")),
    PosterVariant("tactic_line_experiment_24.png", "24 Diagonal Up", 181824, (612, 388), 12, 6, CQB.accent, 3, 58, 132, 0.20, title((1160, 496), "right", 94, "over_weapon", "cream", "short")),
    PosterVariant("tactic_line_experiment_25.png", "25 Left Rifle", 181825, (462, 384), 12, 0, CQB.accent2, 0, 44, 112, 0.14, title((1088, 170), "right", 112, "over_weapon", "cream", "full"), route_shift=(70, 0)),
    PosterVariant("tactic_line_experiment_26.png", "26 Right Rifle", 181826, (774, 382), 12, 0, CQB.accent, 1, 44, 112, 0.14, title((82, 166), "left", 112, "over_weapon", "cream", "full"), route_shift=(-70, 0)),
    PosterVariant("tactic_line_experiment_27.png", "27 Short Mark", 181827, (620, 384), 13, 0, CQB.accent2, 2, 38, 98, 0.12, title((W // 2, 74), "center", 86, "under_weapon", "gold", "short"), background_darkness=0.92),
    PosterVariant("tactic_line_experiment_28.png", "28 Giant Ghost", 181828, (620, 386), 12, 0, CQB.accent2, 3, 34, 92, 0.10, title((W // 2, 226), "center", 176, "under_weapon", "shadow", "none"), background_darkness=0.82),
    PosterVariant("tactic_line_experiment_29.png", "29 Bright Focus", 181829, (620, 382), 12, -1, (236, 214, 132), 0, 62, 140, 0.30, title((W // 2, 42), "center", 108, "under_weapon", "cream", "full"), brightness=1.28),
    PosterVariant("tactic_line_experiment_30.png", "30 Quiet Routes", 181830, (620, 382), 12, 1, (174, 170, 132), 1, 22, 72, 0.05, title((74, 70), "left", 100, "under_weapon", "cream", "none"), background_darkness=0.88),
    PosterVariant("tactic_line_experiment_31.png", "31 Steel Bright", 181831, (638, 386), 12, 3, (236, 214, 132), 2, 58, 130, 0.24, title((W // 2, 506), "center", 104, "over_weapon", "gold", "short"), brightness=1.30, contrast=1.12),
    PosterVariant("tactic_line_experiment_32.png", "32 Minimal Red", 181832, (620, 382), 12, 0, CQB.accent, 3, 36, 92, 0.09, title((W // 2, 60), "center", 104, "under_weapon", "cream", "split"), frame_alpha=150, background_darkness=0.86),
    PosterVariant("tactic_line_experiment_33.png", "33 Route Emphasis", 181833, (620, 384), 11, 0, CQB.accent2, 0, 78, 158, 0.18, title((74, 52), "left", 96, "under_weapon", "cream", "short")),
    PosterVariant("tactic_line_experiment_34.png", "34 Dark Top", 181834, (622, 396), 12, -2, CQB.accent, 1, 38, 98, 0.07, title((W // 2, 44), "center", 122, "under_weapon", "cream", "none"), background_darkness=0.80),
    PosterVariant("tactic_line_experiment_35.png", "35 Tight Center", 181835, (620, 384), 13, 0, CQB.accent2, 2, 48, 116, 0.16, title((W // 2, 222), "center", 118, "over_weapon", "cream", "short")),
    PosterVariant("tactic_line_experiment_36.png", "36 Open Bottom", 181836, (620, 300), 11, 0, CQB.accent2, 3, 40, 106, 0.12, title((W // 2, 544), "center", 126, "over_weapon", "cream", "full")),
    PosterVariant("tactic_line_experiment_37.png", "37 Big Header", 181837, (620, 406), 12, 0, CQB.accent, 0, 46, 114, 0.18, title((W // 2, 34), "center", 138, "under_weapon", "cream", "full")),
    PosterVariant("tactic_line_experiment_38.png", "38 Weapon Above", 181838, (620, 246), 11, 0, CQB.accent2, 1, 52, 120, 0.18, title((W // 2, 430), "center", 134, "under_weapon", "gold", "full")),
    PosterVariant("tactic_line_experiment_39.png", "39 Weapon Below", 181839, (620, 486), 11, 0, CQB.accent, 2, 50, 116, 0.16, title((W // 2, 174), "center", 138, "over_weapon", "cream", "short")),
    PosterVariant("tactic_line_experiment_40.png", "40 Final Select", 181840, (620, 382), 13, 0, CQB.accent2, 3, 56, 128, 0.22, title((W // 2, 54), "center", 116, "under_weapon", "cream", "full"), brightness=1.22, contrast=1.12),
)

POSTER_NAMES = [variant.filename for variant in POSTER_VARIANTS]

STALE_OUTPUTS = (
    "tactic_line_poster_neon_crossfire.png",
    "tactic_line_poster_red_black.png",
    "tactic_line_poster_blueprint.png",
    "tactic_line_single_asvk.png",
    "tactic_line_single_m16.png",
    "tactic_line_single_shotgun.png",
    "tactic_line_single_mini_uzi.png",
    "tactic_line_single_silenced_pistol.png",
    "tactic_line_single_revolver.png",
    "tactic_line_single_ak_gl.png",
    "tactic_line_single_makarov_pm.png",
    "tactic_line_multi_primary_rifles.png",
    "tactic_line_multi_sidearms.png",
    "tactic_line_multi_full_armory.png",
    "tactic_line_multi_precision_cell.png",
    "tactic_line_multi_breach_cell.png",
    "tactic_line_multi_quiet_entry.png",
    "tactic_line_multi_heavy_wall.png",
    "tactic_line_multi_compact_sweep.png",
    "tactic_line_multi_unlock_progression.png",
    "tactic_line_multi_balanced_loadout.png",
    "tactic_line_red_black_asvk.png",
    "tactic_line_red_black_loadout.png",
    "tactic_line_asvk_close_quarters_02.png",
    "tactic_line_asvk_close_quarters_03.png",
    "tactic_line_asvk_close_quarters_04.png",
    "tactic_line_asvk_close_quarters_05.png",
    "tactic_line_asvk_close_quarters_06.png",
    "tactic_line_asvk_close_quarters_07.png",
    "tactic_line_asvk_close_quarters_08.png",
    "tactic_line_asvk_close_quarters_09.png",
    "tactic_line_asvk_close_quarters_10.png",
    "tactic_line_asvk_close_quarters_11.png",
    "tactic_line_asvk_close_quarters_12.png",
    "tactic_line_asvk_close_quarters_13.png",
    "tactic_line_asvk_close_quarters_14.png",
    "tactic_line_asvk_close_quarters_15.png",
    "tactic_line_asvk_close_quarters_16.png",
    "tactic_line_asvk_close_quarters_17.png",
    "tactic_line_asvk_close_quarters_18.png",
    "tactic_line_asvk_close_quarters_19.png",
    "tactic_line_asvk_close_quarters_20.png",
)


def font(path: Path, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(path), size)


def rgba(color: tuple[int, int, int], alpha: int = 255) -> tuple[int, int, int, int]:
    return color[0], color[1], color[2], alpha


def lerp(a: int, b: int, t: float) -> int:
    return int(a + (b - a) * t)


def blend(a: tuple[int, int, int], b: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    return lerp(a[0], b[0], t), lerp(a[1], b[1], t), lerp(a[2], b[2], t)


def scaled(color: tuple[int, int, int], amount: float) -> tuple[int, int, int]:
    return tuple(max(0, min(255, int(channel * amount))) for channel in color)


def make_base(seed: int, darkness: float) -> Image.Image:
    rng = random.Random(seed)
    img = Image.new("RGBA", (W, H), rgba(CQB.bg))
    pix = img.load()
    center_x = W * 0.54
    center_y = H * 0.50
    max_dist = math.hypot(center_x, center_y)

    for y in range(H):
        gy = y / H
        for x in range(W):
            gx = x / W
            t = gx * 0.56 + gy * 0.44
            base = blend(CQB.bg, CQB.floor, min(1.0, t * 1.25))
            d = math.hypot(x - center_x, y - center_y) / max_dist
            shade = max(0.35, 1.0 - d * 0.95) * darkness
            noise = rng.randint(-7, 7)
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
    overlay(img, glow, 0.55)
    draw = ImageDraw.Draw(img)
    draw.line(points, fill=rgba(color, alpha), width=width, joint="curve")


def draw_room_grid(img: Image.Image, seed: int, *, grid_alpha: int) -> None:
    rng = random.Random(seed)
    draw = ImageDraw.Draw(img, "RGBA")

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
        draw.rectangle(rect, fill=rgba(CQB.floor, 198))

    for rect in rooms:
        draw.rectangle(rect, outline=rgba(CQB.wall, 210), width=8)
    for rect in corridors:
        draw.rectangle(rect, outline=rgba(CQB.wall, 120), width=3)

    for x in range(72, W, 44):
        draw.line((x, 62, x, H - 52), fill=rgba(CQB.accent2, grid_alpha), width=1)
    for y in range(66, H, 44):
        draw.line((54, y, W - 54, y), fill=rgba(CQB.accent2, grid_alpha), width=1)

    for _ in range(34):
        x = rng.randrange(80, W - 80)
        y = rng.randrange(90, H - 70)
        w = rng.randrange(14, 56)
        h = rng.randrange(8, 26)
        draw.rectangle((x, y, x + w, y + h), fill=rgba(CQB.wall, rng.randrange(82, 156)))


def draw_tactical_routes(
    img: Image.Image,
    seed: int,
    variant: int,
    route_alpha: int,
    node_alpha: int,
    shift: tuple[int, int],
) -> None:
    rng = random.Random(seed)
    draw = ImageDraw.Draw(img, "RGBA")
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
            shifted.append((x + jitter_x + shift[0], y + jitter_y + shift[1] + variant * (i % 2) * 5))
        color = CQB.accent if i % 2 else CQB.accent2
        width = 2 if i != variant % len(routes) else 3
        draw.line(shifted, fill=rgba(color, route_alpha), width=width)
        for x, y in shifted:
            radius = 5 if i == variant % len(routes) else 4
            draw.ellipse((x - radius, y - radius, x + radius, y + radius), outline=rgba(color, node_alpha), width=2)
            draw.ellipse((x - 2, y - 2, x + 2, y + 2), fill=rgba(color, node_alpha))


def add_flashlight_wash(img: Image.Image, alpha: float) -> None:
    if alpha <= 0:
        return
    cone = Image.open(FLASHLIGHT).convert("RGBA")
    cone = cone.resize((640, 640), Image.Resampling.BILINEAR)
    cone = cone.rotate(-34, expand=True, resample=Image.Resampling.BILINEAR)
    cone = ImageEnhance.Color(cone).enhance(0.4)
    cone = ImageEnhance.Brightness(cone).enhance(1.55)
    a = cone.getchannel("A").point(lambda v: int(v * alpha))
    cone.putalpha(a)
    img.alpha_composite(cone, (166, 120))


def add_corner_frame(img: Image.Image, alpha: int, *, thick: int = 5) -> None:
    draw = ImageDraw.Draw(img, "RGBA")
    pad = 26
    length = 130
    for sx in (pad, W - pad):
        for sy in (pad, H - pad):
            xsign = 1 if sx == pad else -1
            ysign = 1 if sy == pad else -1
            draw.line((sx, sy, sx + xsign * length, sy), fill=rgba(CQB.accent, alpha), width=thick)
            draw.line((sx, sy, sx, sy + ysign * length), fill=rgba(CQB.accent, alpha), width=thick)


def title_color(tone: str) -> tuple[int, int, int]:
    if tone == "gold":
        return (245, 209, 118)
    if tone == "shadow":
        return (108, 92, 58)
    return CQB.text


def draw_title(img: Image.Image, layout: TitleLayout) -> None:
    title_font = font(FONT_TITLE, layout.size)
    draw = ImageDraw.Draw(img, "RGBA")
    bbox = draw.textbbox((0, 0), TITLE, font=title_font, stroke_width=layout.stroke)
    text_w = bbox[2] - bbox[0]
    text_h = bbox[3] - bbox[1]
    x, y = layout.anchor
    if layout.align == "center":
        x -= text_w // 2
    elif layout.align == "right":
        x -= text_w

    x = max(38, min(x, W - text_w - 38))
    y = max(30, min(y, H - text_h - 56))
    fill = title_color(layout.tone)
    stroke_fill = CQB.dark if layout.tone != "shadow" else scaled(CQB.dark, 1.8)

    glow_layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow_layer)
    for off in range(14, 0, -3):
        glow_alpha = int(layout.glow_alpha * (0.35 + off / 18))
        gd.text(
            (x, y),
            TITLE,
            font=title_font,
            fill=rgba(CQB.accent, glow_alpha),
            stroke_width=layout.stroke + off // 3,
            stroke_fill=rgba(CQB.accent, glow_alpha),
        )
    glow_layer = glow_layer.filter(ImageFilter.GaussianBlur(8))
    overlay(img, glow_layer, 0.78)

    draw.text(
        (x, y),
        TITLE,
        font=title_font,
        fill=rgba(fill, 245 if layout.tone != "shadow" else 210),
        stroke_width=layout.stroke,
        stroke_fill=rgba(stroke_fill, 255),
    )

    underline_y = y + text_h + 18
    underline_width = max(4, layout.size // 18)
    if layout.underline == "full":
        glow_line(img, [(x + 8, underline_y), (x + text_w - 8, underline_y)], CQB.accent, width=underline_width, blur=10, alpha=220)
    elif layout.underline == "short":
        cx = x + text_w / 2
        half = text_w * 0.28
        glow_line(img, [(cx - half, underline_y), (cx + half, underline_y)], CQB.accent, width=underline_width, blur=8, alpha=210)
    elif layout.underline == "split":
        gap = text_w * 0.18
        left_end = x + text_w / 2 - gap
        right_start = x + text_w / 2 + gap
        glow_line(img, [(x + 8, underline_y), (left_end, underline_y)], CQB.accent, width=underline_width, blur=8, alpha=210)
        glow_line(img, [(right_start, underline_y), (x + text_w - 8, underline_y)], CQB.accent, width=underline_width, blur=8, alpha=210)


def load_rifle_sprite(variant: PosterVariant) -> Image.Image:
    sprite = Image.open(RIFLE).convert("RGBA")
    alpha = sprite.getchannel("A")
    rgb = ImageEnhance.Brightness(sprite.convert("RGB")).enhance(variant.brightness)
    rgb = ImageEnhance.Contrast(rgb).enhance(variant.contrast)
    sprite = rgb.convert("RGBA")
    sprite.putalpha(alpha)
    sprite = sprite.resize((sprite.width * variant.scale, sprite.height * variant.scale), Image.Resampling.NEAREST)
    if variant.angle:
        sprite = sprite.rotate(variant.angle, expand=True, resample=Image.Resampling.NEAREST)
    return sprite


def paste_rifle(img: Image.Image, variant: PosterVariant) -> None:
    sprite = load_rifle_sprite(variant)
    x = int(variant.center[0] - sprite.width / 2)
    y = int(variant.center[1] - sprite.height / 2)
    mask = sprite.getchannel("A")

    glow_layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    glow_sprite = Image.new("RGBA", sprite.size, rgba(variant.glow, 0))
    glow_sprite.putalpha(mask.filter(ImageFilter.GaussianBlur(16)).point(lambda v: int(v * 0.60)))
    glow_layer.alpha_composite(glow_sprite, (x, y))
    overlay(img, glow_layer, 0.70)

    shadow = Image.new("RGBA", sprite.size, (0, 0, 0, 0))
    shadow.putalpha(mask.filter(ImageFilter.GaussianBlur(6)).point(lambda v: int(v * 0.74)))
    img.alpha_composite(shadow, (x + 10, y + 16))
    img.alpha_composite(sprite, (x, y))


def poster_variant(variant: PosterVariant) -> Image.Image:
    img = make_base(variant.seed, variant.background_darkness)
    draw_room_grid(img, variant.seed + 1, grid_alpha=variant.grid_alpha)
    draw_tactical_routes(img, variant.seed + 2, variant.route_variant, variant.route_alpha, variant.node_alpha, variant.route_shift)
    add_flashlight_wash(img, variant.light_alpha)
    add_corner_frame(img, variant.frame_alpha)

    if variant.title.layer == "under_weapon":
        draw_title(img, variant.title)
        paste_rifle(img, variant)
    else:
        paste_rifle(img, variant)
        draw_title(img, variant.title)

    return img


def save_rgb(img: Image.Image, name: str) -> Path:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    path = OUT_DIR / name
    img.convert("RGB").save(path, optimize=True)
    return path


def make_contact_sheet(paths: list[Path]) -> Path:
    thumb_w = 240
    thumb_h = int(thumb_w * H / W)
    pad = 18
    label_h = 34
    cols = 8
    rows = math.ceil(len(paths) / cols)
    sheet = Image.new("RGB", (thumb_w * cols + pad * (cols + 1), (thumb_h + label_h) * rows + pad * (rows + 1)), (8, 8, 8))
    draw = ImageDraw.Draw(sheet)
    label_font = font(FONT_SANS, 15)

    for i, path in enumerate(paths):
        row = i // cols
        col = i % cols
        x = pad + col * (thumb_w + pad)
        y = pad + row * (thumb_h + label_h + pad)
        poster = Image.open(path).convert("RGB").resize((thumb_w, thumb_h), Image.Resampling.LANCZOS)
        sheet.paste(poster, (x, y))
        draw.rectangle((x, y, x + thumb_w, y + thumb_h), outline=CQB.accent, width=2)
        draw.text((x, y + thumb_h + 8), POSTER_VARIANTS[i].label, font=label_font, fill=(236, 236, 218))

    out = OUT_DIR / "tactic_line_poster_contact_sheet.png"
    sheet.save(out, optimize=True)
    return out


def remove_stale_outputs() -> None:
    for filename in STALE_OUTPUTS:
        path = OUT_DIR / filename
        if path.exists():
            path.unlink()


def generate_posters() -> list[Path]:
    remove_stale_outputs()
    outputs = [save_rgb(poster_variant(variant), variant.filename) for variant in POSTER_VARIANTS]
    make_contact_sheet(outputs)
    return outputs


def main() -> None:
    os.chdir(ROOT)
    outputs = generate_posters()
    for path in outputs + [OUT_DIR / "tactic_line_poster_contact_sheet.png"]:
        print(path.relative_to(ROOT))


if __name__ == "__main__":
    main()
