# Log Analysis: Issue #322 - Enemy Search State

## Game Sessions Analyzed

### Session 1: Original Bug Report

- **Date:** 2026-01-24 22:10:11
- **Log File:** `logs/game_log_20260124_221011.txt`
- **Duration:** ~1 minute of gameplay
- **Focus:** Enemy behavior after Last Chance effect ends (original issue)

### Session 2: After SEARCHING State Implementation

- **Date:** 2026-01-24 23:28:58
- **Log File:** `logs/game_log_20260124_232858.txt`
- **Duration:** ~10 seconds
- **Focus:** Testing SEARCHING state - revealed critical bug
- **Observation:** Log is very short, shows only game startup with no enemy activity
- **Root Cause Found:** `movement_speed` variable typo in `_process_searching_state()` caused runtime error

## Session 1 Analysis

## Timeline of Events

### 22:10:50 - Last Chance Effect Triggered

The Last Chance effect triggered at 22:10:50 when the player was about to be killed:

```
[22:10:50] [INFO] [LastChance] Triggering last chance effect!
[22:10:50] [INFO] [LastChance] Starting last chance effect:
[22:10:50] [INFO] [LastChance]   - Time will be frozen (except player)
[22:10:50] [INFO] [LastChance]   - Duration: 6.0 real seconds
```

### 22:10:56 - Last Chance Effect Ends

After 6 seconds, the effect ended:

```
[22:10:56] [INFO] [LastChance] Effect duration expired after 6.01 real seconds
[22:10:56] [INFO] [LastChance] Ending last chance effect
```

### 22:10:56 - Memory Reset and "Search Mode" Triggered

The memory reset function was called for all enemies:

```
[22:10:56] [ENEMY] [Enemy1] Memory reset: confusion=2.0s, had_target=false
[22:10:56] [ENEMY] [Enemy2] Memory reset: confusion=2.0s, had_target=false
[22:10:56] [ENEMY] [Enemy3] Memory reset: confusion=2.0s, had_target=false
[22:10:56] [ENEMY] [Enemy3] State reset: PURSUING -> IDLE (no target)
[22:10:56] [ENEMY] [Enemy4] Memory reset: confusion=2.0s, had_target=false
[22:10:56] [ENEMY] [Enemy4] State reset: PURSUING -> IDLE (no target)
...
[22:10:56] [ENEMY] [Enemy10] Memory reset: confusion=2.0s, had_target=true
[22:10:56] [ENEMY] [Enemy10] Search mode: COMBAT -> PURSUING at (96.65299, 1704.476)
```

**Key Observation:** Enemy10 had `had_target=true` so it entered "Search mode" transitioning to PURSUING. The log explicitly shows the intent is searching but the actual state is PURSUING.

### 22:11:18 - FLANKING Instead of Searching

After pursuing, Enemy10 transitions to FLANKING:

```
[22:11:18] [ENEMY] [Enemy10] FLANKING started: target=(761.7157, 879.0358), side=left, pos=(1022.634, 1432.302)
[22:11:18] [ENEMY] [Enemy10] State: PURSUING -> FLANKING
```

### 22:11:27 - Multiple Enemies in "Search Mode" but FLANKING

```
[22:11:27] [ENEMY] [Enemy1] Search mode: COMBAT -> PURSUING at (696.5543, 983.9989)
[22:11:27] [ENEMY] [Enemy2] Search mode: SUPPRESSED -> PURSUING at (552.127, 983.9989)
[22:11:27] [ENEMY] [Enemy4] Search mode: SEEKING_COVER -> PURSUING at (696.5543, 983.9989)
[22:11:27] [ENEMY] [Enemy7] Search mode: PURSUING -> PURSUING at (1334.503, 760.2774)
[22:11:27] [ENEMY] [Enemy10] Search mode: FLANKING -> PURSUING at (450, 957.1666)
```

**Critical Finding:** The system logs "Search mode" but transitions to PURSUING, which then may lead to FLANKING or other states. There is no dedicated SEARCHING state.

## Pattern Analysis: FLANKING Loop

The logs show a repeating pattern where enemies get stuck in FLANKING:

```
[22:10:22] [ENEMY] [Enemy3] FLANKING started: target=(205.7051, 1773.085), side=left
[22:10:22] [ENEMY] [Enemy3] State: PURSUING -> FLANKING
[22:10:24] [ENEMY] [Enemy3] FLANKING stuck (2.0s no progress), target=(205.8063, 1772.971)
[22:10:24] [ENEMY] [Enemy3] State: FLANKING -> PURSUING
...
[22:10:30] [ENEMY] [Enemy3] FLANKING started: target=(977.9446, 1875.941), side=left
[22:10:30] [ENEMY] [Enemy3] State: PURSUING -> FLANKING
[22:10:32] [ENEMY] [Enemy3] FLANKING stuck (2.0s no progress)
[22:10:32] [ENEMY] [Enemy3] State: FLANKING -> PURSUING
```

This PURSUING -> FLANKING -> PURSUING cycle repeats multiple times without any systematic search behavior.

## Root Cause Analysis

