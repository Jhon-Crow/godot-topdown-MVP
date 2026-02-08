using Godot;
using GodotTopDownTemplate.AbstractClasses;
using GodotTopDownTemplate.Projectiles;

namespace GodotTopDownTemplate.Weapons;

/// <summary>
/// Revolver reload state for multi-step cylinder loading (Issue #626).
/// Reload sequence: R (open cylinder, eject casings) → RMB drag up (insert cartridge)
/// → scroll wheel (rotate cylinder) → repeat → R (close cylinder)
/// </summary>
public enum RevolverReloadState
{
    /// <summary>
    /// Not reloading - normal operation.
    /// </summary>
    NotReloading,

    /// <summary>
    /// Cylinder is open - casings have been ejected.
    /// Player can insert cartridges with RMB drag up, rotate with scroll, or close with R.
    /// </summary>
    CylinderOpen,

    /// <summary>
    /// Cylinder is open and at least one cartridge has been inserted.
    /// Player can insert more cartridges with RMB drag up, rotate with scroll, or close with R.
    /// </summary>
    Loading,

    /// <summary>
    /// Cylinder is being closed - reload completing.
    /// </summary>
    Closing
}

/// <summary>
/// RSh-12 heavy revolver - semi-automatic high-caliber revolver.
/// Features:
/// - Semi-automatic fire (one shot per click)
/// - 12.7x55mm STs-130 armor-piercing bullets with 20 damage
/// - Penetrates enemies (bullet passes through)
/// - Weak ricochet, penetrates walls at 200px
/// - Strong screen shake and recoil (almost like sniper rifle)
/// - Comfortable aiming like silenced pistol (smooth rotation, sensitivity 2.0)
/// - 5-round cylinder (12.7mm caliber)
/// - Pistol casings (longer than standard)
/// - Very loud (alerts enemies at long range)
/// - Multi-step reload: R (open) → RMB drag up (insert) → scroll (rotate) → R (close) (Issue #626)
/// Reference: https://news.rambler.ru/weapon/40992656-slonoboy-russkiy-revolver-kotoryy-sposoben-unichtozhit-bronetransporter/
/// </summary>
public partial class Revolver : BaseWeapon
{
    /// <summary>
    /// Minimum drag distance to register a gesture (in pixels).
    /// Same threshold as shotgun for consistent feel.
    /// </summary>
    [Export]
    public float MinDragDistance { get; set; } = 30.0f;

    /// <summary>
    /// Reference to the Sprite2D node for the weapon visual.
    /// </summary>
    private Sprite2D? _weaponSprite;

    /// <summary>
    /// Current aim direction based on mouse position.
    /// </summary>
    private Vector2 _aimDirection = Vector2.Right;

    /// <summary>
    /// Position where RMB drag started for gesture detection.
    /// </summary>
    private Vector2 _dragStartPosition = Vector2.Zero;

    /// <summary>
    /// Whether a RMB drag gesture is currently active.
    /// </summary>
    private bool _isDragging = false;

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
    /// RSh-12 has heavy recoil close to the sniper rifle.
    /// </summary>
    private float _recoilOffset = 0.0f;

    /// <summary>
    /// Time since the last shot was fired, used for recoil recovery.
    /// </summary>
    private float _timeSinceLastShot = 0.0f;

    /// <summary>
    /// Time in seconds before recoil starts recovering.
    /// Long delay for heavy revolver (close to sniper rifle).
    /// </summary>
    private const float RecoilRecoveryDelay = 0.45f;

    /// <summary>
    /// Speed at which recoil recovers (radians per second).
    /// Slower than standard pistols, reflecting heavy caliber.
    /// </summary>
    private const float RecoilRecoverySpeed = 3.5f;

    /// <summary>
    /// Maximum recoil offset in radians (about 13 degrees).
    /// Close to sniper rifle (15 degrees) but slightly less.
    /// </summary>
    private const float MaxRecoilOffset = 0.23f;

    /// <summary>
    /// Recoil amount per shot in radians.
    /// Heavy kick for 12.7mm revolver, close to sniper rifle.
    /// </summary>
    private const float RecoilPerShot = 0.12f;

    /// <summary>
    /// Muzzle flash scale for the RSh-12 revolver.
    /// Large flash for 12.7mm caliber but smaller than sniper rifle
    /// (revolver has shorter barrel, so more flash but less total gas).
    /// </summary>
    private const float RevolverMuzzleFlashScale = 1.5f;

