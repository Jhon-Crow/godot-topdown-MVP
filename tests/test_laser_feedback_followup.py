from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CURSOR_ASSET = ROOT / "assets" / "sprites" / "ui" / "red_dot_cursor.svg"
HOVER_CURSOR_ASSET = ROOT / "assets" / "sprites" / "ui" / "red_dot_cursor_hover.svg"
LASER_GLOW = ROOT / "Scripts" / "Weapons" / "LaserGlowEffect.cs"
LASER_WEAPON_FILES = [
    ROOT / "Scripts" / "Weapons" / "AssaultRifle.cs",
    ROOT / "Scripts" / "Weapons" / "SilencedPistol.cs",
    ROOT / "Scripts" / "Weapons" / "MakarovPM.cs",
    ROOT / "Scripts" / "Weapons" / "MiniUzi.cs",
    ROOT / "Scripts" / "Weapons" / "AKGL.cs",
    ROOT / "Scripts" / "Weapons" / "Revolver.cs",
    ROOT / "Scripts" / "Weapons" / "SniperRifle.cs",
]


def test_red_dot_cursor_has_distinct_dot_and_outer_glow():
    svg = CURSOR_ASSET.read_text(encoding="utf-8")

    assert 'id="red_dot_cursor_glow"' in svg
    assert 'width="64"' in svg
    assert 'height="64"' in svg
    assert 'offset="82%" stop-color="#ff160f" stop-opacity="0.025"' in svg
    assert '<circle cx="32" cy="32" r="28"' in svg
    assert '<circle cx="32" cy="32" r="2.5" fill="#ff120c"' in svg
    assert "#fff0df" not in svg


def test_hover_cursor_replaces_default_interaction_cursor():
    svg = HOVER_CURSOR_ASSET.read_text(encoding="utf-8")

    assert 'id="red_dot_cursor_hover_glow"' in svg
    assert 'width="64"' in svg
    assert 'height="64"' in svg
    assert 'offset="84%" stop-color="#ff160f" stop-opacity="0.018"' in svg
    assert '<circle cx="32" cy="32" r="23"' in svg
    assert '<circle cx="32" cy="32" r="3.5" fill="#ff120c"' in svg
    assert "#fff0df" not in svg


def test_shared_laser_glow_is_larger_than_original_cursor_draft():
    source = LASER_GLOW.read_text(encoding="utf-8")

    assert "new GlowLayerDef(72.0f, 0.03f, 0)" in source
    assert "EndpointGlowTextureScale = 0.55f" in source


def test_laser_weapons_have_small_default_aim_inertia():
    for path in LASER_WEAPON_FILES:
        source = path.read_text(encoding="utf-8")
        assert "DefaultLaserAimTurnSpeed = 7.5f" in source, path
        assert "Mathf.LerpAngle(_currentAimAngle, targetAngle" in source, path
