# Case Study: Issue #934 — BFF Companion Not Targeted by Enemies

## Summary

**Issue title:** fix BFF
**Reported by:** Jhon-Crow
**Status:** Open

**Problem statement (translated from Russian):**
Enemies do not shoot at the companion (BFF). Enemies should treat the companion as a second player, attacking either the player or the companion depending on accessibility (can shoot, can throw grenade, can flank).
This behavior should be embedded in the enemy GOAP system.

---

## Root Cause Analysis

### How the BFF Companion is Created (Issue #674)

In `scripts/characters/player.gd`, the companion is spawned via `_summon_bff_companion()`:

1. Instantiates from `res://scenes/objects/Enemy.tscn`
2. Sets health range: `min_health=2`, `max_health=4`
3. **Removes from "enemies" group** (line 3309): `companion.remove_from_group("enemies")`
4. **Adds to "bff_companions" group** (line 3312): `companion.add_to_group("bff_companions")`
5. Sets `set_aggressive(true)` so it attacks enemies using `AggressionComponent`

### How Regular Enemies Find Targets

In `scripts/objects/enemy.gd`:

- `_find_player()` searches `get_nodes_in_group("player")` → only finds the **main player**
- `_player` variable is the sole targeting reference
- `_check_player_visibility()` checks only `_player`
- GOAP world state only has: `player_visible`, `player_close`, `player_distracted`
- Actions `EngagePlayerAction`, `AttackDistractedPlayerAction`, etc. only target the player

### Why Enemies Don't Shoot at the Companion

The companion is in the "bff_companions" group, **not** "enemies" or "player". Regular enemies:
- Never scan "bff_companions" group
- Have no `companion_visible` world state
- Have no GOAP actions that target a companion
- Only aim/shoot at `_player` reference

### Confirmation from Game Log

The log (`game_log_20260301_024305.txt`) shows `BffCompanion` instances spawning, moving, and attacking enemies — but no regular enemy ever targets the companion. Enemies hit the companion only from friendly fire (line 785: `[BffCompanion] Hit: dmg=1`), not from deliberate targeting.

---

## Research: GOAP Multi-Target Patterns

### GOAP and Multiple Targets

GOAP (Goal Oriented Action Planning) is inherently target-agnostic — the planner selects actions based on world state predicates. To support multiple targets, the typical patterns are:

1. **Target abstraction** — Use a single `_current_target` variable and GOAP predicates like `target_visible`, `target_close`. Choose the best target before planning.
2. **Separate GOAP instances per target** — Run two GOAP passes (one for player, one for companion) and merge plans. Complex and costly.
3. **World state extension** — Add `companion_visible`, `companion_close` predicates and new actions that target the companion.

**Pattern 1** (target abstraction) is the most straightforward for this codebase because:
- The existing GOAP predicates (`player_visible`, `player_close`, etc.) map cleanly to target-based predicates
- Most code only needs `_current_target` instead of `_player` for engagement
- Shooting, aiming, and distance checks already have helpers to refactor

### Known Libraries / Approaches

- **Godot AI Toolkit**: No specific BFF targeting built-in
- **GOAP in AAA games** (F.E.A.R., GameAI Pro): Target selection is pre-GOAP — a threat list is maintained, and the "best target" is chosen before planning begins
- **Utility AI** approach: Score each potential target (player vs companion) using utility scores (distance, LOS, threat level) and pick highest-scoring target

### Recommended Approach for This Codebase

**Two-phase targeting:**
1. **Target selection phase** (pre-GOAP): Enemy scans both "player" and "bff_companions" groups, selects the most accessible target (has LOS, closest, not in cover)
2. **GOAP planning phase** (unchanged): Enemy uses `_current_target` (which may be player or companion) in existing GOAP predicates

This is **minimal-diff**, preserves existing behavior for player-only scenarios, and treats the companion as "second player" exactly as the issue requests.

---

## Proposed Solution

### Changes to `scripts/objects/enemy.gd`

1. **Add `_companion` variable** — reference to BFF companion Node2D (null if none)
2. **Add `_current_target` variable** — the currently active target (either `_player` or `_companion`)
3. **Add `_can_see_companion` boolean** — mirror of `_can_see_player` for companion
4. **Add `_find_companion()` method** — scans "bff_companions" group
5. **Add `_check_companion_visibility()` method** — mirrors `_check_player_visibility()`
6. **Add `_select_best_target()` method** — picks best target based on LOS, distance
7. **Update `_update_goap_state()`** — add `companion_visible`, `companion_close` predicates and update `player_visible` to reflect best target
8. **Update combat methods** — use `_current_target` instead of hardcoded `_player` where needed for aiming/shooting at companion

### Changes to `scripts/ai/enemy_actions.gd`

No changes needed — the existing actions work generically with GOAP predicates. The `player_visible` predicate is updated to reflect "can see any threat target" (player or companion).

### Changes to `tests/unit/test_bff_pendant.gd`

Add tests covering:
- `_find_companion()` finds companions in "bff_companions" group
- `_select_best_target()` logic (closer target wins, LOS wins)
- Companion as attack target when player is not visible
- Enemy attacks companion when companion is visible but player is not

---

## Files Modified

- `scripts/objects/enemy.gd` — Target selection logic
- `scripts/components/bff_targeting_component.gd` — Companion detection component
- `tests/unit/test_bff_pendant.gd` — Regression tests for companion targeting

---

## Bug Re-occurrence Report (March 2026)

### User Feedback
On March 2, 2026, user Jhon-Crow reported that "enemies still don't attack the companion" despite the initial PR implementation.

### Investigation

