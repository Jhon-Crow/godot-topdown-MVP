using Godot;
using GodotTopDownTemplate.Characters;
using GodotTopDownTemplate.Data;
using System.Linq;
using CSharpBullet = GodotTopDownTemplate.Projectiles.Bullet;

namespace GodotTopDownTemplate.AbstractClasses;

/// <summary>
/// Abstract base class for all weapons in the game.
/// Provides common functionality for firing, reloading, and managing ammunition.
/// </summary>
public abstract partial class BaseWeapon : Node2D
{
    /// <summary>
    /// Weapon configuration data.
    /// </summary>
    [Export]
    public WeaponData? WeaponData { get; set; }

    /// <summary>
    /// Bullet scene to instantiate when firing.
    /// </summary>
    [Export]
    public PackedScene? BulletScene { get; set; }

    /// <summary>
    /// Casing scene to instantiate when firing (for ejected bullet casings).
    /// </summary>
    [Export]
    public PackedScene? CasingScene { get; set; }

    /// <summary>
    /// Offset from weapon position where bullets spawn.
    /// </summary>
    [Export]
    public float BulletSpawnOffset { get; set; } = 20.0f;

    /// <summary>
    /// Number of magazines the weapon starts with.
    /// </summary>
    [Export]
    public int StartingMagazineCount { get; set; } = 4;

    /// <summary>
    /// Magazine inventory managing all magazines for this weapon.
    /// </summary>
    protected MagazineInventory MagazineInventory { get; private set; } = new();

    /// <summary>
    /// Current ammunition in the magazine.
    /// Exported so GDScript can read it via weapon.get("CurrentAmmo") (Issue #950).
    /// The setter is only called internally from C# code.
    /// </summary>
    [Export]
    public int CurrentAmmo
    {
        get => MagazineInventory.CurrentMagazine?.CurrentAmmo ?? 0;
        set
        {
            if (MagazineInventory.CurrentMagazine != null)
            {
                MagazineInventory.CurrentMagazine.CurrentAmmo = value;
            }
        }
    }

    /// <summary>
    /// Total reserve ammunition across all spare magazines.
    /// Note: This now represents total ammo in spare magazines, not a simple counter.
    /// Exported so GDScript can read it via weapon.get("ReserveAmmo") (Issue #950).
    /// The setter is kept for backward compatibility but is a no-op.
    /// </summary>
    [Export]
    public int ReserveAmmo
    {
        get => MagazineInventory.TotalSpareAmmo;
        set
        {
            // This setter is kept for backward compatibility but does nothing.
            // Reserve ammo is calculated from individual magazines.
        }
    }

    /// <summary>
    /// Whether the weapon can currently fire.
    /// Virtual so weapons with non-standard ammo systems (e.g. Shotgun's tube magazine) can override.
    /// </summary>
    public virtual bool CanFire => CurrentAmmo > 0 && !IsReloading && _fireTimer <= 0;

    /// <summary>
    /// Whether the weapon is currently reloading.
    /// </summary>
    public bool IsReloading { get; protected set; }

    /// <summary>
    /// Whether there is a bullet in the chamber.
    /// This is true when the weapon had ammo when reload started (R->F sequence).
    /// </summary>
    public bool HasBulletInChamber { get; protected set; }

    /// <summary>
    /// Whether the chamber bullet was fired during reload.
    /// Used to track if we need to subtract a bullet after reload completes.
    /// </summary>
    public bool ChamberBulletFired { get; protected set; }

    /// <summary>
    /// Whether the weapon is in the middle of a reload sequence (between R->F and final R).
    /// When true, only chamber bullet can be fired (if available).
    /// </summary>
    public bool IsInReloadSequence { get; set; }


    /// <summary>
    /// Whether breaker bullets are active (passive item, Issue #678).
    /// When true, spawned bullets will have is_breaker_bullet = true.
    /// </summary>
    public bool IsBreakerBulletActive { get; set; } = false;

    /// <summary>
    /// Remaining drilling bullet count for the current magazine (Issue #751).
    /// When > 0, spawned bullets will have is_drilling_bullet = true (pass through walls).
    /// Decremented on each shot; player.gd sets this to CurrentAmmo on activation.
    /// </summary>
    public int DrillingBulletsRemaining { get; set; } = 0;

    /// <summary>
    /// Extra damage bonus added to every bullet spawned (Issue #1047, Combat Disposition passive item).
    /// Can be negative (penalty after taking damage).
    /// </summary>
    public float DamageBonus { get; set; } = 0.0f;

    /// <summary>
    /// Extra fire rate bonus added to fire rate (shots/sec) for every shot (Issue #1047, Combat Disposition passive item).
    /// Can be negative (penalty after taking damage).
    /// </summary>
    public float FireRateBonus { get; set; } = 0.0f;

    protected float _fireTimer;
    private float _reloadTimer;

    /// <summary>
    /// Signal emitted when the weapon fires.
    /// </summary>
    [Signal]
    public delegate void FiredEventHandler();

