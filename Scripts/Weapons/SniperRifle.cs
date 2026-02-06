using Godot;
using GodotTopDownTemplate.AbstractClasses;
using GodotTopDownTemplate.Projectiles;

namespace GodotTopDownTemplate.Weapons;

/// <summary>
/// Bolt-action charging state for the ASVK sniper rifle.
/// Before each shot, the player must complete a 4-step bolt-action sequence:
/// Left (unlock bolt) → Down (extract and eject casing) → Up (chamber round) → Right (close bolt)
/// </summary>
public enum BoltActionStep
{
    /// <summary>
    /// Bolt is ready - weapon can fire. After firing, transitions to NeedsBoltCycle.
    /// </summary>
    Ready,

    /// <summary>
    /// Just fired - needs bolt cycling before next shot.
    /// Waiting for Left arrow (unlock bolt).
    /// </summary>
    NeedsBoltCycle,

    /// <summary>
    /// Step 1 complete (bolt unlocked). Waiting for Down arrow (extract and eject casing).
    /// </summary>
    WaitExtractCasing,

    /// <summary>
    /// Step 2 complete (casing ejected). Waiting for Up arrow (chamber round).
    /// </summary>
    WaitChamberRound,

    /// <summary>
    /// Step 3 complete (round chambered). Waiting for Right arrow (close bolt).
    /// </summary>
    WaitCloseBolt
}

