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
///
/// Supports realistic ricochet mechanics:
/// - Ricochet probability depends on impact angle (shallow = more likely)
/// - Velocity and damage reduction after ricochet
/// - Unlimited ricochets by default
/// - Random angle deviation for realistic bounce behavior
/// - Viewport-based post-ricochet lifetime
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

    // =========================================================================
    // Ricochet Configuration (5.45x39mm defaults, matching GDScript bullet)
    // =========================================================================

    /// <summary>
    /// Maximum number of ricochets allowed. -1 = unlimited.
    /// </summary>
    private const int MaxRicochets = -1;

    /// <summary>
    /// Maximum angle (degrees) from surface at which ricochet is possible.
    /// Set to 90 to allow ricochets at all angles with varying probability.
    /// </summary>
    private const float MaxRicochetAngle = 90.0f;

    /// <summary>
    /// Base probability of ricochet at optimal (grazing) angle.
    /// </summary>
    private const float BaseRicochetProbability = 1.0f;

    /// <summary>
    /// Velocity retention factor after ricochet (0-1).
    /// Higher values mean less speed loss. 0.85 = 85% speed retained.
    /// </summary>
    private const float VelocityRetention = 0.85f;

    /// <summary>
    /// Damage multiplier after each ricochet.
    /// </summary>
    private const float RicochetDamageMultiplier = 0.5f;

    /// <summary>
    /// Random angle deviation (degrees) for ricochet direction.
    /// </summary>
    private const float RicochetAngleDeviation = 10.0f;

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
    /// Whether this bullet has ricocheted at least once.
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

    // =========================================================================
    // Penetration Configuration (matching GDScript bullet.gd)
    // =========================================================================

    /// <summary>
    /// Whether penetration is enabled.
    /// </summary>
    private const bool CanPenetrate = true;

    /// <summary>
    /// Maximum penetration distance (pixels) for 5.45x39mm = 48px (2x thin wall).
    /// </summary>
    private const float MaxPenetrationDistance = 48.0f;

    /// <summary>
    /// Damage multiplier after penetrating a wall (90% of original).
    /// </summary>
    private const float PostPenetrationDamageMultiplier = 0.9f;

    /// <summary>
    /// Distance ratio for point-blank shots (0% = point blank).
    /// </summary>
    private const float PointBlankDistanceRatio = 0.0f;

    /// <summary>
    /// Distance ratio at which normal ricochet rules apply (40% of viewport).
    /// </summary>
    private const float RicochetRulesDistanceRatio = 0.4f;

    /// <summary>
    /// Maximum penetration chance at viewport distance (30%).
    /// </summary>
    private const float MaxPenetrationChanceAtDistance = 0.3f;

    /// <summary>
    /// Enable debug logging for penetration calculations.
    /// </summary>
    private const bool DebugPenetration = true;

    /// <summary>
    /// Whether the bullet is currently penetrating through a wall.
    /// </summary>
    private bool _isPenetrating = false;

    /// <summary>
    /// Distance traveled while penetrating through walls.
    /// </summary>
    private float _penetrationDistanceTraveled = 0.0f;

    /// <summary>
    /// Entry point into the current obstacle being penetrated.
    /// </summary>
    private Vector2 _penetrationEntryPoint = Vector2.Zero;

    /// <summary>
    /// The body currently being penetrated (for tracking exit).
    /// </summary>
    private Node2D? _penetratingBody = null;

    /// <summary>
    /// Whether the bullet has penetrated at least one wall.
    /// </summary>
    private bool _hasPenetrated = false;

    /// <summary>
    /// Shooter's position at firing time (for distance-based penetration).
    /// </summary>
    public Vector2 ShooterPosition { get; set; } = Vector2.Zero;

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
        BodyExited += OnBodyExited;
        AreaEntered += OnAreaEntered;

        // Get trail reference if it exists
        _trail = GetNodeOrNull<Line2D>("Trail");
        if (_trail != null)
        {
            _trail.ClearPoints();
            // Set trail to use global coordinates (not relative to bullet)
            _trail.TopLevel = true;
            // Reset position to origin so points added are truly global
            // (when TopLevel becomes true, the Line2D's position becomes its global position,
            // so we need to reset it to (0,0) for added points to be at their true global positions)
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
            // Fallback to 1920x1080 diagonal
            _viewportDiagonal = 2203.0f;
        }
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
        // Calculate movement this frame
        var movement = Direction * Speed * (float)delta;

        // Move in the set direction
        Position += movement;

        // Track distance traveled since last ricochet (for viewport-based lifetime)
        if (_hasRicocheted)
        {
            _distanceSinceRicochet += movement.Length();
            // Destroy bullet if it has traveled more than the viewport-based max distance
            if (_distanceSinceRicochet >= _maxPostRicochetDistance)
            {
                if (DebugRicochet)
                {
                    GD.Print($"[Bullet] Post-ricochet distance exceeded: {_distanceSinceRicochet} >= {_maxPostRicochetDistance}");
                }
                QueueFree();
                return;
            }
        }

        // Track penetration distance while inside a wall
        if (_isPenetrating)
        {
            _penetrationDistanceTraveled += movement.Length();

            // Check if we've exceeded max penetration distance
            if (_penetrationDistanceTraveled >= MaxPenetrationDistance)
            {
                LogPenetration($"Max penetration distance exceeded: {_penetrationDistanceTraveled} >= {MaxPenetrationDistance}");
                // Bullet stopped inside the wall - destroy it
                // Visual effects disabled as per user request
                QueueFree();
                return;
            }

            // Check if we've exited the obstacle (raycast forward to see if still inside)
            if (!IsStillInsideObstacle())
            {
                ExitPenetration();
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

        // If we're currently penetrating the same body, ignore re-entry
        if (_isPenetrating && _penetratingBody == body)
        {
            return;
        }

        // Check if bullet is inside an existing penetration hole - pass through
        if (IsInsidePenetrationHole())
        {
            LogPenetration("Inside existing penetration hole, passing through");
            return;
        }

        // Try to ricochet or penetrate off static bodies (walls/obstacles)
        if (body is StaticBody2D || body is TileMap)
        {
            // Always spawn dust effect when hitting walls, regardless of ricochet
            SpawnWallHitEffect(body);

            // Calculate distance from shooter to determine penetration behavior
            float distanceToWall = GetDistanceToShooter();
            float distanceRatio = _viewportDiagonal > 0 ? distanceToWall / _viewportDiagonal : 1.0f;

            LogPenetration($"Distance to wall: {distanceToWall} ({distanceRatio * 100}% of viewport)");

            // Point-blank shots (very close to shooter): 100% penetration, ignore ricochet
            if (distanceRatio <= PointBlankDistanceRatio + 0.05f)
            {
                LogPenetration("Point-blank shot - 100% penetration, ignoring ricochet");
                if (TryPenetration(body))
                {
                    return; // Bullet is penetrating
                }
            }
            // At 40% or less of viewport: normal ricochet rules apply
            else if (distanceRatio <= RicochetRulesDistanceRatio)
            {
                LogPenetration("Within ricochet range - trying ricochet first");
                // First try ricochet
                if (TryRicochet(body))
                {
                    return; // Bullet ricocheted, don't destroy
                }
                // Ricochet failed - try penetration
                if (TryPenetration(body))
                {
                    return; // Bullet is penetrating
                }
            }
            // Beyond 40% of viewport: distance-based penetration chance
            else
            {
                // First try ricochet (shallow angles still ricochet)
                if (TryRicochet(body))
                {
                    return; // Bullet ricocheted, don't destroy
                }

                // Calculate penetration chance based on distance
                float penetrationChance = CalculateDistancePenetrationChance(distanceRatio);
                LogPenetration($"Distance-based penetration chance: {penetrationChance * 100}%");

                // Roll for penetration
                if (GD.Randf() <= penetrationChance)
                {
                    if (TryPenetration(body))
                    {
                        return; // Bullet is penetrating
                    }
                }
                else
                {
                    LogPenetration("Penetration failed (distance roll)");
                }
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
    /// Spawns dust/debris particles when bullet hits a wall or static body.
    /// </summary>
    /// <param name="body">The body that was hit (used to get surface normal).</param>
    private void SpawnWallHitEffect(Node2D body)
    {
        var impactManager = GetNodeOrNull("/root/ImpactEffectsManager");
        if (impactManager == null || !impactManager.HasMethod("spawn_dust_effect"))
        {
            return;
        }

        // Get surface normal for particle direction
        var surfaceNormal = GetSurfaceNormal(body);

        // Spawn dust effect at hit position
        // Note: Passing null for caliber_data since C# Bullet doesn't use caliber resources
        impactManager.Call("spawn_dust_effect", GlobalPosition, surfaceNormal, Variant.CreateFrom((Resource?)null));
    }

    /// <summary>
    /// Called when the bullet hits another area (like a target or enemy).
    /// </summary>
    private void OnAreaEntered(Area2D area)
    {
        GD.Print($"[Bullet]: Hit {area.Name} (damage: {Damage})");

        // Check if this is a HitArea - if so, check against parent's instance ID
        // This prevents the shooter from damaging themselves with direct shots
        // BUT ricocheted bullets CAN damage the shooter (realistic self-damage)
        var parent = area.GetParent();
        if (parent != null && ShooterId == parent.GetInstanceId() && !_hasRicocheted)
        {
            GD.Print($"[Bullet]: Ignoring self-hit on {parent.Name} (not ricocheted)");
            return; // Don't hit the shooter with direct shots
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

    // =========================================================================
    // Ricochet Methods
    // =========================================================================

    /// <summary>
    /// Attempts to ricochet the bullet off a surface.
    /// Returns true if ricochet occurred, false if bullet should be destroyed.
    /// </summary>
    /// <param name="body">The body the bullet collided with.</param>
    /// <returns>True if the bullet ricocheted successfully.</returns>
    private bool TryRicochet(Node2D body)
    {
        // Check if we've exceeded maximum ricochets (-1 = unlimited)
        if (MaxRicochets >= 0 && _ricochetCount >= MaxRicochets)
        {
            if (DebugRicochet)
            {
                GD.Print($"[Bullet] Max ricochets reached: {_ricochetCount}");
            }
            return false;
        }

        // Get the surface normal at the collision point
        var surfaceNormal = GetSurfaceNormal(body);
        if (surfaceNormal == Vector2.Zero)
        {
            if (DebugRicochet)
            {
                GD.Print("[Bullet] Could not determine surface normal");
            }
            return false;
        }

        // Calculate impact angle (angle between bullet direction and surface)
        // 0 degrees = parallel to surface (grazing shot)
        // 90 degrees = perpendicular to surface (direct hit)
        float impactAngleRad = CalculateImpactAngle(surfaceNormal);
        float impactAngleDeg = Mathf.RadToDeg(impactAngleRad);

        if (DebugRicochet)
        {
            GD.Print($"[Bullet] Impact angle: {impactAngleDeg} degrees");
        }

        // Calculate ricochet probability based on impact angle
        float ricochetProbability = CalculateRicochetProbability(impactAngleDeg);

        if (DebugRicochet)
        {
            GD.Print($"[Bullet] Ricochet probability: {ricochetProbability * 100}%");
        }

        // Random roll to determine if ricochet occurs
        if (GD.Randf() > ricochetProbability)
        {
            if (DebugRicochet)
            {
                GD.Print("[Bullet] Ricochet failed (random)");
            }
            return false;
        }

        // Ricochet successful - calculate new direction
        PerformRicochet(surfaceNormal, impactAngleDeg);
        return true;
    }

    /// <summary>
    /// Gets the surface normal at the collision point using raycasting.
    /// </summary>
    /// <param name="body">The body that was hit.</param>
    /// <returns>Surface normal vector, or Vector2.Zero if not found.</returns>
    private Vector2 GetSurfaceNormal(Node2D body)
    {
        // Create a raycast to find the exact collision point
        var spaceState = GetWorld2D().DirectSpaceState;

        // Cast ray from slightly behind the bullet to current position
        var rayStart = GlobalPosition - Direction * 50.0f;
        var rayEnd = GlobalPosition + Direction * 10.0f;

        var query = PhysicsRayQueryParameters2D.Create(rayStart, rayEnd);
        query.CollisionMask = CollisionMask;
        query.Exclude = new Godot.Collections.Array<Rid> { GetRid() };

        var result = spaceState.IntersectRay(query);

        if (result.Count == 0)
        {
            // Fallback: estimate normal based on bullet direction
            return -Direction.Normalized();
        }

        return (Vector2)result["normal"];
    }

    /// <summary>
    /// Calculates the impact angle between bullet direction and surface.
    /// This returns the GRAZING angle (angle from the surface plane).
    /// </summary>
    /// <param name="surfaceNormal">The surface normal vector.</param>
    /// <returns>Angle in radians (0 = grazing/parallel to surface, PI/2 = perpendicular/head-on).</returns>
    private float CalculateImpactAngle(Vector2 surfaceNormal)
    {
        // We want the GRAZING angle (angle from the surface, not from the normal).
        // The grazing angle is 90° - (angle from normal).
        //
        // Using dot product with the normal:
        // dot(direction, -normal) = cos(angle_from_normal)
        //
        // The grazing angle = 90° - angle_from_normal
        // So: grazing_angle = asin(|dot(direction, normal)|)
        //
        // For grazing shots (parallel to surface): direction ⊥ normal, dot ≈ 0, grazing_angle ≈ 0°
        // For direct hits (perpendicular to surface): direction ∥ -normal, dot ≈ 1, grazing_angle ≈ 90°

        float dot = Mathf.Abs(Direction.Normalized().Dot(surfaceNormal.Normalized()));
        // Clamp to avoid numerical issues with asin
        dot = Mathf.Clamp(dot, 0.0f, 1.0f);
        return Mathf.Asin(dot);
    }

    /// <summary>
    /// Calculates the ricochet probability based on impact angle.
    /// Uses a custom curve designed for realistic 5.45x39mm behavior:
    /// - 0-15°: ~100% (grazing shots always ricochet)
    /// - 45°: ~80% (moderate angles have good ricochet chance)
    /// - 90°: ~10% (perpendicular shots rarely ricochet)
    /// </summary>
    /// <param name="impactAngleDeg">Impact angle in degrees.</param>
    /// <returns>Probability of ricochet (0.0 to 1.0).</returns>
    private float CalculateRicochetProbability(float impactAngleDeg)
    {
        // No ricochet if angle exceeds maximum
        if (impactAngleDeg > MaxRicochetAngle)
        {
            return 0.0f;
        }

        // Custom curve for realistic ricochet probability:
        // probability = base * (0.9 * (1 - (angle/90)^2.17) + 0.1)
        // This gives approximately:
        // - 0°: 100%, 15°: 98%, 45°: 80%, 90°: 10%
        float normalizedAngle = impactAngleDeg / 90.0f;
        // Power of 2.17 creates a curve matching real-world ballistics
        float powerFactor = Mathf.Pow(normalizedAngle, 2.17f);
        float angleFactor = (1.0f - powerFactor) * 0.9f + 0.1f;
        return BaseRicochetProbability * angleFactor;
    }

    /// <summary>
    /// Performs the ricochet: updates direction, speed, damage, and plays sound.
    /// Also calculates the post-ricochet maximum travel distance.
    /// </summary>
    /// <param name="surfaceNormal">The surface normal vector.</param>
    /// <param name="impactAngleDeg">The impact angle in degrees.</param>
    private void PerformRicochet(Vector2 surfaceNormal, float impactAngleDeg)
    {
        _ricochetCount++;

        // Calculate reflected direction
        // reflection = direction - 2 * dot(direction, normal) * normal
        var reflected = Direction - 2.0f * Direction.Dot(surfaceNormal) * surfaceNormal;
        reflected = reflected.Normalized();

        // Add random deviation for realism
        float deviation = GetRicochetDeviation();
        reflected = reflected.Rotated(deviation);

        // Update direction
        Direction = reflected;
        UpdateRotation();

        // Reduce velocity
        Speed *= VelocityRetention;

        // Reduce damage multiplier
        _damageMultiplier *= RicochetDamageMultiplier;

        // Move bullet slightly away from surface to prevent immediate re-collision
        GlobalPosition += Direction * 5.0f;

        // Mark bullet as having ricocheted and set viewport-based lifetime
        _hasRicocheted = true;
        _distanceSinceRicochet = 0.0f;

        // Calculate max post-ricochet distance based on viewport and ricochet angle
        // Shallow angles (grazing) -> bullet travels longer after ricochet
        // Steeper angles -> bullet travels shorter distance (more energy lost)
        float angleFactor = 1.0f - (impactAngleDeg / 90.0f);
        angleFactor = Mathf.Clamp(angleFactor, 0.1f, 1.0f); // Minimum 10%
        _maxPostRicochetDistance = _viewportDiagonal * angleFactor;

        // Clear trail history to avoid visual artifacts
        _positionHistory.Clear();

        // Play ricochet sound
        PlayRicochetSound();

        if (DebugRicochet)
        {
            GD.Print($"[Bullet] Ricochet #{_ricochetCount} - New speed: {Speed}, Damage mult: {_damageMultiplier}, Max post-ricochet distance: {_maxPostRicochetDistance}");
        }
    }

    /// <summary>
    /// Gets a random deviation angle for ricochet direction.
    /// </summary>
    /// <returns>Random angle in radians.</returns>
    private float GetRicochetDeviation()
    {
        float deviationRad = Mathf.DegToRad(RicochetAngleDeviation);
        return (float)GD.RandRange(-deviationRad, deviationRad);
    }

    /// <summary>
    /// Plays the ricochet sound effect via AudioManager.
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
            // Fallback to wall hit sound if ricochet sound not available
            audioManager.Call("play_bullet_wall_hit", GlobalPosition);
        }
    }

    /// <summary>
    /// Gets the current ricochet count.
    /// </summary>
    public int GetRicochetCount() => _ricochetCount;

    /// <summary>
    /// Gets the current damage multiplier (accounting for ricochets).
    /// </summary>
    public float GetDamageMultiplier() => _damageMultiplier;

    /// <summary>
    /// Gets the effective damage after applying ricochet multiplier.
    /// </summary>
    public float GetEffectiveDamage() => Damage * _damageMultiplier;

    // =========================================================================
    // Penetration Methods
    // =========================================================================

    /// <summary>
    /// Logs a penetration-related message to both console and file logger.
    /// </summary>
    /// <param name="message">The message to log.</param>
    private void LogPenetration(string message)
    {
        if (!DebugPenetration)
        {
            return;
        }
        string fullMessage = $"[Bullet] {message}";
        GD.Print(fullMessage);
        // Also log to FileLogger if available
        var fileLogger = GetNodeOrNull("/root/FileLogger");
        if (fileLogger != null && fileLogger.HasMethod("log_info"))
        {
            fileLogger.Call("log_info", fullMessage);
        }
    }

    /// <summary>
    /// Called when the bullet exits a body (wall).
    /// Used for detecting penetration exit via the physics system.
    /// </summary>
    private void OnBodyExited(Node2D body)
    {
        // Only process if we're currently penetrating this specific body
        if (!_isPenetrating || _penetratingBody != body)
        {
            return;
        }

        LogPenetration("Body exited signal received for penetrating body");
        ExitPenetration();
    }

    /// <summary>
    /// Gets the distance from the current bullet position to the shooter's original position.
    /// </summary>
    /// <returns>Distance in pixels.</returns>
    private float GetDistanceToShooter()
    {
        LogPenetration($"_get_distance_to_shooter: shooter_position={ShooterPosition}, shooter_id={ShooterId}, bullet_pos={GlobalPosition}");

        if (ShooterPosition == Vector2.Zero)
        {
            // Fallback: use shooter instance position if available
            if (ShooterId != 0)
            {
                var shooter = GodotObject.InstanceFromId(ShooterId) as Node2D;
                if (shooter != null)
                {
                    float dist = GlobalPosition.DistanceTo(shooter.GlobalPosition);
                    LogPenetration($"Using shooter_id fallback, distance={dist}");
                    return dist;
                }
            }
            LogPenetration("WARNING: Unable to determine shooter position");
        }

        float distance = GlobalPosition.DistanceTo(ShooterPosition);
        LogPenetration($"Using shooter_position, distance={distance}");
        return distance;
    }

    /// <summary>
    /// Calculates the penetration chance based on distance from shooter.
    /// </summary>
    /// <param name="distanceRatio">Distance as a ratio of viewport diagonal (0.0 to 1.0+).</param>
    /// <returns>Penetration chance (0.0 to 1.0).</returns>
    private float CalculateDistancePenetrationChance(float distanceRatio)
    {
        if (distanceRatio <= RicochetRulesDistanceRatio)
        {
            return 1.0f; // Full penetration chance within ricochet rules range
        }

        // Linear interpolation from 100% at 40% to 30% at 100%
        float rangeStart = RicochetRulesDistanceRatio; // 0.4
        float rangeEnd = 1.0f; // viewport distance
        float rangeSpan = rangeEnd - rangeStart; // 0.6

        float positionInRange = (distanceRatio - rangeStart) / rangeSpan;
        positionInRange = Mathf.Clamp(positionInRange, 0.0f, 1.0f);

        // Interpolate from 1.0 to MaxPenetrationChanceAtDistance
        float penetrationChance = Mathf.Lerp(1.0f, MaxPenetrationChanceAtDistance, positionInRange);

        // Beyond viewport distance, continue decreasing (but clamp to minimum of 5%)
        if (distanceRatio > 1.0f)
        {
            float beyondViewport = distanceRatio - 1.0f;
            penetrationChance = Mathf.Max(MaxPenetrationChanceAtDistance - beyondViewport * 0.2f, 0.05f);
        }

        return penetrationChance;
    }

    /// <summary>
    /// Checks if the bullet is currently inside an existing penetration hole area.
    /// </summary>
    /// <returns>True if inside a penetration hole.</returns>
    private bool IsInsidePenetrationHole()
    {
        var overlappingAreas = GetOverlappingAreas();
        foreach (var area in overlappingAreas)
        {
            // Check by script path
            var script = area.GetScript();
            if (script.VariantType == Variant.Type.Object)
            {
                var scriptObj = script.AsGodotObject();
                if (scriptObj is Script gdScript && gdScript.ResourcePath.Contains("penetration_hole"))
                {
                    return true;
                }
            }
            // Also check by node name as fallback
            if (area.Name.ToString().Contains("PenetrationHole"))
            {
                return true;
            }
        }
        return false;
    }

    /// <summary>
    /// Attempts to penetrate through a wall when ricochet fails.
    /// </summary>
    /// <param name="body">The static body (wall) to penetrate.</param>
    /// <returns>True if penetration started successfully.</returns>
    private bool TryPenetration(Node2D body)
    {
        if (!CanPenetrate)
        {
            LogPenetration("Caliber cannot penetrate walls");
            return false;
        }

        // Don't start a new penetration if already penetrating
        if (_isPenetrating)
        {
            LogPenetration("Already penetrating, cannot start new penetration");
            return false;
        }

        LogPenetration($"Starting wall penetration at {GlobalPosition}");

        // Mark as penetrating
        _isPenetrating = true;
        _penetratingBody = body;
        _penetrationEntryPoint = GlobalPosition;
        _penetrationDistanceTraveled = 0.0f;

        // Visual effects disabled as per user request
        // Entry dust effect removed

        // Move bullet slightly forward to avoid immediate re-collision
        GlobalPosition += Direction * 5.0f;

        return true;
    }

    /// <summary>
    /// Checks if the bullet is still inside an obstacle using raycasting.
    /// </summary>
    /// <returns>True if still inside, false if exited.</returns>
    private bool IsStillInsideObstacle()
    {
        if (_penetratingBody == null || !IsInstanceValid(_penetratingBody))
        {
            return false;
        }

        var spaceState = GetWorld2D().DirectSpaceState;

        // Use longer raycasts to account for bullet speed
        float rayLength = 50.0f;
        var rayStart = GlobalPosition;
        var rayEnd = GlobalPosition + Direction * rayLength;

        var query = PhysicsRayQueryParameters2D.Create(rayStart, rayEnd);
        query.CollisionMask = CollisionMask;
        query.Exclude = new Godot.Collections.Array<Rid> { GetRid() };

        var result = spaceState.IntersectRay(query);

        // If we hit the same body in front, we're still inside
        if (result.Count > 0 && (Node2D)result["collider"] == _penetratingBody)
        {
            LogPenetration($"Raycast forward hit penetrating body at distance {rayStart.DistanceTo((Vector2)result["position"])}");
            return true;
        }

        // Also check backwards to see if we're still overlapping
        rayEnd = GlobalPosition - Direction * rayLength;
        query = PhysicsRayQueryParameters2D.Create(rayStart, rayEnd);
        query.CollisionMask = CollisionMask;
        query.Exclude = new Godot.Collections.Array<Rid> { GetRid() };

        result = spaceState.IntersectRay(query);
        if (result.Count > 0 && (Node2D)result["collider"] == _penetratingBody)
        {
            LogPenetration($"Raycast backward hit penetrating body at distance {rayStart.DistanceTo((Vector2)result["position"])}");
            return true;
        }

        LogPenetration("No longer inside obstacle - raycasts found no collision with penetrating body");
        return false;
    }

    /// <summary>
    /// Called when the bullet exits a penetrated wall.
    /// </summary>
    private void ExitPenetration()
    {
        // Prevent double-calling
        if (!_isPenetrating)
        {
            return;
        }

        Vector2 exitPoint = GlobalPosition;
        LogPenetration($"Exiting penetration at {exitPoint} after traveling {_penetrationDistanceTraveled} pixels through wall");

        // Visual effects disabled as per user request
        // The entry/exit positions couldn't be properly anchored to wall surfaces

        // Apply damage reduction after penetration
        if (!_hasPenetrated)
        {
            _damageMultiplier *= PostPenetrationDamageMultiplier;
            _hasPenetrated = true;
            LogPenetration($"Damage multiplier after penetration: {_damageMultiplier}");
        }

        // Play penetration exit sound
        PlayBulletWallHitSound();

        // Reset penetration state
        _isPenetrating = false;
        _penetratingBody = null;
        _penetrationDistanceTraveled = 0.0f;

        // Destroy bullet after successful penetration
        // Bullets don't continue flying after penetrating a wall
        QueueFree();
    }

    /// <summary>
    /// Spawns a dust effect at the specified position.
    /// </summary>
    /// <param name="position">Position to spawn the dust.</param>
    /// <param name="direction">Direction for the dust particles.</param>
    private void SpawnDustEffect(Vector2 position, Vector2 direction)
    {
        var impactManager = GetNodeOrNull("/root/ImpactEffectsManager");
        if (impactManager != null && impactManager.HasMethod("spawn_dust_effect"))
        {
            impactManager.Call("spawn_dust_effect", position, direction, Variant.CreateFrom((Resource?)null));
        }
    }

    /// <summary>
    /// Spawns a collision hole (visual trail) from entry to exit point.
    /// </summary>
    /// <param name="entryPoint">Where the bullet entered the wall.</param>
    /// <param name="exitPoint">Where the bullet exited the wall.</param>
    private void SpawnCollisionHole(Vector2 entryPoint, Vector2 exitPoint)
    {
        var impactManager = GetNodeOrNull("/root/ImpactEffectsManager");
        if (impactManager == null)
        {
            return;
        }

        if (impactManager.HasMethod("spawn_collision_hole"))
        {
            impactManager.Call("spawn_collision_hole", entryPoint, exitPoint, Direction, Variant.CreateFrom((Resource?)null));
            LogPenetration($"Collision hole spawned from {entryPoint} to {exitPoint}");
        }
    }

    /// <summary>
    /// Returns whether the bullet has penetrated at least one wall.
    /// </summary>
    public bool HasPenetrated() => _hasPenetrated;

    /// <summary>
    /// Returns whether the bullet is currently penetrating a wall.
    /// </summary>
    public bool IsPenetrating() => _isPenetrating;

    /// <summary>
    /// Returns the distance traveled through walls while penetrating.
    /// </summary>
    public float GetPenetrationDistance() => _penetrationDistanceTraveled;
}
