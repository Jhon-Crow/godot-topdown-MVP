using Godot;
using GodotTopDownTemplate.Characters;

namespace GodotTopDownTemplate.Projectiles;

/// <summary>
/// Sniper bullet for the ASVK anti-materiel rifle.
/// Extends the standard bullet with special behavior:
/// - Passes through enemies (deals damage but continues flying)
/// - Penetrates through a configurable number of walls (default: 2)
/// - Does not ricochet (too powerful)
/// - Very long lifetime due to high speed
/// - Smoky trail handled by the weapon, not the bullet
/// </summary>
public partial class SniperBullet : Area2D
{
    /// <summary>
    /// Speed of the bullet in pixels per second.
    /// Very high for sniper rounds (effectively instant).
    /// </summary>
    [Export]
    public float Speed { get; set; } = 10000.0f;

    /// <summary>
    /// Maximum lifetime in seconds before auto-destruction.
    /// </summary>
    [Export]
    public float Lifetime { get; set; } = 3.0f;

    /// <summary>
    /// Damage dealt on hit.
    /// </summary>
    [Export]
    public float Damage { get; set; } = 50.0f;

    /// <summary>
    /// Maximum number of trail points to maintain.
    /// </summary>
    [Export]
    public int TrailLength { get; set; } = 12;

    /// <summary>
    /// Maximum number of walls this bullet can penetrate through.
    /// Set to 2 for 12.7x108mm ASVK rounds.
    /// </summary>
    [Export]
    public int MaxWallPenetrations { get; set; } = 2;

    /// <summary>
    /// Direction the bullet travels (set by the shooter).
    /// </summary>
    [Export]
    public Vector2 Direction { get; set; } = Vector2.Right;

    /// <summary>
    /// Instance ID of the shooter (to prevent self-damage).
    /// </summary>
    [Export]
    public ulong ShooterId { get; set; } = 0;

    /// <summary>
    /// Shooter's position at firing time.
    /// </summary>
    [Export]
    public Vector2 ShooterPosition { get; set; } = Vector2.Zero;

    /// <summary>
    /// Number of walls penetrated so far.
    /// </summary>
    private int _wallsPenetrated = 0;

    /// <summary>
    /// Whether the bullet is currently inside a wall (penetrating).
    /// </summary>
    private bool _isPenetrating = false;

    /// <summary>
    /// The body currently being penetrated.
    /// </summary>
    private Node2D? _penetratingBody = null;

    /// <summary>
    /// Timer tracking remaining lifetime.
    /// </summary>
    private float _timeAlive;

    /// <summary>
    /// Reference to the shooter node (cached).
    /// </summary>
    private Node? _shooterNode;

    /// <summary>
    /// Reference to the trail Line2D node.
    /// </summary>
    private Line2D? _trail;

    /// <summary>
    /// Position history for trail effect.
    /// </summary>
    private readonly System.Collections.Generic.List<Vector2> _positionHistory = new();

    /// <summary>
    /// Signal emitted when the bullet hits something.
    /// </summary>
    [Signal]
    public delegate void HitEventHandler(Node2D target);

    public override void _Ready()
    {
        // Connect collision signals
        BodyEntered += OnBodyEntered;
        BodyExited += OnBodyExited;
        AreaEntered += OnAreaEntered;

        // Get trail reference
        _trail = GetNodeOrNull<Line2D>("Trail");
        if (_trail != null)
        {
            _trail.ClearPoints();
            _trail.TopLevel = true;
            _trail.Position = Vector2.Zero;
        }

        // Set initial rotation
        Rotation = Direction.Angle();
    }

    public override void _PhysicsProcess(double delta)
    {
        // Move in direction
        var movement = Direction * Speed * (float)delta;
        Position += movement;

        // Track penetration state
        if (_isPenetrating)
        {
            // Check if we've exited the wall
            if (!IsStillInsideObstacle())
            {
                ExitPenetration();
            }
        }

        // Update trail
        UpdateTrail();

        // Track lifetime
        _timeAlive += (float)delta;
        if (_timeAlive >= Lifetime)
        {
            QueueFree();
        }
    }

