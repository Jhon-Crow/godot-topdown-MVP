# Case Study: Issue #1355 — Enemy "Teleports In Place"

## Overview

**Issue title:** fix враг с телепортом (fix enemy with teleport)
**Reported:** 2026-03-23
**Reporter:** Jhon-Crow
**Description (translated):** "the enemy sometimes teleports in place (does not move at the same time)"
**Log file:** [game_log_20260323_033911.txt](game_log_20260323_033911.txt)

---

## Evidence: Raw Log Data

The game log records eight teleport events via the `[Teleporter]` tag. Their origin/destination positions and distances are:

| Log line | Time     | From                         | To                          | Distance (px) | Category    |
|----------|----------|------------------------------|-----------------------------|---------------|-------------|
| 806      | 03:39:36 | (1975.715, 2665.908)         | (895.3165, 1909.689)        | **1318.76**   | Normal      |
| 1209     | 03:39:42 | (1008.513, 1897.292)         | (1015, 1895.183)            | **6.82** ⚠️   | **BUG**     |
| 1754     | 03:39:50 | (2293.656, 2773.444)         | (1145.679, 1859.084)        | **1467.62**   | Normal      |
| 2380     | 03:40:00 | (2324.113, 2690.066)         | (1495.285, 1705.172)        | **1287.23**   | Normal      |
| 2932     | 03:40:08 | (2160.926, 2708.739)         | (1004.051, 1805.652)        | **1261.47**   | Normal      |
| 3828     | 03:40:22 | (1800.611, 2183.315)         | (831.8792, 1079.894)        | **1488.28**   | Normal      |
| 4106     | 03:40:28 | (888.921, 988.0231)          | (889.6848, 985)             | **3.12** ⚠️   | **BUG**     |
| 5153     | 03:40:42 | (815.3771, 973.5206)         | (832.4325, 985)             | **20.56** ⚠️  | **BUG**     |

**Three out of eight teleports** (37.5%) are effectively in-place: the enemy barely moves (< 21 pixels), yet the full teleport animation/sound fires, creating a confusing "flickering in place" effect for the player.

---

## Timeline / Sequence of Events

### Bug Instance 1 — Line 1209 (03:39:42), distance 6.82 px

```
03:39:40  [TeleporterEnemy] Hit: dmg=1, hp=3/4->2/4
03:39:40  [TeleporterEnemy] State: COMBAT -> RETREATING
  ...
03:39:42  [Teleporter] Teleported from (1008.513, 1897.292) to (1015, 1895.183)
```

1. Enemy takes damage, transitions to **RETREATING** state.
2. The physics update triggers the cover-teleport check (enemy.gd line 1310–1312):
   > "if teleport component ready AND `_under_fire` AND state ≠ IN_COVER → find cover → teleport to cover"
3. `_find_cover_position()` runs its 16-ray sweep and finds the best scoring cover position at `(1015, 1895.183)` — only **6.82 px** away from the enemy's current position.
4. `try_teleport()` only enforces a **maximum** distance cap (1 viewport diagonal ≈ 1469 px). A 6.82 px distance passes the check trivially.
5. The teleport executes: blue particle burst at origin AND destination (essentially the same spot), `global_position` is set to `(1015, 1895.183)`, cooldown starts.
6. Player sees the enemy flash/sparkle without actually moving anywhere meaningful.

### Bug Instance 2 — Line 4106 (03:40:28), distance 3.12 px

```
03:40:27  [TeleporterEnemy] State: SUPPRESSED -> SEEKING_COVER
03:40:28  [TeleporterEnemy] Player distracted - priority attack triggered
03:40:28  [TeleporterEnemy] [#1311] Player bullet entered threat sphere — suppression triggered
03:40:28  [Teleporter] Teleported from (888.921, 988.0231) to (889.6848, 985)
```

