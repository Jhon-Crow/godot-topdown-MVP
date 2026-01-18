# Case Study: Issue #98 - Tactical Enemy Movement and Wall Detection

## Executive Summary

This case study addresses issue #98 which requests tactical movement for enemies, along with improvements to wall/passage detection to prevent enemies from sticking to walls or attempting to walk through them.

**Status**: First implementation attempt FAILED - caused complete enemy AI breakdown.

---

## Issue Overview

### Original Request

**Issue #98** (Created: 2026-01-18)
- **Title**: update ai враги должны перемещаться тактически
- **Author**: Jhon-Crow (Repository Owner)

**Translated Requirements**:
1. Enemies should move tactically (reference: [Building Catch Tactics](https://poligon64.ru/tactics/70-building-catch-tactics))
2. Enemies should understand where passages are (not stick to walls, not try to walk into walls)
3. Update old behavior with new movement (within GOAP framework)
4. Preserve all previous functionality

### Reference Article Analysis

The reference article describes military tactical movement patterns for building clearance:

1. **Formation Movement**: Triangular "clover leaf" formation with leader at apex
2. **Sector Coverage**: Divide rooms into zones, work sector to completion before advancing
3. **Corridor Operations**: Overlapping fields of fire, cross visual axes
4. **Corner/Intersection Handling**: Back-to-back positioning, coordinated simultaneous clearance
5. **Entry Techniques**: "Cross" and "Hook" methods for room entry

---

## First Implementation Attempt (FAILED)

### What Was Done

Commit `0b694b7` ("Enhance tactical movement with improved wall avoidance and path validation") introduced:

1. **Enhanced wall detection**: Changed from 3 to 8 raycasts
2. **New constants**:
   - `WALL_CHECK_DISTANCE`: 40 → 60 pixels
   - `WALL_CHECK_COUNT`: 3 → 8
   - New `WALL_AVOIDANCE_MIN_WEIGHT`, `WALL_AVOIDANCE_MAX_WEIGHT`, `WALL_SLIDE_DISTANCE`
3. **New functions**:
   - `_apply_wall_avoidance()` - wrapper function for wall avoidance
   - `_get_wall_avoidance_weight()` - distance-based weight calculation
4. **Modified `_check_wall_ahead()`**: Completely rewrote with 8-raycast system
5. **Cover position validation**: Added `_can_reach_position()` checks to `_find_cover_position()` and `_find_cover_closest_to_player()`

### What Went Wrong

**User Feedback:**
> "всё сломалось как было много раз до этого. враги не получают урон и не действуют. f7 перестало работать. в логе ничего."

Translation:
> "Everything broke like before. Enemies don't take damage and don't act. F7 stopped working. Nothing in logs."

### Root Cause Analysis

The CI build logs revealed a **GDScript parse error** in `enemy.gd`:

```
SCRIPT ERROR: Parse Error: Cannot infer the type of "angle_offset" variable because the value doesn't have a set type.
          at: GDScript::reload (res://scripts/objects/enemy.gd:2812)
ERROR: Failed to load script "res://scripts/objects/enemy.gd" with error "Parse error".
```

**The Bug (Line 2812)**:
```gdscript
var angles := [0.0, -0.35, -0.79, -1.22, 0.35, 0.79, 1.22, PI]
# ...
var angle_offset := angles[i] if i < angles.size() else 0.0  # ← ERROR HERE
```

**Why It Failed**:
1. The `angles` array is declared without explicit typing: `var angles := [...]`
2. This creates a generic `Array` (not `Array[float]`)
3. Accessing `angles[i]` returns a `Variant` (untyped value)
4. The ternary expression `angles[i] if ... else 0.0` has type ambiguity
5. GDScript cannot infer whether `angle_offset` should be `Variant` or `float`
6. Parse error causes **entire script to fail loading**

**Cascade Effect**:
When `enemy.gd` fails to load:
- All enemy instances have no AI (no movement, no shooting)
- Damage processing doesn't work (no hit registration)
- F7 debug toggle doesn't work (debug label not toggled)
- No errors in game logs (script never loads to produce runtime errors)

### Comparison to Issue #94

This is **identical** to the failure pattern documented in issue #94 case study:

> After the second implementation, users reported that AI was completely broken - enemies didn't move, didn't respond to damage, and F7 debug toggle didn't work.
>
> Upon examining the CI build logs, we discovered **GDScript parse errors** in the `enemy.gd` file

The same mistake was made: using `:=` (type inference) with array element access inside a conditional expression.

---

## Lessons Learned

### 1. Type Annotations in GDScript 4.x

When working with arrays in GDScript 4.x with type inference (`var x := ...`):

**WRONG** (causes parse error):
```gdscript
var angles := [0.0, -0.35, -0.79, 1.22]  # Untyped Array
var angle_offset := angles[i] if i < angles.size() else 0.0  # ERROR
```

**CORRECT** options:

Option A - Explicit type annotation on result:
```gdscript
var angles := [0.0, -0.35, -0.79, 1.22]
var angle_offset: float = angles[i] if i < angles.size() else 0.0
```

Option B - Type the array:
```gdscript
var angles: Array[float] = [0.0, -0.35, -0.79, 1.22]
var angle_offset := angles[i] if i < angles.size() else 0.0
```

Option C - Avoid ternary, use if/else:
```gdscript
var angle_offset := 0.0
if i < angles.size():
    angle_offset = angles[i]
```

### 2. Always Check CI Logs

Even when CI reports "success", there may be parse errors logged during the import phase. The CI succeeded because:
- Unit tests run in isolation with mocks
- Enemy script isn't directly loaded by test framework
- Parse errors appear in logs but don't fail the job

### 3. This Pattern Keeps Repeating

This is the **second time** this exact failure mode has occurred:
- Issue #94: Same parse error, same symptoms
- Issue #98: Same parse error, same symptoms

**Recommendation**: Add a CI check that specifically validates all GDScript files for parse errors before running tests.

---

## Resolution

The problematic commit was reverted, restoring `enemy.gd` to the main branch version.

**Commit**: Reverted `scripts/objects/enemy.gd` to upstream/main

---

## Next Steps (For Future Implementation)

If tactical movement is to be implemented again, follow these guidelines:

1. **Test parse locally first**: Run Godot with `--headless --validate` to catch parse errors
2. **Use explicit types**: Never use `:=` with array element access in conditionals
3. **Make minimal changes**: Don't rewrite entire functions - modify incrementally
4. **Preserve working code**: The existing wall avoidance works - enhance it, don't replace it
5. **Follow the conservative pattern from issue #94**: Small, targeted changes with fail-open safety

---

## Timeline

- **2026-01-18 04:50**: Issue #98 created
- **2026-01-18 05:00**: First implementation (commit 0b694b7)
- **2026-01-18 05:04**: CI shows parse error in logs (but job "succeeds")
- **2026-01-18 05:06**: User reports complete AI breakdown
- **2026-01-18 05:07**: Investigation started
- **2026-01-18**: Root cause identified, changes reverted

---

## Files Modified

1. `scripts/objects/enemy.gd` - Reverted to main branch
2. `docs/case-studies/issue-98/README.md` - This case study

---

## Appendix: CI Log Evidence

From CI run 21106363298:
```
Run Unit Tests	Import project assets	2026-01-18T05:01:29.6579168Z SCRIPT ERROR: Parse Error: Cannot infer the type of "angle_offset" variable because the value doesn't have a set type.
Run Unit Tests	Import project assets	2026-01-18T05:01:29.6580434Z           at: GDScript::reload (res://scripts/objects/enemy.gd:2812)
Run Unit Tests	Import project assets	2026-01-18T05:01:29.6589037Z ERROR: Failed to load script "res://scripts/objects/enemy.gd" with error "Parse error".
Run Unit Tests	Import project assets	2026-01-18T05:01:29.6589717Z    at: load (modules/gdscript/gdscript.cpp:2936)
```
