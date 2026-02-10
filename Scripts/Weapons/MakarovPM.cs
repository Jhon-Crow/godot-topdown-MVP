using Godot;
using GodotTopDownTemplate.AbstractClasses;
using GodotTopDownTemplate.Characters;
using GodotTopDownTemplate.Projectiles;

namespace GodotTopDownTemplate.Weapons;

/// <summary>
/// Makarov PM (Pistolet Makarova) - starting semi-automatic pistol.
/// Features:
/// - Semi-automatic fire (one shot per click)
/// - 9x18mm Makarov bullets with 0.45 damage
/// - 9 rounds magazine
/// - Medium ricochets (same as all pistols/SMGs, max 20 degrees)
/// - Does not penetrate walls
/// - Standard loudness (not silenced)
/// - Moderate recoil with extended recovery
/// - Blue laser sight in Power Fantasy mode
/// Reference: https://ru.wikipedia.org/wiki/Pistolet_Makarova
/// </summary>
public partial class MakarovPM : BaseWeapon
{
    /// <summary>
    /// Reference to the Sprite2D node for the weapon visual.
    /// </summary>
    private Sprite2D? _weaponSprite;

    /// <summary>
    /// Reference to the Line2D node for the laser sight (Power Fantasy mode only).
    /// </summary>
    private Line2D? _laserSight;

    /// <summary>
    /// Glow effect for the laser sight (aura + endpoint glow).
    /// </summary>
    private LaserGlowEffect? _laserGlow;

    /// <summary>
    /// Whether the laser sight is enabled (true only in Power Fantasy mode).
    /// </summary>
    private bool _laserSightEnabled = false;

    /// <summary>
    /// Color of the laser sight (blue in Power Fantasy mode).
    /// </summary>
    private Color _laserSightColor = new Color(0.0f, 0.5f, 1.0f, 0.6f);

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
    /// </summary>
    private float _recoilOffset = 0.0f;

    /// <summary>
    /// Time since the last shot was fired, used for recoil recovery.
    /// </summary>
    private float _timeSinceLastShot = 0.0f;

    /// <summary>
    /// Time in seconds before recoil starts recovering.
    /// Moderate delay for a standard pistol.
    /// </summary>
    private const float RecoilRecoveryDelay = 0.30f;

    /// <summary>
    /// Speed at which recoil recovers (radians per second).
    /// </summary>
    private const float RecoilRecoverySpeed = 4.5f;

    /// <summary>
    /// Maximum recoil offset in radians (about 8 degrees).
    /// Slightly less than the silenced pistol since PM has lower muzzle energy.
    /// </summary>
    private const float MaxRecoilOffset = 0.14f;

    /// <summary>
    /// Recoil amount per shot in radians.
    /// </summary>
    private const float RecoilPerShot = 0.05f;

    public override void _Ready()
    {
        base._Ready();

        // Get the weapon sprite for visual representation
        _weaponSprite = GetNodeOrNull<Sprite2D>("MakarovSprite");

        if (_weaponSprite != null)
        {
            var texture = _weaponSprite.Texture;
            GD.Print($"[MakarovPM] MakarovSprite found: visible={_weaponSprite.Visible}, z_index={_weaponSprite.ZIndex}, texture={(texture != null ? "loaded" : "NULL")}");
        }
        else
        {
            GD.Print("[MakarovPM] No MakarovSprite node (visual model not yet added)");
        }

        // Check for Power Fantasy mode - enable blue laser sight
        var difficultyManager = GetNodeOrNull("/root/DifficultyManager");
        if (difficultyManager != null)
        {
            var shouldForceBlueLaser = difficultyManager.Call("should_force_blue_laser_sight");
            if (shouldForceBlueLaser.AsBool())
            {
                _laserSightEnabled = true;
                var blueColorVariant = difficultyManager.Call("get_power_fantasy_laser_color");
                _laserSightColor = blueColorVariant.AsColor();
                CreateLaserSight();
                GD.Print($"[MakarovPM] Power Fantasy mode: blue laser sight enabled with color {_laserSightColor}");
            }
        }
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

        // Update laser sight (Power Fantasy mode)
        if (_laserSightEnabled && _laserSight != null)
        {
            UpdateLaserSight();
        }
    }

