# Issue #657: Fix Grenadier - Case Study Analysis

## Problem Statement

The grenadier enemy (added in PR #628, Issue #604) has three behavioral deficiencies:
1. Does not throw grenades on non-hard difficulty
2. Should throw offensive grenade at the player as soon as it sees them at a safe distance
3. Should throw grenade at the slightest suspicion of the player's position

All grenade-throwing behavior should be integrated into the GOAP (Goal-Oriented Action Planning) system.

## Timeline

- **PR #628 merged**: Grenadier added with grenade bag system, passage throw, 7 reactive triggers (T1-T7)
- **Issue #657 opened**: Owner reports grenadier not throwing grenades on non-hard difficulty

## Root Cause Analysis

### Finding 1: No "direct sight" trigger for grenadier

The existing 7 triggers (T1-T7) are all **reactive** conditions:
- T1: Suppressed + hidden 6s
- T2: Approaching under fire at 50px/s
- T3: Witnessed 2+ ally deaths
- T4: Heard vulnerable sound, can't see source
- T5: Sustained fire zone for 10s
- T6: Desperation at 1 HP
- T7: Suspicion timer (3s of medium+ confidence while hidden)

**None of these triggers fire when the grenadier simply sees the player at a throwable distance.** This is the primary reason the grenadier barely throws grenades - it needs to be in very specific reactive situations that rarely occur during normal gameplay.

### Finding 2: Suspicion trigger too conservative for grenadier

T7 requires 3 seconds of the player being hidden with medium+ confidence. For a grenadier whose role is to throw grenades proactively, this is too conservative. The grenadier should throw on minimal suspicion (low confidence) with a shorter timer.

### Finding 3: Passage throw only works in PURSUING state

The `try_passage_throw()` method is only called from `_process_pursuing_state()`. While this is correct for passage clearing, the grenadier doesn't throw in COMBAT, SEARCHING, or IDLE states when it detects the player or suspects their position.

### Finding 4: No GOAP action for grenade throwing

The GOAP system has no `ThrowGrenadeAction` - grenade throwing is handled by a priority check in `_process_ai_state()` at line 1287. Adding a proper GOAP action would allow the planner to consider grenade throwing as part of tactical planning.

## Evidence from Game Log

From `game_log_20260208_175336.txt`:
- Line 90: Grenade bag built correctly for normal mode (3 flashbangs + 5 offensive)
- Line 91: 8 grenades initialized
- Lines 3062-9767: Grenadier goes through ~40+ state transitions (IDLE->COMBAT->PURSUING->FLANKING->RETREATING->IN_COVER->SUPPRESSED->SEARCHING) with only ONE grenade throw
- Line 7082: Single throw happened from SEEKING_COVER state: "Grenadier threw Offensive! Target: (1368, 120), Distance: 387, 7 remaining"
- Grenadier was reinitialized 6+ times (level restarts), each time with fresh 8 grenades, but threw only 1 total

## Solution

### T8: Direct Sight Trigger (Grenadier-only)
- Fires when grenadier **can see the player** AND distance is within safe throwing range (between `min_safe_distance` and `max_throw_distance`)
- Only activates after a brief sighting delay (0.5s) to avoid throwing at fleeting glimpses
- Grenadier-specific: regular enemies use the existing 7 triggers

### T9: Low Suspicion Trigger (Grenadier-only)
- Fires when grenadier has **any suspicion** (low, medium, or high confidence) about player position AND the player is hidden
- Uses a shorter timer (1.0s instead of T7's 3.0s)
- Grenadier-specific: makes grenadier proactive about area denial

### ThrowGrenadeAction (GOAP)
- New GOAP action with preconditions: `has_grenades: true`, `grenadier_throw_ready: true`
- Effects: `grenade_thrown: true`
- Cost: 0.3 (high priority when conditions are met)
- Integrates grenadier throwing decision into the GOAP planning system

## Phase 2: Self-Kill Bug (Follow-up from PR #658 comment)

### Problem

After implementing T8/T9, the grenadier was reported to "стабильно убивает себя гранатой" (consistently kills itself with its own grenade).

### Root Cause: Grenade Impact with Nearby Furniture

**Evidence from `game_log_20260208_182351.txt` (lines 3212-3244):**

1. Grenade spawned at `(1671.783, 296.760)` — only 40px offset from grenadier position
2. Target was `(1434.667, 435.554)`, distance 315px — passed the safe distance check (315 > 275)
3. Grenade immediately collided with `Desk3` (StaticBody2D) right next to the grenadier
4. Frag grenade exploded at `(1669.552, 302.763)` — only ~5px from spawn point!
5. Grenadier was 45.4px from explosion — well within 225px blast radius
6. Took 99 HE damage, HP 1/2 -> 0/2, died

**Root cause chain:**
```
Trigger fires → safe distance check passes (target is far enough)
→ _path_clear() passes (raycast to target doesn't detect nearby desk)
→ Grenade spawns at enemy_pos + dir * 40px
→ Grenade's collision_mask = 4|2 (obstacles + enemies)
→ Desk3 collision shape is within contact distance of spawn point
→ body_entered signal fires immediately
→ FragGrenade._on_body_entered → Desk3 is StaticBody2D → instant explosion
→ Grenadier at 45px distance takes 99 damage → DEAD
```

**Why existing checks didn't help:**
- `_path_clear()` raycasts from enemy to target — doesn't detect obstacles **beside** the throw path
- Safe distance check (275px) only measures distance to the target, not to nearby obstacles
- Grenade spawns only 40px from enemy, but furniture can be right there

### Solution: Two-Pronged Fix

**Fix 1: Spawn Area Obstacle Check (`_spawn_area_clear()`)** — `enemy_grenade_component.gd`
- Before throwing, raycast from enemy in the throw direction for 100px (40px spawn + 60px safety)
- Also raycast slightly to the sides (±15px perpendicular) to catch obstacles at the edges
- If any obstacle is detected, skip the throw entirely
- Applied in both `try_throw()` and `try_passage_throw()`

**Fix 2: Minimum Arming Distance** — `frag_grenade.gd`
- Added `MIN_ARMING_DISTANCE = 80px` constant (twice the spawn offset)
- Grenade records its spawn position on creation
- Impact explosion only triggers after grenade has traveled ≥80px from spawn
- If grenade hits obstacle before 80px, impact is logged but ignored — grenade continues
- This is a safety net that prevents self-kills even if the obstacle check is bypassed

**Why both fixes are needed:**
- Fix 1 prevents most self-kill scenarios by not throwing when obstacles are near
- Fix 2 is a safety net for edge cases where the obstacle check might miss:
  - Obstacles with unusual collision shapes
  - Physics engine edge cases with CCD
  - Moving obstacles that appear after the check but before the throw
