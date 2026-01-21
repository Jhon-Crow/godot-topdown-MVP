using Godot;
using GodotTopDownTemplate.AbstractClasses;
using GodotTopDownTemplate.Weapons;

namespace GodotTopDownTemplate.Characters;

/// <summary>
/// Player character controller for top-down movement and shooting.
/// Uses physics-based movement with acceleration and friction for smooth control.
/// Supports WASD and arrow key input via configured input actions.
/// Shoots bullets towards the mouse cursor on left mouse button.
/// Supports both automatic (hold to fire) and semi-automatic (click per shot) weapons.
/// Uses R-F-R key sequence for instant reload (press R, then F, then R again).
/// Grenade throwing: G+RMB drag right → hold G+RMB → release G → drag and release RMB to throw.
/// </summary>
public partial class Player : BaseCharacter
{
    /// <summary>
    /// Bullet scene to instantiate when shooting.
    /// </summary>
    [Export]
    public PackedScene? BulletScene { get; set; }

    /// <summary>
    /// Offset from player center for bullet spawn position.
    /// </summary>
    [Export]
    public float BulletSpawnOffset { get; set; } = 20.0f;

    /// <summary>
    /// Reference to the player's current weapon (optional, for weapon system).
    /// </summary>
    [Export]
    public BaseWeapon? CurrentWeapon { get; set; }

    /// <summary>
    /// Color when at full health.
    /// </summary>
    [Export]
    public Color FullHealthColor { get; set; } = new Color(0.2f, 0.6f, 1.0f, 1.0f);

    /// <summary>
    /// Color when at low health (interpolates based on health percentage).
    /// </summary>
    [Export]
    public Color LowHealthColor { get; set; } = new Color(0.1f, 0.2f, 0.4f, 1.0f);

    /// <summary>
    /// Color to flash when hit.
    /// </summary>
    [Export]
    public Color HitFlashColor { get; set; } = new Color(1.0f, 0.3f, 0.3f, 1.0f);

    /// <summary>
    /// Duration of hit flash effect in seconds.
    /// </summary>
    [Export]
    public float HitFlashDuration { get; set; } = 0.1f;

    /// <summary>
    /// Grenade scene to instantiate when throwing.
    /// </summary>
    [Export]
    public PackedScene? GrenadeScene { get; set; }

    /// <summary>
    /// Maximum number of grenades the player can carry.
    /// </summary>
    [Export]
    public int MaxGrenades { get; set; } = 3;

    /// <summary>
    /// Reference to the player's sprite for visual feedback.
    /// </summary>
    private Sprite2D? _sprite;

    /// <summary>
    /// Current step in the reload sequence (0 = waiting for R, 1 = waiting for F, 2 = waiting for R).
    /// </summary>
    private int _reloadSequenceStep = 0;

    /// <summary>
    /// Whether the player is currently in a reload sequence.
    /// </summary>
    private bool _isReloadingSequence = false;

    /// <summary>
    /// Tracks ammo count when reload sequence started (at step 1 after R pressed).
    /// Used to determine if there was a bullet in the chamber.
    /// </summary>
    private int _ammoAtReloadStart = 0;

    /// <summary>
    /// Current number of grenades.
    /// </summary>
    private int _currentGrenades = 3;

    /// <summary>
    /// Whether the player is on the tutorial level (infinite grenades).
    /// </summary>
    private bool _isTutorialLevel = false;

    /// <summary>
    /// Grenade state machine states.
    /// 2-step mechanic:
    /// Step 1: G + RMB drag right → timer starts (pin pulled)
    /// Step 2: Hold G → press+hold RMB → release G → ready to throw (only RMB held)
    /// Step 3: Drag and release RMB → throw grenade
    /// </summary>
    private enum GrenadeState
    {
        Idle,           // No grenade action
        TimerStarted,   // Step 1 complete - grenade timer running, G held, waiting for RMB
        WaitingForGRelease, // Step 2 in progress - G+RMB held, waiting for G release
        Aiming          // Step 2 complete - only RMB held, waiting for drag and release to throw
    }

    /// <summary>
    /// Current grenade state.
    /// </summary>
    private GrenadeState _grenadeState = GrenadeState.Idle;

    /// <summary>
    /// Active grenade instance (created when timer starts).
    /// </summary>
    private RigidBody2D? _activeGrenade = null;

    /// <summary>
    /// Position where the grenade throw drag started.
    /// </summary>
    private Vector2 _grenadeDragStart = Vector2.Zero;

    /// <summary>
    /// Whether the grenade throw drag is active (for step 1).
    /// </summary>
    private bool _grenadeDragActive = false;

    /// <summary>
    /// Minimum drag distance to confirm step 1 (in pixels).
    /// </summary>
    private const float MinDragDistanceForStep1 = 30.0f;

    /// <summary>
    /// Player's rotation before throw (to restore after throw animation).
    /// </summary>
    private float _playerRotationBeforeThrow = 0.0f;

