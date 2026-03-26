# Case Study: Issue #1446 — AI Broken After Shieldbearer-as-Cover Implementation

## Problem Statement

Owner reported "ии полностью сломан" (AI completely broken) after PR #1480 was marked ready to merge.

A game log was provided: `game_log_20260325_061123.txt`.

---

## Timeline Reconstruction

| Time | Event |
|------|-------|
| 2026-03-24 21:12 | PR #1480 opened with shieldbearer-as-cover feature |
| 2026-03-24 21:15 | PR marked "ready to merge", all CI checks passing |
| 2026-03-25 03:11 | Owner (Jhon-Crow) tests build, reports "ии полностью сломан" (AI completely broken) |
| 2026-03-25 06:11 | First game log captured (`game_log_20260325_061123.txt`) |
| 2026-03-25 09:01 | Second AI work session started — identified RCA-1 and RCA-2, applied partial fix |
| 2026-03-25 09:10 | Second AI session marked PR ready to merge |
| 2026-03-25 13:43 | Owner tests again, reports "ии сломан" (AI broken) — provides second log |
| 2026-03-25 16:43 | Second game log captured (`game_log_20260325_164302.txt`) |
| 2026-03-25 19:53 | Third AI work session started — identified RCA-3 (GDScript inline if bug) |
| 2026-03-25 20:06 | Third AI session marked PR ready to merge |
| 2026-03-26 09:30 | Owner tests again, reports "ии полностью сломан" (AI completely broken) — provides third log |
| 2026-03-26 12:29 | Third game log captured (`game_log_20260326_122942.txt`) |
| 2026-03-26 09:31 | Fourth AI work session started — identified RCA-5 (PURSUING oscillation from IN_COVER) |

---

## Game Log Analysis (`game_log_20260325_061123.txt`)

The log shows:
- **Normal initialization**: All systems loaded correctly (GameManager, ImpactEffects, shaders, etc.)
- **5 enemies created** in LabyrinthLevel: Enemy1–Enemy5
- **No gameplay logged**: Session ended after ~5 seconds
- **DocksLevel load error**: `ERROR: Invalid resource: res://scenes/levels/DocksLevel.tscn` — this is a pre-existing issue, not related to #1446
- **No AI state transitions logged**: The short session did not show actual combat

The log does NOT directly show AI breakage in action. However, the owner's subjective experience of "AI completely broken" during gameplay — combined with the code analysis below — points to a well-defined set of bugs.

---

## Root Cause Analysis

### RCA-0 (CRITICAL — NEW): GDScript Inline `if` Semicolon-Chaining Bug

**Location**: `scripts/objects/enemy.gd`, commit `d6da24c` (second AI session fix), line 1277

**The bug** was introduced by the second AI session's fix attempt. The "fixed" code was written as a single-line if with semicolons:

```gdscript
if _formation_shielder != null: _cover_position = _formation_target_pos; _has_valid_cover = true; if _current_state not in [AIState.IN_COVER, AIState.COMBAT, AIState.SUPPRESSED]: _transition_to_in_cover(); return  # Issue #1446: arrived — shieldbearer is cover, return early
```

In GDScript, this parses as:
```
if _formation_shielder != null:
    _cover_position = _formation_target_pos
    _has_valid_cover = true
    if _current_state not in [IN_COVER, COMBAT, SUPPRESSED]:
        _transition_to_in_cover()
        return   ← ONLY executes when inner condition is TRUE
```

The `return` is inside the nested `if`. When `_current_state` IS IN_COVER, COMBAT, or SUPPRESSED, the inner `if` is false, so **no return happens** — execution falls through to the full state machine (line 1282+).

This means formation enemies already in COMBAT or SUPPRESSED states (which is the normal operating state after arriving at a shieldbearer) still execute the complete AI state machine every frame: distraction attacks, grenade throws, pursuit decisions, etc.

**Impact**: Same as RCA-1 — formation enemies run the full state machine instead of the limited shieldbearer-follow behavior.

**Fix**: Expand the single-line if into a proper multi-line block with the `return` at the outer level:

```gdscript
if _formation_shielder != null:  # arrived — always return early (shieldbearer is cover)
    _cover_position = _formation_target_pos; _has_valid_cover = true
    if _current_state not in [AIState.IN_COVER, AIState.COMBAT, AIState.SUPPRESSED]: _transition_to_in_cover()
    return  # never fall through to main state machine for formation enemies
```

---

### RCA-1 (CRITICAL): Formation Enemies Fall Through to Full State Machine

**Location**: `scripts/objects/enemy.gd`, lines 1273–1279

**Original code** (main branch):
```gdscript
if _formation_shielder != null: _move_to_target_nav(_formation_target_pos, move_speed); return
```
This **always returns early** for any enemy following a shieldbearer, skipping ALL other AI logic.

