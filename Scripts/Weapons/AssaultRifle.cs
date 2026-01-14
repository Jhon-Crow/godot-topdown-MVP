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
    /// Whether the weapon is currently firing a burst.
    /// </summary>
    private bool _isBurstFiring;

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

        // Update laser sight to point towards mouse
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
    /// </summary>
    private void UpdateLaserSight()
    {
        if (_laserSight == null)
        {
            return;
        }

        // Get direction to mouse
        Vector2 mousePos = GetGlobalMousePosition();
        Vector2 direction = (mousePos - GlobalPosition).Normalized();

        // Store the aim direction for shooting
        _aimDirection = direction;

        // Calculate maximum laser length based on viewport size
        // This ensures the laser extends to viewport edges regardless of direction
        var viewport = GetViewport();
        if (viewport == null)
        {
            return;
        }

        Vector2 viewportSize = viewport.GetVisibleRect().Size;
        // Use diagonal of viewport to ensure laser reaches edge in any direction
        float maxLaserLength = viewportSize.Length();

        // Calculate the end point of the laser using viewport-based length
        Vector2 endPoint = direction * maxLaserLength;

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

        // Play fire mode toggle sound
        PlayFireModeToggleSound();
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
    /// Plays the fire mode toggle sound when switching between fire modes.
    /// </summary>
    private void PlayFireModeToggleSound()
    {
        var audioManager = GetNodeOrNull("/root/AudioManager");
        if (audioManager != null && audioManager.HasMethod("play_fire_mode_toggle"))
        {
            audioManager.Call("play_fire_mode_toggle", GlobalPosition);
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
    /// Applies spread to the shooting direction based on WeaponData settings.
    /// </summary>
    /// <param name="direction">Original direction.</param>
    /// <returns>Direction with spread applied.</returns>
    private Vector2 ApplySpread(Vector2 direction)
    {
        if (WeaponData == null || WeaponData.SpreadAngle <= 0)
        {
            return direction;
        }

        // Convert spread angle from degrees to radians
        float spreadRadians = Mathf.DegToRad(WeaponData.SpreadAngle);

        // Generate random spread within the angle range
        float randomSpread = (float)GD.RandRange(-spreadRadians / 2, spreadRadians / 2);

        // Rotate the direction by the spread amount
        return direction.Rotated(randomSpread);
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
            // Play shell casing sound with delay
            PlayShellCasingDelayed();
        }

        return result;
    }
}