    /// <summary>
    /// Whether player is in throw rotation animation.
    /// </summary>
    private bool _isThrowRotating = false;

    /// <summary>
    /// Target rotation for throw animation.
    /// </summary>
    private float _throwTargetRotation = 0.0f;

    /// <summary>
    /// Time remaining for throw rotation to restore.
    /// </summary>
    private float _throwRotationRestoreTimer = 0.0f;

    /// <summary>
    /// Duration of throw rotation animation.
    /// </summary>
    private const float ThrowRotationDuration = 0.15f;

    /// <summary>
    /// Signal emitted when reload sequence progresses.
    /// </summary>
    [Signal]
    public delegate void ReloadSequenceProgressEventHandler(int step, int total);

    /// <summary>
    /// Signal emitted when reload completes.
    /// </summary>
    [Signal]
    public delegate void ReloadCompletedEventHandler();

    /// <summary>
    /// Signal emitted when reload starts (first step of sequence).
    /// This signal notifies enemies that the player has begun reloading.
    /// </summary>
    [Signal]
    public delegate void ReloadStartedEventHandler();

    /// <summary>
    /// Signal emitted when player tries to shoot with empty weapon.
    /// This signal notifies enemies that the player is out of ammo.
    /// </summary>
    [Signal]
    public delegate void AmmoDepletedEventHandler();

    /// <summary>
    /// Signal emitted when grenade count changes.
    /// </summary>
    [Signal]
    public delegate void GrenadeChangedEventHandler(int current, int maximum);

    /// <summary>
    /// Signal emitted when a grenade is thrown.
    /// </summary>
    [Signal]
    public delegate void GrenadeThrownEventHandler();

    public override void _Ready()
    {
        base._Ready();

        // Get sprite reference for visual feedback
        _sprite = GetNodeOrNull<Sprite2D>("Sprite2D");

        // Configure random health (2-4 HP)
        if (HealthComponent != null)
        {
            HealthComponent.UseRandomHealth = true;
            HealthComponent.MinRandomHealth = 2;
            HealthComponent.MaxRandomHealth = 4;
            HealthComponent.InitializeHealth();

            GD.Print($"[Player] {Name}: Spawned with health {HealthComponent.CurrentHealth}/{HealthComponent.MaxHealth}");

            // Connect to health changed signal for visual feedback
            HealthComponent.HealthChanged += OnPlayerHealthChanged;
        }

        // Update visual based on initial health
        UpdateHealthVisual();

        // Preload bullet scene if not set in inspector
        if (BulletScene == null)
        {
            // Try C# bullet scene first, fallback to GDScript version
            BulletScene = GD.Load<PackedScene>("res://scenes/projectiles/csharp/Bullet.tscn");
            if (BulletScene == null)
            {
                BulletScene = GD.Load<PackedScene>("res://scenes/projectiles/Bullet.tscn");
            }
        }

        // Preload grenade scene if not set in inspector
        if (GrenadeScene == null)
        {
            GrenadeScene = GD.Load<PackedScene>("res://scenes/projectiles/FlashbangGrenade.tscn");
            if (GrenadeScene != null)
            {
                LogToFile($"[Player.Grenade] Grenade scene loaded");
            }
            else
            {
                LogToFile($"[Player.Grenade] WARNING: Grenade scene not found at res://scenes/projectiles/FlashbangGrenade.tscn");
            }
        }

        // Detect if we're on the tutorial level
        // Tutorial level is: scenes/levels/csharp/TestTier.tscn with tutorial_level.gd script
        var currentScene = GetTree().CurrentScene;
        if (currentScene != null)
        {
            var scenePath = currentScene.SceneFilePath;
            // Tutorial level is detected by:
            // 1. Scene path contains "csharp/TestTier" (the tutorial scene)
            // 2. OR scene uses tutorial_level.gd script
            _isTutorialLevel = scenePath.Contains("csharp/TestTier");

            // Also check if the scene script is tutorial_level.gd
            var script = currentScene.GetScript();
            if (script.Obj is GodotObject scriptObj)
            {
                var scriptPath = scriptObj.Get("resource_path").AsString();
                if (scriptPath.Contains("tutorial_level"))
                {
                    _isTutorialLevel = true;
                }
            }
        }

        // Initialize grenade count based on level type
        // Tutorial: infinite grenades (max count)
        // Other levels: 1 grenade
        if (_isTutorialLevel)
        {
            _currentGrenades = MaxGrenades;
            LogToFile($"[Player.Grenade] Tutorial level detected - infinite grenades enabled");
        }
        else
        {
            _currentGrenades = 1;
            LogToFile($"[Player.Grenade] Normal level - starting with 1 grenade");
        }

        // Auto-equip weapon if not set but a weapon child exists
        if (CurrentWeapon == null)
        {
            CurrentWeapon = GetNodeOrNull<BaseWeapon>("AssaultRifle");
            if (CurrentWeapon != null)
            {
                GD.Print($"[Player] {Name}: Auto-equipped weapon {CurrentWeapon.Name}");
            }
        }

        LogToFile($"[Player] Ready! Grenades: {_currentGrenades}/{MaxGrenades}");
    }