    /// <summary>
    /// Current reload state for multi-step cylinder reload (Issue #626).
    /// </summary>
    public RevolverReloadState ReloadState { get; private set; } = RevolverReloadState.NotReloading;

    /// <summary>
    /// Number of cartridges loaded into the cylinder during the current reload.
    /// Tracks how many F presses have been made since opening the cylinder.
    /// </summary>
    public int CartridgesLoadedThisReload { get; private set; } = 0;

    /// <summary>
    /// Number of spent casings that were ejected when cylinder was opened.
    /// Used for spawning casing effects.
    /// </summary>
    private int _spentCasingsToEject = 0;

    /// <summary>
    /// Signal emitted when the reload state changes.
    /// </summary>
    [Signal]
    public delegate void ReloadStateChangedEventHandler(int newState);

    /// <summary>
    /// Signal emitted when a cartridge is inserted into the cylinder.
    /// Provides the number of cartridges loaded so far and the cylinder capacity.
    /// </summary>
    [Signal]
    public delegate void CartridgeInsertedEventHandler(int loaded, int capacity);

    /// <summary>
    /// Signal emitted when casings are ejected from the cylinder.
    /// Provides the number of casings ejected.
    /// </summary>
    [Signal]
    public delegate void CasingsEjectedEventHandler(int count);

    /// <summary>
    /// Signal emitted when the hammer is cocked before firing (Issue #661).
    /// This is a separate event so that other systems can react to it
    /// (e.g., animations, UI feedback, enemy awareness).
    /// </summary>
    [Signal]
    public delegate void HammerCockedEventHandler();

    /// <summary>
    /// Whether the hammer is currently cocked and waiting to fire (Issue #661).
    /// </summary>
    private bool _isHammerCocked = false;

    /// <summary>
    /// Timer for the delay between hammer cock and actual shot (Issue #661).
    /// The hammer cocks and cylinder rotates first, then the shot fires.
    /// </summary>
    private float _hammerCockTimer = 0.0f;

    /// <summary>
    /// Direction stored when hammer was cocked, used for the delayed shot (Issue #661).
    /// </summary>
    private Vector2 _pendingShotDirection = Vector2.Zero;

    /// <summary>
    /// Delay in seconds between hammer cock and shot (Issue #661).
    /// Short enough to feel responsive, long enough for the cock sound to be heard.
    /// </summary>
    private const float HammerCockDelay = 0.15f;

    public override void _Ready()
    {
        base._Ready();

        // Get the weapon sprite for visual representation
        _weaponSprite = GetNodeOrNull<Sprite2D>("RevolverSprite");

        if (_weaponSprite != null)
        {
            var texture = _weaponSprite.Texture;
            GD.Print($"[Revolver] RevolverSprite found: visible={_weaponSprite.Visible}, z_index={_weaponSprite.ZIndex}, texture={(texture != null ? "loaded" : "NULL")}");
        }
        else
        {
            GD.Print("[Revolver] No RevolverSprite node (visual model not yet added)");
        }

        int cylinderCapacity = WeaponData?.MagazineSize ?? 5;
        GD.Print($"[Revolver] RSh-12 initialized - heavy revolver ready, cylinder capacity={cylinderCapacity}");
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

        // Handle hammer cock delay timer (Issue #661)
        // After cocking the hammer, wait a short delay then fire the shot
        if (_isHammerCocked && _hammerCockTimer > 0)
        {
            _hammerCockTimer -= (float)delta;
            if (_hammerCockTimer <= 0)
            {
                ExecuteShot(_pendingShotDirection);
                _isHammerCocked = false;
            }
        }

        // Update aim direction and weapon sprite rotation
        UpdateAimDirection();

        // Handle RMB drag gestures for cartridge insertion (Issue #626)
        HandleDragGestures();
    }

    /// <summary>
    /// Handles mouse scroll wheel input for cylinder rotation (Issue #626).
    /// Scroll up or down rotates the cylinder by one position while it's open.
    /// </summary>
    public override void _Input(InputEvent @event)
    {
        base._Input(@event);

        // Handle scroll wheel for cylinder rotation while cylinder is open
        if (@event is InputEventMouseButton mouseButton && mouseButton.Pressed)
        {
            if (ReloadState == RevolverReloadState.CylinderOpen
                || ReloadState == RevolverReloadState.Loading)
            {
                if (mouseButton.ButtonIndex == MouseButton.WheelUp
                    || mouseButton.ButtonIndex == MouseButton.WheelDown)
                {
                    int direction = mouseButton.ButtonIndex == MouseButton.WheelUp ? 1 : -1;
                    RotateCylinder(direction);
                }
            }
        }
    }

