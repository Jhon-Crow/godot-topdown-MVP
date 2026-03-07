# Case Study: Issue #954 — BFF Companion AI Bugs (Shoots Player, Stuck in Wall, Shoots Through Walls)

## Issue Summary

**Title**: fix BFF

**Reporter**: Jhon-Crow

**Description (Russian)**:
1. напарник иногда стреляет в игрока (companion sometimes shoots at the player)
2. напарник часто упирается в стену и стреляет (не попадает, перестаёт перемещаться) (companion often presses against wall and shoots — misses, stops moving)
3. напарник стреляет у края прохода (пытается попасть во врагов сквозь стены) (companion shoots at the edge of a passage — tries to hit enemies through walls)

**Additional issue reported in PR #955 review (2026-03-02)**:
The companion continues getting stuck in ALWAYS-COMBAT state (never transitions to other states). This was observed via game logs attached to the review.

**Additional issue reported in PR #955 review (2026-03-05)**:
"Update from main and continue from comment #3985986837. Also separately pay attention to the companion shooting at the edge of a passage (trying to hit enemies through walls)."

**Additional issue reported in PR #955 review (2026-03-07)**:
"Still occasionally shoots at the corner of a wall." — Confirms Bug #3 is still occurring despite the v1 fix.

## Game Logs

- `logs/game_log_20260302_205254.txt` — Session 1 (77,988 lines): Severe 96-shot stuck cluster, companion locked for 32 seconds
- `logs/game_log_20260302_205756.txt` — Session 2 (1,978 lines): Rapid P1↔P2 state oscillation, 7 shots through wall within 1 second of spawn
- `logs/game_log_20260307_201817.txt` — Session 3 (8,047 lines): 20+ shots into wall at (2026,1406) with bullet spawning at (2036,1473) — 68px from center. Distance=0 logged by bullet, confirming muzzle was inside the wall.

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

### Bug #3: Companion Shoots at Enemies Through Walls (Edge of Passage)

**Sequence**:
1. BFF companion navigates toward an enemy. At some point, it stands at the edge of a passage/doorway.
2. `process_combat()` calls `_has_los(target)` — center-to-center raycast → returns `true` (centers have clear LOS).
3. `bullet_spawn_blocked` check uses `_is_bullet_spawn_clear()` which only casts a 35px ray from the **enemy center** — this also returns `true` (center area is clear).
4. `velocity = Vector2.ZERO` — companion stops and starts firing.
5. The real weapon muzzle is located ~68px from center at an angle (actual measurement from logs: ~56px lateral + ~38px forward). This muzzle position overhangs the wall corner.
6. `_execute_shoot()` calls `_get_bullet_spawn_position()` which computes the true muzzle at 52px from `_weapon_sprite.global_position` which itself is ~20px from center. The real muzzle lands inside or behind the wall.
7. The bullet is spawned with `distance=0` (point-blank, body falls back to center), or travels ~333px before hitting the perpendicular wall.
8. The AI never stops because `_is_bullet_spawn_clear()` (35px from center) and `_has_los()` (center-to-center) both keep returning `true`.

**Evidence from game logs**:

*Session 1 (game_log_20260302_205254.txt)*:
- **Line 705–2003**: 45-shot stuck cluster at muzzle `(141.3543, 802.4822)`. Every shot shows `bullet_pos == shooter_position` and `distance=0` — the bullet is spawning inside the wall. Muzzle offset from body: **68px**.
- **Line 49854–72577**: **96-shot stuck cluster** spanning 32 seconds at muzzle `(980.1033, 924.3707)`. Only 4 ROT_CHANGE events during entire 32-second window. Body drifted 136px while muzzle stayed fixed at wall corner.

*Session 2 (game_log_20260302_205756.txt)*:
- **Line 580–639**: 7 shots through wall within 1 second of spawn, while log simultaneously shows `Moving to Enemy4 (no LOS)` — firing at an enemy it acknowledges it cannot see.
- **Lines 920–1001**: 14 rapid P1↔P2 state oscillations over 4 seconds, target angle oscillating -119° to -146°, consistent with muzzle borderline at wall corner.

**Root Cause**:
```
_is_bullet_spawn_clear():  35px ray from CENTER   → often CLEAR  (misses muzzle overhang)
_is_shot_clear_of_cover(): ray from REAL MUZZLE   → BLOCKED      (correctly detects wall)
```

The aggressive companion code path in `_shoot()` only called `_is_bullet_spawn_clear()` (center-based, 35px). The non-aggressive path called `_should_shoot_at_target()` which additionally runs `_is_shot_clear_of_cover()` from the real muzzle position. This inconsistency caused the companion to fire in cases where non-aggressive enemies would not.

Same inconsistency existed in `aggression_component.process_combat()`: `bullet_spawn_blocked` used only `_is_bullet_spawn_clear()`, so when the center was clear but the muzzle was inside a wall, the companion stopped moving and kept shooting into the wall.