### Problem Statement

When an enemy loses sight of the player (especially after the Last Chance effect ends), the code:

1. Sets `"Search mode"` in the log (line 3819 of enemy.gd)
2. Transitions to `PURSUING` state (line 3820 of enemy.gd)
3. PURSUING state then attempts to find cover toward the player
4. If no cover is found, it tries `FLANKING` (line 2420-2421 of enemy.gd)
5. FLANKING often gets stuck and returns to PURSUING
6. This creates an endless loop without methodical area search

### Code Evidence

From `scripts/objects/enemy.gd`:

```gdscript
# Line 3818-3820
_log_to_file("Search mode: %s -> PURSUING at %s" % [AIState.keys()[_current_state], old_position])
_transition_to_pursuing()
```

The comment says "Search mode" but the actual transition is to PURSUING.

From the PURSUING state handler (line 2419-2423):

```gdscript
# Can't find cover to pursue, try flanking or combat
if _can_attempt_flanking() and _player:
    _transition_to_flanking()
else:
    _transition_to_combat()
```

There is no option to enter a SEARCHING state.

## What's Missing

1. **No `AIState.SEARCHING` enum value** - The AIState enum has 9 states but no SEARCHING
2. **No methodical search pattern** - No left/right hand rule implementation
3. **No expanding zone** - No mechanism to expand search area
4. **No dedicated search waypoint system** - The PURSUING state uses cover-to-cover movement

## State Diagram: Current vs. Required

### Current Flow (Problematic)

```
COMBAT/PURSUING (lost target)
        |
        v
    PURSUING (to old position)
        |
        +-------> FLANKING (if can't find cover)
        |              |
        |              v
        |         (stuck 2s)
        |              |
        v              |
    (loop)  <----------+
        |
        v
    IDLE (if confidence too low)
```

### Required Flow (After Fix)

```
COMBAT/PURSUING (lost target)
        |
        v
    SEARCHING (methodical area search)
        |
        +-------> Generate waypoints (expanding square)
        |              |
        |              v
        |         Visit each waypoint
        |              |
        |              v
        |         Scan area at waypoint
        |              |
        v              |
    (if player found)  |
        |              |
        v              v
    COMBAT    (if all waypoints visited)
                       |
                       v
                 Expand zone, regenerate waypoints
                       |
                       v
                 (repeat until max radius or timeout)
                       |
                       v
                    IDLE
```

## Impact Assessment

### User Experience Impact

- **High frustration:** Enemies appear to be "glitching" between FLANKING and PURSUING
- **Unrealistic behavior:** No systematic search makes enemies seem unintelligent
- **Easy to exploit:** Players can easily evade enemies by hiding around a corner

### Technical Debt

- The log message "Search mode" is misleading since no actual search state exists
- The PURSUING -> FLANKING loop was not designed for search scenarios
- Missing state leads to workaround code scattered across multiple functions

## Recommendation

Implement a dedicated `AIState.SEARCHING` state as outlined in the case study README.md, with:

1. Expanding square search pattern
2. Navigation-validated waypoints
3. Local area scanning at each waypoint
4. Configurable expansion rate and max radius
5. Proper state transitions from PURSUING when target is lost

## Test Scenarios

1. **After Last Chance:** Trigger last chance effect, verify enemy enters SEARCHING
2. **Memory decay:** Let enemy confidence decay, verify transition to SEARCHING
3. **Search pattern:** Observe enemy following systematic pattern
4. **Zone expansion:** Verify zone expands when initial area is cleared
5. **Player discovery:** Hide and verify enemy finds player during search

## Session 2 Analysis: Critical Bug Found

### Overview

After implementing the SEARCHING state, testing revealed that enemies were "completely broken" (user feedback: "враги полностью сломались").

### Log Analysis

The game log (`game_log_20260124_232858.txt`) shows:
- Game started normally at 23:28:58
- All systems initialized correctly (GameManager, ScoreManager, Player, etc.)
- **No enemy activity logged in the entire session**
- Game ended at 23:29:08 (only 10 seconds of gameplay)

### Root Cause

A critical typo was introduced in `_process_searching_state()` function:

**Line 2403 (buggy code):**
```gdscript
velocity = dir * movement_speed * 0.7
```

**Problem:** `movement_speed` is an undefined variable. The correct variable name is `move_speed` (defined as `@export var move_speed: float = 220.0` on line 35).

**Impact:** When any enemy entered the SEARCHING state, GDScript threw a runtime error for undefined variable access. This caused enemies to completely stop functioning.

### Fix Applied

Changed line 2403 from:
```gdscript
velocity = dir * movement_speed * 0.7
```

To:
```gdscript
velocity = dir * move_speed * 0.7
```

### Lesson Learned

This bug demonstrates the importance of:
1. **Variable naming consistency:** The codebase uses `move_speed` for enemy speed, not `movement_speed`
2. **Testing new code paths:** The SEARCHING state was newly introduced and the navigation code path wasn't properly tested
3. **GDScript's dynamic typing:** Unlike statically typed languages, undefined variables only error at runtime when the code path is executed
