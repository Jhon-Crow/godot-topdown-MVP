#!/usr/bin/env python3
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
EXPORT_PRESETS_PATH = ROOT / "export_presets.cfg"
PROJECT_PATH = ROOT / "project.godot"


def _read_export_setting(setting_name: str) -> str:
    prefix = f"{setting_name}="
    for line in EXPORT_PRESETS_PATH.read_text(encoding="utf-8").splitlines():
        if line.startswith(prefix):
            return line.removeprefix(prefix).strip('"')
    raise AssertionError(f"{setting_name} was not found in export_presets.cfg")


def _read_project_setting(setting_name: str) -> str:
    prefix = f'{setting_name}="'
    for line in PROJECT_PATH.read_text(encoding="utf-8").splitlines():
        if line.startswith(prefix):
            return line.removeprefix(prefix).removesuffix('"')
    raise AssertionError(f"{setting_name} was not found in project.godot")


class WindowsExportNamesTest(unittest.TestCase):
    def test_windows_export_executable_is_named_tactic_line(self):
        self.assertEqual(
            _read_export_setting("export_path"),
            "builds/windows/Tactic Line.exe",
        )

    def test_windows_dotnet_data_folder_uses_tacticline_stem(self):
        project_name = _read_project_setting("config/name")
        architecture = _read_export_setting("binary_format/architecture")

        self.assertEqual(
            f"data_{project_name}_windows_{architecture}",
            "data_TacticLine_windows_x86_64",
        )

    def test_project_name_matches_windows_dotnet_data_folder_prefix(self):
        self.assertEqual(
            _read_project_setting("config/name"),
            "TacticLine",
        )

    def test_windows_export_keeps_existing_dotnet_assembly_name(self):
        self.assertEqual(
            _read_project_setting("project/assembly_name"),
            "GodotTopDownTemplate",
        )

    def test_windows_product_name_is_tactic_line(self):
        self.assertEqual(
            _read_export_setting("application/product_name"),
            "Tactic Line",
        )

    def test_windows_export_keeps_external_dotnet_data_folder(self):
        self.assertEqual(
            _read_export_setting("binary_format/embed_pck"),
            "false",
        )


if __name__ == "__main__":
    unittest.main()
