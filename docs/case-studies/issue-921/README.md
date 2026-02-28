# Case Study: Issue #921 — Enemies in Search State Stand Still and Don't Move

## Issue Summary

**Report**: "Sometimes enemies in the search state just stand and don't move"
- **Reported by**: Jhon-Crow
- **Issue URL**: https://github.com/Jhon-Crow/godot-topdown-MVP/issues/921
- **Log file**: `game_log_20260301_011407.txt` (49,923 lines)
- **Level**: BuildingLevel

---

## Timeline / Sequence of Events

| Timestamp | Event |
|-----------|-------|
| 01:14:07 | Game loads BuildingLevel |
| 01:16:27 | Enemy9 enters SEARCHING (ally death observed, center=(1935, 1323)) |
| 01:16:28 | Enemy9 spots player → COMBAT (normal behavior) |
| 01:16:28 | Enemy10 GLOBAL STUCK → SEARCHING (center=(1371, 1445)) |
| 01:16:42 | Enemy10 spots player → COMBAT (normal behavior) |
| 01:17:20 | GuardEnemy5 enters SEARCHING after ally death (5 waypoints) |
| 01:18:18 | GuardEnemy5 enters SEARCHING (2578, 1348), 5 waypoints — **stuck indefinitely** |
| 01:19:32 | GuardEnemy5 GLOBAL STUCK → SEARCHING (2729, 1663), 4 waypoints |
| 01:19:40 | GuardEnemy5 spots player → PURSUING (8 seconds in SEARCHING) |
| 01:20:03 | **GuardEnemy1 GLOBAL STUCK → SEARCHING** (2121, 780) — stays 22+ seconds |
| 01:20:08 | **PatrolEnemy3 GLOBAL STUCK → SEARCHING** (2317, 1062) — stays 60+ seconds |
| 01:20:25 | GuardEnemy1 enters SEARCHING again (ally death, 1811, 646) |
| 01:21:08+ | PatrolEnemy3 still in SEARCHING (distance to player ~513px, not transitioning) |

---

## Root Cause Analysis

### Root Cause 1: SEARCH_MAX_DURATION Timeout is Logically Impossible to Trigger

**Location**: `scripts/objects/enemy.gd`, line 2193

**Code (buggy)**:
```gdscript
func _transition_to_searching(center_position: Vector2) -> void:
    _current_state = AIState.SEARCHING
    # Mark that enemy has left IDLE state (Issue #330)
    _has_left_idle = true              # ← sets flag to true immediately
    ...

func _process_searching_state(delta: float) -> void:
    _search_state_timer += delta
    # Issue #330: Only timeout for patrol enemies; engaged enemies search infinitely
    if _search_state_timer >= SEARCH_MAX_DURATION and not _has_left_idle:  # ← ALWAYS false!
```

**Problem**: `_transition_to_searching` sets `_has_left_idle = true` at line 2610. This means the timeout condition `not _has_left_idle` is **always `false`** the moment the enemy enters SEARCHING state.