    /// <summary>
    /// Handles RMB drag gestures for cartridge insertion (Issue #626).
    /// Follows the same pattern as shotgun pump-action:
    /// Hold RMB and drag UP (screen coordinates, negative Y) to insert a cartridge.
    /// Uses viewport mouse position (screen coords) for reliable gesture detection
    /// regardless of camera zoom level.
    /// </summary>
    private void HandleDragGestures()
    {
        // Only process drag gestures while cylinder is open
        if (ReloadState != RevolverReloadState.CylinderOpen
            && ReloadState != RevolverReloadState.Loading)
        {
            _isDragging = false;
            return;
        }

        bool rawRMBState = Input.IsMouseButtonPressed(MouseButton.Right);

        if (rawRMBState)
        {
            if (!_isDragging)
            {
                // Use viewport mouse position (screen coordinates) for consistent drag detection
                _dragStartPosition = GetViewport().GetMousePosition();
                _isDragging = true;
            }
            else
            {
                // Check for mid-drag gesture completion (continuous gesture without releasing RMB)
                Vector2 currentPosition = GetViewport().GetMousePosition();
                Vector2 dragVector = currentPosition - _dragStartPosition;

                if (TryProcessDragGesture(dragVector))
                {
                    // Gesture processed - reset drag start for next gesture
                    _dragStartPosition = currentPosition;
                }
            }
        }
        else if (_isDragging)
        {
            // RMB released - evaluate the drag gesture
            Vector2 dragEnd = GetViewport().GetMousePosition();
            Vector2 dragVector = dragEnd - _dragStartPosition;
            _isDragging = false;

            TryProcessDragGesture(dragVector);
        }
    }

    /// <summary>
    /// Attempts to process a drag gesture for cartridge insertion.
    /// Drag UP (negative Y in screen coordinates) while cylinder is open inserts a cartridge.
    /// </summary>
    /// <returns>True if a gesture was processed.</returns>
    private bool TryProcessDragGesture(Vector2 dragVector)
    {
        // Must meet minimum distance threshold (in screen pixels)
        if (dragVector.Length() < MinDragDistance)
        {
            return false;
        }

        // Must be primarily vertical (not horizontal)
        if (Mathf.Abs(dragVector.Y) <= Mathf.Abs(dragVector.X))
        {
            return false;
        }

        // Drag UP = negative Y in screen coordinates
        bool isDragUp = dragVector.Y < 0;

        if (!isDragUp)
        {
            return false;
        }

        // Insert a cartridge
        if (InsertCartridge())
        {
            // Play cartridge insert sound via AudioManager
            PlayCartridgeInsertSound();
            GD.Print($"[Revolver] RMB drag up - cartridge inserted (drag: {dragVector.Y:F0}px)");
            return true;
        }

        return false;
    }

    /// <summary>
    /// Updates the aim direction based on mouse position.
    /// RSh-12 uses silenced pistol-like low sensitivity for smooth, deliberate aiming.
    /// The heavy revolver is comfortable to aim despite its power.
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
        // RSh-12 has same smooth aiming as silenced pistol (sensitivity 2.0)
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
    /// Fires the RSh-12 revolver in semi-automatic mode (Issue #661).
    /// When the player presses LMB, the hammer cocks and the cylinder rotates first,
    /// then after a short delay the shot fires. This gives the revolver a distinctive
    /// mechanical feel with audible hammer cock and cylinder rotation before each shot.
    /// </summary>
    /// <param name="direction">Direction to fire (uses aim direction).</param>
    /// <returns>True if the fire sequence was initiated successfully.</returns>
    public override bool Fire(Vector2 direction)
    {
        // Cannot fire while cylinder is open (Issue #626)
        if (ReloadState != RevolverReloadState.NotReloading)
        {
            GD.Print("[Revolver] Cannot fire - cylinder is open");
            return false;
        }

        // Cannot fire while hammer is already cocked and waiting to fire
        if (_isHammerCocked)
        {
            return false;
        }

        // Check for empty cylinder - play click sound
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

        // Issue #661: Cock the hammer and rotate the cylinder before firing.
        // The actual shot happens after a short delay (HammerCockDelay).
        _isHammerCocked = true;
        _hammerCockTimer = HammerCockDelay;
        _pendingShotDirection = direction;

        // Play hammer cock sound
        PlayHammerCockSound();

        // Play cylinder rotation sound (different variants for variety)
        PlayCylinderRotateSound();

        // Emit HammerCocked signal as a separate event (Issue #661 requirement #2)
        EmitSignal(SignalName.HammerCocked);

        GD.Print("[Revolver] Hammer cocked, cylinder rotated - shot pending");

        return true;
    }