    /// <summary>
    /// Called when player health changes - updates visual feedback.
    /// </summary>
    private void OnPlayerHealthChanged(float currentHealth, float maxHealth)
    {
        GD.Print($"[Player] {Name}: Health changed to {currentHealth}/{maxHealth} ({HealthComponent?.HealthPercent * 100:F0}%)");
        UpdateHealthVisual();
    }

    /// <summary>
    /// Updates the sprite color based on current health percentage.
    /// </summary>
    private void UpdateHealthVisual()
    {
        if (_sprite == null || HealthComponent == null)
        {
            return;
        }

        // Interpolate color based on health percentage
        float healthPercent = HealthComponent.HealthPercent;
        _sprite.Modulate = FullHealthColor.Lerp(LowHealthColor, 1.0f - healthPercent);
    }

    public override void _PhysicsProcess(double delta)
    {
        Vector2 inputDirection = GetInputDirection();
        ApplyMovement(inputDirection, (float)delta);

        // Handle throw rotation animation (restore player rotation after throw)
        HandleThrowRotationAnimation((float)delta);

        // Handle grenade input first (so it can consume shoot input)
        HandleGrenadeInput();

        // Make active grenade follow player if held
        if (_activeGrenade != null && IsInstanceValid(_activeGrenade))
        {
            _activeGrenade.GlobalPosition = GlobalPosition;
        }

        // Handle shooting input - support both automatic and semi-automatic weapons
        // Allow shooting when not in grenade preparation
        bool canShoot = _grenadeState == GrenadeState.Idle || _grenadeState == GrenadeState.TimerStarted;
        if (canShoot)
        {
            HandleShootingInput();
        }

        // Handle reload sequence input (R-F-R)
        HandleReloadSequenceInput();

        // Handle fire mode toggle (B key for burst/auto toggle)
        if (Input.IsActionJustPressed("toggle_fire_mode"))
        {
            ToggleFireMode();
        }
    }

    /// <summary>
    /// Handles shooting input based on weapon type.
    /// For automatic weapons: fires while held.
    /// For semi-automatic/burst: fires on press.
    /// Also handles bullet in chamber mechanics during reload sequence.
    /// </summary>
    private void HandleShootingInput()
    {
        if (CurrentWeapon == null)
        {
            // Fallback to original click-to-shoot behavior
            if (Input.IsActionJustPressed("shoot"))
            {
                Shoot();
            }
            return;
        }

        // Check if weapon is automatic (based on WeaponData)
        bool isAutomatic = CurrentWeapon.WeaponData?.IsAutomatic ?? false;

        // For AssaultRifle, also check if it's in automatic fire mode
        if (CurrentWeapon is AssaultRifle assaultRifle)
        {
            isAutomatic = assaultRifle.CurrentFireMode == FireMode.Automatic;
        }

        // Determine if shooting input is active
        bool shootInputActive = isAutomatic ? Input.IsActionPressed("shoot") : Input.IsActionJustPressed("shoot");

        if (!shootInputActive)
        {
            return;
        }

        // Check if weapon is empty before trying to shoot (not in reload sequence)
        // This notifies enemies that the player tried to shoot with no ammo
        if (!_isReloadingSequence && CurrentWeapon.CurrentAmmo <= 0)
        {
            // Emit signal to notify enemies that player is vulnerable (out of ammo)
            EmitSignal(SignalName.AmmoDepleted);
            // The weapon will play the empty click sound
        }

        // Handle shooting based on reload sequence state
        if (_isReloadingSequence)
        {
            // In reload sequence
            if (_reloadSequenceStep == 1)
            {
                // Step 1 (only R pressed, waiting for F): shooting resets the combo
                GD.Print("[Player] Shooting during reload step 1 - resetting reload sequence");
                ResetReloadSequence();
                Shoot();
            }
            else if (_reloadSequenceStep == 2)
            {
                // Step 2 (R->F pressed, waiting for final R): try to fire chamber bullet
                if (CurrentWeapon.CanFireChamberBullet)
                {
                    // Fire the chamber bullet
                    Vector2 mousePos = GetGlobalMousePosition();
                    Vector2 shootDirection = (mousePos - GlobalPosition).Normalized();

                    if (CurrentWeapon.FireChamberBullet(shootDirection))
                    {
                        GD.Print("[Player] Fired bullet in chamber during reload");
                        // Note: Sound is handled by the weapon's FireChamberBullet implementation
                    }
                }
                else if (CurrentWeapon.ChamberBulletFired)
                {
                    // Chamber bullet already fired, can't shoot until reload completes
                    GD.Print("[Player] Cannot shoot - chamber bullet already fired, wait for reload to complete");
                    PlayEmptyClickSound();
                }
                else
                {
                    // No bullet in chamber (magazine was empty when reload started)
                    GD.Print("[Player] Cannot shoot - no bullet in chamber, wait for reload to complete");
                    PlayEmptyClickSound();
                }
            }
        }
        else
        {
            // Not in reload sequence - normal shooting
            Shoot();
        }
    }

