using Godot;
using GodotTopDownTemplate.AbstractClasses;

namespace GodotTopDownTemplate.Weapons;

/// <summary>
/// Fire mode for the assault rifle.
/// </summary>
public enum FireMode
{
    /// <summary>
    /// Fully automatic fire - hold to continuously fire.
    /// </summary>
    Automatic,

    /// <summary>
    /// Burst fire - fires multiple bullets per trigger pull.
    /// </summary>
    Burst
}

/// <summary>
/// Assault rifle weapon with automatic and burst fire modes plus laser sight.
/// Inherits from BaseWeapon and extends it with specific assault rifle behavior.
/// Default fire mode is fully automatic.
/// </summary>
public partial class AssaultRifle : BaseWeapon
{
    /// <summary>
    /// Current fire mode of the weapon.
    /// </summary>
    [Export]
    public FireMode CurrentFireMode { get; set; } = FireMode.Automatic;

    /// <summary>
    /// Number of bullets fired in a burst (only used in Burst mode).
    /// </summary>
    [Export]
    public int BurstCount { get; set; } = 3;

    /// <summary>
    /// Delay between each bullet in a burst (in seconds).
    /// </summary>
    [Export]
    public float BurstDelay { get; set; } = 0.05f;

    /// <summary>
    /// Whether the laser sight is enabled.
    /// </summary>
    [Export]
    public bool LaserSightEnabled { get; set; } = true;

    /// <summary>
    /// Maximum length of the laser sight in pixels.
    /// Note: The actual laser length is now calculated based on viewport size to appear infinite.
    /// This property is kept for backward compatibility but is no longer used.
    /// </summary>
    [Export]
    public float LaserSightLength { get; set; } = 500.0f;

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
    /// Current aim direction based on laser sight.
    /// This direction is used for shooting when laser sight is enabled.
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
    /// Whether the weapon is currently firing a burst.
    /// </summary>
    private bool _isBurstFiring;

    /// <summary>
    /// Current recoil offset angle in radians.
    /// This offset is applied to both the laser sight and bullet direction.
    /// </summary>
    private float _recoilOffset = 0.0f;

    /// <summary>
    /// Time since the last shot was fired, used for recoil recovery.
    /// </summary>
    private float _timeSinceLastShot = 0.0f;

    /// <summary>
    /// Time in seconds before recoil starts recovering.
    /// </summary>
    private const float RecoilRecoveryDelay = 0.1f;

    /// <summary>
    /// Speed at which recoil recovers (radians per second).
    /// </summary>
    private const float RecoilRecoverySpeed = 8.0f;

    /// <summary>
    /// Maximum recoil offset in radians (about 5 degrees).
    /// </summary>
    private const float MaxRecoilOffset = 0.087f;

    /// <summary>
    /// Signal emitted when a burst starts.
    /// </summary>
    [Signal]
    public delegate void BurstStartedEventHandler();

    /// <summary>
    /// Signal emitted when a burst finishes.
    /// </summary>
    [Signal]
    public delegate void BurstFinishedEventHandler();

    /// <summary>
    /// Signal emitted when fire mode changes.
    /// </summary>
    [Signal]
    public delegate void FireModeChangedEventHandler(int newMode);

    public override void _Ready()
    {
        base._Ready();

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

            // Ensure it has at least 2 points
            if (_laserSight.GetPointCount() < 2)
            {
                _laserSight.ClearPoints();
                _laserSight.AddPoint(Vector2.Zero);
                _laserSight.AddPoint(Vector2.Right * LaserSightLength);
            }
        }

        UpdateLaserSightVisibility();
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

        // Update laser sight to point towards mouse (with recoil offset)
        if (LaserSightEnabled && _laserSight != null)
        {
            UpdateLaserSight();
        }
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

        // Initialize with two points (start and end)
        _laserSight.AddPoint(Vector2.Zero);
        _laserSight.AddPoint(Vector2.Right * LaserSightLength);

