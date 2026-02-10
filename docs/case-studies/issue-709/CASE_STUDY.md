# Case Study: Issue #709 - Homing Bullets Improvements

## Problem Statement

After the initial fix for Issue #709 (curved sniper trail and wall-aware homing bullets), user reported:
1. Sniper rifle homing not working at all
2. Bullets turning too slowly

## Timeline

1. **PR #706**: Initial homing bullets implementation (cherry-picked)
2. **Commit d98805d8**: Cherry-pick homing bullets for all weapons
3. **Commit 406dfdd2**: Fix curved sniper trail and wall-aware homing bullets
   - Added `HasLineOfSightToTarget()` check to prevent bullets from turning into walls
   - Added curved smoke trail for sniper rifle when homing redirects the shot
4. **User Feedback (2026-02-09)**: Sniper homing broken, bullets too slow

## Root Cause Analysis

### Issue 1: Sniper Rifle Homing Not Working

**Root Cause**: The `HasLineOfSightToTarget()` function was checking line-of-sight from the weapon's `GlobalPosition`, which is at the center of the weapon/player. When the player stands near a wall, the raycast would start very close to or even inside the wall, causing it to immediately fail.

**Code Location**: `Scripts/Weapons/SniperRifle.cs`, lines 910-914

**Before**:
```csharp
// Skip enemies behind walls (Issue #709)
if (!HasLineOfSightToTarget(origin, enemyNode.GlobalPosition))
{
    continue;
}
```

**Problem**: `origin` = `GlobalPosition` (weapon center, potentially inside/near wall)

**Fix**: Start the raycast from the bullet spawn position (offset from weapon):
```csharp
// Skip enemies behind walls (Issue #709)
// Start raycast from bullet spawn position (not weapon center) to avoid hitting walls the player is near
Vector2 raycastStart = origin + toEnemy.Normalized() * BulletSpawnOffset;
if (!HasLineOfSightToTarget(raycastStart, enemyNode.GlobalPosition))
{
    continue;
}
```

### Issue 2: Bullets Turning Too Slowly

**Root Cause**: The homing steering speed was set to 8.0 radians/second, which felt sluggish for the fast-paced gameplay.

**Code Location**:
- `Scripts/Projectiles/Bullet.cs`, line 1328
- `Scripts/Projectiles/ShotgunPellet.cs`, line 140

**Fix**: Increased `_homingSteerSpeed` from 8.0 to 15.0 radians/second (nearly doubled).

## Files Modified

1. **Scripts/Weapons/SniperRifle.cs**
   - Fixed raycast start position for line-of-sight check

2. **Scripts/Projectiles/Bullet.cs**
   - Increased `_homingSteerSpeed` from 8.0 to 15.0

3. **Scripts/Projectiles/ShotgunPellet.cs**
   - Increased `_homingSteerSpeed` from 8.0 to 15.0

## Lessons Learned

1. When implementing wall collision checks for hitscan/raycast weapons, always account for where the actual projectile would originate (muzzle), not the weapon center
2. Player feedback about "feeling" (like bullet responsiveness) is important - what works in theory may not feel right in practice
3. Debugging hitscan weapons requires different approach than projectile weapons since there's no visible projectile to observe

## Test Plan

- [ ] Verify sniper rifle homing works when firing at enemies in line-of-sight
- [ ] Verify bullets turn faster toward enemies
- [ ] Verify bullets still don't turn into walls when enemy is behind obstacle
- [ ] Test with player standing near walls to ensure raycast fix works
