#!/usr/bin/env python3
"""Validate generated poster assets for issue #1815."""

from __future__ import annotations

import struct
import zlib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
GENERATOR = ROOT / "experiments" / "generate_tactic_line_posters.py"
POSTER_DIR = ROOT / "assets" / "posters"

POSTERS = [
    POSTER_DIR / "tactic_line_poster_neon_crossfire.png",
    POSTER_DIR / "tactic_line_poster_red_black.png",
    POSTER_DIR / "tactic_line_poster_blueprint.png",
    POSTER_DIR / "tactic_line_poster_close_quarters.png",
]
CONTACT_SHEET = POSTER_DIR / "tactic_line_poster_contact_sheet.png"

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


class PngInfo:
    def __init__(self, width: int, height: int, bit_depth: int, color_type: int, idat: bytes) -> None:
        self.width = width
        self.height = height
        self.bit_depth = bit_depth
        self.color_type = color_type
        self.idat = idat


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


def png_rgb_colors(path: Path) -> set[tuple[int, int, int]]:
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

    colors: set[tuple[int, int, int]] = set()
    for row in rows:
        for i in range(0, len(row), channels):
            colors.add((row[i], row[i + 1], row[i + 2]))
    return colors


def validate_generator_source() -> list[str]:
    source = GENERATOR.read_text(encoding="utf-8")
    forbidden = [
        "characters/player",
        "characters/enemy",
        "player_combined_preview",
        "enemy_combined_preview",
        "paste_sprite(img, PLAYER",
        "paste_sprite(img, ENEMY",
    ]
    return [f"generator still references forbidden character asset: {token}" for token in forbidden if token in source]


def validate_png_outputs() -> list[str]:
    failures: list[str] = []
    for poster in POSTERS:
        info = read_png_info(poster)
        if (info.width, info.height) != (1232, 706):
            failures.append(f"{poster.relative_to(ROOT)} is {info.width}x{info.height}, expected 1232x706")

    contact = read_png_info(CONTACT_SHEET)
    if contact.width <= 0 or contact.height <= 0:
        failures.append(f"{CONTACT_SHEET.relative_to(ROOT)} has invalid dimensions {contact.width}x{contact.height}")

    red_black_colors = png_rgb_colors(POSTER_DIR / "tactic_line_poster_red_black.png")
    expected = {(0, 0, 0), (255, 0, 0)}
    if red_black_colors != expected:
        failures.append(
            "tactic_line_poster_red_black.png must remain strict red/black; "
            f"found {len(red_black_colors)} colors"
        )

    return failures


def main() -> int:
    failures = validate_generator_source()
    failures.extend(validate_png_outputs())

    if failures:
        print("Poster validation failed:")
        for failure in failures:
            print(f"- {failure}")
        return 1

    print("Poster validation passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
