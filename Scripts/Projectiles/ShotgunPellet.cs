using Godot;
using GodotTopDownTemplate.Characters;
using GodotTopDownTemplate.Data;
using GodotTopDownTemplate.Interfaces;

namespace GodotTopDownTemplate.Projectiles;

/// <summary>
/// Shotgun pellet projectile with limited ricochet angles.
/// Unlike rifle bullets, pellets:
/// - Ricochet only at shallow angles (max 35 degrees)
/// - Cannot penetrate walls
/// - Travel at higher speeds
/// </summary>
public partial class ShotgunPellet : Area2D
{
    /// <summary>
    /// Speed of the pellet in pixels per second.
    /// Default matches assault rifle bullet speed for gameplay consistency.
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
    /// </summary>
    [Export]
    public int TrailLength { get; set; } = 8;

    /// <summary>
    /// Direction the pellet travels (set by the shooter).
    /// </summary>
    public Vector2 Direction { get; set; } = Vector2.Right;

    /// <summary>
    /// Instance ID of the node that shot this pellet.
    /// </summary>
    public ulong ShooterId { get; set; } = 0;

    // =========================================================================
    // Ricochet Configuration (Shotgun Pellet - limited to 35 degrees)
    // =========================================================================

    /// <summary>
    /// Maximum number of ricochets allowed. -1 = unlimited.
    /// </summary>
    private const int MaxRicochets = -1;

    /// <summary>
    /// Maximum angle (degrees) from surface at which ricochet is possible.
    /// For shotgun pellets, limited to 35 degrees (shallow/grazing shots only).
    /// </summary>
    private const float MaxRicochetAngle = 35.0f;

    /// <summary>
    /// Base probability of ricochet at optimal (grazing) angle.
    /// </summary>
    private const float BaseRicochetProbability = 1.0f;

    /// <summary>
    /// Velocity retention factor after ricochet (0-1).
    /// </summary>
    private const float VelocityRetention = 0.75f;

    /// <summary>
    /// Damage multiplier after each ricochet.
    /// </summary>
    private const float RicochetDamageMultiplier = 0.5f;

    /// <summary>
    /// Random angle deviation (degrees) for ricochet direction.
    /// </summary>
    private const float RicochetAngleDeviation = 15.0f;

    /// <summary>
    /// Current damage multiplier (decreases with each ricochet).
    /// </summary>
    private float _damageMultiplier = 1.0f;

    /// <summary>
    /// Number of ricochets that have occurred.
    /// </summary>
    private int _ricochetCount = 0;

    /// <summary>
    /// Viewport diagonal for post-ricochet lifetime calculation.
    /// </summary>
    private float _viewportDiagonal = 2203.0f;

    /// <summary>
    /// Whether this pellet has ricocheted at least once.
    /// </summary>
    private bool _hasRicocheted = false;

    /// <summary>
    /// Distance traveled since the last ricochet.
    /// </summary>
    private float _distanceSinceRicochet = 0.0f;

    /// <summary>
    /// Maximum travel distance after ricochet (based on viewport and angle).
    /// </summary>
    private float _maxPostRicochetDistance = 0.0f;

    /// <summary>
    /// Enable debug logging for ricochet calculations.
    /// </summary>
    private const bool DebugRicochet = false;

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
    /// Signal emitted when the pellet hits something.
    /// </summary>
    [Signal]
    public delegate void HitEventHandler(Node2D target);

    public override void _Ready()
    {
        // Connect to collision signals
        BodyEntered += OnBodyEntered;
        AreaEntered += OnAreaEntered;

        // Get trail reference if it exists
        _trail = GetNodeOrNull<Line2D>("Trail");
        if (_trail != null)
        {
            _trail.ClearPoints();
            _trail.TopLevel = true;
            _trail.Position = Vector2.Zero;
        }

        // Calculate viewport diagonal for post-ricochet lifetime
        CalculateViewportDiagonal();

        // Set initial rotation based on direction
        UpdateRotation();
    }

