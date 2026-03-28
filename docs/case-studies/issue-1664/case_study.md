# Case Study: Issue #1664 — Fix Drone Operator Evasion (Dodges)

## Summary

**Title:** fix увороты дроновода (fix drone operator evasion/dodges)
**Issue:** https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1664
**Reporter:** Jhon-Crow
**Related PR:** #1541 (original dodge implementation)
**Fix PR:** #1665

---

## Problem Statement

The drone operator enemy does not dodge bullets as intended.

**Expected behavior (from issue):**
- When a bullet enters the threat zone, the operator should evade with a sharp lateral sidestep (like the machete enemy).
- The operator should dodge **up to 4 times** per burst.
- After 4 dodges, there must be a **4-second cooldown** before dodging is allowed again.

**Observed behavior:**
- The existing `MacheteComponent`-based dodge works mechanically (perpendicular lateral sidestep), but there is no burst limit.
- With `dodge_cooldown = 1.2s`, the operator can dodge indefinitely — one dodge every 1.2 seconds, with no burst cap.
- After Sessions 1 & 2 fixes, the operator still does not dodge in-game ("не уворачивается").

---

## Timeline / Sequence of Events

| Time       | Event |
|------------|-------|
| 23:06:34   | `EnemyDroneOperator` spawns, finds cover |
| 23:06:36   | Drone deployed, operator enters CONTROLLING (defenseless) phase |
| 23:06:38   | Player kills operator while it is in CONTROLLING phase (before it could dodge at all) |
| 23:06:38   | Drone destroyed → operator transitions to ACTIVE (too late, operator already dead) |

The log captures the operator dying in CONTROLLING phase. Because dodge is only available in ACTIVE phase, the operator never had a chance to demonstrate the bug. However, code analysis confirms the burst-limit mechanism was missing.

---

## Root Cause Analysis

### Root Cause 1 (Session 1 — no burst limit, PR #1665 initial commit)

**File:** `scripts/components/drone_operator_component.gd`

`MacheteComponent.try_dodge()` only blocked re-dodging while a dodge was in progress OR within the 1.2s cooldown — no burst counter existed.
The operator could dodge indefinitely, one sidestep every ~1.5s, which is not the intended burst-then-rest behavior.

**Fix (Session 1):** Added burst-limit state (`DODGE_BURST_MAX=4`, `DODGE_BURST_COOLDOWN=4.0s`) to `DroneOperatorComponent.try_dodge()`.

---

### Root Cause 2 (Session 2 — dodges still not working after Session 1 fix)

**Confirmed by:** Game log `game_log_20260327_231926.txt` — the log shows "Player bullet entered threat sphere — suppression triggered" multiple times after the ACTIVE phase transition, but never shows "[DroneOperator] Dodge X/4 in burst".

**File:** `scripts/components/drone_operator_component.gd` — `_setup_dodge_component()`

```gdscript
# DroneOperatorComponent._setup_dodge_component():
_dodge_component = MacheteComponent.new()
add_child(_dodge_component)    # <-- _ready() fires HERE
```

**File:** `scripts/components/machete_component.gd` — `_ready()`

```gdscript
func _ready() -> void:
    _parent = get_parent() as CharacterBody2D   # <-- CAST FAILS
```

`MacheteComponent` is a child of `DroneOperatorComponent` (a `Node`, not `CharacterBody2D`). The `as CharacterBody2D` cast returns `null`. Every call to `try_dodge()` then hits:

```gdscript
func try_dodge(bullet_direction: Vector2) -> bool:
    if _parent == null:
        return false   # <-- ALWAYS RETURNS FALSE
```

So dodging was silently disabled — no errors, no warnings, just silent no-ops.

**Fix (Session 2):** After `add_child(_dodge_component)`, explicitly assign the enemy body:

```gdscript
if _parent is CharacterBody2D:
    _dodge_component._parent = _parent as CharacterBody2D
```

---

### Root Cause 3 (Session 3 — still not dodging after Session 2 fix)

**Confirmed by:** Game log `game_log_20260327_232847.txt`

Evidence from the log:
```
[23:29:01] [DroneOperator] Dodge component set up (machete-style, speed=400, distance=120, parent=EnemyDroneOperator)
[23:29:01] [DroneOperator] Phase: ACTIVE (silenced pistol + laser, machete-style dodge)
...
[23:29:09] [EnemyDroneOperator] [#1311] Player bullet entered threat sphere — suppression triggered
[23:29:09] [EnemyDroneOperator] Hit: dmg=2, hp=2/2->0/2
[23:29:09] [EnemyDroneOperator] Enemy died
```

No `[DroneOperator] Dodge X/4 in burst` entries appear anywhere in the log.

**Root cause:**

`enemy.gd` has a `threat_reaction_delay = 0.2s` guard before `_under_fire` is set to `true`. Looking at `_update_suppression()`:

```gdscript
# Only set under_fire after delay (0.2s of bullet in sphere)
if _threat_reaction_delay_elapsed and not (force_field_active):
    _under_fire = true
```

The dodge check in `_process_combat_state` requires both `_under_fire == true` AND `_bullets_in_threat_sphere.size() > 0`:

```gdscript
if _under_fire and _bullets_in_threat_sphere.size() > 0 and not _drone_operator.is_dodging():
    _drone_operator.try_dodge(bd)
```

