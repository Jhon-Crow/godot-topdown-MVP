using Godot;
using System.Collections.Generic;

namespace GodotTopDownTemplate.Projectiles;

/// <summary>
/// Static helper for breaker bullet detonation logic (Issue #678).
/// Shared by Bullet.cs and ShotgunPellet.cs to avoid code duplication.
///
/// Breaker bullets detonate 95px before hitting a wall, alive enemy, or RPG rocket,
/// dealing 1 damage in a 15px radius and spawning shrapnel in a forward cone.
/// </summary>
public static class BreakerDetonation
{
    /// <summary>
    /// Distance in pixels ahead of the bullet at which to trigger breaker detonation.
    /// </summary>
    public const float DetonationDistance = 95.0f;

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
    /// Widened to 45° (Issue #1634) so the proximity fuse triggers over a broader arc,
    /// giving shrapnel a better chance to hit targets that are slightly off-axis.
    /// </summary>
    public const float ShrapnelHalfAngle = 45.0f;

    /// <summary>
    /// Minimum travel distance (pixels) before the enemy-cone proximity fuse can trigger (Issue #1634).
    /// Prevents immediate detonation when enemies are within the cone at the moment of firing.
    /// The wall check is still active from spawn — only the enemy cone is gated.
    /// </summary>
    public const float ArmingDistance = 40.0f;

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
    /// Cached shrapnel scene (loaded once per process lifetime).
    /// </summary>
    private static PackedScene? _shrapnelScene;
    private static bool _shrapnelSceneLoaded;

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
    /// Checks if a wall is within detonation distance ahead (straight raycast), or if an alive
    /// enemy/RPG rocket is within the shrapnel cone sector (Issue #1634: proximity fuse should
    /// detonate early when a target enters the sector of future shrapnel).
    /// </summary>
    /// <param name="projectile">The bullet/pellet Area2D node.</param>
    /// <param name="direction">Normalized direction of travel.</param>
    /// <param name="damage">Base damage of the projectile.</param>
    /// <param name="damageMultiplier">Damage multiplier (e.g., from ricochets).</param>
    /// <param name="shooterId">Instance ID of the shooter (to prevent self-damage).</param>
    /// <param name="isPenetrating">Whether the bullet is currently penetrating a wall.</param>
    /// <param name="distanceTraveled">Distance the bullet has traveled since spawn (for arming).</param>
    /// <returns>True if detonation occurred, false otherwise.</returns>
    public static bool CheckAndDetonate(
        Area2D projectile,
        Vector2 direction,
        float damage,
        float damageMultiplier,
        ulong shooterId,
        bool isPenetrating,
        float distanceTraveled = 0.0f)
    {
        // Don't detonate while penetrating a wall
        if (isPenetrating)
        {
            return false;
        }

        var spaceState = projectile.GetWorld2D()?.DirectSpaceState;
        if (spaceState == null)
        {
            return false;
        }

        // 1. Raycast forward for wall detection (straight ahead only).
        var rayStart = projectile.GlobalPosition;
        var rayEnd = projectile.GlobalPosition + direction * DetonationDistance;

        var wallQuery = PhysicsRayQueryParameters2D.Create(rayStart, rayEnd);
        wallQuery.CollisionMask = projectile.CollisionMask;
        wallQuery.Exclude = new Godot.Collections.Array<Rid> { projectile.GetRid() };

        var wallResult = spaceState.IntersectRay(wallQuery);

        if (wallResult.Count > 0)
        {
            var collider = (Node2D)wallResult["collider"];
            if (collider is StaticBody2D || collider is TileMap)
            {
                Detonate(projectile, direction, damage, damageMultiplier, shooterId);
                return true;
            }
        }

        // 2. Cone sector check for enemies and RPG rockets (Issues #1634, #1955).
        // Gated by arming distance: the cone fuse only activates after ArmingDistance pixels,
        // preventing immediate detonation when targets are close to the player at fire time.
        if (distanceTraveled >= ArmingDistance)
        {
            if (CheckEnemyInShrapnelCone(projectile, direction, damage, damageMultiplier, shooterId))
            {
                return true;
            }
            if (CheckRpgRocketInShrapnelCone(projectile, direction, damage, damageMultiplier, shooterId))
            {
                return true;
            }
        }

        return false;
    }

