# Case Study: Issue #954 — BFF Companion AI Bugs (Shoots Player, Stuck in Wall)

## Issue Summary

**Title**: fix BFF

**Reporter**: Jhon-Crow

**Description (Russian)**:
1. напарник иногда стреляет в игрока (companion sometimes shoots at the player)
2. напарник часто упирается в стену и стреляет (не попадает, перестаёт перемещаться) (companion often presses against wall and shoots — misses, stops moving)

---

## Context: BFF Companion Architecture

The BFF pendant (Issue #674) summons an actual Enemy scene instance (`res://scenes/objects/Enemy.tscn`) in permanent aggressive state. The companion is:
- Removed from the "enemies" group
- Added to the "bff_companions" group
- Set to `set_aggressive(true)` — uses `AggressionComponent` for combat

### Relevant Code Files
- `scripts/objects/enemy.gd` (4990 lines) — Enemy AI base
- `scripts/components/aggression_component.gd` (192 lines) — Aggression logic
- `scripts/characters/player.gd` — `_summon_bff_companion()` (lines 3280-3339)
- `Scripts/Characters/Player.cs` — `SummonBffCompanion()` (lines 4990-5070)

---

## Timeline of Events (How the Bug Manifests)

### Bug #1: Companion Shoots at Player

**Sequence**:
1. BFF companion spawns as an Enemy instance. During `_ready()`, `_find_player()` is called → `_player` is set to the actual player node.
2. `set_aggressive(true)` is called → `AggressionComponent._is_aggressive = true`.
3. Each physics frame: `_check_player_visibility()` runs → if player is visible, `_can_see_player = true`.
4. `_process_ai_state()` calls `_aggression.process_aggression_tick()` → calls `process_combat()`.
5. In `process_combat()`:
   - `_find_nearest_enemy_target_with_los()` searches the "enemies" group → finds regular enemies.
   - If target found with LOS → aims and calls `_parent._shoot()`.
6. In `_shoot()` (enemy.gd line 3807):
   ```gdscript
   var _agg := _aggression != null and _aggression.is_aggressive()
   var target_position := _aggression.get_target_position() if _agg and _aggression.get_target() != null
       else (_player.global_position if _player else global_position)
   ```
   **BUG**: When `_aggression.get_target()` is `null` (no enemies in the "enemies" group have LOS), the target falls back to `_player.global_position`. The companion then aims and shoots at the player.

**When does this happen?**
- All regular enemies are dead (companion has no targets in "enemies" group)
- Companion has LOS to player but no LOS to any enemy
- Navigation toward enemies means the companion faces the player direction temporarily
- During reload (no `_can_shoot()` but aim check still passes when target is set)

**Root Cause**: The `_shoot()` fallback logic (`_player.global_position when no aggression target`) was designed for normal enemies that always target the player. For the BFF companion, this fallback is incorrect — the companion should never target the player.

### Bug #2: Companion Stuck Against Wall, Shooting but Missing

**Sequence**:
1. BFF companion in aggressive mode navigates toward an enemy.
2. `process_combat()` runs `_has_los(target)` — a center-to-center raycast from companion to target.
3. The ray clears (no obstacle between centers) → `_has_los()` returns `true`.
4. `process_combat()` sets `velocity = Vector2.ZERO` (stand still and shoot) and calls `_parent._shoot()`.
5. The companion stops moving, pressed against a wall.
6. In `_shoot()` → `_execute_shoot()` → the bullet spawn offset (30px from center) places the bullet spawn point INSIDE or behind the wall.
7. For normal enemies, `_should_shoot_at_target()` checks `_is_bullet_spawn_clear()` and prevents shooting.
8. **BUG**: For aggressive enemies (line 3814): `if not _agg and not _should_shoot_at_target(target_position): return` — the `_is_bullet_spawn_clear()` check is SKIPPED for aggressive enemies.
9. The bullet is spawned inside the wall, travels nowhere, and the companion stays stationary.

**Root Cause**: `_shoot()` skips bullet spawn clear check for aggressive enemies (`not _agg` guard). Combined with `process_combat()` stopping movement when center-to-center LOS exists (even if bullet spawn is blocked), the companion gets stuck against a wall, firing useless shots.

---

## Evidence

### Code Evidence — Bug #1 (enemy.gd lines 3807-3814):
```gdscript
func _shoot() -> void:
    # ...
    var _agg := _aggression != null and _aggression.is_aggressive()  # [Issue #675]
    if bullet_scene == null or not (_player != null or (_agg and _aggression.get_target() != null)): return
    if not _can_shoot(): return
    # BUG: Falls back to _player.global_position when aggression has no target
    var target_position := _aggression.get_target_position() if _agg and _aggression.get_target() != null
        else (_player.global_position if _player else global_position)
    if enable_lead_prediction and not _agg and _player: target_position = _calculate_lead_prediction()
    if not _agg and not _should_shoot_at_target(target_position): return  # BUG: no check for _agg!
```

### Code Evidence — Bug #2 (aggression_component.gd lines 49-69):
```gdscript
func process_combat(delta, rotation_speed, shoot_cooldown, combat_move_speed) -> void:
    if _target == null or not is_instance_valid(_target) or _target.get("_is_alive") == false:
        _target = _find_nearest_enemy_target_with_los()
    if _target != null and _has_los(_target):
        # BUG: stops movement when center-to-center LOS clears, ignoring bullet spawn
        var d := (_target.global_position - _parent.global_position).normalized()
        # ...
        if wf.dot(d) >= 0.866 and _parent._can_shoot() and _parent._shoot_timer >= shoot_cooldown:
            _parent._shoot()  # BUG: no bullet spawn clear check in _shoot() for aggressive
        _parent.velocity = Vector2.ZERO  # Stops moving even if against wall
```

---

## Additional Online Research

### Godot AI Navigation Patterns
- **Center-to-LOS vs bullet-spawn-LOS mismatch**: A known pattern in 2D game AI — the character center has clear LOS but the weapon muzzle does not. Best practice: use muzzle position for LOS checks when computing firing solutions.
- **Friendly fire prevention**: Standard approach is to check target faction/group before firing, not just rely on aggression target being non-null.

---

## Proposed Solutions

### Fix #1 — Companion Never Shoots Player (enemy.gd)

**In `_shoot()`**: Add a guard to prevent BFF companions from targeting the player.

```gdscript
# Add flag: is this enemy a BFF companion?
var _is_bff_companion: bool = false  # Set in player.gd when summoning

# In _shoot(), prevent player targeting when companion
if _is_bff_companion and (_agg and _aggression.get_target() == null):
    return  # No enemy targets — don't fall back to shooting player
```

**Alternative**: Instead of a flag, check if the node is in "bff_companions" group.

### Fix #2 — Prevent Companion from Getting Stuck Against Wall (aggression_component.gd)

**Option A**: In `process_combat()`, add bullet spawn clear check before stopping movement:
```gdscript
if _target != null and _has_los(_target):
    var weapon_dir := ...
    if not _is_bullet_spawn_clear_for_parent():
        # Move out from wall instead of standing still
        _parent._move_to_target_nav(_target.global_position, combat_move_speed)
        return
    # ...stand still and shoot
```

**Option B**: In `_shoot()`, add `_is_bullet_spawn_clear()` check even for aggressive enemies.

**Recommendation**: Fix both in `_shoot()` since that's where the actual shooting decision is made.

---

## Implementation Plan

1. **Fix Bug #1**: In `_shoot()`, when `_agg` is true but `_aggression.get_target()` is null, return early instead of falling back to `_player`. Also prevent `_execute_shoot()` from firing toward player position when companion.

2. **Fix Bug #2**: In `_shoot()`, add bullet spawn clear check for aggressive enemies: remove the `not _agg` guard from `_should_shoot_at_target()` check. Additionally, in `process_combat()`, move toward target when bullet spawn is blocked.

3. **Add `is_bff_companion` flag**: Set in `player.gd`/`Player.cs` during summoning so the companion can be identified by its AI code.