/// <summary>
/// ASVK sniper rifle - heavy anti-materiel bolt-action rifle.
/// Features:
/// - 12.7x108mm ammunition dealing 50 damage per shot
/// - Penetrates through 2 walls and through enemies
/// - Instant bullet speed with smoky dissipating tracer trail
/// - Slow turn sensitivity outside aiming (~4x less than normal)
/// - 5-round magazine with M16-style swap reload
/// - Single-shot bolt-action with manual charging sequence (Left→Down→Up→Right)
/// - Arrow keys are consumed during bolt cycling (no walking)
/// - Shell casing ejected on step 2 (Down - extract and eject casing)
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
    // Bolt Cycling and Movement
    // =========================================================================

    /// <summary>
    /// Whether bolt cycling is in progress (arrow keys should be consumed, not move).
    /// When true, the SniperRifle notifies the player to suppress arrow key movement.
    /// </summary>
    public bool IsBoltCycling => _boltStep != BoltActionStep.Ready;

    /// <summary>
    /// Last fire direction, stored for casing ejection during bolt cycling step 2.
    /// </summary>
    private Vector2 _lastFireDirection = Vector2.Right;

    /// <summary>
    /// Reference to the Sprite2D node for the rifle visual.
    /// </summary>
    private Sprite2D? _rifleSprite;

    /// <summary>
    /// Current aim direction.
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

        // Remove LaserSight node if present in scene (laser sight removed per Issue #523)
        var laserSight = GetNodeOrNull<Line2D>("LaserSight");
        if (laserSight != null)
        {
            laserSight.QueueFree();
            GD.Print("[SniperRifle] Laser sight removed");
        }

        GD.Print("[SniperRifle] ASVK initialized - bolt ready, no laser sight");
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

        // Handle bolt-action input
        HandleBoltActionInput();
    }

    // =========================================================================
    // Bolt-Action Charging Mechanics
    // =========================================================================

    /// <summary>
    /// Handles the bolt-action charging input sequence.
    /// Sequence: Left (unlock bolt) → Down (extract and eject casing) → Up (chamber round) → Right (close bolt)
    /// Uses the arrow keys / WASD movement input actions.
    /// Arrow keys are consumed during bolt cycling (no walking).
    /// </summary>
    private void HandleBoltActionInput()
    {
        switch (_boltStep)
        {
            case BoltActionStep.NeedsBoltCycle:
                // Step 1: Left arrow - unlock bolt
                if (Input.IsActionJustPressed("move_left"))
                {
                    _boltStep = BoltActionStep.WaitExtractCasing;
                    EmitSignal(SignalName.BoltStepChanged, 1, 4);
                    PlayBoltStepSound(1);
                    GD.Print("[SniperRifle] Bolt step 1/4: Bolt unlocked");
                }
                break;

            case BoltActionStep.WaitExtractCasing:
                // Step 2: Down arrow - extract and eject casing
                if (Input.IsActionJustPressed("move_down"))
                {
                    _boltStep = BoltActionStep.WaitChamberRound;
                    EmitSignal(SignalName.BoltStepChanged, 2, 4);
                    PlayBoltStepSound(2);
                    // Eject shell casing on this step (like shotgun pump-up)
                    SpawnCasing(_lastFireDirection, WeaponData?.Caliber);
                    GD.Print("[SniperRifle] Bolt step 2/4: Casing extracted and ejected");
                }
                break;

            case BoltActionStep.WaitChamberRound:
                // Step 3: Up arrow - chamber round
                if (Input.IsActionJustPressed("move_up"))
                {
                    _boltStep = BoltActionStep.WaitCloseBolt;
                    EmitSignal(SignalName.BoltStepChanged, 3, 4);
                    PlayBoltStepSound(3);
                    GD.Print("[SniperRifle] Bolt step 3/4: Round chambered");
                }
                break;

            case BoltActionStep.WaitCloseBolt:
                // Step 4: Right arrow - close bolt
                if (Input.IsActionJustPressed("move_right"))
                {
                    _boltStep = BoltActionStep.Ready;
                    EmitSignal(SignalName.BoltStepChanged, 4, 4);
                    PlayBoltStepSound(4);
                    GD.Print("[SniperRifle] Bolt step 4/4: Bolt closed - READY TO FIRE");
                }
                break;

            case BoltActionStep.Ready:
                // Already ready, no bolt action needed
                break;
        }
    }

    /// <summary>
    /// Plays the appropriate ASVK bolt-action sound for the given step.
    /// Uses dedicated ASVK sounds from assets.
    /// </summary>
    /// <param name="step">The bolt-action step number (1-4).</param>
    private void PlayBoltStepSound(int step)
    {
        var audioManager = GetNodeOrNull("/root/AudioManager");
        if (audioManager == null)
        {
            return;
        }

        // Use ASVK-specific bolt action sounds
        if (audioManager.HasMethod("play_asvk_bolt_step"))
        {
            audioManager.Call("play_asvk_bolt_step", step, GlobalPosition);
        }
        else if (audioManager.HasMethod("play_sound_2d"))
        {
            // Direct sound playback fallback
            string soundPath = step switch
            {
                1 => "res://assets/audio/отпирание затвора ASVK (1 шаг зарядки).wav",
                2 => "res://assets/audio/извлечение и выброс гильзы ASVK (2 шаг зарядки).wav",
                3 => "res://assets/audio/досылание патрона ASVK (3 шаг зарядки).wav",
                4 => "res://assets/audio/запирание затвора ASVK (4 шаг зарядки).wav",
                _ => ""
            };
            if (!string.IsNullOrEmpty(soundPath))
            {
                audioManager.Call("play_sound_2d", soundPath, GlobalPosition, -3.0f);
            }
        }
    }

    // =========================================================================
    // Aiming
    // =========================================================================

    /// <summary>
    /// Sensitivity reduction factor when not aiming (outside scope/aim mode).
    /// The rifle rotates approximately 4x slower when just moving without aiming.
    /// </summary>
    private const float NonAimingSensitivityFactor = 0.25f;

    /// <summary>
    /// Updates the aim direction and rifle sprite rotation.
    /// The rifle rotates slowly outside aiming (~4x less sensitivity).
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
        // Outside aiming, sensitivity is reduced by 4x (NonAimingSensitivityFactor)
        if (WeaponData != null && WeaponData.Sensitivity > 0)
        {
            float angleDiff = Mathf.Wrap(targetAngle - _currentAimAngle, -Mathf.Pi, Mathf.Pi);
            // Apply reduced sensitivity: rifle rotates very slowly outside aiming
            float effectiveSensitivity = WeaponData.Sensitivity * NonAimingSensitivityFactor;
            float rotationSpeed = effectiveSensitivity * 10.0f;
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
            // Store fire direction for casing ejection during bolt step 2
            _lastFireDirection = spreadDirection;

            // Transition to needs bolt cycle
            _boltStep = BoltActionStep.NeedsBoltCycle;
            EmitSignal(SignalName.BoltStepChanged, 0, 4);

            // Play sniper shot sound (ASVK specific)
            PlaySniperShotSound();
            // Emit gunshot sound for enemy detection
            EmitGunshotSound();
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

        // NOTE: Casing is NOT spawned on fire - it's ejected during bolt step 2
        // (Down arrow - extract and eject casing), similar to shotgun pump-action.
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
    /// Plays the ASVK sniper shot sound via AudioManager.
    /// Uses dedicated ASVK shot sound from assets.
    /// </summary>
    private void PlaySniperShotSound()
    {
        var audioManager = GetNodeOrNull("/root/AudioManager");
        if (audioManager == null)
        {
            return;
        }

        // Use ASVK-specific shot sound
        if (audioManager.HasMethod("play_asvk_shot"))
        {
            audioManager.Call("play_asvk_shot", GlobalPosition);
        }
        else if (audioManager.HasMethod("play_sound_2d"))
        {
            // Direct sound playback fallback
            audioManager.Call("play_sound_2d", "res://assets/audio/выстрел из ASVK.wav", GlobalPosition, -3.0f);
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
}
