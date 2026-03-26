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

    /// <summary>
    /// Loudness of the weapon in pixels - determines how far gunshots propagate for enemy detection.
    /// Each weapon's .tres resource file should explicitly set this value.
    /// Issue #1524: AssaultRifle (M16) Loudness = 840.0px.
    /// Issue #1269: All values scaled by factor 800/1469 from original viewport-diagonal baseline.
    /// </summary>
    [Export]
    public float Loudness { get; set; } = 800.0f;

    /// <summary>
    /// Aiming sensitivity for the weapon. Controls how fast the weapon rotates toward the cursor.
    /// Works like a "leash" - the virtual cursor distance from player is divided by this value.
    /// Higher sensitivity = faster rotation (cursor feels closer).
    /// When set to 0 (default), uses automatic sensitivity based on actual cursor distance.
    /// Recommended values: 1-10, with 4 being a good middle ground.
    /// </summary>
    [Export(PropertyHint.Range, "0,20,0.1")]
    public float Sensitivity { get; set; } = 0.0f;

    /// <summary>
    /// Screen shake intensity per shot in pixels.
    /// The actual shake distance per shot is calculated as: ScreenShakeIntensity / FireRate * 10
    /// This means slower firing weapons create bigger shakes per shot.
    /// Set to 0 to disable screen shake for this weapon.
    /// </summary>
    [Export(PropertyHint.Range, "0,50,0.5")]
    public float ScreenShakeIntensity { get; set; } = 5.0f;

    /// <summary>
    /// Minimum recovery time in seconds for screen shake at minimum spread.
    /// When the weapon has minimal spread (accurate), recovery is slower.
    /// </summary>
    [Export(PropertyHint.Range, "0.05,2.0,0.01")]
    public float ScreenShakeMinRecoveryTime { get; set; } = 0.3f;

    /// <summary>
    /// Maximum recovery time in seconds for screen shake at maximum spread.
    /// When the weapon has maximum spread (inaccurate), recovery is faster.
    /// The minimum value is clamped to 0.05 seconds (50ms) as per specification.
    /// </summary>
    [Export(PropertyHint.Range, "0.05,1.0,0.01")]
    public float ScreenShakeMaxRecoveryTime { get; set; } = 0.05f;

    /// <summary>
    /// Caliber data for this weapon's ammunition.
    /// Defines ballistic properties and casing appearance.
    /// </summary>
    [Export]
    public Resource? Caliber { get; set; }

    /// <summary>
    /// Whether this weapon's caliber can ricochet off surfaces (Issue #935).
    /// Mirrors CaliberData.can_ricochet as a C# property to avoid GDScript resource interop issues.
    /// When false, trajectory glasses will show all segments as red (no ricochet).
    /// </summary>
    [Export]
    public bool CaliberCanRicochet { get; set; } = true;

    /// <summary>
    /// Maximum angle in degrees from the surface at which ricochet is possible (Issue #935).
    /// Mirrors CaliberData.max_ricochet_angle as a C# property to avoid GDScript resource interop issues.
    /// Default 90.0 means any angle can ricochet. Set to 70.0 for rifle calibers.
    /// </summary>
    [Export(PropertyHint.Range, "0.0,90.0,1.0")]
    public float CaliberMaxRicochetAngle { get; set; } = 90.0f;

    /// <summary>
    /// Maximum number of ricochets allowed for this weapon's caliber (Issue #935).
    /// Mirrors CaliberData.max_ricochets as a C# property to avoid GDScript resource interop issues.
    /// -1 means unlimited. 0 means no ricochet even if CaliberCanRicochet is true.
    /// </summary>
    [Export]
    public int CaliberMaxRicochets { get; set; } = -1;

    /// <summary>
    /// Whether bullets from this weapon penetrate through enemies (Issue #829).
    /// When true, bullets deal damage to enemies but continue flying through them.
    /// Used by the RSh-12 revolver with its 12.7x55mm armor-piercing rounds.
    /// </summary>
    [Export]
    public bool PenetratesEnemies { get; set; } = false;
}
