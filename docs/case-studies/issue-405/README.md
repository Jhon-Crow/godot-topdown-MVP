# Case Study: Issue #405 - Unlimited Enemy Search Zone

## Summary

**Issue:** [#405](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/405) - "Enemy search zone should be unlimited from the very beginning"

**Original Request (Russian):** "враги с самого начала должны искать в неограниченной зоне, но начиная с зоны наиболее вероятного нахождения игрока."

**Translation:** "Enemies should search in an unlimited zone from the very beginning, but starting from the zone where the player is most likely located."

## Timeline of Events

### Initial Implementation (PR #406, commit 46ed2d3)

The initial implementation made these changes:
1. Set `SEARCH_MAX_RADIUS = INF` (unlimited search radius)
2. Added `_start_initial_search()` function called from `_ready()`
3. All enemies immediately start in SEARCHING state targeting player position

### Reported Issues (Comment by @Jhon-Crow, 2026-02-03)

User reported two problems:
1. **Enemies start in search state from the very beginning** (should not happen)
2. **Enemies ignore many zones** - should systematically explore all rooms (can't find a standing player)

### Game Log Analysis

From `game_log_20260203_112842.txt`:

```
[11:28:42] [ENEMY] [Enemy1] Enemy spawned at (300, 350), health: 2, behavior: GUARD
[11:28:42] [ENEMY] [Enemy1] SEARCHING started: center=(450, 1250), radius=100, waypoints=1
[11:28:42] [ENEMY] [Enemy1] Issue #405: Initial search started from (450, 1250)
...
[11:28:42] [ENEMY] [Enemy10] SEARCHING started: center=(450, 1250), radius=100, waypoints=1
```

**Key Observations:**
- All 10 enemies spawn and immediately enter SEARCHING state
- All enemies search from the SAME center point `(450, 1250)` (player's position)
- The radius is always `100` - never expands beyond this
- Enemies continuously restart search with `radius=100` instead of expanding

## Root Cause Analysis

### Problem 1: Incorrect Interpretation of Requirements

The original request was misinterpreted:
- **What was implemented:** ALL enemies start in SEARCHING state immediately on spawn
- **What was intended:** Enemies that have DETECTED the player (post-combat) should search in an unlimited zone

The issue description says enemies should search "from the very beginning" - but this refers to the beginning of SEARCH MODE (after detection), not the beginning of the game.

### Problem 2: Search Algorithm Clustering

All enemies converge on the same point because:
1. `_start_initial_search()` uses `_player.global_position` as the search center
2. All enemies share the same starting target
3. Enemies don't coordinate or distribute their search areas

### Problem 3: Search Radius Not Expanding

The log shows `radius=100` repeatedly without expansion because:
1. When enemies reach max waypoints, they reset to `SEARCH_INITIAL_RADIUS` (line 2234)
2. The search resets to `global_position` instead of continuing exploration
3. Enemies get stuck in a loop of "search -> run out of waypoints -> reset -> search"

## Technical Details

### Current Search Logic (enemy.gd:2213-2246)

```gdscript
func _process_searching_state(delta: float) -> void:
    # ...
    if _search_current_waypoint_index >= _search_waypoints.size() or _search_waypoints.is_empty():
        if _search_radius < SEARCH_MAX_RADIUS:
            _search_radius += SEARCH_RADIUS_EXPANSION
            _generate_search_waypoints()
            # ...
        else:
            if _has_left_idle:  # Engaged enemy - move center, continue
                _search_center = global_position
                _search_radius = SEARCH_INITIAL_RADIUS  # <-- RESETS RADIUS!
                _generate_search_waypoints()
```

The problem: When `_search_radius >= SEARCH_MAX_RADIUS` (which is `INF`), this branch NEVER executes because `INF >= INF` is always true. The code falls through to the reset branch, restarting the search.

### With `SEARCH_MAX_RADIUS = INF`:
- `_search_radius < SEARCH_MAX_RADIUS` is always true (100 < INF)
- So `_search_radius += SEARCH_RADIUS_EXPANSION` keeps increasing
- But `_generate_search_waypoints()` may return empty results for large radii
- Empty waypoints + infinite radius = reset loop

## Implemented Solution

### 1. Removed Immediate Search on Spawn

Removed `call_deferred("_start_initial_search")` from `_ready()` and deleted the `_start_initial_search()` function. Enemies now start in their normal IDLE/PATROL/GUARD states based on their `behavior` property.

### 2. Proper Search Trigger

The unlimited search zone now only activates when enemies naturally transition to SEARCHING state:
- After detecting and losing the player (COMBAT/PURSUING -> SEARCHING)
- After hearing a sound and investigating
- After state reset when player reference becomes null

### 3. Fixed Search Algorithm

Changed `SEARCH_MAX_RADIUS` from `INF` to `2000.0` (large but finite). When enemies reach max radius:
1. Enemy moves search center to their CURRENT position (not player position)
2. Enemy clears visited zones to allow fresh exploration
3. Enemy resets radius and continues searching

```gdscript
# When max radius reached:
var old_center := _search_center
_search_center = global_position  # Move center to enemy's current pos
_search_radius = SEARCH_INITIAL_RADIUS  # Reset radius
_search_visited_zones.clear()  # Clear zones for fresh exploration
_generate_search_waypoints()  # Generate new waypoints
```

### 4. Key Changes Made

1. **enemy.gd line 344**: `SEARCH_MAX_RADIUS = 2000.0` (was `INF`)
2. **enemy.gd line 495-497**: Removed `_start_initial_search()` call
3. **enemy.gd line 2233-2237**: Added `_search_visited_zones.clear()` when relocating center
4. **enemy.gd line 2241-2245**: Added `_search_visited_zones.clear()` for empty waypoint case
5. **test_enemy.gd**: Updated tests to reflect new finite max radius behavior

## References

### Research Sources

1. [Dynamic Guard Patrol in Stealth Games (AAAI)](https://cdn.aaai.org/ojs/7425/7425-52-10738-1-2-20200923.pdf) - Academic paper on intelligent patrol systems
2. [Patrolling AI Systems in Video Games (ResearchGate)](https://www.researchgate.net/publication/364090728_Patrolling_AI_Systems_in_Video_Games) - Survey of patrol AI techniques
3. [AI for Game Developers - Pattern Movement (O'Reilly)](https://www.oreilly.com/library/view/ai-for-game/0596005555/ch03.html) - Classic reference on AI movement patterns
4. [Building Complex NPC AI in Godot (Medium)](https://medium.com/@kennethpetti/building-out-complex-npc-ai-in-godot-230ef3d956ad) - Godot-specific AI implementation guide

### Key Concepts from Research

1. **Finite State Machines (FSM):** Most appropriate for predefined behaviors like patrol/alert/engage states
2. **Occupancy Maps:** Track which areas have been searched to avoid re-searching
3. **Coverage Expansion:** As guards patrol, tracked regions expand until fully covered
4. **Waypoint Systems:** Cyclic vs ping-pong patterns for systematic coverage

## Files

- `game_log_20260203_112842.txt` - Full game log showing the issues
- `README.md` - This case study document

## Related Files in Codebase

- `scripts/objects/enemy.gd` - Enemy AI script with search logic
- `tests/unit/test_enemy.gd` - Unit tests for enemy behavior