**New code** (PR #1480):
```gdscript
if _formation_shielder != null and global_position.distance_to(_formation_target_pos) > 25.0:
    _move_to_target_nav(_formation_target_pos, move_speed)
    if ((_can_see_player and _player) or ...) and ...: _aim_at_player(); _shoot(); _shoot_timer = 0.0
    return
if _formation_shielder != null: _cover_position = _formation_target_pos; _has_valid_cover = true
if _formation_shielder != null and _current_state not in [AIState.IN_COVER, AIState.COMBAT, AIState.SUPPRESSED]: _transition_to_in_cover()
# ... falls through to FULL state machine
```

When an enemy following a shieldbearer **arrives within 25px**, the early return is removed. The enemy now:
1. Sets cover data
2. May transition to `IN_COVER`
3. **Falls through to all priority checks**: distraction attacks, vulnerable-player pursuit, grenade throws, and the full match-state dispatch

This was unintended. Formation enemies should have controlled, limited behavior — not the entire state machine.

---

### RCA-2 (CRITICAL): Ping-Pong State Oscillation

**Location**: `scripts/objects/enemy.gd`, lines 1278 and 1780–1791

Line 1278 forces any formation enemy **not** in `[IN_COVER, COMBAT, SUPPRESSED]` to `IN_COVER` every frame.

But `_process_in_cover_state` (lines 1780–1791) immediately transitions the enemy to COMBAT or PURSUING if it can see the player — which happens on the very next frame.

**Result per frame:**
- Frame N: Enemy is in PURSUING → line 1278 forces to IN_COVER
- Frame N+1: `_process_in_cover_state` sees player → transitions to COMBAT or PURSUING
- Frame N+2: Enemy is in PURSUING → line 1278 forces to IN_COVER again
- … repeats every 1–2 frames

This rapid state oscillation causes:
- Stuttering/frozen movement (enemy can't commit to any path)
- No consistent shooting (shoot timer reset never aligns with state)
- Erratic rotation/aiming
- Navigation agent path thrashing

This is the "AI completely broken" symptom.

---

### RCA-3 (CRITICAL): PURSUING/RETREATING States Not Protected

**Location**: Line 1278 exclusion list

```gdscript
if _formation_shielder != null and _current_state not in [AIState.IN_COVER, AIState.COMBAT, AIState.SUPPRESSED]: _transition_to_in_cover()
```

Missing from the exclusion list:
- `AIState.PURSUING` — enemy chasing player gets yanked to IN_COVER
- `AIState.RETREATING` — enemy running from grenade/threat gets yanked to IN_COVER
- `AIState.EVADING_GRENADE` — enemy dodging grenade gets yanked to IN_COVER (very dangerous — grenade deaths)
- `AIState.FLANKING`
- `AIState.SEARCHING`
- `AIState.ASSAULT`

---

### RCA-4 (MEDIUM): IN_COVER State Transitions Not Guarded for Formation Enemies

**Location**: `_process_in_cover_state`, lines 1780–1791

When a formation enemy is in IN_COVER behind a shieldbearer, if it can see the player:
- Line 1782: → COMBAT
- Line 1786: → COMBAT
- Line 1790: → PURSUING

This immediately breaks the IN_COVER state that was just set. Combined with RCA-2, this creates the oscillation loop.

**The correct behavior**: Formation enemies in cover behind a shieldbearer should shoot from cover without transitioning to COMBAT or PURSUING.

---

### RCA-5 (MINOR): Shieldbearer Cover Candidates Called on Every Cover Search

**Location**: `_find_cover_position()`, line 3323

```gdscript
candidates.append_array(_get_shieldbearer_cover_candidates())
```

`_get_shieldbearer_cover_candidates()` iterates all enemies in the scene every cover search. While a cooldown exists, this adds `O(N)` work per cover search for all enemies. Not a breakage, but an efficiency concern.

---

## Sequence of Events During Gameplay (Reconstructed)

1. Player enters level. 5 enemies are IDLE.
2. Shieldbearer raises shield → `_update_formation` fires each physics frame.
3. Nearby enemies receive `set_formation_follow_target()` → `_formation_shielder` is set.
4. **Old behavior**: Enemies move to formation, return early from `_process_ai_state`. Stable.
5. **New behavior**: Enemy arrives within 25px of formation target.
   - `_transition_to_in_cover()` called → state = IN_COVER
   - Falls through to `_process_in_cover_state`
   - Can see player → `_transition_to_combat()` → state = COMBAT
   - Next frame: COMBAT not in exclusion list at 1278 → OK (doesn't force IN_COVER)
   - COMBAT processes normally...
   - Wait: COMBAT may transition to SEEKING_COVER, RETREATING, PURSUING...
   - Any of those: next frame line 1278 forces IN_COVER again → oscillation

6. Result: Enemy near shieldbearer oscillates between states every 1–3 frames. Navigation thrashes. Movement stutters. Shooting is disrupted. The entire AI appears "frozen" or "stuck".

---

## Proposed Fix

### Fix A: Restore early return for formation enemies at formation position

In `_process_ai_state`, when `_formation_shielder != null` and the enemy has arrived at the formation position:
1. Update cover data (`_cover_position`, `_has_valid_cover`)
2. If not in IN_COVER/COMBAT/SUPPRESSED, transition to IN_COVER
3. **Return early** — do NOT fall through to state machine

This preserves the original "formation always returns early" invariant.

### Fix B: Let IN_COVER state handle the actual shooting for formation enemies

In `_process_in_cover_state`, the existing lines 1793–1799 already handle shooting at visible players from cover. Formation enemies will naturally use this.

The transitions at lines 1780–1791 (→COMBAT, →PURSUING) must be skipped for formation enemies (when `_formation_shielder != null`), because the shieldbearer is mobile and the enemy should stay close to it.

### Fix C: Ensure all critical states are protected from forced IN_COVER

Line 1278 should also exclude PURSUING, RETREATING, EVADING_GRENADE, FLANKING so enemies in those states are not overridden mid-action. However, with Fix A (early return), line 1278 becomes a one-time transition that fires once after arriving, making this less critical.

---

## Related Issues and Prior Art

- Issue #1242: Original shieldbearer + formation system implementation
- Issue #407: Grenade avoidance — EVADING_GRENADE must not be interrupted
- Issue #997 RCA-18: IN_COVER minimum duration to prevent rapid cycling
- Issue #1161, #1289: Cover/navigation interaction issues

---

---

## RCA-5 (CRITICAL — Fourth Session): Formation Enemy Oscillates IN_COVER ↔ PURSUING

**Location**: `scripts/objects/enemy.gd`, `_process_in_cover_state`, line 1803 (before fix)

**The bug**: When a formation enemy is in `IN_COVER` state behind a shieldbearer and loses sight of the player (e.g., player moves around a wall), `_process_in_cover_state` reached the "lost sight" branch:

```gdscript
if not (_can_see_player or _can_see_companion) and not _under_fire and not (suppressive_fire):
    _transition_to_pursuing()  # ← no guard for formation enemies
```

This transitions the enemy to `PURSUING`. On the very next frame, `_process_ai_state` sees `_formation_shielder != null` with state = PURSUING (not in `[IN_COVER, COMBAT, SUPPRESSED]`), so it calls `_transition_to_in_cover()` again. This creates a 2-frame oscillation loop:

```
Frame N:   IN_COVER  → _process_in_cover_state → lost sight → PURSUING
Frame N+1: PURSUING  → _process_ai_state       → force IN_COVER
Frame N+2: IN_COVER  → _process_in_cover_state → lost sight → PURSUING
…
```

**Impact**: Frozen/stuttering movement, no coherent navigation or shooting. The "AI completely broken" symptom described by the owner.

**Fix**: Added `_formation_shielder == null` guard to the "lost sight → PURSUING" branch:

```gdscript
# Issue #1446: formation enemies behind shieldbearer stay in cover — shieldbearer IS cover, no need to pursue.
if _formation_shielder == null and not (_can_see_player or _can_see_companion) and not _under_fire and ...:
    _transition_to_pursuing()
```

Formation enemies that lose sight of the player remain in `IN_COVER` behind the shieldbearer — the shieldbearer provides mobile cover and will eventually move to reestablish line of fire.

---

## Game Log Analysis: Third Report (`game_log_20260326_122942.txt`)

The log shows (same pattern as previous logs):
- **Normal initialization**: LabyrinthLevel (menu/entry level), 5 enemies created
- **0 enemies tracked**: All children lack the `died` signal — pre-existing LabyrinthLevel issue unrelated to #1446
- **No gameplay logged**: Session ends after ~4 seconds when navigating to BuildingLevel
- **BuildingLevel load error**: `ERROR: Invalid resource: res://scenes/levels/BuildingLevel.tscn` — same pre-existing SceneLoader issue
- **Difficulty**: Power Fantasy (invincibility: true) — owner is testing in debug/dev mode

The third log does not show enemy AI behavior directly — the actual gameplay with shieldbearer interactions happens in the level loaded after LabyrinthLevel. The "AI completely broken" report after the third session's fix indicates RCA-5 was still present.

---

## Files Changed

- `scripts/objects/enemy.gd` — Formation + cover state machine logic
- `docs/case-studies/issue-1446/README.md` — This file
- `docs/case-studies/issue-1446/game_log_20260325_061123.txt` — Owner-provided game log (first report)
- `docs/case-studies/issue-1446/game_log_20260325_164302.txt` — Owner-provided game log (second report)
- `docs/case-studies/issue-1446/game_log_20260326_122942.txt` — Owner-provided game log (third report)
- `docs/case-studies/issue-1446/analysis.md` — Initial design analysis (pre-implementation)
