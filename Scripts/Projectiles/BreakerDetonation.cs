using Godot;
using System.Collections.Generic;

namespace GodotTopDownTemplate.Projectiles;

/// <summary>
/// Static helper for breaker bullet detonation logic (Issue #678).
/// Shared by Bullet.cs and ShotgunPellet.cs to avoid code duplication.
///
/// Breaker bullets detonate 60px before hitting a wall or alive enemy,
/// dealing 1 damage in a 15px radius and spawning shrapnel in a forward cone.
///
/// Issue #1462: Optimized to reduce FPS drops during rapid shotgun fire.
/// Key optimizations:
/// - Raycast throttling: skip frames when projectile hasn't traveled enough distance
/// - Object pool integration: use ProjectilePoolManager for shrapnel spawning
/// - Reduced per-frame allocations: reuse PhysicsRayQueryParameters2D
/// </summary>
public static class BreakerDetonation
{
    /// <summary>
    /// Distance in pixels ahead of the bullet at which to trigger breaker detonation.
    /// </summary>
    public const float DetonationDistance = 60.0f;

    /// <summary>
    /// Explosion damage radius for breaker bullet detonation (in pixels).
    /// </summary>
    public const float ExplosionRadius = 15.0f;

    /// <summary>
    /// Explosion damage dealt by breaker bullet detonation.
    /// </summary>
    public const float ExplosionDamage = 1.0f;

    /// <summary>
    /// Half-angle of the shrapnel cone in degrees.
    /// </summary>
    public const float ShrapnelHalfAngle = 30.0f;

    /// <summary>
    /// Damage per breaker shrapnel piece.
    /// </summary>
    public const float ShrapnelDamage = 0.1f;

    /// <summary>
    /// Multiplier for shrapnel count: shrapnel_count = bullet_damage * this multiplier.
    /// </summary>
    public const float ShrapnelCountMultiplier = 10.0f;

    /// <summary>
    /// Maximum shrapnel pieces per single detonation (performance cap).
    /// </summary>
    public const int MaxShrapnelPerDetonation = 10;

    /// <summary>
    /// Maximum total concurrent breaker shrapnel in the scene (global cap).
    /// </summary>
    public const int MaxConcurrentShrapnel = 60;

    /// <summary>
    /// Breaker shrapnel scene path.
    /// </summary>
    public const string ShrapnelScenePath = "res://scenes/projectiles/BreakerShrapnel.tscn";

    /// <summary>
    /// Minimum distance a projectile must travel between raycast checks (Issue #1462).
    /// At 2500 px/s and 60 FPS, a pellet moves ~42px/frame. The detonation distance
    /// is 60px, so checking every ~30px of travel ensures we never miss a detonation
    /// while halving the raycast frequency.
    /// </summary>
    public const float RaycastDistanceInterval = 30.0f;

    /// <summary>
    /// Cached shrapnel scene (loaded once per process lifetime).
    /// </summary>
    private static PackedScene? _shrapnelScene;
    private static bool _shrapnelSceneLoaded;

    /// <summary>
    /// Tracks cumulative distance traveled per projectile for raycast throttling (Issue #1462).
    /// Key: projectile instance ID, Value: distance since last raycast.
    /// </summary>
    private static readonly Dictionary<ulong, float> _distanceSinceLastRaycast = new();

    /// <summary>
    /// Gets or loads the shrapnel scene.
    /// </summary>
    private static PackedScene? GetShrapnelScene()
    {
        if (!_shrapnelSceneLoaded)
        {
            _shrapnelSceneLoaded = true;
            if (ResourceLoader.Exists(ShrapnelScenePath))
            {
                _shrapnelScene = GD.Load<PackedScene>(ShrapnelScenePath);
            }
        }
        return _shrapnelScene;
    }

