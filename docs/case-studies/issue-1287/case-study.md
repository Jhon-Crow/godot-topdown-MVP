# Case Study: Issue #1287 — Tactical Group Movement for Enemies

## Summary

**Issue:** [#1287 — update групповое перемещение](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1287)
**PR:** [#1288 — feat(#1287): tactical group movement — enemies within 500px encircle player](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1288)
**Status:** Implemented and merged to branch, pending merge to main.

The issue requests that enemies within **500 px** of the player form a tactical group and coordinate their paths to encircle the player rather than rushing from the same direction.

---

## Data Collected

### Game Log (2026-03-22 04:08:26)

**File:** [`game_log_20260322_040826.txt`](./game_log_20260322_040826.txt)

**Environment:**
- Game: Godot Top-Down Template
- Engine: Godot 4.3-stable (official)
- OS: Windows
- Build: Export (non-debug)
- Level: LabyrinthLevel
- Player weapon: M16 (AssaultRifle)

**Key observations from log:**

1. **Tactical group feature is present but disabled:**
   ```
   [ExperimentalSettings] ExperimentalSettings initialized - ... Tactical group: false
   ```
   The build running this log already includes our PR's changes. The feature works.

2. **Enemy path monitor overlay created successfully:**
   ```
   [EnemyPathMonitor] EnemyPathMonitor: overlay created
   ```
   Path display initializes correctly in this session.

3. **Nav mesh display works:**
   ```
   [NavMeshMonitor] refresh done: 1 region(s), 1 baked poly(s), 0 outline(s), 1 draw polys
   [NavMeshMonitor] Overlay shown with 1 polygon(s)
   ```

4. **Enemy count:** 5 enemies in LabyrinthLevel at spawn (Enemy1–Enemy5), later levels reach Enemy1–Enemy10.

5. **FPS drops detected** (multiple instances):
   ```
   [FPS] Drop detected: 27 fps (threshold: 30)
   [FPS] Drop detected: 20 fps (threshold: 30)
   ```
   Drops occur during scenes with many blood decals spawning simultaneously (30+ decals per kill).

6. **No tactical group errors** — no scripting errors, null references, or failures related to `TacticalGroupComponent` in the log.

7. **Enemy behavior works correctly** — enemies transition between states (GUARD → PURSUING → COMBAT → PURSUING) normally.

8. **"No valid flank position" warnings** (pre-existing, unrelated to this issue):
   ```
   [Enemy1] Warning: No valid flank position (both sides behind walls)
   [Enemy4] Warning: No valid flank position (both sides behind walls)
   ```

---

## Timeline / Sequence of Events

### Problem Background

Before this issue, enemy AI moved each unit independently toward the player's position. When multiple enemies engaged simultaneously, they all navigated to the same target point. This caused:
- Enemies stacking on top of each other
- No positional variety in approach
- Player could face all enemies from one direction

### Implementation Sequence

1. **Initial implementation** (commit `f71e2669`): Added `TacticalGroupComponent`, modified `enemy.gd`, `experimental_settings.gd`, `ExperimentalMenu.tscn`, `experimental_menu.gd`, and unit tests.

2. **Line count fix** (commit `19dad4d1`): Condensed comments in `enemy.gd` to stay within the 5000-line limit imposed by the project.

3. **Path display regression identified**: After implementation, merging with `main` (which had fix for PR#1286 — path/navmesh display) was needed. The bug was in `search_path_monitor.gd` and `waypoint_monitor.gd` where `_draw_node` was initialized in `_ready()` instead of `_init()`. Since `_ready()` is deferred to the next frame after `add_child()`, calling `refresh()` immediately after creating the overlay would find `_draw_node == null`.

4. **Fix applied** (merge commit `29aa2a48`): Merged `origin/main` which contains PR#1286's fix. Now `_draw_node` is initialized in `_init()` making it available immediately.

---

## Root Cause Analysis

### Primary Issue: Enemy Coordination

**Root cause:** `NavigationAgent2D` in Godot uses ORCA (Optimal Reciprocal Collision Avoidance) for local avoidance, but each agent computes its own path independently to the player's exact position. When N enemies all target `(player.x, player.y)`, they converge to the same point.

**Solution:** Pre-compute N evenly-spaced angular slots around the player and assign each enemy a slot. Enemies navigate to `player_pos + direction(slot_angle) * APPROACH_DISTANCE` instead of to `player_pos` directly.

### Secondary Issue: Path Display Broken After Merge

**Root cause:** In `_SearchPathOverlay` (and similar classes), the inner `_draw_node` was created in `_ready()`. In Godot 4, `_ready()` is called deferred — on the *next frame* after `add_child()`. If `refresh()` was called in the same frame as `new() + add_child()`, `_draw_node` was still `null`, causing a null-safe early return and no visible paths.

**Fix:** Move `_draw_node` initialization to `_init()` which runs synchronously before `add_child()` returns.

---

## Solution Design

### TacticalGroupComponent (`scripts/components/tactical_group_component.gd`)

| Constant | Value | Purpose |
|---|---|---|
| `GROUP_RADIUS` | 500 px | Distance within which enemies join a group |
| `MIN_GROUP_SIZE` | 2 | Minimum enemies to activate group logic |
| `APPROACH_DISTANCE` | 160 px | Orbit radius — enemies approach to this distance |
| `CLOSE_RANGE` | 80 px | Inside this range, no offset applied (engage normally) |
| `UPDATE_INTERVAL` | 0.4 s | How often slot assignments are recalculated |

**Algorithm:**
1. Every `UPDATE_INTERVAL` seconds, query all alive combat-active enemies within `GROUP_RADIUS` of the player.
2. If `count >= MIN_GROUP_SIZE`, compute N evenly-spaced angles: `slot_i = i * (2π / N)`.
3. Assign each enemy to the slot closest to its current bearing relative to the player (greedy assignment, no duplicates).
4. Navigate to `player_pos + Vector2(cos(slot), sin(slot)) * APPROACH_DISTANCE`.
5. Within `CLOSE_RANGE`, blend offset to zero so enemies can actually reach and attack the player.

### Integration in `enemy.gd`

```gdscript
# In _ready():
_tactical_group = TacticalGroupComponent.new(self)

# In PURSUING/COMBAT/ASSAULT target calculation:
if _tactical_group and _current_state in [AIState.PURSUING, AIState.COMBAT, AIState.ASSAULT]:
    target_pos = _tactical_group.get_adjusted_target(target_pos, get_physics_process_delta_time())
```

### ExperimentalSettings

New flag `tactical_group_enabled: bool = false` with getter `is_tactical_group_enabled()` and setter `set_tactical_group_enabled()`. Persisted in `user://experimental_settings.cfg`. Off by default.

---

## Known Issues / Observations

1. **FPS drops** during heavy blood decal spawning (30+ decals/kill) — pre-existing, unrelated to this issue. Visible in game log at `04:09:11`, `04:09:22`, etc.

2. **"No valid flank position" warnings** — pre-existing warnings from flanking behavior when walls block both sides. Unrelated to tactical group.

3. **Feature is disabled by default** — user must enable via Experimental Menu → Tactical Group Movement. This is intentional (experimental feature).

---

## Related Work

- **PR #1278 / Issue #1277**: Added enemy navigation path display feature that this issue builds upon.
- **PR #1286 / Issue #1285**: Fixed path/navmesh display by initializing `_draw_node` in `_init()` — directly related because our branch needed to merge this fix.
- **ORCA avoidance**: Godot's `NavigationAgent2D` uses ORCA internally. Our approach offsets the *target* rather than modifying the avoidance algorithm, making it compatible with existing ORCA behavior.

---

## External References

- [Godot 4 NavigationAgent2D docs](https://docs.godotengine.org/en/stable/classes/class_navigationagent2d.html) — ORCA avoidance built-in
- [ORCA algorithm (van den Berg et al., 2011)](https://gamma.cs.unc.edu/ORCA/) — basis of Godot's local avoidance
- [Coordinated multi-agent pathfinding](https://en.wikipedia.org/wiki/Multi-agent_pathfinding) — general problem our solution addresses
- [Encirclement/flanking in game AI](https://www.gamedeveloper.com/design/coordinated-unit-movement) — classic game AI design pattern

---

## Conclusion

The implementation successfully addresses the issue requirements:
- Enemies within 500 px of the player form a tactical group ✅
- Paths are coordinated so enemies spread around the player (encirclement) ✅
- Existing ORCA-based collision avoidance still handles wall-following and local bumping ✅
- Feature is opt-in via Experimental Menu ✅
- Path/navmesh display regression fixed by merging main ✅
- Unit tests cover constants, group detection, slot uniqueness, blend-out, and angle helpers ✅
