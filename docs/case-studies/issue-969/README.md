# Case Study: Issue #969 — FPS Drop During Shootout

## Summary

FPS drops to 5–9 fps during active shooting with MiniUzi weapon. Blood effects and grenade
explosions are explicitly excluded from scope. The issue is reproducible and confirmed by three
game session logs provided by the reporter.

## Logs Analyzed

### Before Fix (Original Reports)

| Log file | Duration | FPS drops | Worst FPS | Enemies |
|---|---|---|---|---|
| game_log_20260305_233837.txt | ~2.7 min | 13 | 9 fps | 10 |
| game_log_20260305_233927.txt | ~2.4 min | 35 | 5 fps | 10 |
| game_log_20260305_234058.txt | ~2.4 min | 18 | 24 fps | 10 |

**Common setup**: MiniUzi (32/32 ammo), 10 enemy listeners, Hard difficulty, FPS counter + drop logging enabled.

### After Fix (Verification Log — 2026-03-07)

| Log file | Duration | FPS drops | Worst FPS | Enemies (section) |
|---|---|---|---|---|
| game_log_20260307_203841.txt | ~2 min | 1 (29fps) | **29 fps** | 10 enemies (20:38:42–20:39:03) |
| game_log_20260307_203841.txt | ~30 s | 16 | 4 fps | 20 enemies (20:39:03–20:39:33) |

**Key finding**: With the initial fix (debug logging + CASING_KICK throttle) applied, the **10-enemy
scenario is resolved** — only 1 borderline drop at 29 fps (vs 5–9 fps before). The 20-enemy scenario
still showed severe drops because of a **newly identified root cause (RCA-6)**: enemy AI gunshot
propagation flooding with many enemies active.

## Root Causes Found

### RCA-1 (Critical): `_debug_penetration = true` by default in `bullet.gd`

**File:** `scripts/projectiles/bullet.gd`, line 103
**Severity:** High — every bullet wall hit triggers `_log_penetration()` which:
- Calls `print()` (console I/O)
- Calls `FileLogger.log_info()` (file I/O)

**Evidence from logs:**
```
[Bullet] _get_distance_to_shooter: shooter_position=..., bullet_pos=..., distance=98.99
[Bullet] Using shooter_position, distance=98.99
[Bullet] Distance to wall: 98.99 (6.74% of viewport)
[Bullet] Within ricochet range - trying ricochet first
[Bullet] Caliber cannot penetrate walls
```

The game logs show **493–1,262 `_get_distance_to_shooter` entries per session**. Each wall hit
from each bullet produces 4–6 log lines. With MiniUzi at high fire rate, this generates
continuous file I/O flooding during combat.

The `_log_penetration()` function writes to FileLogger even when `_debug_penetration = false`,
because the function only checks the flag before printing, but the FileLogger call is inside the
same conditional — however, the **default value is `true`**, so all logging is active.

### RCA-2 (High): CASING_KICK sound propagated to all enemies per shot

**File:** `scripts/effects/casing.gd`, lines 271–286
**File:** `scripts/autoload/sound_propagation.gd`, lines 130–194

Each bullet fired spawns a casing (RigidBody2D). When the casing lands (`_land()` called via
`body_entered` or auto-land timer), it calls `_play_landing_sound()` → `_play_kick_sound()`.
Furthermore, when the player walks over landed casings, each kick triggers `emit_casing_kick()`
which iterates **all registered enemy listeners** computing distance + intensity.

**Evidence from logs:**
```
[23:38:55] CASING_KICK emitted: type=CASING_KICK, range=900, listeners=10
Enemy1 Heard CASING_KICK (intensity=0.89, dist=103)
Enemy2 Heard CASING_KICK (intensity=0.93, dist=74)
...×10 enemies
```

Log2 shows **3,193 CASING_KICK entries** in a 2.4 minute session with MiniUzi. Each call
iterates all 10 listeners, computing distance. That is **~31,930 distance calculations** from
casing sounds alone.

### RCA-3 (Medium): Casings instantiated per shot (not pooled)

**File:** `Scripts/AbstractClasses/BaseWeapon.cs`, line 598
```csharp
var casing = CasingScene.Instantiate<RigidBody2D>();
```

Each weapon shot calls `CasingScene.Instantiate()`, which allocates a new `RigidBody2D` node
and adds it to the scene tree. With high-fire-rate weapons like MiniUzi, this creates many
nodes per second. Despite `ProjectilePoolManager` existing for bullets/shrapnel, casings were
not included in pooling.

**Evidence:** 3,193 CASING_KICK events in log2 implies ~3,000+ casing objects were created in
one session. Each RigidBody2D runs physics simulation until landed.

### RCA-4 (Medium): Double raycast every frame during wall penetration

**File:** `scripts/projectiles/bullet.gd`, lines 943–981
The `_is_still_inside_obstacle()` function fires **two raycasts** every physics frame while a
bullet is penetrating a wall. At 60 FPS with multiple bullets penetrating simultaneously, this
compounds quickly.

### RCA-5 (Lower): `get_overlapping_areas()` on every wall hit

**File:** `scripts/projectiles/bullet.gd`, lines 866–879
`_is_inside_penetration_hole()` calls `get_overlapping_areas()` on every `_on_body_entered`
event, even when not near any penetration hole. This can be expensive in dense scenes.

### RCA-6 (High, newly discovered): Enemy GUNSHOT propagation flooding with 20+ enemies

