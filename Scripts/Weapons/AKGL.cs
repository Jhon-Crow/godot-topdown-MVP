using Godot;
using GodotTopDownTemplate.AbstractClasses;

namespace GodotTopDownTemplate.Weapons;

/// <summary>
/// AK assault rifle with underbarrel grenade launcher (GP-25).
/// Primary fire (LMB): Automatic 7.62x39mm rifle fire.
/// Secondary fire (RMB): Fires a single VOG-25 grenade from the underbarrel launcher.
///
/// Compared to M16 (AssaultRifle):
/// - Damage: 1.5x (7.62mm vs 5.45mm)
/// - Fire rate: slightly lower
/// - Bullet speed: higher
/// - Recoil and screen shake: slightly more
/// - Fewer ricochets (heavier bullet)
/// - Fully penetrates one wall
/// - Has underbarrel grenade launcher (1 grenade)
/// </summary>
public partial class AKGL : BaseWeapon
{
    /// <summary>
    /// Scene for the VOG grenade projectile fired by the underbarrel launcher.
    /// </summary>
    [Export]
    public PackedScene? GrenadeScene { get; set; }

    /// <summary>
    /// Whether the underbarrel grenade has been fired (player gets only 1 shot).
    /// </summary>
    [Export]
    public bool GrenadeAvailable { get; set; } = true;

    /// <summary>
    /// Whether the laser sight is enabled.
    /// </summary>
    [Export]
    public bool LaserSightEnabled { get; set; } = true;

    /// <summary>
    /// Color of the laser sight.
    /// </summary>
    [Export]
    public Color LaserSightColor { get; set; } = new Color(1.0f, 0.0f, 0.0f, 0.5f);

    /// <summary>
    /// Width of the laser sight line.
    /// </summary>
    [Export]
    public float LaserSightWidth { get; set; } = 2.0f;

    /// <summary>
    /// Reference to the Line2D node for the laser sight.
    /// </summary>
    private Line2D? _laserSight;

    /// <summary>
    /// Reference to the Sprite2D node for the rifle visual.
    /// </summary>
    private Sprite2D? _rifleSprite;

    /// <summary>
    /// Current aim direction based on laser sight.
    /// </summary>
    private Vector2 _aimDirection = Vector2.Right;

    /// <summary>
    /// Current aim angle in radians.
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
    /// Slightly longer than M16 for heavier recoil feel.
    /// </summary>
    private const float RecoilRecoveryDelay = 0.12f;

    /// <summary>
    /// Speed at which recoil recovers (radians per second).
    /// Slightly slower than M16 for heavier recoil feel.
    /// </summary>
    private const float RecoilRecoverySpeed = 7.0f;

    /// <summary>
    /// Maximum recoil offset in radians (~6 degrees, slightly more than M16's ~5 degrees).
    /// </summary>
    private const float MaxRecoilOffset = 0.105f;

    /// <summary>
    /// Tracks consecutive shots for spread calculation.
    /// </summary>
    private int _shotCount = 0;

    /// <summary>
    /// Time since last shot for spread reset.
    /// </summary>
    private float _spreadResetTimer = 0.0f;

    /// <summary>
    /// Number of shots before spread starts increasing.
    /// </summary>
    private const int SpreadThreshold = 3;

    /// <summary>
    /// Time in seconds for spread to reset after stopping fire.
    /// </summary>
    private const float SpreadResetTime = 0.25f;

    /// <summary>
    /// Signal emitted when the grenade launcher fires.
    /// </summary>
    [Signal]
    public delegate void GrenadeFiredEventHandler();

    /// <summary>
    /// Signal emitted when grenade availability changes.
    /// </summary>
    [Signal]
    public delegate void GrenadeAvailabilityChangedEventHandler(bool available);

