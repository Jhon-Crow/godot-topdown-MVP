# Case Study: Issue #1228 — Enemy Self-Suppression from Own/Friendly Bullets

## Summary

**Issue:** Enemies enter the `SUPPRESSED` AI state when their own bullets (or bullets from other enemies) pass through their threat sphere — even though those bullets are not aimed at them.

**Russian title:** "враг переходит в состояние Подавлен от своих пуль, которые летят не в него"
**Translation:** "enemy transitions to SUPPRESSED state from its own bullets flying NOT toward it"

**Fix:** In `_on_threat_area_entered` (`scripts/objects/enemy.gd`), only allow player-fired bullets to trigger suppression. Bullets fired by any enemy (including the enemy itself) are excluded.

---

## Timeline / Sequence of Events

### Step 1 — Enemy Fires at Player
An enemy in COMBAT or PURSUING state fires a bullet toward the player using `_spawn_projectile()` in `scripts/objects/enemy.gd`. The bullet scene defaults to `scenes/projectiles/Bullet.tscn` (backed by `scripts/projectiles/bullet.gd`) and is spawned at the weapon muzzle, which is only `bullet_spawn_offset = 30.0` pixels from the enemy center.

### Step 2 — Bullet Spawns Inside Threat Sphere
The enemy has a `_threat_sphere: Area2D` with `threat_sphere_radius = 100.0` px. Since `bullet_spawn_offset (30px) < threat_sphere_radius (100px)`, every bullet the enemy fires spawns **inside** its own threat sphere.

### Step 3 — `area_entered` Signal Fires
When the bullet is added to the scene tree (`get_tree().current_scene.add_child(p)`), Godot's physics system detects the overlap between the bullet and the enemy's threat sphere. At the next physics frame, `_on_threat_area_entered(area)` is called on the enemy.

### Step 4 — Bug: Broken Self-Detection Logic (Pre-Fix)
The original check at the time of the bug report:

```gdscript
func _on_threat_area_entered(area: Area2D) -> void:
    if ("shooter_id" in area and area.shooter_id == get_instance_id()) or not _is_position_visible_to_enemy(area.global_position):
        return  # Own bullet or wall blocking line of sight — no suppression
    _bullets_in_threat_sphere.append(area)
```

The check `area.shooter_id == get_instance_id()` correctly excludes the **shooting enemy's own bullets**. However, it has two failure modes:

**Bug A — Other Enemies' Bullets:**
When Enemy A fires and bullets fly past Enemy B's threat sphere, Enemy B's `get_instance_id()` ≠ Enemy A's ID = `bullet.shooter_id`. The check fails → Enemy B gets incorrectly suppressed by a bullet that is not aimed at it.

**Bug B — Subtle timing with pooled bullets:**
In the projectile pool path, a bullet may momentarily overlap with the threat sphere when `monitorable` is re-enabled. This is a minor secondary risk.

### Step 5 — Enemy Transitions to SUPPRESSED
Because `_bullets_in_threat_sphere` is non-empty, `_update_suppression()` sets `_under_fire = true`. Depending on the current AI state, this triggers a transition to `SUPPRESSED` or `RETREATING`, causing the enemy to seek cover — even though the nearby bullet poses no actual threat to it.

### Step 6 — Cascading Friendly-Fire Suppression
In firefights with multiple enemies, all enemies fire simultaneously. Each enemy's bullets pass through other enemies' threat spheres, causing a cascading suppression effect: **all enemies suppressed each other's fire simultaneously**, severely degrading the AI's combat effectiveness.

---

## Root Cause Analysis

The root cause is a **design oversight** in the suppression trigger logic: the `_on_threat_area_entered` function was written to exclude only the enemy's own bullets (`shooter_id == get_instance_id()`), but did not account for bullets fired by OTHER enemies of the same faction.

### Key Code Location
`scripts/objects/enemy.gd` — function `_on_threat_area_entered` (~line 4149)

### Contributing Factors

1. **Threat sphere radius vs muzzle offset mismatch**: The threat sphere radius (100px) is more than 3× the bullet spawn offset (30px). Every bullet fired by an enemy immediately enters its own threat sphere.

2. **No faction-awareness in suppression**: The game has a clear player-vs-enemy faction structure (`"player"` group vs `"enemies"` group), but the suppression system only checked for identity equality (`shooter_id == self_id`), not faction membership.

3. **Large threat sphere for suppressive fire detection**: The 100px radius is large enough to catch bullets from adjacent enemies who are firing at the player from nearby positions.

---

## Proposed Solution

### Fix Applied

Replace the narrow self-check with a faction-aware check: **only player-fired bullets trigger enemy suppression**.

**Before:**
```gdscript
func _on_threat_area_entered(area: Area2D) -> void:
    if ("shooter_id" in area and area.shooter_id == get_instance_id()) or not _is_position_visible_to_enemy(area.global_position):
        return  # Own bullet or wall blocking line of sight — no suppression
    _bullets_in_threat_sphere.append(area)
    _threat_memory_timer = THREAT_MEMORY_DURATION
    _log_debug("Bullet entered threat sphere, starting reaction delay...")
```

**After:**
```gdscript
func _on_threat_area_entered(area: Area2D) -> void:
    if not _is_position_visible_to_enemy(area.global_position):
        return  # Wall blocking line of sight — no suppression
    # Issue #1228: only suppress from player bullets — ignore own and other enemies' bullets.
    if "shooter_id" in area:
        var bullet_shooter_id: int = area.shooter_id
        if bullet_shooter_id == -1:
            return  # Unknown shooter — no suppression
        var bullet_shooter: Object = instance_from_id(bullet_shooter_id)
        if bullet_shooter == null or not (bullet_shooter as Node).is_in_group("player"):
            return  # Bullet not from player (own or another enemy) — no suppression
    _bullets_in_threat_sphere.append(area)
    _threat_memory_timer = THREAT_MEMORY_DURATION
    _log_debug("Bullet entered threat sphere, starting reaction delay...")
```

