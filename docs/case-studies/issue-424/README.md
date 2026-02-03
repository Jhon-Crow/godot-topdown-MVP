# Case Study: Issue #424 - Shell Casing Push Mechanics

## Issue Summary

**Title:** fix отталкивание гильз (fix shell casing push)
**Issue URL:** https://github.com/Jhon-Crow/godot-topdown-MVP/issues/424
**PR URL:** https://github.com/Jhon-Crow/godot-topdown-MVP/pull/425

## Original Problem

The shell casings were being pushed too far when players or enemies walked over them. The original issue requested that casings should be pushed approximately 2-3 times weaker.

## Timeline of Events

### 2026-02-03: Initial Solution Attempt

1. **First fix (commit 9e0d8e4):** Reduced the **ejection speed** of casings from `300-450` to `120-180` pixels/sec
   - This fix only affected the initial ejection when a weapon fires
   - It did NOT address the push mechanics when characters walk over casings

2. **User feedback:** User reported not seeing the changes and requested:
   - Direction-based push (based on angle from character center to casing)
   - The push force reduction

### Root Cause Analysis

The initial fix targeted the wrong parameter. There are TWO separate force systems for casings:

1. **Ejection Force** (when weapon fires):
   - `BaseWeapon.cs`: ejection speed 300-450 px/s (was fixed)
   - `enemy.gd`: ejection speed 300-450 px/s (was fixed)

2. **Push Force** (when character walks over casing):
   - `BaseCharacter.cs`: `CasingPushForce = 50.0f` (NOT fixed initially)
   - `Player.cs`: `CasingPushForce = 50.0f` (NOT fixed initially)
   - `player.gd`: `CASING_PUSH_FORCE = 50.0` (NOT fixed initially)
   - `enemy.gd`: `CASING_PUSH_FORCE = 50.0` (NOT fixed initially)

The user's complaint about not seeing changes was valid - the **push force** (which is what the user interacts with when walking over casings) was never reduced.

## Solution

### 1. Reduced Push Force by 2.5x

Changed push force from 50.0 to 20.0 in all locations:

| File | Before | After |
|------|--------|-------|
| `BaseCharacter.cs` | 50.0 | 20.0 |
| `Player.cs` | 50.0 | 20.0 |
| `player.gd` | 50.0 | 20.0 |
| `enemy.gd` | 50.0 | 20.0 |

### 2. Changed Push Direction to Position-Based

**Before:** Push direction was based on character's movement velocity
```gdscript
var push_dir := velocity.normalized()
```

**After:** Push direction is calculated from character center to casing position
```gdscript
var push_dir := (casing.global_position - global_position).normalized()
```

This change ensures that:
- Casings are pushed away from the character in a realistic manner
- The push direction depends on which side of the character the casing is on
- Casings don't all fly in the same direction regardless of their position

## Files Modified

1. `Scripts/AbstractClasses/BaseCharacter.cs` - Base character casing push (C#)
2. `Scripts/Characters/Player.cs` - Player Area2D-based casing push (C#)
3. `scripts/characters/player.gd` - Player casing push (GDScript)
4. `scripts/objects/enemy.gd` - Enemy casing push (GDScript)

## Technical Details

### Push Force Calculation

The push strength is calculated as:
```
push_strength = velocity.length() * CASING_PUSH_FORCE / 100.0
```

With the new force of 20.0, a character moving at 200 pixels/sec would apply:
- Old: `200 * 50 / 100 = 100` units of force
- New: `200 * 20 / 100 = 40` units of force (2.5x weaker)

### Direction Calculation

The new direction calculation:
```gdscript
var push_dir := (casing.global_position - global_position).normalized()
```

This vector points from the character's center outward to where the casing is located, ensuring casings are pushed radially away from the character.

## Attached Log Files

The following game logs were provided by the user for analysis:

1. `game_log_20260203_155149.txt` (1.3MB) - Full gameplay session log
2. `game_log_20260203_155558.txt` (36KB) - Shorter gameplay session log

These logs contain standard gameplay events (enemy AI, gunshots, blood effects, etc.) but don't show specific casing push events, as there was no debug logging enabled for casing physics during the user's test.

## Lessons Learned

1. **Identify all affected systems:** When fixing physics behavior, identify ALL code paths that affect the behavior (ejection vs push).
2. **User feedback is valuable:** The user correctly identified that changes weren't visible, leading to discovery of the actual issue.
3. **Direction matters:** Using position-based direction calculation provides more realistic physics behavior than velocity-based direction.

## References

- Issue #341: Original shell casing push implementation
- Issue #392: Shell casing collision fixes and CasingPusher Area2D implementation