    /// <summary>
    /// Executes the actual shot after the hammer cock delay (Issue #661).
    /// Called from _Process when the hammer cock timer expires.
    /// </summary>
    /// <param name="direction">Direction to fire.</param>
    private void ExecuteShot(Vector2 direction)
    {
        // Re-check conditions (state may have changed during delay)
        if (ReloadState != RevolverReloadState.NotReloading)
        {
            GD.Print("[Revolver] Shot cancelled - cylinder was opened during hammer cock");
            return;
        }

        if (CurrentAmmo <= 0 || WeaponData == null || BulletScene == null)
        {
            GD.Print("[Revolver] Shot cancelled - conditions changed during hammer cock");
            return;
        }

        // Apply recoil offset to aim direction
        Vector2 spreadDirection = ApplySpread(_aimDirection);
        bool result = base.Fire(spreadDirection);

        if (result)
        {
            // Play heavy revolver shot sound
            PlayRevolverShotSound();
            // Emit gunshot sound for in-game sound propagation (very loud)
            EmitGunshotSound();
            // Note: No casing ejection on fire - revolver keeps spent casings in the cylinder
            // until the player opens it (casings eject in OpenCylinder → SpawnEjectedCasings)
            // Trigger heavy screen shake (close to sniper rifle)
            TriggerScreenShake(spreadDirection);
        }
    }

    /// <summary>
    /// Applies recoil offset to the shooting direction and adds new recoil.
    /// RSh-12 has heavy recoil close to sniper rifle, with extended recovery time.
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

