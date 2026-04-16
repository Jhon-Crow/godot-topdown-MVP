#!/usr/bin/env python3
import struct
import unittest
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
ICON_PATH = ROOT / "assets" / "icon.ico"


class WindowsIconTest(unittest.TestCase):
    def test_icon_contains_expected_windows_sizes(self):
        data = ICON_PATH.read_bytes()
        reserved, icon_type, count = struct.unpack_from("<HHH", data, 0)

        self.assertEqual(reserved, 0)
        self.assertEqual(icon_type, 1)
        self.assertGreaterEqual(count, 7)

        sizes = set()
        for index in range(count):
            offset = 6 + index * 16
            width, height = struct.unpack_from("<BB", data, offset)
            sizes.add((256 if width == 0 else width, 256 if height == 0 else height))

        self.assertEqual(
            sizes,
            {(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)},
        )

    def test_small_icon_entries_fill_windows_small_icon_slots(self):
        with Image.open(ICON_PATH) as icon_file:
            ico = icon_file.ico

            for size in [(16, 16), (24, 24), (32, 32)]:
                with self.subTest(size=size):
                    image = ico.getimage(size).convert("RGBA")
                    alpha_bbox = image.getchannel("A").getbbox()
                    self.assertIsNotNone(alpha_bbox)
                    self.assertEqual(image.size, size)

                    left, top, right, bottom = alpha_bbox
                    self.assertEqual(right - left, bottom - top)
                    self.assertEqual(left, 1)
                    self.assertEqual(top, 1)
                    self.assertEqual(right, size[0] - 1)
                    self.assertEqual(bottom, size[1] - 1)

                    center_x = (left + right - 1) / 2
                    center_y = (top + bottom - 1) / 2
                    expected_center = (size[0] - 1) / 2
                    self.assertLessEqual(abs(center_x - expected_center), 0.5)
                    self.assertLessEqual(abs(center_y - expected_center), 0.5)

    def test_small_icon_background_is_even_black_circle(self):
        with Image.open(ICON_PATH) as icon_file:
            ico = icon_file.ico

            for size in [(16, 16), (24, 24), (32, 32)]:
                with self.subTest(size=size):
                    image = ico.getimage(size).convert("RGBA")
                    width, height = image.size
                    center = (width - 1) / 2
                    radius = (width - 2) / 2

                    for x, y in [
                        (width // 2, 1),
                        (width // 2, height - 2),
                        (1, height // 2),
                        (width - 2, height // 2),
                    ]:
                        self.assertEqual(image.getpixel((x, y)), (0, 0, 0, 255))

                    edge_samples = [
                        (0, 0),
                        (width - 1, 0),
                        (0, height - 1),
                        (width - 1, height - 1),
                    ]
                    for pixel in edge_samples:
                        self.assertEqual(image.getpixel(pixel)[3], 0)

                    opaque_points = []
                    for y in range(height):
                        for x in range(width):
                            if image.getpixel((x, y))[3] > 0:
                                opaque_points.append((x, y))

                    for x, y in opaque_points:
                        mirrored = (width - 1 - x, y)
                        self.assertGreater(image.getpixel(mirrored)[3], 0)
                        mirrored = (x, height - 1 - y)
                        self.assertGreater(image.getpixel(mirrored)[3], 0)

                    expected_mask = {
                        (x, y)
                        for y in range(height)
                        for x in range(width)
                        if ((x - center) ** 2 + (y - center) ** 2) <= radius**2
                    }
                    actual_mask = set(opaque_points)
                    self.assertLessEqual(
                        len(actual_mask.symmetric_difference(expected_mask)),
                        width,
                    )


if __name__ == "__main__":
    unittest.main()
