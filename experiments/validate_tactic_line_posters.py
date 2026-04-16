#!/usr/bin/env python3
"""Validate generated Tactic Line poster assets for issue #1815."""

from __future__ import annotations

import importlib.util
import struct
import sys
import zlib
from collections import Counter
from pathlib import Path
from types import ModuleType


ROOT = Path(__file__).resolve().parents[1]
GENERATOR = ROOT / "experiments" / "generate_tactic_line_posters.py"
POSTER_DIR = ROOT / "assets" / "posters"
CONTACT_SHEET = POSTER_DIR / "tactic_line_poster_contact_sheet.png"

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


class PngInfo:
    def __init__(self, width: int, height: int, bit_depth: int, color_type: int, idat: bytes) -> None:
        self.width = width
        self.height = height
        self.bit_depth = bit_depth
        self.color_type = color_type
        self.idat = idat


def load_generator() -> ModuleType:
    spec = importlib.util.spec_from_file_location("generate_tactic_line_posters", GENERATOR)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load generator module from {GENERATOR}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def read_png_info(path: Path) -> PngInfo:
    data = path.read_bytes()
    if not data.startswith(PNG_SIGNATURE):
        raise ValueError(f"{path} is not a PNG file")

    offset = len(PNG_SIGNATURE)
    width = height = bit_depth = color_type = None
    idat_chunks: list[bytes] = []

    while offset < len(data):
        length = struct.unpack(">I", data[offset : offset + 4])[0]
        offset += 4
        chunk_type = data[offset : offset + 4]
        offset += 4
        chunk_data = data[offset : offset + length]
        offset += length + 4

        if chunk_type == b"IHDR":
            width, height, bit_depth, color_type = struct.unpack(">IIBB", chunk_data[:10])
        elif chunk_type == b"IDAT":
            idat_chunks.append(chunk_data)
        elif chunk_type == b"IEND":
            break

    if width is None or height is None or bit_depth is None or color_type is None:
        raise ValueError(f"{path} has no IHDR chunk")

    return PngInfo(width, height, bit_depth, color_type, b"".join(idat_chunks))


def paeth_predictor(a: int, b: int, c: int) -> int:
    p = a + b - c
    pa = abs(p - a)
    pb = abs(p - b)
    pc = abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    if pb <= pc:
        return b
    return c


def png_rgb_counter(path: Path) -> Counter[tuple[int, int, int]]:
    info = read_png_info(path)
    if info.bit_depth != 8 or info.color_type not in (2, 6):
        raise ValueError(f"{path} must be 8-bit RGB/RGBA, got bit_depth={info.bit_depth}, color_type={info.color_type}")

    channels = 3 if info.color_type == 2 else 4
    stride = info.width * channels
    raw = zlib.decompress(info.idat)
    rows: list[bytearray] = []
    offset = 0

    for _ in range(info.height):
        filter_type = raw[offset]
        offset += 1
        row = bytearray(raw[offset : offset + stride])
        offset += stride
        prev = rows[-1] if rows else bytearray(stride)

        for i, value in enumerate(row):
            left = row[i - channels] if i >= channels else 0
            up = prev[i]
            upper_left = prev[i - channels] if i >= channels else 0
            if filter_type == 1:
                row[i] = (value + left) & 0xFF
            elif filter_type == 2:
                row[i] = (value + up) & 0xFF
            elif filter_type == 3:
                row[i] = (value + ((left + up) // 2)) & 0xFF
            elif filter_type == 4:
                row[i] = (value + paeth_predictor(left, up, upper_left)) & 0xFF
            elif filter_type != 0:
                raise ValueError(f"{path} uses unsupported PNG filter {filter_type}")
        rows.append(row)

    colors: Counter[tuple[int, int, int]] = Counter()
    for row in rows:
        for i in range(0, len(row), channels):
            colors[(row[i], row[i + 1], row[i + 2])] += 1
    return colors


def validate_generator_source() -> list[str]:
    source = GENERATOR.read_text(encoding="utf-8")
    forbidden = [
        "characters/player",
        "characters/enemy",
        "player_combined_preview",
        "enemy_combined_preview",
        "m16_rifle.png",
        "m16_rifle_topdown.png",
        "shotgun_icon.png",
        "shotgun_topdown.png",
        "revolver_icon.png",
        "revolver_topdown.png",
        "ak_gl_icon.png",
        "ak_gl_topdown.png",
        "mini_uzi_icon.png",
        "mini_uzi_topdown.png",
        "silenced_pistol_icon.png",
        "silenced_pistol_topdown.png",
        "makarov_pm_icon.png",
        "makarov_pm_topdown.png",
        "pkm_topdown.png",
        "rpg_topdown.png",
        "machete_topdown.png",
        "draw_focus_field",
        "draw_soft_weapon_plinth",
        "rounded_rectangle",
        "add_scanlines",
        "scanline_alpha",
        "draw_caption",
        "CAPTION",
        "\"ASVK\"",
        "'ASVK'",
    ]
    failures = [f"generator still references forbidden asset/source token: {token}" for token in forbidden if token in source]

    required = [
        "asvk_topdown.png",
        "Rye-Regular.ttf",
        "Tactic Line",
        "POSTER_VARIANTS",
        "tactic_line_experiment_40.png",
    ]
    for token in required:
        if token not in source:
            failures.append(f"generator no longer references required poster token: {token}")

    return failures


def validate_png_outputs(poster_names: list[str]) -> list[str]:
    failures: list[str] = []
    if len(poster_names) != 40:
        failures.append(f"generator defines {len(poster_names)} posters, expected 40")

    expected = {POSTER_DIR / name for name in poster_names}
    for poster in expected:
        if not poster.exists():
            failures.append(f"{poster.relative_to(ROOT)} is missing")
            continue
        info = read_png_info(poster)
        if (info.width, info.height) != (1232, 706):
            failures.append(f"{poster.relative_to(ROOT)} is {info.width}x{info.height}, expected 1232x706")

    unexpected = sorted(path for path in POSTER_DIR.glob("tactic_line*.png") if path not in expected and path != CONTACT_SHEET)
    for poster in unexpected:
        failures.append(f"stale or unexpected poster exists: {poster.relative_to(ROOT)}")

    contact = read_png_info(CONTACT_SHEET)
    if contact.width <= 0 or contact.height <= 0:
        failures.append(f"{CONTACT_SHEET.relative_to(ROOT)} has invalid dimensions {contact.width}x{contact.height}")

    return failures


def validate_not_red_black_batch(posters: list[Path]) -> list[str]:
    failures: list[str] = []
    for path in posters:
        colors = png_rgb_counter(path)
        total = sum(colors.values())
        red_dominant = sum(
            count
            for (r, g, b), count in colors.items()
            if r >= 130 and r > g * 1.45 and r > b * 1.45
        )
        red_ratio = red_dominant / total
        if red_ratio > 0.075:
            failures.append(f"{path.relative_to(ROOT)} uses too much red for the close-quarters batch: {red_ratio:.1%}, expected <= 7.5%")
    return failures


def main() -> int:
    module = load_generator()
    poster_names = list(module.POSTER_NAMES)
    posters = [POSTER_DIR / name for name in poster_names]

    failures = validate_generator_source()
    failures.extend(validate_png_outputs(poster_names))
    failures.extend(validate_not_red_black_batch(posters))

    if failures:
        print("Poster validation failed:")
        for failure in failures:
            print(f"- {failure}")
        return 1

    print("Poster validation passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