**Design intent** (from Issue #330): Patrol enemies that were never in combat should timeout after 30 seconds and return to their patrol route. Enemies that have been in combat should search indefinitely. But the current implementation prevents ALL enemies from timing out.

**Evidence from log**: PatrolEnemy3 enters SEARCHING at 01:20:08 and is still in SEARCHING at 01:21:08 — 60+ seconds, more than double the 30-second timeout.

### Root Cause 2: SEARCHING State Does Not React to Player Vulnerability Sounds

**Location**: `scripts/objects/enemy.gd`, lines 575-578 and 605-607

**Code (buggy)**:
```gdscript
# For RELOAD sound (line 575):
if _current_state in [AIState.IDLE, AIState.IN_COVER, AIState.SUPPRESSED, AIState.RETREATING, AIState.SEEKING_COVER]:
    _transition_to_pursuing()

# For EMPTY_CLICK sound (line 605):
if _current_state in [AIState.IDLE, AIState.IN_COVER, AIState.SUPPRESSED, AIState.RETREATING, AIState.SEEKING_COVER]:
    _transition_to_pursuing()
```

**Problem**: `AIState.SEARCHING` is NOT in the list. When the player reloads or runs out of ammo while an enemy is in SEARCHING state, the enemy continues its search pattern instead of immediately pursuing the vulnerable player.

**Evidence from log**: PatrolEnemy3 and GuardEnemy1 log "Player vulnerable (ammo_empty) but cannot attack: close=false" repeatedly while in SEARCHING state, but never transition to PURSUING to exploit the vulnerability.

### Secondary Factor: Visual Confusion (Not a Bug)

Enemies in SEARCHING state face the player direction (Priority 2 in rotation logic, line 924-928) even while moving to nearby waypoints. From a distance, this creates the appearance that the enemy is staring at the player without moving toward them, reinforcing the perception that they are "standing still."

The actual movement during SEARCHING is within a 100-200px radius (initial search radius), which appears nearly stationary from across the level.

---

## Evidence Summary

| Enemy | SEARCHING Start | Duration | Behavior |
|-------|----------------|----------|----------|
| Enemy9 | 01:16:27 | ~1s | Normal — found player quickly |
| Enemy10 | 01:16:28 | ~14s | Normal — found player |
| GuardEnemy5 | 01:18:18 | ~1min (dead) | Spawned while SEARCHING logged, transitioned to IDLE/PURSUING normally |
| GuardEnemy1 | 01:20:03 | 22s (log ends) | Stuck — no combat transitions while player ~1200-1290px away |
| PatrolEnemy3 | 01:20:08 | 60s+ (log ends) | Stuck — no timeout, no aggression when player ~500-1600px away |

---

## Fix Plan

### Fix 1: Restore SEARCH_MAX_DURATION Timeout

**File**: `scripts/objects/enemy.gd`
**Line**: 2610

**Change**: Remove `_has_left_idle = true` from `_transition_to_searching`. The flag is already set by earlier state transitions (COMBAT, RETREATING, FLANKING, PURSUING) for enemies that have been in combat.

```gdscript
# Before (buggy):
func _transition_to_searching(center_position: Vector2) -> void:
    _current_state = AIState.SEARCHING
    _has_left_idle = true  # ← REMOVE THIS

# After (fixed):
func _transition_to_searching(center_position: Vector2) -> void:
    _current_state = AIState.SEARCHING
    # Note: _has_left_idle intentionally NOT set here
    # Enemies that have left IDLE via combat already have _has_left_idle = true
    # Enemies going directly from IDLE to SEARCHING (ally death, sound) should
    # timeout per SEARCH_MAX_DURATION so they return to their patrol route.
```

**Effect**:
- Enemies that were in combat (FLANKING, PURSUING, RETREATING, etc.) already have `_has_left_idle = true` → still search indefinitely ✓
- Patrol enemies entering SEARCHING from IDLE (ally death, sound detection) → `_has_left_idle = false` → timeout after 30s and return to patrol ✓

### Fix 2: SEARCHING State Reacts to Vulnerability Sounds

**File**: `scripts/objects/enemy.gd`
**Lines**: ~575-578 and ~605-607

**Change**: Add `AIState.SEARCHING` to the state list that reacts to reload/empty_click sounds.

```gdscript
# Before (buggy):
if _current_state in [AIState.IDLE, AIState.IN_COVER, AIState.SUPPRESSED, AIState.RETREATING, AIState.SEEKING_COVER]:
    _transition_to_pursuing()

# After (fixed):
if _current_state in [AIState.IDLE, AIState.IN_COVER, AIState.SUPPRESSED, AIState.RETREATING, AIState.SEEKING_COVER, AIState.SEARCHING]:
    _transition_to_pursuing()
```

**Effect**: Enemies that are searching for the player will immediately pursue when they hear the player reload or run out of ammo, making them more aggressive and less easily avoided.

---

## Alternative Solutions Considered

| Option | Pros | Cons | Decision |
|--------|------|------|----------|
| Remove `_has_left_idle = true` from `_transition_to_searching` | Minimal change, preserves existing logic | None — this is the correct fix | **Chosen** |
| Replace `not _has_left_idle` with `behavior_mode == BehaviorMode.PATROL` | Simple and clear | Changes semantics — guard enemies would now also timeout | Not chosen |
| Add a new `_was_in_combat` flag | More precise | More complex, requires additional state tracking | Not chosen |
| Increase SEARCH_MAX_DURATION | Easy | Doesn't fix the logic bug, just delays the problem | Not chosen |

---

## Impact Assessment

- **Bug severity**: Medium (affects game feel — enemies appear unresponsive)
- **Frequency**: Every game session where enemies lose sight of the player and transition to SEARCHING
- **Player impact**: Player can easily evade enemies by staying out of initial search radius; enemies don't pursue when player is vulnerable
- **Fix risk**: Low — minimal code change, well-tested code paths

---

## References

- [Issue #322](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/322): SEARCHING state implementation
- [Issue #330](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/330): Engaged enemies never return to IDLE
- [Issue #354](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/354): Stuck detection for SEARCHING
- [Issue #367](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/367): Global stuck detection
- [Issue #405](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/405): Search continues indefinitely
