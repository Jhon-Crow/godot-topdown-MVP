using Godot;

namespace GodotTopDownTemplate.Data;

/// <summary>
/// Resource class containing weapon configuration data.
/// Can be saved as .tres files and shared between weapon instances.
/// </summary>
[GlobalClass]
public partial class WeaponData : Resource
{
    /// <summary>
    /// Display name of the weapon.
    /// </summary>
    [Export]
    public string Name { get; set; } = "Weapon";

    /// <summary>
    /// Damage dealt per bullet.
    /// </summary>
    [Export]
    public float Damage { get; set; } = 10.0f;

    /// <summary>
    /// Rate of fire in shots per second.
    /// </summary>
    [Export]
    public float FireRate { get; set; } = 5.0f;

    /// <summary>
    /// Number of bullets in a magazine.
    /// </summary>
    [Export]
    public int MagazineSize { get; set; } = 30;

    /// <summary>
    /// Maximum reserve ammunition.
    /// </summary>
    [Export]
    public int MaxReserveAmmo { get; set; } = 120;

    /// <summary>
    /// Time in seconds to reload.
    /// </summary>
    [Export]
    public float ReloadTime { get; set; } = 2.0f;

    /// <summary>
    /// Bullet speed in pixels per second.
    /// </summary>
    [Export]
    public float BulletSpeed { get; set; } = 600.0f;

    /// <summary>
    /// Maximum range of the bullet in pixels before despawning.
    /// </summary>
    [Export]
    public float Range { get; set; } = 1000.0f;

    /// <summary>
    /// Spread angle in degrees for inaccuracy.
    /// </summary>
    [Export(PropertyHint.Range, "0,45,0.1")]
    public float SpreadAngle { get; set; } = 0.0f;

    /// <summary>
    /// Number of bullets fired per shot (for shotguns).
    /// </summary>
    [Export]
    public int BulletsPerShot { get; set; } = 1;

    /// <summary>
    /// Whether the weapon is automatic (hold to fire) or semi-automatic (click for each shot).
    /// </summary>
    [Export]
    public bool IsAutomatic { get; set; } = false;
}
