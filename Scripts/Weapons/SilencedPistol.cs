using Godot;
using GodotTopDownTemplate.AbstractClasses;
using GodotTopDownTemplate.Projectiles;

namespace GodotTopDownTemplate.Weapons;

/// <summary>
/// Silenced pistol - semi-automatic weapon with suppressor.
/// Features:
/// - Semi-automatic fire (one shot per click)
/// - 9mm bullets with standard damage
/// - Spread same as M16 (2.0 degrees)
/// - Recoil 2x higher than M16, with extended recovery delay
/// - Silent shots (no sound propagation to enemies)
/// - Very low aiming sensitivity (smooth aiming)
/// - Ricochets like other 9mm (same as Uzi)
/// - Does not penetrate walls
/// - Green laser sight for tactical aiming
/// - Stun effect on hit (enemies briefly stunned)
/// - 13 rounds magazine (Beretta M9 style)
/// - Reload similar to M16
/// Reference: Beretta M9 with suppressor and laser sight
/// </summary>
public partial class SilencedPistol : BaseWeapon
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
    /// Silenced pistol has 2x recoil compared to M16.
    /// </summary>
    private float _recoilOffset = 0.0f;

    /// <summary>
    /// Time since the last shot was fired, used for recoil recovery.
    /// </summary>
    private float _timeSinceLastShot = 0.0f;

    /// <summary>
    /// Time in seconds before recoil starts recovering.
    /// Extended delay to simulate realistic pistol handling - user must wait
    /// for recoil to settle before accurate follow-up shots.
    /// </summary>
    private const float RecoilRecoveryDelay = 0.35f;

    /// <summary>
    /// Speed at which recoil recovers (radians per second).
    /// Slower than automatic weapons for deliberate fire.
    /// </summary>
    private const float RecoilRecoverySpeed = 4.0f;

    /// <summary>
    /// Maximum recoil offset in radians (about 10 degrees - 2x assault rifle).
    /// M16 is ±5 degrees, so silenced pistol is ±10 degrees.
    /// </summary>
    private const float MaxRecoilOffset = 0.175f;

    /// <summary>
    /// Recoil amount per shot in radians.
    /// Calculated as 2x M16's recoil per shot.
    /// </summary>
    private const float RecoilPerShot = 0.06f;

    // =========================================================================
    // Laser Sight Configuration
    // =========================================================================

    /// <summary>
    /// Whether the laser sight is enabled.
    /// </summary>
    [Export]
    public bool LaserSightEnabled { get; set; } = true;

    /// <summary>
    /// Maximum length of the laser sight in pixels.
    /// The actual laser length is calculated based on viewport size to appear infinite.
    /// </summary>
    [Export]
    public float LaserSightLength { get; set; } = 500.0f;

    /// <summary>
    /// Color of the laser sight (green for tactical silenced pistol).
    /// </summary>
    [Export]
    public Color LaserSightColor { get; set; } = new Color(0.0f, 1.0f, 0.0f, 0.5f);

    /// <summary>
    /// Width of the laser sight line.
    /// </summary>
    [Export]
    public float LaserSightWidth { get; set; } = 2.0f;

    /// <summary>
    /// Reference to the Line2D node for the laser sight.
    /// </summary>
    private Line2D? _laserSight;

    public override void _Ready()
    {
        base._Ready();

        // Get the weapon sprite for visual representation
        _weaponSprite = GetNodeOrNull<Sprite2D>("PistolSprite");

        if (_weaponSprite != null)
        {
            var texture = _weaponSprite.Texture;
            GD.Print($"[SilencedPistol] PistolSprite found: visible={_weaponSprite.Visible}, z_index={_weaponSprite.ZIndex}, texture={(texture != null ? "loaded" : "NULL")}");
        }
        else
        {
            GD.Print("[SilencedPistol] No PistolSprite node (visual model not yet added)");
        }

        // Get or create the laser sight Line2D
        _laserSight = GetNodeOrNull<Line2D>("LaserSight");

        if (_laserSight == null && LaserSightEnabled)
        {
            CreateLaserSight();
        }
        else if (_laserSight != null)
        {
            // Ensure the existing laser sight has the correct properties
            _laserSight.Width = LaserSightWidth;
            _laserSight.DefaultColor = LaserSightColor;
            _laserSight.BeginCapMode = Line2D.LineCapMode.Round;
            _laserSight.EndCapMode = Line2D.LineCapMode.Round;

            // Ensure proper points exist
            if (_laserSight.GetPointCount() < 2)
            {
                _laserSight.ClearPoints();
                _laserSight.AddPoint(Vector2.Zero);
                _laserSight.AddPoint(Vector2.Right * LaserSightLength);
            }
        }

        UpdateLaserSightVisibility();
        GD.Print($"[SilencedPistol] Green laser sight initialized: enabled={LaserSightEnabled}");
    }

    public override void _Process(double delta)
    {
        base._Process(delta);

        // Update time since last shot for recoil recovery
        _timeSinceLastShot += (float)delta;

        // Recover recoil after extended delay (simulates human recoil control)
        if (_timeSinceLastShot >= RecoilRecoveryDelay && _recoilOffset != 0)
        {
            float recoveryAmount = RecoilRecoverySpeed * (float)delta;
            _recoilOffset = Mathf.MoveToward(_recoilOffset, 0, recoveryAmount);
        }

        // Update aim direction and weapon sprite rotation
        UpdateAimDirection();

        // Update laser sight to point towards mouse (with recoil offset)
        if (LaserSightEnabled && _laserSight != null)
        {
            UpdateLaserSight();
        }
    }

    /// <summary>
    /// Updates the aim direction based on mouse position.
    /// Silenced pistol uses very low sensitivity for smooth, deliberate aiming.
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
        // Silenced pistol has very low sensitivity for smooth, tactical aiming
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

    // =========================================================================
    // Laser Sight Methods
    // =========================================================================

    /// <summary>
    /// Creates the laser sight Line2D programmatically.
    /// </summary>
    private void CreateLaserSight()
    {
        _laserSight = new Line2D
        {
            Name = "LaserSight",
            Width = LaserSightWidth,
            DefaultColor = LaserSightColor,
            BeginCapMode = Line2D.LineCapMode.Round,
            EndCapMode = Line2D.LineCapMode.Round
        };

        // Initialize with two points (start and end)
        _laserSight.AddPoint(Vector2.Zero);
        _laserSight.AddPoint(Vector2.Right * LaserSightLength);

        AddChild(_laserSight);
    }

    /// <summary>
    /// Updates the laser sight visualization.
    /// Uses the aim direction and applies recoil offset.
    /// Uses raycasting to stop at obstacles.
    /// </summary>
    private void UpdateLaserSight()
    {
        if (_laserSight == null)
        {
            return;
        }

        // Apply recoil offset to aim direction for laser visualization
        // This makes the laser show where the bullet will actually go
        Vector2 laserDirection = _aimDirection.Rotated(_recoilOffset);

        // Calculate maximum laser length based on viewport size
        // This ensures the laser extends to viewport edges regardless of direction
        Viewport? viewport = GetViewport();
        if (viewport == null)
        {
            return;
        }

        Vector2 viewportSize = viewport.GetVisibleRect().Size;
        // Use diagonal of viewport to ensure laser reaches edge in any direction
        float maxLaserLength = viewportSize.Length();

        // Calculate the end point of the laser using viewport-based length
        // Use laserDirection (with recoil) instead of base direction
        Vector2 endPoint = laserDirection * maxLaserLength;

        // Perform raycast to check for obstacles
        var spaceState = GetWorld2D().DirectSpaceState;
        var query = PhysicsRayQueryParameters2D.Create(
            GlobalPosition,
            GlobalPosition + endPoint,
            4 // Collision mask for obstacles (layer 3 = value 4)
        );

        var result = spaceState.IntersectRay(query);

        if (result.Count > 0)
        {
            // Hit an obstacle, shorten the laser
            Vector2 hitPosition = (Vector2)result["position"];
            endPoint = hitPosition - GlobalPosition;
        }

        // Update the laser sight line points (in local coordinates)
        _laserSight.SetPointPosition(0, Vector2.Zero);
        _laserSight.SetPointPosition(1, endPoint);
    }

    /// <summary>
    /// Updates the visibility of the laser sight based on LaserSightEnabled.
    /// </summary>
    private void UpdateLaserSightVisibility()
    {
        if (_laserSight != null)
        {
            _laserSight.Visible = LaserSightEnabled;
        }
    }

    /// <summary>
    /// Enables or disables the laser sight.
    /// </summary>
    /// <param name="enabled">Whether to enable the laser sight.</param>
    public void SetLaserSightEnabled(bool enabled)
    {
        LaserSightEnabled = enabled;
        UpdateLaserSightVisibility();
    }

    /// <summary>
    /// Fires the silenced pistol in semi-automatic mode.
    /// Silent shots do not propagate sound to enemies.
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
            // Play silenced shot sound (very quiet, close range only)
            PlaySilencedShotSound();
            // NO sound propagation - enemies don't hear silenced shots
            // Play shell casing sound with delay (pistol casings)
            PlayShellCasingDelayed();
            // Trigger screen shake with extended recoil
            TriggerScreenShake(spreadDirection);
        }

        return result;
    }

    /// <summary>
    /// Applies recoil offset to the shooting direction and adds new recoil.
    /// Silenced pistol has 2x recoil compared to M16, with extended recovery time.
    /// </summary>
    private Vector2 ApplySpread(Vector2 direction)
    {
        // Apply the current recoil offset to the direction
        Vector2 result = direction.Rotated(_recoilOffset);

        if (WeaponData != null)
        {
            // Apply base spread from weapon data (same as M16: 2.0 degrees)
            float spreadRadians = Mathf.DegToRad(WeaponData.SpreadAngle);

            // Generate random spread within the angle
            float randomSpread = (float)GD.RandRange(-spreadRadians, spreadRadians);
            result = result.Rotated(randomSpread * 0.5f);

            // Add strong recoil for next shot (2x assault rifle)
            // This kicks the weapon up/sideways significantly
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
    /// Plays the silenced shot sound via AudioManager.
    /// This is a very quiet sound that doesn't alert enemies.
    /// </summary>
    private void PlaySilencedShotSound()
    {
        var audioManager = GetNodeOrNull("/root/AudioManager");
        if (audioManager != null && audioManager.HasMethod("play_silenced_shot"))
        {
            audioManager.Call("play_silenced_shot", GlobalPosition);
        }
        else
        {
            // Fallback: play pistol bolt sound as placeholder until silenced sound is added
            if (audioManager != null && audioManager.HasMethod("play_sound_2d"))
            {
                // Use pistol bolt sound at very low volume as placeholder
                audioManager.Call("play_sound_2d",
                    "res://assets/audio/взвод затвора пистолета.wav",
                    GlobalPosition,
                    -15.0f);
            }
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
    /// Silenced pistol has strong recoil (2x M16) but with extended recovery time,
    /// simulating the time needed to control pistol recoil.
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
        // This makes the screen shake persist longer, emphasizing recoil
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
            PlaySilencedShotSound();
            PlayShellCasingDelayed();
            TriggerScreenShake(spreadDirection);
        }

        return result;
    }

    /// <summary>
    /// Gets the current aim direction.
    /// </summary>
    public Vector2 AimDirection => _aimDirection;

    /// <summary>
    /// Stun duration applied to enemies on hit.
    /// Duration of 0.6 seconds provides noticeable stun effect and
    /// allows for tactical follow-up shots on stunned enemies.
    /// </summary>
    private const float StunDurationOnHit = 0.6f;

    /// <summary>
    /// Override SpawnBullet to set the stun effect on bullets.
    /// The silenced pistol has a special effect: enemies hit are briefly stunned,
    /// preventing them from shooting or moving for just long enough for the next shot.
    /// </summary>
    /// <param name="direction">Direction for the bullet to travel.</param>
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
            // Wall detected at point-blank range
            spawnPosition = GlobalPosition + direction * 2.0f;
            GD.Print($"[SilencedPistol] Point-blank shot: spawning bullet at weapon position for penetration");
        }
        else
        {
            // Normal case: spawn at offset position
            spawnPosition = GlobalPosition + direction * BulletSpawnOffset;
        }

        var bulletNode = BulletScene.Instantiate<Node2D>();
        bulletNode.GlobalPosition = spawnPosition;

        // Try to cast to C# Bullet type for direct property access
        var bullet = bulletNode as Bullet;

        if (bullet != null)
        {
            // C# Bullet - set properties directly for reliable stun effect
            bullet.Direction = direction;
            if (WeaponData != null)
            {
                bullet.Speed = WeaponData.BulletSpeed;
            }
            var owner = GetParent();
            if (owner != null)
            {
                bullet.ShooterId = owner.GetInstanceId();
            }
            bullet.ShooterPosition = GlobalPosition;

            // Set stun duration for silenced pistol special effect
            // Enemies hit by silenced pistol bullets are briefly stunned,
            // allowing for follow-up shots while they can't retaliate
            bullet.StunDuration = StunDurationOnHit;
            GD.Print($"[SilencedPistol] Spawned C# bullet with StunDuration={StunDurationOnHit}s");
        }
        else
        {
            // GDScript bullet fallback - use Node.Set() for compatibility
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
            }

            var owner = GetParent();
            if (owner != null)
            {
                bulletNode.Set("ShooterId", owner.GetInstanceId());
                bulletNode.Set("shooter_id", owner.GetInstanceId());
            }

            bulletNode.Set("ShooterPosition", GlobalPosition);
            bulletNode.Set("shooter_position", GlobalPosition);

            // Try to set stun duration via Set() for GDScript bullets
            bulletNode.Set("StunDuration", StunDurationOnHit);
            bulletNode.Set("stun_duration", StunDurationOnHit);
            GD.Print($"[SilencedPistol] Spawned GDScript bullet, attempted to set stun_duration={StunDurationOnHit}s");
        }

        GetTree().CurrentScene.AddChild(bulletNode);

        // Spawn casing if casing scene is set
        SpawnCasing(direction, WeaponData?.Caliber);
    }
}
