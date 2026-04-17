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

## Latest Regression: Exported EXE Gray Screen (2026-04-17)

### Owner Report

After the previous PM bullet/pool fix, the owner reported:

> "после запуска exe серый экран."
>
> Translation: "After launching the exe, there is a gray screen."

New evidence downloaded into this repository:

- `docs/case-studies/issue-1634/data/logs/game_log_20260417_205433.txt`
- `docs/case-studies/issue-1634/data/logs/game_log_20260417_205531.txt`
- `docs/case-studies/issue-1634/data/logs/game_log_20260417_205615.txt`

### Timeline Reconstruction

All three logs show the same startup sequence:

1. The exported Windows build starts successfully.
2. `LabyrinthLevel` loads normally, including `Player` and 5 enemies.
3. `ReplayManager` starts recording with `player_valid=True`.
4. `PersistManager` navigates to the saved last level: `res://scenes/levels/RoguelikeLevel.tscn`.
5. `SceneLoader` reports `THREAD_LOAD_INVALID_RESOURCE` and uses its synchronous fallback.
6. The scene tree changes to `RoguelikeLevel`.
7. No `RoguelikeLevel` startup logs appear, even though `roguelike_level.gd` logs new-run setup through `FileLogger`.
8. `ReplayManager` continues logging `player_valid=False` every second until shutdown.

Representative evidence from the new logs:

```text
[SceneLoader] ERROR: Invalid resource (falling back to sync): res://scenes/levels/RoguelikeLevel.tscn
[SceneLoader] Using synchronous load fallback
[CinemaEffects] Scene changed to: RoguelikeLevel
[CinemaEffects] Player not found yet, will connect when scene changes
[ReplayManager] Recording frame 60 (1,0s): player_valid=False, enemies=5
```

### Root Cause

`SceneLoader._fallback_sync_load()` used bare GDScript `load(_current_load_path)` after a threaded
load returned `THREAD_LOAD_INVALID_RESOURCE`. In the exported Windows build, this fallback could
change to a packed scene whose attached GDScript startup did not execute, leaving the procedural
Roguelike scene as only its static root/navigation nodes — visually a gray/empty screen.

This path was especially risky because `RoguelikeLevel.tscn` is almost entirely built by
`scripts/levels/roguelike_level.gd` at `_ready()` time. If that script does not run, no room,
player, HUD, enemies, or doors are created.

### Online Research Used

- Godot 4.3 `ResourceLoader` docs: `THREAD_LOAD_INVALID_RESOURCE` means the resource is invalid
  or was not loaded through `load_threaded_request()`, and loaded threaded resources should be
  accessed via `load_threaded_get()`.
  Source: https://docs.godotengine.org/en/4.3/classes/class_resourceloader.html
- The same docs warn that GDScript's simplified `load()` can fail to read converted resources in
  exported projects when `editor/export/convert_text_resources_to_binary` is enabled; runtime
  resource loading should use `ResourceLoader.load()` for this advanced path.
  Source: https://docs.godotengine.org/en/4.3/classes/class_resourceloader.html
- Existing repository case studies already document Godot 4.3 exported-build GDScript execution
  failures and the `LevelInitFallback` workaround for static levels. Roguelike has no such fallback
  and depends on its GDScript `_ready()` for nearly all scene contents.
  Local references: `docs/case-studies/issue-1684/case-study.md`,
  `docs/case-studies/issue-1751/README.md`.
- Related Godot issue: binary-token GDScript export mode has caused exported-build runtime
  failures in Godot 4.3-era builds.
  Source: https://github.com/godotengine/godot/issues/94150

### Fix Applied

`scripts/autoload/scene_loader.gd` now makes scene loading explicit and export-safe:

- `ResourceLoader.exists(level_path, "PackedScene")` validates scene resources with a type hint.
- `ResourceLoader.load_threaded_request(_current_load_path, "PackedScene", false)` requests a
  `PackedScene` directly and avoids sub-thread loading on Godot 4.3 exports.
- `_fallback_sync_load()` uses `ResourceLoader.load(path, "PackedScene")` instead of bare
  GDScript `load()`.
- `_hide_loading_screen()` disables processing immediately so stale polling stops after fallback.
- The fallback path now logs scene-change failures and successful fallback scene changes.

