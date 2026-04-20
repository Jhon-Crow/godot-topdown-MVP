# Case Study: Issue #1896 — Drone Grenade Throw-Before-Pilot Mechanic

## Overview

**Issue:** [#1896 — update граната дрон](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1896)  
**PR:** [#1906](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1906)  
**Attached logs preserved in this folder:**

- `game_log_20260420_120715.txt` — first failed retest attached at 2026-04-20T09:09Z.
- `game_log_20260420_123426.txt` — second failed retest attached at 2026-04-20T09:35Z.

**Original requirements:**

1. Increase drone grenade speed by 50%.
2. Throw the drone like a grenade toward the aim point first; only after a successful throw should player drone control begin. If it collides before reaching the throw aim point, it explodes immediately.

**Reported symptom:** the drone still spawned near the player and entered piloting immediately, with no visible throw-before-pilot phase.

---

## Timeline

| Time (UTC) | Event |
|------------|-------|
| 2026-04-20 | Issue #1896 filed. |
| 2026-04-20T07:15 | PR #1906 opened with `DroneGrenade` state machine and unit tests. |
| 2026-04-20T09:09 | Jhon-Crow reported the first failure: “throw-before-pilot не работает”; attached `game_log_20260420_120715.txt`. |
| 2026-04-20T09:13 | First follow-up fix added `set_aim_point()` calls to `scripts/characters/player.gd`. |
| 2026-04-20T09:35 | Jhon-Crow reported the second failure: “всё по старому, не кидается”; attached `game_log_20260420_123426.txt`. |
| 2026-04-20T09:37+ | Second investigation found that the tested runtime path was C# `Scripts/Characters/Player.Grenade.cs`, not GDScript `scripts/characters/player.gd`. |

---

## Evidence From Logs

### First Failed Retest

From `game_log_20260420_120715.txt`:

```text
[12:07:32] [Player.Grenade.Simple] Throwing! Target: (666.0539, 1545.0447), Distance: 410,1, Speed: 496,0, Friction: 300,0
[12:07:32] [GrenadeBase] Simple mode throw! Dir: (0.999999, 0.001552), Speed: 496.0
[12:07:32] [DroneGrenade] PILOTING phase started at (255.9691, 1544.408)
[12:07:32] [DroneGrenade] Drone launched at (255.9691, 1544.408)
```

### Second Failed Retest

From `game_log_20260420_123426.txt`:

```text
[12:34:32] [Player.Grenade.Simple] Throwing! Target: (790.8414, 257.69128), Distance: 589,0, Speed: 594,5, Friction: 300,0
[12:34:32] [Player.Grenade.Simple] C# set velocity directly: dir=(0.9874949, -0.15765108), speed=594,5, spawn=(209.2497, 350.54092)
[12:34:32] [DroneGrenade] PILOTING phase started at (209.2497, 350.5409)
[12:34:32] [DroneGrenade] Drone launched at (209.2497, 350.5409)
```

The second log repeats the same signature twice:

- `Throwing! Target: ...` proves the player throw code has the world-space aim point.
- `C# set velocity directly` identifies the active path as `Scripts/Characters/Player.Grenade.cs`.
- `PILOTING phase started` appears immediately.
- `THROWING phase started` never appears.

---

## Root Cause

The drone state machine was correct but its new API was only wired in the GDScript player path.

`DroneGrenade._launch_drone()` enters `THROWING` only when `_aim_point` is set:

```gdscript
if _aim_point != Vector2.ZERO:
    _drone_state = DroneState.THROWING
    _throw_target = _aim_point
else:
    _start_piloting()
```

The first follow-up fix added:

```gdscript
_active_grenade.set_aim_point(target_pos)
```

to `scripts/characters/player.gd`, but the logs are produced by the C# player partial. The string:

```text
[Player.Grenade.Simple] C# set velocity directly
```

exists in `Scripts/Characters/Player.Grenade.cs`, and that file still had zero `set_aim_point` call sites. Therefore the exported/tested path left `_aim_point == Vector2.ZERO`, so `DroneGrenade` fell back to immediate `PILOTING` every time.

### Why The First Fix Did Not Change The Retest

There are two player implementations in this project:

- `scripts/characters/player.gd`
- `Scripts/Characters/Player.Grenade.cs` / `Scripts/Characters/Player.cs`

The PR initially fixed only the GDScript implementation. The user's runtime was using the C# implementation, which directly sets grenade velocity and then calls GDScript grenade hooks. That C# code needed to call the GDScript method `set_aim_point` before the drone was unfrozen or launched.

---

## Additional Facts Checked Online

Official Godot documentation confirms the interop assumptions used in the fix:

- Godot C# projects can communicate with GDScript nodes through `Call(...)`; the cross-language scripting docs show C# calling a GDScript node method with `myGDScriptNode.Call("print_node_name", this)`:
  https://docs.godotengine.org/en/3.3/getting_started/scripting/cross_language_scripting.html
- Godot's C# docs note that `Get()`, `Set()`, `Call()` and `Connect()` rely on Godot API naming conventions, including `snake_case` names for dynamically called methods. This supports calling `"set_aim_point"` from C#:
  https://docs.godotengine.org/en/stable/tutorials/scripting/c_sharp/c_sharp_basics.html
- `RigidBody2D.freeze` disables gravity and forces; setting the drone aim point before unfreezing avoids a fallback launch path running while the aim point is still unset:
  https://docs.godotengine.org/en/stable/classes/class_rigidbody2d.html

---

## Fix Applied

### C# Runtime Path

`Scripts/Characters/Player.Grenade.cs` now passes the world-space throw target to any active grenade that implements `set_aim_point`:

```csharp
private void PassDroneThrowAimPoint(Vector2 aimPoint)
{
    if (_activeGrenade == null || !IsInstanceValid(_activeGrenade))
    {
        return;
    }

    if (_activeGrenade.HasMethod("set_aim_point"))
    {
        _activeGrenade.Call("set_aim_point", aimPoint);
        LogToFile($"[Player.Grenade] Drone aim point set to {aimPoint}");
    }
}
```

The helper is called in both C# throw paths:

- `ThrowSimpleGrenade()` passes `targetPos`.
- `ThrowGrenade(Vector2 dragEnd)` passes `dragEnd`.

Both calls happen after the safe spawn position is assigned and before `_activeGrenade.Freeze = false` / `throw_grenade_*` calls. That ordering prevents `DroneGrenade` from launching with `_aim_point == Vector2.Zero`.

### Existing GDScript Path

The previous fix remains in `scripts/characters/player.gd`, so both player implementations now pass the aim point.

---

## Tests

`tests/unit/test_drone_grenade.gd` now covers:

- Drone state machine behavior: aim point enters `THROWING`, reaches target then enters `PILOTING`, throw-phase collision explodes.
- C# interop regression: `ThrowSimpleGrenade()` must call `PassDroneThrowAimPoint(targetPos)` before unfreezing and before `throw_grenade_simple`.
- C# interop regression: `ThrowGrenade(Vector2 dragEnd)` must call `PassDroneThrowAimPoint(dragEnd)` before unfreezing and before `throw_grenade_with_direction`.
- C# interop regression: helper must call the snake_case GDScript method `set_aim_point`.

These tests fail against the earlier PR state because `Player.Grenade.cs` did not contain any `set_aim_point` handoff.

---

## Expected Runtime Signature After Fix

For a successful drone throw, logs should show:

```text
[Player.Grenade] Drone aim point set to (...)
[DroneGrenade] THROWING phase started toward (...)
[DroneGrenade] Drone launched at (...)
```

Only after the drone reaches the throw target should it log:

```text
[DroneGrenade] Throw target reached — switching to PILOTING
[DroneGrenade] PILOTING phase started at (...)
```

If the drone collides with a wall or enemy during the throw phase, expected logs include:

```text
[DroneGrenade] Throw collision with '...' — exploding!
```

---

## Lessons Learned

1. Component unit tests were not enough because they called `set_aim_point()` directly. The regression lived in the caller integration.
2. This codebase has parallel GDScript and C# player paths. Gameplay fixes touching player behavior must check both.
3. Log strings are useful runtime fingerprints. The `C# set velocity directly` line identified the actual implementation used in the user's exported build.
4. Backward-compatible fallback behavior (`_aim_point == Vector2.ZERO` => immediate piloting) hid the missing caller setup. Future fallback paths should log enough state to distinguish intentional legacy behavior from missing setup.

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/projectiles/drone_grenade.gd` | Drone speed 400 -> 600 and throw/pilot state machine from the original implementation. |
| `scripts/characters/player.gd` | GDScript player passes `set_aim_point()` before throw. |
| `Scripts/Characters/Player.Grenade.cs` | C# player now passes `set_aim_point()` before unfreezing/calling grenade throw hooks. |
| `tests/unit/test_drone_grenade.gd` | Added C# interop regression tests. |
| `docs/case-studies/issue-1896/game_log_20260420_120715.txt` | First failed retest log preserved. |
| `docs/case-studies/issue-1896/game_log_20260420_123426.txt` | Second failed retest log preserved. |