            // Add heavy recoil for next shot (close to sniper rifle)
            float recoilDirection = (float)GD.RandRange(-1.0, 1.0);
            _recoilOffset += recoilDirection * RecoilPerShot;
            _recoilOffset = Mathf.Clamp(_recoilOffset, -MaxRecoilOffset, MaxRecoilOffset);
        }

        // Reset time since last shot for recoil recovery
        _timeSinceLastShot = 0;

        return result;
    }

    /// <summary>
    /// Plays the revolver hammer cock sound via AudioManager (Issue #661).
    /// Called before each shot to give the revolver its distinctive mechanical feel.
    /// </summary>
    private void PlayHammerCockSound()
    {
        var audioManager = GetNodeOrNull("/root/AudioManager");
        if (audioManager != null && audioManager.HasMethod("play_revolver_hammer_cock"))
        {
            audioManager.Call("play_revolver_hammer_cock", GlobalPosition);
        }
    }

    /// <summary>
    /// Plays the revolver empty click sound (no ammo).
    /// </summary>
    private void PlayEmptyClickSound()
    {
        var audioManager = GetNodeOrNull("/root/AudioManager");
        if (audioManager != null && audioManager.HasMethod("play_revolver_empty_click"))
        {
            audioManager.Call("play_revolver_empty_click", GlobalPosition);
        }
    }

    /// <summary>
    /// Plays the RSh-12 revolver shot sound via AudioManager.
    /// Uses dedicated revolver shot sounds (random variant).
    /// </summary>
    private void PlayRevolverShotSound()
    {
        var audioManager = GetNodeOrNull("/root/AudioManager");
        if (audioManager == null)
        {
            return;
        }

        if (audioManager.HasMethod("play_revolver_shot"))
        {
            audioManager.Call("play_revolver_shot", GlobalPosition);
        }
    }

    /// <summary>
    /// Emits a gunshot sound to SoundPropagation system for in-game sound propagation.
    /// The RSh-12 is very loud (12.7mm round), alerting enemies at long range.
    /// </summary>
    private void EmitGunshotSound()
    {
        var soundPropagation = GetNodeOrNull("/root/SoundPropagation");
        if (soundPropagation != null && soundPropagation.HasMethod("emit_sound"))
        {
            float loudness = WeaponData?.Loudness ?? 2500.0f;
            soundPropagation.Call("emit_sound", 0, GlobalPosition, 0, this, loudness);
        }
    }

    /// <summary>
    /// Triggers heavy screen shake based on shooting direction.
    /// RSh-12 has strong recoil close to sniper rifle, with extended recovery time.
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
        float recoveryTime = WeaponData.ScreenShakeMinRecoveryTime;

        screenShakeManager.Call("add_shake", shootDirection, shakeIntensity, recoveryTime);
    }

    /// <summary>
    /// Fires the bullet in the chamber during reload sequence.
    /// Note: Chamber bullet fires immediately without hammer cock delay,
    /// since the hammer is already in a ready state during reload sequence.
    /// </summary>
    public override bool FireChamberBullet(Vector2 direction)
    {
        Vector2 spreadDirection = ApplySpread(_aimDirection);
        bool result = base.FireChamberBullet(spreadDirection);

        if (result)
        {
            PlayRevolverShotSound();
            EmitGunshotSound();
            // No casing ejection - spent casings stay in cylinder
            TriggerScreenShake(spreadDirection);
        }

        return result;
    }

    /// <summary>
    /// Override SpawnCasing to suppress casing ejection during normal fire.
    /// Revolvers keep spent casings in the cylinder - they only fall out when
    /// the player opens the cylinder (handled by SpawnEjectedCasings in OpenCylinder).
    /// </summary>
    protected override void SpawnCasing(Vector2 direction, Resource? caliber)
    {
        // Intentionally empty - revolvers don't eject casings when firing.
        // Spent casings stay in the cylinder until the player opens it.
    }

    /// <summary>
    /// Spawns a large muzzle flash for the RSh-12 revolver.
    /// The 12.7mm round creates a significant muzzle flash from the revolver's barrel.
    /// </summary>
    protected override void SpawnMuzzleFlash(Vector2 position, Vector2 direction, Resource? caliber)
    {
        var impactManager = GetNodeOrNull("/root/ImpactEffectsManager");
        if (impactManager != null && impactManager.HasMethod("spawn_muzzle_flash"))
        {
            // Pass caliber with large muzzle flash scale for 12.7mm revolver
            impactManager.Call("spawn_muzzle_flash", position, direction, caliber, RevolverMuzzleFlashScale);
        }
    }

    /// <summary>
    /// Gets the current aim direction.
    /// </summary>
    public Vector2 AimDirection => _aimDirection;

    #region Multi-Step Cylinder Reload (Issue #626)

    /// <summary>
    /// Gets the cylinder capacity (number of chambers in the revolver).
    /// </summary>
    public int CylinderCapacity => WeaponData?.MagazineSize ?? 5;

    /// <summary>
    /// Whether the cylinder can be opened for reloading.
    /// Can open when not already reloading and either cylinder is not full or has spent casings.
    /// </summary>
    public bool CanOpenCylinder => ReloadState == RevolverReloadState.NotReloading
                                   && !IsReloading;

    /// <summary>
    /// Whether a cartridge can be inserted into the cylinder.
    /// Requires cylinder to be open and not yet full, with spare ammo available.
    /// </summary>
    public bool CanInsertCartridge => (ReloadState == RevolverReloadState.CylinderOpen
                                      || ReloadState == RevolverReloadState.Loading)
                                     && CurrentAmmo < CylinderCapacity
                                     && MagazineInventory.HasSpareAmmo;

    /// <summary>
    /// Whether the cylinder can be closed.
    /// Requires cylinder to be open (with or without cartridges loaded).
    /// </summary>
    public bool CanCloseCylinder => ReloadState == RevolverReloadState.CylinderOpen
                                    || ReloadState == RevolverReloadState.Loading;

    /// <summary>
    /// Step 1: Open the cylinder and eject spent casings (Issue #626).
    /// Called when player presses R with the revolver equipped.
    /// Spent casings fall out (visual effect), cylinder is now empty and open.
    /// </summary>
    /// <returns>True if the cylinder was opened successfully.</returns>
    public bool OpenCylinder()
    {
        if (!CanOpenCylinder)
        {
            return false;
        }

        // Track how many spent rounds to eject as casings
        int cylinderCapacity = CylinderCapacity;
        _spentCasingsToEject = cylinderCapacity - CurrentAmmo;

        // Live rounds stay in the cylinder - only spent casings fall out
        // CurrentAmmo is NOT reset to 0 - the player only needs to reload empty chambers
        CartridgesLoadedThisReload = 0;

        // Update reload state
        ReloadState = RevolverReloadState.CylinderOpen;

        // Play cylinder open sound
        PlayCylinderOpenSound();

        // Spawn spent casings falling out and play ejection sound
        if (_spentCasingsToEject > 0)
        {
            SpawnEjectedCasings(_spentCasingsToEject);
            PlayCasingsEjectSound();
            EmitSignal(SignalName.CasingsEjected, _spentCasingsToEject);
        }

        EmitSignal(SignalName.ReloadStateChanged, (int)ReloadState);
        EmitSignal(SignalName.ReloadStarted);
        EmitSignal(SignalName.AmmoChanged, CurrentAmmo, ReserveAmmo);
        EmitMagazinesChanged();

        GD.Print($"[Revolver] Cylinder opened - ejected {_spentCasingsToEject} spent casings, {CurrentAmmo}/{cylinderCapacity} live rounds remain");

        return true;
    }

    /// <summary>
    /// Step 2: Insert one cartridge into the cylinder (Issue #626).
    /// Called when player drags RMB up with the cylinder open.
    /// Can be done up to CylinderCapacity times (5 for RSh-12).
    /// Consumes one round from reserve ammunition.
    /// </summary>
    /// <returns>True if a cartridge was inserted successfully.</returns>
    public bool InsertCartridge()
    {
        if (!CanInsertCartridge)
        {
            if (CurrentAmmo >= CylinderCapacity)
            {
                GD.Print("[Revolver] Cylinder is full - cannot insert more cartridges");
            }
            else if (!MagazineInventory.HasSpareAmmo)
            {
                GD.Print("[Revolver] No spare ammo - cannot insert cartridge");
            }
            return false;
        }

        // Consume one round from spare magazines
        // Find a spare magazine with ammo and take one round from it
        bool consumed = false;
        foreach (var mag in MagazineInventory.SpareMagazines)
        {
            if (mag.CurrentAmmo > 0)
            {
                mag.CurrentAmmo--;
                consumed = true;
                break;
            }
        }

        if (!consumed)
        {
            GD.Print("[Revolver] Failed to consume ammo from spare magazines");
            return false;
        }

        // Add one round to the cylinder
        CurrentAmmo++;
        CartridgesLoadedThisReload++;

        // Update state to Loading (at least one cartridge inserted)
        ReloadState = RevolverReloadState.Loading;

        EmitSignal(SignalName.CartridgeInserted, CartridgesLoadedThisReload, CylinderCapacity);
        EmitSignal(SignalName.ReloadStateChanged, (int)ReloadState);
        EmitSignal(SignalName.AmmoChanged, CurrentAmmo, ReserveAmmo);
        EmitMagazinesChanged();

        GD.Print($"[Revolver] Cartridge inserted ({CartridgesLoadedThisReload}/{CylinderCapacity}), ammo: {CurrentAmmo}/{CylinderCapacity}, reserve: {ReserveAmmo}");

        return true;
    }

    /// <summary>
    /// Step 3: Close the cylinder to complete the reload (Issue #626).
    /// Called when player presses R with the cylinder open (after inserting cartridges).
    /// Weapon is now ready to fire.
    /// </summary>
    /// <returns>True if the cylinder was closed successfully.</returns>
    public bool CloseCylinder()
    {
        if (!CanCloseCylinder)
        {
            return false;
        }

        ReloadState = RevolverReloadState.NotReloading;
        IsReloading = false;

        // Play cylinder close sound
        PlayCylinderCloseSound();

        EmitSignal(SignalName.ReloadStateChanged, (int)ReloadState);
        EmitSignal(SignalName.ReloadFinished);
        EmitSignal(SignalName.AmmoChanged, CurrentAmmo, ReserveAmmo);
        EmitMagazinesChanged();

        GD.Print($"[Revolver] Cylinder closed - {CurrentAmmo}/{CylinderCapacity} rounds loaded, ready to fire");

        return true;
    }

    /// <summary>
    /// Rotate the cylinder by one position (Issue #626).
    /// Called when player scrolls the mouse wheel while the cylinder is open.
    /// This is a purely visual/mechanical action - it doesn't load ammo,
    /// it just turns the cylinder to the next chamber position.
    /// </summary>
    /// <param name="direction">1 for clockwise, -1 for counter-clockwise.</param>
    /// <returns>True if the cylinder was rotated.</returns>
    public bool RotateCylinder(int direction)
    {
        if (ReloadState != RevolverReloadState.CylinderOpen
            && ReloadState != RevolverReloadState.Loading)
        {
            return false;
        }

        // Play cylinder rotation click sound
        PlayCylinderRotateSound();

        GD.Print($"[Revolver] Cylinder rotated {(direction > 0 ? "clockwise" : "counter-clockwise")}");

        return true;
    }

    /// <summary>
    /// Plays the cylinder open sound via AudioManager.
    /// </summary>
    public void PlayCylinderOpenSound()
    {
        var audioManager = GetNodeOrNull("/root/AudioManager");
        if (audioManager != null && audioManager.HasMethod("play_revolver_cylinder_open"))
        {
            audioManager.Call("play_revolver_cylinder_open", GlobalPosition);
        }
    }

    /// <summary>
    /// Plays the cylinder close sound via AudioManager.
    /// </summary>
    public void PlayCylinderCloseSound()
    {
        var audioManager = GetNodeOrNull("/root/AudioManager");
        if (audioManager != null && audioManager.HasMethod("play_revolver_cylinder_close"))
        {
            audioManager.Call("play_revolver_cylinder_close", GlobalPosition);
        }
    }

    /// <summary>
    /// Plays the cartridge insertion sound via AudioManager.
    /// </summary>
    private void PlayCartridgeInsertSound()
    {
        var audioManager = GetNodeOrNull("/root/AudioManager");
        if (audioManager != null && audioManager.HasMethod("play_revolver_cartridge_insert"))
        {
            audioManager.Call("play_revolver_cartridge_insert", GlobalPosition);
        }
    }

    /// <summary>
    /// Plays the cylinder rotation sound via AudioManager (random variant).
    /// </summary>
    private void PlayCylinderRotateSound()
    {
        var audioManager = GetNodeOrNull("/root/AudioManager");
        if (audioManager != null && audioManager.HasMethod("play_revolver_cylinder_rotate"))
        {
            audioManager.Call("play_revolver_cylinder_rotate", GlobalPosition);
        }
    }

    /// <summary>
    /// Plays the casings ejection sound via AudioManager.
    /// </summary>
    private void PlayCasingsEjectSound()
    {
        var audioManager = GetNodeOrNull("/root/AudioManager");
        if (audioManager != null && audioManager.HasMethod("play_revolver_casings_eject"))
        {
            audioManager.Call("play_revolver_casings_eject", GlobalPosition);
        }
    }

    /// <summary>
    /// Spawns casings falling from the opened cylinder.
    /// When the cylinder opens, spent casings fall out due to gravity.
    /// They drop downward (not ejected forcefully like semi-auto pistols).
    /// </summary>
    /// <param name="count">Number of casings to spawn.</param>
    private void SpawnEjectedCasings(int count)
    {
        if (CasingScene == null)
        {
            return;
        }

        for (int i = 0; i < count; i++)
        {
            var casing = CasingScene.Instantiate<RigidBody2D>();
            // Casings fall from the cylinder position with slight random spread
            float randomOffsetX = (float)GD.RandRange(-8.0f, 8.0f);
            float randomOffsetY = (float)GD.RandRange(-5.0f, 5.0f);
            casing.GlobalPosition = GlobalPosition + new Vector2(randomOffsetX, randomOffsetY);

            // Casings fall downward with slight random horizontal drift (gravity drop, not ejection)
            float horizontalDrift = (float)GD.RandRange(-30.0f, 30.0f);
            float downwardSpeed = (float)GD.RandRange(40.0f, 80.0f);
            casing.LinearVelocity = new Vector2(horizontalDrift, downwardSpeed);

            // Light spin as casings tumble
            casing.AngularVelocity = (float)GD.RandRange(-10.0f, 10.0f);

            // Set caliber data on the casing for appearance
            if (WeaponData?.Caliber != null)
            {
                casing.Set("caliber_data", WeaponData.Caliber);
            }

            GetTree().CurrentScene.AddChild(casing);
        }
    }

    /// <summary>
    /// Override StartReload to use cylinder-based reload instead of magazine swap.
    /// The base class timed reload is not used for the revolver.
    /// </summary>
    public override void StartReload()
    {
        // Revolver uses multi-step cylinder reload, not timed reload
        // This method is intentionally empty - reload is handled by
        // OpenCylinder(), InsertCartridge(), and CloseCylinder()
    }

    #endregion
}