1. Enemy is in **SEEKING_COVER** state, under fire (`_under_fire` = true).
2. Same cover-teleport code path fires.
3. Nearest wall raycast hits something only ~3 px away — cover position computed at collision_point + normal × 35 px happens to be just 3.12 px from the enemy.
4. Teleport fires in-place. Distance: **3.12 px** — effectively zero.

### Bug Instance 3 — Line 5153 (03:40:42), distance 20.56 px

```
03:40:42  [TeleporterEnemy] State: COMBAT -> RETREATING
03:40:42  [TeleporterEnemy] ROT_CHANGE: ... state=RETREATING ...
03:40:42  [Teleporter] Teleported from (815.3771, 973.5206) to (832.4325, 985)
```

1. Enemy transitions to **RETREATING**, immediately triggering the cover-teleport check.
2. Cover found at **20.56 px** — not truly "in place" but still far too short for a meaningful teleport.
3. The 5-second teleport cooldown is now consumed on a useless micro-teleport.

---

## Root Cause Analysis

### Primary Root Cause: Missing Minimum Distance Guard in `try_teleport()`

**File:** `scripts/components/enemy_teleport_component.gd`
**Function:** `try_teleport()` (line 37–44)

```gdscript
func try_teleport(target: Vector2) -> bool:
    if not is_ready() or _parent == null:
        return false
    var dist := _parent.global_position.distance_to(target)
    if dist > _get_max_distance():   # ← only upper bound checked
        return false
    _execute_teleport(target)
    return true
```

There is **no lower bound** on `dist`. Any target distance > 0 passes, including the observed 3.12 and 6.82 px cases. The fix is a single additional guard:

```gdscript
const MIN_TELEPORT_DISTANCE: float = 200.0  # minimum meaningful teleport
...
if dist < MIN_TELEPORT_DISTANCE:
    return false
```

### Secondary Contributing Factor: `_find_cover_position()` Can Return Nearby Positions

**File:** `scripts/objects/enemy.gd`
**Function:** `_find_cover_position()` (line 3228+)

The scoring function favors:
- Positions hidden from player (highest weight: 10.0)
- Closer positions (distance_score = `1.0 - dist/MAX`)
- Positions behind cover (blocking_score)

When the enemy is already standing next to a wall, `collision_point + collision_normal × 35` can be on the same side of the wall as the enemy — only 35 px away or less. The "closer is better" distance score actually makes a nearby wall corner the *best* candidate. The result is a valid-but-useless cover position that is nearly on top of the enemy.

This is a secondary issue. Even if `_find_cover_position()` returns a nearby point, a minimum distance check in `try_teleport()` would prevent the useless teleport.

### Tertiary Factor: Navmesh Snap Can Return Current Position

**File:** `scripts/objects/enemy.gd`
**Function:** `_calculate_flank_position()` (line 3310)

```gdscript
if _nav_agent: _flank_target = NavigationServer2D.map_get_closest_point(_nav_agent.get_navigation_map(), _fp)
```

As documented in Godot's own forum ([thread #79052](https://forum.godotengine.org/t/navigationserver2d-get-closest-point-inaccuracy/79052) and [thread #132040](https://forum.godotengine.org/t/navigationserver2d-map-get-closest-point-issue/132040)), `map_get_closest_point` can return a point near the query position — especially near navmesh edges. If `_fp` (the ideal flank position) is unreachable through the navmesh, the snap returns the nearest reachable point, which could be near the enemy. This only affects the flank-teleport path (line 1313 in enemy.gd), but the same minimum-distance fix would prevent it too.

---

## Observed Pattern in Log

All three buggy teleports share the same pattern:
1. Enemy transitions to RETREATING or SEEKING_COVER (triggered by taking damage while `_under_fire` = true).
2. The cover-teleport guard on line 1310–1312 fires in the **same physics frame** as the state transition.
3. `_find_cover_position()` finds a cover position nearby (enemy is already near a wall).
4. `try_teleport()` accepts the nearby target because it only checks max distance.