Analysis of the game log (`logs/game_log_20260302_194932.txt`) revealed:
1. The companion was correctly spawned and placed in the `bff_companions` group
2. Enemies were detecting the companion (evidenced by `[->companion]` markers in rotation logs)
3. Enemies were rotating toward the companion

However, enemies were NOT shooting at the companion.

### Root Cause (Second Pass)

The initial implementation added:
- `BffTargetingComponent` for companion detection and target selection
- `_can_see_companion` flag set correctly
- `_current_target` pointing to the closer visible target
- `_aim_at_player()` using `_current_target` correctly
- `_shoot()` supporting companion targeting via `_aiming_companion`

**BUT** the shooting guard conditions throughout the state processing functions still checked only `_can_see_player and _player`, blocking shooting even when the companion was the valid target.

### Locations Fixed

The following shooting guard conditions were updated to also consider companion visibility:

1. `_process_seeking_cover_state()` - Line 1613
2. `_process_in_cover_state()` - Lines 1687, 1694
3. `_process_suppressed_state()` - Lines 1772, 1800
4. `_process_retreating_state()` - Line 1888
5. `_process_pursuing_state()` - Lines 1953, 1974, 1994, 2087
6. `_get_target_position()` - Added companion position fallback
7. Debug drawing - Added companion visibility line

### Pattern Applied

**Before:**
```gdscript
if _can_see_player and _player:
    _aim_at_player()
    _shoot()
```

**After:**
```gdscript
if (_can_see_player and _player) or (_can_see_companion and _companion != null):
    _aim_at_player()  # Uses _current_target internally
    _shoot()          # Supports companion via _aiming_companion
```

---

## References

- [Issue #674](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/674) — BFF Pendant implementation
- [Issue #729](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/729) — Aggressive enemy navigation
- [Issue #675](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/675) — Aggression gas component
- [Game Log (initial)](https://github.com/user-attachments/files/25640945/game_log_20260301_024305.txt) — Evidence that companion is not targeted
- [Game Log (re-report)](./logs/game_log_20260302_194932.txt) — Evidence of partial fix (rotation works, shooting doesn't)
- GameAI Pro (2013): "Goal-Oriented Action Planning for a Smarter AI" — multi-target GOAP patterns

---

## Bug Re-occurrence Report #2 (March 5, 2026)

### User Feedback
On March 5, 2026, user Jhon-Crow reported: "враги всё ещё не стреляют в напарника" (enemies still don't shoot at companion).

### Investigation

Analysis of the game log (`game_log_20260305_223211.txt`) revealed:
1. Enemies were detecting the companion correctly
2. Rotation toward companion was working (`[->companion]` markers present)
3. Enemies were in FLANKING state but not transitioning to COMBAT

Key log entries showed enemies stuck in FLANKING state:
```
[22:32:29] [ENEMY] [Enemy1] ROT_CHANGE: P2:combat_state -> P1:visible, state=FLANKING, target=-171.8°, current=-168.9°, player=(642,1040), corner_timer=0.00 [->companion]
```

### Root Cause (Third Pass)

The second fix addressed the **shooting guard conditions** — places where `_shoot()` was called. However, the **state transition logic** was still checking only player visibility:

1. **FLANKING state** (`_process_flanking_state`):
   - Line 1708: On timeout, `if _can_see_player: _transition_to_combat()` — no companion check
   - Line 1724: On stuck, same issue
   - Line 1739: Combat transition used `_can_hit_player_from_current_position()` instead of `_can_hit_target_from_current_position()`

2. **IN_COVER state** (`_process_in_cover_state`):
   - Lines 1663-1685: Decision logic only checked `if _player:` and `if _can_see_player:` for transitions

3. **PURSUING state** (`_process_pursuing_state`):
   - Line 1976: Used `_can_hit_player_from_current_position()` with misleading comment
   - Line 2031: Approach phase used player-only hit check

### Pattern Applied (Third Fix)

**Before:**
```gdscript
# FLANKING timeout
if _can_see_player: _transition_to_combat()

# FLANKING combat transition
if _can_see_player and _can_hit_player_from_current_position():
    _transition_to_combat()

# IN_COVER decision
if _player:
    if _can_see_player:
        _transition_to_combat()
```

**After:**
```gdscript
# FLANKING timeout
if _can_see_player or _can_see_companion: _transition_to_combat()  # #934

# FLANKING combat transition
if (_can_see_player or _can_see_companion) and _can_hit_target_from_current_position():
    _transition_to_combat()

# IN_COVER decision
var can_see_target := _can_see_player or _can_see_companion
var has_target := (_player != null) or (_companion != null and _can_see_companion)
if has_target:
    if can_see_target:
        _transition_to_combat()
```

### Lesson Learned

When adding multi-target support to a state machine, **all three layers** must be updated:
1. **Detection layer**: Find and track companion (`BffTargetingComponent`) ✓ (1st fix)
2. **Action layer**: Shoot at companion (`_shoot()` guard conditions) ✓ (2nd fix)
3. **Transition layer**: Change state when companion visible (`if _can_see_player` → `if _can_see_player or _can_see_companion`) ✓ (3rd fix)

---

## Files Modified (Complete)

- `scripts/objects/enemy.gd` — Target selection, state transitions, shooting logic
- `scripts/components/bff_targeting_component.gd` — Companion detection component
- `tests/unit/test_bff_pendant.gd` — Regression tests for companion targeting

---

## Test Status

- **Unit tests**: 26 tests pass (GUT framework)
- **Line count**: 4988 lines (under 5000 CI limit)
- **CI checks**: All passing
