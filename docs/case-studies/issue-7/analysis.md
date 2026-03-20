# Case Study: Issue #7 — Arm Separation and Z-Index Layering Bugs

## Overview

**Issue:** After the arm hierarchy refactor (PR #1205 / Issue #1204), the player's right arm appears
detached from the body across multiple iterations of bug fixing.

**Reported by:** @Jhon-Crow (repository owner)
**Reported in:** PR #1205 comments, 2026-03-20
**Issue reference:** https://github.com/Jhon-Crow/godot-topdown-MVP/issues/7
**PR reference:** https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1205

---

## Timeline / Sequence of Events

### Iteration 1 — Hierarchy fix (commit `1c2ba603`)

**Fix:** Made `RightForearm` a child of `RightShoulder` in the scene tree.

**Problem introduced:** `Scripts/Characters/Player.cs` `UpdateReloadAnimation()` still animated
`_rightArmSprite.Position` toward `(0, 0)`, lerping the forearm away from the shoulder joint
(its correct local offset is `(-26, 0)`). This caused the forearm to visually detach from the shoulder
after each reload.

### Iteration 2 — Stop animating forearm position in C# reload (commit `bc73d106`)

**Fix:** Removed `_rightArmSprite.Position` animation from C# `UpdateReloadAnimation()`.

**Problem introduced:** Shoulder z_index was still 4 (same as original), meaning it appeared IN FRONT
of the body. Owner feedback: "shoulder should be hidden under the body."

### Iteration 3 — Fix z-index, add elbow bend (commit `f36f1844`)

**Fix attempted:** Set `RightShoulder` z_index=0 (hidden), set `RightForearm` z_as_relative=false
with z_index=4 (absolute, visible). Added `forearm_local_rot` to create elbow bend animation.

**Problem introduced:** Z-index was applied to the WRONG node. The semantics are:
- `RightShoulder` (position 24, 6) = the **outer/gun-side** arm segment — extends toward the weapon
- `RightForearm` (position -2, 6 absolute) = the **inner/body-side** arm segment — overlaps the body

Hiding the outer arm (shoulder at z=0) made the gun-side arm invisible, creating the visual
appearance of a disconnected or missing arm.

### Iteration 4 — Correct z-index assignment (current fix)

**Fix:** Swap z-index values:
- `RightShoulder` z_index=4: **visible** (outer/gun-side arm, extends toward weapon)
- `RightForearm` z_as_relative=false, z_index=0: **hidden** behind body (inner/body-side arm, overlaps body)

---

## Root Cause Analysis

### The Core Confusion

The sprite naming creates a semantic trap:
- **"RightShoulder"** sounds like the body-side piece (shoulder socket) → should be HIDDEN
- **"RightForearm"** sounds like the far piece (gun-holding hand) → should be VISIBLE

But in the actual scene layout:
- `RightShoulder` is at position **(24, 6)** — **far from body center** (-4, 0), toward the gun
- `RightForearm` is at absolute position **(-2, 6)** — **near body center**, overlapping the body

The names describe the anatomical role of each sprite in the context of the original arm orientation
(where the "shoulder" attaches at the body and the "forearm" extends outward), but since the player
faces RIGHT in the default orientation:
- The sprite at x=24 (far right) is the forearm/hand side
- The sprite at x=-2 (near center) is the shoulder/elbow side

### Geometry

Both sprites are 20x8 pixels (at scale 1.3 = 26x10.4 rendered):
- `RightShoulder` center at (24, 6): spans x=11 to x=37 — **outside the body area, toward gun**
- `RightForearm` center at (-2, 6): spans x=-15 to x=11 — **overlaps body, should be hidden**

The body sprite is centered at (-4, 0) and extends to cover the shoulder/elbow area (x=-15 to x=6 approximately). This confirms that `RightForearm` (the body-side piece) should be hidden under the body, while `RightShoulder` (the gun-side piece) should remain visible.

### Z-index Layout (Correct)

```
z=0 (hidden): RightForearm (body-side, overlaps body — hidden behind it)
z=1:          Body
z=3:          Head
z=4:          RightShoulder (gun-side, visible in front), Weapon
z=5:          Armband
```

---

## Fix Summary

### Scene files

- `scenes/characters/Player.tscn`
- `scenes/characters/csharp/Player.tscn`

```
RightShoulder: z_index=4  (was 0)
RightForearm:  z_index=0, z_as_relative=false  (was z_index=4)
```

### Code files

- `scripts/characters/player.gd`: Set shoulder z_index=4 in init
- `Scripts/Characters/Player.cs`: Set shoulder ZIndex=4 in init and `RestoreArmZIndex()`

---

## Prevention

1. **Naming vs geometry**: When z-index layering is determined by POSITION not just role, document
   the actual screen position (e.g., "outer arm, x=24, toward gun") not just the anatomical name.

2. **Test z-index changes visually**: After changing z-index, verify in-game that all arm segments
   appear correctly at idle AND during animations.

3. **Parent-child z-index with z_as_relative=false**: When using `z_as_relative=false` on a child
   node, the z_index is absolute and independent of the parent. This means hiding the parent does NOT
   hide the child. Always set z-index independently for each node that uses `z_as_relative=false`.

---

## Related Issues and PRs

- Issue #1204 / PR #1205: The arm hierarchy refactor
- Issue #448 / PR #449: Previous arm separation attempt (lerp divergence)
- Issue #7: Original weapon system request

---

## Evidence

- `bug_current.png` — Screenshot showing broken state (first iteration)
- `bug_expected.png` — Screenshot showing expected state