### Why This Fix Is Correct

1. **Faction check via group membership**: Using `is_in_group("player")` is the established pattern in this codebase (see `_is_player_bullet()` in `bullet.gd`, line 944). It reliably distinguishes player from enemy shooters for both GDScript and C# nodes.

2. **Handles all enemy bullet cases**: Own bullets (shooter = self) and other enemies' bullets (shooter = another enemy) are all excluded by the same condition — they are all not in the `"player"` group.

3. **Handles null/freed shooters safely**: If `instance_from_id()` returns `null` (shooter was freed), we conservatively skip suppression (safe default).

4. **Handles bullets with no shooter_id**: If the area has no `shooter_id` property (other Area2D objects), the `"shooter_id" in area` check fails and we fall through to adding to the threat sphere — unchanged behavior for non-bullet areas.

5. **Wall blocking check remains intact**: The `_is_position_visible_to_enemy` check is preserved as the first filter.

### Alternative Approaches Considered

**Alternative A — Direction-based check**: Only suppress if the bullet is heading toward the enemy. This would require calculating trajectory vs enemy position for every bullet, which is more expensive and harder to maintain.

**Alternative B — Separate faction flag on bullets**: Add an `is_player_bullet: bool` property to bullet.gd. This is cleaner but requires additional changes to bullet spawning logic across many weapons.

**Chosen approach** (faction group check) is simpler, consistent with existing patterns, and handles the problem comprehensively.

---

## Test Coverage

New test file: `tests/unit/test_enemy_self_suppression_1228.gd`

Test cases:
- `test_own_bullet_does_not_suppress` — enemy's own bullet is ignored
- `test_other_enemy_bullet_does_not_suppress` — another enemy's bullet is ignored
- `test_player_bullet_suppresses_enemy` — player bullet correctly suppresses
- `test_player_bullet_detected_in_sphere` — correct bullet instance tracked
- `test_bullet_without_shooter_id_does_not_suppress` — unset shooter_id is safe
- `test_bullet_with_null_shooter_does_not_suppress` — freed shooter node is safe
- `test_wall_blocking_prevents_suppression` — wall check still works
- `test_multiple_player_bullets_all_suppress` — multiple player bullets tracked
- `test_mix_of_bullets_only_player_suppresses` — mixed scenario correct

---

## Game Log Evidence (2026-03-21)

A game log was provided by the repository owner after the initial fix was posted as a PR draft (still unmerged). The log is from a **release binary built from the main branch** (without the fix), which confirms the bug persists in the unpatched version.

**Log file:** `docs/case-studies/issue-1228/game_log_20260321_064834.txt`

### Key Findings from Log Analysis

**Player shot timestamps:**
```
06:48:54 — Player (MakarovPM) shot at (450, 781)
06:49:18 — Player (MakarovPM) shot
06:49:21 — Player (MakarovPM) shot
06:49:36 — Player (MakarovPM) shot
06:49:53 — Player (MakarovPM) shot
06:49:59 — Player (MakarovPM) shot
06:50:01 — Player (MakarovPM) shot
06:50:05 — Player (MakarovPM) shot
```

**Suppression events with causal analysis:**
| Timestamp | Enemy | Time since last player shot | Likely cause |
|-----------|-------|-----------------------------|--------------|
| 06:48:55 | Enemy3 | 1s | ✅ Player bullet (correct) |
| 06:48:56 | Enemy3 | 2s | ✅ Player bullet (correct) |
| 06:49:00 | Enemy3, Enemy4 | **6s** | ❌ Enemy bullet cross-suppression (BUG) |
| 06:49:05 | Enemy3 | **11s** | ❌ Enemy bullet cross-suppression (BUG) |
| 06:49:07 | Enemy2 | **13s** | ❌ Enemy bullet cross-suppression (BUG) |
| 06:49:11 | Enemy3 | **17s** | ❌ Enemy bullet cross-suppression (BUG) |
| 06:49:13 | Enemy4 | **19s** | ❌ Enemy bullet cross-suppression (BUG) |
| 06:49:14 | Enemy2, Enemy3 | **20s** | ❌ Enemy bullet cross-suppression (BUG) |
| 06:49:26 | Enemy2 | 5-8s | Ambiguous |
| 06:49:37/38 | Enemy4, Enemy3 | 1-2s | ✅ Player bullet (correct) |
| 06:49:55 | Enemy4, Enemy3 | 2s | ✅ Player bullet (correct) |

**Conclusion:** The suppression events at 06:49:00–06:49:14 occur 6–20 seconds after the last player shot, far beyond any bullet's flight time. These are clearly caused by enemy bullets cross-suppressing each other — confirming the bug described in the issue. The game had 10 enemies all firing simultaneously, and their bullets were triggering each other's threat spheres in a cascade.

### Why the User Reported the Issue After Fix Was Posted

The PR (#1233) with the fix was posted as a DRAFT on 2026-03-21 and **not yet merged** to main. The user ran a release binary built from the **main branch** (without the fix), so the bug was still present in their test. The fix on the PR branch correctly addresses the root cause.

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/objects/enemy.gd` | Fixed `_on_threat_area_entered` to use faction-aware check |
| `tests/unit/test_enemy_self_suppression_1228.gd` | New unit tests for the fix |
| `docs/case-studies/issue-1228/case-study.md` | This document |