        AddChild(_laserSight);
    }

    /// <summary>
    /// Updates the laser sight to point towards the mouse cursor.
    /// Uses raycasting to stop at obstacles.
    /// Also stores the aim direction for use when shooting.
    /// Applies sensitivity setting from WeaponData to create a "leash" effect:
    /// - Sensitivity > 0: Aim interpolates toward cursor at speed proportional to sensitivity.
    ///   Higher sensitivity = faster rotation, feels like cursor is on a shorter "leash".
    /// - Sensitivity = 0: Direct aim at cursor (automatic mode, instant response).
    /// </summary>
    private void UpdateLaserSight()
    {
        if (_laserSight == null)
        {
            return;
        }

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
        // This makes the aiming consistent regardless of actual cursor position
        if (WeaponData != null && WeaponData.Sensitivity > 0)
        {
            // Calculate angle difference, normalized to [-PI, PI]
            float angleDiff = Mathf.Wrap(targetAngle - _currentAimAngle, -Mathf.Pi, Mathf.Pi);

            // Sensitivity controls rotation speed
            // Higher sensitivity = faster interpolation toward target
            // Base rotation speed is multiplied by sensitivity
            // Sensitivity of 1 = base speed, Sensitivity of 4 = 4x speed
            float rotationSpeed = WeaponData.Sensitivity * 10.0f; // radians per second base

            // Calculate maximum rotation this frame
            float delta = (float)GetProcessDeltaTime();
            float maxRotation = rotationSpeed * delta;

            // Clamp the rotation to not overshoot
            float actualRotation = Mathf.Clamp(angleDiff, -maxRotation, maxRotation);

            // Apply rotation
            _currentAimAngle += actualRotation;

            // Convert angle to direction
            direction = new Vector2(Mathf.Cos(_currentAimAngle), Mathf.Sin(_currentAimAngle));
        }
        else
        {
            // Automatic mode: direct aim at cursor (instant response)
            if (toMouse.LengthSquared() > 0.001f)
            {
                direction = toMouse.Normalized();
                _currentAimAngle = targetAngle; // Keep angle in sync
            }
            else
            {
                direction = _aimDirection; // Keep previous direction if cursor is at player position
            }
        }

        // Store the aim direction for shooting
        _aimDirection = direction;

        // Apply recoil offset to direction for laser visualization
        // This makes the laser show where the bullet will actually go
        Vector2 laserDirection = direction.Rotated(_recoilOffset);

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
    /// Switches between fire modes.
    /// </summary>
    public void ToggleFireMode()
    {
        CurrentFireMode = CurrentFireMode == FireMode.Automatic ? FireMode.Burst : FireMode.Automatic;
        EmitSignal(SignalName.FireModeChanged, (int)CurrentFireMode);
        GD.Print($"[AssaultRifle] Fire mode changed to: {CurrentFireMode}");
    }

    /// <summary>
    /// Sets a specific fire mode.
    /// </summary>
    /// <param name="mode">The fire mode to set.</param>
    public void SetFireMode(FireMode mode)
    {
        if (CurrentFireMode != mode)
        {
            CurrentFireMode = mode;
            EmitSignal(SignalName.FireModeChanged, (int)CurrentFireMode);
            GD.Print($"[AssaultRifle] Fire mode set to: {CurrentFireMode}");
        }
    }

    /// <summary>
    /// Fires the assault rifle based on current fire mode.
    /// Overrides base Fire to implement fire mode behavior.
    /// When laser sight is enabled, uses the laser aim direction instead of the passed direction.
    /// </summary>
    /// <param name="direction">Direction to fire (ignored when laser sight is enabled).</param>
    /// <returns>True if the weapon fired successfully.</returns>
    public override bool Fire(Vector2 direction)
    {
        // Check for empty magazine - play click sound
        if (CurrentAmmo <= 0)
        {
            PlayEmptyClickSound();
            return false;
        }

        // Use laser aim direction when laser sight is enabled
        Vector2 fireDirection = LaserSightEnabled ? _aimDirection : direction;

        if (CurrentFireMode == FireMode.Burst)
        {
            return FireBurst(fireDirection);
        }
        else
        {
            return FireAutomatic(fireDirection);
        }
    }

    /// <summary>
    /// Plays the empty gun click sound when out of ammo.
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
    /// Fires in automatic mode - single bullet per call, respects fire rate.
    /// </summary>
    /// <param name="direction">Direction to fire.</param>
    /// <returns>True if the weapon fired successfully.</returns>
    private bool FireAutomatic(Vector2 direction)
    {
        // Check if we can fire at all
        if (!CanFire || WeaponData == null || BulletScene == null)
        {
            return false;
        }

        // Use base class fire logic for automatic mode
        bool result = base.Fire(ApplySpread(direction));

        if (result)
        {
            // Play M16 shot sound
            PlayM16ShotSound();
            // Emit gunshot sound for in-game sound propagation (alerts enemies)
            EmitGunshotSound();
            // Play shell casing sound with delay
            PlayShellCasingDelayed();
        }

        return result;
    }

    /// <summary>
    /// Plays the M16 shot sound via AudioManager.
    /// </summary>
    private void PlayM16ShotSound()
    {
        var audioManager = GetNodeOrNull("/root/AudioManager");
        if (audioManager != null && audioManager.HasMethod("play_m16_shot"))
        {
            audioManager.Call("play_m16_shot", GlobalPosition);
        }
    }

    /// <summary>
    /// Emits a gunshot sound to SoundPropagation system for in-game sound propagation.
    /// This alerts nearby enemies to the player's position.
    /// </summary>
    private void EmitGunshotSound()
    {
        var soundPropagation = GetNodeOrNull("/root/SoundPropagation");
        if (soundPropagation != null && soundPropagation.HasMethod("emit_sound"))
        {
            // Determine weapon loudness from WeaponData, or use viewport diagonal as default
            float loudness = WeaponData?.Loudness ?? 1469.0f;
            // emit_sound(sound_type, position, source_type, source_node, custom_range)
            // sound_type 0 = GUNSHOT, source_type 0 = PLAYER
            soundPropagation.Call("emit_sound", 0, GlobalPosition, 0, this, loudness);
        }
    }

    /// <summary>
    /// Plays shell casing sound with a delay.
    /// </summary>
    private async void PlayShellCasingDelayed()
    {
        await ToSignal(GetTree().CreateTimer(0.15), "timeout");
        var audioManager = GetNodeOrNull("/root/AudioManager");
        if (audioManager != null && audioManager.HasMethod("play_shell_rifle"))
        {
            audioManager.Call("play_shell_rifle", GlobalPosition);
        }
    }

    /// <summary>
    /// Fires in burst mode - fires multiple bullets per trigger pull.
    /// </summary>
    /// <param name="direction">Direction to fire.</param>
    /// <returns>True if the burst was started successfully.</returns>
    private bool FireBurst(Vector2 direction)
    {
        // Don't start a new burst if already firing
        if (_isBurstFiring)
        {
            return false;
        }

        // Check if we can fire at all
        if (!CanFire || WeaponData == null || BulletScene == null)
        {
            return false;
        }

        // Start burst fire
        StartBurstFire(direction);
        return true;
    }

    /// <summary>
    /// Starts the burst fire sequence.
    /// </summary>
    /// <param name="direction">Direction to fire.</param>
    private async void StartBurstFire(Vector2 direction)
    {
        _isBurstFiring = true;
        EmitSignal(SignalName.BurstStarted);

        int bulletsToFire = Mathf.Min(BurstCount, CurrentAmmo);

        for (int i = 0; i < bulletsToFire; i++)
        {
            if (CurrentAmmo <= 0)
            {
                break;
            }

            // Fire a single bullet with index for sound selection
            FireSingleBulletBurst(direction, i, bulletsToFire);

            // Wait for burst delay before firing next bullet (except for the last one)
            if (i < bulletsToFire - 1)
            {
                await ToSignal(GetTree().CreateTimer(BurstDelay), "timeout");
            }
        }

        _isBurstFiring = false;
        EmitSignal(SignalName.BurstFinished);
    }

    /// <summary>
    /// Fires a single bullet in burst mode with appropriate sound.
    /// First two bullets use double shot sound, third uses single shot.
    /// </summary>
    /// <param name="direction">Direction to fire.</param>
    /// <param name="bulletIndex">Index of bullet in burst (0-based).</param>
    /// <param name="totalBullets">Total bullets in this burst.</param>
    private void FireSingleBulletBurst(Vector2 direction, int bulletIndex, int totalBullets)
    {
        if (WeaponData == null || BulletScene == null || CurrentAmmo <= 0)
        {
            return;
        }

        CurrentAmmo--;

        // Apply spread if configured in WeaponData
        Vector2 spreadDirection = ApplySpread(direction);

        SpawnBullet(spreadDirection);

        // Play appropriate sound based on bullet position in burst
        // First bullet of burst: play double shot sound (includes first two shots)
        // Third bullet: play single shot sound
        if (bulletIndex == 0 && totalBullets >= 2)
        {
            // First bullet - play double shot sound for variety
            PlayM16DoubleShotSound();
        }
        else if (bulletIndex == 2 || (bulletIndex == 0 && totalBullets == 1))
        {
            // Third bullet or single shot - play single shot sound
            PlayM16ShotSound();
        }
        // Second bullet doesn't need sound - covered by double shot sound

        // Emit gunshot sound for in-game sound propagation (alerts enemies)
        EmitGunshotSound();

        // Play shell casing for each bullet
        PlayShellCasingDelayed();

        EmitSignal(SignalName.Fired);
        EmitSignal(SignalName.AmmoChanged, CurrentAmmo, ReserveAmmo);
    }

    /// <summary>
    /// Plays the M16 double shot sound for burst fire.
    /// </summary>
    private void PlayM16DoubleShotSound()
    {
        var audioManager = GetNodeOrNull("/root/AudioManager");
        if (audioManager != null && audioManager.HasMethod("play_m16_double_shot"))
        {
            audioManager.Call("play_m16_double_shot", GlobalPosition);
        }
    }

    /// <summary>
    /// Applies recoil offset to the shooting direction and adds new recoil.
    /// The bullet is fired in the same direction shown by the laser sight,
    /// then recoil is added for the next shot.
    /// </summary>
    /// <param name="direction">Original direction.</param>
    /// <returns>Direction with current recoil applied.</returns>
    private Vector2 ApplySpread(Vector2 direction)
    {
        // Apply the current recoil offset to the direction
        // This matches where the laser is pointing
        Vector2 result = direction.Rotated(_recoilOffset);

        // Add recoil for the next shot
        if (WeaponData != null && WeaponData.SpreadAngle > 0)
        {
            // Convert spread angle from degrees to radians
            float spreadRadians = Mathf.DegToRad(WeaponData.SpreadAngle);

            // Generate random recoil direction (-1 or 1) with small variation
            float recoilDirection = (float)GD.RandRange(-1.0, 1.0);
            float recoilAmount = spreadRadians * Mathf.Abs(recoilDirection);

            // Add to current recoil, clamped to maximum
            _recoilOffset += recoilDirection * recoilAmount * 0.5f;
            _recoilOffset = Mathf.Clamp(_recoilOffset, -MaxRecoilOffset, MaxRecoilOffset);
        }

        // Reset time since last shot for recoil recovery
        _timeSinceLastShot = 0;

        return result;
    }

    /// <summary>
    /// Gets whether the weapon is currently in the middle of a burst.
    /// </summary>
    public bool IsBurstFiring => _isBurstFiring;

    /// <summary>
    /// Gets the current aim direction based on the laser sight.
    /// This is the direction that bullets will travel when fired.
    /// </summary>
    public Vector2 AimDirection => _aimDirection;

    /// <summary>
    /// Fires the bullet in the chamber during reload sequence.
    /// Overrides base to use laser aim direction when laser sight is enabled.
    /// </summary>
    /// <param name="direction">Direction to fire (ignored when laser sight is enabled).</param>
    /// <returns>True if the chamber bullet was fired.</returns>
    public override bool FireChamberBullet(Vector2 direction)
    {
        // Use laser aim direction when laser sight is enabled
        Vector2 fireDirection = LaserSightEnabled ? _aimDirection : direction;

        // Apply spread
        Vector2 spreadDirection = ApplySpread(fireDirection);

        bool result = base.FireChamberBullet(spreadDirection);

        if (result)
        {
            // Play M16 shot sound for chamber bullet
            PlayM16ShotSound();
            // Emit gunshot sound for in-game sound propagation (alerts enemies)
            EmitGunshotSound();
            // Play shell casing sound with delay
            PlayShellCasingDelayed();
        }

        return result;
    }
}