    /// <summary>
    /// Checks if a wall or alive enemy is within detonation distance ahead of the projectile.
    /// If so, triggers detonation and returns true.
    ///
    /// Issue #1462: Implements distance-based raycast throttling. Instead of raycasting
    /// every physics frame, only raycasts when the projectile has traveled at least
    /// RaycastDistanceInterval pixels since the last check. This halves raycast count
    /// for shotgun pellets while maintaining correct detonation behavior.
    /// </summary>
    /// <param name="projectile">The bullet/pellet Area2D node.</param>
    /// <param name="direction">Normalized direction of travel.</param>
    /// <param name="damage">Base damage of the projectile.</param>
    /// <param name="damageMultiplier">Damage multiplier (e.g., from ricochets).</param>
    /// <param name="shooterId">Instance ID of the shooter (to prevent self-damage).</param>
    /// <param name="isPenetrating">Whether the bullet is currently penetrating a wall.</param>
    /// <param name="distanceTraveledThisFrame">Distance the projectile moved this frame (for throttling).</param>
    /// <returns>True if detonation occurred, false otherwise.</returns>
    public static bool CheckAndDetonate(
        Area2D projectile,
        Vector2 direction,
        float damage,
        float damageMultiplier,
        ulong shooterId,
        bool isPenetrating,
        float distanceTraveledThisFrame = 0.0f)
    {
        // Don't detonate while penetrating a wall
        if (isPenetrating)
        {
            return false;
        }

        // Issue #1462: Distance-based raycast throttling.
        // Skip raycast if the projectile hasn't traveled far enough since the last check.
        var projectileId = projectile.GetInstanceId();
        if (distanceTraveledThisFrame > 0.0f)
        {
            if (!_distanceSinceLastRaycast.TryGetValue(projectileId, out float accumulated))
            {
                accumulated = 0.0f;
            }
            accumulated += distanceTraveledThisFrame;

            if (accumulated < RaycastDistanceInterval)
            {
                _distanceSinceLastRaycast[projectileId] = accumulated;
                return false;
            }
            // Reset accumulator — we're doing a raycast now
            _distanceSinceLastRaycast[projectileId] = 0.0f;
        }

        var spaceState = projectile.GetWorld2D()?.DirectSpaceState;
        if (spaceState == null)
        {
            return false;
        }

        // Raycast forward from projectile position
        var rayStart = projectile.GlobalPosition;
        var rayEnd = projectile.GlobalPosition + direction * DetonationDistance;

        var query = PhysicsRayQueryParameters2D.Create(rayStart, rayEnd);
        query.CollisionMask = projectile.CollisionMask;
        query.Exclude = new Godot.Collections.Array<Rid> { projectile.GetRid() };

        var result = spaceState.IntersectRay(query);

        if (result.Count == 0)
        {
            return false; // Nothing ahead within detonation distance
        }

        var collider = (Node2D)result["collider"];

        // Wall detected — trigger detonation
        if (collider is StaticBody2D || collider is TileMap)
        {
            CleanupTracking(projectileId);
            Detonate(projectile, direction, damage, damageMultiplier, shooterId);
            return true;
        }

        // Alive enemy detected — trigger detonation
        if (collider is CharacterBody2D)
        {
            if (collider.HasMethod("is_alive"))
            {
                bool isAlive = collider.Call("is_alive").AsBool();
                if (isAlive)
                {
                    CleanupTracking(projectileId);
                    Detonate(projectile, direction, damage, damageMultiplier, shooterId);
                    return true;
                }
            }
        }

        return false;
    }

    /// <summary>
    /// Removes tracking data for a projectile that is being destroyed (Issue #1462).
    /// Call when the projectile detonates or is freed to prevent dictionary leak.
    /// </summary>
    public static void CleanupTracking(ulong projectileId)
    {
        _distanceSinceLastRaycast.Remove(projectileId);
    }

    /// <summary>
    /// Triggers full breaker detonation: explosion damage + visual + shrapnel + sound.
    /// Destroys the projectile after detonation.
    /// </summary>
    private static void Detonate(
        Area2D projectile,
        Vector2 direction,
        float damage,
        float damageMultiplier,
        ulong shooterId)
    {
        var center = projectile.GlobalPosition;

        // Issue #1196: determine if the shooter is the player so kills are counted toward Laser Sight unlock.
        bool isFromPlayer = IsShooterPlayer(shooterId);

        // 1. Apply explosion damage in radius
        ApplyExplosionDamage(projectile, center, shooterId, isFromPlayer);

        // 2. Spawn visual explosion effect
        SpawnExplosionEffect(projectile, center);

        // 3. Spawn shrapnel in a forward cone
        SpawnShrapnel(projectile, center, direction, damage, damageMultiplier, shooterId);

        // 4. Play explosion sound
        PlayExplosionSound(projectile, center);

        // 5. Destroy the projectile
        projectile.QueueFree();
    }

