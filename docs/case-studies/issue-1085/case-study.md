# Case Study: Issue #1085 — Trajectory Glasses Ray Blink Not Visible

## Overview

**Issue:** Ray blink warning for trajectory glasses was implemented in code but never visible to the player.
**Root Cause:** `Player.cs::DrawTrajectoryGlasses()` (C#) did not check the `trajectory_ray_visible` flag computed by the GDScript controller.
**Fix:** Added a single guard check in `DrawTrajectoryGlasses()` to return early when `trajectory_ray_visible == false`.

---

## Timeline / Sequence of Events

| Time | Event |
|------|-------|
| PR #1055 | Removed the trajectory glasses progress bar (Issue #1049). Replaced with a simple single low-time blink at ≤ 2 s. |
| Issue #1085 opened | Owner requests two-phase blink: **one-shot blink at 25% remaining** (2.5 s) and **continuous blink at 4 s remaining**. |
| PR #1086 (commit bd0b31c7) | Blink logic added to `trajectory_glasses_effect.gd`. A `trajectory_ray_visible` boolean is computed every frame. |
| PR #1086 (commit 9ed1bd48) | Single-blink timeline corrected (fires inside continuous blink zone). |
| 2026-03-17 | User tests the release build (Windows) and reports blinking never appears. Attaches `game_log_20260317_063830.txt`. |
| 2026-03-17 | AI analysis: log shows **zero blink state log entries** across two full 10-second activations. GDScript logic ran correctly, but the C# drawing code never read the flag. |
| 2026-03-17 | Root cause confirmed and fix applied: `Player.cs::DrawTrajectoryGlasses()` now checks `trajectory_ray_visible` before drawing. |

---

## Root Cause Analysis

The project is a hybrid C# / GDScript Godot 4 game. The trajectory glasses effect is implemented in GDScript (`trajectory_glasses_effect.gd`) but the player character and all drawing are in C# (`Player.cs`).

### The Bug

`trajectory_glasses_effect.gd` computes `trajectory_ray_visible` correctly each frame:
- Normal phase (> 4 s remaining): `true`
- Continuous blink (≤ 4 s remaining): toggled at 3 Hz
- Single-blink at 25% (≤ 2.5 s): forced `false` for half a blink period, then `true`

`Player.cs::DrawTrajectoryGlasses()` (line 6429) reads `is_active`, `trajectory_local_points`, and `trajectory_invalid_start_index` via `_trajectoryGlassesEffect.Get(...)` — but **never reads `trajectory_ray_visible`**.

The GDScript `player.gd` equivalent function did have the check (line 2840):
```gdscript
if not _trajectory_glasses.trajectory_ray_visible:
    return
```

But the game executable uses `Player.cs`, not `player.gd`. The GDScript player is a legacy file that is no longer active.

### Evidence from Game Log

`game_log_20260317_063830.txt` (attached):
- Activation 1: `06:38:36` → Deactivation: `06:38:46` (full 10 s, no blink logs)
- Activation 2: `06:38:49` → Deactivation: `06:38:59` (full 10 s, no blink logs)
- **Total `[TrajectoryGlasses]` log entries: 5237 lines, zero contain "blink", "ray_visible", or "continuous"**

This confirms the GDScript blink logic was never logging its state changes — the blink phase code wasn't reached in a way that produced output. After adding log statements to the blink branch, the absence of any such logs would immediately reveal the visual draw path was ignoring the flag.

---

## The Fix

**File:** `Scripts/Characters/Player.cs`
**Method:** `DrawTrajectoryGlasses()` (line ~6441)

Added immediately after the `is_active` guard:
```csharp
// Skip drawing during the "off" phase of the blink cycle (Issue #1085).
bool rayVisible = (bool)_trajectoryGlassesEffect.Get("trajectory_ray_visible");
if (!rayVisible)
{
    return;
}
```

This mirrors the existing check in `scripts/characters/player.gd:2840`.

---

## Additional Changes

### Logging Added (`trajectory_glasses_effect.gd`)

To make future regressions immediately visible in logs:
- **Continuous blink phase start**: logged once per activation when `_effect_timer` first drops below `CONTINUOUS_BLINK_THRESHOLD`
- **Blink state transitions**: logged whenever `trajectory_ray_visible` changes
- **Single-blink trigger**: logged when the one-shot flash fires

These use `FileLogger.info` and produce no output during the normal (solid) phase.

---

## Contributing Factors

1. **Hybrid C#/GDScript architecture**: The GDScript `player.gd` was kept as a legacy file with correct logic, but the active code path is `Player.cs`. Changes to one don't automatically propagate to the other.

2. **No log coverage for blink path**: Before this fix, zero log messages were emitted from the blink logic branch, making it impossible to diagnose via logs alone.

3. **Previous PR (#1055) set the pattern**: The old `LOW_TIME_WARNING` blink was implemented in the GDScript controller only — and also would have had the same bug in the C# draw path if it was ever tested more carefully. PR #1055 happened to work because it targeted `trajectory_glasses_hud.gd` (a separate UI node) rather than the ray itself.

---

## Artifacts

- [`game_log_20260317_063830.txt`](game_log_20260317_063830.txt) — User-provided log confirming no blink output during two activations
