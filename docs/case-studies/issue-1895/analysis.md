# Issue #1895 — Case Study: Drone Grenade Weapon/Item Use

## Timeline of Events

### Original Issue
Issue #1895 requested that while piloting the drone grenade, the player should be able to fire their weapon (LMB) and use their active item (Space). The first PR #1905 commit implemented `ShootFromDrone` and `TriggerActiveItemFromDrone` in `Player.cs` and wired up LMB/Space in `drone_grenade.gd`.

### Owner Feedback (2026-04-20 12:25)
Five bugs reported after testing with AKGL + Flashlight (game log `game_log_20260420_122158.txt`):

1. **AKGL underbarrel grenade launcher (RMB) doesn't work during drone**
2. **Bullets don't follow laser sight — aim desync**
3. **Flashlight direction doesn't change with player rotation during drone**
4. **Dash (рывок) doesn't work during drone**
5. **Player model doesn't rotate with weapon during drone**

Screenshot `screenshot_player_rotation_desync.png` shows the player body frozen pointing the wrong direction while the weapon/laser aim somewhere else.

---

## Root Cause Analysis

### Core Problem: `set_physics_process(false)` disables ALL processing

The drone's `_disable_player_control()` method checks `has_method("set_drone_piloting")`. The GDScript `player.gd` has this method. The **C# `Player.cs`** did NOT, so the drone fell back to `_player.set_physics_process(false)`.

With `set_physics_process(false)` the entire `_PhysicsProcess` is skipped — including `UpdatePlayerModelRotation()`. The player body froze in its last rotation.

### Bug 1: AKGL (RMB) not handled
`TriggerActiveItemFromDrone` and the drone input block only handled LMB (shoot) and Space (active item). RMB `grenade_throw` for AKGL was never forwarded.

### Bug 2 & 3: Laser sight / flashlight desync
Both are children of `PlayerModel`. `PlayerModel.Rotation` is set by `UpdatePlayerModelRotation()`. Since `_PhysicsProcess` was disabled, `PlayerModel` rotation never updated. Laser sight and flashlight pointed in a fixed direction.

### Bug 4: Dash not in `TriggerActiveItemFromDrone`
`HandleDashInput()` is called from `_PhysicsProcess` but was missing from `TriggerActiveItemFromDrone`. With `set_physics_process(false)`, Space for dash was never processed.

### Bug 5: Player model frozen
Same root cause as bugs 2 & 3 — `UpdatePlayerModelRotation()` skipped.

---

## Solution

### `Scripts/Characters/Player.cs`

1. **Added `_isDronePiloting` flag** — replaces relying on `set_physics_process(false)`.
2. **Added `SetDronePiloting(bool active)`** — public method callable from GDScript.
3. **`_PhysicsProcess` drone mode block** — when `_isDronePiloting` is true: stop movement, call `MoveAndSlide()`, call `UpdatePlayerModelRotation()`, then return. This keeps the model tracking the mouse.
4. **`TriggerActiveItemFromDrone`** — added `HandleDashInput()`.
5. **`FireAKGLFromDrone()`** — new public method that fires the AKGL underbarrel launcher toward the mouse cursor.

### `scripts/projectiles/drone_grenade.gd`

1. **`_disable_player_control` / `_restore_player_control`** — now also check `has_method("SetDronePiloting")` for the C# player before falling back to `set_physics_process`.
2. **Input block in `_physics_process`** — added RMB (`grenade_throw`) detection to call `FireAKGLFromDrone()`.

---

## Files Changed
- `Scripts/Characters/Player.cs`
- `scripts/projectiles/drone_grenade.gd`

## Log Evidence
`game_log_20260420_122158.txt` — AKGL + Flashlight equipped, drone launched at 12:22:11. No `ShootFromDrone` calls logged → confirms the fallback to `set_physics_process(false)` was causing the root issue.

`game_log_20260420_121813.txt` — Same pattern without flashlight; second session added flashlight via armory at 12:19:16, confirming the desync issue only manifests with active items that require model rotation.