    /// <summary>
    /// Signal emitted when the weapon starts reloading.
    /// </summary>
    [Signal]
    public delegate void ReloadStartedEventHandler();

    /// <summary>
    /// Signal emitted when the weapon finishes reloading.
    /// </summary>
    [Signal]
    public delegate void ReloadFinishedEventHandler();

    /// <summary>
    /// Signal emitted when ammunition changes.
    /// </summary>
    [Signal]
    public delegate void AmmoChangedEventHandler(int currentAmmo, int reserveAmmo);

    /// <summary>
    /// Signal emitted when the magazine inventory changes (reload, etc).
    /// Provides an array of ammo counts for each magazine.
    /// First element is current magazine, rest are spares sorted by ammo count.
    /// </summary>
    [Signal]
    public delegate void MagazinesChangedEventHandler(int[] magazineAmmoCounts);

    public override void _Ready()
    {
        // Diagnostic logging for Issue #765 (weapon data corruption after restart)
        GD.Print($"[BaseWeapon] _Ready() called for weapon: {Name}");
        GD.Print($"[BaseWeapon]   WeaponData: {(WeaponData != null ? "Present" : "NULL")}");

        // Issue #765 Fix: Validate WeaponData and provide clear error if missing
        if (WeaponData == null)
        {
            GD.PrintErr($"[BaseWeapon] CRITICAL ERROR: WeaponData is NULL for weapon {Name}!");
            GD.PrintErr($"[BaseWeapon] This weapon will not function correctly. Check that:");
            GD.PrintErr($"[BaseWeapon]   1. The weapon scene (.tscn) has WeaponData resource assigned");
            GD.PrintErr($"[BaseWeapon]   2. The .tres file exists and is not corrupted");
            GD.PrintErr($"[BaseWeapon]   3. Scene reload hasn't cleared the resource reference");
            // Don't initialize if WeaponData is missing - prevents using wrong defaults
            return;
        }

        // Log weapon data for diagnostics
        GD.Print($"[BaseWeapon]   WeaponData.Name: {WeaponData.Name}");
        GD.Print($"[BaseWeapon]   WeaponData.MagazineSize: {WeaponData.MagazineSize}");
        GD.Print($"[BaseWeapon]   WeaponData.Caliber: {(WeaponData.Caliber != null ? "Present" : "NULL")}");
        if (WeaponData.Caliber != null)
        {
            var caliberName = WeaponData.Caliber.Get("caliber_name");
            GD.Print($"[BaseWeapon]   Caliber.caliber_name: {caliberName}");
        }
        GD.Print($"[BaseWeapon]   WeaponData resource path: {WeaponData.ResourcePath}");

        InitializeMagazinesWithDifficulty();

        // Connect to difficulty_changed signal to re-initialize ammo when difficulty changes
        var difficultyManager = GetNodeOrNull("/root/DifficultyManager");
        if (difficultyManager != null)
        {
            difficultyManager.Connect("difficulty_changed", Callable.From<int>(OnDifficultyChanged));
        }
    }

    /// <summary>
    /// Initializes magazine inventory accounting for Power Fantasy ammo multiplier.
    /// Can be called again when difficulty changes to re-apply the multiplier.
    /// </summary>
    protected virtual void InitializeMagazinesWithDifficulty()
    {
        if (WeaponData == null)
        {
            GD.PrintErr($"[BaseWeapon] InitializeMagazinesWithDifficulty: WeaponData is NULL for {Name}! Cannot initialize.");
            return;
        }

        int magazineCount = StartingMagazineCount;
        var difficultyManager = GetNodeOrNull("/root/DifficultyManager");
        if (difficultyManager != null)
        {
            var multiplierResult = difficultyManager.Call("get_ammo_multiplier");
            int ammoMultiplier = multiplierResult.AsInt32();
            if (ammoMultiplier > 1)
            {
                magazineCount *= ammoMultiplier;
                GD.Print($"[BaseWeapon] Power Fantasy mode: ammo multiplied by {ammoMultiplier}x ({StartingMagazineCount} -> {magazineCount} magazines)");
            }
        }

        int magazineSize = WeaponData.MagazineSize;

        // Apply extended magazine passive item (Issue #1065):
        // 2.5x magazine size, 5% less total ammo.
        var activeItemManager = GetNodeOrNull("/root/ActiveItemManager");
        if (activeItemManager != null && activeItemManager.HasMethod("has_extended_magazine")
            && activeItemManager.Call("has_extended_magazine").AsBool())
        {
            float magSizeMultiplier = activeItemManager.Call("get_magazine_size_multiplier").AsSingle();
            float totalAmmoMultiplier = activeItemManager.Call("get_total_ammo_multiplier").AsSingle();

            int originalTotal = magazineCount * magazineSize;
            int newMagSize = Mathf.Max(1, Mathf.RoundToInt(magazineSize * magSizeMultiplier));
            int newTotal = Mathf.Max(newMagSize, Mathf.RoundToInt(originalTotal * totalAmmoMultiplier));
            // Derive magazine count from new total / new magazine size (at least 1)
            int newMagCount = Mathf.Max(1, Mathf.CeilToInt((float)newTotal / newMagSize));

            GD.Print($"[BaseWeapon] Extended Magazine: magSize {magazineSize}->{newMagSize}, " +
                     $"magazines {magazineCount}->{newMagCount} (total ammo {originalTotal}->{newMagCount * newMagSize})");

            magazineSize = newMagSize;
            magazineCount = newMagCount;
        }

        // Diagnostic logging for Issue #765
        GD.Print($"[BaseWeapon] Initializing magazines for {Name}:");
        GD.Print($"[BaseWeapon]   Magazine count: {magazineCount}");
        GD.Print($"[BaseWeapon]   Magazine size: {magazineSize}");

        // Initialize magazine inventory with the starting magazines
        MagazineInventory.Initialize(magazineCount, magazineSize, fillAllMagazines: true);

        // Emit initial magazine state
        EmitMagazinesChanged();
    }