---

## Evidence Summary from Logs

| Session | Lines | Duration | Shots | Position (muzzle) | Behavior |
|---------|-------|----------|-------|-------------------|----------|
| Log 1 | 705–2003 | 9s | 45 | (141.3, 802.5) | Point-blank wall, bullet_pos=body_pos |
| Log 1 | 3346–4316 | 6s | 30 | (520.3, 750.3) | Fixed muzzle, stuck at passage |
| Log 1 | 49854–72577 | 32s | 96 | (980.1, 924.4) | Muzzle anchored to wall corner, body drifted 136px |
| Log 2 | 580–639 | 1s | 7 | (549.9, 1206.0) | Fires 1s after spawn, no LOS acknowledged |

---

## Additional Online Research

### Godot AI Navigation Patterns
- **Center-to-LOS vs bullet-spawn-LOS mismatch**: A known pattern in 2D game AI — the character center has clear LOS but the weapon muzzle does not. Best practice: use muzzle position for LOS checks when computing firing solutions.
- **Friendly fire prevention**: Standard approach is to check target faction/group before firing, not just rely on aggression target being non-null.
- **Passage edge problem**: When an AI agent stands at a doorway corner, the agent's center may be in the clear area but the weapon (offset from center) clips the wall. A correct implementation must check from the actual muzzle position, not the center.

---

## Implemented Fixes

### Fix #1 — Companion Never Shoots Player (enemy.gd) ✓

**In `_shoot()`**: Added early return when `_agg` is true but `_aggression.get_target()` is null. This prevents the fallback to `_player.global_position` that caused friendly fire.

```gdscript
# [Issue #954] BFF companion (aggressive mode) must not fall back to shooting the player.
if _agg and (_aggression.get_target() == null):
    return
```

### Fix #2 — Prevent Companion from Getting Stuck Against Wall (aggression_component.gd + enemy.gd) ✓

**In `aggression_component.process_combat()`**: Added bullet spawn blocked check using `_is_bullet_spawn_clear()`. When blocked, navigate toward target instead of stopping.

**In `_shoot()` for aggressive enemies**: Added `_is_bullet_spawn_clear()` check — when bullet spawn is blocked by the wall the companion is pressing against, abort the shot.

### Fix #3 — Prevent Companion from Shooting Through Walls at Passage Edges (enemy.gd + aggression_component.gd) ✓

#### v1 Fix (PR #955 initial) — Partially Effective

**Root cause identified**: The real muzzle is ~68px from enemy center at an angle and can overhang wall corners. For aggressive enemies, only the 35px center check (`_is_bullet_spawn_clear`) was used.

**v1 fix**: Added `_is_shot_clear_of_cover()` check in `_shoot()` for aggressive path (raycasts from muzzle to target). Also added muzzle check in `aggression_component.process_combat()`.

**Why v1 was insufficient**: `_is_shot_clear_of_cover()` casts a ray FROM the muzzle TO the target. When the muzzle is already INSIDE a wall (which happens when enemy is flush against a wall corner), Godot's physics engine returns no hit for rays starting inside a collider. So the check erroneously passes and shots are fired into the wall.

#### v2 Fix (current) — Root Cause Resolution

**Evidence from `game_log_20260307_201817.txt`** (2026-03-07 session):
- BffCompanion at `(2026.06, 1406.34)` fired 20+ shots while stuck
- Bullet log: `bullet_pos=(2036.26, 1473.62)` — 68px from center
- Bullet log: `Distance to wall: 0` — bullet spawned INSIDE a wall
- The 35px `_is_bullet_spawn_clear` check never reached the wall (wall was at ~35-68px range)
- `_is_shot_clear_of_cover` started its ray from inside the wall and returned clear (Godot behavior)

**v2 fix in `_is_bullet_spawn_clear()` (enemy.gd)**:
```gdscript
# [#954] Use real muzzle position: bullet_spawn_offset (30px) underestimates real
# muzzle offset (~52-68px), missing walls between 35px-68px from center.
var muzzle_pos := _get_bullet_spawn_position(direction)
var real_muzzle_distance := global_position.distance_to(muzzle_pos)
var check_end := global_position + direction * (real_muzzle_distance + 5.0)
```

By casting from enemy center to the actual muzzle position (+5px buffer), the check correctly detects walls that the muzzle would overhang, blocking the shot and triggering navigation.

---

## Regression Tests

Tests added to `tests/unit/test_bff_pendant.gd`:
- **Bug #1** (5 tests): `MockBffShootLogic` — verifies no fallback to player shooting
- **Bug #2** (7 tests): `MockBffCombatMovement` — verifies navigation when center spawn blocked
- **Bug #3** (6 tests): `MockMuzzleWallCheck` — verifies no shooting when real muzzle path blocked
- **Bug #3 v2** (4 tests): `MockBulletSpawnCheck` — verifies real muzzle distance catches walls at 40-50px that old 35px check missed
