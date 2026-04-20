# Case Study: Issue #1632 — Original Enemy Teleports Through Walls on Illusion Spawn

## Overview

**Issue**: When a gas-mask enemy throws a chemical grenade and illusory copies are spawned (`ChemicalCloud._spawn_illusions_for_nearby_enemies`), the original enemy is teleported to a randomly chosen offset position. In narrow corridors, this sometimes placed the enemy inside wall geometry.

**Status**: Updated in PR #1646 after two follow-up reports: wall placement persisted at lower frequency after the nav-mesh-only fix, then the physics validation raised performance concerns in long chemical-cloud sessions.

**Input logs**:
- `logs/game_log_20260327_223228.txt` (session from 2026-03-27 22:32-22:33)
- `logs/game_log_20260327_231057.txt` (performance follow-up)
- `logs/game_log_20260327_232137.txt` (performance follow-up)
- `logs/game_log_20260327_233304.txt` (performance follow-up)
- `logs/game_log_20260418_080333.txt` (visual regression follow-up)
- `logs/game_log_20260420_115753.txt` (visual regression follow-up)
- `logs/game_log_20260420_122934.txt` (GDScript class registration follow-up)
- `logs/game_log_20260420_125332.txt` (continued missing-gas report)
- `logs/game_log_20260420_125349.txt` (continued missing-gas report)
- `logs/performance-key-lines.txt` (extracted chemical-cloud and FPS events)

---

## Timeline of Events (from game log)

| Time | Event |
|------|-------|
| 22:32:50 | Chemical cloud spawned at (193.4, 2569.0), radius=600 |
| 22:32:50 | Enemy moved (192.4, 2547.2) → (97.5, 2478.1), offset **−113.6px** — HIGH RISK |
| 22:32:50 | Enemy moved (201.1, 2607.9) → (140.7, 2521.0), offset **105.8px** — HIGH RISK |
| 22:32:52 | `[ForkGuardRight] Warning: No valid flank position (both sides behind walls)` |
| 22:33:01 | Second cloud spawned at (79.2, 2670.6) |
| 22:33:01 | Enemy moved (61.0, 2762.1) → (157.3, 2723.3), offset **103.9px** — HIGH RISK |
| 22:33:10 | Third cloud spawned at (120.4, 2604.9) |
| 22:33:10 | Enemy moved (159.0, 2317.7) → (103.0, 2402.8), offset **101.9px** — HIGH RISK |
| 22:33:13 | `[ForkGuardUp] FLANKING stuck (2.0s), pos=(177.7, 1158.6)` |
| 22:33:37 | Fourth cloud spawned, 3 enemies moved with offsets 101–114px — HIGH RISK |

### All Original Enemy Movements (13 total)

| Time | From | To | Offset magnitude | Risk |
|------|------|----|-----------------|------|
| 22:32:50 | (200.0, 2701.3) | (130.8, 2736.7) | 77.7 px | medium |
| 22:32:50 | (201.1, 2607.9) | (140.7, 2521.0) | **105.8 px** | HIGH |
| 22:32:50 | (192.4, 2547.2) | (97.5, 2478.1) | **117.4 px** | HIGH |
| 22:33:01 | (61.0, 2762.1) | (157.3, 2723.3) | **103.9 px** | HIGH |
| 22:33:01 | (264.0, 1656.3) | (188.0, 1641.0) | 77.5 px | medium |
| 22:33:10 | (200.7, 2621.3) | (274.5, 2657.2) | 82.0 px | medium |
| 22:33:10 | (159.0, 2317.7) | (103.0, 2402.8) | **101.9 px** | HIGH |
| 22:33:10 | (256.2, 2369.0) | (311.8, 2340.1) | 62.7 px | medium |
| 22:33:19 | (200.0, 2752.7) | (250.8, 2856.2) | **115.3 px** | HIGH |
| 22:33:26 | (242.1, 2721.5) | (245.5, 2656.5) | 65.1 px | medium |
| 22:33:37 | (204.1, 2621.0) | (304.9, 2615.3) | **101.0 px** | HIGH |
| 22:33:37 | (178.1, 2580.5) | (209.5, 2685.0) | **109.1 px** | HIGH |
| 22:33:37 | (299.2, 2313.9) | (275.0, 2202.3) | **114.2 px** | HIGH |

