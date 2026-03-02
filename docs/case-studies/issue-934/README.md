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
- `tests/unit/test_bff_pendant.gd` — Regression tests for companion targeting

---

## References

- [Issue #674](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/674) — BFF Pendant implementation
- [Issue #729](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/729) — Aggressive enemy navigation
- [Issue #675](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/675) — Aggression gas component
- [Game Log](https://github.com/user-attachments/files/25640945/game_log_20260301_024305.txt) — Evidence that companion is not targeted
- GameAI Pro (2013): "Goal-Oriented Action Planning for a Smarter AI" — multi-target GOAP patterns