    /// <summary>
    /// Updates the trail effect.
    /// </summary>
    private void UpdateTrail()
    {
        if (_trail == null)
        {
            return;
        }

        _positionHistory.Insert(0, GlobalPosition);

        while (_positionHistory.Count > TrailLength)
        {
            _positionHistory.RemoveAt(_positionHistory.Count - 1);
        }

        _trail.ClearPoints();
        foreach (var pos in _positionHistory)
        {
            _trail.AddPoint(pos);
        }
    }

    /// <summary>
    /// Sets the direction for the bullet.
    /// </summary>
    public void SetDirection(Vector2 direction)
    {
        Direction = direction.Normalized();
        Rotation = Direction.Angle();
    }

    /// <summary>
    /// Called when the bullet hits a static body (wall).
    /// Sniper bullet penetrates through walls up to MaxWallPenetrations.
    /// </summary>
    private void OnBodyEntered(Node2D body)
    {
        // Skip shooter
        if (ShooterId == body.GetInstanceId())
        {
            return;
        }

        // Skip dead entities
        if (body.HasMethod("is_alive"))
        {
            var isAlive = body.Call("is_alive").AsBool();
            if (!isAlive)
            {
                return;
            }
        }

        // Skip if already penetrating the same body
        if (_isPenetrating && _penetratingBody == body)
        {
            return;
        }

        // Wall/obstacle hit
        if (body is StaticBody2D || body is TileMap)
        {
            // Spawn dust effect
            SpawnWallHitEffect(body);

            // Check if we can still penetrate
            if (_wallsPenetrated < MaxWallPenetrations)
            {
                // Start penetrating this wall
                _isPenetrating = true;
                _penetratingBody = body;
                GlobalPosition += Direction * 5.0f;
                GD.Print($"[SniperBullet] Penetrating wall {_wallsPenetrated + 1}/{MaxWallPenetrations}");
                return;
            }

            // Exceeded max wall penetrations - stop
            GD.Print($"[SniperBullet] Max wall penetrations ({MaxWallPenetrations}) reached, destroying bullet");
            PlayBulletWallHitSound();
            EmitSignal(SignalName.Hit, body);
            QueueFree();
            return;
        }

        // Enemy body hit - pass through (damage handled by area collision)
        // CharacterBody2D collision is just the physics body, damage goes through HitArea
    }

    /// <summary>
    /// Called when the bullet exits a wall body.
    /// </summary>
    private void OnBodyExited(Node2D body)
    {
        if (!_isPenetrating || _penetratingBody != body)
        {
            return;
        }

        ExitPenetration();
    }

    /// <summary>
    /// Called when the bullet hits an area (enemy HitArea).
    /// Sniper bullet passes through enemies - deals damage but continues flying.
    /// </summary>
    private void OnAreaEntered(Area2D area)
    {
        GD.Print($"[SniperBullet]: Hit area {area.Name} (damage: {Damage})");

        // Check self-hit
        var parent = area.GetParent();
        if (parent != null && ShooterId == parent.GetInstanceId())
        {
            GD.Print($"[SniperBullet]: Ignoring self-hit on {parent.Name}");
            return;
        }

        // Check dead entities
        if (parent != null && parent.HasMethod("is_alive"))
        {
            var isAlive = parent.Call("is_alive").AsBool();
            if (!isAlive)
            {
                GD.Print($"[SniperBullet]: Passing through dead entity {parent.Name}");
                return;
            }
        }

        bool hitEnemy = false;

        // Deal damage to target
        if (parent != null && parent.HasMethod("take_damage"))
        {
            GD.Print($"[SniperBullet]: Penetrating through {parent.Name}, applying {Damage} damage");
            parent.Call("take_damage", Damage);
            hitEnemy = true;
        }
        else if (area.HasMethod("on_hit"))
        {
            area.Call("on_hit");
            hitEnemy = true;
        }
        else if (area.HasMethod("OnHit"))
        {
            area.Call("OnHit");
            hitEnemy = true;
        }

        // Trigger player hit effects
        if (hitEnemy && IsPlayerBullet())
        {
            TriggerPlayerHitEffects();
        }

        // IMPORTANT: Do NOT destroy the bullet on enemy hit
        // The sniper bullet passes through enemies
        EmitSignal(SignalName.Hit, area);
        GD.Print($"[SniperBullet]: Bullet continues after penetrating enemy");
    }

