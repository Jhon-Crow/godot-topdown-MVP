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

**File:** `scripts/components/drone_operator_component.gd`

The `_setup_dodge_component()` method (line ~389) creates a `MacheteComponent` with:
- `dodge_speed = 400.0`
- `dodge_distance = 120.0`
- `dodge_cooldown = 1.2`

`MacheteComponent.try_dodge()` only blocks re-dodging while a dodge is in progress OR within the 1.2s cooldown. There is no counter for "how many times have we dodged in a row" and no "long cooldown after N dodges".

The `DroneOperatorComponent.try_dodge()` wrapper simply delegated to `_dodge_component.try_dodge()` without any additional burst-limiting logic.

**Result:** The operator could dodge indefinitely, one sidestep every ~1.5 seconds (0.3s dodge + 1.2s cooldown), which is not the intended burst-then-rest behavior.

---

## Fix

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

---

## Tests Added (test_drone_operator.gd)

- `test_dodge_burst_max_is_four` — constant is 4
- `test_dodge_burst_cooldown_is_four_seconds` — cooldown is 4.0s
- `test_operator_can_dodge_four_times_in_burst` — 4 sequential dodges succeed
- `test_operator_blocked_after_four_dodges` — 5th dodge fails and starts cooldown
- `test_operator_burst_cooldown_blocks_further_dodges` — mid-cooldown attempts blocked
- `test_operator_can_dodge_again_after_burst_cooldown_expires` — dodging resumes after 4s
- `test_drone_operator_component_has_burst_constants` — source file check

---

## Impact

- No changes to `MacheteComponent` (other enemies are unaffected).
- Only `DroneOperatorComponent` gains the burst counter.
- The underlying dodge physics (perpendicular sidestep, 120px, 400px/s) are unchanged.
