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
///
/// Features a visual tracer trail effect for better visibility and
/// realistic appearance during fast movement.
/// </summary>
public partial class Bullet : Area2D
{
    /// <summary>
    /// Speed of the bullet in pixels per second.
    /// Default is 2500 for faster projectiles that make combat more challenging.
    /// </summary>
    [Export]
    public float Speed { get; set; } = 2500.0f;

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
    /// Maximum number of trail points to maintain.
    /// Higher values create longer trails but use more memory.
    /// </summary>
    [Export]
    public int TrailLength { get; set; } = 8;

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
    /// Reference to the trail Line2D node (if present).
    /// </summary>
    private Line2D? _trail;

    /// <summary>
    /// History of global positions for the trail effect.
    /// </summary>
    private readonly System.Collections.Generic.List<Vector2> _positionHistory = new();

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

        // Get trail reference if it exists
        _trail = GetNodeOrNull<Line2D>("Trail");
        if (_trail != null)
        {
            _trail.ClearPoints();
            // Set trail to use global coordinates (not relative to bullet)
            _trail.TopLevel = true;
        }

        // Set initial rotation based on direction
        UpdateRotation();
    }

    /// <summary>
    /// Updates the bullet rotation to match its travel direction.
    /// </summary>
    private void UpdateRotation()
    {
        Rotation = Direction.Angle();
    }

    public override void _PhysicsProcess(double delta)
    {
        // Move in the set direction
        Position += Direction * Speed * (float)delta;

        // Update trail effect
        UpdateTrail();

        // Track lifetime and auto-destroy if exceeded
        _timeAlive += (float)delta;
        if (_timeAlive >= Lifetime)
        {
            QueueFree();
        }
    }

    /// <summary>
    /// Updates the visual trail effect by maintaining position history.
    /// </summary>
    private void UpdateTrail()
    {
        if (_trail == null)
        {
            return;
        }

        // Add current position to history (at the front)
        _positionHistory.Insert(0, GlobalPosition);

        // Limit trail length
        while (_positionHistory.Count > TrailLength)
        {
            _positionHistory.RemoveAt(_positionHistory.Count - 1);
        }

        // Update Line2D points
        _trail.ClearPoints();
        foreach (var pos in _positionHistory)
        {
            _trail.AddPoint(pos);
        }
    }

    /// <summary>
    /// Sets the direction for the bullet.
    /// Called by the shooter to set the travel direction.
    /// Also updates the bullet's rotation to match the direction.
    /// </summary>
    /// <param name="direction">Direction vector (will be normalized).</param>
    public void SetDirection(Vector2 direction)
    {
        Direction = direction.Normalized();
        UpdateRotation();
    }

    /// <summary>
    /// Called when the bullet hits a static body (wall or obstacle).
    /// </summary>
    private void OnBodyEntered(Node2D body)
    {
        // Check if this is the shooter - don't collide with own body
        if (ShooterId == body.GetInstanceId())
        {
            return; // Pass through the shooter
        }

        // Check if this is a dead enemy - bullets should pass through dead entities
        // This handles the CharacterBody2D collision (separate from HitArea collision)
        if (body.HasMethod("is_alive"))
        {
            var isAlive = body.Call("is_alive").AsBool();
            if (!isAlive)
            {
                return; // Pass through dead entities
            }
        }

        // Hit a static body (wall or obstacle) or alive enemy body
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

        // Check if the parent is dead - bullets should pass through dead entities
        // This is a fallback check in case the collision shape/layer disabling
        // doesn't take effect immediately (see Godot issues #62506, #100687)
        if (parent != null && parent.HasMethod("is_alive"))
        {
            var isAlive = parent.Call("is_alive").AsBool();
            if (!isAlive)
            {
                GD.Print($"[Bullet]: Passing through dead entity {parent.Name}");
                return; // Pass through dead entities
            }
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
