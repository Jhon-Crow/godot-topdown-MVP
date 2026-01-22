# Case Study: Issue #252 - Fix Trajectory Debug

## Overview

- **Issue**: [#252 - fix trajecotry debug](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/252)
- **Pull Request**: [#253 - Fix grenade trajectory debug to match actual throw distance](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/253)
- **Status**: Draft (pending CI verification)
- **Date**: 2026-01-22

## Problem Statement

PR #248 added grenade trajectory debug visualization, but the C# implementation didn't correctly show the actual throw range. The debug trajectory showed a shorter distance than where the grenade would actually land.

### Original Issue (translated from Russian)

> "Debug for grenade throw trajectory was added in PR #248, but it incorrectly shows the throw range (should show actual range). It should get range data from the grenade's range calculation function (range depends on mouse movement speed)."

## Timeline of Events

| Timestamp | Event |
|-----------|-------|
| 2026-01-22 ~13:58 | Issue #252 created by Jhon-Crow |
| 2026-01-22 13:59:33 | First AI work session started |
| 2026-01-22 13:59:39 | PR #253 created as draft |
| 2026-01-22 14:05:56 | CI runs triggered on commit 2f885f2 |
| 2026-01-22 14:06:05 | GitHub Internal Server Error (HTTP 500) during checkout |
| 2026-01-22 14:06:50 | "Check Architecture Best Practices" job failed after 3 retries |
| 2026-01-22 14:09:35 | First AI session completed (interrupted by rate limit) |
| 2026-01-22 15:33:45 | User reported CI failure and requested case study |
| 2026-01-22 15:34:24 | Second AI work session started |

## Root Cause Analysis

### Code Issue (Primary)

The C# `Player.cs` implementation was missing the `9x` sensitivity multiplier that exists in GDScript `player.gd`:

**GDScript `player.gd` (lines 1416-1417):**
```gdscript
# Increase throw sensitivity significantly - multiply drag distance by 9x
var sensitivity_multiplier := 9.0
var adjusted_drag_distance := drag_distance * sensitivity_multiplier
```

**C# `Player.cs` (before fix):**
```csharp
// Pass raw drag distance to grenade (no multiplier!)
_activeGrenade.Call("throw_grenade", throwDirection, dragDistance);
```

This caused two issues:
1. The C# player's debug visualization used raw `dragDistance` instead of the adjusted value
2. The throw itself passed raw distance to the grenade, but the grenade applies its own multiplier

### CI Failure (Secondary/Transient)

The "Check Architecture Best Practices" workflow failed due to **GitHub infrastructure issues**, not code problems:

```
2026-01-22T14:06:05.0174532Z remote: Internal Server Error
##[error]fatal: unable to access 'https://github.com/Jhon-Crow/godot-topdown-MVP/':
The requested URL returned error: 500
```

The workflow attempted 3 retries over ~50 seconds before failing. This was a transient GitHub server issue.

## Solution Applied

### Code Fix

1. Added `ThrowSensitivityMultiplier = 9.0f` constant to match GDScript
2. Applied the multiplier in `ThrowGrenade()` before passing to grenade
3. Applied the same multiplier in `_Draw()` for accurate debug visualization
4. Added clamping to `viewport.width * 3` to match GDScript behavior

**Key changes in `Player.cs`:**
```csharp
private const float ThrowSensitivityMultiplier = 9.0f;

// In ThrowGrenade():
float adjustedDragDistance = dragDistance * ThrowSensitivityMultiplier;
adjustedDragDistance = Mathf.Min(adjustedDragDistance, maxDragDistance);
_activeGrenade.Call("throw_grenade", throwDirection, adjustedDragDistance);

// In _Draw():
float adjustedDragDistance = dragDistance * ThrowSensitivityMultiplier;
// ... use adjustedDragDistance for trajectory calculation
```

### CI Fix

The CI failure was transient. Re-running the workflow should succeed.

## Files Changed

| File | Changes |
|------|---------|
| `Scripts/Characters/Player.cs` | +38/-8 lines - Added sensitivity multiplier to throw and debug visualization |

## Lessons Learned

1. **Feature Parity**: When porting features between languages (GDScript to C#), ensure all constants and multipliers are carried over, not just the basic logic.

2. **Debug Visualization Accuracy**: Debug visualizations should use the exact same calculations as the actual gameplay code to avoid confusion.

3. **CI Transient Failures**: GitHub infrastructure can experience temporary issues (HTTP 500). These should be handled by re-running workflows rather than investigating code changes.

## Test Plan

- [ ] Enable debug mode with F7 key
- [ ] Hold G to prepare grenade, then hold RMB and drag to aim
- [ ] Verify trajectory line shows correct predicted range
- [ ] Release RMB to throw and confirm grenade lands near predicted position

## References

- [PR #248 - Add grenade throw trajectory debug visualization](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/248)
- [Issue #247 - Add grenade throw trajectory debug](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/247)
- [Case Study: Issue #247](../issue-247/)
