using Godot;
using GodotTopDownTemplate.AbstractClasses;
using GodotTopDownTemplate.Projectiles;

namespace GodotTopDownTemplate.Weapons;

/// <summary>
/// RSh-12 heavy revolver - semi-automatic high-caliber revolver.
/// Features:
/// - Semi-automatic fire (one shot per click)
/// - 12.7x55mm STs-130 armor-piercing bullets with 20 damage
/// - Penetrates enemies (bullet passes through)
/// - Weak ricochet, penetrates walls at 200px
/// - Strong screen shake and recoil (almost like sniper rifle)
/// - Comfortable aiming like silenced pistol (smooth rotation, sensitivity 2.0)
/// - 5-round cylinder (12.7mm caliber)
/// - Pistol casings (longer than standard)
/// - Very loud (alerts enemies at long range)
/// Reference: https://news.rambler.ru/weapon/40992656-slonoboy-russkiy-revolver-kotoryy-sposoben-unichtozhit-bronetransporter/
/// </summary>
public partial class Revolver : BaseWeapon
{
    /// <summary>
    /// Reference to the Sprite2D node for the weapon visual.
    /// </summary>
    private Sprite2D? _weaponSprite;

    /// <summary>
    /// Current aim direction based on mouse position.
    /// </summary>
    private Vector2 _aimDirection = Vector2.Right;

    /// <summary>
    /// Current aim angle in radians. Used for sensitivity-based aiming
    /// where the aim interpolates smoothly toward the target angle.
    /// </summary>
    private float _currentAimAngle = 0.0f;

    /// <summary>
    /// Whether the aim angle has been initialized.
    /// </summary>
    private bool _aimAngleInitialized = false;

    /// <summary>
    /// Current recoil offset angle in radians.
    /// RSh-12 has heavy recoil close to the sniper rifle.
    /// </summary>
    private float _recoilOffset = 0.0f;

    /// <summary>
    /// Time since the last shot was fired, used for recoil recovery.
    /// </summary>
    private float _timeSinceLastShot = 0.0f;

    /// <summary>
    /// Time in seconds before recoil starts recovering.
    /// Long delay for heavy revolver (close to sniper rifle).
    /// </summary>
    private const float RecoilRecoveryDelay = 0.45f;

    /// <summary>
    /// Speed at which recoil recovers (radians per second).
    /// Slower than standard pistols, reflecting heavy caliber.
    /// </summary>
    private const float RecoilRecoverySpeed = 3.5f;

    /// <summary>
    /// Maximum recoil offset in radians (about 13 degrees).
    /// Close to sniper rifle (15 degrees) but slightly less.
    /// </summary>
    private const float MaxRecoilOffset = 0.23f;

    /// <summary>
    /// Recoil amount per shot in radians.
    /// Heavy kick for 12.7mm revolver, close to sniper rifle.
    /// </summary>
    private const float RecoilPerShot = 0.12f;

    /// <summary>
    /// Muzzle flash scale for the RSh-12 revolver.
    /// Large flash for 12.7mm caliber but smaller than sniper rifle
    /// (revolver has shorter barrel, so more flash but less total gas).
    /// </summary>
    private const float RevolverMuzzleFlashScale = 1.5f;

    public override void _Ready()
    {
        base._Ready();

        // Get the weapon sprite for visual representation
        _weaponSprite = GetNodeOrNull<Sprite2D>("RevolverSprite");

        if (_weaponSprite != null)
        {
            var texture = _weaponSprite.Texture;
            GD.Print($"[Revolver] RevolverSprite found: visible={_weaponSprite.Visible}, z_index={_weaponSprite.ZIndex}, texture={(texture != null ? "loaded" : "NULL")}");
        }
        else
        {
            GD.Print("[Revolver] No RevolverSprite node (visual model not yet added)");
        }

        GD.Print("[Revolver] RSh-12 initialized - heavy revolver ready");
    }

