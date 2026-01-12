using Godot;
using GodotTopDownTemplate.Characters;
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
    /// Instance ID of the node that shot this bullet.
    /// Used to prevent self-damage (e.g., player or enemies not damaging themselves).
    /// </summary>
    public ulong ShooterId { get; set; } = 0;

    /// <summary>
    /// Timer tracking remaining lifetime.
    /// </summary>
    private float _timeAlive;

    /// <summary>
    /// Reference to the shooter node (cached for player detection).
    /// </summary>
    private Node? _shooterNode;

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
        // Play bullet wall impact sound
        PlayBulletWallHitSound();
        EmitSignal(SignalName.Hit, body);
        QueueFree();
    }

    /// <summary>
    /// Plays the bullet wall impact sound.
    /// </summary>
    private void PlayBulletWallHitSound()
    {
        var audioManager = GetNodeOrNull("/root/AudioManager");
        if (audioManager != null && audioManager.HasMethod("play_bullet_wall_hit"))
        {
            audioManager.Call("play_bullet_wall_hit", GlobalPosition);
        }
    }

    /// <summary>
    /// Called when the bullet hits another area (like a target or enemy).
    /// </summary>
    private void OnAreaEntered(Area2D area)
    {
        GD.Print($"[Bullet]: Hit {area.Name} (damage: {Damage})");

        // Check if this is a HitArea - if so, check against parent's instance ID
        // This prevents the shooter from damaging themselves
        var parent = area.GetParent();
        if (parent != null && ShooterId == parent.GetInstanceId())
        {
            GD.Print($"[Bullet]: Ignoring self-hit on {parent.Name}");
            return; // Don't hit the shooter
        }

        // Track if this is a valid hit on an enemy target
        bool hitEnemy = false;

        // Check if the target implements IDamageable
        if (area is IDamageable damageable)
        {
            GD.Print($"[Bullet]: Target {area.Name} is IDamageable, applying {Damage} damage");
            damageable.TakeDamage(Damage);
            hitEnemy = true;
        }
        // Fallback: Check for on_hit method (compatibility with GDScript targets)
        else if (area.HasMethod("on_hit"))
        {
            GD.Print($"[Bullet]: Target {area.Name} has on_hit method, calling it");
            area.Call("on_hit");
            hitEnemy = true;
        }
        // Also check for OnHit method (C# convention)
        else if (area.HasMethod("OnHit"))
        {
            GD.Print($"[Bullet]: Target {area.Name} has OnHit method, calling it");
            area.Call("OnHit");
            hitEnemy = true;
        }

        // Trigger hit effects if this is a player bullet hitting an enemy
        if (hitEnemy && IsPlayerBullet())
        {
            TriggerPlayerHitEffects();
        }

        EmitSignal(SignalName.Hit, area);
        QueueFree();
    }

    /// <summary>
    /// Checks if this bullet was fired by the player.
    /// </summary>
    /// <returns>True if the shooter is a player.</returns>
    private bool IsPlayerBullet()
    {
        if (ShooterId == 0)
        {
            return false;
        }

        // Try to find the shooter node if not cached
        if (_shooterNode == null)
        {
            _shooterNode = GodotObject.InstanceFromId(ShooterId) as Node;
        }

        // Check if the shooter is a Player (C# type)
        if (_shooterNode is Player)
        {
            return true;
        }

        // Check for GDScript player (by script path or node name convention)
        if (_shooterNode != null)
        {
            var script = _shooterNode.GetScript();
            if (script.VariantType == Variant.Type.Object)
            {
                var scriptObj = script.AsGodotObject();
                if (scriptObj is Script gdScript && gdScript.ResourcePath.Contains("player"))
                {
                    return true;
                }
            }
        }

        return false;
    }

    /// <summary>
    /// Triggers hit effects via the HitEffectsManager autoload.
    /// Effects: time slowdown to 0.9 for 3 seconds, saturation boost for 400ms.
    /// </summary>
    private void TriggerPlayerHitEffects()
    {
        // Get the HitEffectsManager autoload singleton
        var hitEffectsManager = GetNodeOrNull("/root/HitEffectsManager");
        if (hitEffectsManager != null && hitEffectsManager.HasMethod("on_player_hit_enemy"))
        {
            GD.Print("[Bullet]: Triggering player hit effects");
            hitEffectsManager.Call("on_player_hit_enemy");
        }
    }
}
