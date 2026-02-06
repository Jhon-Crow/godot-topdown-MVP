using Godot;
using GodotTopDownTemplate.AbstractClasses;
using GodotTopDownTemplate.Projectiles;

namespace GodotTopDownTemplate.Weapons;

/// <summary>
/// Bolt-action charging state for the ASVK sniper rifle.
/// Before each shot, the player must complete a 4-step bolt-action sequence:
/// Down (pull bolt back) → Left (open bolt) → Down (close bolt) → Up (chamber round)
/// </summary>
public enum BoltActionStep
{
    /// <summary>
    /// Bolt is ready - weapon can fire. After firing, transitions to NeedsBoltCycle.
    /// </summary>
    Ready,

    /// <summary>
    /// Just fired - needs bolt cycling before next shot.
    /// Waiting for Down arrow (pull bolt back).
    /// </summary>
    NeedsBoltCycle,

    /// <summary>
    /// Step 1 complete (bolt pulled back). Waiting for Left arrow (open bolt).
    /// </summary>
    WaitOpenBolt,

    /// <summary>
    /// Step 2 complete (bolt opened). Waiting for Down arrow (close bolt).
    /// </summary>
    WaitCloseBolt,

    /// <summary>
    /// Step 3 complete (bolt closed). Waiting for Up arrow (chamber round).
    /// </summary>
    WaitChamberRound
}

/// <summary>
/// ASVK sniper rifle - heavy anti-materiel bolt-action rifle.
/// Features:
/// - 12.7x108mm ammunition dealing 50 damage per shot
/// - Penetrates through 2 walls and through enemies
/// - Instant bullet speed with smoky dissipating tracer trail
/// - Very high turn sensitivity
/// - 5-round magazine with M16-style swap reload
/// - Single-shot bolt-action with manual charging sequence (Down→Left→Down→Up)
/// - Red laser sight for aiming
/// Reference: ASVK (АСВК) anti-materiel sniper rifle
/// </summary>
public partial class SniperRifle : BaseWeapon
{
    // =========================================================================
    // Bolt-Action State
    // =========================================================================

    /// <summary>
    /// Current bolt-action charging step.
    /// </summary>
    private BoltActionStep _boltStep = BoltActionStep.Ready;

    /// <summary>
    /// Whether the bolt action is ready to fire (chambered).
    /// Initially true so first shot can be fired immediately.
    /// </summary>
    public bool IsBoltReady => _boltStep == BoltActionStep.Ready;

    /// <summary>
    /// Whether the weapon needs bolt cycling before it can fire again.
    /// </summary>
    public bool NeedsBoltCycle => _boltStep != BoltActionStep.Ready;

    /// <summary>
    /// Signal emitted when bolt-action step changes.
    /// </summary>
    [Signal]
    public delegate void BoltStepChangedEventHandler(int step, int totalSteps);

    // =========================================================================
    // Smoky Tracer Trail
    // =========================================================================

    /// <summary>
    /// Scene for the smoky tracer trail effect.
    /// Created programmatically as a Line2D with smoke-like appearance.
    /// </summary>
    private Line2D? _lastTracerTrail;

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
    /// </summary>
    [Export]
    public float LaserSightLength { get; set; } = 500.0f;

    /// <summary>
    /// Color of the laser sight (red for sniper).
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
    /// Heavy sniper recoil.
    /// </summary>
    private float _recoilOffset = 0.0f;

    /// <summary>
    /// Time since the last shot was fired, used for recoil recovery.
    /// </summary>
    private float _timeSinceLastShot = 0.0f;

    /// <summary>
    /// Time in seconds before recoil starts recovering.
    /// Long delay for heavy sniper.
    /// </summary>
    private const float RecoilRecoveryDelay = 0.5f;

    /// <summary>
    /// Speed at which recoil recovers (radians per second).
    /// </summary>
    private const float RecoilRecoverySpeed = 3.0f;

    /// <summary>
    /// Maximum recoil offset in radians (about 15 degrees).
    /// </summary>
    private const float MaxRecoilOffset = 0.26f;

    /// <summary>
    /// Recoil amount per shot in radians.
    /// Heavy kick for 12.7mm.
    /// </summary>
    private const float RecoilPerShot = 0.15f;

    /// <summary>
    /// Number of walls this bullet can penetrate through.
    /// The bullet continues flying after penetrating walls.
    /// </summary>
    private const int MaxWallPenetrations = 2;

