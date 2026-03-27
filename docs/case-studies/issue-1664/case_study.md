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

---

## Impact

- No changes to `MacheteComponent` (other enemies are unaffected).
- Only `DroneOperatorComponent` gains the explicit `_parent` override.
- The underlying dodge physics (perpendicular sidestep, 120px, 400px/s) are unchanged.