    /// <summary>
    /// Called when difficulty changes. Re-initializes magazines with the new ammo multiplier.
    /// </summary>
    private void OnDifficultyChanged(int newDifficulty)
    {
        if (WeaponData != null)
        {
            GD.Print($"[BaseWeapon] Difficulty changed to {newDifficulty}, re-initializing magazines");
            InitializeMagazinesWithDifficulty();
        }
    }

    /// <summary>
    /// Emits the MagazinesChanged signal with current magazine states.
    /// </summary>
    protected void EmitMagazinesChanged()
    {
        EmitSignal(SignalName.MagazinesChanged, MagazineInventory.GetMagazineAmmoCounts());
    }

    /// <summary>
    /// Gets all magazine ammo counts as an array.
    /// First element is current magazine, rest are spares sorted by ammo (descending).
    /// </summary>
    public int[] GetMagazineAmmoCounts()
    {
        return MagazineInventory.GetMagazineAmmoCounts();
    }

    /// <summary>
    /// Gets a formatted string showing all magazine ammo counts.
    /// Format: "[30] | 25 | 10" where [30] is current magazine.
    /// </summary>
    public string GetMagazineDisplayString()
    {
        return MagazineInventory.GetMagazineDisplayString();
    }

    public override void _Process(double delta)
    {
        if (_fireTimer > 0)
        {
            _fireTimer -= (float)delta;
        }

        if (IsReloading)
        {
            _reloadTimer -= (float)delta;
            if (_reloadTimer <= 0)
            {
                FinishReload();
            }
        }
    }

    /// <summary>
    /// Accelerates the fire cooldown timer by the given extra delta.
    /// Called by the recoil compensator to apply a 10% fire rate boost (Issue #1073).
    /// </summary>
    public void AccelerateFireTimer(float extraDelta)
    {
        if (_fireTimer > 0)
            _fireTimer -= extraDelta;
    }

    /// <summary>
    /// Attempts to fire the weapon in the specified direction.
    /// </summary>
    /// <param name="direction">Direction to fire.</param>
    /// <returns>True if the weapon fired successfully.</returns>
    public virtual bool Fire(Vector2 direction)
    {
        if (!CanFire || WeaponData == null || BulletScene == null)
        {
            return false;
        }

        // Consume ammo from current magazine
        MagazineInventory.ConsumeAmmo();
        float effectiveFireRate = WeaponData.FireRate + FireRateBonus;
        _fireTimer = 1.0f / Mathf.Max(effectiveFireRate, 0.1f);

        SpawnBullet(direction);

        EmitSignal(SignalName.Fired);
        EmitSignal(SignalName.AmmoChanged, CurrentAmmo, ReserveAmmo);
        EmitMagazinesChanged();

        return true;
    }

    /// <summary>
    /// Checks if the bullet spawn path is clear (no wall between weapon and spawn point).
    /// This prevents shooting through walls when standing flush against cover.
    /// If blocked, spawns wall hit effects and plays impact sound for feedback.
    ///
    /// Returns a tuple: (isBlocked, wallHitPosition, wallHitNormal).
    /// If isBlocked is true, the caller should spawn the bullet at weapon position
    /// instead of at the offset position, so penetration can occur.
    /// </summary>
    /// <param name="direction">Direction to check.</param>
    /// <returns>Tuple indicating if blocked and wall hit info.</returns>
    protected virtual (bool isBlocked, Vector2 hitPosition, Vector2 hitNormal) CheckBulletSpawnPath(Vector2 direction)
    {
        var spaceState = GetWorld2D()?.DirectSpaceState;
        if (spaceState == null)
        {
            return (false, Vector2.Zero, Vector2.Zero); // Not blocked if physics not ready
        }

        // Check from weapon center to bullet spawn position plus a small buffer
        float checkDistance = BulletSpawnOffset + 5.0f;

        var query = PhysicsRayQueryParameters2D.Create(
            GlobalPosition,
            GlobalPosition + direction * checkDistance,
            4 // Collision mask for obstacles (layer 3 = value 4)
        );

        var result = spaceState.IntersectRay(query);
        if (result.Count > 0)
        {
            Vector2 hitPosition = (Vector2)result["position"];
            Vector2 hitNormal = (Vector2)result["normal"];
            GD.Print($"[BaseWeapon] Wall detected at distance {GlobalPosition.DistanceTo(hitPosition):F1} - bullet will spawn at weapon position for penetration");

            return (true, hitPosition, hitNormal);
        }

        return (false, Vector2.Zero, Vector2.Zero);
    }

