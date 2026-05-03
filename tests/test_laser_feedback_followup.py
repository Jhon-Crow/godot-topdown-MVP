from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CURSOR_ASSET = ROOT / "assets" / "sprites" / "ui" / "red_dot_cursor.svg"
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


def test_red_dot_cursor_has_no_solid_center_dot():
    svg = CURSOR_ASSET.read_text(encoding="utf-8")

    assert svg.count("<circle") == 1
    assert 'fill="#ff120c"' not in svg
    assert 'fill="#fff0df"' not in svg


def test_shared_laser_glow_is_larger_than_original_cursor_draft():
    source = LASER_GLOW.read_text(encoding="utf-8")

    assert "new GlowLayerDef(72.0f, 0.03f, 0)" in source
    assert "EndpointGlowTextureScale = 0.55f" in source


def test_laser_weapons_have_small_default_aim_inertia():
    for path in LASER_WEAPON_FILES:
        source = path.read_text(encoding="utf-8")
        assert "DefaultLaserAimTurnSpeed = 18.0f" in source, path
        assert "Mathf.LerpAngle(_currentAimAngle, targetAngle" in source, path