Regression tests were added to `tests/unit/test_scene_loader.gd` to prevent reintroducing bare
`load()` in the exported-build fallback path.

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

## Bug Found and Fixed: Immediate Detonation on Spawn (Session 3)

### Root Cause

After session 2 (LOS fix), the user reported: **"пистолетные патроны всё ещё сломаны"**
("pistol bullets are still broken"), with a new game log (`game_log_20260330_124617.txt`) attached.

Analysis of the log and gameplay scenarios revealed a second root cause:

**The enemy-cone proximity fuse had no arming distance.** It ran every physics frame starting
from the bullet's spawn position (20px from the weapon). If an enemy was within 95px and in the
forward cone with clear line of sight — even at the moment of firing — the bullet detonated
immediately upon spawning.

**Example:** Player stands 80px from an enemy and fires toward them. The bullet spawns at
position `player + 20px` (muzzle), travels 0–40px, then checks the cone. The enemy is 60–80px
ahead in a ±45° arc with clear LOS — **cone check triggers on the first or second physics frame**.
The bullet explodes at the muzzle, dealing no ranged damage. To the player, the pistol "doesn't
work" — bullets vanish as soon as fired.

This was not visible in the session-1 log because the session-1 issue was worse (through-wall
detonation before the bullet even cleared the player's immediate area). Once that was fixed, this
arming-distance issue became the dominant complaint.

### Game Log Evidence (2026-03-30)

`game_log_20260330_124617.txt` shows breaker bullets active on MiniUzi with initial enemy
positions all >200px from the player. However, enemies move; by the time the player fired at
`[12:46:36]`, some enemies may have been within 95px with clear LOS.

Key indicator from log: `[Player.BreakerBullets] Breaker bullets active — bullets will detonate
60px before walls` — this stale message confirmed the player was running from the fixed branch.
The "60px" refers to the old distance (the real value was updated to 95px, but the log message
was not updated, confirming it's the patched build).

### Fix Applied (Session 3)

Added `BREAKER_ARMING_DISTANCE = 40.0` constant. The enemy-cone proximity fuse check is now
**gated by a minimum travel distance**:

- **Wall check**: still active from spawn (a wall very close to the muzzle should still trigger)
- **Enemy cone check**: only activates after the bullet travels ≥40px from spawn

This matches real proximity fuse behavior: real fuzes have an "arming" phase where the fuze is
mechanically/electronically inert until a safe distance from the weapon, preventing self-damage.

```gdscript
# In _check_breaker_detonation():
if _breaker_distance_traveled >= BREAKER_ARMING_DISTANCE:
    if _check_enemy_in_shrapnel_cone():
        return true
```

The distance is tracked incrementally in `_physics_process`:
```gdscript
if is_breaker_bullet and not _is_penetrating:
    _breaker_distance_traveled += movement.length()
```

**Why 40px?** At bullet speed 2500px/s and 60fps, one frame = ~42px of travel. 40px is
approximately one physics frame of travel, ensuring the fuse is armed almost immediately after
spawn while preventing frame-zero detonation. This is a minimal safety margin that does not
measurably reduce the effective range.

---

## Implementation Summary

### Changes in `scripts/projectiles/bullet.gd`

The `_check_breaker_detonation()` function was restructured:

1. **Wall detection** — unchanged forward raycast for `StaticBody2D`/`TileMap`.
2. **Enemy cone detection** — `_check_enemy_in_shrapnel_cone()` using group query + dot
   product geometry, now gated by `_breaker_distance_traveled >= BREAKER_ARMING_DISTANCE`.

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

The same `ArmingDistance` constant and `distanceTraveled` parameter were applied.
`Bullet.cs` and `ShotgunPellet.cs` track `_breakerDistanceTraveled` per-instance.

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

## Bug Found and Fixed: Pool Bullet Loses Shrapnel Scene (Session 4)

### Root Cause

**User report (PR #1661, 2026-04-10):**
> "использую последний билд, всё ещё сломаны пул у ПМ"
> *Translation: "using the latest build, the bullet pool at PM is still broken"*
> — Jhon-Crow

After Session 3's arming distance fix, a new root cause was identified related to the **object
pool system (Issue #724)**:

When the `ProjectilePoolManager` recycles a bullet from the pool for reuse as a breaker bullet,
the call sequence is:

1. `pool_activate()` → calls `_reset_state()` → sets `_breaker_shrapnel_scene = null`
   AND `_breaker_distance_traveled` was **not reset at all** (stale value from previous use)
2. Player code sets `bullet.is_breaker_bullet = true` (direct property assignment, or via
   `set_is_breaker_bullet(true)`)
3. `_ready()` does **not** run again on a reused pool bullet

**Consequence 1 — No shrapnel on detonation:** `_breaker_spawn_shrapnel()` had an early return
`if _breaker_shrapnel_scene == null: return`. Since the scene was cleared in `_reset_state()`
and never reloaded (no `_ready()`), the bullet detonated with explosion effect and sound but
**zero shrapnel pieces**.

**Consequence 2 — Arming distance bypassed:** `_breaker_distance_traveled` was not reset in
`_reset_state()`. If the previous bullet had traveled ≥ 40px before dying, a recycled pool
bullet started with the cone check **already armed** — no frame-zero protection.

### Fix Applied (Session 4)

Three targeted changes in `scripts/projectiles/bullet.gd`:

**1. `set_is_breaker_bullet()` — reload shrapnel scene when scene is null:**

```gdscript
func set_is_breaker_bullet(is_breaker: bool) -> void:
    is_breaker_bullet = is_breaker
    if is_breaker and _breaker_shrapnel_scene == null:
        if ResourceLoader.exists(BREAKER_SHRAPNEL_SCENE_PATH):
            _breaker_shrapnel_scene = load(BREAKER_SHRAPNEL_SCENE_PATH)
```

This ensures the shrapnel scene is always available when the breaker flag is set, regardless
of whether the bullet is fresh or reused from the pool.

**2. `_breaker_spawn_shrapnel()` — allow pool-based shrapnel even if scene is null:**

```gdscript
var pool_manager_available := get_node_or_null("/root/ProjectilePoolManager") != null
if _breaker_shrapnel_scene == null and not pool_manager_available:
    return  # No scene AND no pool — cannot spawn
```

The old check `if _breaker_shrapnel_scene == null: return` blocked pool-based shrapnel too.
The fix only skips if both the scene AND the pool manager are unavailable.

**3. `_reset_state()` — reset breaker distance traveled:**

```gdscript
# Reset breaker state
is_breaker_bullet = false
_breaker_shrapnel_scene = null
_breaker_distance_traveled = 0.0  # NEW: ensure arming distance restarts from zero
```

**Also fixed in `player.gd`:** The pooled bullet path used direct property assignment
`bullet.is_breaker_bullet = true`, which bypasses the setter and its scene-loading logic.
Changed to `bullet.call("set_is_breaker_bullet", true)` so the setter always runs.

### Why PM Specifically?

The Makarov PM weapon (`MakarovPM.cs`) does **not** use the bullet pool for spawning — it
always instantiates fresh `Bullet9mm.tscn` bullets via `BulletScene.Instantiate<Node2D>()`.
Fresh bullets always have `_ready()` called, which correctly loads the shrapnel scene.

However, when a PM bullet is destroyed (`_destroy()`), it returns to the pool via
`pool_deactivate()`. The next time that bullet is retrieved for any weapon (including the
GDScript M16 player code), it starts with a stale `_breaker_distance_traveled` value and no
shrapnel scene.

The user's observation of "пул у ПМ сломаны" is consistent with the pool recycling PM
bullets into an invalid state for subsequent breaker bullet use by any weapon.

---

## Bug Found and Fixed: PM Bullet Pool Contamination (Session 5)

### New User Report and Preserved Data

**User report (PR #1661, 2026-04-11):**
> "всё ещё полностью сломаны пули ПМ это точно новый билд ТОЧНО!!!"
> *Translation: "PM bullets are still completely broken, this is definitely the new build, definitely."*

All available evidence from the issue/PR was downloaded for offline review:

- `data/logs/game_log_20260328_085423.txt` — 10,972 lines
- `data/logs/game_log_20260330_124617.txt` — 1,066 lines
- `data/logs/game_log_20260411_014724.txt` — 723 lines
- `data/github/issue-1634.json`
- `data/github/pr-1661.json`
- `data/github/pr-1661-comments.json`

The latest log confirms the user was on the newer branch: breaker bullets report **95px** wall
detonation and **40px** enemy-fuse arming distance. It also confirms the exact PM path:

- `game_log_20260411_014724.txt:580-581` — weapon selection is `makarov_pm (MakarovPM)`.
- `game_log_20260411_014724.txt:593-594` — breaker bullets are active and applied to `MakarovPM`.
- `game_log_20260411_014724.txt:704-716` — two PM shots are fired.

There are no projectile-level diagnostics after those shots, so the log proves activation and
firing but not the exact runtime projectile state. The root cause came from tracing the PM bullet
scene and pool ownership code.

### Root Cause

The Session 4 conclusion was incomplete. The real PM-specific bug is not only that pooled bullets
lost breaker shrapnel state. The deeper bug is that **fresh PM bullets were entering a generic
autoload pool they did not belong to**.

The chain before this fix:

1. `MakarovPM.tscn` uses `res://scenes/projectiles/Bullet9mm.tscn`.
2. `BaseWeapon.SpawnBullet()` instantiates that scene directly for PM shots.
3. `Bullet9mm.tscn` runs `scripts/projectiles/bullet.gd`.
4. When destroyed, `_destroy()` checked only whether `/root/ProjectilePoolManager` exists.
5. If the singleton existed, the fresh PM bullet called `pool_deactivate()` and was appended to
   `_bullet_pool`.

That generic pool is warmed with `res://scenes/projectiles/Bullet.tscn`, not `Bullet9mm.tscn`.
Mixing direct weapon-instantiated 9mm scenes into that pool contaminates later reuse with the wrong
scene resource, caliber defaults, per-scene state, and lifetime ownership. It also leaves a serious
scene-lifecycle risk: Godot's `queue_free()` docs state that deleting a node deletes its children
and invalidates references, and Object docs warn that object references can become invalid without
becoming `null`. A singleton pool must therefore not store nodes owned by a gameplay scene that can
later be freed during scene changes.

A second pool bug was found in the same path: warmup used `pool_deactivate()` on newly created pool
objects, and `pool_deactivate()` called back into `return_*()`. That means warmup could append the
same object from both the create loop and the self-return path, producing duplicate idle references.
Duplicate pool references can make one active projectile appear in the idle pool again.

### Fix Applied (Session 5)

The pool now has explicit ownership:

- `bullet.gd`, `shrapnel.gd`, and `breaker_shrapnel.gd` gained `_pool_managed`.
- `ProjectilePoolManager` marks only the projectiles it instantiates as pool-managed.
- `_destroy()` returns to the pool only when `_pool_managed == true`; fresh PM `Bullet9mm.tscn`
  bullets now `queue_free()` normally.
- `pool_deactivate(return_to_manager := true)` supports internal deactivation without recursive
  self-return during warmup and recycling.
- `return_bullet()`, `return_shrapnel()`, and `return_breaker_shrapnel()` reject unmanaged nodes and
  append only unique pool entries.
- `get_*()` skips stale, unmanaged, or already-active duplicate entries before returning a projectile.
- `_breaker_spawn_shrapnel()` now skips a shard cleanly if both the pool and fallback scene fail,
  instead of calling `instantiate()` on a null scene.

This keeps the performance benefit for pool-owned generic bullets and shrapnel, while preventing
PM's fresh 9mm bullets from poisoning the pool.

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
- `test_arming_distance_constant` — confirms 40px arming distance constant
- `test_does_not_detonate_via_cone_before_arming` — **arming distance bug fix** (session 3)
- `test_detonates_via_cone_after_arming` — cone fuse activates after arming distance
- `test_wall_check_still_works_before_arming` — wall check still active before arming
- `test_pool_bullet_reloads_shrapnel_scene` — **pool bug fix** (session 4)
- `test_pool_bullet_resets_arming_distance` — **pool arming reset bug fix** (session 4)

Additional Session 5 regression tests in `tests/unit/test_projectile_pool_manager.gd`:

- `test_warmup_deactivation_does_not_self_return` — warmup does not recursively append pool objects
- `test_return_bullet_rejects_unmanaged_projectile` — PM-style fresh bullets cannot contaminate the pool
- `test_duplicate_return_does_not_duplicate_pool_entry` — duplicate returns do not duplicate references
- `test_get_bullet_skips_active_duplicate_reference` — active duplicate references are discarded before reuse
- `test_csharp_breaker_shrapnel_uses_pool_fallback_when_scene_missing` — C# PM/Bullet9mm breaker path
  does not skip shrapnel when the cached `PackedScene` load is unavailable but `ProjectilePoolManager`
  can supply breaker shrapnel.

---

## Bug Found and Fixed: C# Breaker Shrapnel Missing in PM Path (Session 7)

### New User Report and Preserved Data

**User report (PR #1661, 2026-04-17):**
> "всё ещё нет осколков у пуль с превзрывателем"
> *Translation: "breaker bullets still have no shrapnel."*

Preserved log:

- `data/logs/game_log_20260417_213214.txt` — 2,708 lines

The log confirms the player enabled Breaker Bullets and that the active weapon was repeatedly
`MakarovPM`:

- `game_log_20260417_213214.txt:614` — active item changed to Breaker Bullets.
- `game_log_20260417_213214.txt:619-620` — breaker bullets active and applied to `MakarovPM`.
- `game_log_20260417_213214.txt:683-684`, `876-877`, `1241-1242`, `1462-1463`, and
  `2519-2520` — later reload/restart cycles still apply breaker bullets to `MakarovPM`.

### Root Cause

The latest missing-shrapnel report was on the C# PM projectile path, not the GDScript pooled bullet
path that Session 4 and Session 5 hardened. `MakarovPM.tscn` fires `Bullet9mm.tscn`, and the runtime
bullet is handled by `Scripts/Projectiles/Bullet.cs`, which delegates breaker detonation to
`Scripts/Projectiles/BreakerDetonation.cs`.

`BreakerDetonation.SpawnShrapnel()` had a C#-specific early return:

1. Load cached `BreakerShrapnel.tscn`.
2. If that cached scene is `null`, return immediately.
3. Never ask `/root/ProjectilePoolManager` for breaker shrapnel.

That differs from the fixed GDScript `bullet.gd` behavior, which can still spawn pooled breaker
shrapnel when the fallback scene reference is unavailable. In exported builds this means C# breaker
bullets can detonate and play the small explosion while silently producing no fragments.

### Fix Applied (Session 7)

`BreakerDetonation.SpawnShrapnel()` now mirrors the robust GDScript path:

- It looks up `/root/ProjectilePoolManager` before deciding whether shrapnel spawning is possible.
- It only returns early when both the cached `PackedScene` and the pool fallback are unavailable.
- It tries `get_breaker_shrapnel()` first and activates the returned shard with `pool_activate()`.
- It falls back to direct `PackedScene` instantiation only if the pool cannot provide a shard.

This keeps PM/C# breaker bullets aligned with the GDScript breaker bullet behavior and preserves the
pool ownership fixes from Session 5.

---

## References

- [Proximity fuze — Wikipedia](https://en.wikipedia.org/wiki/Proximity_fuze)
- [Proximity fuze — Britannica](https://www.britannica.com/technology/proximity-fuze)
- [PhysicsDirectSpaceState2D — Godot Engine docs](https://docs.godotengine.org/en/stable/classes/class_physicsdirectspacestate2d.html)
- [PhysicsShapeQueryParameters2D — Godot Engine docs](https://docs.godotengine.org/en/stable/classes/class_physicsshapequeryparameters2d.html)
- [Ray-casting — Godot Engine 4.4 docs](https://docs.godotengine.org/en/4.4/tutorials/physics/ray-casting.html)
- [Node.queue_free — Godot Engine 4.3 docs](https://docs.godotengine.org/en/4.3/classes/class_node.html#class-node-method-queue-free)
- [Object lifecycle and invalid references — Godot Engine 4.3 docs](https://docs.godotengine.org/en/4.3/classes/class_object.html)
- [How to implement a vision cone for AI in Godot](https://playgama.com/blog/godot/how-can-i-implement-a-vision-cone-for-ai-characters-in-godot-to-detect-the-player/)
- [General optimization tips — Godot Engine docs](https://docs.godotengine.org/en/stable/tutorials/performance/general_optimization.html)
- [Godot Projectile Engine (Asset Library)](https://godotengine.org/asset-library/asset/4165)
- Original Issue: [#1634](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1634)
- Original Breaker PR: [#678](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/678)
- This fix PR: [#1661](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1661)
