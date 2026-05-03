from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PROJECT_FILE = ROOT / "project.godot"
CURSOR_ASSET = ROOT / "assets" / "sprites" / "ui" / "red_dot_cursor.svg"
HOVER_CURSOR_ASSET = ROOT / "assets" / "sprites" / "ui" / "red_dot_cursor_hover.svg"
INTERACTIVE_UI_FILES = [
    ROOT / "scripts" / "ui" / "levels_menu.gd",
    ROOT / "scripts" / "ui" / "armory_menu.gd",
]


def test_project_uses_red_dot_cursor_asset():
    project_text = PROJECT_FILE.read_text(encoding="utf-8")

    assert 'mouse_cursor/custom_image="res://assets/sprites/ui/red_dot_cursor.svg"' in project_text
    assert "mouse_cursor/custom_image_hotspot=Vector2(32, 32)" in project_text


def test_red_dot_cursor_asset_is_small_and_glowing():
    svg = CURSOR_ASSET.read_text(encoding="utf-8")

    assert 'width="64"' in svg
    assert 'height="64"' in svg
    assert "radialGradient" in svg
    assert "#ff160f" in svg
    assert 'offset="82%" stop-color="#ff160f" stop-opacity="0.025"' in svg
    assert '<circle cx="32" cy="32" r="28"' in svg
    assert '<circle cx="32" cy="32" r="2.5"' in svg
    assert "#fff0df" not in svg


def test_hover_cursor_uses_larger_dot_and_tighter_glow():
    svg = HOVER_CURSOR_ASSET.read_text(encoding="utf-8")

    assert 'width="64"' in svg
    assert 'height="64"' in svg
    assert 'id="red_dot_cursor_hover_glow"' in svg
    assert 'offset="84%" stop-color="#ff160f" stop-opacity="0.018"' in svg
    assert '<circle cx="32" cy="32" r="23"' in svg
    assert '<circle cx="32" cy="32" r="3.5" fill="#ff120c"' in svg
    assert "#fff0df" not in svg


def test_interactive_cards_keep_laser_cursor_shape():
    for path in INTERACTIVE_UI_FILES:
        source = path.read_text(encoding="utf-8")
        assert "CURSOR_POINTING_HAND" not in source, path
        assert "red_dot_cursor_hover.svg" in source, path
        assert "Vector2(32, 32)" in source, path
        assert "Input.set_custom_mouse_cursor" in source, path
