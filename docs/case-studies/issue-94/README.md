# Case Study: Issue #94 - AI Enemies Shooting Through Walls in COMBAT State

## Issue Summary

**Issue URL:** https://github.com/Jhon-Crow/godot-topdown-MVP/issues/94

**Problem Description (Russian):**
> враги находясь за тонким укрытием или сбоку укрытия начинают стрелять в сторону игрока, при этом все снаряды попадают в стену, в которую направлен выстрел.
> добавь проверку чтоб избежать стрельбы в стену, к которой враг находится впритык.
> сделай надёжный выход врага из укрытия (чтоб выход из укрытия прекращался только тогда, когда враг точно может попасть в игрока).

**English Translation:**
> Enemies behind thin cover or at the side of cover start shooting toward the player, but all projectiles hit the wall they're aiming through.
> Add a check to prevent shooting into a wall that the enemy is right next to.
> Make a reliable cover exit mechanism (so that exiting cover only stops when the enemy can definitely hit the player).

## Timeline and Sequence of Events

### Current Behavior Flow

1. **Enemy detects player** → `_can_see_player` becomes true via raycast from enemy center to player
2. **Enemy enters COMBAT state** → Approaches player and starts shooting phase
3. **Enemy positioned near wall/cover edge** → Enemy is close to or touching thin cover
4. **Shooting logic executes** → `_shoot()` is called
5. **Shot validation** → `_should_shoot_at_target()` checks:
   - `_is_firing_line_clear_of_friendlies()` - checks for friendly fire
   - `_is_shot_clear_of_cover()` - checks if obstacles block the shot
6. **BUG: Shot appears clear** → Raycast from `bullet_spawn_offset` (30px ahead) misses the adjacent wall
7. **Bullet spawns and hits wall** → Bullet spawns at offset position and immediately collides

## Root Cause Analysis

### Primary Issue: Bullet Spawn Point Validation

**Location:** `scripts/objects/enemy.gd:1893-1917` (`_is_shot_clear_of_cover()`)

The current implementation:
```gdscript
func _is_shot_clear_of_cover(target_position: Vector2) -> bool:
    var direction := (target_position - global_position).normalized()
    var distance := global_position.distance_to(target_position)

    var space_state := get_world_2d().direct_space_state
    var query := PhysicsRayQueryParameters2D.new()
    query.from = global_position + direction * bullet_spawn_offset  # Start from bullet spawn point
    query.to = target_position
    query.collision_mask = 4  # Only check obstacles (layer 3)
    # ... rest of validation
```

**Problem:** The raycast starts from `global_position + direction * bullet_spawn_offset`, which is 30 pixels ahead of the enemy's center. When the enemy is positioned:
- Flush against a wall
- At the side of thin cover
- Very close to any obstacle

The raycast starting point may already be **past** the wall (on the wrong side), or the short distance from enemy center to bullet spawn point crosses through the wall undetected.

### Missing Check: Enemy-to-Spawn-Point Wall Detection

There is no check to verify that the path from the enemy's center to the bullet spawn point is clear. The enemy might be:
1. Standing right next to a wall on their side
2. Positioned at the corner of cover
3. Against thin cover where the 30px offset puts the spawn point inside or past the wall

### Secondary Issue: Cover Exit Reliability

The cover exit mechanism in `_process_in_cover_state()` and `_process_seeking_cover_state()` uses `_is_visible_from_player()` to detect flanking. However:
1. It doesn't validate if the enemy's shooting direction is clear
2. An enemy might be visible to the player but still unable to hit them due to adjacent geometry
3. The "exposed" phase starts without confirming a clear firing lane

## Proposed Solution

### Fix 1: Add Immediate Obstacle Check

Add a check for walls directly in front of the enemy (between enemy center and bullet spawn point):

```gdscript
## Check if there's an obstacle immediately in front of the enemy that would block bullets.
## This prevents shooting into walls that the enemy is flush against.
func _is_immediate_path_clear(direction: Vector2) -> bool:
    var space_state := get_world_2d().direct_space_state
    var query := PhysicsRayQueryParameters2D.new()
    query.from = global_position
    query.to = global_position + direction * (bullet_spawn_offset + 10.0)  # Check slightly past spawn point
    query.collision_mask = 4  # Only check obstacles (layer 3)
    query.exclude = [get_rid()]

    var result := space_state.intersect_ray(query)
    return result.is_empty()
```

### Fix 2: Update Shot Validation

Modify `_should_shoot_at_target()` to include the immediate path check:

```gdscript
func _should_shoot_at_target(target_position: Vector2) -> bool:
    var direction := (target_position - global_position).normalized()

    # NEW: Check if the immediate path to bullet spawn point is clear
    if not _is_immediate_path_clear(direction):
        _log_debug("Shot blocked: wall immediately in front of enemy")
        return false

    # Check if friendlies are in the way
    if not _is_firing_line_clear_of_friendlies(target_position):
        return false

    # Check if cover blocks the shot
    if not _is_shot_clear_of_cover(target_position):
        return false

    return true
```

### Fix 3: Reliable Cover Exit Mechanism

Update the combat exposed phase to verify shooting lane before staying exposed:

```gdscript
# In _process_combat_state(), before staying in exposed phase:
if _combat_exposed:
    # Verify we can actually hit the player before continuing to shoot
    if _player:
        var direction := (_player.global_position - global_position).normalized()
        if not _is_immediate_path_clear(direction):
            # Can't hit player from here, seek better position
            _combat_exposed = false
            _transition_to_seeking_cover()
            return
```

## Impact Assessment

### Files Modified
- `scripts/objects/enemy.gd`

### Risk Level: Low
- Changes are additive (new validation checks)
- No existing functionality is removed
- Behavioral change only prevents clearly incorrect behavior (shooting into walls)

## Testing Strategy

1. **Unit Test:** Create test scene with enemy next to thin wall, verify no shooting
2. **Edge Cases:**
   - Enemy flush against wall, player on other side
   - Enemy at corner of cover
   - Enemy at edge of thin pillar
3. **Regression Test:** Verify normal combat behavior unchanged when no walls nearby

## References

- Issue: https://github.com/Jhon-Crow/godot-topdown-MVP/issues/94
- Main file: `scripts/objects/enemy.gd` (2853 lines)
- Key functions:
  - `_shoot()` - Line 2395
  - `_should_shoot_at_target()` - Line 1922
  - `_is_shot_clear_of_cover()` - Line 1893
  - `_process_combat_state()` - Line 758
