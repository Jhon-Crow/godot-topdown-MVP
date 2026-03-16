# Issue #729: Fix Gas Grenade - Aggressive Enemies Not Moving

## Summary
Aggressive enemies affected by the Aggression Gas Grenade stand still and do not move or flank other enemies, even in the SEARCHING state.

## Timeline Reconstruction

Based on log analysis from the provided game logs:

1. **20:36:30** - Gas grenade releases cloud at building level
2. **20:36:30** - Enemy3, Enemy4, Enemy2 become AGGRESSIVE (marked with `[#675]`)
3. **20:36:30** - Enemy4 state: `COMBAT -> PURSUING`
4. **20:36:30** - Immediately after, Enemy4 marked `[#675] AGGRESSIVE`
5. **20:36:35** (4s later) - Enemy4: `GLOBAL STUCK: pos=(648.4668, 887.4746) for 4.0s without player contact, State: PURSUING -> SEARCHING`

The enemy was stuck at the same position for 4 seconds despite being in PURSUING state. This is because the aggression system completely overrode the enemy AI state machine.

## Root Cause Analysis

### The Problem
Located in `scripts/components/aggression_component.gd`:

```gdscript
func process_combat(delta: float, ...):
    if _target == null or not is_instance_valid(_target) or _target.get("_is_alive") == false:
        _target = _find_nearest_enemy_target()  # Only finds targets WITH line of sight
    if _target == null:
        _parent.velocity = Vector2.ZERO  # BUG: Enemy stops moving entirely
        return
```

And in `_find_nearest_enemy_target()`:
```gdscript
func _find_nearest_enemy_target() -> Node2D:
    for e in _parent.get_tree().get_nodes_in_group("enemies"):
        ...
        if d < best_d and _has_los(e):  # BUG: Only targets with LOS considered
            best_d = d; best = e
    return best
```

### Why This Caused Issues

1. **Aggression Override**: When an enemy is aggressive, all AI state processing is delegated to `AggressionComponent.process_combat()` at line 1168-1169 of `enemy.gd`:
   ```gdscript
   if _aggression and _aggression.is_aggressive():
       _aggression.process_combat(delta, ...); return
   ```

2. **LOS Requirement**: The `_find_nearest_enemy_target()` function ONLY returns enemies that have line of sight. If no enemies are visible (blocked by walls), the function returns `null`.

3. **No Navigation Fallback**: When `_target == null`, the enemy simply sets `velocity = Vector2.ZERO` and returns. There was no logic to navigate toward enemies behind walls.

4. **State Machine Bypass**: Because aggression overrides the state machine, the normal PURSUING, FLANKING, and SEARCHING behaviors (which include navigation) are never executed.

## The Fix

Modified `aggression_component.gd` to:

1. **Separate targeting from navigation**: Created two functions:
   - `_find_nearest_enemy_target_with_los()` - for combat targeting (shoot at visible enemies)
   - `_find_nearest_enemy_any()` - for navigation (move toward any enemy)

2. **Add navigation when no LOS**: When no visible target exists but enemies are present, use navigation to move toward the nearest one:
   ```gdscript
   else:
       # No visible target - find any enemy and navigate toward them
       _nav_target = _find_nearest_enemy_any()
       if _nav_target != null:
           _parent._move_to_target_nav(_nav_target.global_position, combat_move_speed)
   ```

3. **Throttled logging**: Added frame-based throttling to avoid log spam when navigating.

## Files Modified

- `scripts/components/aggression_component.gd` - Main fix

## Testing

The fix can be verified by:
1. Throwing an Aggression Gas Grenade near enemies
2. Observing that aggressive enemies now navigate toward other enemies even when they can't see them
3. Checking logs for `[#675] Moving to EnemyX (no LOS)` messages

## Related Issues

- Issue #675 - Original Aggression Gas Grenade implementation
- Issue #367 - Global stuck detection for PURSUING/FLANKING states
