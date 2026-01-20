# Case Study: Issue #67 - Coordinated Flanking System Bug

## Problem Report

**Date**: 2026-01-20
**Reporter**: Jhon-Crow (repository owner)
**Report**: "враги полностью сломались" (enemies are completely broken)

## Evidence Collected

### Game Log Analysis

#### First Log (game_log_20260120_215529.txt)
```
[21:55:29] [INFO] GAME LOG STARTED
[21:55:29] [INFO] [GameManager] GameManager ready
[21:55:29] [INFO] [SoundPropagation] SoundPropagation autoload initialized
[21:55:47] [INFO] [SoundPropagation] Sound emitted: type=GUNSHOT, pos=(2634.438, 1146.578), source=PLAYER (AssaultRifle), range=1469, listeners=0
[21:55:47] [INFO] [SoundPropagation] Sound result: notified=0, out_of_range=0, self=0, below_threshold=0
```

#### Second Log (game_log_20260120_220549.txt) - After first fix attempt
```
[22:05:49] [INFO] GAME LOG STARTED
[22:05:49] [INFO] [GameManager] GameManager ready
[22:05:49] [INFO] [SoundPropagation] SoundPropagation autoload initialized
[22:05:57] [INFO] [SoundPropagation] Sound emitted: type=GUNSHOT, pos=(625.2544, 1276.855), source=PLAYER (AssaultRifle), range=1469, listeners=0
[22:05:57] [INFO] [SoundPropagation] Sound result: notified=0, out_of_range=0, self=0, below_threshold=0
```

### Key Observations

1. **`listeners=0`** in all sound emission events - persisted after first fix
2. No "Registered listener" messages in the log
3. Sound propagation system initialized correctly
4. Game autoloads loaded in correct order

## Timeline Reconstruction

| Date/Time | Event |
|-----------|-------|
| 2026-01-20 18:50 | PR #143 created with coordinated flanking system |
| 2026-01-20 18:56 | User reports: "враги полностью сломались" with game_log_20260120_215529.txt |
| 2026-01-20 19:02 | First fix: Removed duplicate `is_alive()` and `get_current_state()` functions |
| 2026-01-20 19:06 | User reports: "всё ещё полностью сломаны враги" with game_log_20260120_220549.txt |
| 2026-01-20 22:04 | User points to working PR #148 for comparison |
| 2026-01-20 22:11 | Investigation continues - discovered missing constants |

## Root Cause Analysis

### Bug #1: Duplicate Function Definitions (Fixed)

The coordinated flanking implementation added duplicate methods:

| Function | Original Location | Duplicate Location |
|----------|------------------|-------------------|
| `is_alive()` | Line 3874 | Line 4260 |
| `get_current_state()` | Line 3992 | Line 4265 |

**Status**: Fixed in commit 7500766

### Bug #2: Missing Constants (Root Cause - Current Fix)

After fixing the duplicate functions, the enemy script still failed to compile because of **undefined constants**:

```gdscript
# Used but NOT defined:
var supporting_offset := SUPPORTING_OFFSET        # Line 4617
var angle_offset := SUPPORTING_ANGLE_OFFSET       # Line 4618
```

These constants were used in `_process_supporting_role()` and `_process_upper_supporting_role()` functions but never declared.

In GDScript, referencing an undefined constant causes a **compilation error**:
```
Parser Error: Identifier "SUPPORTING_OFFSET" not declared in the current scope.
```

### How This Breaks the Game

When the enemy script fails to compile:
1. Enemy nodes cannot be instantiated
2. No enemies exist in the scene tree
3. No enemies register as sound listeners
4. `listeners=0` appears in all sound propagation events
5. All enemy AI behavior stops working

### Why This Wasn't Caught Earlier

1. **No Static Analysis**: No GDScript linter in CI pipeline
2. **Export Build**: The issue only manifests in exported builds where script compilation happens differently
3. **Unit Tests**: Tests used mock objects rather than the actual enemy script
4. **Multiple Bugs**: The first bug (duplicate functions) masked the second bug (missing constants)

## Solution

### Fix #1 (Previously Applied)
Remove the duplicate function definitions.

### Fix #2 (Current Fix)
Add the missing constant definitions to `enemy.gd`:

```gdscript
## Distance behind lead attacker for SUPPORTING role positioning.
const SUPPORTING_OFFSET: float = 50.0

## Angle offset for SUPPORTING role position (diagonally behind lead).
const SUPPORTING_ANGLE_OFFSET: float = PI / 6  # 30 degrees
```

Added after `AIM_BELOW_COVER_OFFSET` constant at line 557.

## Files Modified

- `scripts/objects/enemy.gd` - Added missing `SUPPORTING_OFFSET` and `SUPPORTING_ANGLE_OFFSET` constants

## Lessons Learned

1. **Code Review**: When adding new methods to large files, always search for existing methods with the same name
2. **Constant Definition**: Before using constants, ensure they are defined
3. **Multiple Bugs**: One script can have multiple compilation errors - fix all of them
4. **Testing**: Unit tests should attempt to load actual scripts, not just mocks
5. **CI/CD**: Consider adding GDScript static analysis tools to the CI pipeline
6. **Logging**: The file logging system helped diagnose the issue by showing `listeners=0`
7. **Comparison**: Compare with working branches (PR #148) to identify differences

## Verification Steps

1. ~~Remove duplicate function definitions~~ (Done)
2. Add missing `SUPPORTING_OFFSET` and `SUPPORTING_ANGLE_OFFSET` constants (Done)
3. Verify no other missing constants: `grep -oE '\b[A-Z][A-Z0-9_]+\b' scripts/objects/enemy.gd | sort | uniq`
4. Export the project and test in-game
5. Verify enemies appear and respond to player actions
6. Verify sound propagation shows `listeners > 0`

## Related Information

- **Issue**: https://github.com/Jhon-Crow/godot-topdown-MVP/issues/67
- **PR**: https://github.com/Jhon-Crow/godot-topdown-MVP/pull/143
- **Working PR for comparison**: https://github.com/Jhon-Crow/godot-topdown-MVP/pull/148
- **Godot Version**: 4.3-stable
- **Platform**: Windows
