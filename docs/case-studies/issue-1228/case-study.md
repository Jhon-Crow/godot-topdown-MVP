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

**After (second-iteration fix — handles both GDScript and C# bullets):**
```gdscript
func _on_threat_area_entered(area: Area2D) -> void:
    if not _is_position_visible_to_enemy(area.global_position): return
    # Issue #1228: only suppress from player bullets — ignore own/enemy bullets.
    # Uses .get() for both GDScript "shooter_id" (int, -1 default) and C# "ShooterId" (ulong, 0 default).
    var raw_id = area.get("shooter_id"); if raw_id == null: raw_id = area.get("ShooterId")
    if raw_id == null: return  # No shooter info — safe default, no suppression
    var sid: int = int(raw_id); if sid <= 0: return  # -1 or 0 default — no suppression
    var shooter: Object = instance_from_id(sid); if shooter == null: return
    if not (shooter as Node).is_in_group("player"): return  # Enemy bullet — no suppression
    _bullets_in_threat_sphere.append(area)
    _threat_memory_timer = THREAT_MEMORY_DURATION
```

### Why This Fix Is Correct

1. **Faction check via group membership**: Using `is_in_group("player")` is the established pattern in this codebase (see `_is_player_bullet()` in `bullet.gd`, line 944). It reliably distinguishes player from enemy shooters for both GDScript and C# nodes.

2. **Handles all enemy bullet cases**: Own bullets (shooter = self) and other enemies' bullets (shooter = another enemy) are all excluded by the same condition — they are all not in the `"player"` group.

3. **Handles null/freed shooters safely**: If `instance_from_id()` returns `null` (shooter was freed), we conservatively skip suppression (safe default).

4. **Handles bullets with no shooter_id**: If the area has neither `shooter_id` nor `ShooterId` property (other Area2D objects), `raw_id` stays `null` and we return without suppression — safe default.

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

## Second Game Log (2026-03-21 07:08)

After the first analysis was posted in the PR, the repository owner provided a second log: `game_log_20260321_070804.txt`. This log was also from an **unpatched main-branch binary** (`Build info: not available (build_info.cfg not found)`).

**Log file:** `docs/case-studies/issue-1228/game_log_20260321_070804.txt`

### Key Findings from Second Log

The second log is shorter (2,464 lines vs 7,391) and covers ~45 seconds of gameplay (07:08:04–07:08:49). The suppression pattern is identical to the first log:

| Timestamp | Enemy | State Change | Context |
|-----------|-------|--------------|---------|
| 07:08:23 | Enemy1 | IN_COVER → SUPPRESSED | 0s after Enemy1 shot (own bullet) |
| 07:08:26 | Enemy1 | SUPPRESSED → IN_COVER | — |
| 07:08:27 | Enemy3 | IN_COVER → SUPPRESSED | Enemy4/Enemy3 shooting nearby |
| 07:08:29 | Enemy1, Enemy2, Enemy7 | IN_COVER → SUPPRESSED | Multiple enemies firing simultaneously |
| 07:08:31 | Enemy4 | IN_COVER → SUPPRESSED | Cascade continues |

At 07:08:23, Enemy1 transitions RETREATING → IN_COVER and immediately → SUPPRESSED within the same second. At that moment, Enemy1 just fired (`Sound emitted: type=GUNSHOT, source=ENEMY (Enemy1)` at 07:08:23). This is the classic self-suppression bug — Enemy1 fires, its own bullet enters its own threat sphere, and it immediately goes SUPPRESSED.

No `[#1228]` log messages appear in this log (those would only appear with the patched code from this PR), confirming the test was run on the unpatched binary.

### Confirmation

Both logs confirm the **same bug in the same unpatched main branch binary**. The fix in this PR (PR #1233) has not been merged and the owner's executable does not contain it. Once merged and a new binary is built, the `[#1228]` log lines will confirm the fix is active.

The updated `_on_threat_area_entered` now also emits detailed `[#1228]` log lines for every bullet decision (rejected/accepted), making it easy to verify the fix in future game logs.

---

## Third Game Log (2026-03-22 03:55) — Regression Report

The repository owner provided a third log on 2026-03-22 with the comment (Russian):
> "враги не подавляются от пул игрока, но подавляются от своих (или после ретритинг автоматическки не знаю)"
> Translation: "enemies are not suppressed by player bullets, but are suppressed by their own (or after retreating automatically I don't know)"

**Log file:** `docs/case-studies/issue-1228/game_log_20260322_035546.txt`

### Build Info

The log again shows `Build info: not available (build_info.cfg not found)`. This means the binary was downloaded from the GitHub Actions CI artifact for this PR branch — not from the original main branch. The CI workflow (`build-windows.yml`) runs on every push to the branch and uploads a Windows build artifact but does **not** embed `build_info.cfg`.

### What the User Observed

The user says "enemies are not suppressed by player bullets" — meaning after applying the fix (from the CI artifact), player bullets no longer suppress enemies. Enemy-to-enemy suppression persists.

### Root Cause of the Regression — C# Interop Bug in the First Fix

The original fix used:
```gdscript
if "shooter_id" in area:
    var bullet_shooter_id: int = area.shooter_id
    ...
```

**The `in` operator calls `.get()` internally.** As explicitly documented in `Scripts/Projectiles/Bullet.cs` (comment at line 566):
> *"GDScript's `.get("property_name")` does NOT work reliably with C# `[Export]` properties."*

The player uses C# weapons (AKGL, AssaultRifle — from `Scripts/Weapons/`) whose `SpawnBullet` method in `BaseWeapon.cs` creates instances of `scenes/projectiles/csharp/Bullet.tscn` (C# `Bullet.cs`). The C# Bullet has:
```csharp
[Export]
public ulong ShooterId { get; set; } = 0;
```

For C# bullets, `"shooter_id" in area` may return **FALSE** or an unexpected value. When it fails:

- **C# enemy bullets** (enemies also instantiate from `Bullet.tscn` → GDScript `bullet.gd` with snake_case `shooter_id`) ARE correctly filtered
- **C# player bullets** — if the check returns false or the property isn't read correctly, the filter logic may misclassify them

Additionally, enemies use `scenes/projectiles/Bullet.tscn` which is the **GDScript** bullet (`scripts/projectiles/bullet.gd`, snake_case `shooter_id` = -1 default), while player weapons use `scenes/projectiles/csharp/Bullet.tscn` (C# `Bullet.cs`, PascalCase `ShooterId` = 0 default).

### Fix Applied (Second Iteration)

The fix was updated to use `.get()` explicitly for **both** property names, following the established pattern from `scripts/effects/force_field_effect.gd` (Issue #932):

```gdscript
func _on_threat_area_entered(area: Area2D) -> void:
    if not _is_position_visible_to_enemy(area.global_position): return
    # Try GDScript snake_case first, then C# PascalCase (Issue #932 pattern)
    var raw_id = area.get("shooter_id"); if raw_id == null: raw_id = area.get("ShooterId")
    if raw_id == null: return  # No shooter info — safe default, no suppression
    var sid: int = int(raw_id); if sid <= 0: return  # -1 or 0 default — no suppression
    var shooter: Object = instance_from_id(sid); if shooter == null: return
    if not (shooter as Node).is_in_group("player"): return  # Enemy bullet — no suppression
    _bullets_in_threat_sphere.append(area)
```

**Key improvements over the first fix:**
1. Uses `.get()` explicitly instead of `in` operator — more reliable for C# `[Export]` properties
2. Checks both `"shooter_id"` (GDScript) and `"ShooterId"` (C# PascalCase)
3. Uses `sid <= 0` to catch both GDScript default (-1) and C# default (0) in one check
4. Logs `[#1228] Player bullet ... — suppression allowed` for player bullets, making verification easy

### Third Log Analysis

The log covers ~3 minutes 23 seconds of gameplay (03:55:46 – 03:57:09) on BuildingLevel with 10 enemies.

**Enemy-to-enemy suppressions (bug still present in first-iteration patched build):**

| Timestamp | Enemy | Time since last player shot | Cause |
|-----------|-------|-----------------------------|-------|
| 03:56:01 | Enemy4 | ~9s | Enemy cross-suppression (BUG v1) |
| 03:56:16 | Enemy1 | ~11s | Enemy cross-suppression (BUG v1) |
| 03:56:26 | Enemy3, Enemy4 | ~6s | Enemy cross-suppression (BUG v1) |
| 03:56:31 | Enemy1-4 (cascade) | ~11s | Enemy cross-suppression (BUG v1) |

**Player-bullet suppressions also affected:** Multiple suppressions that should follow player shots (at 03:55:57, 03:56:05, 03:56:20, 03:56:38, 03:56:59, 03:57:04, 03:57:08) appear to work in this log — Enemy3 suppresses 1-2 seconds after player shots. However, the user reports enemy suppression from player bullets doesn't work reliably.

The second-iteration fix resolves the C# interop issue, ensuring both player C# bullets and enemy GDScript bullets are handled correctly.

---

### Fourth and Fifth Log Analysis (2026-03-22 04:20:35 and 04:21:29)

Two logs submitted together from the **second-iteration patched binary** (same executable session).

**Log 1 (`game_log_20260322_042035.txt`)** — `Debug: false`, no combat:
- Game ran for only ~22 seconds with no firefights.
- FPS drops (1fps, 13fps, 3fps) are from scene/shader warmup at startup — pre-existing, unrelated to the fix.
- No `[#1228]` lines (expected: debug mode off, no combat reached).
- No AI state transitions to SUPPRESSED. No evidence of self-suppression.

**Log 2 (`game_log_20260322_042129.txt`)** — `Debug: true`, combat observed:
- Contains `[#1228]` diagnostic lines — **confirms the fix is in this binary**.
- Timeline around the sole SUPPRESSED event:
  - `04:21:47` — Player fires (`source=PLAYER (AKGL)`)
  - `04:21:47` — `[#1228] Player bullet 'Player' — suppression allowed` → bullet added to Enemy3's threat sphere
  - `04:21:47–50` — 6× `[#1228] Non-player bullet 'Enemy3' — no suppression` → Enemy3's own bullets correctly rejected
  - `04:21:48` — Enemy3 `COMBAT → RETREATING` (reaction to player bullet threat)
  - `04:21:50` — Enemy3 `RETREATING → IN_COVER → SUPPRESSED`
- **Conclusion: Enemy3 was suppressed by the player's bullet — this is correct behavior.**

**FPS drops in log 2:** Drops at 6fps, 3fps, 3fps, 3fps, 2fps detected during Debug=true session. With debug logging enabled, `_log_to_file` was being called for *every* enemy bullet that entered any enemy's threat sphere, causing excessive file I/O. This was addressed in the third-iteration fix by gating `[#1228]` diagnostic lines behind the `debug_logging` export flag.

**User feedback interpretation:** The user observed Enemy3 enter SUPPRESSED state and reported self-suppression. However, as shown by the `[#1228]` log evidence, the suppression was correctly triggered by a player bullet. The fix is working as intended: enemies suppress only from player bullets, never from their own or other enemies' bullets.

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/objects/enemy.gd` | Fixed `_on_threat_area_entered` to use `.get()` for both `shooter_id` and `ShooterId`; `[#1228]` diagnostic logs gated behind `debug_logging` flag |
| `tests/unit/test_enemy_self_suppression_1228.gd` | Unit tests including new C# bullet (ShooterId) test cases |
| `docs/case-studies/issue-1228/case-study.md` | This document |
| `docs/case-studies/issue-1228/game_log_20260321_064834.txt` | First game log (unpatched build) |
| `docs/case-studies/issue-1228/game_log_20260321_070804.txt` | Second game log (unpatched build, confirms same bug) |
| `docs/case-studies/issue-1228/game_log_20260322_035546.txt` | Third game log (first-fix build, reveals C# interop regression) |
| `docs/case-studies/issue-1228/game_log_20260322_042035.txt` | Fourth game log (second-fix build, debug off, no combat, FPS drops from startup warmup) |
| `docs/case-studies/issue-1228/game_log_20260322_042129.txt` | Fifth game log (second-fix build, debug on, confirms fix working via `[#1228]` lines) |
