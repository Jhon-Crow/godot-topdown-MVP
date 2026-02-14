using Godot;

namespace GodotTopDownTemplate.Projectiles;

/// <summary>
/// Shared utility methods for the homing projectile system (Issue #704, #709).
/// Extracted to avoid duplicating the aim-line targeting algorithm
/// across Bullet, ShotgunPellet, and SniperRifle.
/// Includes line-of-sight checking to prevent homing through walls (Issue #709).
/// </summary>
public static class HomingUtils
{
    /// <summary>
    /// Default maximum perpendicular distance (in pixels) from the aim line
    /// for an enemy to be considered a valid target.
    /// </summary>
    public const float DefaultMaxPerpDistance = 500.0f;

    /// <summary>
    /// Default maximum angle (in radians) from the aim direction
    /// for an enemy to be considered a valid target (110 degrees).
    /// </summary>
    public static readonly float DefaultMaxAngle = Mathf.DegToRad(110.0f);

    /// <summary>
    /// Collision mask for walls/obstacles (layer 3 = mask 4).
    /// Used for line-of-sight checks to prevent homing through walls.
    /// </summary>
    private const uint WallCollisionMask = 4;

    /// <summary>
    /// Enable debug logging for homing calculations.
    /// </summary>
    private const bool DebugHoming = false;

    /// <summary>
    /// Checks if there is a clear line of sight between two positions (Issue #709).
    /// Uses a physics raycast against obstacles (collision layer 3 = mask 4) to detect walls.
    /// Returns false if a wall blocks the path, preventing projectiles from homing into walls.
    /// </summary>
    /// <param name="world">The World2D to perform the raycast in.</param>
    /// <param name="from">Starting position of the raycast.</param>
    /// <param name="to">Target position to check visibility to.</param>
    /// <returns>True if there's a clear line of sight, false if blocked by a wall.</returns>
    public static bool HasLineOfSightToTarget(World2D? world, Vector2 from, Vector2 to)
    {
        var spaceState = world?.DirectSpaceState;
        if (spaceState == null)
        {
            return true; // Can't check, assume clear
        }

        var query = PhysicsRayQueryParameters2D.Create(from, to);
        query.CollisionMask = WallCollisionMask; // Layer 3 = obstacles/walls only
        query.CollideWithAreas = false;
        query.CollideWithBodies = true;

        var result = spaceState.IntersectRay(query);
        return result.Count == 0; // True if no wall in the way
    }

    /// <summary>
    /// Finds the enemy closest to the player's aim line.
    /// Uses perpendicular distance from the aim ray to score enemies,
    /// with actual distance as a tiebreaker (weight 0.1).
    /// Only considers enemies within <paramref name="maxAngle"/> of the aim direction
    /// and within <paramref name="maxPerpDistance"/> perpendicular distance.
    /// Skips enemies blocked by walls (Issue #709).
    /// </summary>
    /// <param name="enemies">Collection of enemy nodes (from "enemies" group).</param>
    /// <param name="shooterOrigin">The player's position when the projectile was fired.</param>
    /// <param name="aimDirection">The player's normalized aim direction.</param>
    /// <param name="maxAngle">Max angle from aim direction in radians (default: 110 degrees).</param>
    /// <param name="maxPerpDistance">Max perpendicular distance in pixels (default: 500).</param>
    /// <param name="world">Optional World2D for line-of-sight checks. If null, LOS checks are skipped.</param>
    /// <param name="raycastOrigin">Optional origin for LOS raycast (e.g., projectile position). Uses shooterOrigin if not provided.</param>
    /// <returns>Global position of the best target, or Vector2.Zero if none found.</returns>
    public static Vector2 FindEnemyNearestToAimLine(
        Godot.Collections.Array<Node> enemies,
        Vector2 shooterOrigin,
        Vector2 aimDirection,
        float maxAngle = -1f,
        float maxPerpDistance = DefaultMaxPerpDistance,
        World2D? world = null,
        Vector2? raycastOrigin = null)
    {
        if (maxAngle < 0f)
        {
            maxAngle = DefaultMaxAngle;
        }

        var bestTarget = Vector2.Zero;
        float bestScore = float.PositiveInfinity;
        Vector2 losOrigin = raycastOrigin ?? shooterOrigin;

        foreach (var enemy in enemies)
        {
            if (enemy is not Node2D enemyNode)
            {
                continue;
            }

            // Skip dead enemies
            if (enemyNode.HasMethod("is_alive"))
            {
                bool alive = (bool)enemyNode.Call("is_alive");
                if (!alive)
                {
                    continue;
                }
            }

            Vector2 toEnemy = enemyNode.GlobalPosition - shooterOrigin;
            float distToEnemy = toEnemy.Length();
            if (distToEnemy < 1.0f)
            {
                continue; // Too close, skip
            }

            // Check angle from aim direction
            float angle = Mathf.Abs(aimDirection.AngleTo(toEnemy.Normalized()));
            if (angle > maxAngle)
            {
                continue; // Too far off from aim direction
            }

            // Calculate perpendicular distance from the aim line
            // perpDist = |toEnemy × aimDirection| (cross product magnitude in 2D)
            float perpDist = Mathf.Abs(toEnemy.X * aimDirection.Y - toEnemy.Y * aimDirection.X);
            if (perpDist > maxPerpDistance)
            {
                continue; // Too far from aim line
            }

            // Skip enemies behind walls (Issue #709)
            if (world != null && !HasLineOfSightToTarget(world, losOrigin, enemyNode.GlobalPosition))
            {
                if (DebugHoming)
                {
                    GD.Print($"[HomingUtils] Skipping enemy {enemyNode.Name} - wall blocks line of sight");
                }
                continue;
            }

            // Score: prioritize closeness to aim line, with distance as tiebreaker
            float score = perpDist + distToEnemy * 0.1f;
            if (score < bestScore)
            {
                bestScore = score;
                bestTarget = enemyNode.GlobalPosition;
            }
        }

        return bestTarget;
    }
}