The normal teleports (1318–1488 px) fire during **FLANKING** state (flank-teleport, line 1313), where the target is far from the enemy by design.

---

## Impact

| Dimension | Impact |
|-----------|--------|
| **Gameplay** | High: Player sees enemy "flicker" or flash visual effects without moving. Breaks immersion and looks like a glitch. |
| **Tactical fairness** | Medium: The 5-second teleport cooldown is wasted on a useless micro-teleport. The enemy cannot use its teleport ability to escape for another 5 seconds. |
| **Reproduction rate** | High: Occurs every round when enemy is under fire near a wall (3/8 teleports in a single 3-minute session). |
| **Difficulty** | Low: Enemy actually becomes *weaker* because cooldown is wasted. |

---

## Proposed Solutions

### Solution A — Minimum Distance Guard in `try_teleport()` *(Recommended)*

**Location:** `scripts/components/enemy_teleport_component.gd`

Add `MIN_TELEPORT_DISTANCE` constant and check:

```gdscript
## Minimum distance for a teleport to be considered meaningful.
const MIN_TELEPORT_DISTANCE: float = 200.0

func try_teleport(target: Vector2) -> bool:
    if not is_ready() or _parent == null:
        return false
    var dist := _parent.global_position.distance_to(target)
    if dist < MIN_TELEPORT_DISTANCE:   # ← NEW: reject trivially close targets
        return false
    if dist > _get_max_distance():
        return false
    _execute_teleport(target)
    return true
```

**Pros:** Single-line fix, minimal risk, easy to tune `MIN_TELEPORT_DISTANCE`.
**Cons:** Does not fix the root trigger (cover position near enemy). Buggy cover position is still selected; it just won't be teleported to. The enemy will fall back to walking to cover normally.

### Solution B — Exclude Nearby Covers from `_find_cover_position()`

**Location:** `scripts/objects/enemy.gd`, `_find_cover_position()`

Add a minimum distance check inside the cover scoring loop:

```gdscript
const COVER_MIN_DISTANCE: float = 150.0   # reject covers too close to enemy

# Inside the scoring loop, after computing cover_pos:
if global_position.distance_to(cover_pos) < COVER_MIN_DISTANCE:
    continue  # Too close — not meaningful cover
```

**Pros:** Fixes the root cause; prevents wasted cover selection.
**Cons:** More invasive; may cause no valid cover to be found in tight spaces, triggering the fallback path.

### Solution C — Combine A + B *(Best)*

Apply both fixes:
- Solution A ensures `try_teleport()` never teleports short distances (defensive coding).
- Solution B ensures `_find_cover_position()` does not waste a valid cover slot on a nearby wall (proper fix).

This is the most robust approach: neither layer alone is sufficient, but together they are redundant in the best way.

### Solution D — Log Warning for Short Teleports

Add a log message in `try_teleport()` when a short-distance teleport is rejected, to aid future debugging:

```gdscript
if dist < MIN_TELEPORT_DISTANCE:
    FileLogger.info("[Teleporter] Skipped near-teleport: dist=%.1f (target=%s)" % [dist, target])
    return false
```

---

## Recommended Fix

Implement **Solution C** (A + B):

1. In `enemy_teleport_component.gd`: add `MIN_TELEPORT_DISTANCE = 200.0` constant and check `dist < MIN_TELEPORT_DISTANCE` in `try_teleport()`.
2. In `enemy.gd` `_find_cover_position()`: skip cover positions within `COVER_MIN_DISTANCE` (150 px) of the enemy.
3. Add log message for skipped short teleports (Solution D) to aid future debugging.

The `200.0` px minimum is a reasonable starting point (roughly one enemy "screen unit" of meaningful displacement). It can be adjusted based on further playtesting.

---

## Session 2: Log `game_log_20260323_051440.txt`