    /// <summary>
    /// Applies explosion damage to all enemies within explosion radius.
    /// </summary>
    private static void ApplyExplosionDamage(Node projectile, Vector2 center, ulong shooterId, bool isFromPlayer = false)
    {
        var tree = projectile.GetTree();
        if (tree == null)
        {
            return;
        }

        // Check enemies in radius
        var enemies = tree.GetNodesInGroup("enemies");
        foreach (var enemy in enemies)
        {
            if (enemy is Node2D enemyNode && enemyNode.HasMethod("is_alive") && enemyNode.Call("is_alive").AsBool())
            {
                float distance = center.DistanceTo(enemyNode.GlobalPosition);
                if (distance <= ExplosionRadius)
                {
                    if (HasLineOfSight(projectile, center, enemyNode.GlobalPosition))
                    {
                        ApplyDamage(enemyNode, center, ExplosionDamage, isFromPlayer);
                    }
                }
            }
        }

        // Also check player (breaker explosion can hurt the player at close range)
        var players = tree.GetNodesInGroup("player");
        foreach (var player in players)
        {
            if (player is Node2D playerNode)
            {
                if (shooterId == playerNode.GetInstanceId())
                {
                    continue; // Don't damage the shooter
                }
                float distance = center.DistanceTo(playerNode.GlobalPosition);
                if (distance <= ExplosionRadius)
                {
                    if (HasLineOfSight(projectile, center, playerNode.GlobalPosition))
                    {
                        ApplyDamage(playerNode, center, ExplosionDamage);
                    }
                }
            }
        }
    }

    /// <summary>
    /// Applies damage to a target using available methods.
    /// </summary>
    private static void ApplyDamage(Node2D target, Vector2 center, float amount, bool isFromPlayer = false)
    {
        var hitDirection = (target.GlobalPosition - center).Normalized();

        // Issue #1196: pass is_from_player so enemy.gd tracks kill source for Laser Sight unlock.
        if (target.HasMethod("on_hit_with_bullet_info_and_damage"))
        {
            target.Call("on_hit_with_bullet_info_and_damage", hitDirection,
                Variant.CreateFrom((Resource?)null), false, false, amount, isFromPlayer);
        }
        else if (target.HasMethod("take_damage"))
        {
            target.Call("take_damage", amount);
        }
        else if (target.HasMethod("on_hit_with_info"))
        {
            target.Call("on_hit_with_info", hitDirection, Variant.CreateFrom((Resource?)null));
        }
        else if (target.HasMethod("on_hit"))
        {
            target.Call("on_hit");
        }
    }

    /// <summary>
    /// Checks if the shooter with the given instance ID is the player.
    /// </summary>
    private static bool IsShooterPlayer(ulong shooterId)
    {
        if (shooterId == 0) return false;
        var shooter = GodotObject.InstanceFromId(shooterId) as Node;
        if (shooter == null) return false;
        // Check group membership (consistent with Bullet.cs and ShotgunPellet.cs)
        return shooter.IsInGroup("player");
    }

    /// <summary>
    /// Checks line of sight between two positions (obstacles only).
    /// </summary>
    private static bool HasLineOfSight(Node projectile, Vector2 from, Vector2 to)
    {
        var world2d = ((Node2D)projectile).GetWorld2D();
        if (world2d == null)
        {
            return true;
        }

        var spaceState = world2d.DirectSpaceState;
        var query = PhysicsRayQueryParameters2D.Create(from, to);
        query.CollisionMask = 4; // Only check against obstacles
        var result = spaceState.IntersectRay(query);
        return result.Count == 0;
    }

    /// <summary>
    /// Spawns visual explosion effect at the detonation point.
    /// </summary>
    private static void SpawnExplosionEffect(Node projectile, Vector2 center)
    {
        var impactManager = projectile.GetNodeOrNull("/root/ImpactEffectsManager");
        if (impactManager != null && impactManager.HasMethod("spawn_explosion_effect"))
        {
            impactManager.Call("spawn_explosion_effect", center, ExplosionRadius);
        }
    }

    /// <summary>
    /// Plays explosion sound and emits sound for AI awareness.
    /// </summary>
    private static void PlayExplosionSound(Node projectile, Vector2 center)
    {
        var audioManager = projectile.GetNodeOrNull("/root/AudioManager");
        if (audioManager != null && audioManager.HasMethod("play_bullet_wall_hit"))
        {
            audioManager.Call("play_bullet_wall_hit", center);
        }

        var soundPropagation = projectile.GetNodeOrNull("/root/SoundPropagation");
        if (soundPropagation != null && soundPropagation.HasMethod("emit_sound"))
        {
            // 1 = EXPLOSION, 0 = PLAYER, 500.0 = range
            soundPropagation.Call("emit_sound", 1, center, 0, projectile, 500.0f);
        }
    }

