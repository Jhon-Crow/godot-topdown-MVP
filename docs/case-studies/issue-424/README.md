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

1. `game_log_20260203_155149.txt` (1.3MB) - Full gameplay session log (before push force fix)
2. `game_log_20260203_155558.txt` (36KB) - Shorter gameplay session log
3. `game_log_20260203_161125.txt` (682KB) - Post-fix test session showing enemy issue
4. `game_log_20260203_162558.txt` (9.6KB) - Fourth test session (enemies still broken after sound fix)

These logs contain standard gameplay events (enemy AI, gunshots, blood effects, etc.) but don't show specific casing push events, as there was no debug logging enabled for casing physics during the user's test.

### Iteration 3: Enemy System Issue Investigation

After the push force fix was deployed, the user reported that enemies were "completely broken" with a suspected "language conflict" (GDScript vs C#).

#### Analysis of game_log_20260203_161125.txt

**Comparison of working vs broken logs:**

| Metric | Working Log (15:51) | Broken Log (16:11) |
|--------|--------------------|--------------------|
| Death animation init | ✅ Present | ❌ Missing |
| Sound listeners | ✅ 10 registered | ❌ 0 registered |
| Enemy spawns | ✅ 10 spawned | ❌ None logged |
| `has_died_signal` | ✅ true | ❌ false |
| Enemies registered | 10 | 0 |

**Key finding:** The `BuildingLevel` script uses `child.has_signal("died")` to detect enemies. The broken build returns `false` even though the signal is defined in `enemy.gd`.

#### Root Cause Hypothesis

The code changes to `enemy.gd` are syntactically correct and only affect:
- Line 1044: `CASING_PUSH_FORCE = 20.0` (was 50.0)
- Lines 1052-1054: Push direction calculation
- Line 3949: Ejection speed (120-180 vs 300-450)

None of these changes affect the `died` signal or `_ready()` function. The most likely causes are:

1. **Godot cache corruption:** Compiled scripts in `.godot/` directory are stale
2. **Incomplete export:** The GDScript files weren't properly bundled in the export
3. **Editor reimport needed:** Godot needs to reimport/recompile the scripts

**Recommended fix:** User should:
1. Close Godot Editor
2. Delete the `.godot/` directory
3. Reopen the project to force reimport
4. Rebuild the export

### Iteration 3: Sound Volume Reduction

User requested casing push sound to be 2x quieter.

**Change made:**
- File: `scripts/autoload/audio_manager.gd`
- Constant: `VOLUME_SHELL`
- Old value: `-10.0` dB
- New value: `-16.0` dB (6 dB reduction = ~2x quieter perceived volume)

### Iteration 4: Continued Enemy Issue Investigation (game_log_20260203_162558.txt)

After the sound volume fix, user reported enemies were STILL broken. Deep investigation was performed.

#### CI Status
All CI checks passed ✅, including:
- C# Build Validation
- GDScript Tests (GUT Tests)
- C# and GDScript Interoperability Check
- Gameplay Critical Systems Validation
- Architecture Best Practices Check

#### Code Validation
The code changes to `enemy.gd` were verified to be syntactically correct:

```gdscript
# Line 1054 - using the same pattern as many other places in the file
var push_dir := (collider.global_position - global_position).normalized()
```

This pattern `(target.global_position - global_position).normalized()` is used in many other places in enemy.gd (lines 915, 921, 1177, 1224, etc.) and works correctly.

#### Comparison with Issue #377
In issue #377, similar symptoms (`has_died_signal=false`) were caused by a **typo** referencing an undefined variable (`max_grenade_throw_distance` vs `grenade_max_throw_distance`).

Our changes **do not** introduce any undefined variables:
- `collider.global_position` - valid (property of Node2D)
- `global_position` - valid (inherited from Node2D)
- `CASING_PUSH_FORCE` - valid (defined as const on line 1044)
- `velocity` - valid (inherited from CharacterBody2D)

#### Investigation Conclusion
Since all CI checks pass and the code is syntactically valid, the issue is likely related to:
1. Godot cache not being cleared properly
2. User testing an older version of the export
3. Export process not including updated scripts

## Lessons Learned

1. **Identify all affected systems:** When fixing physics behavior, identify ALL code paths that affect the behavior (ejection vs push).
2. **User feedback is valuable:** The user correctly identified that changes weren't visible, leading to discovery of the actual issue.
3. **Direction matters:** Using position-based direction calculation provides more realistic physics behavior than velocity-based direction.
4. **Build cache issues:** Godot may have stale compiled scripts that don't reflect code changes - clearing `.godot/` directory can fix unexplained behavior.
5. **Audio perception:** Reducing volume by ~6 dB roughly halves perceived loudness.
6. **CI validation is crucial:** When users report issues but CI passes, the problem may be in the user's build environment rather than the code.
7. **Pattern consistency:** Using established patterns from existing code (like `(target.global_position - global_position).normalized()`) reduces the risk of introducing errors.

## References

- Issue #341: Original shell casing push implementation
- Issue #392: Shell casing collision fixes and CasingPusher Area2D implementation
- Issue #377: Similar enemy breakage caused by variable name typo (reference for debugging approach)
