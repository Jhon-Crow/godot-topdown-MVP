#!/usr/bin/env python3
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
EXPORT_PRESETS_PATH = ROOT / "export_presets.cfg"


def _read_export_setting(setting_name: str) -> str:
    prefix = f'{setting_name}="'
    for line in EXPORT_PRESETS_PATH.read_text(encoding="utf-8").splitlines():
        if line.startswith(prefix):
            return line.removeprefix(prefix).removesuffix('"')
    raise AssertionError(f"{setting_name} was not found in export_presets.cfg")


class WindowsExportNamesTest(unittest.TestCase):
    def test_windows_export_executable_is_named_tactic_line(self):
        self.assertEqual(
            _read_export_setting("export_path"),
            "builds/windows/Tactic Line.exe",
        )

    def test_windows_dotnet_data_folder_uses_tacticline_stem(self):
        executable_stem = Path(_read_export_setting("export_path")).stem.replace(" ", "")
        architecture = _read_export_setting("binary_format/architecture")

        self.assertEqual(
            f"data_{executable_stem}_windows_{architecture}",
            "data_TacticLine_windows_x86_64",
        )

    def test_windows_product_name_is_tactic_line(self):
        self.assertEqual(
            _read_export_setting("application/product_name"),
            "Tactic Line",
        )


if __name__ == "__main__":
    unittest.main()