    /// <summary>
    /// Checks if the bullet spawn path is clear (no wall between weapon and spawn point).
    /// This prevents shooting through walls when standing flush against cover.
    /// If blocked, spawns wall hit effects and plays impact sound for feedback.
    /// </summary>
    /// <param name="direction">Direction to check.</param>
    /// <returns>True if the path is clear, false if a wall blocks it.</returns>
    protected virtual bool IsBulletSpawnClear(Vector2 direction)
    {
        var (isBlocked, hitPosition, hitNormal) = CheckBulletSpawnPath(direction);

        if (isBlocked)
        {
            // Play wall hit sound for audio feedback
            PlayBulletWallHitSound(hitPosition);

            // Spawn dust effect at impact point
            SpawnWallHitEffect(hitPosition, hitNormal);

            return false;
        }

        return true;
    }

    /// <summary>
    /// Plays the bullet wall hit sound at the specified position.
    /// </summary>
    /// <param name="position">Position to play the sound at.</param>
    private void PlayBulletWallHitSound(Vector2 position)
    {
        var audioManager = GetNodeOrNull("/root/AudioManager");
        if (audioManager != null && audioManager.HasMethod("play_bullet_wall_hit"))
        {
            audioManager.Call("play_bullet_wall_hit", position);
        }
    }

    /// <summary>
    /// Spawns dust/debris particles at wall hit position.
    /// </summary>
    /// <param name="position">Position of the impact.</param>
    /// <param name="normal">Surface normal at the impact point.</param>
    private void SpawnWallHitEffect(Vector2 position, Vector2 normal)
    {
        var impactManager = GetNodeOrNull("/root/ImpactEffectsManager");
        if (impactManager != null && impactManager.HasMethod("spawn_dust_effect"))
        {
            impactManager.Call("spawn_dust_effect", position, normal, Variant.CreateFrom((Resource?)null));
        }
    }