    public override void _Process(double delta)
    {
        base._Process(delta);

        // Update time since last shot for recoil recovery
        _timeSinceLastShot += (float)delta;

        // Recover recoil after delay
        if (_timeSinceLastShot >= RecoilRecoveryDelay && _recoilOffset != 0)
        {
            float recoveryAmount = RecoilRecoverySpeed * (float)delta;
            _recoilOffset = Mathf.MoveToward(_recoilOffset, 0, recoveryAmount);
        }

        // Update aim direction and weapon sprite rotation
        UpdateAimDirection();
    }

    /// <summary>
    /// Updates the aim direction based on mouse position.
    /// RSh-12 uses silenced pistol-like low sensitivity for smooth, deliberate aiming.
    /// The heavy revolver is comfortable to aim despite its power.
    /// </summary>
    private void UpdateAimDirection()
    {
        // Get direction to mouse
        Vector2 mousePos = GetGlobalMousePosition();
        Vector2 toMouse = mousePos - GlobalPosition;

        // Calculate target angle from player to mouse
        float targetAngle = toMouse.Angle();

        // Initialize aim angle on first frame
        if (!_aimAngleInitialized)
        {
            _currentAimAngle = targetAngle;
            _aimAngleInitialized = true;
        }

        Vector2 direction;

        // Apply sensitivity "leash" effect when sensitivity is set
        // RSh-12 has same smooth aiming as silenced pistol (sensitivity 2.0)
        if (WeaponData != null && WeaponData.Sensitivity > 0)
        {
            float angleDiff = Mathf.Wrap(targetAngle - _currentAimAngle, -Mathf.Pi, Mathf.Pi);
            float rotationSpeed = WeaponData.Sensitivity * 10.0f;
            float delta = (float)GetProcessDeltaTime();
            float maxRotation = rotationSpeed * delta;
            float actualRotation = Mathf.Clamp(angleDiff, -maxRotation, maxRotation);
            _currentAimAngle += actualRotation;
            direction = new Vector2(Mathf.Cos(_currentAimAngle), Mathf.Sin(_currentAimAngle));
        }
        else
        {
            // Automatic mode: direct aim at cursor (instant response)
            if (toMouse.LengthSquared() > 0.001f)
            {
                direction = toMouse.Normalized();
                _currentAimAngle = targetAngle;
            }
            else
            {
                direction = _aimDirection;
            }
        }

        // Store the aim direction for shooting
        _aimDirection = direction;

        // Update weapon sprite rotation to match aim direction
        UpdateWeaponSpriteRotation(_aimDirection);
    }

    /// <summary>
    /// Updates the weapon sprite rotation to match the aim direction.
    /// Also handles vertical flipping when aiming left.
    /// </summary>
    private void UpdateWeaponSpriteRotation(Vector2 direction)
    {
        if (_weaponSprite == null)
        {
            return;
        }

        float angle = direction.Angle();
        _weaponSprite.Rotation = angle;

        // Flip the sprite vertically when aiming left
        bool aimingLeft = Mathf.Abs(angle) > Mathf.Pi / 2;
        _weaponSprite.FlipV = aimingLeft;
    }

    /// <summary>
    /// Fires the RSh-12 revolver in semi-automatic mode.
    /// Heavy revolver with strong recoil and screen shake.
    /// Very loud - alerts enemies at long range.
    /// </summary>
    /// <param name="direction">Direction to fire (uses aim direction).</param>
    /// <returns>True if the weapon fired successfully.</returns>
    public override bool Fire(Vector2 direction)
    {
        // Check for empty cylinder - play click sound
        if (CurrentAmmo <= 0)
        {
            PlayEmptyClickSound();
            return false;
        }

        // Check if we can fire at all
        if (!CanFire || WeaponData == null || BulletScene == null)
        {
            return false;
        }

        // Apply recoil offset to aim direction
        Vector2 spreadDirection = ApplySpread(_aimDirection);
        bool result = base.Fire(spreadDirection);

        if (result)
        {
            // Play heavy revolver shot sound (uses PM shot as base, louder)
            PlayRevolverShotSound();
            // Emit gunshot sound for in-game sound propagation (very loud)
            EmitGunshotSound();
            // Play shell casing sound with delay (heavy pistol casings)
            PlayShellCasingDelayed();
            // Trigger heavy screen shake (close to sniper rifle)
            TriggerScreenShake(spreadDirection);
        }

        return result;
    }