    /// <summary>
    /// Updates the aim direction based on mouse position.
    /// Uses sensitivity-based aiming for smooth rotation.
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
    /// Fires the Makarov PM in semi-automatic mode.
    /// Standard loudness - alerts enemies.
    /// </summary>
    /// <param name="direction">Direction to fire (uses aim direction).</param>
    /// <returns>True if the weapon fired successfully.</returns>
    public override bool Fire(Vector2 direction)
    {
        // Check for empty magazine - play click sound
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
            // Play pistol shot sound
            PlayPistolShotSound();
            // Emit gunshot sound for in-game sound propagation (alerts enemies)
            EmitGunshotSound();
            // Play shell casing sound with delay
            PlayShellCasingDelayed();
            // Trigger screen shake
            TriggerScreenShake(spreadDirection);
        }

        return result;
    }

    /// <summary>
    /// Applies recoil offset to the shooting direction and adds new recoil.
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

            // Add recoil for next shot
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
    /// Plays the Makarov PM shot sound via AudioManager.
    /// </summary>
    private void PlayPistolShotSound()
    {
        var audioManager = GetNodeOrNull("/root/AudioManager");
        if (audioManager != null && audioManager.HasMethod("play_pm_shot"))
        {
            audioManager.Call("play_pm_shot", GlobalPosition);
        }
    }

    /// <summary>
    /// Emits a gunshot sound to SoundPropagation system for in-game sound propagation.
    /// </summary>
    private void EmitGunshotSound()
    {
        var soundPropagation = GetNodeOrNull("/root/SoundPropagation");
        if (soundPropagation != null && soundPropagation.HasMethod("emit_sound"))
        {
            float loudness = WeaponData?.Loudness ?? 1469.0f;
            soundPropagation.Call("emit_sound", 0, GlobalPosition, 0, this, loudness);
        }
    }

    /// <summary>
    /// Plays pistol shell casing sound with a delay.
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
    /// Triggers screen shake based on shooting direction.
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
            PlayPistolShotSound();
            EmitGunshotSound();
            PlayShellCasingDelayed();
            TriggerScreenShake(spreadDirection);
        }

        return result;
    }

    /// <summary>
    /// Stun duration in seconds applied to enemies hit by PM bullets (Issue #592).
    /// 100ms provides a brief flinch effect on hit.
    /// </summary>
    private const float StunDurationOnHit = 0.1f;

    /// <summary>
    /// Override SpawnBullet to set StunDuration on PM bullets (Issue #592).
    /// Enemies hit by PM bullets are briefly stunned (100ms).
    /// </summary>
    protected override void SpawnBullet(Vector2 direction)
    {
        if (BulletScene == null)
        {
            return;
        }

        // Check if the bullet spawn path is blocked by a wall
        var (isBlocked, hitPosition, hitNormal) = CheckBulletSpawnPath(direction);

        Vector2 spawnPosition;
        if (isBlocked)
        {
            spawnPosition = GlobalPosition + direction * 2.0f;
        }
        else
        {
            spawnPosition = GlobalPosition + direction * BulletSpawnOffset;
        }

        var bulletNode = BulletScene.Instantiate<Node2D>();
        bulletNode.GlobalPosition = spawnPosition;

        // Try to cast to C# Bullet type for direct property access
        var bullet = bulletNode as Bullet;

        if (bullet != null)
        {
            bullet.Direction = direction;
            if (WeaponData != null)
            {
                bullet.Speed = WeaponData.BulletSpeed;
                bullet.Damage = WeaponData.Damage;
            }
            var owner = GetParent();
            if (owner != null)
            {
                bullet.ShooterId = owner.GetInstanceId();
            }
            bullet.ShooterPosition = GlobalPosition;
            bullet.StunDuration = StunDurationOnHit;
        }
        else
        {
            // GDScript bullet fallback
            if (bulletNode.HasMethod("SetDirection"))
            {
                bulletNode.Call("SetDirection", direction);
            }
            else
            {
                bulletNode.Set("Direction", direction);
                bulletNode.Set("direction", direction);
            }

            if (WeaponData != null)
            {
                bulletNode.Set("Speed", WeaponData.BulletSpeed);
                bulletNode.Set("speed", WeaponData.BulletSpeed);
                bulletNode.Set("Damage", WeaponData.Damage);
                bulletNode.Set("damage", WeaponData.Damage);
            }

            var owner = GetParent();
            if (owner != null)
            {
                bulletNode.Set("ShooterId", owner.GetInstanceId());
                bulletNode.Set("shooter_id", owner.GetInstanceId());
            }

            bulletNode.Set("ShooterPosition", GlobalPosition);
            bulletNode.Set("shooter_position", GlobalPosition);
            bulletNode.Set("StunDuration", StunDurationOnHit);
            bulletNode.Set("stun_duration", StunDurationOnHit);
        }

        // Set breaker bullet flag if breaker bullets active item is selected (Issue #678)
        if (IsBreakerBulletActive)
        {
            bulletNode.Set("is_breaker_bullet", true);
        }

        GetTree().CurrentScene.AddChild(bulletNode);

        // Enable homing on the bullet if the player's homing effect is active (Issue #704)
        // When firing during activation, use aim-line targeting (nearest to crosshair)
        var weaponOwner = GetParent();
        if (weaponOwner is Player player && player.IsHomingActive())
        {
            Vector2 aimDir = (GetGlobalMousePosition() - player.GlobalPosition).Normalized();
            if (bullet != null)
            {
                bullet.EnableHomingWithAimLine(player.GlobalPosition, aimDir);
            }
            else if (bulletNode.HasMethod("enable_homing_with_aim_line"))
            {
                bulletNode.Call("enable_homing_with_aim_line", player.GlobalPosition, aimDir);
            }
            else if (bulletNode.HasMethod("enable_homing"))
            {
                bulletNode.Call("enable_homing");
            }
        }

        // Spawn muzzle flash effect
        SpawnMuzzleFlash(spawnPosition, direction, WeaponData?.Caliber);

        // Spawn casing
        SpawnCasing(direction, WeaponData?.Caliber);
    }

    /// <summary>
    /// Gets the current aim direction.
    /// </summary>
    public Vector2 AimDirection => _aimDirection;

    #region Power Fantasy Laser Sight

    /// <summary>
    /// Creates the laser sight Line2D programmatically (Power Fantasy mode only).
    /// </summary>
    private void CreateLaserSight()
    {
        _laserSight = new Line2D
        {
            Name = "LaserSight",
            Width = 2.0f,
            DefaultColor = _laserSightColor,
            BeginCapMode = Line2D.LineCapMode.Round,
            EndCapMode = Line2D.LineCapMode.Round
        };

        _laserSight.AddPoint(Vector2.Zero);
        _laserSight.AddPoint(Vector2.Right * 500.0f);

        AddChild(_laserSight);

        // Create glow effect (aura + endpoint glow)
        _laserGlow = new LaserGlowEffect();
        _laserGlow.Create(this, _laserSightColor);
    }

    /// <summary>
    /// Updates the laser sight visualization (Power Fantasy mode only).
    /// The laser shows where bullets will go, accounting for current spread/recoil.
    /// </summary>
    private void UpdateLaserSight()
    {
        if (_laserSight == null)
        {
            return;
        }

        // Apply recoil offset to aim direction for laser visualization
        Vector2 laserDirection = _aimDirection.Rotated(_recoilOffset);

        // Calculate maximum laser length based on viewport size
        Vector2 viewportSize = GetViewport().GetVisibleRect().Size;
        float maxLaserLength = viewportSize.Length();

        // Calculate the end point of the laser
        Vector2 endPoint = laserDirection * maxLaserLength;

        // Raycast to find obstacles
        var spaceState = GetWorld2D()?.DirectSpaceState;
        if (spaceState != null)
        {
            var query = PhysicsRayQueryParameters2D.Create(
                GlobalPosition,
                GlobalPosition + endPoint,
                4 // Collision mask for obstacles
            );

            var result = spaceState.IntersectRay(query);
            if (result.Count > 0)
            {
                Vector2 hitPosition = (Vector2)result["position"];
                endPoint = hitPosition - GlobalPosition;
            }
        }

        // Update the laser sight line points (in local coordinates)
        _laserSight.SetPointPosition(0, Vector2.Zero);
        _laserSight.SetPointPosition(1, endPoint);

        // Sync glow effect with laser
        _laserGlow?.Update(Vector2.Zero, endPoint);
    }

    #endregion
}