A second game log was provided by the reporter, revealing an additional critical bug: **enemies teleporting to `(0, 0)` — outside the map**.

### Evidence: Raw Log Data (Session 2)

| Log line | Time     | From                         | To                          | Distance (px) | Category    |
|----------|----------|------------------------------|-----------------------------|---------------|-------------|
| 641      | 05:15:04 | (350, 356.27)                | (350, 387)                  | **30.73**     | Short ⚠️    |
| 888      | 05:15:12 | (350, 387)                   | (0, 0)                      | **529.90**    | **Off-map** ⚠️ |
| 921      | 05:15:31 | (28.74, 8.22)                | (0, 0)                      | **29.89**     | **Off-map + Short** ⚠️ |
| 941      | 05:15:36 | (-14.92, 160.42)             | (-3.00, 160.55)             | **11.92**     | **Short** ⚠️ |
| 974      | 05:15:46 | (7.93, 81.93)                | (0, 0)                      | **82.31**     | **Off-map** ⚠️ |
| 1005     | 05:15:56 | (7.93, 394.34)               | (0, 0)                      | **394.42**    | **Off-map** ⚠️ |
| 1113     | 05:16:07 | (350, 356.27)                | (350, 387)                  | **30.73**     | Short ⚠️    |
| 1294     | 05:16:16 | (429.85, 345.23)             | (0, 0)                      | **550.42**    | **Off-map** ⚠️ |

**Key findings:**
- **5 out of 8 teleports** go to `(0, 0)` — enemy disappears off-map
- **3 teleports** are short-distance (< 35 px) — in-place flicker
- **0 teleports** are normal — 100% failure rate in this session

### Root Cause: Teleport to (0, 0)

`_flank_target` and `_cover_position` are both initialized to `Vector2.ZERO` (line 193, 197 in `enemy.gd`). When the teleport trigger fires before these targets have been properly computed — e.g., when `_find_cover_position()` or `_calculate_flank_position()` hasn't run or found no valid result — the teleport uses the default `Vector2.ZERO` value.

Since `try_teleport()` had no check for zero-target or off-map targets, the enemy was teleported to the world origin `(0, 0)`, which is outside the playable map area.

### Root Cause: Negative Coordinates

Once at `(0, 0)`, the enemy's movement and physics push it into negative coordinates (e.g., `(-14.92, 160.42)`), creating cascading issues where subsequent cover searches and teleports produce increasingly invalid positions.

### Additional Fix Required: Nav-Map Bounds Check

Beyond the minimum distance guard, `try_teleport()` must validate that the target position lies within the navigation mesh. Using `NavigationServer2D.map_get_closest_point()`, the teleport component can verify that the snapped position is within tolerance of the requested target. If the snap distance exceeds a threshold (30 px), the target is off the navigable map and the teleport should be rejected.

---

## Applied Fix (Solution C + Nav-Map Validation)

The implemented fix addresses all three root causes:

1. **`enemy_teleport_component.gd` — `try_teleport()`:**
   - Added `MIN_DISTANCE = 50.0` constant — rejects teleports shorter than 50 px
   - Added `Vector2.ZERO` rejection — prevents teleporting to uninitialized targets
   - Added `_is_on_nav_map()` check — validates target is on the navigation mesh (within 30 px snap tolerance)
   - All rejections are logged with `FileLogger.info` for debugging

2. **`enemy.gd` — `_find_cover_position()` and `_find_distant_cover_position()`:**
   - Teleporter enemies skip cover candidates within 50 px of their current position
   - Prevents wasting cover slots on nearby wall corners

---

## Session 3: Log `game_log_20260323_055049.txt`

A third game log was provided after the initial fix was deployed. This revealed two new issues:

### Evidence: Teleport Never Succeeds

After the initial fix, the enemy's teleport was blocked in **100% of attempts**. The log shows:

