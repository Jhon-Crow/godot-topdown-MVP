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
    /// Signal emitted when reload sequence progresses.
    /// </summary>
    [Signal]
    public delegate void ReloadSequenceProgressEventHandler(int step, int total);

    /// <summary>
    /// Signal emitted when reload completes.
    /// </summary>
    [Signal]
    public delegate void ReloadCompletedEventHandler();

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

        // Auto-equip weapon if not set but a weapon child exists
        if (CurrentWeapon == null)
        {
            CurrentWeapon = GetNodeOrNull<BaseWeapon>("AssaultRifle");
            if (CurrentWeapon != null)
            {
                GD.Print($"[Player] {Name}: Auto-equipped weapon {CurrentWeapon.Name}");
            }
        }
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

        // Handle shooting input - support both automatic and semi-automatic weapons
        HandleShootingInput();

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
}