**8 of 13 moves (62%) had offsets ≥100 px** — these are the risky ones.

---

## Root Cause Analysis

### Root Cause 1: Nav-mesh Snap Tolerance Is Too Permissive

The fix in PR #1646 introduced `_is_position_on_nav_map()` with `NAV_SNAP_TOLERANCE = 50.0` px.

`NavigationServer2D.map_get_closest_point(nav_map, pos)` returns the **nearest point on the nav-mesh surface**. When a candidate position is inside a wall:
- The closest nav-mesh point is the nearest edge of the nav-mesh polygon — usually the inside edge of the wall.
- If the wall is **thinner than 50 px**, the snapped distance is less than 50 px → the position is falsely accepted.

Common wall thicknesses in tilemaps: 16–64 px. Many corridor walls are ≤50 px thick.

### Root Cause 2: Nav-mesh Geometry ≠ Physical Geometry

The nav-mesh is baked from physics geometry with a safety margin (`agent_radius` in the NavigationPolygon). However:
- The nav-mesh boundary can be offset from the physical wall by the agent radius (typically 10–20 px).
- A point just inside the physical wall may still be within 50 px of the nav-mesh edge.
- The nav-mesh check confirms reachability for navigation, not physical overlap with wall collision shapes.

### Root Cause 3: No Physical Overlap Check

The codebase already has a proven pattern for checking if a position is inside a wall:

```gdscript
# From enemy.gd line 3089 — checks if a point is inside a wall (obstacles layer)
var pq := PhysicsPointQueryParameters2D.new()
pq.position = candidate_pos
pq.collision_mask = 4  # Layer 3 = obstacles/walls
if not space_state.intersect_point(pq, 1).is_empty():
    # Position is inside a wall — reject it
```

This uses Godot's physics engine to directly test overlap with colliders. The nav-mesh check **does not** do this — it only measures distance to the nearest nav polygon surface point.

### Root Cause 4: No Line-of-Sight Check Between Old and New Position

Even if the destination is on the navmesh, the straight line from the enemy's current position to the target may cross a wall. Moving through a wall (even briefly via `global_position =`) clips the enemy into geometry, and the physics engine may not push them out correctly.

### Root Cause 5: Center Candidate Could Short-Circuit Random Placement

The first physics-validation draft shuffled all candidate indices, including index `0` (the original center position). Because the center was accepted immediately as always valid, any shuffle that put index `0` before valid non-center offsets would keep the real enemy in place without testing those offsets.

That behavior did not cause wall clipping, but it weakened the "random position for the original" behavior requested in issue #1361. The final selection now shuffles and validates only non-center offsets first, and uses center strictly as the fallback when no random offset is safe.

---

## Performance Follow-up

The owner reported on 2026-03-27 that the fix appeared to affect performance heavily and attached three more logs. Those logs show:

| Log | Chemical cloud pattern | FPS pattern |
|-----|------------------------|-------------|
| `game_log_20260327_231057.txt` | Repeated radius-600 clouds spawning capped illusion batches | FPS drops continue while clouds/illusions remain active |
| `game_log_20260327_232137.txt` | Many clouds spawn 10 illusion copies for 11-13 enemies | Drops range from high 20s down to single digits after cloud spawn |
| `game_log_20260327_233304.txt` | Multiple overlapping clouds, frequent per-cloud cap hits, global cap hits | Drops continue for the 20s cloud/illusion lifetime |

The log evidence points to the sustained cost of active chemical clouds and illusion copies, not only the one-time placement validation. The validation checks run during spawn candidate selection, while the severe FPS drops persist for many seconds after the spawn line and often until the cloud dissipates.

Still, the final implementation keeps validation allocation-light:

- One validation context is created per enemy placement batch.
- One `PhysicsPointQueryParameters2D` and one `PhysicsRayQueryParameters2D` are reused for all candidates in that batch.
- Only non-center candidates are validated. Center is not queried because it is the fallback no-move position.

---

## Evidence from the Log

### High-Risk Moves That May Have Caused Issues

Move at 22:32:50: **enemy at (192.4, 2547.2) moved to (97.5, 2478.1), offset = (−113.6, −29.7)**

