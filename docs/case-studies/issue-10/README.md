# Case Study: Issue #10 - Enemy AI Not Working

## Problem Description

After implementing tactical AI improvements (cover, flanking, suppression), enemies stopped functioning properly. They:
- Don't shoot at the player
- Don't move (patrol or guard)
- Don't take damage from player bullets

## Root Cause Analysis

### Primary Bug: ThreatSphere Intercepting Bullets

**Severity: Critical**

The new ThreatSphere Area2D (for detecting suppression) is intercepting all bullets before they can reach their intended targets.

#### Technical Details

The ThreatSphere is dynamically created in `_setup_threat_sphere()` with:
```gdscript
_threat_sphere.collision_layer = 0
_threat_sphere.collision_mask = 16  # Detect projectiles (layer 5)
```

The bullet (Area2D) has:
```gdscript
collision_layer = 16  # projectiles
collision_mask = 38   # enemies + obstacles + targets
```

#### How Godot 4 Area2D Collision Works

According to [Godot documentation and bug reports](https://github.com/godotengine/godot/issues/26139):
> "If the above example is done with 2 Area2Ds, then both receive the signal."

When two Area2Ds overlap and at least one can detect the other, **BOTH** receive the `area_entered` signal. This is different from body-area collision.

#### The Bug Sequence

1. Player shoots bullet at enemy
2. Bullet enters enemy's ThreatSphere (100px radius)
3. ThreatSphere detects bullet (intended behavior)
4. **BUT** bullet ALSO receives `area_entered` signal
5. Bullet's `_on_area_entered` calls `queue_free()` on ANY area hit
6. Bullet is destroyed before reaching the HitArea
7. Enemy takes no damage

#### Code Evidence

In `bullet.gd`:
```gdscript
func _on_area_entered(area: Area2D) -> void:
    # Hit another area (like a target)
    if area.has_method("on_hit"):
        area.on_hit()
    queue_free()  # ALWAYS destroys bullet, even for ThreatSphere
```

The bullet destroys itself when entering ANY Area2D, even if that area doesn't have `on_hit()`.

### Secondary Bug: Own Bullet Detection

**Severity: Medium**

The ThreatSphere incorrectly detects the enemy's OWN bullets as threats.

```gdscript
func _on_threat_area_entered(area: Area2D) -> void:
    if area.get_parent() != self:  # This check doesn't work
        _bullets_in_threat_sphere.append(area)
```

Since bullets are added to `get_tree().current_scene`, their parent is the scene root (e.g., TestTier), not the enemy. The check `area.get_parent() != self` is always true, so the enemy's own bullets trigger suppression behavior.

### Potential Issue: COMBAT State Missing Velocity

**Severity: Low**

In `_process_combat_state()`, velocity is never set. This could cause movement issues if the enemy was moving before entering combat.

## Impact Assessment

| Issue | Impact | Affected Behavior |
|-------|--------|-------------------|
| ThreatSphere bullet interception | Critical | Enemies can't take damage |
| Own bullet detection | Medium | Enemies immediately seek cover when shooting |
| Missing velocity reset | Low | Minor movement glitches |

## Proposed Solutions

### Solution 1: Fix Bullet Detection Logic

Modify `bullet.gd` to only destroy on hitting areas with `on_hit()`:

```gdscript
func _on_area_entered(area: Area2D) -> void:
    if area.has_method("on_hit"):
        area.on_hit()
        queue_free()
    # Don't destroy if hitting non-target areas like ThreatSphere
```

**Pros:** Simple fix, preserves suppression functionality
**Cons:** Bullets pass through ThreatSphere (intended for detection only)

### Solution 2: Use Different Collision Layer for ThreatSphere

Create a new collision layer (layer 7) specifically for threat detection that bullets don't interact with destructively.

**Pros:** Clean separation of concerns
**Cons:** Adds complexity, requires project configuration changes

### Solution 3: Track Bullet Ownership

Add bullet ownership tracking to prevent self-suppression:

```gdscript
# In bullet.gd
var owner_id: int = -1

# In enemy.gd when shooting
bullet.owner_id = get_instance_id()

# In threat sphere detection
func _on_threat_area_entered(area: Area2D) -> void:
    if area.has_method("owner_id") and area.owner_id == get_instance_id():
        return  # Ignore own bullets
    _bullets_in_threat_sphere.append(area)
```

**Pros:** Accurately tracks bullet ownership
**Cons:** More code changes required

## Recommended Solution

**Use Solution 1** as the primary fix because:
1. It's the simplest change
2. It fixes the critical bug (enemies not taking damage)
3. ThreatSpheres are meant for detection only, not to stop bullets

Additionally, implement **Solution 3** to fix the self-suppression issue.

## References

- [Godot Forum: Area2D collision signal being received without having collision layer in mask](https://github.com/godotengine/godot/issues/26139)
- [Godot Forum: Area2D doesn't detect CharacterBody2D](https://forum.godotengine.org/t/area2d-doesnt-detect-characterbody2d-collision-is-not-working/87187)
- [Godot Documentation: Using Area2D](https://docs.godotengine.org/en/stable/tutorials/physics/using_area_2d.html)
- [Godot Forum: Collision Layers and Masks in Godot 4](https://www.gotut.net/collision-layers-and-masks-in-godot-4/)

## Follow-up Issues (Update #2)

### Issue: Enemies Not Properly Hiding in Cover

**Reported by:** User (PR comment)
**Severity:** Medium

#### Problem Description

Enemies were seeking cover positions but not actually hiding from the player's line of sight. The user noted: "enemies are not hiding in cover - they should go to cover until they are hidden from the player's direct line of sight (rays fired in all directions from the player should stop hitting them)."

#### Root Cause

The original cover-finding algorithm (`_find_cover_position()`) used a scoring system based on:
1. Distance to cover (closer = better)
2. Dot product of cover direction vs player direction (blocking score)

**However**, it never actually verified that the cover position would hide the enemy from the player. The scoring was an approximation that didn't guarantee true line-of-sight blocking.

#### Technical Fix

Added two new functions:
1. `_is_visible_from_player()` - Uses physics raycasting to check if player can see the enemy
2. `_is_position_visible_from_player(pos)` - Checks if a specific position is visible to the player

Modified `_find_cover_position()` to:
1. Prioritize positions that are actually hidden (verified by raycasting)
2. Use a heavy score bonus (10.0) for hidden positions
3. Only accept non-hidden positions if no hidden cover is available

Modified `_process_seeking_cover_state()` to:
1. Check if enemy is hidden before transitioning to IN_COVER state
2. Keep seeking better cover if reached destination but still visible
3. Only transition to cover state when truly hidden from player

### Issue: GDScript Warnings

**Reported by:** User (PR comment)
**Severity:** Low

#### Problem Description

The Godot editor reported several warnings about unused variables and parameters:
- Line 189: `_available_covers` - unused private class variable
- Lines 391, 417, 450, 474, 510: `delta` parameters unused in state processing functions

#### Fix

1. Removed `_available_covers` variable (was a placeholder for future GOAP integration)
2. Prefixed unused `delta` parameters with underscore (`_delta`) to suppress warnings

### Issue: Missing Laser Sight

**Reported by:** User (PR comment)
**Severity:** Investigation Required

#### Investigation

The laser sight feature (from Issue #8) exists in the codebase at `Scripts/Weapons/AssaultRifle.cs`. The files are identical in both `main` and the issue branch.

**Conclusion:** This is likely a build/export issue, not a code issue. The laser sight code is present and should work when the game is properly built from the repository.

## Test Plan

1. Launch game and verify enemies patrol/guard normally
2. Shoot at enemy - verify damage is applied (health decreases, flash effect)
3. Shoot near enemy (not at them) - verify suppression triggers
4. Stop shooting near enemy - verify they emerge from cover after 2s
5. Verify enemy bullets don't cause self-suppression
6. Verify all existing AI behaviors work (shooting, aiming, movement)
7. **New:** Verify enemies seek cover until truly hidden from player
8. **New:** Verify no GDScript warnings in the editor