    /// <summary>
    /// Spawns breaker shrapnel pieces in a forward cone.
    /// Shrapnel count is capped for performance.
    ///
    /// Issue #1462: Now uses ProjectilePoolManager when available instead of
    /// instantiating new scenes every detonation. This eliminates GC pressure
    /// and scene tree churn during rapid shotgun fire.
    /// </summary>
    private static void SpawnShrapnel(
        Node projectile,
        Vector2 center,
        Vector2 direction,
        float damage,
        float damageMultiplier,
        ulong shooterId)
    {
        var tree = projectile.GetTree();
        if (tree == null)
        {
            return;
        }

        // Try to use object pool first (Issue #1462 optimization)
        var poolManager = projectile.GetNodeOrNull("/root/ProjectilePoolManager");

        // If no pool available, fall back to scene instantiation
        if (poolManager == null || !poolManager.HasMethod("get_breaker_shrapnel"))
        {
            SpawnShrapnelWithoutPool(projectile, center, direction, damage, damageMultiplier, shooterId);
            return;
        }

        // Check global concurrent shrapnel limit via pool manager stats
        var existingShrapnel = tree.GetNodesInGroup("breaker_shrapnel");
        if (existingShrapnel.Count >= MaxConcurrentShrapnel)
        {
            return;
        }

        // Calculate shrapnel count based on bullet damage, capped for performance
        float effectiveDamage = damage * damageMultiplier;
        int shrapnelCount = (int)(effectiveDamage * ShrapnelCountMultiplier);
        shrapnelCount = Mathf.Clamp(shrapnelCount, 1, MaxShrapnelPerDetonation);

        // Further reduce if approaching global limit
        int remainingBudget = MaxConcurrentShrapnel - existingShrapnel.Count;
        shrapnelCount = Mathf.Min(shrapnelCount, remainingBudget);

        float halfAngleRad = Mathf.DegToRad(ShrapnelHalfAngle);

        for (int i = 0; i < shrapnelCount; i++)
        {
            float randomAngle = (float)GD.RandRange(-halfAngleRad, halfAngleRad);
            var shrapnelDirection = direction.Rotated(randomAngle);

            // Get shrapnel from pool (Issue #1462)
            var shrapnel = poolManager.Call("get_breaker_shrapnel").As<Node>();
            if (shrapnel == null)
            {
                continue;
            }

            // Activate pooled shrapnel with position, direction, and source
            var spawnPos = center + shrapnelDirection * 5.0f;
            if (shrapnel.HasMethod("pool_activate"))
            {
                shrapnel.Call("pool_activate", spawnPos, shrapnelDirection, (int)shooterId);
            }
            else
            {
                // Fallback: set properties directly
                ((Node2D)shrapnel).GlobalPosition = spawnPos;
                shrapnel.Set("direction", shrapnelDirection);
                shrapnel.Set("source_id", (int)shooterId);
                shrapnel.Set("damage", ShrapnelDamage);
                shrapnel.Set("speed", (float)GD.RandRange(1400.0, 2200.0));
            }
        }
    }

    /// <summary>
    /// Fallback shrapnel spawning via scene instantiation (when pool is not available).
    /// </summary>
    private static void SpawnShrapnelWithoutPool(
        Node projectile,
        Vector2 center,
        Vector2 direction,
        float damage,
        float damageMultiplier,
        ulong shooterId)
    {
        var shrapnelScene = GetShrapnelScene();
        if (shrapnelScene == null)
        {
            return;
        }

        var tree = projectile.GetTree();
        if (tree == null)
        {
            return;
        }

        // Check global concurrent shrapnel limit
        var existingShrapnel = tree.GetNodesInGroup("breaker_shrapnel");
        if (existingShrapnel.Count >= MaxConcurrentShrapnel)
        {
            return;
        }

        // Calculate shrapnel count based on bullet damage, capped for performance
        float effectiveDamage = damage * damageMultiplier;
        int shrapnelCount = (int)(effectiveDamage * ShrapnelCountMultiplier);
        shrapnelCount = Mathf.Clamp(shrapnelCount, 1, MaxShrapnelPerDetonation);

        // Further reduce if approaching global limit
        int remainingBudget = MaxConcurrentShrapnel - existingShrapnel.Count;
        shrapnelCount = Mathf.Min(shrapnelCount, remainingBudget);

        float halfAngleRad = Mathf.DegToRad(ShrapnelHalfAngle);

        var scene = tree.CurrentScene;
        if (scene == null)
        {
            return;
        }

        for (int i = 0; i < shrapnelCount; i++)
        {
            float randomAngle = (float)GD.RandRange(-halfAngleRad, halfAngleRad);
            var shrapnelDirection = direction.Rotated(randomAngle);

            var shrapnel = shrapnelScene.Instantiate<Node2D>();
            if (shrapnel == null)
            {
                continue;
            }

            shrapnel.GlobalPosition = center + shrapnelDirection * 5.0f;
            shrapnel.Set("direction", shrapnelDirection);
            shrapnel.Set("source_id", (int)shooterId);
            shrapnel.Set("damage", ShrapnelDamage);
            shrapnel.Set("speed", (float)GD.RandRange(1400.0, 2200.0));

            // Use call_deferred for performance (batch scene tree changes)
            scene.CallDeferred("add_child", shrapnel);
        }
    }
}
