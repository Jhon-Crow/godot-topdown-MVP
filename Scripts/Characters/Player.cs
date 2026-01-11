using Godot;
using GodotTopDownTemplate.AbstractClasses;

namespace GodotTopDownTemplate.Characters;

/// <summary>
/// Player character controller for top-down movement and shooting.
/// Uses physics-based movement with acceleration and friction for smooth control.
/// Supports WASD and arrow key input via configured input actions.
/// Shoots bullets towards the mouse cursor on left mouse button click.
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

    public override void _Ready()
    {
        base._Ready();

        // Preload bullet scene if not set in inspector
        if (BulletScene == null)
        {
            BulletScene = GD.Load<PackedScene>("res://scenes/projectiles/Bullet.tscn");
        }
    }

    public override void _PhysicsProcess(double delta)
    {
        Vector2 inputDirection = GetInputDirection();
        ApplyMovement(inputDirection, (float)delta);

        // Handle shooting input
        if (Input.IsActionJustPressed("shoot"))
        {
            Shoot();
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

        // Add bullet to the scene tree
        GetTree().CurrentScene.AddChild(bullet);
    }

    /// <inheritdoc/>
    public override void OnDeath()
    {
        base.OnDeath();
        // Handle player death - can be overridden or extended
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
