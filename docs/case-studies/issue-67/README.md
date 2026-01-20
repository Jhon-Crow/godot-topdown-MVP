# Case Study: Issue #67 - Coordinated Flanking System Bug

## Problem Report

**Date**: 2026-01-20
**Reporter**: Jhon-Crow (repository owner)
**Report**: "враги полностью сломались" (enemies are completely broken)

## Evidence Collected

### Game Log Analysis (game_log_20260120_215529.txt)

```
[21:55:29] [INFO] GAME LOG STARTED
[21:55:29] [INFO] [GameManager] GameManager ready
[21:55:29] [INFO] [SoundPropagation] SoundPropagation autoload initialized
[21:55:47] [INFO] [SoundPropagation] Sound emitted: type=GUNSHOT, pos=(2634.438, 1146.578), source=PLAYER (AssaultRifle), range=1469, listeners=0
[21:55:47] [INFO] [SoundPropagation] Sound result: notified=0, out_of_range=0, self=0, below_threshold=0
[21:55:47] [INFO] [SoundPropagation] Sound emitted: type=GUNSHOT, pos=(2653.902, 1124.747), source=PLAYER (AssaultRifle), range=1469, listeners=0
[21:55:47] [INFO] [SoundPropagation] Sound result: notified=0, out_of_range=0, self=0, below_threshold=0
[21:55:48] [INFO] [SoundPropagation] Sound emitted: type=GUNSHOT, pos=(2665.312, 1111.95), source=PLAYER (AssaultRifle), range=1469, listeners=0
[21:55:48] [INFO] [SoundPropagation] Sound result: notified=0, out_of_range=0, self=0, below_threshold=0
[21:55:49] [INFO] GAME LOG ENDED
```

### Key Observations

1. **`listeners=0`** in all sound emission events
2. No "Registered listener" messages in the log
3. Sound propagation system initialized correctly
4. Game autoloads loaded in correct order

## Timeline Reconstruction

1. **Pre-PR State**: Working enemy AI system with sound propagation
2. **PR #143 Created**: Added coordinated flanking system (commit 7ecd428)
3. **Code Changes**:
   - Added `COORDINATED_FLANKING` state to enemy AI
   - Added `FlankSquadManager` autoload
   - Added new functions to `enemy.gd` including `is_alive()` and `get_current_state()`
4. **Bug Introduced**: Duplicate function definitions in `enemy.gd`
5. **Result**: GDScript compilation error prevents enemy script from loading

## Root Cause Analysis

### Primary Cause: Duplicate Function Definitions

The coordinated flanking implementation added new public methods that duplicated existing methods:

| Function | Original Location | Duplicate Location |
|----------|------------------|-------------------|
| `is_alive()` | Line 3874 | Line 4260 |
| `get_current_state()` | Line 3992 | Line 4265 |

### How This Breaks the Game

In GDScript, duplicate function definitions cause a **compilation error**:

```
Parser Error: Function "is_alive" duplicates a function from a parent class or previously in the current file.
```

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

## Solution

Remove the duplicate function definitions added in the coordinated flanking section:

```diff
-## Check if enemy is alive.
-func is_alive() -> bool:
-	return _is_alive
-
-
-## Get current AI state.
-func get_current_state() -> AIState:
-	return _current_state
-
-
 ## Get the string name of the current state.
```

The original functions at lines 3874 and 3992 remain and provide the same functionality.

## Files Modified

- `scripts/objects/enemy.gd` - Removed duplicate function definitions

## Lessons Learned

1. **Code Review**: When adding new methods to large files, always search for existing methods with the same name
2. **Testing**: Unit tests should attempt to load actual scripts, not just mocks
3. **CI/CD**: Consider adding GDScript static analysis tools to the CI pipeline
4. **Logging**: The file logging system helped diagnose the issue by showing `listeners=0`

## Verification Steps

1. Remove duplicate function definitions
2. Verify no other duplicate functions exist: `grep -n "^func " scripts/objects/enemy.gd | awk -F':' '{print $2}' | sort | uniq -d`
3. Export the project and test in-game
4. Verify enemies appear and respond to player actions
5. Verify sound propagation shows `listeners=10` (or appropriate enemy count)

## Related Information

- **Issue**: https://github.com/Jhon-Crow/godot-topdown-MVP/issues/67
- **PR**: https://github.com/Jhon-Crow/godot-topdown-MVP/pull/143
- **Godot Version**: 4.3-stable
- **Platform**: Windows
