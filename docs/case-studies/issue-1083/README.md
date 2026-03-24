# Case Study: Issue #1083 — Fix врага с мачете (Machete Enemy Attacking Through Walls)

## Summary

A machete-wielding enemy could attack and deal damage to the player even when a wall or obstacle was between them. The melee range check only verified Euclidean distance; it did not perform any line-of-sight or obstacle raycast.

---

## Timeline / Sequence of Events

1. **Player moves behind a wall** — enemy is within 80 px (melee range) but a wall separates them.
2. **`_process_combat_state()` runs** — checks `_machete.is_in_melee_range(_player)` → returns `true` (distance ≤ 80 px).
3. **`perform_melee_attack()` is called** — starts the WINDUP → PAUSE → STRIKE animation sequence.
4. **STRIKE phase midpoint** — `_apply_strike_damage()` executes, calls `take_damage()` on the player.
5. **Result**: Player receives 2 damage through a solid wall.

---

## Root Cause Analysis

### File: `scripts/components/machete_component.gd`

```gdscript
## Check if in melee range of target.
func is_in_melee_range(target: Node2D) -> bool:
    if target == null or _parent == null:
        return false
    return _parent.global_position.distance_to(target.global_position) <= melee_range
```

The `is_in_melee_range()` function only checks **Euclidean distance** — it has no knowledge of walls or obstacles. Any node within 80 pixels is considered reachable.

Similarly, `_apply_strike_damage()` only checked whether the target had moved out of range during the windup animation:

```gdscript
var distance := _parent.global_position.distance_to(_attack_target.global_position)
if distance > melee_range * 1.5:
    return  # target moved away
# No wall check — damage applied regardless of obstacles
```

### Why Ranged Attacks Did Not Have This Problem

Ranged attacks use `_is_shot_clear_of_cover()` (lines ~2882–2896 in `enemy.gd`) and `_is_bullet_spawn_clear()` before firing. These functions cast a ray against collision mask 4 (obstacles layer). Melee attacks had no equivalent check.

---

## Fix

Three changes were made:

### 1. New method `is_melee_path_clear()` in `machete_component.gd`

```gdscript
## Check if the path to target is clear of walls/obstacles (Issue #1083).
func is_melee_path_clear(target: Node2D) -> bool:
    if target == null or _parent == null:
        return false
    var world_2d := _parent.get_world_2d()
    if world_2d == null:
        return true
    var space_state := world_2d.direct_space_state
    if space_state == null:
        return true
    var query := PhysicsRayQueryParameters2D.new()
    query.from = _parent.global_position
    query.to = target.global_position
    query.collision_mask = 4  # Only check obstacles (layer 3)
    query.exclude = [_parent.get_rid()]
    var result := space_state.intersect_ray(query)
    if result.is_empty():
        return true
    _log("Melee path blocked by wall at %.0f,%.0f" % [...])
    return false
```

### 2. Guard in `_apply_strike_damage()` in `machete_component.gd`

Added after the distance check:

```gdscript
# Check wall is not blocking the strike (Issue #1083)
if not is_melee_path_clear(_attack_target):
    _log("Strike damage skipped: wall between enemy and target")
    return
```

This is the critical safety check: even if the attack animation started (e.g., player walked behind a wall during windup), damage is not applied.

### 3. Guard in `_process_combat_state()` in `enemy.gd`

```gdscript
if _machete.is_in_melee_range(_player) and _shoot_timer >= shoot_cooldown and _machete.is_melee_path_clear(_player):
    _machete.perform_melee_attack(_player); _shoot_timer = 0.0; return
```

Prevents the animation from starting at all when a wall is present. This avoids a wasted attack animation where the enemy swings but deals no damage.

---

## Online Research

- Godot's `PhysicsDirectSpaceState2D.intersect_ray()` with `collision_mask = 4` is the standard pattern used throughout this codebase for obstacle detection (see `_is_shot_clear_of_cover()`).
- Melee LOS checks are a standard requirement in top-down games to prevent "ghost hits" through thin geometry.
- The double-guard approach (prevent attack start + prevent damage application) is a defense-in-depth pattern: the first guard avoids unnecessary animations; the second is a failsafe for fast-moving targets.

---

## Proposed Solutions (Considered)

| Option | Description | Chosen? |
|--------|-------------|---------|
| **Raycast on attack start + on damage** | Prevent animation start AND block damage if target moves behind wall during windup. Defense-in-depth. | ✓ Yes |
| Raycast only on attack start | Simpler, but player could dodge behind wall after windup begins and still take damage. | No |
| Raycast only in `_apply_strike_damage()` | Fixes the damage bug but still plays useless attack animation toward wall. | No |
| Use navigation mesh reachability | More accurate for complex geometry but expensive and overkill for 80 px melee range. | No |
