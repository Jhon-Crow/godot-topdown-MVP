# Case Study: Issue #538 — ASVK Scope Crosshair Aiming Bug

## Problem Statement

After the sniper rifle (ASVK) was added in PR #532, bullets fired in scope/aiming mode did not fly to the center of the crosshair. The user reported: "в режиме прицеливания пули летят не в центр прицела" (in aiming mode, bullets don't fly to the center of the crosshair).

## Timeline

| Time (UTC) | Event |
|---|---|
| 2026-02-06 20:14 | PR #528 merged: ASVK scope system with distance-based sensitivity |
| 2026-02-06 20:50 | PR #532 merged: Redesign ASVK sniper rifle mechanics (bolt-action, sounds, visuals, scope) |
| 2026-02-07 00:35 | Issue #538 filed: scope crosshair aiming still broken after PR #532 |
| 2026-02-07 03:23–03:33 | User testing sessions producing 3 game log files |
| 2026-02-07 03:17 | PR #547 opened: initial fix (freeze `_aimDirection` + use `GetScreenCenterPosition()`) |
| 2026-02-07 03:53 | User feedback on PR #547: bullets hit correctly but scope view doesn't move at all |
| 2026-02-07 06:51 | User game log `game_log_20260207_065116.txt` — confirms scope control regression |
| 2026-02-07 ~10:50 | Revised fix: remove `_aimDirection` freeze, keep only `GetScreenCenterPosition()` targeting |

## Root Cause Analysis

### The Aim Direction Feedback Loop (Context)

**File:** `Scripts/Weapons/SniperRifle.cs`, method `UpdateAimDirection()` (line ~413)

**Observation:** `UpdateAimDirection()` calls `GetGlobalMousePosition()` every frame. In scope mode, the camera offset depends on `_aimDirection`, and `GetGlobalMousePosition()` depends on the camera position. This creates a feedback loop where `_aimDirection` lags behind the camera's actual pointing direction due to rate-limited rotation (~7.6°/frame at 60fps).

**Important:** This feedback loop causes `_aimDirection` to lag, but it does NOT need to be fixed by freezing `_aimDirection`. Freezing it would break scope view movement entirely (the scope camera offset depends on `_aimDirection` to follow the mouse). Instead, the fix is to decouple bullet targeting from `_aimDirection`.

### Root Cause: Aim Target Calculation Mismatch

**File:** `Scripts/Weapons/SniperRifle.cs`, method `GetScopeAimTarget()` (line ~1078)

**Root Cause:** `GetScopeAimTarget()` independently calculated the world-space position of the crosshair using:
```
aimTarget = WeaponGlobalPosition + _aimDirection * baseDistance * zoom + _aimDirection * fineTune + _scopeMouseOffset
```

Meanwhile, the actual crosshair is at viewport center, and the viewport center shows whatever world position the camera is focused on. These calculations could differ due to:
- **Aim direction lag**: `_aimDirection` lags behind the camera view due to the feedback loop (rate-limited rotation)
- **Weapon offset**: The weapon is a child of the player at local position (0, 6), so `WeaponGlobalPosition ≠ PlayerGlobalPosition`. At scope distances of 1000+ pixels, even 6 pixels of base offset creates ~10-15 pixels of angular error at the target.
- **Camera smoothing**: The Camera2D has `position_smoothing_enabled = true`, meaning the camera lags behind the player. The aim target calculation used the weapon's current position, not the camera's smoothed position.
- **Frame timing**: `UpdateAimDirection()` ran before `UpdateScope()`, so the `_aimDirection` used stale camera state from the previous frame.

**Fix:** Use `Camera2D.GetScreenCenterPosition()` to get the exact world position at viewport center. This Godot API returns the actual camera center position, automatically accounting for smoothing, offset, and all transforms. This decouples bullet targeting from `_aimDirection`, so even though `_aimDirection` lags slightly, bullets always go exactly where the crosshair is displayed.

### Rejected Approach: Freezing _aimDirection

An earlier fix attempted to freeze `_aimDirection` during scope mode to prevent the feedback loop. While this made bullets hit the crosshair correctly (via `GetScreenCenterPosition()`), it completely broke scope view control — the scope view would not move at all when the mouse moved, because `_aimDirection` drives the scope camera offset via `GetScopeCameraOffset()`. User feedback confirmed: "пули летят куда надо, но пропало управление прицелом (вообще не двигается)" — "bullets fly where they should, but scope control is gone (doesn't move at all)".

## Evidence from Game Logs

All three game logs show:
- `Debug build: false` — exported release build
- Multiple `SniperRifle` gunshots fired (`SoundPropagation` events)
- **Zero `[SniperRifle]` log messages** — C# `GD.Print()` output goes to console but not to the FileLogger (GDScript-based)
- The C# code IS executing (SoundPropagation callbacks work)

## Mathematical Verification

Example with stationary player, demonstrating the weapon offset error:

| Parameter | Value |
|---|---|
| Player position | (500, 500) |
| Weapon position | (500, 506) — 6px Y offset |
| Viewport | 1280×720 |
| Base distance | 734.8 px |
| Zoom | 1.5× |
| `_aimDirection` | (1, 0) — pointing right |
| `_scopeMouseOffset` | (0, 100) |

- **Camera offset**: (1102.2, 100)
- **Viewport center world**: (1602.2, 600)
- **Old `GetScopeAimTarget()`**: (1602.2, 606) — 6px off due to weapon offset
- **Bullet direction** computed from player → aim target: (0.9954, 0.0957)
- **Bullet y-position at target x**: 612 — **12px miss from crosshair**

With `Camera2D.GetScreenCenterPosition()`, the aim target is exactly (1602.2, 600) — **0px miss**.

## Files Changed

| File | Change |
|---|---|
| `Scripts/Weapons/SniperRifle.cs` | Use `Camera2D.GetScreenCenterPosition()` for aim target in `GetScopeAimTarget()` |

## Lessons Learned

1. **Decouple bullet targeting from view control**: When the aim direction both controls the camera view AND determines where bullets go, any lag in the aim direction causes bullets to miss. The fix is to use the camera's actual position for bullet targeting (`GetScreenCenterPosition()`), while leaving the aim direction to control the camera view. This way the view follows the mouse smoothly, and bullets go exactly where the crosshair is displayed.

2. **Don't freeze variables that drive the UI**: Freezing `_aimDirection` during scope mode broke scope movement because `GetScopeCameraOffset()` depends on it to compute where the camera looks. The correct approach is to let the variable update naturally and fix the downstream calculation that produces incorrect results.

3. **Use the camera's actual position for aim target**: Instead of independently calculating where the viewport center should be, query the camera directly with `GetScreenCenterPosition()`. This automatically handles smoothing, offsets, and frame timing.

4. **Position smoothing + offset interaction**: Camera2D smoothing applies to position tracking, not to the offset. But the smoothed position means the camera center differs from the anchor node's position. Any aim calculation must use the camera's actual center, not the anchor's position.

5. **GD.Print vs FileLogger**: C# `GD.Print()` output does not appear in the GDScript-based FileLogger. For debugging exported builds, C# code should call the FileLogger autoload directly.