    /// <summary>
    /// Applies recoil offset to the shooting direction and adds new recoil.
    /// RSh-12 has heavy recoil close to sniper rifle, with extended recovery time.
    /// </summary>
    private Vector2 ApplySpread(Vector2 direction)
    {
        // Apply the current recoil offset to the direction
        Vector2 result = direction.Rotated(_recoilOffset);

        if (WeaponData != null)
        {
            // Apply base spread from weapon data
            float spreadRadians = Mathf.DegToRad(WeaponData.SpreadAngle);

            // Generate random spread within the angle
            float randomSpread = (float)GD.RandRange(-spreadRadians, spreadRadians);
            result = result.Rotated(randomSpread * 0.5f);

            // Add heavy recoil for next shot (close to sniper rifle)
            float recoilDirection = (float)GD.RandRange(-1.0, 1.0);
            _recoilOffset += recoilDirection * RecoilPerShot;
            _recoilOffset = Mathf.Clamp(_recoilOffset, -MaxRecoilOffset, MaxRecoilOffset);
        }

        // Reset time since last shot for recoil recovery
        _timeSinceLastShot = 0;

        return result;
    }

    /// <summary>
    /// Plays the empty gun click sound.
    /// </summary>
    private void PlayEmptyClickSound()
    {
        var audioManager = GetNodeOrNull("/root/AudioManager");
        if (audioManager != null && audioManager.HasMethod("play_empty_click"))
        {
            audioManager.Call("play_empty_click", GlobalPosition);
        }
    }

    /// <summary>
    /// Plays the RSh-12 revolver shot sound via AudioManager.
    /// Uses PM shot sound as a base (heavy pistol shot).
    /// </summary>
    private void PlayRevolverShotSound()
    {
        var audioManager = GetNodeOrNull("/root/AudioManager");
        if (audioManager == null)
        {
            return;
        }

        // Use PM shot sound for now (heavy pistol shot)
        if (audioManager.HasMethod("play_pm_shot"))
        {
            audioManager.Call("play_pm_shot", GlobalPosition);
        }
    }

    /// <summary>
    /// Emits a gunshot sound to SoundPropagation system for in-game sound propagation.
    /// The RSh-12 is very loud (12.7mm round), alerting enemies at long range.
    /// </summary>
    private void EmitGunshotSound()
    {
        var soundPropagation = GetNodeOrNull("/root/SoundPropagation");
        if (soundPropagation != null && soundPropagation.HasMethod("emit_sound"))
        {
            float loudness = WeaponData?.Loudness ?? 2500.0f;
            soundPropagation.Call("emit_sound", 0, GlobalPosition, 0, this, loudness);
        }
    }

    /// <summary>
    /// Plays heavy pistol shell casing sound with a delay.
    /// The RSh-12 ejects larger casings than standard pistols.
    /// </summary>
    private async void PlayShellCasingDelayed()
    {
        await ToSignal(GetTree().CreateTimer(0.12), "timeout");
        var audioManager = GetNodeOrNull("/root/AudioManager");
        if (audioManager != null && audioManager.HasMethod("play_shell_pistol"))
        {
            audioManager.Call("play_shell_pistol", GlobalPosition);
        }
    }

