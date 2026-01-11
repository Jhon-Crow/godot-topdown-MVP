using Godot;
using GodotTopDownTemplate.Data;
using GodotTopDownTemplate.Interfaces;

namespace GodotTopDownTemplate.Projectiles;

/// <summary>
/// Bullet projectile that travels in a direction and handles collisions.
/// The bullet moves at a constant speed in its set direction.
/// It destroys itself when hitting walls or targets, and triggers
/// target reactions on hit.
/// </summary>
public partial class Bullet : Area2D
{
    /// <summary>
    /// Speed of the bullet in pixels per second.
    /// </summary>
    [Export]
    public float Speed { get; set; } = 600.0f;

    /// <summary>
    /// Maximum lifetime in seconds before auto-destruction.
    /// </summary>
    [Export]
    public float Lifetime { get; set; } = 3.0f;

    /// <summary>
    /// Damage dealt on hit.
    /// </summary>
    [Export]
    public float Damage { get; set; } = 1.0f;

    /// <summary>
    /// Bullet configuration data (optional, overrides individual properties).
    /// </summary>
    [Export]
    public BulletData? BulletData { get; set; }

    /// <summary>
    /// Direction the bullet travels (set by the shooter).
    /// </summary>
    public Vector2 Direction { get; set; } = Vector2.Right;

    /// <summary>
    /// Timer tracking remaining lifetime.
    /// </summary>
    private float _timeAlive;

    /// <summary>
    /// Signal emitted when the bullet hits something.
    /// </summary>
    [Signal]
    public delegate void HitEventHandler(Node2D target);

    public override void _Ready()
    {
        // Apply bullet data if available
        if (BulletData != null)
        {
            Speed = BulletData.Speed;
            Lifetime = BulletData.Lifetime;
            Damage = BulletData.Damage;
        }

        // Connect to collision signals
        BodyEntered += OnBodyEntered;
        AreaEntered += OnAreaEntered;
    }

    public override void _PhysicsProcess(double delta)
    {
        // Move in the set direction
        Position += Direction * Speed * (float)delta;

        // Track lifetime and auto-destroy if exceeded
        _timeAlive += (float)delta;
        if (_timeAlive >= Lifetime)
        {
            QueueFree();
        }
    }

    /// <summary>
    /// Sets the direction for the bullet.
    /// Called by the shooter to set the travel direction.
    /// </summary>
    /// <param name="direction">Direction vector (will be normalized).</param>
    public void SetDirection(Vector2 direction)
    {
        Direction = direction.Normalized();
    }

    /// <summary>
    /// Called when the bullet hits a static body (wall or obstacle).
    /// </summary>
    private void OnBodyEntered(Node2D body)
    {
        EmitSignal(SignalName.Hit, body);
        QueueFree();
    }

    /// <summary>
    /// Called when the bullet hits another area (like a target or enemy).
    /// </summary>
    private void OnAreaEntered(Area2D area)
    {
        GD.Print($"[Bullet]: Hit {area.Name} (damage: {Damage})");

        // Check if the target implements IDamageable
        if (area is IDamageable damageable)
        {
            GD.Print($"[Bullet]: Target {area.Name} is IDamageable, applying {Damage} damage");
            damageable.TakeDamage(Damage);
        }
        // Fallback: Check for on_hit method (compatibility with GDScript targets)
        else if (area.HasMethod("on_hit"))
        {
            GD.Print($"[Bullet]: Target {area.Name} has on_hit method, calling it");
            area.Call("on_hit");
        }
        // Also check for OnHit method (C# convention)
        else if (area.HasMethod("OnHit"))
        {
            GD.Print($"[Bullet]: Target {area.Name} has OnHit method, calling it");
            area.Call("OnHit");
        }

        EmitSignal(SignalName.Hit, area);
        QueueFree();
    }
}
