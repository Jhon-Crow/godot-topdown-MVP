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

    def test_small_icon_entries_are_square_centered_and_not_cropped(self):
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
                    self.assertGreater(left, 0)
                    self.assertGreater(top, 0)
                    self.assertLess(right, size[0])
                    self.assertLess(bottom, size[1])

                    center_x = (left + right - 1) / 2
                    center_y = (top + bottom - 1) / 2
                    expected_center = (size[0] - 1) / 2
                    self.assertLessEqual(abs(center_x - expected_center), 0.5)
                    self.assertLessEqual(abs(center_y - expected_center), 0.5)


if __name__ == "__main__":
    unittest.main()