    /// <summary>
    /// Triggers heavy screen shake based on shooting direction.
    /// RSh-12 has strong recoil close to sniper rifle, with extended recovery time.
    /// </summary>
    private void TriggerScreenShake(Vector2 shootDirection)
    {
        if (WeaponData == null || WeaponData.ScreenShakeIntensity <= 0)
        {
            return;
        }

        var screenShakeManager = GetNodeOrNull("/root/ScreenShakeManager");
        if (screenShakeManager == null || !screenShakeManager.HasMethod("add_shake"))
        {
            return;
        }

        // Calculate shake intensity based on fire rate
        float fireRate = WeaponData.FireRate;
        float shakeIntensity;
        if (fireRate > 0)
        {
            shakeIntensity = WeaponData.ScreenShakeIntensity / fireRate * 10.0f;
        }
        else
        {
            shakeIntensity = WeaponData.ScreenShakeIntensity;
        }

        // Use extended recovery time from weapon data
        float recoveryTime = WeaponData.ScreenShakeMinRecoveryTime;

        screenShakeManager.Call("add_shake", shootDirection, shakeIntensity, recoveryTime);
    }

    /// <summary>
    /// Fires the bullet in the chamber during reload sequence.
    /// </summary>
    public override bool FireChamberBullet(Vector2 direction)
    {
        Vector2 spreadDirection = ApplySpread(_aimDirection);
        bool result = base.FireChamberBullet(spreadDirection);

        if (result)
        {
            PlayRevolverShotSound();
            EmitGunshotSound();
            PlayShellCasingDelayed();
            TriggerScreenShake(spreadDirection);
        }

        return result;
    }

    /// <summary>
    /// Override SpawnCasing for RSh-12-specific casing ejection behavior.
    /// RSh-12 casings are pistol-sized but longer and slightly wider (12.7mm).
    /// They eject with moderate force - between pistol and sniper rifle ejection.
    /// </summary>
    protected override void SpawnCasing(Vector2 direction, Resource? caliber)
    {
        if (CasingScene == null)
        {
            return;
        }

        // Calculate casing spawn position (near the weapon, slightly offset)
        Vector2 casingSpawnPosition = GlobalPosition + direction * (BulletSpawnOffset * 0.5f);

        var casing = CasingScene.Instantiate<RigidBody2D>();
        casing.GlobalPosition = casingSpawnPosition;

        // Calculate ejection direction to the right of the weapon
        Vector2 weaponRight = new Vector2(-direction.Y, direction.X);

        // Eject to the right with some randomness
        float randomAngle = (float)GD.RandRange(-0.3f, 0.3f);
        Vector2 ejectionDirection = weaponRight.Rotated(randomAngle);

        // RSh-12: Moderate-fast ejection speed (between pistol 120-180 and sniper 300-400)
        float ejectionSpeed = (float)GD.RandRange(180.0f, 260.0f);
        casing.LinearVelocity = ejectionDirection * ejectionSpeed;

        // Add initial spin for realism (heavy casing)
        casing.AngularVelocity = (float)GD.RandRange(-18.0f, 18.0f);

        // Set caliber data on the casing for appearance
        if (caliber != null)
        {
            casing.Set("caliber_data", caliber);
        }

        GetTree().CurrentScene.AddChild(casing);
    }

    /// <summary>
    /// Spawns a large muzzle flash for the RSh-12 revolver.
    /// The 12.7mm round creates a significant muzzle flash from the revolver's barrel.
    /// </summary>
    protected override void SpawnMuzzleFlash(Vector2 position, Vector2 direction, Resource? caliber)
    {
        var impactManager = GetNodeOrNull("/root/ImpactEffectsManager");
        if (impactManager != null && impactManager.HasMethod("spawn_muzzle_flash"))
        {
            // Pass caliber with large muzzle flash scale for 12.7mm revolver
            impactManager.Call("spawn_muzzle_flash", position, direction, caliber, RevolverMuzzleFlashScale);
        }
    }

    /// <summary>
    /// Gets the current aim direction.
    /// </summary>
    public Vector2 AimDirection => _aimDirection;
}