    /// <summary>
    /// Calculates the viewport diagonal for post-ricochet distance limits.
    /// </summary>
    private void CalculateViewportDiagonal()
    {
        var viewport = GetViewport();
        if (viewport != null)
        {
            var size = viewport.GetVisibleRect().Size;
            _viewportDiagonal = Mathf.Sqrt(size.X * size.X + size.Y * size.Y);
        }
        else
        {
            _viewportDiagonal = 2203.0f;
        }
    }

    /// <summary>
    /// Updates the pellet rotation to match its travel direction.
    /// </summary>
    private void UpdateRotation()
    {
        Rotation = Direction.Angle();
    }

    public override void _PhysicsProcess(double delta)
    {
        // Calculate movement this frame
        var movement = Direction * Speed * (float)delta;

        // Move in the set direction
        Position += movement;

        // Track distance traveled since last ricochet
        if (_hasRicocheted)
        {
            _distanceSinceRicochet += movement.Length();
            if (_distanceSinceRicochet >= _maxPostRicochetDistance)
            {
                if (DebugRicochet)
                {
                    GD.Print($"[ShotgunPellet] Post-ricochet distance exceeded: {_distanceSinceRicochet} >= {_maxPostRicochetDistance}");
                }
                QueueFree();
                return;
            }
        }

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
    /// Sets the direction for the pellet.
    /// </summary>
    /// <param name="direction">Direction vector (will be normalized).</param>
    public void SetDirection(Vector2 direction)
    {
        Direction = direction.Normalized();
        UpdateRotation();
    }

    /// <summary>
    /// Called when the pellet hits a static body (wall or obstacle).
    /// Pellets cannot penetrate - they either ricochet or stop.
    /// </summary>
    private void OnBodyEntered(Node2D body)
    {
        // Check if this is the shooter
        if (ShooterId == body.GetInstanceId())
        {
            return;
        }

        // Check if this is a dead enemy
        if (body.HasMethod("is_alive"))
        {
            var isAlive = body.Call("is_alive").AsBool();
            if (!isAlive)
            {
                return;
            }
        }

        // Try to ricochet off static bodies (walls/obstacles)
        // Pellets CANNOT penetrate - only ricochet or stop
        if (body is StaticBody2D || body is TileMap)
        {
            SpawnWallHitEffect(body);

            // Try ricochet (limited to 35 degrees)
            if (TryRicochet(body))
            {
                return;
            }
        }

        // Hit a static body or enemy body
        PlayPelletHitSound();
        EmitSignal(SignalName.Hit, body);
        QueueFree();
    }

    /// <summary>
    /// Plays the pellet wall impact sound.
    /// </summary>
    private void PlayPelletHitSound()
    {
        var audioManager = GetNodeOrNull("/root/AudioManager");
        if (audioManager != null && audioManager.HasMethod("play_bullet_wall_hit"))
        {
            audioManager.Call("play_bullet_wall_hit", GlobalPosition);
        }
    }

    /// <summary>
    /// Spawns dust/debris particles when pellet hits a wall.
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
    /// Called when the pellet hits another area (like a target or enemy).
    /// </summary>
    private void OnAreaEntered(Area2D area)
    {
        GD.Print($"[ShotgunPellet]: Hit {area.Name} (damage: {Damage * _damageMultiplier})");

        // Check if this is the shooter's HitArea
        var parent = area.GetParent();
        if (parent != null && ShooterId == parent.GetInstanceId() && !_hasRicocheted)
        {
            GD.Print($"[ShotgunPellet]: Ignoring self-hit on {parent.Name} (not ricocheted)");
            return;
        }

        // Check if parent is dead
        if (parent != null && parent.HasMethod("is_alive"))
        {
            var isAlive = parent.Call("is_alive").AsBool();
            if (!isAlive)
            {
                GD.Print($"[ShotgunPellet]: Passing through dead entity {parent.Name}");
                return;
            }
        }

        bool hitEnemy = false;
        float effectiveDamage = Damage * _damageMultiplier;

        // Check if the target implements IDamageable
        if (area is IDamageable damageable)
        {
            GD.Print($"[ShotgunPellet]: Target {area.Name} is IDamageable, applying {effectiveDamage} damage");
            damageable.TakeDamage(effectiveDamage);
            hitEnemy = true;
        }
        else if (area.HasMethod("on_hit"))
        {
            GD.Print($"[ShotgunPellet]: Target {area.Name} has on_hit method, calling it");
            area.Call("on_hit");
            hitEnemy = true;
        }
        else if (area.HasMethod("OnHit"))
        {
            GD.Print($"[ShotgunPellet]: Target {area.Name} has OnHit method, calling it");
            area.Call("OnHit");
            hitEnemy = true;
        }

        if (hitEnemy && IsPlayerPellet())
        {
            TriggerPlayerHitEffects();
        }

        EmitSignal(SignalName.Hit, area);
        QueueFree();
    }

    /// <summary>
    /// Checks if this pellet was fired by the player.
    /// </summary>
    private bool IsPlayerPellet()
    {
        if (ShooterId == 0)
        {
            return false;
        }

        if (_shooterNode == null)
        {
            _shooterNode = GodotObject.InstanceFromId(ShooterId) as Node;
        }

        if (_shooterNode is Player)
        {
            return true;
        }

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
    /// </summary>
    private void TriggerPlayerHitEffects()
    {
        var hitEffectsManager = GetNodeOrNull("/root/HitEffectsManager");
        if (hitEffectsManager != null && hitEffectsManager.HasMethod("on_player_hit_enemy"))
        {
            GD.Print("[ShotgunPellet]: Triggering player hit effects");
            hitEffectsManager.Call("on_player_hit_enemy");
        }
    }

    // =========================================================================
    // Ricochet Methods (Limited to 35 degrees for pellets)
    // =========================================================================

    /// <summary>
    /// Attempts to ricochet the pellet off a surface.
    /// Only succeeds for shallow angles (under 35 degrees).
    /// </summary>
    private bool TryRicochet(Node2D body)
    {
        if (MaxRicochets >= 0 && _ricochetCount >= MaxRicochets)
        {
            if (DebugRicochet)
            {
                GD.Print($"[ShotgunPellet] Max ricochets reached: {_ricochetCount}");
            }
            return false;
        }

        var surfaceNormal = GetSurfaceNormal(body);
        if (surfaceNormal == Vector2.Zero)
        {
            if (DebugRicochet)
            {
                GD.Print("[ShotgunPellet] Could not determine surface normal");
            }
            return false;
        }

        float impactAngleRad = CalculateImpactAngle(surfaceNormal);
        float impactAngleDeg = Mathf.RadToDeg(impactAngleRad);

        if (DebugRicochet)
        {
            GD.Print($"[ShotgunPellet] Impact angle: {impactAngleDeg} degrees (max: {MaxRicochetAngle})");
        }

        // Pellets only ricochet at shallow angles (35 degrees or less)
        if (impactAngleDeg > MaxRicochetAngle)
        {
            if (DebugRicochet)
            {
                GD.Print($"[ShotgunPellet] Impact angle {impactAngleDeg}° > max {MaxRicochetAngle}° - no ricochet");
            }
            return false;
        }

        // Calculate ricochet probability
        float ricochetProbability = CalculateRicochetProbability(impactAngleDeg);

        if (DebugRicochet)
        {
            GD.Print($"[ShotgunPellet] Ricochet probability: {ricochetProbability * 100}%");
        }

        if (GD.Randf() > ricochetProbability)
        {
            if (DebugRicochet)
            {
                GD.Print("[ShotgunPellet] Ricochet failed (random)");
            }
            return false;
        }

        PerformRicochet(surfaceNormal, impactAngleDeg);
        return true;
    }

    /// <summary>
    /// Gets the surface normal at the collision point.
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
    /// Calculates the impact angle (grazing angle from surface).
    /// </summary>
    private float CalculateImpactAngle(Vector2 surfaceNormal)
    {
        float dot = Mathf.Abs(Direction.Normalized().Dot(surfaceNormal.Normalized()));
        dot = Mathf.Clamp(dot, 0.0f, 1.0f);
        return Mathf.Asin(dot);
    }

    /// <summary>
    /// Calculates the ricochet probability based on impact angle.
    /// For pellets, probability decreases faster with angle.
    /// </summary>
    private float CalculateRicochetProbability(float impactAngleDeg)
    {
        if (impactAngleDeg > MaxRicochetAngle)
        {
            return 0.0f;
        }

        // Linear falloff from 100% at 0° to 50% at 35°
        float normalizedAngle = impactAngleDeg / MaxRicochetAngle;
        float angleFactor = 1.0f - (normalizedAngle * 0.5f);
        return BaseRicochetProbability * angleFactor;
    }

    /// <summary>
    /// Performs the ricochet.
    /// </summary>
    private void PerformRicochet(Vector2 surfaceNormal, float impactAngleDeg)
    {
        _ricochetCount++;

        // Calculate reflected direction
        var reflected = Direction - 2.0f * Direction.Dot(surfaceNormal) * surfaceNormal;
        reflected = reflected.Normalized();

        // Add random deviation (larger for pellets)
        float deviation = GetRicochetDeviation();
        reflected = reflected.Rotated(deviation);

        Direction = reflected;
        UpdateRotation();

        // Reduce velocity (pellets lose more energy)
        Speed *= VelocityRetention;

        // Reduce damage multiplier
        _damageMultiplier *= RicochetDamageMultiplier;

        // Move away from surface
        GlobalPosition += Direction * 5.0f;

        // Set post-ricochet lifetime
        _hasRicocheted = true;
        _distanceSinceRicochet = 0.0f;

        float angleFactor = 1.0f - (impactAngleDeg / MaxRicochetAngle);
        angleFactor = Mathf.Clamp(angleFactor, 0.1f, 1.0f);
        _maxPostRicochetDistance = _viewportDiagonal * angleFactor * 0.5f; // Shorter post-ricochet distance for pellets

        // Clear trail history
        _positionHistory.Clear();

        // Play ricochet sound
        PlayRicochetSound();

        if (DebugRicochet)
        {
            GD.Print($"[ShotgunPellet] Ricochet #{_ricochetCount} - New speed: {Speed}, Damage mult: {_damageMultiplier}");
        }
    }

    /// <summary>
    /// Gets a random deviation angle for ricochet direction.
    /// </summary>
    private float GetRicochetDeviation()
    {
        float deviationRad = Mathf.DegToRad(RicochetAngleDeviation);
        return (float)GD.RandRange(-deviationRad, deviationRad);
    }

    /// <summary>
    /// Plays the ricochet sound effect.
    /// </summary>
    private void PlayRicochetSound()
    {
        var audioManager = GetNodeOrNull("/root/AudioManager");
        if (audioManager != null && audioManager.HasMethod("play_bullet_ricochet"))
        {
            audioManager.Call("play_bullet_ricochet", GlobalPosition);
        }
        else if (audioManager != null && audioManager.HasMethod("play_bullet_wall_hit"))
        {
            audioManager.Call("play_bullet_wall_hit", GlobalPosition);
        }
    }

    /// <summary>
    /// Gets the current ricochet count.
    /// </summary>
    public int GetRicochetCount() => _ricochetCount;

    /// <summary>
    /// Gets the current damage multiplier.
    /// </summary>
    public float GetDamageMultiplier() => _damageMultiplier;

    /// <summary>
    /// Gets the effective damage after applying ricochet multiplier.
    /// </summary>
    public float GetEffectiveDamage() => Damage * _damageMultiplier;
}
