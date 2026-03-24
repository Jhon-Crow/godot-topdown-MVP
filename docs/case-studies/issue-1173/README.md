# Case Study: Issue #1173 — Enemy AI Immediately Jumps to SEARCHING State

## Overview

**Issue:** Enemies immediately transition from PURSUING to SEARCHING state, within ~1 second of entering PURSUING.

**Reported:** 2026-03-18

**Game log:** `game_log_20260318_105129.txt`

---

## Timeline / Sequence of Events

```
10:51:38 — Enemy2  State: COMBAT -> PURSUING
10:51:38 — Enemy3  State: COMBAT -> PURSUING
10:51:38 — Enemy4  State: COMBAT -> PURSUING
10:51:38 — Enemy1  State: IDLE   -> PURSUING

10:51:39 — Enemy2  GLOBAL STUCK: pos=(379.84, 663.93) for 1.5s → SEARCHING
10:51:39 — Enemy3  GLOBAL STUCK: pos=(667.87, 778.07) for 1.5s → SEARCHING
10:51:39 — Enemy4  GLOBAL STUCK: pos=(724.18, 914.07) for 1.5s → SEARCHING
10:51:40 — Enemy1  GLOBAL STUCK: pos=(462.31, 545.19) for 1.5s → SEARCHING
```

All four enemies transition PURSUING → SEARCHING within 1–2 seconds of entering PURSUING.
They never actually reach the player. The SEARCHING state immediately begins as if the player is lost.

---

## Root Cause Analysis

### The Triggering Code

`scripts/objects/enemy.gd`, function `_physics_process`:

```gdscript
const GLOBAL_STUCK_MAX_TIME: float = 1.5  # Issue #1107: reduced 4.0→1.5 to bail out of wall faster

if _current_state == AIState.PURSUING or _current_state == AIState.FLANKING:
    var moved_distance := global_position.distance_to(_global_stuck_last_position)
    if moved_distance < GLOBAL_STUCK_DISTANCE_THRESHOLD:  # GLOBAL_STUCK_DISTANCE_THRESHOLD = 30.0px
        if not (_can_see_player and _can_hit_player_from_current_position()):
            _global_stuck_timer += delta
            if _global_stuck_timer >= GLOBAL_STUCK_MAX_TIME:
                _transition_to_searching(global_position)
```

This code transitions the enemy to SEARCHING if the enemy hasn't moved 30px within `GLOBAL_STUCK_MAX_TIME` seconds.

### History of the Bug

**Original value:** `GLOBAL_STUCK_MAX_TIME = 4.0` (present since Issue #367, present in `backup` branch)

**Changed to:** `GLOBAL_STUCK_MAX_TIME = 1.5` in commit `eb1499b4` (`fix(#1107): escape wall faster`) to fix machete enemies getting stuck in walls for too long.

Commit message rationale from #1107:
> GLOBAL_STUCK timer 4.0s too long after 0.8s COMBAT stuck → 4.8s total wall-walk

### Why 1.5s Is Too Short

The GLOBAL_STUCK check tracks movement over a 30px threshold. During normal navigation, an enemy:

1. Enters PURSUING state and NavigationAgent2D calculates a path (takes 1+ frames)
2. Starts navigating — but while turning a corner or near a wall, speed may drop
3. At 1.5s, if the enemy hasn't moved 30px from its starting position, it triggers SEARCHING

In the BuildingLevel (map in the log), enemies start far from the player and need to navigate around corners. It's common to be blocked momentarily for >1.5s by navmesh path recalculation.

### Why the Machete Fix Didn't Need to Change This

The machete COMBAT stuck was solved with a **separate timer**:
```gdscript
const MACHETE_COMBAT_STUCK_MAX_TIME: float = 0.8  # Reroute after 0.8s stuck within 20px
```

This handles the specific case of machete enemies stuck in COMBAT state. The `GLOBAL_STUCK_MAX_TIME` reduction was an additional change that turned out to be unnecessary for the machete fix and caused a regression for all enemy types.

---

## Impact

- All enemy types (GUARD, PATROL, Grenadier) affected
- Enemies immediately give up pursuit and start aimlessly searching
- Behavior change is visible within 1–2 seconds of combat engagement
- Makes the game significantly easier — enemies never chase the player

---

## Solution

Restore `GLOBAL_STUCK_MAX_TIME` from `1.5` back to `4.0` (the value present in the `backup` branch).

The machete-specific wall-stuck issue introduced in #1107 is already handled by the separate `MACHETE_COMBAT_STUCK_MAX_TIME = 0.8s` constant, which is not changed.

**Expected behavior after fix:**
- Enemies spend up to 4 seconds pursuing before giving up due to inability to progress
- Normal navigation around corners takes ~0.5–2s, well within the 4s window
- Machete enemies still escape walls quickly via `MACHETE_COMBAT_STUCK_MAX_TIME = 0.8s`

---

## Files Changed

- `scripts/objects/enemy.gd`: `GLOBAL_STUCK_MAX_TIME = 1.5` → `GLOBAL_STUCK_MAX_TIME = 4.0`
