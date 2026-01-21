# Case Study: Issue #169 - Remove ASSAULT AI Behavior

## Issue Summary

The user reported that an unwanted AI behavior called "assault" was breaking enemy AI behavior. The user believed this came from group/team AI that was never merged, but actually it came from a different PR (#89).

## Timeline of Events

### 2026-01-17: PR #89 Merged - PURSUING and ASSAULT States Added
- **Commit**: `4a457ef` - "Add PURSUING and ASSAULT states for improved enemy AI combat behavior"
- **Changes**:
  - Added `PURSUING` state: Enemies move cover-to-cover toward player when far away
  - Added `ASSAULT` state: When 2+ enemies are in combat, they coordinate an assault
  - ASSAULT behavior: wait at cover for 5 seconds, then rush player together while shooting

### 2026-01-20: PR #148 Created (NOT MERGED) - Group Tactical AI
- **Commit**: `c9a9b4b` - "Add group tactical AI system with squad coordination"
- **Status**: OPEN (not merged into main)
- This PR would have added squad coordination with roles like Leader, Suppressor, Flanker, etc.
- The user may have confused this PR with the source of ASSAULT behavior

## Root Cause Analysis

The ASSAULT state behavior was introduced in PR #89, which was correctly merged. The issue is that this behavior breaks the AI flow:

### Current Problematic Flow:
1. Enemy detects player → enters COMBAT
2. If 2+ enemies in combat-related states → ALL enemies transition to ASSAULT
3. In ASSAULT: wait at cover 5 seconds, then rush player simultaneously
4. This creates undesirable coordinated "zombie rush" behavior

### Expected Flow (per issue):
- Enemies should go directly to PURSUE or COMBAT
- No automatic transition to ASSAULT when multiple enemies are in combat

## Evidence from Code

The transition to ASSAULT is triggered in multiple places:

1. **In COMBAT state** (`_process_combat_state`):
```gdscript
var enemies_in_combat := _count_enemies_in_combat()
if enemies_in_combat >= 2:
    _log_debug("Multiple enemies in combat (%d), transitioning to ASSAULT" % enemies_in_combat)
    _transition_to_assault()
    return
```

2. **In IN_COVER state** (`_process_in_cover_state`):
```gdscript
var enemies_in_combat := _count_enemies_in_combat()
if enemies_in_combat >= 2:
    _log_debug("Multiple enemies detected (%d), transitioning to ASSAULT" % enemies_in_combat)
    _transition_to_assault()
    return
```

3. **In PURSUING state** (`_process_pursuing_state`):
```gdscript
var enemies_in_combat := _count_enemies_in_combat()
if enemies_in_combat >= 2:
    _log_debug("Multiple enemies detected during pursuit (%d), transitioning to ASSAULT" % enemies_in_combat)
    _transition_to_assault()
    return
```

## Proposed Solution

Remove or disable the ASSAULT state functionality:

1. Remove all automatic transitions to ASSAULT state (keep the state enum for backwards compatibility)
2. Remove the `_process_assault_state` function or make it immediately transition to COMBAT
3. Enemies should stay in their current state (COMBAT, PURSUING, etc.) instead of transitioning to ASSAULT

## Files Affected

- `scripts/objects/enemy.gd` - Main AI state machine
- `scripts/ai/enemy_actions.gd` - GOAP actions (AssaultPlayerAction)

## Related PRs and Commits

| PR/Commit | Description | Date | Status |
|-----------|-------------|------|--------|
| PR #89 | Add PURSUING and ASSAULT states | 2026-01-17 | MERGED |
| PR #148 | Add group tactical AI with squad coordination | 2026-01-20 | OPEN |
| Issue #88 | Original request for improved AI behavior | - | Closed |
| Issue #99 | Request for group tactical AI | - | Open |

## Implementation Details

### Changes Made

#### 1. `scripts/objects/enemy.gd`

- **Removed automatic ASSAULT transitions** from three state processing functions:
  - `_process_combat_state()` - line ~1235
  - `_process_in_cover_state()` - line ~1547
  - `_process_pursuing_state()` - line ~1883

- **Disabled `_process_assault_state()`** - now immediately transitions to COMBAT if an enemy somehow enters ASSAULT state (for backwards compatibility)

#### 2. `scripts/ai/enemy_actions.gd`

- **Disabled `AssaultPlayerAction`** GOAP action - now returns cost of 1000.0 so it's never selected by the planner

### Behavior Change

| Before | After |
|--------|-------|
| 2+ enemies in combat → ASSAULT state → wait 5s → rush player together | Enemies stay in their current state (COMBAT, PURSUING, IN_COVER) |
| Coordinated "zombie rush" behavior | Independent enemy behavior |
| Complex state machine with ASSAULT state | Simpler state machine without ASSAULT transitions |

## Conclusion

The ASSAULT behavior was intentionally added as part of improved AI behavior (PR #89), not accidentally merged from the group tactical AI branch. The user wants this behavior removed to restore simpler enemy AI that goes directly into PURSUE or COMBAT states.

The fix disables all automatic transitions to ASSAULT state while keeping the state enum and related code for backwards compatibility. If any enemy somehow enters ASSAULT state, they will immediately transition to COMBAT.