    public override void _Ready()
    {
        base._Ready();

        // Get the rifle sprite
        _rifleSprite = GetNodeOrNull<Sprite2D>("RifleSprite");
        if (_rifleSprite != null)
        {
            GD.Print($"[AKGL] RifleSprite found: visible={_rifleSprite.Visible}, z_index={_rifleSprite.ZIndex}");
        }
        else
        {
            GD.PrintErr("[AKGL] WARNING: RifleSprite node not found!");
        }

        // Check for Power Fantasy mode blue laser
        var difficultyManager = GetNodeOrNull("/root/DifficultyManager");
        if (difficultyManager != null)
        {
            var shouldForceBlueLaser = difficultyManager.Call("should_force_blue_laser_sight");
            if (shouldForceBlueLaser.AsBool())
            {
                var blueColorVariant = difficultyManager.Call("get_power_fantasy_laser_color");
                LaserSightColor = blueColorVariant.AsColor();
                GD.Print($"[AKGL] Power Fantasy mode: laser color set to blue {LaserSightColor}");
            }
        }

        // Get or create the laser sight Line2D
        _laserSight = GetNodeOrNull<Line2D>("LaserSight");
        if (_laserSight == null && LaserSightEnabled)
        {
            CreateLaserSight();
        }
        else if (_laserSight != null)
        {
            _laserSight.Width = LaserSightWidth;
            _laserSight.DefaultColor = LaserSightColor;
            _laserSight.BeginCapMode = Line2D.LineCapMode.Round;
            _laserSight.EndCapMode = Line2D.LineCapMode.Round;

            if (_laserSight.GetPointCount() < 2)
            {
                _laserSight.ClearPoints();
                _laserSight.AddPoint(Vector2.Zero);
                _laserSight.AddPoint(Vector2.Right * 500.0f);
            }
        }

        UpdateLaserSightVisibility();
    }

    public override void _Process(double delta)
    {
        base._Process(delta);

        // Update recoil recovery
        _timeSinceLastShot += (float)delta;
        if (_timeSinceLastShot >= RecoilRecoveryDelay && _recoilOffset != 0)
        {
            float recoveryAmount = RecoilRecoverySpeed * (float)delta;
            _recoilOffset = Mathf.MoveToward(_recoilOffset, 0, recoveryAmount);
        }

        // Update spread reset timer
        _spreadResetTimer += (float)delta;
        if (_spreadResetTimer >= SpreadResetTime)
        {
            _shotCount = 0;
        }

        // Update aim direction and rifle sprite rotation
        UpdateAimDirection();

        // Update laser sight
        if (LaserSightEnabled && _laserSight != null)
        {
            UpdateLaserSight();
        }
    }

    /// <summary>
    /// Updates the aim direction and rifle sprite rotation.
    /// </summary>
    private void UpdateAimDirection()
    {
        Vector2 mousePos = GetGlobalMousePosition();
        Vector2 toMouse = mousePos - GlobalPosition;
        float targetAngle = toMouse.Angle();

        if (!_aimAngleInitialized)
        {
            _currentAimAngle = targetAngle;
            _aimAngleInitialized = true;
        }

        Vector2 direction;

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

        _aimDirection = direction;
        UpdateRifleSpriteRotation(direction);
    }

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

        _laserSight.AddPoint(Vector2.Zero);
        _laserSight.AddPoint(Vector2.Right * 500.0f);