    /// <summary>
    /// Plays the empty click sound when trying to shoot without ammo.
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
    /// Toggles fire mode on the current weapon (if supported).
    /// </summary>
    private void ToggleFireMode()
    {
        if (CurrentWeapon is AssaultRifle assaultRifle)
        {
            assaultRifle.ToggleFireMode();
        }
    }

    /// <summary>
    /// Gets the normalized input direction from player input.
    /// </summary>
    /// <returns>Normalized direction vector.</returns>
    private Vector2 GetInputDirection()
    {
        Vector2 direction = Vector2.Zero;
        direction.X = Input.GetAxis("move_left", "move_right");
        direction.Y = Input.GetAxis("move_up", "move_down");

        // Normalize to prevent faster diagonal movement
        if (direction.Length() > 1.0f)
        {
            direction = direction.Normalized();
        }

        return direction;
    }

    /// <summary>
    /// Handles the R-F-R reload sequence input.
    /// Step 0: Press R to start sequence (eject magazine)
    /// Step 1: Press F to continue (insert new magazine)
    /// Step 2: Press R to complete reload instantly (chamber round)
    ///
    /// Bullet in chamber mechanics:
    /// - At step 1 (R pressed): shooting resets the combo
    /// - At step 2 (R->F pressed): if previous magazine had ammo, one chamber bullet can be fired
    /// - After reload: if chamber bullet was fired, subtract one from new magazine
    /// </summary>
    private void HandleReloadSequenceInput()
    {
        if (CurrentWeapon == null)
        {
            return;
        }

        // Can't reload if magazine is full (and not in reload sequence)
        if (!_isReloadingSequence && CurrentWeapon.CurrentAmmo >= (CurrentWeapon.WeaponData?.MagazineSize ?? 0))
        {
            return;
        }

        // Can't reload if no reserve ammo (and not in reload sequence)
        if (!_isReloadingSequence && CurrentWeapon.ReserveAmmo <= 0)
        {
            return;
        }

        // Handle R key (first and third step)
        if (Input.IsActionJustPressed("reload"))
        {
            if (_reloadSequenceStep == 0 || _reloadSequenceStep == 1)
            {
                // Check if we can start a new reload (need ammo or already in sequence)
                if (_reloadSequenceStep == 0)
                {
                    // Starting fresh - check conditions
                    if (CurrentWeapon.CurrentAmmo >= (CurrentWeapon.WeaponData?.MagazineSize ?? 0))
                    {
                        return; // Magazine is full
                    }
                    if (CurrentWeapon.ReserveAmmo <= 0)
                    {
                        return; // No reserve ammo
                    }
                }

                // Start or restart reload sequence
                // This handles both initial R press and R->R sequence (restart)
                _isReloadingSequence = true;
                _reloadSequenceStep = 1;
                _ammoAtReloadStart = CurrentWeapon.CurrentAmmo;
                GD.Print($"[Player] Reload sequence started (R pressed) - ammo at start: {_ammoAtReloadStart} - press F next");
                // Play magazine out sound
                PlayReloadMagOutSound();
                EmitSignal(SignalName.ReloadSequenceProgress, 1, 3);
                // Notify enemies that player has started reloading (vulnerable state)
                EmitSignal(SignalName.ReloadStarted);
            }
            else if (_reloadSequenceStep == 2)
            {
                // Complete reload sequence - instant reload!
                // Play bolt cycling sound
                PlayM16BoltSound();
                CompleteReloadSequence();
            }
        }

        // Handle F key (reload_step action - second step)
        if (Input.IsActionJustPressed("reload_step"))
        {
            if (_reloadSequenceStep == 1)
            {
                // Continue to next step - set up chamber bullet
                _reloadSequenceStep = 2;

                // Set up bullet in chamber based on ammo at reload start
                bool hadAmmoInMagazine = _ammoAtReloadStart > 0;
                CurrentWeapon.StartReloadSequence(hadAmmoInMagazine);

                GD.Print($"[Player] Reload sequence step 2 (F pressed) - bullet in chamber: {hadAmmoInMagazine} - press R to complete");
                // Play magazine in sound
                PlayReloadMagInSound();
                EmitSignal(SignalName.ReloadSequenceProgress, 2, 3);
            }
            else if (_isReloadingSequence)
            {
                // Wrong key pressed, reset sequence
                GD.Print("[Player] Wrong key! Reload sequence reset (expected R)");
                ResetReloadSequence();
            }
        }
    }

    /// <summary>
    /// Plays the magazine out sound (first reload step).
    /// </summary>
    private void PlayReloadMagOutSound()
    {
        var audioManager = GetNodeOrNull("/root/AudioManager");
        if (audioManager != null && audioManager.HasMethod("play_reload_mag_out"))
        {
            audioManager.Call("play_reload_mag_out", GlobalPosition);
        }
    }