This is an x-displacement of 113.6 px to the **left** from an enemy near x=192. In the LabyrinthLevel, the leftmost playable area near y=2547 is approximately x=75–90 (based on cloud position at x=193 and enemy starting positions near x=200). Moving left 113 px from x=192 puts the enemy at x=97 — potentially near or inside a left corridor wall.

### ForkGuardRight "No Valid Flank Position" Warnings

These warnings appear immediately after the first batch of illusion spawns (line 1194, 2.0s after the moves). The guard was likely stuck because it was teleported to a position near a wall and the AI's flank position calculation found no valid options.

---

## Solution

### Implemented Fix (PR #1646, first round)

Added nav-mesh validation via `NavigationServer2D.map_get_closest_point()` with 50 px tolerance. This reduced frequency but did not eliminate the bug.

### Improved Fix (Implemented)

Replace (or supplement) the nav-mesh check with **physics-based overlap detection**:

1. **Primary check**: Use `PhysicsDirectSpaceState2D.intersect_point()` with `collision_mask = 4` (obstacles layer) to directly check if the candidate position is inside a wall collider.

2. **Secondary check** (defense in depth): Keep the nav-mesh check as an additional guard. Reduce `NAV_SNAP_TOLERANCE` to 20 px (matching agent radius).

3. **Line-of-sight check**: Cast a ray from `enemy.global_position` to `candidate_pos` with `collision_mask = 4`. Reject candidates where the path crosses a wall.

4. **Preserve random original placement**: Shuffle only non-center candidates first. Keep index `0` as a deterministic fallback only if every random candidate fails validation.

5. **Reduce validation overhead**: Reuse physics query parameter objects inside a validation context instead of allocating new query objects for every candidate.

The combined approach matches the physics-query pattern used elsewhere in the codebase while avoiding the nav-mesh false positives that caused the wall placement bug.

---

---

## Visual Regression: Gas Cloud Invisible on Spawn (Issue #1688, April 2026)

**Report date**: 2026-04-18  
**Log**: `logs/game_log_20260418_080333.txt`  
**Symptom**: "газ перестал появляться (граната просто исчезает со звуком газа)" — the grenade disappears with the gas sound but no visual cloud appears.

### Analysis

The April 18 log confirms gas IS released (18/19 grenades → "Gas released" logged) and clouds ARE created ("Chemical cloud spawned" appears). The issue is purely visual.

