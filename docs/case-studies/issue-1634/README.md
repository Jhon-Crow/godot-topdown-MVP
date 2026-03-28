# Case Study: Issue #1634 — Proximity Fuse (Breaker Bullet) Cone Sector Detection

## Problem Statement

**Issue:** Breaker bullets (пули с превзрывателем) should detonate when an enemy enters the
**sector of future shrapnel** (at detonation distance ahead), not only when the bullet's straight
forward path is blocked.

The original implementation from Issue #678 used a single forward raycast to detect walls and
enemies within 95px. This means the bullet only detonated when something was *directly in its
path* — the proximity fuse had no awareness of targets within the shrapnel cone arc.

**Owner requirement (comment on PR #1661):**
> "взрыв пули должен триггериться когда в сектор будущих осколков (на расстоянии взрыва) попадает
> враг. (то есть превзрыватель должен работать как превзрыватель - взрываться раньше, чтоб
> увеличить шанс попадания осколками), только не забудь про оптимизацию"
>
> *Translation: "The explosion should trigger when an enemy enters the sector of future shrapnel
> (at detonation distance). That is, the proximity fuse should work as a fuse — explode earlier
> to increase the chance of hitting with shrapnel. Don't forget about optimization."*

---

## Real-World Analogy: How Proximity Fuses Work

A proximity fuze detonates an explosive automatically when the projectile comes within a
preset distance of a target — without requiring direct contact. Real proximity fuses use
miniaturized Doppler radar: they emit a signal and fire when a reflected return indicates
target proximity within the "lethal fragment radius."

**Key real-world insight:** The fuze fires when the target enters the *predicted lethal volume*
of the warhead — not when the projectile touches the target. For fragmentation warheads
(analogous to shrapnel), the optimal detonation point is when the target is within the
fragmentation cone radius, maximizing the chance of fragments hitting.

This is exactly what Issue #1634 implements: detonate when a target is within the shrapnel
cone sector, not just when the bullet itself would hit.

---

## Analysis of Current Implementation (Before Fix)

```
Bullet → [raycast forward] → detects wall/enemy at ≤95px → detonate at bullet position
```

**Problem:** The raycast only covers a single line of 0° width. An enemy 50px ahead at ±25°
from the bullet's direction (well within the 30° shrapnel cone) would NOT trigger detonation.
The bullet would fly past, and shrapnel would miss.

**Root cause:** Single-ray forward detection conflates "obstacle ahead" detection with
"enemy in kill zone" detection. These are different requirements.

---

## Solution Options Considered

### Option A: Multiple Raycasts in a Fan Pattern
Cast N raycasts spread across ±30° (e.g., 5 rays at -30°, -15°, 0°, +15°, +30°).

- ✅ Respects line-of-sight (wall occlusion)
- ✅ Integrates with existing physics collision mask
- ❌ 5 physics queries per frame per breaker bullet (expensive for many bullets)
- ❌ Misses enemies between rays if angle spacing is coarse

### Option B: PhysicsShapeQueryParameters2D with ConvexPolygonShape2D (Sector)
Create a triangular/wedge polygon representing the cone and use `intersect_shape`.

- ✅ Accurate cone geometry
- ✅ Single physics query
- ❌ Requires constructing polygon vertices from direction each frame
- ❌ Shape queries have higher overhead than ray/group checks for small counts

### Option C: Group Query + Geometric Cone Check with LOS (CHOSEN)
Iterate `get_nodes_in_group("enemies")`, check each alive enemy with:
1. Distance ≤ `BREAKER_DETONATION_DISTANCE` (95px)
2. Angle from bullet direction ≤ `BREAKER_SHRAPNEL_HALF_ANGLE` (45°, widened) — using dot product
3. Line-of-sight check (no wall between bullet and enemy) — prevents detonation through walls

- ✅ One extra raycast per candidate only (rare: enemies within 95px)
- ✅ O(n) over enemies only — enemies count is typically small
- ✅ Wall occlusion prevents premature detonation through walls (critical correctness fix)
- ✅ Simple, maintainable code
- ✅ Dot product avoids `acos` (no trigonometry at runtime beyond `cos()` once per bullet instance)

**Decision:** Option C was chosen for its combination of correctness, simplicity, and performance.

---

## Bug Found and Fixed: Detonation Through Walls (Session 2)

### Root Cause

The initial cone check implementation (session 1) **omitted the line-of-sight check**. This caused
breaker bullets to detonate immediately when they were fired near a room boundary with enemies on the
other side — even when a wall separated the bullet from the enemy.

**Example:** Player fires in a corridor. An enemy is in the adjacent room, 70px away but behind a
wall. The cone check returned `true` (distance ≤ 95px, angle ≤ 30°), and the bullet detonated
instantly — before reaching the enemy or even exiting the player's immediate area.

**User observation (PR #1661 comment, 2026-03-28):**

> "полностью сломались пули в ПМ"
> *Translation: "Bullets are completely broken in PM mode"*
> — Jhon-Crow, with game log attached (`game_log_20260328_085423.txt`)

### Game Log Evidence

The attached log (`game_log_20260328_085423.txt`) shows:
- Breaker bullets activated at `[08:54:40]` (AssaultRifle, not MakarovPM — "ПМ" may refer to
  the Makarov PM weapon or the test mode)
- Multiple rapid explosion events at positions that do not correspond to enemy contact
- The regular game flow (grenades, enemy awareness, weapon swaps) was otherwise normal

The log confirms that detonation was happening too frequently and in wrong positions, consistent
with through-wall triggering.

### Fix Applied

Added `_breaker_has_line_of_sight(global_position, enemy.global_position)` call before detonating
in `_check_enemy_in_shrapnel_cone()` (GDScript) and `HasLineOfSight()` in `CheckEnemyInShrapnelCone()`
(C#). If the LOS raycast hits a wall, the enemy is skipped.

Additionally, widened `BREAKER_SHRAPNEL_HALF_ANGLE` from **30°** to **45°** as requested to improve
the effectiveness of the proximity fuse in open areas.

---

## Implementation Summary

### Changes in `scripts/projectiles/bullet.gd`

The `_check_breaker_detonation()` function was restructured:

1. **Wall detection** — unchanged forward raycast for `StaticBody2D`/`TileMap`.
2. **Enemy cone detection** — new `_check_enemy_in_shrapnel_cone()` function using group
   query + dot product geometry.

```gdscript
func _check_enemy_in_shrapnel_cone() -> bool:
    var cos_half_angle := cos(deg_to_rad(BREAKER_SHRAPNEL_HALF_ANGLE))  # 45°
    var enemies := get_tree().get_nodes_in_group("enemies")
    for enemy in enemies:
        if not (enemy is Node2D): continue
        if not (enemy.has_method("is_alive") and enemy.is_alive()): continue
        var to_enemy := enemy.global_position - global_position
        var dist := to_enemy.length()
        if dist > BREAKER_DETONATION_DISTANCE: continue
        # Dot product: equals cos(angle). Enemy in cone if cos(angle) >= cos(half_angle).
        if dist > 0.0 and (to_enemy / dist).dot(direction) >= cos_half_angle:
            # LOS check: don't detonate through walls (Issue #1634 fix — session 2)
            if not _breaker_has_line_of_sight(global_position, enemy.global_position):
                continue
            _breaker_detonate(global_position)
            return true
    return false
```

### Changes in `Scripts/Projectiles/BreakerDetonation.cs`

The same logic was applied in the C# shared helper, with `CheckEnemyInShrapnelCone()` added.

---

## Performance Analysis

| Scenario | Queries per frame per bullet |
|---|---|
| Old: single forward raycast | 1 physics raycast |
| New: wall raycast + group cone check | 1 physics raycast + O(n_enemies) distance/dot checks |

The added cost per frame is O(n_enemies) multiplied by: 2 float comparisons + 1 vector
subtraction + 1 vector length + 1 dot product. For typical room-scale enemy counts (5-30
enemies), this is negligible. For large open-world scenes with hundreds of enemies, a
`PhysicsShapeQueryParameters2D` approach (Option B) would be more appropriate.

The group query `get_nodes_in_group("enemies")` is a cached operation in Godot 4 and has
near-zero overhead.

---

## Test Coverage Added

New test cases in `tests/unit/test_breaker_bullet.gd`:

- `test_detonates_when_enemy_directly_ahead_in_cone` — enemy at 0° within range
- `test_detonates_when_enemy_at_cone_edge_angle` — enemy at exactly 45° boundary (widened)
- `test_does_not_detonate_when_enemy_outside_cone_angle` — enemy at 60° (out of 45° cone)
- `test_does_not_detonate_when_enemy_in_cone_but_too_far` — enemy at 0° but > 95px
- `test_does_not_detonate_when_enemy_behind_bullet` — enemy at 180°
- `test_detonates_when_enemy_in_cone_at_exact_detonation_distance` — edge case at 95px
- `test_cone_check_uses_bullet_direction_not_just_right` — validates direction independence
- `test_normal_bullet_does_not_detonate_via_cone_check` — non-breaker bullet unchanged
- `test_does_not_detonate_when_enemy_in_cone_but_wall_blocks_los` — **LOS bug fix** (session 2)
- `test_detonates_when_enemy_in_cone_with_clear_los` — baseline with clear LOS

---

## References

- [Proximity fuze — Wikipedia](https://en.wikipedia.org/wiki/Proximity_fuze)
- [Proximity fuze — Britannica](https://www.britannica.com/technology/proximity-fuze)
- [PhysicsDirectSpaceState2D — Godot Engine docs](https://docs.godotengine.org/en/stable/classes/class_physicsdirectspacestate2d.html)
- [PhysicsShapeQueryParameters2D — Godot Engine docs](https://docs.godotengine.org/en/stable/classes/class_physicsshapequeryparameters2d.html)
- [Ray-casting — Godot Engine 4.4 docs](https://docs.godotengine.org/en/4.4/tutorials/physics/ray-casting.html)
- [How to implement a vision cone for AI in Godot](https://playgama.com/blog/godot/how-can-i-implement-a-vision-cone-for-ai-characters-in-godot-to-detect-the-player/)
- [General optimization tips — Godot Engine docs](https://docs.godotengine.org/en/stable/tutorials/performance/general_optimization.html)
- [Godot Projectile Engine (Asset Library)](https://godotengine.org/asset-library/asset/4165)
- Original Issue: [#1634](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1634)
- Original Breaker PR: [#678](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/678)
- This fix PR: [#1661](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1661)