1. **Nav-map rejection spam** (lines 385–600+): Hundreds of identical lines per second:
   ```
   [Teleporter] Rejected teleport: target (363.6755, 387) is off the nav-map
   ```
   The `NAV_SNAP_TOLERANCE` of 30.0 px was too strict — position (363, 387) is a valid playable position (only ~37 px from spawn point (350, 360)) but the navigation mesh snap returned a point > 30 px away.

2. **MIN_DISTANCE too strict** (lines 1105–1270+): After the enemy moved closer, hundreds of:
   ```
   [Teleporter] Rejected teleport: distance 48.8 < min 50.0
   ```
   The `MIN_DISTANCE` of 50.0 px rejected teleports that were close to the threshold. The owner specified 10 px as the minimum acceptable distance.

3. **No teleport on first damage** (line 507): Enemy was hit (`Hit: dmg=1, hp=4/4->3/4`) but never teleported because:
   - Teleport is only checked in `_process_ai_state()` when `_under_fire` is true
   - The damage handler (`on_hit_with_bullet_info`) transitions the enemy to COMBAT but doesn't trigger teleport
   - By the time the physics loop runs, the teleport target is still being rejected

### Root Causes Found (Session 3)

| Issue | Root Cause | Fix |
|-------|-----------|-----|
| Nav-map false rejections | `NAV_SNAP_TOLERANCE = 30.0` too strict for experimental spawn positions | Increased to `50.0` |
| MIN_DISTANCE too strict | `MIN_DISTANCE = 50.0` rejects legitimate short-range cover teleports | Reduced to `10.0` per owner feedback |
| Log spam (thousands of lines/sec) | `try_teleport()` logs every frame with no rate-limiting | Added `_log_reject()` with deduplication — only logs first occurrence + summary count |
| No teleport on first damage | Teleport only triggers in physics loop via `_under_fire` check, not from damage handler | Added `try_damage_teleport()` method called directly from `on_hit_with_bullet_info()` |

### Applied Fix (Iteration 2)

1. **`enemy_teleport_component.gd`:**
   - `MIN_DISTANCE`: 50.0 → **10.0** (per owner specification)
   - `NAV_SNAP_TOLERANCE`: 30.0 → **50.0** (prevents false rejections on valid positions)
   - Added `_log_reject()` / `_flush_reject_log()` for rate-limited rejection logging
   - Added `try_damage_teleport(cover, flank)` — attempts teleport to cover then flank, called from damage handler

2. **`enemy.gd` — `on_hit_with_bullet_info()`:**
   - After non-lethal hit processing, teleporter enemies now immediately attempt `try_damage_teleport()`
   - If successful, transitions to IN_COVER state
   - Cover search is triggered if no valid cover exists yet

3. **`enemy.gd` — cover distance thresholds:**
   - `_find_cover_position()` and `_find_distant_cover_position()` skip threshold: 50.0 → **10.0** (matches MIN_DISTANCE)

---

## References

- [Godot Forum: NavigationServer2D get_closest_point inaccuracy](https://forum.godotengine.org/t/navigationserver2d-get-closest-point-inaccuracy/79052)
- [Godot Forum: NavigationServer2D.map_get_closest_point issue](https://forum.godotengine.org/t/navigationserver2d-map-get-closest-point-issue/132040)
- [Godot Forum: get_next_path_position() returns current position](https://forum.godotengine.org/t/get-next-path-position-returns-current-position/60753)
- [Godot Issue #102695: CharacterBody2D sets platform velocity when depenetrating](https://github.com/godotengine/godot/issues/102695)
- [Godot Issue #84153: CharacterBody2D teleports with another CharacterBody2D](https://github.com/godotengine/godot/issues/84153)
- `scripts/components/enemy_teleport_component.gd` — teleport logic (Issue #752)
- `scripts/objects/enemy.gd` — cover-teleport trigger lines 1310–1313, `_find_cover_position()` line 3228, `_calculate_flank_position()` line 3305
