using System.Collections.Generic;
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
/// - Very slow turn sensitivity outside aiming (~25x less than normal, heavy weapon)
/// - 5-round magazine with M16-style swap reload
/// - Single-shot bolt-action with manual charging sequence (Left→Down→Up→Right)
/// - Arrow keys are consumed during bolt cycling (WASD still works for movement)
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
    /// Whether there is a spent casing in the chamber that needs to be ejected during bolt step 2.
    /// Set to true after firing (spent case remains), cleared after ejection during bolt cycling.
    /// When cycling bolt on empty magazine (no prior fire), this is false so no casing is spawned.
    /// </summary>
    private bool _hasCasingToEject = false;

    /// <summary>
    /// Tracks previous frame arrow key states for edge detection (just-pressed).
    /// Order: [Left, Down, Up, Right] matching bolt action steps 1-4.
    /// </summary>
    private bool[] _prevArrowKeyStates = new bool[4];

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

        // Remove default LaserSight node if present in scene (laser sight removed per Issue #523)
        var laserSightNode = GetNodeOrNull<Line2D>("LaserSight");
        if (laserSightNode != null)
        {
            laserSightNode.QueueFree();
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
                GD.Print($"[SniperRifle] Power Fantasy mode: blue laser sight enabled with color {_laserSightColor}");
            }
        }

        GD.Print($"[SniperRifle] ASVK initialized - bolt ready, laser={_laserSightEnabled}");
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

        // Handle bolt-action input
        HandleBoltActionInput();

        // Update laser sight (Power Fantasy mode)
        if (_laserSightEnabled && _laserSight != null)
        {
            UpdateLaserSight();
        }

        // Update scope system (sway, camera offset, overlay)
        UpdateScope((float)delta);
    }

    // =========================================================================
    // Bolt-Action Charging Mechanics
    // =========================================================================

    /// <summary>
    /// Checks if an arrow key was just pressed this frame (edge detection).
    /// Uses physical key codes to detect ONLY arrow keys, not WASD.
    /// </summary>
    /// <param name="index">Arrow key index: 0=Left, 1=Down, 2=Up, 3=Right</param>
    /// <returns>True if the key was just pressed this frame.</returns>
    private bool IsArrowKeyJustPressed(int index)
    {
        Key key = index switch
        {
            0 => Key.Left,
            1 => Key.Down,
            2 => Key.Up,
            3 => Key.Right,
            _ => Key.None
        };

        bool currentlyPressed = Input.IsKeyPressed(key);
        bool wasPressed = _prevArrowKeyStates[index];
        _prevArrowKeyStates[index] = currentlyPressed;
        return currentlyPressed && !wasPressed;
    }

    /// <summary>
    /// Handles the bolt-action charging input sequence.
    /// Sequence: Left (unlock bolt) → Down (extract and eject casing) → Up (chamber round) → Right (close bolt)
    /// Uses ONLY arrow keys (not WASD) so player can still move with WASD during bolt cycling.
    /// </summary>
    private void HandleBoltActionInput()
    {
        // Read all arrow key just-pressed states for this frame
        bool leftJustPressed = IsArrowKeyJustPressed(0);
        bool downJustPressed = IsArrowKeyJustPressed(1);
        bool upJustPressed = IsArrowKeyJustPressed(2);
        bool rightJustPressed = IsArrowKeyJustPressed(3);

        switch (_boltStep)
        {
            case BoltActionStep.NeedsBoltCycle:
                // Step 1: Left arrow - unlock bolt
                if (leftJustPressed)
                {
                    _boltStep = BoltActionStep.WaitExtractCasing;
                    EmitSignal(SignalName.BoltStepChanged, 1, 4);
                    PlayBoltStepSound(1);
                    GD.Print("[SniperRifle] Bolt step 1/4: Bolt unlocked");
                }
                break;

            case BoltActionStep.WaitExtractCasing:
                // Step 2: Down arrow - extract and eject casing
                if (downJustPressed)
                {
                    _boltStep = BoltActionStep.WaitChamberRound;
                    EmitSignal(SignalName.BoltStepChanged, 2, 4);
                    PlayBoltStepSound(2);
                    // Only eject casing if there's a spent case in the chamber (after firing)
                    // When cycling bolt on empty magazine after reload, no casing to eject
                    if (_hasCasingToEject)
                    {
                        SpawnCasing(_lastFireDirection, WeaponData?.Caliber);
                        _hasCasingToEject = false;
                        GD.Print("[SniperRifle] Bolt step 2/4: Casing extracted and ejected");
                    }
                    else
                    {
                        GD.Print("[SniperRifle] Bolt step 2/4: No casing to eject (chamber was empty)");
                    }
                }
                break;

            case BoltActionStep.WaitChamberRound:
                // Step 3: Up arrow - chamber round
                if (upJustPressed)
                {
                    _boltStep = BoltActionStep.WaitCloseBolt;
                    EmitSignal(SignalName.BoltStepChanged, 3, 4);
                    PlayBoltStepSound(3);
                    GD.Print("[SniperRifle] Bolt step 3/4: Round chambered");
                }
                break;

            case BoltActionStep.WaitCloseBolt:
                // Step 4: Right arrow - close bolt
                if (rightJustPressed)
                {
                    PlayBoltStepSound(4);
                    // Only transition to Ready if there's ammo to chamber
                    // If magazine is empty, bolt cycling doesn't count (no round chambered)
                    if (CurrentAmmo > 0)
                    {
                        _boltStep = BoltActionStep.Ready;
                        EmitSignal(SignalName.BoltStepChanged, 4, 4);
                        GD.Print("[SniperRifle] Bolt step 4/4: Bolt closed - READY TO FIRE");
                    }
                    else
                    {
                        // Bolt closes but no round was chambered (empty magazine)
                        // Must cycle bolt again after inserting a new magazine
                        _boltStep = BoltActionStep.NeedsBoltCycle;
                        EmitSignal(SignalName.BoltStepChanged, 0, 4);
                        GD.Print("[SniperRifle] Bolt step 4/4: Bolt closed but NO round chambered (empty magazine) - needs cycling after reload");
                    }
                }
                break;

            case BoltActionStep.Ready:
                // Already ready, no bolt action needed
                break;
        }
    }

    /// <summary>
    /// Plays the appropriate ASVK bolt-action sound for the given step.
    /// Uses non-positional audio so the sound volume is constant regardless
    /// of scope camera offset (fixes issue #565).
    /// </summary>
    /// <param name="step">The bolt-action step number (1-4).</param>
    private void PlayBoltStepSound(int step)
    {
        var audioManager = GetNodeOrNull("/root/AudioManager");
        if (audioManager == null)
        {
            return;
        }

        // Use ASVK-specific bolt action sounds (non-positional to avoid scope attenuation)
        if (audioManager.HasMethod("play_asvk_bolt_step"))
        {
            audioManager.Call("play_asvk_bolt_step", step);
        }
        else if (audioManager.HasMethod("play_sound"))
        {
            // Fallback to non-positional sound playback
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
                audioManager.Call("play_sound", soundPath, -3.0f);
            }
        }
    }

    // =========================================================================
    // Aiming
    // =========================================================================

    /// <summary>
    /// Sensitivity reduction factor when not aiming (outside scope/aim mode).
    /// The heavy ASVK rotates very slowly - 25x slower than normal weapons.
    /// </summary>
    private const float NonAimingSensitivityFactor = 0.04f;

    /// <summary>
    /// Updates the aim direction and rifle sprite rotation.
    /// The heavy rifle rotates very slowly outside aiming (~25x less sensitivity).
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
        // Outside aiming, sensitivity is reduced by 25x (NonAimingSensitivityFactor)
        if (WeaponData != null && WeaponData.Sensitivity > 0)
        {
            float angleDiff = Mathf.Wrap(targetAngle - _currentAimAngle, -Mathf.Pi, Mathf.Pi);
            // Apply reduced sensitivity: heavy rifle rotates very slowly outside aiming
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
    // Laser Sight (Power Fantasy mode only)
    // =========================================================================

    /// <summary>
    /// Creates the laser sight Line2D programmatically (Power Fantasy mode only).
    /// </summary>
    private void CreateLaserSight()
    {
        _laserSight = new Line2D
        {
            Name = "PowerFantasyLaser",
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
    /// The laser shows where bullets will go, accounting for current recoil.
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

    // =========================================================================
    // Firing
    // =========================================================================

    /// <summary>
    /// Whether to skip bullet spawning (used during hitscan fire).
    /// When true, SpawnBullet() does nothing because hitscan handles damage directly.
    /// </summary>
    private bool _skipBulletSpawn = false;

    /// <summary>
    /// Fires the sniper rifle using hitscan (instant raycast damage).
    /// All enemies along the bullet path take damage instantly.
    /// The smoke tracer only extends to the point where the bullet stops
    /// (after exceeding wall penetration limit or reaching max range).
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

        // When scope is active, use the direction passed from Player.Shoot() (scope crosshair target)
        // When scope is not active, use _aimDirection (laser sight direction)
        Vector2 fireDirection = _isScopeActive ? direction : _aimDirection;
        Vector2 spreadDirection = ApplyRecoil(fireDirection);

        // Skip bullet spawning - we use hitscan instead
        _skipBulletSpawn = true;
        bool result = base.Fire(spreadDirection);
        _skipBulletSpawn = false;

        if (result)
        {
            // Perform hitscan - instant raycast damage along bullet path
            Vector2 bulletEndPoint = PerformHitscan(GlobalPosition, spreadDirection);

            // Store fire direction for casing ejection during bolt step 2
            _lastFireDirection = spreadDirection;
            _hasCasingToEject = true;

            // Transition to needs bolt cycle
            _boltStep = BoltActionStep.NeedsBoltCycle;
            EmitSignal(SignalName.BoltStepChanged, 0, 4);

            // Play sniper shot sound (ASVK specific)
            PlaySniperShotSound();
            // Emit gunshot sound for enemy detection
            EmitGunshotSound();
            // Trigger heavy screen shake
            TriggerScreenShake(spreadDirection);

            // Spawn smoky tracer trail limited to the bullet's actual path
            SpawnSmokyTracer(GlobalPosition, spreadDirection, bulletEndPoint);

            // Spawn muzzle flash
            Vector2 muzzlePos = GlobalPosition + spreadDirection * BulletSpawnOffset;
            SpawnMuzzleFlash(muzzlePos, spreadDirection, WeaponData?.Caliber);

            GD.Print("[SniperRifle] FIRED (hitscan)! Bolt needs cycling. Ammo remaining: " + CurrentAmmo);
        }

        return result;
    }

    // =========================================================================
    // Hitscan Logic
    // =========================================================================

    /// <summary>
    /// Performs instant hitscan along the bullet path.
    /// Raycasts sequentially to find all walls and enemies along the path.
    /// Enemies take damage instantly. The bullet stops after exceeding
    /// MaxWallPenetrations walls or reaching max range.
    /// </summary>
    /// <param name="origin">Starting position of the shot.</param>
    /// <param name="direction">Normalized direction of the shot.</param>
    /// <returns>The endpoint where the bullet stops (for smoke tracer).</returns>
    private Vector2 PerformHitscan(Vector2 origin, Vector2 direction)
    {
        float maxRange = 5000.0f;
        Vector2 startPos = origin + direction * BulletSpawnOffset;
        Vector2 endPos = origin + direction * maxRange;
        int wallsPenetrated = 0;
        float damage = WeaponData?.Damage ?? 50.0f;
        Vector2 bulletEndPoint = endPos;

        var spaceState = GetWorld2D()?.DirectSpaceState;
        if (spaceState == null)
        {
            return bulletEndPoint;
        }

        // Get shooter ID to prevent self-damage
        var owner = GetParent();
        ulong shooterId = owner?.GetInstanceId() ?? 0;

        // Collision mask: walls (layer 3 = 4) + enemy bodies (layer 2 = 2) + enemy hit areas need area detection
        // For physics raycast we detect bodies: walls (layer 3 = 4) and enemy CharacterBody2D (layer 2 = 2)
        uint wallMask = 4;  // Layer 3 = obstacles/walls
        uint enemyBodyMask = 2;  // Layer 2 = enemy bodies
        uint combinedMask = wallMask | enemyBodyMask;

        Vector2 currentPos = startPos;
        var excludeRids = new Godot.Collections.Array<Rid>();
        var damagedEnemies = new HashSet<ulong>(); // Track already-damaged enemies by instance ID

        // Sequential raycasts to find all hits along the path
        for (int iteration = 0; iteration < 50; iteration++) // Safety limit
        {
            if (currentPos.DistanceTo(endPos) < 1.0f)
            {
                break;
            }

            var query = PhysicsRayQueryParameters2D.Create(
                currentPos, endPos, combinedMask
            );
            query.Exclude = excludeRids;
            query.HitFromInside = true;
            query.CollideWithAreas = false;
            query.CollideWithBodies = true;

            var result = spaceState.IntersectRay(query);
            if (result.Count == 0)
            {
                // No more hits - bullet travels to max range
                break;
            }

            var hitCollider = (Node2D)result["collider"];
            var hitPosition = (Vector2)result["position"];
            var hitRid = (Rid)result["rid"];

            // Skip self
            if (hitCollider.GetInstanceId() == shooterId)
            {
                excludeRids.Add(hitRid);
                continue;
            }

            // Check if this is a wall/obstacle
            if (hitCollider is StaticBody2D || hitCollider is TileMap)
            {
                // Spawn dust effect at wall hit point
                SpawnWallHitEffectAt(hitPosition, direction);

                if (wallsPenetrated < MaxWallPenetrations)
                {
                    // Penetrate through this wall
                    wallsPenetrated++;
                    GD.Print($"[SniperRifle] Hitscan: penetrated wall {wallsPenetrated}/{MaxWallPenetrations} at {hitPosition}");
                    excludeRids.Add(hitRid);
                    // Continue from just past the hit point
                    currentPos = hitPosition + direction * 5.0f;
                    continue;
                }
                else
                {
                    // Exceeded max penetrations - bullet stops here
                    bulletEndPoint = hitPosition;
                    GD.Print($"[SniperRifle] Hitscan: max wall penetrations ({MaxWallPenetrations}) reached at {hitPosition}");
                    break;
                }
            }

            // Check if this is an enemy (CharacterBody2D on layer 2)
            if (hitCollider is CharacterBody2D)
            {
                var enemyId = hitCollider.GetInstanceId();

                // Skip already-damaged enemies and self
                if (enemyId == shooterId || damagedEnemies.Contains(enemyId))
                {
                    excludeRids.Add(hitRid);
                    currentPos = hitPosition + direction * 5.0f;
                    continue;
                }

                // Check if enemy is alive
                bool isAlive = true;
                if (hitCollider.HasMethod("is_alive"))
                {
                    isAlive = hitCollider.Call("is_alive").AsBool();
                }

                if (isAlive)
                {
                    // Apply instant damage
                    if (hitCollider.HasMethod("take_damage"))
                    {
                        GD.Print($"[SniperRifle] Hitscan: hit enemy {hitCollider.Name} at {hitPosition}, applying {damage} damage");
                        hitCollider.Call("take_damage", damage);
                        damagedEnemies.Add(enemyId);

                        // Trigger player hit effects
                        TriggerPlayerHitEffectsHitscan();
                    }
                }

                // Bullet passes through enemies - continue
                excludeRids.Add(hitRid);
                currentPos = hitPosition + direction * 5.0f;
                continue;
            }

            // Unknown collider - skip and continue
            excludeRids.Add(hitRid);
            currentPos = hitPosition + direction * 5.0f;
        }

        GD.Print($"[SniperRifle] Hitscan complete: walls={wallsPenetrated}, enemies_hit={damagedEnemies.Count}, endpoint={bulletEndPoint}");
        return bulletEndPoint;
    }

    /// <summary>
    /// Spawns a dust/impact effect at a wall hit position (for hitscan).
    /// </summary>
    private void SpawnWallHitEffectAt(Vector2 position, Vector2 direction)
    {
        var impactManager = GetNodeOrNull("/root/ImpactEffectsManager");
        if (impactManager == null || !impactManager.HasMethod("spawn_dust_effect"))
        {
            return;
        }

        Vector2 surfaceNormal = -direction.Normalized();
        impactManager.Call("spawn_dust_effect", position, surfaceNormal, Variant.CreateFrom((Resource?)null));
    }

    /// <summary>
    /// Triggers hit effects when player hitscan hits an enemy.
    /// </summary>
    private void TriggerPlayerHitEffectsHitscan()
    {
        var hitEffectsManager = GetNodeOrNull("/root/HitEffectsManager");
        if (hitEffectsManager != null && hitEffectsManager.HasMethod("on_player_hit_enemy"))
        {
            hitEffectsManager.Call("on_player_hit_enemy");
        }
    }

    /// <summary>
    /// Override SpawnCasing for ASVK-specific casing ejection behavior (Issue #575).
    /// ASVK casings are ejected:
    /// - Faster (300-400 px/sec vs normal 120-180 px/sec)
    /// - More to the right and slightly forward (45-degree angle from perpendicular)
    /// This creates a distinctive, powerful ejection for the heavy 12.7x108mm casings.
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
        // In a top-down view with Y increasing downward:
        // - If weapon points right (1, 0), right side of weapon is DOWN (0, 1)
        // - If weapon points up (0, -1), right side of weapon is RIGHT (1, 0)
        // This is a 90 degree counter-clockwise rotation (perpendicular to shooting direction)
        Vector2 weaponRight = new Vector2(-direction.Y, direction.X); // Rotate 90 degrees counter-clockwise

        // ASVK-specific: Eject to the right AND slightly forward
        // Mix the perpendicular direction with the forward direction to get ~45 degree angle
        // This makes ASVK casings eject more forward than other weapons
        Vector2 ejectionBase = (weaponRight + direction * 0.3f).Normalized();

        // Add some randomness for variety
        float randomAngle = (float)GD.RandRange(-0.2f, 0.2f); // ±0.2 radians (~±11 degrees)
        Vector2 ejectionDirection = ejectionBase.Rotated(randomAngle);

        // ASVK-specific: Much faster ejection speed (2-3x normal weapons)
        // Heavy 12.7x108mm casings are ejected with more force
        float ejectionSpeed = (float)GD.RandRange(300.0f, 400.0f); // Fast ejection
        casing.LinearVelocity = ejectionDirection * ejectionSpeed;

        // Add strong initial spin for realism (heavy casing tumbling through the air)
        casing.AngularVelocity = (float)GD.RandRange(-20.0f, 20.0f);

        // Set caliber data on the casing for appearance (12.7x108mm)
        if (caliber != null)
        {
            casing.Set("caliber_data", caliber);
        }

        GetTree().CurrentScene.AddChild(casing);

        GD.Print($"[SniperRifle] ASVK casing ejected: speed={ejectionSpeed:F0} px/sec, direction={ejectionDirection}");
    }

    /// <summary>
    /// Override SpawnBullet to configure the SniperBullet for sniper behavior:
    /// - Very high damage (50)
    /// - Passes through enemies (doesn't destroy on hit)
    /// - Penetrates through 2 walls (wall-count based, not distance-based)
    /// NOTE: This method is kept for compatibility but is no longer called
    /// during normal firing (hitscan is used instead).
    /// </summary>
    protected override void SpawnBullet(Vector2 direction)
    {
        // Skip bullet spawning when using hitscan (damage is applied via raycast)
        if (_skipBulletSpawn)
        {
            return;
        }

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
    /// to the bullet's endpoint (where it stopped after wall penetration limit
    /// or at max range). The tracer is an instant visual effect that fades out.
    /// </summary>
    private void SpawnSmokyTracer(Vector2 fromPosition, Vector2 direction, Vector2 bulletEndPoint)
    {
        // Use the bullet's actual endpoint (limited by wall penetrations)
        Vector2 endPosition = bulletEndPoint;

        // Create the tracer as a Line2D with smoke-like appearance
        var tracer = new Line2D
        {
            Name = "SniperTracer",
            Width = 5.0f,
            DefaultColor = new Color(0.8f, 0.8f, 0.8f, 0.7f),
            BeginCapMode = Line2D.LineCapMode.Round,
            EndCapMode = Line2D.LineCapMode.Round,
            TopLevel = true,
            Position = Vector2.Zero,
            ZIndex = 10 // Above game elements to be visible
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
        GD.Print($"[SniperRifle] Smoke tracer spawned: from={fromPosition + direction * BulletSpawnOffset} to={endPosition}, width={tracer.Width}");

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
            tracer.Width = initialWidth + progress * 3.0f;

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
    /// Uses non-positional audio so the sound volume is constant regardless
    /// of scope camera offset (fixes issue #565).
    /// </summary>
    private void PlaySniperShotSound()
    {
        var audioManager = GetNodeOrNull("/root/AudioManager");
        if (audioManager == null)
        {
            return;
        }

        // Use ASVK-specific shot sound (non-positional to avoid scope attenuation)
        if (audioManager.HasMethod("play_asvk_shot"))
        {
            audioManager.Call("play_asvk_shot");
        }
        else if (audioManager.HasMethod("play_sound"))
        {
            // Fallback to non-positional sound playback
            audioManager.Call("play_sound", "res://assets/audio/выстрел из ASVK.wav", -3.0f);
        }
    }

    /// <summary>
    /// Plays the empty gun click sound.
    /// Uses non-positional audio so the sound volume is constant regardless
    /// of scope camera offset (fixes issue #565).
    /// </summary>
    private void PlayEmptyClickSound()
    {
        var audioManager = GetNodeOrNull("/root/AudioManager");
        if (audioManager != null && audioManager.HasMethod("play_sound"))
        {
            audioManager.Call("play_sound",
                "res://assets/audio/кончились патроны в пистолете.wav", -3.0f);
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
    private float _scopeZoomDistance = 1.5f;

    /// <summary>
    /// Minimum scope zoom distance (viewport multiplier).
    /// Set to 1.5 so the scope starts half a viewport beyond the normal view.
    /// </summary>
    private const float MinScopeZoomDistance = 1.5f;

    /// <summary>
    /// Maximum scope zoom distance (viewport multiplier).
    /// Allows zooming up to 4x viewport distance for long-range aiming.
    /// </summary>
    private const float MaxScopeZoomDistance = 4.0f;

    /// <summary>
    /// Step size for mouse wheel zoom adjustment.
    /// </summary>
    private const float ScopeZoomStep = 0.25f;

    /// <summary>
    /// Fine-tune range as a fraction of viewport diagonal.
    /// Approximately 1/3 of the viewport, allowing the player to move
    /// the scope view further or closer by about a third of the screen.
    /// </summary>
    private const float ScopeFineTuneFraction = 0.33f;

    /// <summary>
    /// Base mouse sensitivity multiplier when scoped.
    /// The actual multiplier = BaseScopeSensitivityMultiplier * effectiveZoomDistance.
    /// High value makes precise aiming more challenging (crosshair moves fast).
    /// At 1x zoom, sensitivity is 8x normal. At 2x zoom, 16x. At 4x zoom, 32x.
    /// </summary>
    private const float BaseScopeSensitivityMultiplier = 8.0f;

    /// <summary>
    /// Current mouse fine-tune offset applied to scope distance in pixels.
    /// Positive = further along aim direction, negative = closer.
    /// </summary>
    private float _scopeMouseFineTunePixels = 0.0f;

    /// <summary>
    /// Current scope mouse offset in pixels (applied to crosshair and camera).
    /// Controlled by mouse movement while scoped with increased sensitivity.
    /// </summary>
    private Vector2 _scopeMouseOffset = Vector2.Zero;

    /// <summary>
    /// Maximum scope mouse offset in pixels (limits how far the crosshair can drift).
    /// Automatically calculated based on viewport size and zoom distance.
    /// </summary>
    private float _maxScopeMouseOffset = 100.0f;

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
    /// Gets the effective scope zoom distance (without fine-tune pixel offset).
    /// Fine-tune offset is applied separately as a pixel-based displacement.
    /// </summary>
    private float EffectiveScopeZoomDistance => _scopeZoomDistance;

    /// <summary>
    /// Gets the maximum fine-tune range in pixels (1/3 of viewport diagonal).
    /// </summary>
    private float GetFineTuneMaxPixels()
    {
        Viewport? viewport = GetViewport();
        if (viewport == null) return 400.0f; // fallback
        return viewport.GetVisibleRect().Size.Length() * ScopeFineTuneFraction;
    }

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

        // Camera offset = aim direction * zoom distance * viewport size + fine-tune pixels + mouse offset
        Vector2 offset = _aimDirection * baseDistance * EffectiveScopeZoomDistance
            + _aimDirection * _scopeMouseFineTunePixels
            + _scopeMouseOffset;

        return offset;
    }

    /// <summary>
    /// Gets the world-space position that the scope crosshair center is aiming at.
    /// Used to direct bullets to the crosshair center.
    /// Computes the exact world position at viewport center using the camera,
    /// ensuring bullets go precisely where the crosshair is displayed.
    /// </summary>
    public Vector2 GetScopeAimTarget()
    {
        // Use the camera's actual position to determine where the crosshair center
        // is in world space. This ensures perfect alignment: the bullet goes exactly
        // to the world position shown at viewport center (where the crosshair is).
        if (_playerCamera != null)
        {
            // The world position at viewport center = camera's global position + camera offset
            // Camera2D.GetScreenCenterPosition() returns exactly this in Godot 4
            return _playerCamera.GetScreenCenterPosition();
        }

        // Fallback: compute from aim direction if camera is not available
        Viewport? viewport = GetViewport();
        if (viewport == null)
        {
            return GlobalPosition + _aimDirection * 1000.0f;
        }

        Vector2 viewportSize = viewport.GetVisibleRect().Size;
        float baseDistance = viewportSize.Length() * 0.5f;

        Vector2 aimTarget = GlobalPosition + _aimDirection * baseDistance * EffectiveScopeZoomDistance
            + _aimDirection * _scopeMouseFineTunePixels
            + _scopeMouseOffset;

        return aimTarget;
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
        _scopeMouseFineTunePixels = 0.0f;
        _scopeMouseOffset = Vector2.Zero;

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

        // Reset fine-tune offset when zoom changes to avoid going out of range
        float fineTuneMax = GetFineTuneMaxPixels();
        _scopeMouseFineTunePixels = Mathf.Clamp(_scopeMouseFineTunePixels,
            -fineTuneMax, fineTuneMax);

        GD.Print($"[SniperRifle] Scope zoom adjusted: {_scopeZoomDistance:F2}x (fine-tune: {_scopeMouseFineTunePixels:F0}px)");
    }

    /// <summary>
    /// Handles mouse movement while scoped. Does two things:
    /// 1. Fine-tunes scope distance along the aim direction (closer/further by ~1/3 viewport).
    /// 2. Moves the crosshair/camera offset with increased sensitivity based on distance.
    ///    The further the scope, the higher the sensitivity (at 2x distance, 2x sensitivity).
    /// Called from Player.cs when mouse moves while scoped.
    /// </summary>
    public void AdjustScopeFineTune(Vector2 mouseMotion)
    {
        if (!_isScopeActive)
        {
            return;
        }

        // --- 1. Fine-tune scope distance along aim direction ---
        // Project mouse motion onto the aim direction to get forward/backward pixel movement
        float projection = mouseMotion.Dot(_aimDirection);
        // Direct pixel mapping: mouse movement along aim direction adjusts scope distance in pixels
        float fineTuneMax = GetFineTuneMaxPixels();
        _scopeMouseFineTunePixels += projection * 0.5f;
        _scopeMouseFineTunePixels = Mathf.Clamp(_scopeMouseFineTunePixels,
            -fineTuneMax, fineTuneMax);

        // --- 2. Move crosshair with distance-based sensitivity ---
        // Sensitivity multiplier scales linearly with effective zoom distance
        float sensitivityMultiplier = BaseScopeSensitivityMultiplier * EffectiveScopeZoomDistance;
        _scopeMouseOffset += mouseMotion * sensitivityMultiplier;

        // Clamp to maximum offset (scales with zoom distance for larger range at higher zoom)
        Viewport? viewport = GetViewport();
        if (viewport != null)
        {
            Vector2 viewportSize = viewport.GetVisibleRect().Size;
            _maxScopeMouseOffset = viewportSize.Length() * 0.25f * EffectiveScopeZoomDistance;
        }
        _scopeMouseOffset = _scopeMouseOffset.LimitLength(_maxScopeMouseOffset);
    }

    /// <summary>
    /// Gets the effective sensitivity multiplier for the current scope state.
    /// Returns 1.0 when scope is not active.
    /// </summary>
    public float GetScopeSensitivityMultiplier()
    {
        if (!_isScopeActive)
        {
            return 1.0f;
        }
        return BaseScopeSensitivityMultiplier * EffectiveScopeZoomDistance;
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
    /// Camera offset and crosshair position are driven by mouse input
    /// with distance-based sensitivity (no programmed sway).
    /// </summary>
    private void UpdateScope(float delta)
    {
        if (!_isScopeActive)
        {
            return;
        }

        // Update camera offset for scope view (driven by mouse offset, no auto-sway)
        if (_playerCamera != null)
        {
            _playerCamera.Offset = _originalCameraOffset + GetScopeCameraOffset();
        }

        // Update scope overlay crosshair position with mouse offset
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

        // Crosshair stays at viewport center (camera offset moves the world view)
        // This ensures bullets fired at GetScopeAimTarget() match the crosshair position
        _scopeCrosshair.Position = viewportSize / 2;

        // Update zoom label showing effective zoom distance
        var zoomLabel = _scopeCrosshair.GetNodeOrNull<Label>("ZoomLabel");
        if (zoomLabel != null)
        {
            zoomLabel.Text = $"{EffectiveScopeZoomDistance:F1}x";
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