    /// <summary>
    /// Spawns a bullet traveling in the specified direction.
    /// </summary>
    /// <param name="direction">Direction for the bullet to travel.</param>
    protected virtual void SpawnBullet(Vector2 direction)
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
            // Spawn bullet at weapon position (not offset) so it can interact with the wall
            // and trigger penetration instead of being blocked entirely
            // Use a small offset to ensure the bullet starts moving into the wall
            spawnPosition = GlobalPosition + direction * 2.0f;
            GD.Print($"[BaseWeapon] Point-blank shot: spawning bullet at weapon position for penetration");
        }
        else
        {
            // Normal case: spawn at offset position
            spawnPosition = GlobalPosition + direction * BulletSpawnOffset;
        }

        var bullet = BulletScene.Instantiate<Node2D>();
        bullet.GlobalPosition = spawnPosition;

        // Set bullet properties BEFORE AddChild() so _ready() sees correct values.
        // Issue #781: Node.Set() silently fails for non-@export GDScript properties.
        // C# bullets support direct property access; GDScript bullets use Call() setter methods.
        if (bullet is CSharpBullet csBulletDirect)
        {
            // C# bullet: direct property assignment
            csBulletDirect.Direction = direction;
            if (WeaponData != null)
            {
                csBulletDirect.Speed = WeaponData.BulletSpeed;
                csBulletDirect.Damage = WeaponData.Damage + DamageBonus;
                // Pass caliber data so Bullet.cs reads correct ricochet parameters (Issue #915)
                csBulletDirect.CaliberData = WeaponData.Caliber;
            }
            var owner = GetParent();
            if (owner != null)
            {
                csBulletDirect.ShooterId = owner.GetInstanceId();
            }
            csBulletDirect.ShooterPosition = GlobalPosition;
        }
        else if (bullet is GodotTopDownTemplate.Projectiles.ShotgunPellet pelletDirect)
        {
            // ShotgunPellet (C#): direct property assignment
            pelletDirect.Direction = direction;
            if (WeaponData != null)
            {
                pelletDirect.Speed = WeaponData.BulletSpeed;
                pelletDirect.Damage = WeaponData.Damage + DamageBonus;
            }
            var owner = GetParent();
            if (owner != null)
            {
                pelletDirect.ShooterId = owner.GetInstanceId();
            }
            // Note: ShotgunPellet does not have ShooterPosition property
        }
        else
        {
            // GDScript bullet: use Call() setter methods (Issue #781).
            // These methods exist in bullet.gd and work before AddChild().
            bullet.Call("set_direction", direction);
            if (WeaponData != null)
            {
                bullet.Call("set_speed", WeaponData.BulletSpeed);
                bullet.Call("set_damage", WeaponData.Damage + DamageBonus);
            }
            var owner = GetParent();
            if (owner != null)
            {
                bullet.Call("set_shooter_id", (long)owner.GetInstanceId());
            }
            bullet.Call("set_shooter_position", GlobalPosition);
        }

        // Set breaker bullet flag if breaker bullets active item is selected (Issue #678)
        // Must be set BEFORE AddChild() so _ready() can load the shrapnel scene.
        if (IsBreakerBulletActive)
        {
            if (bullet is CSharpBullet csBulletBreaker)
            {
                csBulletBreaker.IsBreakerBullet = true;
            }
            else if (bullet is GodotTopDownTemplate.Projectiles.ShotgunPellet pelletBreaker)
            {
                pelletBreaker.IsBreakerBullet = true;
            }
            else
            {
                // GDScript bullet — use setter method (Issue #781)
                bullet.Call("set_is_breaker_bullet", true);
            }
        }

        // Set drilling bullet flag if drilling bullets are active for this magazine (Issue #751)
        // Decrements the counter; when it reaches 0, drilling effect ends naturally.
        if (DrillingBulletsRemaining > 0)
        {
            DrillingBulletsRemaining--;
            if (bullet is CSharpBullet csBulletDrilling)
            {
                csBulletDrilling.IsDrillingBullet = true;
            }
            else
            {
                // GDScript bullet — use setter method (Issue #781)
                bullet.Call("set_is_drilling_bullet", true);
            }
        }

        // Set enemy penetration flag if weapon penetrates enemies (Issue #829)
        // This is used by the RSh-12 revolver - bullets pass through enemies
        if (WeaponData != null && WeaponData.PenetratesEnemies)
        {
            if (bullet is CSharpBullet csBulletPenetrate)
            {
                csBulletPenetrate.PenetratesEnemies = true;
            }
            else
            {
                // GDScript bullet — use setter method (Issue #781)
                bullet.Call("set_penetrates_enemies", true);
            }
        }

        GetTree().CurrentScene.AddChild(bullet);

        // Enable homing on the bullet if the player's homing effect is active (Issue #677, #704)
        // When firing during activation, use aim-line targeting (nearest to crosshair)
        var weaponOwner = GetParent();
        if (weaponOwner is Player player && player.IsHomingActive())
        {
            Vector2 aimDir = (GetGlobalMousePosition() - player.GlobalPosition).Normalized();
            if (bullet is CSharpBullet csBullet)
            {
                csBullet.EnableHomingWithAimLine(player.GlobalPosition, aimDir);
            }
            else if (bullet.HasMethod("enable_homing_with_aim_line"))
            {
                bullet.Call("enable_homing_with_aim_line", player.GlobalPosition, aimDir);
            }
            else if (bullet.HasMethod("enable_homing"))
            {
                bullet.Call("enable_homing");
            }
        }

        // Spawn muzzle flash effect at the bullet spawn position
        SpawnMuzzleFlash(spawnPosition, direction, WeaponData?.Caliber);

        // Spawn casing if casing scene is set
        SpawnCasing(direction, WeaponData?.Caliber);
    }

    /// <summary>
    /// Spawns a muzzle flash effect at the specified position.
    /// </summary>
    /// <param name="position">Position to spawn the muzzle flash.</param>
    /// <param name="direction">Direction the weapon is firing.</param>
    /// <param name="caliber">Caliber data for effect scaling (smaller calibers = smaller flash).</param>
    protected virtual void SpawnMuzzleFlash(Vector2 position, Vector2 direction, Resource? caliber)
    {
        var impactManager = GetNodeOrNull("/root/ImpactEffectsManager");
        if (impactManager != null && impactManager.HasMethod("spawn_muzzle_flash"))
        {
            // Pass caliber data for effect scaling (9x19mm = 0.5x, 5.45x39mm = 1.0x)
            impactManager.Call("spawn_muzzle_flash", position, direction, caliber);
        }
    }

    /// <summary>
    /// Spawns a bullet casing that gets ejected from the weapon.
    /// </summary>
    /// <param name="direction">Direction the bullet was fired (used to determine casing ejection direction).</param>
    /// <param name="caliber">Caliber data for the casing appearance.</param>
    protected virtual void SpawnCasing(Vector2 direction, Resource? caliber)
    {
        if (CasingScene == null)
        {
            return;
        }

        // Diagnostic logging for Issue #765 (verify caliber data is correct)
        // Issue #969: These prints fire on EVERY shot. Disabled by default to prevent
        // console flooding (which causes measurable FPS drops at high fire rates).
        // Re-enable DebugCasing = true in BaseWeapon if you need to diagnose casing issues.
        const bool DebugCasing = false;
        if (DebugCasing)
        {
            if (caliber != null)
            {
                var caliberName = caliber.Get("caliber_name");
                GD.Print($"[BaseWeapon] Spawning casing for {Name} with caliber: {caliberName}");
            }
            else
            {
                GD.PrintErr($"[BaseWeapon] WARNING: Spawning casing for {Name} with NULL caliber!");
            }
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

        // Eject to the right with some randomness
        float randomAngle = (float)GD.RandRange(-0.3f, 0.3f); // ±0.3 radians (~±17 degrees)
        Vector2 ejectionDirection = weaponRight.Rotated(randomAngle);

        // Add some upward component for realistic ejection
        ejectionDirection = ejectionDirection.Rotated((float)GD.RandRange(-0.1f, 0.1f));

        // Set initial velocity for the casing (increased for faster ejection animation)
        float ejectionSpeed = (float)GD.RandRange(120.0f, 180.0f); // Random speed between 120-180 pixels/sec (reduced 2.5x for Issue #424)
        casing.LinearVelocity = ejectionDirection * ejectionSpeed;

        // Add some initial spin for realism
        casing.AngularVelocity = (float)GD.RandRange(-15.0f, 15.0f);

        // Set caliber data on the casing for appearance
        if (caliber != null)
        {
            casing.Set("caliber_data", caliber);
        }

        GetTree().CurrentScene.AddChild(casing);
    }

    /// <summary>
    /// Starts the reload process.
    /// </summary>
    public virtual void StartReload()
    {
        if (IsReloading || WeaponData == null || !MagazineInventory.HasSpareAmmo)
        {
            return;
        }

        if (CurrentAmmo >= WeaponData.MagazineSize)
        {
            return;
        }

        IsReloading = true;
        _reloadTimer = WeaponData.ReloadTime;
        EmitSignal(SignalName.ReloadStarted);
    }

    /// <summary>
    /// Finishes the reload process by swapping to the fullest spare magazine.
    /// The current magazine is stored as a spare with its remaining ammo preserved.
    /// </summary>
    protected virtual void FinishReload()
    {
        if (WeaponData == null)
        {
            return;
        }

        IsReloading = false;

        // Swap to the magazine with the most ammo
        MagazineData? oldMag = MagazineInventory.SwapToFullestMagazine();

        if (oldMag != null)
        {
            GD.Print($"[BaseWeapon] Reloaded: swapped magazine with {oldMag.CurrentAmmo} rounds for one with {CurrentAmmo} rounds");
        }

        EmitSignal(SignalName.ReloadFinished);
        EmitSignal(SignalName.AmmoChanged, CurrentAmmo, ReserveAmmo);
        EmitMagazinesChanged();
    }

    /// <summary>
    /// Performs an instant reload without any timer delay.
    /// Used for sequence-based reload systems (e.g., R-F-R player reload).
    /// Accounts for bullet in chamber mechanic.
    /// Swaps to the magazine with the most ammo (magazines are NOT combined).
    /// </summary>
    public virtual void InstantReload()
    {
        if (WeaponData == null || !MagazineInventory.HasSpareAmmo)
        {
            return;
        }

        // Allow reload even if current magazine is full, as long as there are spare magazines
        // This enables tactical magazine swapping

        // Cancel any ongoing timed reload
        if (IsReloading)
        {
            IsReloading = false;
            _reloadTimer = 0;
        }

        // Reset reload sequence state
        IsInReloadSequence = false;

        // Swap to the magazine with the most ammo
        // The current magazine is stored as a spare with its remaining ammo preserved
        MagazineData? oldMag = MagazineInventory.SwapToFullestMagazine();

        if (oldMag != null)
        {
            GD.Print($"[BaseWeapon] Instant reload: swapped magazine with {oldMag.CurrentAmmo} rounds for one with {CurrentAmmo} rounds");
        }

        // Handle bullet chambering from new magazine:
        // Only subtract a bullet if the chamber bullet was fired during reload (had ammo, shot during R->F)
        // Empty magazine reloads don't subtract a bullet (no chambering penalty)
        if (ChamberBulletFired && CurrentAmmo > 0)
        {
            MagazineInventory.ConsumeAmmo();
        }

        // Reset chamber state
        HasBulletInChamber = false;
        ChamberBulletFired = false;

        EmitSignal(SignalName.ReloadFinished);
        EmitSignal(SignalName.AmmoChanged, CurrentAmmo, ReserveAmmo);
        EmitMagazinesChanged();
    }

    /// <summary>
    /// Starts the reload sequence (R->F pressed).
    /// Sets up the chamber bullet if there was ammo in the magazine.
    /// </summary>
    /// <param name="hadAmmoInMagazine">Whether there was ammo in the magazine when reload started.</param>
    public virtual void StartReloadSequence(bool hadAmmoInMagazine)
    {
        IsInReloadSequence = true;
        HasBulletInChamber = hadAmmoInMagazine;
        ChamberBulletFired = false;
    }

    /// <summary>
    /// Cancels the reload sequence (e.g., when shooting resets the combo after only R was pressed).
    /// </summary>
    public virtual void CancelReloadSequence()
    {
        IsInReloadSequence = false;
        HasBulletInChamber = false;
        ChamberBulletFired = false;
    }

    /// <summary>
    /// Fires the bullet in the chamber during reload sequence.
    /// Returns true if the chamber bullet was fired successfully.
    /// </summary>
    /// <param name="direction">Direction to fire.</param>
    /// <returns>True if the chamber bullet was fired.</returns>
    public virtual bool FireChamberBullet(Vector2 direction)
    {
        if (!IsInReloadSequence || !HasBulletInChamber || ChamberBulletFired)
        {
            return false;
        }

        if (BulletScene == null || _fireTimer > 0)
        {
            return false;
        }

        // Fire the chamber bullet
        if (WeaponData != null)
        {
            float effectiveFireRate = WeaponData.FireRate + FireRateBonus;
            _fireTimer = 1.0f / Mathf.Max(effectiveFireRate, 0.1f);
        }
        else
        {
            _fireTimer = 0.1f;
        }
        ChamberBulletFired = true;
        HasBulletInChamber = false;

        SpawnBullet(direction);

        EmitSignal(SignalName.Fired);
        // Note: We don't change CurrentAmmo here because the bullet was already
        // in the chamber, not in the magazine

        return true;
    }

    /// <summary>
    /// Checks if the weapon can fire a chamber bullet during reload sequence.
    /// </summary>
    public bool CanFireChamberBullet => IsInReloadSequence && HasBulletInChamber && !ChamberBulletFired && _fireTimer <= 0;

    /// <summary>
    /// Adds a new full magazine to the spare magazines.
    /// </summary>
    public virtual void AddMagazine()
    {
        if (WeaponData == null)
        {
            return;
        }

        // Create a new full magazine and add it to the inventory
        // Note: We access the internal list through a method to add magazines
        AddMagazineWithAmmo(WeaponData.MagazineSize);
    }

    /// <summary>
    /// Adds a new magazine with specified ammo count to the spare magazines.
    /// </summary>
    /// <param name="ammoCount">Amount of ammo in the new magazine.</param>
    public virtual void AddMagazineWithAmmo(int ammoCount)
    {
        if (WeaponData == null)
        {
            return;
        }

        MagazineInventory.AddSpareMagazine(ammoCount, WeaponData.MagazineSize);

        EmitSignal(SignalName.AmmoChanged, CurrentAmmo, ReserveAmmo);
        EmitMagazinesChanged();
    }

    /// <summary>
    /// Adds ammunition to the reserve (legacy method for backward compatibility).
    /// This now adds ammo to the first non-full spare magazine, or creates a new one.
    /// </summary>
    /// <param name="amount">Amount of ammo to add.</param>
    public virtual void AddAmmo(int amount)
    {
        if (WeaponData == null)
        {
            return;
        }

        // For backward compatibility, add ammo to existing magazines or create new ones
        int remaining = amount;
        int magSize = WeaponData.MagazineSize;

        // First, try to fill existing non-full magazines
        foreach (var mag in MagazineInventory.AllMagazines)
        {
            if (remaining <= 0) break;

            int canAdd = mag.MaxCapacity - mag.CurrentAmmo;
            int toAdd = Math.Min(canAdd, remaining);
            mag.CurrentAmmo += toAdd;
            remaining -= toAdd;
        }

        // If there's still ammo left, create new magazines
        while (remaining > 0)
        {
            int ammoForNewMag = Math.Min(remaining, magSize);
            AddMagazineWithAmmo(ammoForNewMag);
            remaining -= ammoForNewMag;
        }

        EmitSignal(SignalName.AmmoChanged, CurrentAmmo, ReserveAmmo);
        EmitMagazinesChanged();
    }

    /// <summary>
    /// Reinitializes the magazine inventory with a new starting magazine count.
    /// This method allows level-specific ammunition configuration.
    /// </summary>
    /// <param name="magazineCount">Number of magazines to initialize with.</param>
    /// <param name="fillAllMagazines">If true, all magazines start full. Otherwise, only current is full.</param>
    public virtual void ReinitializeMagazines(int magazineCount, bool fillAllMagazines = true)
    {
        if (WeaponData == null)
        {
            GD.PrintErr("[BaseWeapon] Cannot reinitialize magazines: WeaponData is null");
            return;
        }

        int magazineSize = WeaponData.MagazineSize;

        // Respect Extended Magazine passive item (Issue #1065): scale magazine size.
        var activeItemManager = GetNodeOrNull("/root/ActiveItemManager");
        if (activeItemManager != null && activeItemManager.HasMethod("has_extended_magazine")
            && activeItemManager.Call("has_extended_magazine").AsBool())
        {
            float magSizeMultiplier = activeItemManager.Call("get_magazine_size_multiplier").AsSingle();
            magazineSize = Mathf.Max(1, Mathf.RoundToInt(magazineSize * magSizeMultiplier));
            GD.Print($"[BaseWeapon] ReinitializeMagazines: Extended Magazine applied, magazineSize {WeaponData.MagazineSize}->{magazineSize}");
        }

        MagazineInventory.Initialize(magazineCount, magazineSize, fillAllMagazines);
        EmitSignal(SignalName.AmmoChanged, CurrentAmmo, ReserveAmmo);
        EmitMagazinesChanged();

        GD.Print($"[BaseWeapon] Magazines reinitialized: {magazineCount} magazines of size {magazineSize}, fillAll={fillAllMagazines}");
    }

    /// <summary>
    /// Reinitializes the magazine inventory with a custom magazine size.
    /// Used by the auto-reload passive item (Issue #1067) to reduce magazine capacity.
    /// </summary>
    /// <param name="magazineCount">Number of magazines to initialize with.</param>
    /// <param name="magazineSize">Custom magazine capacity (overrides WeaponData.MagazineSize).</param>
    /// <param name="fillAllMagazines">If true, all magazines start full. Otherwise, only current is full.</param>
    public virtual void ReinitializeMagazines(int magazineCount, int magazineSize, bool fillAllMagazines = true)
    {
        if (WeaponData == null)
        {
            GD.PrintErr("[BaseWeapon] Cannot reinitialize magazines: WeaponData is null");
            return;
        }

        MagazineInventory.Initialize(magazineCount, magazineSize, fillAllMagazines);
        EmitSignal(SignalName.AmmoChanged, CurrentAmmo, ReserveAmmo);
        EmitMagazinesChanged();

        GD.Print($"[BaseWeapon] Magazines reinitialized: {magazineCount} magazines of size {magazineSize}, fillAll={fillAllMagazines}");
    }

    /// <summary>
    /// Consumes a specified number of rounds from the spare (reserve) magazines.
    /// Used by the auto-reload passive item to deduct bullets transferred to the current magazine.
    /// Removes bullets starting from the magazines with the least ammo.
    /// </summary>
    /// <param name="amount">Number of rounds to consume from reserve.</param>
    public virtual void ConsumeReserveAmmo(int amount)
    {
        int remaining = amount;

        // Consume from spare magazines starting from the least-loaded ones
        // (prefer to empty partial magazines first to reduce clutter)
        var sparesSortedAscending = MagazineInventory.SpareMagazines
            .OrderBy(m => m.CurrentAmmo)
            .ToList();

        foreach (var mag in sparesSortedAscending)
        {
            if (remaining <= 0) break;

            int toConsume = Math.Min(mag.CurrentAmmo, remaining);
            mag.CurrentAmmo -= toConsume;
            remaining -= toConsume;
        }

        EmitSignal(SignalName.AmmoChanged, CurrentAmmo, ReserveAmmo);
        EmitMagazinesChanged();
    }

    // =========================================================================
    // Caliber Data Accessors (Issue #935)
    // These C# methods expose caliber properties to GDScript callers.
    //
    // Root cause of Issue #935 (v3 analysis):
    // All previous approaches (duck-typing .get(), "as CaliberData" cast, and
    // reading WeaponData.Caliber.Get() from C#) returned 90.0 (the GDScript
    // script default) instead of the serialized .tres value (70.0).
    //
    // This happens because in Godot 4.3, calling .Get() from C# on a GDScript-
    // backed Resource returns the GDScript script-level default, not the
    // deserialized .tres property value.
    //
    // Fix: Store caliber ricochet parameters directly in WeaponData.cs as C#
    // [Export] properties (CaliberCanRicochet, CaliberMaxRicochetAngle,
    // CaliberMaxRicochets). Being native C# properties on a C# resource, they
    // are always read correctly from .tres files with no GDScript interop.
    // The corresponding weapon .tres files are updated to set the correct values.
    // =========================================================================

    /// <summary>
    /// Returns the maximum ricochet angle in degrees for this weapon's caliber.
    /// Returns 90.0 (default) if no weapon data is set.
    /// Called by trajectory_glasses_effect.gd to correctly color ricochet segments.
    /// </summary>
    public float GetCaliberMaxRicochetAngle()
    {
        if (WeaponData == null)
            return 90.0f;
        return WeaponData.CaliberMaxRicochetAngle;
    }

    /// <summary>
    /// Returns the maximum number of ricochets allowed for this weapon's caliber.
    /// Returns -1 (unlimited) if no weapon data is set.
    /// Called by trajectory_glasses_effect.gd to determine bounce limit.
    /// </summary>
    public int GetCaliberMaxRicochets()
    {
        if (WeaponData == null)
            return -1;
        return WeaponData.CaliberMaxRicochets;
    }

    /// <summary>
    /// Returns whether this weapon's caliber can ricochet.
    /// Returns true (default) if no weapon data is set.
    /// Called by trajectory_glasses_effect.gd to check ricochet capability.
    /// </summary>
    public bool GetCaliberCanRicochet()
    {
        if (WeaponData == null)
            return true;
        return WeaponData.CaliberCanRicochet;
    }
}