    /// <summary>
    /// Plays the magazine in sound (second reload step).
    /// </summary>
    private void PlayReloadMagInSound()
    {
        var audioManager = GetNodeOrNull("/root/AudioManager");
        if (audioManager != null && audioManager.HasMethod("play_reload_mag_in"))
        {
            audioManager.Call("play_reload_mag_in", GlobalPosition);
        }
    }

    /// <summary>
    /// Plays the M16 bolt cycling sound (third reload step).
    /// </summary>
    private void PlayM16BoltSound()
    {
        var audioManager = GetNodeOrNull("/root/AudioManager");
        if (audioManager != null && audioManager.HasMethod("play_m16_bolt"))
        {
            audioManager.Call("play_m16_bolt", GlobalPosition);
        }
    }

    /// <summary>
    /// Completes the reload sequence, instantly reloading the weapon.
    /// </summary>
    private void CompleteReloadSequence()
    {
        if (CurrentWeapon == null)
        {
            return;
        }

        // Perform instant reload
        CurrentWeapon.InstantReload();

        GD.Print("[Player] Reload sequence complete! Magazine refilled instantly.");
        EmitSignal(SignalName.ReloadSequenceProgress, 3, 3);
        EmitSignal(SignalName.ReloadCompleted);

        ResetReloadSequence();
    }

    /// <summary>
    /// Resets the reload sequence to the beginning.
    /// Also cancels the weapon's reload sequence state.
    /// </summary>
    private void ResetReloadSequence()
    {
        _reloadSequenceStep = 0;
        _isReloadingSequence = false;
        _ammoAtReloadStart = 0;

        // Cancel weapon's reload sequence state
        CurrentWeapon?.CancelReloadSequence();
    }

    /// <summary>
    /// Gets whether the player is currently in a reload sequence.
    /// </summary>
    public bool IsReloadingSequence => _isReloadingSequence;

    /// <summary>
    /// Gets the current reload sequence step (0-2).
    /// </summary>
    public int ReloadSequenceStep => _reloadSequenceStep;

    /// <summary>
    /// Fires a bullet towards the mouse cursor.
    /// Uses weapon system if available, otherwise uses direct bullet spawning.
    /// </summary>
    private void Shoot()
    {
        // Calculate direction towards mouse cursor
        Vector2 mousePos = GetGlobalMousePosition();
        Vector2 shootDirection = (mousePos - GlobalPosition).Normalized();

        // If we have a weapon equipped, use it
        if (CurrentWeapon != null)
        {
            CurrentWeapon.Fire(shootDirection);
            return;
        }

        // Otherwise use direct bullet spawning (original behavior)
        SpawnBullet(shootDirection);
    }

    /// <summary>
    /// Spawns a bullet directly without using the weapon system.
    /// Preserves the original template behavior.
    /// </summary>
    /// <param name="direction">Direction for the bullet to travel.</param>
    private void SpawnBullet(Vector2 direction)
    {
        if (BulletScene == null)
        {
            return;
        }

        // Create bullet instance
        var bullet = BulletScene.Instantiate<Node2D>();

        // Set bullet position with offset in shoot direction
        bullet.GlobalPosition = GlobalPosition + direction * BulletSpawnOffset;

        // Set bullet direction
        bullet.Set("Direction", direction);

        // Set shooter ID to prevent self-damage
        bullet.Set("ShooterId", GetInstanceId());

        // Add bullet to the scene tree
        GetTree().CurrentScene.AddChild(bullet);
    }

    /// <summary>
    /// Called when hit by a projectile via hit_area.gd.
    /// This method name follows GDScript naming convention for cross-language compatibility
    /// with the hit detection system that uses has_method("on_hit") checks.
    /// </summary>
    public void on_hit()
    {
        TakeDamage(1);
    }

    /// <inheritdoc/>
    public override void TakeDamage(float amount)
    {
        if (HealthComponent == null || !IsAlive)
        {
            return;
        }

        GD.Print($"[Player] {Name}: Taking {amount} damage. Current health: {HealthComponent.CurrentHealth}");

        // Show hit flash effect
        ShowHitFlash();

        // Determine if this hit will be lethal before applying damage
        bool willBeFatal = HealthComponent.CurrentHealth <= amount;

        // Play appropriate hit sound
        if (willBeFatal)
        {
            PlayHitLethalSound();
        }
        else
        {
            PlayHitNonLethalSound();
        }

        base.TakeDamage(amount);
    }

    /// <summary>
    /// Plays the lethal hit sound when player dies.
    /// </summary>
    private void PlayHitLethalSound()
    {
        var audioManager = GetNodeOrNull("/root/AudioManager");
        if (audioManager != null && audioManager.HasMethod("play_hit_lethal"))
        {
            audioManager.Call("play_hit_lethal", GlobalPosition);
        }
    }