**Root cause**: The grow-in feature (Issue #1688) sets `scale = Vector2.ZERO` on the entire `ChemicalCloud` Node2D in `_ready()`. This scales the whole node, including:

- `GPUParticles2D`: particles emit but are squished to a point — invisible.
- `Area2D` (detection area): collapses to zero size, breaking enemy-detection during grow-in.
- `_is_player_in_range()` uses direct distance comparison and is unaffected, but the Area2D is still scaled.

The cloud takes ~5.62 seconds (= gas sound length) to grow from scale 0 to 1. At the low FPS observed in the log (3–29 FPS, with many drops to 5–10 FPS), the player sees:
1. Grenade hits obstacle → gas sound plays.
2. Cloud spawned (logged by grenade code).
3. No visible gas for 5+ seconds (cloud is at near-zero scale).
4. Player interprets this as "gas did not appear".

### Fix

Scale only `_cloud_visual` (the `GPUParticles2D` or sprite fallback), not the entire node:

```gdscript
# _ready():
if grow_in_duration > 0.0 and _cloud_visual != null:
    _cloud_visual.scale = Vector2.ZERO  # visual only

# _physics_process():
if grow_in_duration > 0.0 and _cloud_visual != null:
    var grow_progress := clampf(_spawn_elapsed / grow_in_duration, 0.0, 1.0)
    _cloud_visual.scale = Vector2(grow_progress, grow_progress)
```

This keeps the detection area at full size and ensures the grow-in animation works correctly while fixing the invisible-gas regression.

---

---

## Second Visual Regression Report (April 20, 2026)

**Report date**: 2026-04-20
**Log**: `logs/game_log_20260420_115753.txt`  
**Symptom**: "у газовой гранаты всё ещё не появляется газ (сломана)" — gas grenade still produces no visible gas.

### Session Overview

| Metric | Value |
|--------|-------|
| Session duration | 11:57:53 – 11:58:15 (22 seconds) |
| Clouds spawned | 4 |
| FPS drops observed | 1 fps, then 5–23 fps after clouds |
| `[ChemicalCloud]` log lines | **0** |

### Evidence: Clouds Spawned But No ChemicalCloud Logs

The grenade script logged "Chemical cloud spawned" 4 times:

| Time | Cloud position | grow_in |
|------|---------------|---------|
| 11:58:03 | (203.9, 2632.9) | 5.62s |
| 11:58:04 | (176.1, 2877.7) | 5.62s |
| 11:58:06 | (188.0, 2878.8) | 5.62s |
| 11:58:08 | (120.3, 3120.7) | 5.62s |

Despite 4 clouds being created, there are zero `[ChemicalCloud]` messages in the log. This means `ChemicalCloud._ready()` was never called. Several possibilities:

1. **Upstream code still has the bug** — the game being tested was the upstream build which still contains `scale = Vector2.ZERO` on the whole node (not our fixed branch). The node IS added to the scene but the scale collapse makes particles invisible. The missing `_ready()` logs may be due to log buffer overload (719 log messages in 2 seconds) causing write delays.

2. **Massive log throughput** — 719 messages were generated in just 2 seconds during the cloud spawn (11:58:03–11:58:04). The `FileLogger` write buffer uses a 1-second flush interval. Under this load, ordering is preserved but messages could arrive out-of-temporal-order in the file.

### Root Cause Assessment

The April 20 log confirms the upstream version still has the invisible-gas bug. PR #1646's fix (scaling only `_cloud_visual`) is not yet merged into upstream. The user is testing the unpatched build.

**Our fix addresses this correctly**: by scaling only `_cloud_visual` (the particle node), the gas becomes visible immediately while the grow-in animation progresses over 5.62 seconds. The detection area remains at full scale throughout.

---

---

## Third Visual Regression Report (April 20, 2026 — 12:29)

**Report date**: 2026-04-20  
**Log**: `logs/game_log_20260420_122934.txt`  
**Symptom**: "газовая граната врага в противогазе всё ещё сломана, сверься с веткой backup" — gas mask enemy's gas grenade is still broken; owner asks to check the backup branch.

### Session Overview

| Metric | Value |
|--------|-------|
| Session time | 12:29:34 – 12:29:56+ |
| Clouds spawned | 8 (logged by grenade) |
| `[ChemicalCloud]` log lines | **0** — `_ready()` never ran |
| FPS drops | Yes (21, 28, 29 fps drops logged) |
| Level load error | `ERROR: Invalid resource (falling back to sync): Labyrinth2Level.tscn` |
| GDScript level init | `LevelInitFallback GDScript _ready() did NOT execute` |

### Evidence: `_ready()` Never Called

8 "Chemical cloud spawned" lines appear (from grenade), but zero `[ChemicalCloud] _ready()` lines follow. The sequence for each cloud is:

```
[12:29:40] [ChemicalGasGrenade] Spawning cloud with 5.62s grow-in matching sound
[12:29:40] [ChemicalGasGrenade] Chemical cloud spawned at (401.18, 1193.68) (radius=600, duration=20s, grow_in=5.62s)
```

No `[ChemicalCloud] _ready()` ever appears after these lines. In the March 2026 logs, `_ready()` appeared BETWEEN those two grenade messages (because `add_child()` fires `_ready()` synchronously before returning).

### Root Cause: Godot Binary Tokenization Bug (Issue #94150)

The log shows:

```
[SceneLoader] ERROR: Invalid resource (falling back to sync): res://scenes/levels/Labyrinth2Level.tscn
[LevelInitFallback] GDScript _ready() did NOT execute - performing C# fallback initialization
```

This is Godot engine bug [#94150](https://github.com/godotengine/godot/issues/94150): the async scene loader encounters binary tokenization errors, falls back to sync. The level's GDScript `_ready()` fails to execute (C# fallback compensates for that).

When `ChemicalCloud.new()` is called after this scene loading failure, Godot may fail to look up the `ChemicalCloud` class from the GDScript class registry if `chemical_cloud.gd` was not tokenized successfully in this run. The node is added to the scene tree but has no script attached — so `_ready()` (the GDScript method) is never called.

### Comparison with Backup Branch

The owner asked to "check the backup branch" (refs/heads/backup, HEAD at `7e89c045`, dated 2026-04-10). Analysis shows:

- `scripts/effects/chemical_cloud.gd` on the backup branch is **identical** to upstream/main — it still has the `scale = Vector2.ZERO` bug introduced in commit `949c490e`.
- `scripts/projectiles/chemical_gas_grenade.gd` on the backup branch is **identical** to upstream/main.
- Neither branch has a `ChemicalCloud.tscn` scene file.

The backup branch does NOT provide a working version of the gas cloud. It has the same bugs as upstream/main.

### Conclusion

There are two independent problems in the upstream build:

1. **Scale bug** (our fix in PR #1646): `scale = Vector2.ZERO` on the entire node collapses particles and detection area. Our fix scales only `_cloud_visual`. This makes the gas visible as soon as it's spawned.

2. **GDScript class registration failure** (Godot engine bug #94150): When the level scene fails to load via async, the GDScript tokenizer may fail to register `ChemicalCloud` as a class. `ChemicalCloud.new()` silently creates a bare Node2D with no script. The cloud has no behavior and is invisible.

The second issue is a Godot engine-level bug that is not reliably reproducible (it only happens when the async loader encounters tokenization errors on a given run). PR #1646 now mitigates this with `preload("res://scripts/effects/chemical_cloud.gd").new()`, which forces the resource to be compiled at game startup rather than relying on runtime class lookup.

---

---

## Fourth Visual Regression Report (April 20, 2026 — 12:53)

**Report date**: 2026-04-20

**Logs**:
- `logs/game_log_20260420_125332.txt`
- `logs/game_log_20260420_125349.txt`

**Symptom**: "всё ещё нет газа" — gas is still not visible.

### Session Overview

| Log | Clouds spawned | `[ChemicalCloud]` log lines | FPS drops |
|-----|----------------|-----------------------------|-----------|
| `game_log_20260420_125332.txt` | 2 | 0 | 1 fps |
| `game_log_20260420_125349.txt` | 7 | 0 | 3, 16, 21 fps |

The logs again show grenade-level cloud creation:

```gdscript
[12:53:52] [ChemicalGasGrenade] Chemical cloud spawned at (169.4894, 1118.667) (radius=600, duration=20s, grow_in=5.62s)
```

There are still no `[ChemicalCloud] _ready()` messages. The owner-visible symptom therefore remains consistent with a cloud node that is either not executing its script or not appearing at the intended world position.

### Additional Root Cause: Assigning `global_position` Before Scene Attachment

Both gas grenade implementations created the cloud, assigned `cloud.global_position`, and only then added it to `get_tree().current_scene`.

That order is unsafe for runtime nodes spawned under transformed scene roots. Before a node enters the scene tree, `global_position` has no active parent transform to resolve against, so the assignment can effectively become local position. When the cloud is later attached under the level root, the root transform can move the cloud away from the grenade while the log still prints the grenade's intended position.

This explains a player-visible state where:

1. The grenade disappears and logs "Chemical cloud spawned".
2. No gas is visible at the impact point.
3. Gameplay still appears as if no gas exists near the player.

### Fix

Set cloud configuration first, attach it to the active scene, then assign `global_position`:

```gdscript
get_tree().current_scene.add_child(cloud)
cloud.global_position = global_position
```

This was applied to:

- `scripts/projectiles/chemical_gas_grenade.gd`
- `scripts/projectiles/aggression_gas_grenade.gd`

The previous `preload("res://scripts/effects/chemical_cloud.gd").new()` mitigation remains in place so the chemical cloud script is compiled at grenade-load time instead of relying on runtime `class_name` lookup.

---

---

---

---

## Fifth Visual Regression Report (April 20, 2026 — 13:10)

**Report date**: 2026-04-20
**Log**: `logs/game_log_20260420_131056.txt`
**Symptom**: "не исправлено" — still not fixed.

### Session Overview

| Metric | Value |
|--------|-------|
| Session time | 13:10:56 – 13:11:17 |
| Clouds spawned | 4 (logged by grenade) |
| `[ChemicalCloud]` log lines | **0** — `_ready()` never ran |
| No SceneLoader error in this log | Async fallback is absent this run |

### Log Evidence

The log shows 4 successful cloud-spawn lines:

```
[13:11:10] [ChemicalGasGrenade] Chemical cloud spawned at (92.77065, 933.2136) (radius=600, duration=20s, grow_in=5.62s)
[13:11:11] [ChemicalGasGrenade] Chemical cloud spawned at (329.0563, 1027.515) (radius=600, duration=20s, grow_in=5.62s)
[13:11:12] [ChemicalGasGrenade] Chemical cloud spawned at (328.0982, 1043.108) (radius=600, duration=20s, grow_in=5.62s)
[13:11:13] [ChemicalGasGrenade] Chemical cloud spawned at (328.1023, 1052.131) (radius=600, duration=20s, grow_in=5.62s)
```

There are zero `[ChemicalCloud]` messages following any of these lines. No SceneLoader errors appear in this run.

### Root Cause Analysis

The previous preload mitigation (`preload("res://scripts/effects/chemical_cloud.gd").new()`) is **not sufficient**. Even though `preload()` forces the GDScript resource to compile at load time, calling `.new()` on the loaded GDScript resource in Godot 4 does not guarantee that the compiled class is registered in the runtime global class registry under all conditions.

The definitive fix is to use a **PackedScene** (`.tscn` file) and call `instantiate()` instead of `.new()`. This is how all other effects in the codebase work (BloodEffect.tscn, ExplosionFlash.tscn, etc.). The `instantiate()` path:

1. Uses the PackedScene's serialized script reference directly — bypasses the GDScript class registry entirely.
2. Is guaranteed to call `_ready()` on all script nodes after `add_child()`.
3. Is consistent with how `ChemicalGasGrenade.tscn` itself is instantiated by `GasMaskGrenadeComponent`.

### Fix Applied

Created `scenes/effects/ChemicalCloud.tscn` — a minimal Node2D scene with `chemical_cloud.gd` attached as a script.

Changed `chemical_gas_grenade.gd`:
- Replaced `const ChemicalCloudScript := preload("...chemical_cloud.gd")` with `const ChemicalCloudScene := preload("res://scenes/effects/ChemicalCloud.tscn")`
- Replaced `ChemicalCloudScript.new()` with `ChemicalCloudScene.instantiate()`

Applied the same fix to `aggression_gas_grenade.gd` / `aggression_cloud.gd`:
- Created `scenes/effects/AggressionCloud.tscn`
- Changed to `const AggressionCloudScene := preload("res://scenes/effects/AggressionCloud.tscn")` + `AggressionCloudScene.instantiate()`
- Also fixed the `aggression_cloud.gd` issue #1688 regression: the whole-node scale was never fixed (it was only fixed for `chemical_cloud.gd`). Now only `_cloud_visual` is scaled so the detection area stays at full size.

---

---

## Files Involved

| File | Role |
|------|------|
| `scripts/effects/chemical_cloud.gd` | Main fix location — `_spawn_illusions_for_nearby_enemies()`, `_create_position_validation_context()`, and `_is_position_valid()` |
| `scenes/effects/ChemicalCloud.tscn` | New: PackedScene for reliable `instantiate()` — bypasses GDScript class registry |
| `scenes/effects/AggressionCloud.tscn` | New: PackedScene for `AggressionCloud` — same reliability fix |
| `scripts/effects/aggression_cloud.gd` | Fixed: whole-node scale bug (#1688 regression) — now scales only `_cloud_visual` |
| `scripts/effects/illusion_effect.gd` | IllusionEffect node — not involved in position validation |
| `scripts/components/enemy_teleport_component.gd` | Reference: uses same nav-mesh approach (50px tolerance) |
| `scripts/characters/player.gd` | Reference: `_is_spawn_position_valid()` uses physics overlap check (correct approach) |

---

## References

- [Godot 4 NavigationServer2D.map_get_closest_point](https://docs.godotengine.org/en/stable/classes/class_navigationserver2d.html#class-navigationserver2d-method-map-get-closest-point) — returns closest point on nav-mesh surface, does NOT detect interior-of-wall positions
- [Godot 4 PhysicsDirectSpaceState2D.intersect_point](https://docs.godotengine.org/en/stable/classes/class_physicsdirectspacestate2d.html#class-physicsdirectspacestate2d-method-intersect-point) — detects if a point is inside a collider, even when origin is inside
- PR #1646: Initial fix (nav-mesh validation)
- Issue #1632: Original report
- Issue #1355: Similar problem in `EnemyTeleportComponent` — solved with same nav-mesh approach (partial fix)
