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

## Root Cause Analysis

### Bug 1: Aim Direction Feedback Loop

**File:** `Scripts/Weapons/SniperRifle.cs`, method `UpdateAimDirection()` (line ~413)

**Root Cause:** `UpdateAimDirection()` called `GetGlobalMousePosition()` every frame, even during scope mode. In scope mode, the camera offset depends on `_aimDirection`, and `GetGlobalMousePosition()` depends on the camera position. This created a feedback loop:

1. Mouse moves → `_scopeMouseOffset` changes (via `AdjustScopeFineTune`)
2. Camera offset changes (uses `_aimDirection` + `_scopeMouseOffset`)
3. `GetGlobalMousePosition()` returns a different world position (camera moved)
4. `UpdateAimDirection()` tries to rotate `_aimDirection` toward the new mouse world position
5. But rotation is rate-limited (sensitivity factor 0.2, ~7.6°/frame at 60fps)
6. `_aimDirection` lags behind the camera's actual pointing direction
7. Camera offset (which uses `_aimDirection`) jumps on next frame
8. Result: `_aimDirection` and camera are out of sync, bullets go to wrong position

**Fix:** Skip `UpdateAimDirection()` when scope is active. The scope has its own mouse offset system (`_scopeMouseOffset`) for controlling the view.

### Bug 2: Aim Target Calculation Mismatch

**File:** `Scripts/Weapons/SniperRifle.cs`, method `GetScopeAimTarget()` (line ~1088)

**Root Cause:** `GetScopeAimTarget()` independently calculated the world-space position of the crosshair using:
```
aimTarget = WeaponGlobalPosition + _aimDirection * baseDistance * zoom + _aimDirection * fineTune + _scopeMouseOffset
```

Meanwhile, the actual crosshair is at viewport center, and the viewport center shows whatever world position the camera is focused on. These calculations could differ due to:
- **Weapon offset**: The weapon is a child of the player at local position (0, 6), so `WeaponGlobalPosition ≠ PlayerGlobalPosition`. At scope distances of 1000+ pixels, even 6 pixels of base offset creates ~10-15 pixels of angular error at the target.
- **Camera smoothing**: The Camera2D has `position_smoothing_enabled = true`, meaning the camera lags behind the player. The aim target calculation used the weapon's current position, not the camera's smoothed position.
- **Frame timing**: `UpdateAimDirection()` ran before `UpdateScope()`, so the `_aimDirection` used stale camera state from the previous frame.

**Fix:** Use `Camera2D.GetScreenCenterPosition()` to get the exact world position at viewport center. This Godot API returns the actual camera center position, automatically accounting for smoothing, offset, and all transforms.

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
| `Scripts/Weapons/SniperRifle.cs` | Freeze `_aimDirection` during scope mode; use `Camera2D.GetScreenCenterPosition()` for aim target |

## Lessons Learned

1. **Avoid feedback loops between camera and aim direction**: When a camera offset depends on a direction value, and that direction is computed from mouse position (which depends on the camera), the two systems fight each other. The solution is to freeze one system while the other is in control.

2. **Use the camera's actual position for aim target**: Instead of independently calculating where the viewport center should be, query the camera directly with `GetScreenCenterPosition()`. This automatically handles smoothing, offsets, and frame timing.

3. **Position smoothing + offset interaction**: Camera2D smoothing applies to position tracking, not to the offset. But the smoothed position means the camera center differs from the anchor node's position. Any aim calculation must use the camera's actual center, not the anchor's position.

4. **GD.Print vs FileLogger**: C# `GD.Print()` output does not appear in the GDScript-based FileLogger. For debugging exported builds, C# code should call the FileLogger autoload directly.
