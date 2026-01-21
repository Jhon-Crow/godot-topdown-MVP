using Godot;
using GodotTopDownTemplate.Data;
using System.Linq;

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
    /// </summary>
    public int CurrentAmmo
    {
        get => MagazineInventory.CurrentMagazine?.CurrentAmmo ?? 0;
        protected set
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
    /// </summary>
    public int ReserveAmmo
    {
        get => MagazineInventory.TotalSpareAmmo;
        protected set
        {
            // This setter is kept for backward compatibility but does nothing
            // The reserve ammo is now calculated from individual magazines
        }
    }

    /// <summary>
    /// Whether the weapon can currently fire.
    /// </summary>
    public bool CanFire => CurrentAmmo > 0 && !IsReloading && _fireTimer <= 0;

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


    private float _fireTimer;
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
        if (WeaponData != null)
        {
            // Initialize magazine inventory with the starting magazines
            MagazineInventory.Initialize(StartingMagazineCount, WeaponData.MagazineSize, fillAllMagazines: true);

            // Emit initial magazine state
            EmitMagazinesChanged();
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
        _fireTimer = 1.0f / WeaponData.FireRate;

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

        // Set bullet properties if it has a Direction property
        if (bullet.HasMethod("SetDirection"))
        {
            bullet.Call("SetDirection", direction);
        }
        else
        {
            // Try to set direction via property
            bullet.Set("Direction", direction);
        }

        // Set bullet speed from weapon data
        if (WeaponData != null)
        {
            bullet.Set("Speed", WeaponData.BulletSpeed);
        }

        // Set shooter ID to prevent self-damage
        // The shooter is the owner of the weapon (parent node)
        var owner = GetParent();
        if (owner != null)
        {
            bullet.Set("ShooterId", owner.GetInstanceId());
        }

        // Set shooter position for distance-based penetration calculations
        bullet.Set("ShooterPosition", GlobalPosition);

        GetTree().CurrentScene.AddChild(bullet);
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
        _fireTimer = WeaponData != null ? 1.0f / WeaponData.FireRate : 0.1f;
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
}