    /// <summary>
    /// Plays the non-lethal hit sound when player is damaged but survives.
    /// </summary>
    private void PlayHitNonLethalSound()
    {
        var audioManager = GetNodeOrNull("/root/AudioManager");
        if (audioManager != null && audioManager.HasMethod("play_hit_non_lethal"))
        {
            audioManager.Call("play_hit_non_lethal", GlobalPosition);
        }
    }

    /// <summary>
    /// Shows a brief flash effect when hit.
    /// </summary>
    private async void ShowHitFlash()
    {
        if (_sprite == null)
        {
            return;
        }

        _sprite.Modulate = HitFlashColor;

        await ToSignal(GetTree().CreateTimer(HitFlashDuration), "timeout");

        // Restore color based on current health (if still alive)
        if (HealthComponent != null && HealthComponent.IsAlive)
        {
            UpdateHealthVisual();
        }
    }

    /// <inheritdoc/>
    public override void OnDeath()
    {
        base.OnDeath();
        // Handle player death
        GD.Print("Player died!");
    }

    /// <summary>
    /// Equips a new weapon.
    /// </summary>
    /// <param name="weapon">The weapon to equip.</param>
    public void EquipWeapon(BaseWeapon weapon)
    {
        // Unequip current weapon if any
        if (CurrentWeapon != null && CurrentWeapon.GetParent() == this)
        {
            RemoveChild(CurrentWeapon);
        }

        CurrentWeapon = weapon;

        // Add weapon as child if not already in scene tree
        if (CurrentWeapon.GetParent() == null)
        {
            AddChild(CurrentWeapon);
        }
    }

    /// <summary>
    /// Unequips the current weapon.
    /// </summary>
    public void UnequipWeapon()
    {
        if (CurrentWeapon != null && CurrentWeapon.GetParent() == this)
        {
            RemoveChild(CurrentWeapon);
        }
        CurrentWeapon = null;
    }

    #region Grenade System

    /// <summary>
    /// Handle grenade input with 2-step mechanic.
    /// Step 1: G + RMB drag right → starts 4s timer (pin pulled)
    /// Step 2: Hold G → press+hold RMB → release G → ready to throw (only RMB held)
    /// Step 3: Drag and release RMB → throw grenade
    /// </summary>
    private void HandleGrenadeInput()
    {
        // Check for active grenade explosion (explodes in hand after 4 seconds)
        if (_activeGrenade != null && !IsInstanceValid(_activeGrenade))
        {
            // Grenade exploded while held
            ResetGrenadeState();
            return;
        }

        switch (_grenadeState)
        {
            case GrenadeState.Idle:
                HandleGrenadeIdleState();
                break;
            case GrenadeState.TimerStarted:
                HandleGrenadeTimerStartedState();
                break;
            case GrenadeState.WaitingForGRelease:
                HandleGrenadeWaitingForGReleaseState();
                break;
            case GrenadeState.Aiming:
                HandleGrenadeAimingState();
                break;
        }
    }

    /// <summary>
    /// Handle grenade input in Idle state.
    /// Waiting for G + RMB drag right to start timer (Step 1).
    /// </summary>
    private void HandleGrenadeIdleState()
    {
        // Check if G key is held and player has grenades
        if (Input.IsActionPressed("grenade_prepare") && _currentGrenades > 0)
        {
            // Check if RMB was just pressed (start of drag)
            if (Input.IsActionJustPressed("grenade_throw"))
            {
                _grenadeDragStart = GetGlobalMousePosition();
                _grenadeDragActive = true;
                LogToFile($"[Player.Grenade] Step 1 started: G held, RMB pressed at {_grenadeDragStart}");
            }

            // Check if RMB was released (end of drag)
            if (_grenadeDragActive && Input.IsActionJustReleased("grenade_throw"))
            {
                Vector2 dragEnd = GetGlobalMousePosition();
                Vector2 dragVector = dragEnd - _grenadeDragStart;

                // Check if drag was to the right and long enough
                if (dragVector.X > MinDragDistanceForStep1)
                {
                    StartGrenadeTimer();
                    LogToFile($"[Player.Grenade] Step 1 complete! Drag: {dragVector}");
                }
                else
                {
                    LogToFile($"[Player.Grenade] Step 1 failed: drag not far enough right ({dragVector.X} < {MinDragDistanceForStep1})");
                }
                _grenadeDragActive = false;
            }
        }
        else
        {
            _grenadeDragActive = false;
        }
    }

    /// <summary>
    /// Handle grenade input in TimerStarted state.
    /// Waiting for RMB to be pressed while G is held (Step 2 part 1).
    /// </summary>
    private void HandleGrenadeTimerStartedState()
    {
        // If G is released, drop grenade at feet
        if (!Input.IsActionPressed("grenade_prepare"))
        {
            LogToFile("[Player.Grenade] G released - dropping grenade at feet");
            DropGrenadeAtFeet();
            return;
        }

        // Check if RMB is pressed to enter WaitingForGRelease state
        if (Input.IsActionJustPressed("grenade_throw"))
        {
            _grenadeState = GrenadeState.WaitingForGRelease;
            LogToFile("[Player.Grenade] Step 2 part 1: G+RMB held - now release G to ready the throw");
        }
    }

