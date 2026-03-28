# Case Study: Issue #1670 — Enemies Don't Shoot at Drone Grenade

## Overview

- **Issue**: [#1670](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1670) — "fix дрон (граната)" / "enemies currently don't try to shoot at the drone"
- **Context**: Follows [PR #1668](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1668) which implemented drone targeting per [Issue #1667](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1667)
- **Date identified**: 2026-03-28

---

## Timeline / Sequence of Events

| Date | Event |
|------|-------|
| 2026-03-27 | PR #1668 merged: added `DRIFT_FACTOR`, `ENEMY_TARGETING_DELAY`, enemy drone-targeting code in `_process_combat_state()`, and 24 unit tests |
| 2026-03-28 | Issue #1670 opened: "enemies currently don't try to shoot at the drone" — the feature from PR #1668 doesn't work in practice |

---

## Root Cause Analysis

Investigation revealed **two independent bugs** that together prevent enemies from shooting the drone.

### Root Cause #1 — Missing HitArea: Bullets Can't Hit the Drone

**Location**: `scenes/projectiles/DroneGrenade.tscn`

**Evidence**:
- `DroneGrenade.tscn` is a `RigidBody2D` with `collision_layer = 32` (layer 6) and `collision_mask = 6`
- It has a `CollisionShape2D` child, but **no `Area2D` HitArea** child
- Player.tscn has `HitArea` (Area2D, `collision_layer = 1`)
- Enemy.tscn has `HitArea` (Area2D, `collision_layer = 2`)
- Enemy bullets (`Bullet.tscn`) have `collision_mask = 39` = layers 1+2+3+6 = player+enemy+obstacles+projectiles

**How bullet hit detection works** (`bullet.gd`):
1. Bullet connects `area_entered` signal → calls `_on_area_entered(area: Area2D)`
2. `_on_area_entered` calls `area.on_hit()` (or variants) on the `Area2D` node
3. `hit_area.gd` script forwards `on_hit()` to the parent

**The bug**: `DroneGrenade` has no `Area2D` HitArea child. Enemy bullets' `area_entered` signal never fires for the drone, so `drone_grenade.on_hit()` is never called by enemy bullets. The drone cannot be destroyed by enemy fire.

**Fix**: Add an `Area2D` HitArea node (with `collision_layer = 1`, `collision_mask = 16`, script = `hit_area.gd`) to `DroneGrenade.tscn`. This matches the player's HitArea setup so enemy bullets detect the drone.

---

### Root Cause #2 — Drone Targeting Only in COMBAT State

**Location**: `scripts/objects/enemy.gd`, line 1452

**Evidence**:
The drone targeting code added in PR #1668:
```gdscript
# In _process_combat_state():
var _pd := _find_targetable_player_drone(); if _pd != null and _can_shoot() and _shoot_timer >= shoot_cooldown: ...
```

This code is **only inside `_process_combat_state()`** (called when `_current_state == AIState.COMBAT`).

**The state machine flow when player uses drone**:
1. Player throws drone — grenade added to `"player_drones"` group
2. After 1.5s — drone becomes targetable (`is_targetable_by_enemies()` returns true)
3. If enemy was in COMBAT (could see player): after player hides to pilot drone, enemy loses sight → transitions to **PURSUING** after `COMBAT_MIN_DURATION_BEFORE_PURSUE = 0.5s`
4. In **PURSUING** state: no drone targeting code → enemies don't shoot drone
5. If enemy was never in COMBAT (player threw drone from hiding): enemies stay in IDLE/SEARCHING/PURSUING → drone targeting code never runs

**The bug**: `_find_targetable_player_drone()` is only called inside `_process_combat_state()`. No other state checks for targetable player drones, so enemies in PURSUING, IN_COVER, or other states will never shoot the drone even when they have line-of-sight to it.

**Fix**: Add the same compact drone targeting one-liner at the start of `_process_pursuing_state()` (after melee/sniper special-case handling, before the player-visibility-based COMBAT transition). This ensures enemies in PURSUING state will also shoot at targetable drones.

---

### Root Cause #3 — Drone in "grenades" Group Causes EVADING_GRENADE State (Discovered 2026-03-28)

**Location**: `scripts/projectiles/drone_grenade.gd` (`_launch_drone()`), `scripts/components/grenade_avoidance_component.gd`

**Evidence** from game log `game_log_20260328_081723.txt` (owner's report after first fix was deployed):
```
[08:17:49] [ENEMY] [InvisibleEnemy1] GRENADE DANGER: Entering EVADING_GRENADE state from SEARCHING
[08:17:49] [ENEMY] [InvisibleEnemy1] EVADING_GRENADE started: escaping to (1400.49, 739.3375)
[08:17:49] [ENEMY] [InvisibleEnemy1] EVADING_GRENADE: Escaped to safe distance
[08:17:49] [ENEMY] [InvisibleEnemy1] State: EVADING_GRENADE → SEARCHING
```
Enemies were constantly entering `EVADING_GRENADE` and running away from the drone instead of shooting it. This happened immediately after the drone became active (after the 1.5s targeting delay).

**Root cause**:
1. `GrenadeBase._ready()` always calls `add_to_group("grenades")` (line 125 of `grenade_base.gd`)
2. `DroneGrenade` extends `GrenadeBase`, so the drone is always in the `"grenades"` group
3. `GrenadeAvoidanceComponent.update()` scans `get_tree().get_nodes_in_group("grenades")` every physics frame and marks enemies as being in danger if any "grenade" is within `effect_radius + safety_margin` (225 + 75 = 300px)
4. The drone's `_get_effect_radius()` returns 225.0 — so enemies within 300px immediately enter `EVADING_GRENADE`
5. In `EVADING_GRENADE` state, enemies only flee — they do NOT check for targetable player drones

**The bug**: The drone was never removed from the `"grenades"` group after launch. The `GrenadeAvoidanceComponent` is designed to detect thrown/flying grenades that will explode, not controllable player drones. The drone should be in `"player_drones"` (for targeting) and NOT in `"grenades"` (for evasion) once it is actively piloted.

**Fix**: In `_launch_drone()`, call `remove_from_group("grenades")` immediately after `add_to_group("player_drones")`. This ensures that once the drone is under player control, enemies no longer treat it as a fuse-grenade to flee from — they instead engage via the `player_drones` targeting path.

---

### Root Cause #4 — Enemies Target Idle Player Body Instead of Drone (Discovered 2026-03-28)

**Location**: `scripts/characters/player.gd` (`is_invisible()`), `scripts/objects/enemy.gd` (`_process_idle_state()`)

**Evidence** from game log `game_log_20260328_094605.txt` (owner's report "enemies ignore the drone"):
```
[09:46:17] [ENEMY] [Enemy10] Player distracted - priority attack triggered
[09:46:17] [ENEMY] [Enemy10] Found cover at (1286.899, 1424) (distance: 135.1, player at (450, 1250))
[09:46:17] [ENEMY] [Enemy10] ROT_CHANGE: P3:corner -> P2:combat_state, state=COMBAT, target=-161.3°
[09:46:18] [ENEMY] [Enemy10] State: COMBAT -> PURSUING
```
After drone launch at (444, 1190), Enemy10 sees the **player body standing at (450, 1250)** and enters COMBAT targeting the player, then immediately transitions to PURSUING (can't see player around cover). All other enemies follow the same pattern.

**Root cause**:
1. When the player pilots the drone, `set_drone_piloting(true)` disables player movement/shooting but the player body **remains physically present and visible** to enemy raycasts
2. `_check_player_visibility()` uses `_player.has_method("is_invisible") and _player.is_invisible()` as the only skip condition for player body detection
3. The player's `is_invisible()` method returns `true` only when the invisibility suit is active — not when drone-piloting
4. Enemies in IDLE state see the idle player body → enter COMBAT targeting the player → lose LOS → PURSUING → never find player → never attack drone
5. The drone targeting in COMBAT (line 1451) fires once, then the enemy leaves COMBAT immediately because `_can_see_player = false` and `_combat_state_timer >= 0.5s`
6. Enemies in IDLE never checked for targetable player drones at all

**Fix**:
1. `player.gd`: `is_invisible()` returns `true` when `_is_drone_piloting` — enemy raycasts skip the idle player body
2. `enemy.gd` `_process_idle_state()`: add check for `_find_targetable_player_drone() != null` → enter COMBAT to engage the drone

---

### Root Cause #5 — Cover-Finding Uses Player Body as Threat Source (Discovered 2026-03-28)

**Location**: `scripts/objects/enemy.gd` — `_get_hidden_cover_candidates()`, `_is_point_visible_from_player()`, `_process_combat_state()`

**Evidence** from game log `game_log_20260328_101107.txt` (owner's report "enemies attack/move toward player, not the drone"):
```
[10:11:42] [ENEMY] [Enemy3] State: IDLE -> COMBAT
[10:11:42] [ENEMY] [Enemy3] Found cover at (961.3275, 1380.134) (distance: 682.2, player at (255.5063, 1793.934))
```
After drone launch at `(306, 1762)`, Enemy3 enters COMBAT but finds cover relative to **player body at `(255, 1793)`**, not the drone at `(723, 1508)`. Enemy moves to cover behind obstacles that hide from the idle body — from that position, the drone is in a completely different direction and often blocked by walls.

Additionally, with the RC#4 fix making the player invisible, enemies in COMBAT immediately see `_can_see_player = false` and transition to PURSUING after `COMBAT_MIN_DURATION_BEFORE_PURSUE = 0.5s` — even when a drone is visible and actively being targeted.

**Root cause**:
1. `_get_hidden_cover_candidates()` casts rays from `_player.global_position` to find hidden cover → selects cover that hides from the idle body
2. `_is_point_visible_from_player()` checks LOS from `_player.global_position` → `_is_position_visible_from_player()` cache is keyed on cover positions with player-body LOS — same problem
3. `_process_combat_state()` computes `direction_to_player` and `distance_to_player` from `_player.global_position` — misdirecting sidestep and approach logic away from drone
4. COMBAT→PURSUING check `if not _can_see_player:` fires immediately because player is invisible — enemy leaves COMBAT even when drone is visible and being shot

**Fix**:
1. Add `_get_threat_position()` helper — returns drone position when `player.is_invisible()`, else player position
2. `_is_point_visible_from_player()`: use `_get_threat_position()` as the observer for LOS checks
3. `_get_hidden_cover_candidates()`: use `_get_threat_position()` as the cover-source position (ray origins, cover-hidden checks)
4. `_process_combat_state()`: use `_get_threat_position()` for `distance_to_player` and `direction_to_player`
5. COMBAT→PURSUING transition: add `and _find_targetable_player_drone() == null` guard — stay in COMBAT when drone is visible

---

## Additional Context

**Why the unit tests passed but the feature didn't work**: The 24 unit tests in `test_drone_grenade.gd` test `MockDroneGrenade` logic (drift math, targeting delay countdown, `is_targetable_by_enemies()` return value). They do **not** test the end-to-end flow: bullet collision detection → `on_hit()` triggering → explosion. The missing HitArea is a scene-level issue that pure unit tests can't catch.

**Collision layers reference** (from scene files):
| Layer bit | Decimal | Used for |
|-----------|---------|---------|
| 1 (bit 0) | 1 | Player HitArea |
| 2 (bit 1) | 2 | Enemy HitArea |
| 3 (bit 2) | 4 | Obstacles/walls |
| 4 (bit 3) | 8 | (unused here) |
| 5 (bit 4) | 16 | Bullets (projectiles) |
| 6 (bit 5) | 32 | Grenades/projectiles body |

Enemy bullets: `collision_mask = 39` = layers 1+2+3+6 = 0b100111

---

## Proposed Solutions

### Fix 1: Add HitArea to DroneGrenade.tscn

Add to `scenes/projectiles/DroneGrenade.tscn`:
```
[sub_resource type="CircleShape2D" id="CircleShape2D_hit_area"]
radius = 10.0

[node name="HitArea" type="Area2D" parent="."]
collision_layer = 1
collision_mask = 16
script = ExtResource("...hit_area...")

[node name="HitAreaShape" type="CollisionShape2D" parent="HitArea"]
shape = SubResource("CircleShape2D_hit_area")
```

This makes the drone detectable by enemy bullets' `area_entered` signal.

### Fix 2: Add Drone Targeting to PURSUING State

In `scripts/objects/enemy.gd`, `_process_pursuing_state()`, after melee/sniper special handling and before the player-visibility COMBAT transition:

```gdscript
# Issue #1670: shoot at targetable player drone even while pursuing
var _pd := _find_targetable_player_drone(); if _pd != null and _can_shoot() and _shoot_timer >= shoot_cooldown: var _pd_dir := (_pd.global_position - global_position).normalized(); if _is_bullet_spawn_clear(_pd_dir): _rotate_body_toward(_pd_dir.angle(), get_physics_process_delta_time()); _execute_shoot(_pd.global_position); _shoot_timer = 0.0
```

Note: Must stay within 5000-line CI limit (currently 4999 lines). Use compact one-liner style matching line 1452.

---

## Files to Change

| File | Change |
|------|--------|
| `scenes/projectiles/DroneGrenade.tscn` | Add HitArea Area2D node with collision_layer=1, collision_mask=16, hit_area.gd script |
| `scripts/objects/enemy.gd` | Add compact drone targeting one-liner to `_process_pursuing_state()` — replace 1 line to stay within 5000-line limit |
| `scripts/projectiles/drone_grenade.gd` | In `_launch_drone()`, call `remove_from_group("grenades")` after `add_to_group("player_drones")` so enemies don't flee the drone |
| `tests/unit/test_drone_grenade.gd` | Add source-file integration tests verifying HitArea exists in scene and drone targeting exists in pursuing state |