    /// <summary>
    /// Returns true (and triggers detonation) if any alive enemy is within the shrapnel cone sector
    /// AND has clear line of sight from the projectile (no wall in between).
    /// The cone is defined by DetonationDistance (radius) and ShrapnelHalfAngle (half-angle from
    /// the projectile's travel direction).
    /// LOS check prevents premature detonation against enemies through walls (Issue #1634).
    /// </summary>
    private static bool CheckEnemyInShrapnelCone(
        Area2D projectile,
        Vector2 direction,
        float damage,
        float damageMultiplier,
        ulong shooterId)
    {
        var tree = projectile.GetTree();
        if (tree == null) return false;

        var enemies = tree.GetNodesInGroup("enemies");

        foreach (var enemy in enemies)
        {
            if (enemy is not Node2D enemyNode) continue;
            if (!enemyNode.HasMethod("is_alive") || !enemyNode.Call("is_alive").AsBool()) continue;

            if (TargetInShrapnelCone(projectile, direction, enemyNode.GlobalPosition))
            {
                Detonate(projectile, direction, damage, damageMultiplier, shooterId);
                return true;
            }
        }

        return false;
    }

    /// <summary>
    /// Returns true (and triggers detonation) if any RPG rocket is within the shrapnel cone sector.
    /// Issue #1955: proximity-fuse bullets should detonate before RPG rockets too.
    /// </summary>
    private static bool CheckRpgRocketInShrapnelCone(
        Area2D projectile,
        Vector2 direction,
        float damage,
        float damageMultiplier,
        ulong shooterId)
    {
        var tree = projectile.GetTree();
        if (tree == null) return false;

        var rockets = tree.GetNodesInGroup("rpg_rockets");

        foreach (var rocket in rockets)
        {
            if (rocket is not Node2D rocketNode) continue;
            if (rocketNode == projectile) continue;

            if (TargetInShrapnelCone(projectile, direction, rocketNode.GlobalPosition))
            {
                Detonate(projectile, direction, damage, damageMultiplier, shooterId);
                return true;
            }
        }

        return false;
    }

    /// <summary>
    /// Returns true when a target point is in the breaker cone with clear line of sight.
    /// </summary>
    private static bool TargetInShrapnelCone(Area2D projectile, Vector2 direction, Vector2 targetPosition)
    {
        var toTarget = targetPosition - projectile.GlobalPosition;
        float dist = toTarget.Length();
        if (dist > DetonationDistance || dist <= 0f) return false;

        float cosHalfAngle = Mathf.Cos(Mathf.DegToRad(ShrapnelHalfAngle));
        if ((toTarget / dist).Dot(direction) < cosHalfAngle) return false;

        // Only detonate if there is no wall between the bullet and target.
        // Without this check, bullets detonate against targets through walls.
        return HasLineOfSight(projectile, projectile.GlobalPosition, targetPosition);
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

        var poolManager = projectile.GetNodeOrNull("/root/ProjectilePoolManager");
        bool canUsePool = poolManager != null && poolManager.HasMethod("get_breaker_shrapnel");
        var shrapnelScene = GetShrapnelScene();
        if (shrapnelScene == null && !canUsePool)
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

            var spawnPosition = center + shrapnelDirection * 5.0f;
            var shrapnelSpeed = (float)GD.RandRange(1400.0, 2200.0);

            if (canUsePool)
            {
                var pooledVariant = poolManager!.Call("get_breaker_shrapnel");
                if (pooledVariant.Obj is Node pooledShrapnel && pooledShrapnel.HasMethod("pool_activate"))
                {
                    pooledShrapnel.Call("pool_activate", spawnPosition, shrapnelDirection, (int)shooterId, ShrapnelDamage, shrapnelSpeed);
                    continue;
                }
            }

            var fallbackScene = shrapnelScene ?? GetShrapnelScene();
            if (fallbackScene == null)
            {
                continue;
            }

            var shrapnel = fallbackScene.Instantiate<Node2D>();
            if (shrapnel == null)
            {
                continue;
            }

            shrapnel.GlobalPosition = spawnPosition;
            shrapnel.Set("direction", shrapnelDirection);
            shrapnel.Set("source_id", (int)shooterId);
            shrapnel.Set("damage", ShrapnelDamage);
            shrapnel.Set("speed", shrapnelSpeed);

            // Use call_deferred for performance (batch scene tree changes)
            scene.CallDeferred("add_child", shrapnel);
        }
    }
}