**File:** `scripts/objects/enemy.gd`, lines 2402, 2462, 3843
**Severity:** High — when multiple high-fire-rate enemies are present, each shot propagates
to ALL registered listeners (other enemies + player), creating O(enemies²) distance calculations.

**Evidence from verification log (game_log_20260307_203841.txt):**
```
[20:39:07] Sound emitted: GUNSHOT, listeners=19
[20:39:08] Sound emitted: GUNSHOT, listeners=19   ← 48 gunshots at 20:39:08
... (48 enemy gunshot events in 1 second × 19 listeners = 912 distance calculations)
```

During the 20-enemy section (20:39:03–20:39:33):
- **526 enemy gunshot events** in 30 seconds (17.5/second average)
- **WarehouseA_UZI2 alone fired 13 shots/second** (high-fire-rate enemy weapon)
- At 19 listeners: **526 × 19 = ~9,994 distance calculations** from enemy shots alone
- Enemy AI reaction to ENEMY gunshots only triggers for IDLE enemies; all others skip it
  — meaning the vast majority of these calculations result in no action at all

Compounding factor: Blood decal deferred spawning creates burst events when many particles
land simultaneously (72 blood decals in one second at 20:39:10), accounting for the worst drops.

## Quantitative Impact

### Before Fix (original log2 — 10 enemies)

| Issue | Events/session | Cost per event | Total impact |
|---|---|---|---|
| Debug logging per wall hit | ~1,262 | file I/O + print | Very High |
| CASING_KICK propagation | 3,193 | 10× distance calc | High |
| Casing instantiation | ~3,000+ | Node alloc + physics | Medium |
| Penetration raycasts | varies | 2× raycast/frame | Medium |

### After Initial Fix (verification log — 10 enemies section)

| Issue | Events/session | Reduction |
|---|---|---|
| Debug penetration logging | **0** (was 1,262) | **100%** eliminated |
| CASING_KICK propagation | **99** (was 3,193) | **97%** reduction |
| Enemy GUNSHOT propagation | still high (640+ events) | not yet fixed |

**Result with 10 enemies**: Worst FPS drop was 29 fps (vs 5–9 fps before) — essentially fixed.

### After Full Fix (adding per-enemy gunshot cooldown)

| Issue | Events expected | Reduction |
|---|---|---|
| Enemy GUNSHOT propagation | ~60 per 30s (from 526) | **~89%** reduction |
| Distance calculations from enemy shots | ~1,140 (from ~10,000) | ~89% |

## Solutions Implemented

### Fix 1: Set `_debug_penetration = false` by default

Changed `_debug_penetration: bool = true` to `_debug_penetration: bool = false` in
`scripts/projectiles/bullet.gd`.

This is the highest-impact fix. Debug logging is appropriate during development but must be off
by default in gameplay. The flag already existed; only the default value was wrong.

**Expected improvement:** Elimination of hundreds of print/file-write calls per second during
combat.

### Fix 2: Add casing landing sound throttle to prevent CASING_KICK spam

The `_play_kick_sound()` in `casing.gd` propagates `CASING_KICK` to all enemies. This is
called on every casing landing. For high-fire-rate weapons, casings land in rapid succession.

We add a minimum time between `emit_casing_kick()` calls using a per-casing cooldown. Since
enemies already react to the gunshot sound, the casing kick sound is a supplementary alert;
throttling it at 200ms intervals retains the gameplay mechanic while eliminating the flood.

Additionally, we cap casing instantiation with a per-weapon casing count limit to prevent
RigidBody2D node accumulation.

### Fix 3: Pool casings using `ProjectilePoolManager` pattern

Extended the `ProjectilePoolManager` to include a casing pool, so casing nodes are reused
rather than created and destroyed each shot.

### Fix 4 (new, from verification): Per-enemy GUNSHOT propagation cooldown

**File:** `scripts/objects/enemy.gd`

Added `ENEMY_GUNSHOT_PROPAGATION_COOLDOWN = 0.5s` per-enemy constant and
`_last_gunshot_propagation_time` tracking variable. Each of the three enemy shoot functions
(`_shoot_with_inaccuracy`, `_shoot_burst_shot`, `_execute_shoot`) now checks the cooldown
before calling `sound_propagation.emit_sound()`.

**Rationale:**
- Idle enemies only need one alert per ~0.5s to transition to COMBAT (they're already alert after first shot)
- Non-idle enemies (COMBAT, PURSUING, RETREATING, etc.) ignore enemy gunshot sounds entirely per the
  existing `should_react` logic in `on_sound_heard_with_intensity()` — so all their propagation was wasted
- Each enemy has an independent cooldown, so different enemies still alert properly; only
  rapid burst-fire from a single enemy is throttled

**Expected reduction:** WarehouseA_UZI2 firing 13 shots/sec → propagates 1 per 0.5s = 2/sec
(vs 13/sec before). With 5 firing enemies, total sound propagation drops from ~270/sec to ~10/sec.

## References

- [Godot 4 General Optimization Tips](https://docs.godotengine.org/en/stable/tutorials/performance/general_optimization.html)
- [Godot 4 Object Pooling Guide](https://uhiyama-lab.com/en/notes/godot/godot-object-pooling-basics/)
- [Debug logging performance impact — Godot proposals #14370](https://github.com/godotengine/godot-proposals/issues/14370)
- [Sound propagation batching — Godot Forum](https://forum.godotengine.org/t/spatialised-audio-system-in-godot-with-support-for-occlusion-and-propagation/40824)