    /// <summary>
    /// Handle grenade input in WaitingForGRelease state.
    /// G+RMB are both held, waiting for G to be released (Step 2 part 2).
    /// </summary>
    private void HandleGrenadeWaitingForGReleaseState()
    {
        // If RMB is released before G, go back to TimerStarted
        if (!Input.IsActionPressed("grenade_throw"))
        {
            _grenadeState = GrenadeState.TimerStarted;
            LogToFile("[Player.Grenade] RMB released before G - back to waiting for RMB");
            return;
        }

        // If G is released while RMB is still held, enter Aiming state
        if (!Input.IsActionPressed("grenade_prepare"))
        {
            _grenadeState = GrenadeState.Aiming;
            _grenadeDragStart = GetGlobalMousePosition();
            LogToFile("[Player.Grenade] Step 2 complete: G released, RMB held - now aiming, drag and release RMB to throw");
        }
    }

    /// <summary>
    /// Handle grenade input in Aiming state.
    /// Only RMB is held (G was released), waiting for drag and release to throw.
    /// </summary>
    private void HandleGrenadeAimingState()
    {
        // In this state, G is already released (that's how we got here)
        // We only care about RMB

        // If RMB is released, throw the grenade
        if (Input.IsActionJustReleased("grenade_throw"))
        {
            Vector2 dragEnd = GetGlobalMousePosition();
            ThrowGrenade(dragEnd);
        }
    }

    /// <summary>
    /// Start the grenade timer (step 1 complete - pin pulled).
    /// Creates the grenade instance and starts its 4-second fuse.
    /// </summary>
    private void StartGrenadeTimer()
    {
        if (_currentGrenades <= 0)
        {
            LogToFile("[Player.Grenade] Cannot start timer: no grenades");
            return;
        }

        if (GrenadeScene == null)
        {
            LogToFile("[Player.Grenade] Cannot start timer: GrenadeScene is null");
            return;
        }

        // Create grenade instance (held by player)
        _activeGrenade = GrenadeScene.Instantiate<RigidBody2D>();
        if (_activeGrenade == null)
        {
            LogToFile("[Player.Grenade] Failed to instantiate grenade scene");
            return;
        }

        // Add grenade to scene first (must be in tree before setting GlobalPosition)
        GetTree().CurrentScene.AddChild(_activeGrenade);

        // Set position AFTER AddChild (GlobalPosition only works when node is in the scene tree)
        _activeGrenade.GlobalPosition = GlobalPosition;

        // Activate the grenade timer (starts 4s countdown)
        if (_activeGrenade.HasMethod("activate_timer"))
        {
            _activeGrenade.Call("activate_timer");
        }

        _grenadeState = GrenadeState.TimerStarted;

        // Decrement grenade count now (pin is pulled) - but not on tutorial level (infinite)
        if (!_isTutorialLevel)
        {
            _currentGrenades--;
        }
        EmitSignal(SignalName.GrenadeChanged, _currentGrenades, MaxGrenades);

        // Play grenade prepare sound
        var audioManager = GetNodeOrNull("/root/AudioManager");
        if (audioManager != null && audioManager.HasMethod("play_grenade_prepare"))
        {
            audioManager.Call("play_grenade_prepare", GlobalPosition);
        }

        LogToFile($"[Player.Grenade] Timer started, grenade created at {GlobalPosition}");
    }

    /// <summary>
    /// Drop the grenade at player's feet (when G is released before throwing).
    /// </summary>
    private void DropGrenadeAtFeet()
    {
        if (_activeGrenade != null && IsInstanceValid(_activeGrenade))
        {
            // The grenade stays where it is (at player's feet)
            LogToFile($"[Player.Grenade] Grenade dropped at feet at {_activeGrenade.GlobalPosition}");
        }
        ResetGrenadeState();
    }

    /// <summary>
    /// Reset grenade state to idle.
    /// </summary>
    private void ResetGrenadeState()
    {
        _grenadeState = GrenadeState.Idle;
        _grenadeDragActive = false;
        _grenadeDragStart = Vector2.Zero;
        // Don't null out _activeGrenade - it's now an independent object in the scene
        _activeGrenade = null;
    }

