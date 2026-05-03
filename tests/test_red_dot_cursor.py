from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PROJECT_FILE = ROOT / "project.godot"
CURSOR_ASSET = ROOT / "assets" / "sprites" / "ui" / "red_dot_cursor.svg"


def test_project_uses_red_dot_cursor_asset():
    project_text = PROJECT_FILE.read_text(encoding="utf-8")

    assert 'mouse_cursor/custom_image="res://assets/sprites/ui/red_dot_cursor.svg"' in project_text
    assert "mouse_cursor/custom_image_hotspot=Vector2(16, 16)" in project_text


def test_red_dot_cursor_asset_is_small_and_glowing():
    svg = CURSOR_ASSET.read_text(encoding="utf-8")

    assert 'width="32"' in svg
    assert 'height="32"' in svg
    assert "radialGradient" in svg
    assert "#ff160f" in svg