    /// <summary>
    /// Exits penetration state after passing through a wall.
    /// </summary>
    private void ExitPenetration()
    {
        if (!_isPenetrating)
        {
            return;
        }

        _wallsPenetrated++;
        GD.Print($"[SniperBullet] Exited wall - walls penetrated: {_wallsPenetrated}/{MaxWallPenetrations}");

        // Play wall hit sound on exit
        PlayBulletWallHitSound();

        _isPenetrating = false;
        _penetratingBody = null;
    }

    /// <summary>
    /// Checks if the bullet is still inside an obstacle.
    /// </summary>
    private bool IsStillInsideObstacle()
    {
        if (_penetratingBody == null || !IsInstanceValid(_penetratingBody))
        {
            return false;
        }

        var spaceState = GetWorld2D().DirectSpaceState;
        float rayLength = 50.0f;

        // Check forward
        var query = PhysicsRayQueryParameters2D.Create(
            GlobalPosition,
            GlobalPosition + Direction * rayLength
        );
        query.CollisionMask = CollisionMask;
        query.Exclude = new Godot.Collections.Array<Rid> { GetRid() };

        var result = spaceState.IntersectRay(query);
        if (result.Count > 0 && (Node2D)result["collider"] == _penetratingBody)
        {
            return true;
        }

        // Check backward
        query = PhysicsRayQueryParameters2D.Create(
            GlobalPosition,
            GlobalPosition - Direction * rayLength
        );
        query.CollisionMask = CollisionMask;
        query.Exclude = new Godot.Collections.Array<Rid> { GetRid() };

        result = spaceState.IntersectRay(query);
        if (result.Count > 0 && (Node2D)result["collider"] == _penetratingBody)
        {
            return true;
        }

        return false;
    }

    /// <summary>
    /// Spawns wall hit dust effect.
    /// </summary>
    private void SpawnWallHitEffect(Node2D body)
    {
        var impactManager = GetNodeOrNull("/root/ImpactEffectsManager");
        if (impactManager == null || !impactManager.HasMethod("spawn_dust_effect"))
        {
            return;
        }

        var surfaceNormal = GetSurfaceNormal(body);
        impactManager.Call("spawn_dust_effect", GlobalPosition, surfaceNormal, Variant.CreateFrom((Resource?)null));
    }

    /// <summary>
    /// Gets the surface normal at collision point.
    /// </summary>
    private Vector2 GetSurfaceNormal(Node2D body)
    {
        var spaceState = GetWorld2D().DirectSpaceState;
        var rayStart = GlobalPosition - Direction * 50.0f;
        var rayEnd = GlobalPosition + Direction * 10.0f;

        var query = PhysicsRayQueryParameters2D.Create(rayStart, rayEnd);
        query.CollisionMask = CollisionMask;
        query.Exclude = new Godot.Collections.Array<Rid> { GetRid() };

        var result = spaceState.IntersectRay(query);
        if (result.Count == 0)
        {
            return -Direction.Normalized();
        }

        return (Vector2)result["normal"];
    }

    /// <summary>
    /// Plays wall hit sound.
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
    /// Checks if this bullet was fired by the player.
    /// </summary>
    private bool IsPlayerBullet()
    {
        if (ShooterId == 0) return false;

        if (_shooterNode == null)
        {
            _shooterNode = GodotObject.InstanceFromId(ShooterId) as Node;
        }

        if (_shooterNode is Player) return true;

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
    /// Triggers hit effects when player bullet hits enemy.
    /// </summary>
    private void TriggerPlayerHitEffects()
    {
        var hitEffectsManager = GetNodeOrNull("/root/HitEffectsManager");
        if (hitEffectsManager != null && hitEffectsManager.HasMethod("on_player_hit_enemy"))
        {
            hitEffectsManager.Call("on_player_hit_enemy");
        }
    }
}