        AddChild(_laserSight);
    }

    /// <summary>
    /// Updates the laser sight visualization with recoil offset.
    /// </summary>
    private void UpdateLaserSight()
    {
        if (_laserSight == null)
        {
            return;
        }

        Vector2 laserDirection = _aimDirection.Rotated(_recoilOffset);

        Viewport? viewport = GetViewport();
        if (viewport == null)
        {
            return;
        }

        Vector2 viewportSize = viewport.GetVisibleRect().Size;
        float maxLaserLength = viewportSize.Length();

        Vector2 endPoint = laserDirection * maxLaserLength;

        var spaceState = GetWorld2D().DirectSpaceState;
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

        _laserSight.SetPointPosition(0, Vector2.Zero);
        _laserSight.SetPointPosition(1, endPoint);
    }

    /// <summary>
    /// Updates the visibility of the laser sight.
    /// </summary>
    private void UpdateLaserSightVisibility()
    {
        if (_laserSight != null)
        {
            _laserSight.Visible = LaserSightEnabled;
        }
    }

    /// <summary>
    /// Updates the rifle sprite rotation to match the aim direction.
    /// </summary>
    private void UpdateRifleSpriteRotation(Vector2 direction)
    {
        if (_rifleSprite == null)
        {
            return;
        }

        float angle = direction.Angle();
        _rifleSprite.Rotation = angle;

        bool aimingLeft = Mathf.Abs(angle) > Mathf.Pi / 2;
        _rifleSprite.FlipV = aimingLeft;
    }

    /// <summary>
    /// Fires the AK rifle. Uses laser aim direction when laser sight is enabled.
    /// </summary>
    public override bool Fire(Vector2 direction)
    {
        if (CurrentAmmo <= 0)
        {
            PlayEmptyClickSound();
            return false;
        }

        if (!CanFire || WeaponData == null || BulletScene == null)
        {
            return false;
        }

        Vector2 fireDirection = LaserSightEnabled ? _aimDirection : direction;
        Vector2 spreadDirection = ApplySpread(fireDirection);
        bool result = base.Fire(spreadDirection);

        if (result)
        {
            PlayAKShotSound();
            EmitGunshotSound();
            PlayShellCasingDelayed();
            TriggerScreenShake(spreadDirection);
            _shotCount++;
            _spreadResetTimer = 0.0f;
        }

        return result;
    }

    /// <summary>
    /// Fires the underbarrel grenade launcher (secondary fire).
    /// The player has only one grenade shot.
    /// </summary>
    public bool FireGrenadeLauncher(Vector2 direction)
    {
        if (!GrenadeAvailable)
        {
            PlayEmptyClickSound();
            GD.Print("[AKGL] Grenade launcher empty - no grenade available");
            return false;
        }

        if (GrenadeScene == null)
        {
            GD.PrintErr("[AKGL] ERROR: GrenadeScene is null!");
            return false;
        }

        // Use laser aim direction when laser sight is enabled
        Vector2 fireDirection = LaserSightEnabled ? _aimDirection : direction;

        // Calculate grenade launch speed to travel 1.5 viewports
        Viewport? viewport = GetViewport();
        float viewportWidth = 1280.0f; // Default fallback
        if (viewport != null)
        {
            viewportWidth = viewport.GetVisibleRect().Size.X;
        }
        // Target distance: 1.5 viewport widths
        // Using formula: d = v² / (2 * friction), so v = sqrt(2 * d * friction)
        // With ground_friction = 280 and target distance = 1.5 * viewportWidth:
        float targetDistance = viewportWidth * 1.5f;
        float groundFriction = 280.0f;
        float launchSpeed = Mathf.Sqrt(2.0f * targetDistance * groundFriction);

        // Spawn the VOG grenade
        var grenade = GrenadeScene.Instantiate<RigidBody2D>();
        grenade.GlobalPosition = GlobalPosition + fireDirection * BulletSpawnOffset;

        GetTree().CurrentScene.AddChild(grenade);

        // Configure and launch the grenade
        // The VOG grenade is fired, not thrown - so we unfreeze and set velocity directly
        grenade.Freeze = false;
        grenade.LinearVelocity = fireDirection.Normalized() * launchSpeed;
        grenade.Rotation = fireDirection.Angle();

        // Mark as launched for impact detection and activate timer
        if (grenade.HasMethod("activate_timer"))
        {
            grenade.Call("activate_timer");
        }
        if (grenade.HasMethod("mark_as_launched"))
        {
            grenade.Call("mark_as_launched");
        }

        // Attach C# GrenadeTimer for reliable explosion handling in exports (Issue #432 pattern)
        var grenadeTimerHelper = GetNodeOrNull("/root/GrenadeTimerHelper");
        if (grenadeTimerHelper != null)
        {
            grenadeTimerHelper.Call("AttachGrenadeTimer", grenade, "Frag");
            grenadeTimerHelper.Call("ActivateTimer", grenade);
            grenadeTimerHelper.Call("MarkAsThrown", grenade);
        }

        // Consume the grenade
        GrenadeAvailable = false;

        // Play launch sound and effects
        PlayGrenadeLaunchSound();
        TriggerGrenadeLaunchScreenShake(fireDirection);
        EmitGunshotSound(); // Grenade launch is loud

        EmitSignal(SignalName.GrenadeFired);
        EmitSignal(SignalName.GrenadeAvailabilityChanged, false);

        GD.Print("[AKGL] Grenade launcher fired! No more grenades available.");
        return true;
    }

    /// <summary>
    /// Gets the current aim direction based on the laser sight.
    /// </summary>
    public Vector2 AimDirection => _aimDirection;

    /// <summary>
    /// Fires the bullet in the chamber during reload sequence.
    /// </summary>
    public override bool FireChamberBullet(Vector2 direction)
    {
        Vector2 fireDirection = LaserSightEnabled ? _aimDirection : direction;
        Vector2 spreadDirection = ApplySpread(fireDirection);

        bool result = base.FireChamberBullet(spreadDirection);

        if (result)
        {
            PlayAKShotSound();
            EmitGunshotSound();
            PlayShellCasingDelayed();
            TriggerScreenShake(spreadDirection);
            _shotCount++;
            _spreadResetTimer = 0.0f;
        }

        return result;
    }

    // =========================================================================
    // Audio Methods
    // =========================================================================

    private void PlayEmptyClickSound()
    {
        var audioManager = GetNodeOrNull("/root/AudioManager");
        if (audioManager != null && audioManager.HasMethod("play_empty_click"))
        {
            audioManager.Call("play_empty_click", GlobalPosition);
        }
    }

    /// <summary>
    /// Plays AK shot sound. Falls back to M16 sound if AK-specific sound is not available.
    /// </summary>
    private void PlayAKShotSound()
    {
        var audioManager = GetNodeOrNull("/root/AudioManager");
        if (audioManager == null)
        {
            return;
        }

        // Try AK-specific sound first, fall back to M16 shot sound
        if (audioManager.HasMethod("play_ak_shot"))
        {
            audioManager.Call("play_ak_shot", GlobalPosition);
        }
        else if (audioManager.HasMethod("play_m16_shot"))
        {
            audioManager.Call("play_m16_shot", GlobalPosition);
        }
    }

    private void EmitGunshotSound()
    {
        var soundPropagation = GetNodeOrNull("/root/SoundPropagation");
        if (soundPropagation != null && soundPropagation.HasMethod("emit_sound"))
        {
            float loudness = WeaponData?.Loudness ?? 1600.0f;
            soundPropagation.Call("emit_sound", 0, GlobalPosition, 0, this, loudness);
        }
    }

    private async void PlayShellCasingDelayed()
    {
        await ToSignal(GetTree().CreateTimer(0.15), "timeout");
        var audioManager = GetNodeOrNull("/root/AudioManager");
        if (audioManager != null && audioManager.HasMethod("play_shell_rifle"))
        {
            audioManager.Call("play_shell_rifle", GlobalPosition);
        }
    }

    private void PlayGrenadeLaunchSound()
    {
        var audioManager = GetNodeOrNull("/root/AudioManager");
        if (audioManager == null)
        {
            return;
        }

        // Try grenade launcher specific sound, fall back to explosion sound
        if (audioManager.HasMethod("play_grenade_launch"))
        {
            audioManager.Call("play_grenade_launch", GlobalPosition);
        }
        else if (audioManager.HasMethod("play_m16_shot"))
        {
            // Fallback to rifle shot sound (grenade launcher makes a distinctive thump)
            audioManager.Call("play_m16_shot", GlobalPosition);
        }
    }

    // =========================================================================
    // Screen Shake
    // =========================================================================

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

        float spreadRatio = 0.0f;
        if (_shotCount > SpreadThreshold)
        {
            spreadRatio = Mathf.Clamp((_shotCount - SpreadThreshold) * 0.15f, 0.0f, 1.0f);
        }

        float minRecovery = WeaponData.ScreenShakeMinRecoveryTime;
        float maxRecovery = Mathf.Max(WeaponData.ScreenShakeMaxRecoveryTime, 0.05f);
        float recoveryTime = Mathf.Lerp(minRecovery, maxRecovery, spreadRatio);

        screenShakeManager.Call("add_shake", shootDirection, shakeIntensity, recoveryTime);
    }

    /// <summary>
    /// Triggers stronger screen shake for grenade launch.
    /// </summary>
    private void TriggerGrenadeLaunchScreenShake(Vector2 direction)
    {
        var screenShakeManager = GetNodeOrNull("/root/ScreenShakeManager");
        if (screenShakeManager == null || !screenShakeManager.HasMethod("add_shake"))
        {
            return;
        }

        // Grenade launch has stronger shake than rifle fire
        float shakeIntensity = 15.0f;
        float recoveryTime = 0.4f;
        screenShakeManager.Call("add_shake", direction, shakeIntensity, recoveryTime);
    }

    // =========================================================================
    // Spread / Recoil
    // =========================================================================

    /// <summary>
    /// Applies recoil offset to the shooting direction and adds new recoil.
    /// </summary>
    private Vector2 ApplySpread(Vector2 direction)
    {
        Vector2 result = direction.Rotated(_recoilOffset);

        if (WeaponData != null && WeaponData.SpreadAngle > 0)
        {
            float spreadRadians = Mathf.DegToRad(WeaponData.SpreadAngle);

            var difficultyManager = GetNodeOrNull("/root/DifficultyManager");
            if (difficultyManager != null)
            {
                var multiplierResult = difficultyManager.Call("get_recoil_multiplier");
                float recoilMultiplier = multiplierResult.AsSingle();
                spreadRadians *= recoilMultiplier;
            }

            float recoilDirection = (float)GD.RandRange(-1.0, 1.0);
            float recoilAmount = spreadRadians * Mathf.Abs(recoilDirection);

            _recoilOffset += recoilDirection * recoilAmount * 0.5f;
            _recoilOffset = Mathf.Clamp(_recoilOffset, -MaxRecoilOffset, MaxRecoilOffset);
        }

        _timeSinceLastShot = 0;

        return result;
    }
}
