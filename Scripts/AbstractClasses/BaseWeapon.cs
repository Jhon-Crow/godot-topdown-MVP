using Godot;
using GodotTopDownTemplate.Data;

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
    /// Current ammunition in the magazine.
    /// </summary>
    public int CurrentAmmo { get; protected set; }

    /// <summary>
    /// Total reserve ammunition.
    /// </summary>
    public int ReserveAmmo { get; protected set; }

    /// <summary>
    /// Whether the weapon can currently fire.
    /// </summary>
    public bool CanFire => CurrentAmmo > 0 && !IsReloading && _fireTimer <= 0;

    /// <summary>
    /// Whether the weapon is currently reloading.
    /// </summary>
    public bool IsReloading { get; protected set; }

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

    public override void _Ready()
    {
        if (WeaponData != null)
        {
            CurrentAmmo = WeaponData.MagazineSize;
            ReserveAmmo = WeaponData.MaxReserveAmmo;
        }
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

        CurrentAmmo--;
        _fireTimer = 1.0f / WeaponData.FireRate;

        SpawnBullet(direction);

        EmitSignal(SignalName.Fired);
        EmitSignal(SignalName.AmmoChanged, CurrentAmmo, ReserveAmmo);

        return true;
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

        var bullet = BulletScene.Instantiate<Node2D>();
        bullet.GlobalPosition = GlobalPosition + direction * BulletSpawnOffset;

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

        GetTree().CurrentScene.AddChild(bullet);
    }

    /// <summary>
    /// Starts the reload process.
    /// </summary>
    public virtual void StartReload()
    {
        if (IsReloading || WeaponData == null || ReserveAmmo <= 0)
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
    /// Finishes the reload process, transferring ammo from reserve to magazine.
    /// </summary>
    protected virtual void FinishReload()
    {
        if (WeaponData == null)
        {
            return;
        }

        IsReloading = false;
        int ammoNeeded = WeaponData.MagazineSize - CurrentAmmo;
        int ammoToLoad = Math.Min(ammoNeeded, ReserveAmmo);

        CurrentAmmo += ammoToLoad;
        ReserveAmmo -= ammoToLoad;

        EmitSignal(SignalName.ReloadFinished);
        EmitSignal(SignalName.AmmoChanged, CurrentAmmo, ReserveAmmo);
    }

    /// <summary>
    /// Adds ammunition to the reserve.
    /// </summary>
    /// <param name="amount">Amount of ammo to add.</param>
    public virtual void AddAmmo(int amount)
    {
        if (WeaponData == null)
        {
            return;
        }

        ReserveAmmo = Math.Min(ReserveAmmo + amount, WeaponData.MaxReserveAmmo);
        EmitSignal(SignalName.AmmoChanged, CurrentAmmo, ReserveAmmo);
    }
}