    /// <summary>
    /// Throw the grenade based on aiming drag direction and distance.
    /// Includes player rotation animation to prevent grenade hitting player.
    /// </summary>
    /// <param name="dragEnd">The end position of the drag.</param>
    private void ThrowGrenade(Vector2 dragEnd)
    {
        if (_activeGrenade == null || !IsInstanceValid(_activeGrenade))
        {
            LogToFile("[Player.Grenade] Cannot throw: no active grenade");
            ResetGrenadeState();
            return;
        }

        // Calculate throw direction and distance from drag
        Vector2 dragVector = dragEnd - _grenadeDragStart;
        float dragDistance = dragVector.Length();

        // Direction is the drag direction (normalized)
        Vector2 throwDirection = dragVector.Normalized();

        // If drag is too short, use a minimum distance for the throw
        if (dragDistance < 10.0f)
        {
            // Default to throwing forward (towards mouse from player)
            throwDirection = (GetGlobalMousePosition() - GlobalPosition).Normalized();
            dragDistance = 50.0f; // Minimum throw distance
        }

        // Pass raw drag distance to grenade - GDScript handles the speed calculation
        // The grenade's drag_to_speed_multiplier controls the sensitivity
        LogToFile($"[Player.Grenade] Throwing! Direction: {throwDirection}, Drag distance: {dragDistance}");

        // Rotate player to face throw direction (prevents grenade hitting player when throwing upward)
        RotatePlayerForThrow(throwDirection);

        // IMPORTANT: Set grenade position to player's CURRENT position (not where it was activated)
        // Offset grenade spawn position in throw direction to avoid collision with player
        float spawnOffset = 60.0f; // Increased from 30 to 60 pixels in front of player to avoid hitting
        Vector2 spawnPosition = GlobalPosition + throwDirection * spawnOffset;
        _activeGrenade.GlobalPosition = spawnPosition;

        // Call the throw method on the grenade with raw drag distance
        if (_activeGrenade.HasMethod("throw_grenade"))
        {
            _activeGrenade.Call("throw_grenade", throwDirection, dragDistance);
        }

        // Emit signal
        EmitSignal(SignalName.GrenadeThrown);

        // Play grenade throw sound
        var audioManager = GetNodeOrNull("/root/AudioManager");
        if (audioManager != null && audioManager.HasMethod("play_grenade_throw"))
        {
            audioManager.Call("play_grenade_throw", GlobalPosition);
        }

        LogToFile($"[Player.Grenade] Thrown! Direction: {throwDirection}, Drag distance: {dragDistance}");

        // Reset state (grenade is now independent)
        ResetGrenadeState();
    }

    /// <summary>
    /// Rotate player to face throw direction (with swing animation).
    /// Prevents grenade from hitting player when throwing upward.
    /// </summary>
    /// <param name="throwDirection">The direction of the throw.</param>
    private void RotatePlayerForThrow(Vector2 throwDirection)
    {
        // Store current rotation to restore later
        _playerRotationBeforeThrow = Rotation;

        // Calculate target rotation (face throw direction)
        _throwTargetRotation = throwDirection.Angle();

        // Apply rotation immediately
        Rotation = _throwTargetRotation;

        // Start restore timer
        _isThrowRotating = true;
        _throwRotationRestoreTimer = ThrowRotationDuration;

        LogToFile($"[Player.Grenade] Player rotated for throw: {_playerRotationBeforeThrow} -> {_throwTargetRotation}");
    }

    /// <summary>
    /// Handle throw rotation animation - restore player rotation after throw.
    /// </summary>
    /// <param name="delta">Time since last frame.</param>
    private void HandleThrowRotationAnimation(float delta)
    {
        if (!_isThrowRotating)
        {
            return;
        }

        _throwRotationRestoreTimer -= delta;
        if (_throwRotationRestoreTimer <= 0)
        {
            // Restore original rotation
            Rotation = _playerRotationBeforeThrow;
            _isThrowRotating = false;
            LogToFile($"[Player.Grenade] Player rotation restored to {_playerRotationBeforeThrow}");
        }
    }

    /// <summary>
    /// Get current grenade count.
    /// </summary>
    public int GetCurrentGrenades()
    {
        return _currentGrenades;
    }

    /// <summary>
    /// Get maximum grenade count.
    /// </summary>
    public int GetMaxGrenades()
    {
        return MaxGrenades;
    }

    /// <summary>
    /// Add grenades to inventory (e.g., from pickup).
    /// </summary>
    /// <param name="count">Number of grenades to add.</param>
    public void AddGrenades(int count)
    {
        _currentGrenades = Mathf.Min(_currentGrenades + count, MaxGrenades);
        EmitSignal(SignalName.GrenadeChanged, _currentGrenades, MaxGrenades);
    }

    /// <summary>
    /// Check if player is preparing to throw a grenade.
    /// </summary>
    public bool IsPreparingGrenade()
    {
        return _grenadeState != GrenadeState.Idle;
    }

    #endregion

    #region Logging

    /// <summary>
    /// Logs a message to the FileLogger (GDScript autoload) for debugging.
    /// </summary>
    /// <param name="message">The message to log.</param>
    private void LogToFile(string message)
    {
        // Print to console
        GD.Print(message);

        // Also log to FileLogger if available
        var fileLogger = GetNodeOrNull("/root/FileLogger");
        if (fileLogger != null && fileLogger.HasMethod("log_info"))
        {
            fileLogger.Call("log_info", message);
        }
    }

    #endregion
}