**Timeline of events per frame:**
1. Frame N: Player bullet enters threat sphere → `_bullets_in_threat_sphere.append(area)` → `_threat_memory_timer` set.
2. Same frame N or frame N+1: Player bullet body-collides with enemy → `on_hit_with_bullet_info()` → `dmg=2, hp=0` → `_on_death()`.
3. `_update_suppression` would have started the 0.2s reaction timer, but the enemy dies on frame N or N+1, **12 frames before** `_under_fire` is ever set to `true` at 60 fps.
4. `_process_combat_state` therefore never sees `_under_fire == true` while the bullet is in the sphere.
5. Result: dodge never triggers.

This is confirmed by the fact the operator has only **2 HP** while the player's weapon deals **2 damage per shot** — every shot is a 1-shot kill, leaving zero frames between "threat detected" and "enemy dead".

**Why the teleporter works but the dodge didn't:**
The teleporter's `try_damage_teleport` is called **inside `on_hit_with_bullet_info`** (non-lethal branch, `_current_health > 0`). It bypasses the reaction delay entirely — it fires on the same frame as the hit. The drone operator's dodge had no equivalent immediate-response path.

**Fix (Session 3):**

Add an immediate dodge attempt directly inside `_on_threat_area_entered`, before the bullet can hit the body. This fires on the same frame the bullet enters the 100px threat sphere — giving the operator a head start to sidestep before the bullet reaches the body hitbox.

```gdscript
# In _on_threat_area_entered (enemy.gd):
if _drone_operator and _drone_operator.get_phase() == DroneOperatorComponent.Phase.ACTIVE and not _drone_operator.is_dodging():
    var bd: Vector2 = area.get("direction") if area.get("direction") != null else Vector2.RIGHT.rotated(area.rotation)
    if _drone_operator.try_dodge(bd):
        _log_to_file("[#1664] Drone operator immediate dodge triggered from threat sphere entry")
```

This mirrors the pattern used by `EnemyTeleportComponent.try_damage_teleport` — react immediately rather than waiting for the next physics tick's suppression update cycle.

---

## Fix Summary

### Session 1 Fix
Added burst-limit state to `DroneOperatorComponent` (issue #1664):

```
const DODGE_BURST_MAX: int = 4       # max dodges per burst
const DODGE_BURST_COOLDOWN: float = 4.0  # seconds to wait after burst

var _dodge_burst_count: int = 0
var _dodge_burst_cooldown_timer: float = 0.0
```

Updated `try_dodge()` to:
1. Reject if `_dodge_burst_cooldown_timer > 0.0`
2. If `_dodge_burst_count >= DODGE_BURST_MAX`: start 4s cooldown, reset count, return false
3. Otherwise: delegate to `MacheteComponent`, increment `_dodge_burst_count`

Updated `_update_active()` to tick `_dodge_burst_cooldown_timer` down each frame.

### Session 2 Fix
In `_setup_dodge_component()`, after `add_child(_dodge_component)`:

```gdscript
if _parent is CharacterBody2D:
    _dodge_component._parent = _parent as CharacterBody2D
```

This ensures `MacheteComponent.try_dodge()` can access the enemy body for navigation and position calculations.

### Session 3 Fix
In `_on_threat_area_entered()` (`scripts/objects/enemy.gd`), after appending the bullet to the sphere list:

```gdscript
# Issue #1664: Drone operator ACTIVE phase — trigger dodge immediately on threat sphere entry.
if _drone_operator and _drone_operator.get_phase() == DroneOperatorComponent.Phase.ACTIVE and not _drone_operator.is_dodging():
    var bd: Vector2 = area.get("direction") if area.get("direction") != null else Vector2.RIGHT.rotated(area.rotation)
    if _drone_operator.try_dodge(bd):
        _log_to_file("[#1664] Drone operator immediate dodge triggered from threat sphere entry")
```

This fires the dodge on the **same frame** the bullet enters the 100px threat sphere, giving the operator a head start to sidestep before the bullet reaches the body hitbox. No longer requires `_under_fire` to be set.

---

## Tests Added (test_drone_operator.gd)

- `test_dodge_burst_max_is_four` — constant is 4
- `test_dodge_burst_cooldown_is_four_seconds` — cooldown is 4.0s
- `test_operator_can_dodge_four_times_in_burst` — 4 sequential dodges succeed
- `test_operator_blocked_after_four_dodges` — 5th dodge fails and starts cooldown
- `test_operator_burst_cooldown_blocks_further_dodges` — mid-cooldown attempts blocked
- `test_operator_can_dodge_again_after_burst_cooldown_expires` — dodging resumes after 4s
- `test_drone_operator_component_has_burst_constants` — source file check
- `test_dodge_component_parent_is_assigned_after_add_child` — verifies the Session 2 fix (Issue #1664)
- `test_immediate_dodge_trigger_source_present` — verifies the Session 3 fix is in enemy.gd (Issue #1664)

---

## Impact

- No changes to `MacheteComponent` (other enemies are unaffected).
- Only `DroneOperatorComponent` gains the explicit `_parent` override.
- Only `_on_threat_area_entered` in `enemy.gd` gains the immediate-trigger path (guarded by `is_drone_operator`-phase check).
- The underlying dodge physics (perpendicular sidestep, 120px, 400px/s) are unchanged.
