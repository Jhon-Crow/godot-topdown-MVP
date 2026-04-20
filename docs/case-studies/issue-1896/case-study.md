# Case Study: Issue #1896 — Drone Grenade Throw-Before-Pilot Mechanic Not Working

## Overview

**Issue:** [#1896 — update граната дрон](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1896)  
**PR:** [#1906](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1906)  
**Game log:** `game_log_20260420_120715.txt` (attached by Jhon-Crow on 2026-04-20)  
**Reported symptom:** Drone spawns next to player and immediately enters pilot mode — no ballistic throw phase.

---

## Timeline of Events

| Time | Event |
|------|-------|
| 2026-04-20 | Issue #1896 filed: requests 50% speed boost + throw-before-pilot mechanic |
| 2026-04-20T07:15 | PR #1906 opened with implementation in `drone_grenade.gd` and unit tests |
| 2026-04-20T07:20 | PR marked ready to merge, CI passing |
| 2026-04-20T09:09 | Jhon-Crow tests in-game and reports: throw phase not working at all; attaches `game_log_20260420_120715.txt` |
| 2026-04-20T09:10 | AI work session restarted |

---

## Sequence of Events During a Drone Throw (from game log)

```
12:07:27  [GrenadeBase] Grenade created at (0, 0) (frozen)
12:07:27  [DroneGrenade] Ready
12:07:27  [DroneGrenade] Pin pulled — drone will launch on throw
12:07:32  [Player.Grenade.Simple] Throwing! Target: (666.05, 1545.04), Distance: 410.1, Speed: 496.0
12:07:32  [GrenadeBase] Simple mode throw! Dir: (0.999999, 0.001552), Speed: 496.0
12:07:32  [DroneGrenade] PILOTING phase started at (255.97, 1544.41)   ← BUG: should be THROWING
12:07:32  [DroneGrenade] Drone launched at (255.97, 1544.41)
```

**Key observation:** The log shows `PILOTING phase started` directly after throw — the `THROWING` phase is never entered. The target position `(666.05, 1545.04)` was known to the player code but never forwarded to the drone.

---

## Root Cause Analysis

### The Bug

`DroneGrenade._launch_drone()` enters the `THROWING` phase only when `_aim_point != Vector2.ZERO`:

```gdscript
# drone_grenade.gd line 164
if _aim_point != Vector2.ZERO:
    _drone_state = DroneState.THROWING   # ← only reachable if set_aim_point() was called
    ...
else:
    _start_piloting()                    # ← always reached because _aim_point = Vector2.ZERO
```

`set_aim_point(world_pos)` was implemented in `drone_grenade.gd` but **never called** from `player.gd`. The player's grenade-throwing code (`_throw_simple_grenade` and `_throw_grenade`) knew the target position (`target_pos` / `drag_end`) but passed it only to the physics throw — not to the drone's state machine.

### Why Unit Tests Passed

Unit tests (`test_drone_grenade.gd`) call `drone.set_aim_point(...)` directly before each throw. They test the drone in isolation and correctly verify the THROWING state. But the integration path — player code → grenade throw — never called `set_aim_point()`.

This is a classic **unit test / integration gap**: the component works in isolation, but the caller never uses the new API.

### Root Cause (one sentence)

`player.gd`'s `_throw_simple_grenade()` and `_throw_grenade()` functions had the mouse cursor position available but never called `_active_grenade.set_aim_point(target_pos)` before invoking the throw, leaving `DroneGrenade._aim_point` at `Vector2.ZERO` and causing the drone to skip the THROWING phase entirely.

---

## Evidence

### Game Log (lines 1190–1199)
```
[Player.Grenade.Simple] Throwing! Target: (666.0539, 1545.0447), Distance: 410.1, Speed: 496.0
[GrenadeBase] Simple mode throw! Dir: (0.999999, 0.001552), Speed: 496.0
[DroneGrenade] PILOTING phase started at (255.9691, 1544.408)   ← wrong state
[DroneGrenade] Drone launched at (255.9691, 1544.408)
```
No `THROWING phase started` log line ever appears across the entire 2985-line log.

### Code Search
```
$ grep -rn "set_aim_point" scripts/
scripts/projectiles/drone_grenade.gd:143:func set_aim_point(world_pos: Vector2) -> void:
```
Zero call sites found — only the definition existed.

---

## Fix Applied

Two call sites added in `scripts/characters/player.gd`:

**1. Simple mode (`_throw_simple_grenade`, line ~1931):**
```gdscript
# Issue #1896: pass the mouse cursor world position so DroneGrenade can fly there first.
if _active_grenade.has_method("set_aim_point"):
    _active_grenade.set_aim_point(target_pos)
```

**2. Velocity-based mode (`_throw_grenade`, line ~2094):**
```gdscript
# Issue #1896: pass the mouse cursor world position so DroneGrenade can fly there first.
if _active_grenade.has_method("set_aim_point"):
    _active_grenade.set_aim_point(drag_end)
```

Both use `has_method()` guard so non-drone grenades are unaffected.

---

## Lessons Learned

1. **New API methods on components must be wired up at every call site.** Adding `set_aim_point()` to `DroneGrenade` without adding a matching call in `player.gd` created a silent no-op.

2. **Unit tests that test components in isolation can miss integration bugs.** The test called `set_aim_point()` directly; the real throwing code did not.

3. **Log-first debugging is effective.** The game log provided an unambiguous trace: `PILOTING phase started` appearing immediately after throw (with no `THROWING phase started` line) pinpointed the issue within minutes.

4. **Fallback-to-legacy patterns hide missing calls.** The "if `_aim_point == Vector2.ZERO`, start piloting immediately" fallback was added for backward compatibility but masked the missing caller setup — the drone silently fell back to old behavior with no warning.

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/characters/player.gd` | Added `set_aim_point(target_pos)` call before throw in `_throw_simple_grenade()` and `set_aim_point(drag_end)` in `_throw_grenade()` |
| `docs/case-studies/issue-1896/case-study.md` | This document |
| `docs/case-studies/issue-1896/game_log_20260420_120715.txt` | Original game log from Jhon-Crow |