    public override void _Ready()
    {
        base._Ready();

        // Get the rifle sprite for visual representation
        _rifleSprite = GetNodeOrNull<Sprite2D>("RifleSprite");

        if (_rifleSprite != null)
        {
            var texture = _rifleSprite.Texture;
            GD.Print($"[SniperRifle] RifleSprite found: visible={_rifleSprite.Visible}, z_index={_rifleSprite.ZIndex}, texture={(texture != null ? "loaded" : "NULL")}");
        }
        else
        {
            GD.PrintErr("[SniperRifle] WARNING: RifleSprite node not found!");
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
                GD.Print($"[SniperRifle] Power Fantasy mode: laser color set to blue {LaserSightColor}");
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
                _laserSight.AddPoint(Vector2.Right * LaserSightLength);
            }
        }

        UpdateLaserSightVisibility();
        GD.Print("[SniperRifle] ASVK initialized - bolt ready, laser sight enabled");
    }

    public override void _ExitTree()
    {
        // Clean up scope overlay when weapon is removed from scene tree
        if (_isScopeActive)
        {
            DeactivateScope();
        }
        base._ExitTree();
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

        // Always update aim direction and rifle sprite rotation
        UpdateAimDirection();

        // Update laser sight to point towards mouse (with recoil offset)
        if (LaserSightEnabled && _laserSight != null)
        {
            UpdateLaserSight();
        }

        // Handle bolt-action input
        HandleBoltActionInput();

        // Update scope system (sway, camera offset, overlay)
        UpdateScope((float)delta);
    }

    // =========================================================================
    // Bolt-Action Charging Mechanics
    // =========================================================================

    /// <summary>
    /// Handles the bolt-action charging input sequence.
    /// Sequence: Down (pull bolt) → Left (open bolt) → Down (close bolt) → Up (chamber round)
    /// Uses the arrow keys / WASD movement input actions.
    /// </summary>
    private void HandleBoltActionInput()
    {
        switch (_boltStep)
        {
            case BoltActionStep.NeedsBoltCycle:
                // Step 1: Down arrow - pull bolt back
                if (Input.IsActionJustPressed("move_down"))
                {
                    _boltStep = BoltActionStep.WaitOpenBolt;
                    EmitSignal(SignalName.BoltStepChanged, 1, 4);
                    PlayBoltSound();
                    GD.Print("[SniperRifle] Bolt step 1/4: Bolt pulled back");
                }
                break;

            case BoltActionStep.WaitOpenBolt:
                // Step 2: Left arrow - open bolt
                if (Input.IsActionJustPressed("move_left"))
                {
                    _boltStep = BoltActionStep.WaitCloseBolt;
                    EmitSignal(SignalName.BoltStepChanged, 2, 4);
                    PlayBoltSound();
                    GD.Print("[SniperRifle] Bolt step 2/4: Bolt opened");
                }
                break;

            case BoltActionStep.WaitCloseBolt:
                // Step 3: Down arrow - close bolt
                if (Input.IsActionJustPressed("move_down"))
                {
                    _boltStep = BoltActionStep.WaitChamberRound;
                    EmitSignal(SignalName.BoltStepChanged, 3, 4);
                    PlayBoltSound();
                    GD.Print("[SniperRifle] Bolt step 3/4: Bolt closed");
                }
                break;

            case BoltActionStep.WaitChamberRound:
                // Step 4: Up arrow - chamber round
                if (Input.IsActionJustPressed("move_up"))
                {
                    _boltStep = BoltActionStep.Ready;
                    EmitSignal(SignalName.BoltStepChanged, 4, 4);
                    PlayBoltChamberSound();
                    GD.Print("[SniperRifle] Bolt step 4/4: Round chambered - READY TO FIRE");
                }
                break;

            case BoltActionStep.Ready:
                // Already ready, no bolt action needed
                break;
        }
    }

    /// <summary>
    /// Plays the bolt manipulation sound.
    /// </summary>
    private void PlayBoltSound()
    {
        var audioManager = GetNodeOrNull("/root/AudioManager");
        if (audioManager != null && audioManager.HasMethod("play_m16_bolt"))
        {
            audioManager.Call("play_m16_bolt", GlobalPosition);
        }
    }

    /// <summary>
    /// Plays the bolt chamber/ready sound.
    /// </summary>
    private void PlayBoltChamberSound()
    {
        var audioManager = GetNodeOrNull("/root/AudioManager");
        if (audioManager != null && audioManager.HasMethod("play_m16_bolt"))
        {
            audioManager.Call("play_m16_bolt", GlobalPosition);
        }
    }

    // =========================================================================
    // Aiming and Laser Sight
    // =========================================================================

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

        // Apply sensitivity for the sniper rifle
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
        _laserSight.AddPoint(Vector2.Right * LaserSightLength);

        AddChild(_laserSight);
    }

    /// <summary>
    /// Updates the laser sight visualization with recoil offset.
    /// Uses raycasting to stop at obstacles.
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
            4 // Collision mask for obstacles (layer 3 = value 4)
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
    /// Updates the rifle sprite rotation to match aim direction.
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
    /// Enables or disables the laser sight.
    /// </summary>
    public void SetLaserSightEnabled(bool enabled)
    {
        LaserSightEnabled = enabled;
        UpdateLaserSightVisibility();
    }

    // =========================================================================
    // Firing
    // =========================================================================

    /// <summary>
    /// Fires the sniper rifle. Only fires if bolt is ready.
    /// After firing, transitions to NeedsBoltCycle state.
    /// </summary>
    public override bool Fire(Vector2 direction)
    {
        // Check for empty magazine
        if (CurrentAmmo <= 0)
        {
            PlayEmptyClickSound();
            return false;
        }

        // Check if bolt is ready
        if (!IsBoltReady)
        {
            // Play a click to indicate bolt not cycled
            PlayEmptyClickSound();
            return false;
        }

        // Check standard fire conditions
        if (!CanFire || WeaponData == null || BulletScene == null)
        {
            return false;
        }

        // Apply recoil to aim direction
        Vector2 spreadDirection = ApplyRecoil(_aimDirection);
        bool result = base.Fire(spreadDirection);

        if (result)
        {
            // Transition to needs bolt cycle
            _boltStep = BoltActionStep.NeedsBoltCycle;
            EmitSignal(SignalName.BoltStepChanged, 0, 4);

            // Play sniper shot sound
            PlaySniperShotSound();
            // Emit gunshot sound for enemy detection
            EmitGunshotSound();
            // Play shell casing with delay
            PlayShellCasingDelayed();
            // Trigger heavy screen shake
            TriggerScreenShake(spreadDirection);

            // Spawn smoky tracer trail
            SpawnSmokyTracer(GlobalPosition, spreadDirection);

            GD.Print("[SniperRifle] FIRED! Bolt needs cycling. Ammo remaining: " + CurrentAmmo);
        }

        return result;
    }

    /// <summary>
    /// Override SpawnBullet to configure the SniperBullet for sniper behavior:
    /// - Very high damage (50)
    /// - Passes through enemies (doesn't destroy on hit)
    /// - Penetrates through 2 walls (wall-count based, not distance-based)
    /// </summary>
    protected override void SpawnBullet(Vector2 direction)
    {
        if (BulletScene == null)
        {
            return;
        }

        // Check bullet spawn path
        var (isBlocked, hitPosition, hitNormal) = CheckBulletSpawnPath(direction);

        Vector2 spawnPosition;
        if (isBlocked)
        {
            spawnPosition = GlobalPosition + direction * 2.0f;
            GD.Print("[SniperRifle] Point-blank shot: spawning for penetration");
        }
        else
        {
            spawnPosition = GlobalPosition + direction * BulletSpawnOffset;
        }

        var bulletNode = BulletScene.Instantiate<Node2D>();
        bulletNode.GlobalPosition = spawnPosition;

        // Try to cast to C# SniperBullet for direct property access
        var sniperBullet = bulletNode as SniperBullet;

        if (sniperBullet != null)
        {
            // SniperBullet - set properties directly
            sniperBullet.Direction = direction;
            if (WeaponData != null)
            {
                sniperBullet.Speed = WeaponData.BulletSpeed;
                sniperBullet.Damage = WeaponData.Damage;
            }
            var owner = GetParent();
            if (owner != null)
            {
                sniperBullet.ShooterId = owner.GetInstanceId();
            }
            sniperBullet.ShooterPosition = GlobalPosition;
            sniperBullet.MaxWallPenetrations = MaxWallPenetrations;
            GD.Print($"[SniperRifle] Spawned SniperBullet: Damage={sniperBullet.Damage}, Speed={sniperBullet.Speed}, MaxWallPen={MaxWallPenetrations}");
        }
        else
        {
            // Fallback for any bullet type
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
        }

        GetTree().CurrentScene.AddChild(bulletNode);

        // Spawn muzzle flash effect - large flash for 12.7mm
        SpawnMuzzleFlash(spawnPosition, direction, WeaponData?.Caliber);

        // Spawn casing
        SpawnCasing(direction, WeaponData?.Caliber);
    }

    // =========================================================================
    // Smoky Tracer Trail
    // =========================================================================

    /// <summary>
    /// Spawns a smoky dissipating tracer trail from the fire position
    /// in the shooting direction across the entire map.
    /// The tracer is an instant visual effect (like a contrail from a plane)
    /// that fades out over time.
    /// </summary>
    private void SpawnSmokyTracer(Vector2 fromPosition, Vector2 direction)
    {
        // Calculate tracer end point - extend to edge of map (very far)
        float tracerLength = 5000.0f; // Far enough to reach any map edge
        Vector2 endPosition = fromPosition + direction * tracerLength;

        // Create the tracer as a Line2D with smoke-like appearance
        var tracer = new Line2D
        {
            Name = "SniperTracer",
            Width = 6.0f,
            DefaultColor = new Color(0.8f, 0.8f, 0.8f, 0.7f),
            BeginCapMode = Line2D.LineCapMode.Round,
            EndCapMode = Line2D.LineCapMode.Round,
            TopLevel = true,
            Position = Vector2.Zero,
            ZIndex = -1 // Behind other elements
        };

        // Set up width curve - wider at start, tapers to narrower at end
        var widthCurve = new Curve();
        widthCurve.AddPoint(new Vector2(0.0f, 1.0f));
        widthCurve.AddPoint(new Vector2(0.3f, 0.8f));
        widthCurve.AddPoint(new Vector2(1.0f, 0.3f));
        tracer.WidthCurve = widthCurve;

        // Set up gradient - smoky white/gray that fades out
        var gradient = new Gradient();
        gradient.SetColor(0, new Color(0.9f, 0.9f, 0.85f, 0.8f));
        gradient.AddPoint(0.5f, new Color(0.7f, 0.7f, 0.65f, 0.5f));
        gradient.SetColor(gradient.GetPointCount() - 1, new Color(0.5f, 0.5f, 0.5f, 0.2f));
        tracer.Gradient = gradient;

        // Add the tracer line points (using global coordinates since TopLevel=true)
        tracer.AddPoint(fromPosition + direction * BulletSpawnOffset);
        tracer.AddPoint(endPosition);

        // Add to scene
        GetTree().CurrentScene.AddChild(tracer);

        // Start the fade-out animation
        FadeOutTracer(tracer);
    }

    /// <summary>
    /// Animates the tracer trail fading out and dissipating over time.
    /// The tracer gradually becomes more transparent and wider (simulating smoke dissipation).
    /// </summary>
    private async void FadeOutTracer(Line2D tracer)
    {
        float fadeDuration = 2.0f;
        float elapsed = 0.0f;

        float initialWidth = tracer.Width;

        while (elapsed < fadeDuration && IsInstanceValid(tracer))
        {
            elapsed += (float)GetProcessDeltaTime();
            float progress = elapsed / fadeDuration;

            // Fade the alpha
            float alpha = Mathf.Lerp(0.7f, 0.0f, progress);
            tracer.DefaultColor = new Color(0.8f, 0.8f, 0.8f, alpha);

            // Widen slightly to simulate smoke dissipation
            tracer.Width = initialWidth + progress * 4.0f;

            // Update gradient alpha
            var gradient = new Gradient();
            gradient.SetColor(0, new Color(0.9f, 0.9f, 0.85f, alpha));
            gradient.AddPoint(0.5f, new Color(0.7f, 0.7f, 0.65f, alpha * 0.6f));
            gradient.SetColor(gradient.GetPointCount() - 1, new Color(0.5f, 0.5f, 0.5f, alpha * 0.3f));
            tracer.Gradient = gradient;

            await ToSignal(GetTree(), "process_frame");
        }

        // Remove the tracer after fade completes
        if (IsInstanceValid(tracer))
        {
            tracer.QueueFree();
        }
    }

    // =========================================================================
    // Sound and Effects
    // =========================================================================

    /// <summary>
    /// Plays the sniper shot sound via AudioManager.
    /// </summary>
    private void PlaySniperShotSound()
    {
        var audioManager = GetNodeOrNull("/root/AudioManager");
        // Use M16 shot as a placeholder sound for the sniper
        if (audioManager != null && audioManager.HasMethod("play_m16_shot"))
        {
            audioManager.Call("play_m16_shot", GlobalPosition);
        }
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
    /// Emits gunshot sound for enemy detection via SoundPropagation.
    /// Very loud for the 12.7mm round.
    /// </summary>
    private void EmitGunshotSound()
    {
        var soundPropagation = GetNodeOrNull("/root/SoundPropagation");
        if (soundPropagation != null && soundPropagation.HasMethod("emit_sound"))
        {
            float loudness = WeaponData?.Loudness ?? 3000.0f;
            soundPropagation.Call("emit_sound", 0, GlobalPosition, 0, this, loudness);
        }
    }

    /// <summary>
    /// Plays shell casing sound with a delay.
    /// </summary>
    private async void PlayShellCasingDelayed()
    {
        await ToSignal(GetTree().CreateTimer(0.2), "timeout");
        var audioManager = GetNodeOrNull("/root/AudioManager");
        if (audioManager != null && audioManager.HasMethod("play_shell_rifle"))
        {
            audioManager.Call("play_shell_rifle", GlobalPosition);
        }
    }

    /// <summary>
    /// Applies recoil to shooting direction.
    /// </summary>
    private Vector2 ApplyRecoil(Vector2 direction)
    {
        // Apply current recoil offset
        Vector2 result = direction.Rotated(_recoilOffset);

        // Add strong recoil for next shot (heavy 12.7mm kick)
        float recoilDirection = (float)GD.RandRange(-1.0, 1.0);
        _recoilOffset += recoilDirection * RecoilPerShot;
        _recoilOffset = Mathf.Clamp(_recoilOffset, -MaxRecoilOffset, MaxRecoilOffset);

        _timeSinceLastShot = 0;

        return result;
    }

    /// <summary>
    /// Triggers screen shake from sniper shot.
    /// Heavy shake for 12.7mm round.
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

        // Heavy shake for sniper
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
        // Sniper rifle doesn't support chamber bullet during reload
        // (bolt-action requires full cycle)
        return false;
    }

    /// <summary>
    /// Gets the current aim direction.
    /// </summary>
    public Vector2 AimDirection => _aimDirection;

    /// <summary>
    /// Gets the current bolt-action step.
    /// </summary>
    public BoltActionStep CurrentBoltStep => _boltStep;

    /// <summary>
    /// Resets the bolt to ready state (e.g., after reload with a new magazine).
    /// </summary>
    public void ResetBolt()
    {
        _boltStep = BoltActionStep.Ready;
        EmitSignal(SignalName.BoltStepChanged, 4, 4);
        GD.Print("[SniperRifle] Bolt reset to ready state");
    }

    // =========================================================================
    // Scope / Aiming System (RMB)
    // =========================================================================

    /// <summary>
    /// Whether the scope is currently active (RMB held).
    /// </summary>
    private bool _isScopeActive = false;

    /// <summary>
    /// Whether the scope is active (read-only property for external access).
    /// </summary>
    public bool IsScopeActive => _isScopeActive;

    /// <summary>
    /// Signal emitted when scope state changes.
    /// </summary>
    [Signal]
    public delegate void ScopeStateChangedEventHandler(bool isActive);

    /// <summary>
    /// Current scope zoom distance multiplier (how far beyond viewport the player can see).
    /// 1.0 = one viewport distance, 2.0 = two viewport distances.
    /// Controlled by mouse wheel while scoping.
    /// </summary>
    private float _scopeZoomDistance = 1.0f;

    /// <summary>
    /// Minimum scope zoom distance (viewport multiplier).
    /// </summary>
    private const float MinScopeZoomDistance = 0.5f;

    /// <summary>
    /// Maximum scope zoom distance (viewport multiplier).
    /// </summary>
    private const float MaxScopeZoomDistance = 3.0f;

    /// <summary>
    /// Step size for mouse wheel zoom adjustment.
    /// </summary>
    private const float ScopeZoomStep = 0.25f;

    /// <summary>
    /// Base sway amplitude in pixels at 1 viewport distance.
    /// </summary>
    private const float BaseScopeSwayAmplitude = 8.0f;

    /// <summary>
    /// Speed of the sway oscillation.
    /// </summary>
    private const float ScopeSwaySpeed = 2.5f;

    /// <summary>
    /// Current scope sway time accumulator.
    /// </summary>
    private float _scopeSwayTime = 0.0f;

    /// <summary>
    /// Current scope sway offset in pixels (applied to camera).
    /// </summary>
    private Vector2 _scopeSwayOffset = Vector2.Zero;

    /// <summary>
    /// Reference to the scope overlay CanvasLayer (created when scope activates).
    /// </summary>
    private CanvasLayer? _scopeOverlay = null;

    /// <summary>
    /// Reference to the scope crosshair control node.
    /// </summary>
    private Control? _scopeCrosshair = null;

    /// <summary>
    /// Reference to the scope darkening background.
    /// </summary>
    private ColorRect? _scopeBackground = null;

    /// <summary>
    /// Cached reference to the player's Camera2D node.
    /// </summary>
    private Camera2D? _playerCamera = null;

    /// <summary>
    /// Original camera offset before scoping (to restore on exit).
    /// </summary>
    private Vector2 _originalCameraOffset = Vector2.Zero;

    /// <summary>
    /// Gets the current camera offset for scope aiming.
    /// Called by the player or level scripts to position the camera.
    /// </summary>
    public Vector2 GetScopeCameraOffset()
    {
        if (!_isScopeActive)
        {
            return Vector2.Zero;
        }

        Viewport? viewport = GetViewport();
        if (viewport == null)
        {
            return Vector2.Zero;
        }

        Vector2 viewportSize = viewport.GetVisibleRect().Size;
        float baseDistance = viewportSize.Length() * 0.5f;

        // Camera offset = aim direction * zoom distance * viewport size + sway
        Vector2 offset = _aimDirection * baseDistance * _scopeZoomDistance + _scopeSwayOffset;

        return offset;
    }

    /// <summary>
    /// Activates the scope (called when RMB is pressed).
    /// </summary>
    public void ActivateScope()
    {
        if (_isScopeActive)
        {
            return;
        }

        _isScopeActive = true;
        _scopeSwayTime = 0.0f;

        // Find and cache the player's Camera2D
        FindPlayerCamera();

        // Store original camera offset
        if (_playerCamera != null)
        {
            _originalCameraOffset = _playerCamera.Offset;
        }

        // Create the scope overlay
        CreateScopeOverlay();

        EmitSignal(SignalName.ScopeStateChanged, true);
        GD.Print($"[SniperRifle] Scope activated. Zoom distance: {_scopeZoomDistance:F1}x");
    }

    /// <summary>
    /// Deactivates the scope (called when RMB is released).
    /// </summary>
    public void DeactivateScope()
    {
        if (!_isScopeActive)
        {
            return;
        }

        _isScopeActive = false;

        // Restore original camera offset
        if (_playerCamera != null)
        {
            _playerCamera.Offset = _originalCameraOffset;
        }

        // Remove scope overlay
        RemoveScopeOverlay();

        EmitSignal(SignalName.ScopeStateChanged, false);
        GD.Print("[SniperRifle] Scope deactivated.");
    }

    /// <summary>
    /// Adjusts the scope zoom distance (called on mouse wheel while scoping).
    /// </summary>
    public void AdjustScopeZoom(float direction)
    {
        if (!_isScopeActive)
        {
            return;
        }

        _scopeZoomDistance += direction * ScopeZoomStep;
        _scopeZoomDistance = Mathf.Clamp(_scopeZoomDistance, MinScopeZoomDistance, MaxScopeZoomDistance);

        GD.Print($"[SniperRifle] Scope zoom adjusted: {_scopeZoomDistance:F2}x");
    }

    /// <summary>
    /// Finds the player's Camera2D node by traversing up to the parent (player).
    /// </summary>
    private void FindPlayerCamera()
    {
        if (_playerCamera != null)
        {
            return;
        }

        var parent = GetParent();
        if (parent != null)
        {
            _playerCamera = parent.GetNodeOrNull<Camera2D>("Camera2D");
        }
    }

    /// <summary>
    /// Updates the scope system each frame (called from _Process).
    /// </summary>
    private void UpdateScope(float delta)
    {
        if (!_isScopeActive)
        {
            return;
        }

        // Update sway
        _scopeSwayTime += delta;
        float swayAmplitude = BaseScopeSwayAmplitude * _scopeZoomDistance;

        // Use two sine waves at different frequencies for natural-looking sway
        float swayX = Mathf.Sin(_scopeSwayTime * ScopeSwaySpeed * 1.0f) * swayAmplitude
                    + Mathf.Sin(_scopeSwayTime * ScopeSwaySpeed * 2.3f) * swayAmplitude * 0.3f;
        float swayY = Mathf.Sin(_scopeSwayTime * ScopeSwaySpeed * 1.4f) * swayAmplitude
                    + Mathf.Sin(_scopeSwayTime * ScopeSwaySpeed * 0.7f) * swayAmplitude * 0.4f;

        _scopeSwayOffset = new Vector2(swayX, swayY);

        // Update camera offset for scope view
        if (_playerCamera != null)
        {
            _playerCamera.Offset = _originalCameraOffset + GetScopeCameraOffset();
        }

        // Update scope overlay crosshair position with sway
        UpdateScopeOverlayPosition();
    }

    /// <summary>
    /// Creates the scope overlay UI with crosshair and darkened edges.
    /// </summary>
    private void CreateScopeOverlay()
    {
        RemoveScopeOverlay();

        _scopeOverlay = new CanvasLayer
        {
            Name = "ScopeOverlay",
            Layer = 10
        };

        Viewport? viewport = GetViewport();
        Vector2 viewportSize = viewport?.GetVisibleRect().Size ?? new Vector2(1280, 720);

        // Dark background with circular cutout effect (vignette)
        _scopeBackground = new ColorRect
        {
            Name = "ScopeBackground",
            Color = new Color(0.0f, 0.0f, 0.0f, 0.5f),
            Size = viewportSize,
            Position = Vector2.Zero,
            MouseFilter = Control.MouseFilterEnum.Ignore
        };
        _scopeOverlay.AddChild(_scopeBackground);

        // Create the crosshair as a Control node
        _scopeCrosshair = new Control
        {
            Name = "ScopeCrosshair",
            Position = viewportSize / 2,
            Size = Vector2.Zero,
            MouseFilter = Control.MouseFilterEnum.Ignore
        };
        _scopeOverlay.AddChild(_scopeCrosshair);

        // Add crosshair lines - based on the reference image from the issue
        // The scope has a classic crosshair with circle and mil-dots

        // Outer circle
        float circleRadius = Mathf.Min(viewportSize.X, viewportSize.Y) * 0.35f;
        int segments = 64;
        var outerCircle = new Line2D
        {
            Name = "OuterCircle",
            Width = 2.0f,
            DefaultColor = new Color(0.0f, 0.0f, 0.0f, 0.9f),
            Antialiased = true
        };
        for (int i = 0; i <= segments; i++)
        {
            float angle = (float)i / segments * Mathf.Tau;
            outerCircle.AddPoint(new Vector2(Mathf.Cos(angle), Mathf.Sin(angle)) * circleRadius);
        }
        _scopeCrosshair.AddChild(outerCircle);

        // Inner thin circle
        float innerRadius = circleRadius * 0.05f;
        var innerCircle = new Line2D
        {
            Name = "InnerCircle",
            Width = 1.5f,
            DefaultColor = new Color(0.0f, 0.0f, 0.0f, 0.8f),
            Antialiased = true
        };
        for (int i = 0; i <= segments; i++)
        {
            float angle = (float)i / segments * Mathf.Tau;
            innerCircle.AddPoint(new Vector2(Mathf.Cos(angle), Mathf.Sin(angle)) * innerRadius);
        }
        _scopeCrosshair.AddChild(innerCircle);

        // Horizontal crosshair line (left)
        var hLineLeft = new Line2D
        {
            Name = "HLineLeft",
            Width = 2.0f,
            DefaultColor = new Color(0.0f, 0.0f, 0.0f, 0.9f)
        };
        hLineLeft.AddPoint(new Vector2(-circleRadius, 0));
        hLineLeft.AddPoint(new Vector2(-innerRadius, 0));
        _scopeCrosshair.AddChild(hLineLeft);

        // Horizontal crosshair line (right)
        var hLineRight = new Line2D
        {
            Name = "HLineRight",
            Width = 2.0f,
            DefaultColor = new Color(0.0f, 0.0f, 0.0f, 0.9f)
        };
        hLineRight.AddPoint(new Vector2(innerRadius, 0));
        hLineRight.AddPoint(new Vector2(circleRadius, 0));
        _scopeCrosshair.AddChild(hLineRight);

        // Vertical crosshair line (top)
        var vLineTop = new Line2D
        {
            Name = "VLineTop",
            Width = 2.0f,
            DefaultColor = new Color(0.0f, 0.0f, 0.0f, 0.9f)
        };
        vLineTop.AddPoint(new Vector2(0, -circleRadius));
        vLineTop.AddPoint(new Vector2(0, -innerRadius));
        _scopeCrosshair.AddChild(vLineTop);

        // Vertical crosshair line (bottom) with mil-dots
        var vLineBottom = new Line2D
        {
            Name = "VLineBottom",
            Width = 2.0f,
            DefaultColor = new Color(0.0f, 0.0f, 0.0f, 0.9f)
        };
        vLineBottom.AddPoint(new Vector2(0, innerRadius));
        vLineBottom.AddPoint(new Vector2(0, circleRadius));
        _scopeCrosshair.AddChild(vLineBottom);

        // Add mil-dot markers on the bottom crosshair (range estimation)
        float dotSpacing = circleRadius * 0.15f;
        for (int i = 1; i <= 4; i++)
        {
            float dotY = dotSpacing * i;
            var dot = new Line2D
            {
                Name = $"MilDot_{i}",
                Width = 3.0f,
                DefaultColor = new Color(0.0f, 0.0f, 0.0f, 0.8f)
            };
            float dotWidth = 4.0f - i * 0.5f; // Dots get smaller further from center
            dot.AddPoint(new Vector2(-dotWidth, dotY));
            dot.AddPoint(new Vector2(dotWidth, dotY));
            _scopeCrosshair.AddChild(dot);
        }

        // Add mil-dot markers on horizontal lines
        for (int i = 1; i <= 3; i++)
        {
            float dotX = dotSpacing * i;
            // Right side dots
            var dotRight = new Line2D
            {
                Name = $"HMilDotRight_{i}",
                Width = 3.0f,
                DefaultColor = new Color(0.0f, 0.0f, 0.0f, 0.8f)
            };
            float dotHeight = 4.0f - i * 0.5f;
            dotRight.AddPoint(new Vector2(dotX, -dotHeight));
            dotRight.AddPoint(new Vector2(dotX, dotHeight));
            _scopeCrosshair.AddChild(dotRight);

            // Left side dots
            var dotLeft = new Line2D
            {
                Name = $"HMilDotLeft_{i}",
                Width = 3.0f,
                DefaultColor = new Color(0.0f, 0.0f, 0.0f, 0.8f)
            };
            dotLeft.AddPoint(new Vector2(-dotX, -dotHeight));
            dotLeft.AddPoint(new Vector2(-dotX, dotHeight));
            _scopeCrosshair.AddChild(dotLeft);
        }

        // Add thick outer ring to mask edges (simulate scope tube)
        var scopeRing = new Line2D
        {
            Name = "ScopeRing",
            Width = 6.0f,
            DefaultColor = new Color(0.1f, 0.1f, 0.1f, 0.95f),
            Antialiased = true
        };
        float ringRadius = circleRadius + 3.0f;
        for (int i = 0; i <= segments; i++)
        {
            float angle = (float)i / segments * Mathf.Tau;
            scopeRing.AddPoint(new Vector2(Mathf.Cos(angle), Mathf.Sin(angle)) * ringRadius);
        }
        _scopeCrosshair.AddChild(scopeRing);

        // Zoom distance indicator text
        var zoomLabel = new Label
        {
            Name = "ZoomLabel",
            Position = new Vector2(circleRadius * 0.5f, circleRadius * 0.7f),
            Text = $"{_scopeZoomDistance:F1}x",
            HorizontalAlignment = HorizontalAlignment.Center,
            MouseFilter = Control.MouseFilterEnum.Ignore
        };
        zoomLabel.AddThemeColorOverride("font_color", new Color(0.0f, 0.0f, 0.0f, 0.6f));
        zoomLabel.AddThemeFontSizeOverride("font_size", 12);
        _scopeCrosshair.AddChild(zoomLabel);

        GetTree().CurrentScene.AddChild(_scopeOverlay);
    }

    /// <summary>
    /// Updates the scope overlay crosshair position with sway applied.
    /// </summary>
    private void UpdateScopeOverlayPosition()
    {
        if (_scopeCrosshair == null || _scopeOverlay == null)
        {
            return;
        }

        Viewport? viewport = GetViewport();
        if (viewport == null)
        {
            return;
        }

        Vector2 viewportSize = viewport.GetVisibleRect().Size;

        // Crosshair stays centered but sways
        _scopeCrosshair.Position = viewportSize / 2 + _scopeSwayOffset;

        // Update zoom label
        var zoomLabel = _scopeCrosshair.GetNodeOrNull<Label>("ZoomLabel");
        if (zoomLabel != null)
        {
            zoomLabel.Text = $"{_scopeZoomDistance:F1}x";
        }
    }

    /// <summary>
    /// Removes the scope overlay from the scene.
    /// </summary>
    private void RemoveScopeOverlay()
    {
        if (_scopeOverlay != null && IsInstanceValid(_scopeOverlay))
        {
            _scopeOverlay.QueueFree();
            _scopeOverlay = null;
            _scopeCrosshair = null;
            _scopeBackground = null;
        }
    }
}
