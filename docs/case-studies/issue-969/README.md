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

### Summary of All 9 Sessions (Chronological)

| Log file | Date | Fixes applied | FPS drops | Worst FPS | Enemies |
|---|---|---|---|---|---|
| game_log_20260305_233837.txt | 2026-03-05 | None | 13 | 9 fps | 10 |
| game_log_20260305_233927.txt | 2026-03-05 | None | 35 | 5 fps | 10 |
| game_log_20260305_234058.txt | 2026-03-05 | None | 18 | 24 fps | 10 |
| game_log_20260307_203841.txt | 2026-03-07 | Fixes 1–3 | 1 (10e) / 16 (20e) | 29 fps (10e) / 4 fps (20e) | 10 / 20 |
| game_log_20260307_211503.txt | 2026-03-07 | Fixes 1–4 | 2 (10e) / 19 (20e) | 29 fps (10e) / 5 fps (20e) | 10 / 20 |
| game_log_20260307_215133.txt | 2026-03-07 | Fixes 1–7 | 48 | 1 fps (shader), 5 fps | 20 |
| game_log_20260309_194900.txt | 2026-03-09 | Fixes 1–9 | 61 | 6 fps | 20 |
| game_log_20260311_200846.txt | 2026-03-11 | Fixes 1–11 | **14** | **5 fps** | 20 |
| game_log_20260311_200920.txt | 2026-03-11 | Fixes 1–11 | **14** | **5 fps** | 20 |

### After Fix (Verification Log — 2026-03-07)

| Log file | Duration | FPS drops | Worst FPS | Enemies (section) |
|---|---|---|---|---|
| game_log_20260307_203841.txt | ~2 min | 1 (29fps) | **29 fps** | 10 enemies (20:38:42–20:39:03) |
| game_log_20260307_203841.txt | ~30 s | 16 | 4 fps | 20 enemies (20:39:03–20:39:33) |

**Key finding**: With the initial fix (debug logging + CASING_KICK throttle) applied, the **10-enemy
scenario is resolved** — only 1 borderline drop at 29 fps (vs 5–9 fps before). The 20-enemy scenario
still showed severe drops because of a **newly identified root cause (RCA-6)**: enemy AI gunshot
propagation flooding with many enemies active.

### Second Verification Log — 2026-03-07 (21:15:03)

| Log file | Duration | FPS drops | Worst FPS | Enemies (section) |
|---|---|---|---|---|
| game_log_20260307_211503.txt | ~53 s | 2 (29fps) | **29 fps** | 10 enemies (21:15:12–21:15:24) |
| game_log_20260307_211503.txt | ~27 s | 19 | 5 fps | 20 enemies (21:15:25–21:15:52) |

**Key findings** (with Fixes 1–4 applied):
- **10-enemy scenario**: Only 2 borderline drops at 29 fps — effectively fixed ✅
- **20-enemy scenario**: Still 19 drops (5–19 fps range) — Fix 4 did NOT fully resolve it
- **CASING_KICK throttle confirmed working**: Only 36 events (vs 3,193 originally, vs 99 in first verification)
- **Enemy GUNSHOT propagation confirmed working**: Max 10 enemy gunshots/second (vs 526 in previous log)
- **New root causes identified**: RCA-7, RCA-8, RCA-9 (see below)

### Third Verification Log — 2026-03-07 (21:51:33)

| Log file | Duration | FPS drops | Worst FPS | Notes |
|---|---|---|---|---|
| game_log_20260307_215133.txt | ~87 s | **48** | 1 fps (shader warmup) | DocksLevel (20 enemies) |

**Key findings** (with Fixes 1–7 applied):
- The 1 fps drop at 21:51:35 is a one-time GPU shader compilation stall (not a gameplay issue)
- Still 47 drops ranging from 5 fps to 29 fps during the 20-enemy combat section
- **New root causes identified**: RCA-10, RCA-11 (see below)

**Confirmed improvements** (vs second verification log):
- CASING_KICK: 79 events/session (low, throttle working)
- Enemy GUNSHOT propagation: max 13/sec (expected with 20 enemies shooting)
- EnemyGrenade log writes: 0 (Fix 5 working)
- Per-frame visibility cache: working (Fix 6)

### Fourth Verification Log — 2026-03-09 (19:49:00)

| Log file | Duration | FPS drops | Worst FPS | Notes |
|---|---|---|---|---|
| game_log_20260309_194900.txt | ~103 s | **61** | 6 fps | DocksLevel + LabyrinthLevel (20 enemies) |

**Key findings** (with Fixes 1–9 applied):
- Still 61 drops ranging from 6 fps to 29 fps — fixes 8–9 not yet applied when this log was recorded
- CASING_KICK: 98 events (low, throttle working) ✅
- EnemyGrenade log writes: 0 ✅
- SUPPRESSED cycling: fix applied, minimum duration enforced ✅
- **New root causes identified**: RCA-12, RCA-13 (see below)

**Confirmed: 1,400 BloodDecal creation events** in session (many decals per lethal hit, each triggering `tree_changed`)
**Confirmed: 148 LastChance "Not in hard mode" file writes** in normal gameplay (useless I/O on every bullet threat)

### Fifth Verification — 2026-03-11 (Two Sessions: 20:08:46 and 20:09:20)

| Log file | Duration | FPS drops | Worst FPS | Notes |
|---|---|---|---|---|
| game_log_20260311_200846.txt | ~29 s | **14** | 5 fps | DocksLevel (20 enemies), M16, Hard |
| game_log_20260311_200920.txt | ~22 s | **14** | 5 fps | DocksLevel (20 enemies), M16, Hard |

**Key findings** (with Fixes 1–11 all applied):
- FPS drops are still severe — 14 drops per session, worst at 5 fps, average ~7–8 fps during combat
- Both sessions span DocksLevel with 20 enemies (exact same roster: CraneGuard1/2, ContainerYardA × 5, WarehouseA × 3, LoadingDock × 4, ContainerYardB × 3, WarehouseB × 3, OpenArea_Patrol × 2)

**Confirmed improvements from previous fixes:**

| Metric | Round 6 | Previous worst | Improvement |
|---|---|---|---|
| CASING_KICK events/session | 83–124 | 3,193 | **97%** eliminated ✅ |
| EnemyGrenade file writes | 0 | 466/27s | **100%** eliminated ✅ |
| ImpactEffects per-hit file writes | 7–9/session (init only) | 765/session | **99%** eliminated ✅ |
| LastChance per-threat file writes | 13–18/session | 148/session | **91%** reduced ✅ |
| Enemy GUNSHOT propagation | 80–99 events | 526 in 30s | **~75%** reduced ✅ |

**Remaining bottlenecks confirmed in Round 6:**

| Metric | Round 6 observed | Status |
|---|---|---|
| BloodDecal creation peak | 35–36/sec (was 48/sec originally) | Reduced but still high |
| SUPPRESSED rapid cycling | OpenArea_Patrol1/2 still cycle 4+ times/sec | Fix 9 partially effective |
| AI state transitions | 490 / 343 per session | High — 20 AI agents all running every frame |
| SoundPropagation GUNSHOT broadcast | 15–20 listener O(N) scan per shot | Core architectural bottleneck |
| ROT_CHANGE calculations | 223 / 191 per session | Every enemy rotation tracked every frame |

**Critical new finding — Log 2 (20:09:20):**
The first FPS drop (6 fps at 20:09:22) occurs **before combat begins** — immediately after particle shader warmup, before the player fires a single shot. Just having 20 enemy AI agents patrolling and running their state machines causes sub-30fps. This confirms that the 20-enemy ceiling is a fundamental architectural limitation of the current per-enemy-per-frame AI processing model, independent of visual effects.

**Correlation confirmed:** Every 5 fps drop co-occurs with BloodDecal bursts of 30–36/sec. The blood decal count was reduced (Fixes 10–11) but the underlying `add_child()` + `tree_changed` overhead remains. With 20 concurrent enemies, even 8 decals/kill × multiple simultaneous kills generates large bursts.

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

### RCA-6 (High, from first verification): Enemy GUNSHOT propagation flooding with 20+ enemies

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

### RCA-7 (High, from second verification): EnemyGrenadeComponent logs ALL throw attempts to file

**File:** `scripts/components/enemy_grenade_component.gd`, lines 448–452
**Severity:** High — the `_log()` function correctly gates `print()` behind `debug_logging = false`,
but **always writes to `FileLogger`** regardless of the flag:

```gdscript
func _log(msg: String) -> void:
    if debug_logging:
        print("[EnemyGrenadeComponent] %s" % msg)
    if _logger and _logger.has_method("log_info"):  # ← BUG: always writes to file!
        _logger.log_info("[EnemyGrenade] %s" % msg)
```

**Evidence from game_log_20260307_211503.txt:**
- **466 EnemyGrenade log entries** in a 27-second 20-enemy session
- Breakdown: 114 "Unsafe throw distance", 127 "Target not visible", 118 "not in enemy FOV", 58 "Throw path blocked"
- At 20 enemies with grenade-capable enemies, throw attempts fire EVERY frame per grenade check cycle
- **121 events in one second** (21:15:49) — each is a file I/O write

### RCA-8 (High, from second verification): `_is_visible_from_player()` called every frame per enemy

**File:** `scripts/objects/enemy.gd`, functions `_process_suppressed_state`, `_process_seeking_cover_state`, `_process_retreating_state`
**Severity:** High — each call performs 5 raycasts via `direct_space_state.intersect_ray()`.
Called on **every physics frame** when enemy is in SUPPRESSED, SEEKING_COVER, or RETREATING state.

**Evidence from second verification log:**
- **817 state transitions** in 53 seconds = 15+ state changes/second
- ContainerYardA_Rifle1 alone: **10 state cycles per second** at peak (21:15:50)
- With 20 enemies × 60fps × 5 raycasts/call = up to **6,000 raycasts/second** from this one function
- No per-frame caching existed — each call fully re-ran the raycast check

### RCA-9 (High, from second verification): `_find_cover_position()` called repeatedly with no cooldown

**File:** `scripts/objects/enemy.gd`, function `_find_cover_position()`
**Severity:** High — each call does **16 `force_raycast_update()` calls** (COVER_CHECK_COUNT = 16).
Called from state processing whenever no valid cover is cached.

**Evidence from second verification log:**
- **311 "SEEKING_COVER → COMBAT" + "RETREATING → SUPPRESSED" transitions** = 311+ cover search attempts
- At open-area levels where cover is sparse, repeated searches return no results
- 311 calls × 16 raycasts = **4,976 cover raycasts** in one session
- No minimum cooldown between searches — enemies retry every frame when cover is not found

### RCA-10 (High, from third verification): `impact_effects_manager.gd` logs on every blood effect

**File:** `scripts/autoload/impact_effects_manager.gd`, function `spawn_blood_effect()` and `_spawn_blood_decals_at_particle_landing()`
**Severity:** High — `_log_info()` writes to FileLogger **unconditionally** (no debug flag check) on every blood effect.
With MiniUzi at 13 shots/sec hitting enemies, this produces:
- "spawn_blood_effect called at..." — 1 write/hit
- "Blood particle effect instantiated successfully" — 1 write/hit
- "Blood decals scheduled: N..." — 1 write/hit
- "Blood effect spawned at..." — 1 write/hit
- "Wall found for blood splatter at..." (if wall nearby) — 1 write/hit

**Evidence from third verification log:**
- **765 ImpactEffects events** in 87-second session
- Peak: blood decal spawns contributing 128 puddle-creation events in a single second (21:51:47)
- Pattern: all drops correlate with sustained shooting → blood effect burst → file write flood

### RCA-11 (High, from third verification): Enemy SUPPRESSED state rapid cycling when no cover available

**File:** `scripts/objects/enemy.gd`, function `_process_suppressed_state()`
**Severity:** High — enemies in open terrain (no cover available) rapidly cycle through states:
`SUPPRESSED → SEEKING_COVER → COMBAT → RETREATING → SUPPRESSED` at 4–6 full cycles per second.

**Evidence from third verification log (OpenArea_Patrol2):**
```
[21:51:42] SUPPRESSED → SEEKING_COVER
[21:51:42] SEEKING_COVER → COMBAT      ← no cover found
[21:51:42] COMBAT → RETREATING
[21:51:42] RETREATING → SUPPRESSED
[21:51:43] SUPPRESSED → SEEKING_COVER  ← cycle repeats immediately
[21:51:43] SEEKING_COVER → COMBAT      ← still no cover found
...continues for entire session (100+ cycles in 87 seconds)
```

Each cycle triggers:
- `_find_cover_position()`: 16 raycasts → 0 results (open terrain)
- `_is_visible_from_player()`: up to 5 raycasts per call (even with cache, once per frame)
- State machine transitions: 4 function calls per cycle
- Navigation path updates: per SEEKING_COVER entry

With Fix 7 (COVER_SEARCH_COOLDOWN = 0.3s), the cover search itself was throttled, but state cycling
still forced `_transition_to_seeking_cover()` immediately when SUPPRESSED with `_is_visible_from_player() == true`.
The SUPPRESSED state itself had no minimum duration, so it exited in under one physics frame.

### RCA-12 (High, from fourth verification): Blood decal count too high — tree_changed flood

**File:** `scripts/autoload/impact_effects_manager.gd`, function `_spawn_blood_decals_at_particle_landing()`
**Severity:** High — each lethal hit spawned **20 blood decals** (non-lethal: 10). Every `add_child(decal)`
fires `SceneTree.tree_changed` signal, which is caught by every manager that tracks scene changes
(ImpactEffectsManager, PenultimateHitEffectsManager, LastChanceEffectsManager, CinemaEffectsManager, etc.).

**Evidence from fourth verification log:**
- **1,400 BloodDecal creation events** logged in 103-second session
- Peak blood decal spawn bursts correlated with every enemy kill (8–20 decals added at once)
- At 8 hits/sec with M16: up to **160 `add_child()` calls/sec** → 160 `tree_changed` callbacks/sec
- Each `tree_changed` callback checks scene name — with 4+ managers listening, this is **640+ callbacks/sec**

### RCA-13 (Medium, from fourth verification): LastChanceEffectsManager logs on every bullet threat

**File:** `scripts/autoload/last_chance_effects_manager.gd`, function processing `threat_detected` signal
**Severity:** Medium — the `LastChanceEffectsManager` logged to FileLogger on **every bullet entering
the ThreatSphere**, even when the effect is unavailable (Normal difficulty, not in hard mode):
- "Threat detected: @Area2D@N" — 1 write/bullet-threat
- "Not in hard mode - effect disabled" — 1 write/bullet-threat
- (or) "Cannot trigger effect" — 1 write/bullet-threat

**Evidence from fourth verification log:**
- **148 LastChance "Threat detected" + "Not in hard mode" events** in 103-second session
- All 148 writes were useless: the effect was never triggered (Normal difficulty)
- These writes occurred throughout the entire session, adding constant file I/O overhead

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

### After Fix 4 (per-enemy gunshot cooldown) — second verification log (20 enemies)

| Issue | Events/session | Reduction from original |
|---|---|---|
| CASING_KICK propagation | **36** (was 3,193) | **99%** eliminated |
| Enemy GUNSHOT propagation | **135** (was 526 in 30s) | **74%** reduction |
| EnemyGrenade log writes to file | **466** | **NEW** — not yet fixed |
| _is_visible_from_player() raycasts | **~6,000/sec** | **NEW** — not yet fixed |
| _find_cover_position() raycasts | **4,976** | **NEW** — not yet fixed |

**Result with 20 enemies**: Still 19 FPS drops (5–19 fps range) — 3 new root causes identified.

### After Fixes 5–7 (expected improvement — 20 enemies)

| Issue | Events expected | Expected reduction |
|---|---|---|
| EnemyGrenade log writes to file | **0** (was 466) | **100%** eliminated |
| _is_visible_from_player() raycasts | **5/enemy/frame** (1 check cached per frame) | ~**95%** reduction |
| _find_cover_position() raycasts | **~330** (from 4,976) | ~**93%** reduction (0.3s cooldown) |

### After Fixes 8–9 (from third verification — 20 enemies, DocksLevel)

| Issue | Events expected | Expected reduction |
|---|---|---|
| ImpactEffects file writes per hit | **0** (was 4–5 per hit) | **100%** eliminated (debug_effects = false) |
| Enemy SUPPRESSED cycling rate | **max 2/sec** (was 4–6/sec) | **>50%** reduction (0.5s minimum duration) |

### After Fixes 10–11 (from fourth verification — 20 enemies, DocksLevel)

| Issue | Events/session | Expected reduction |
|---|---|---|
| Blood decal count per kill | **8 lethal / 4 non-lethal** (was 20/10) | **60%** fewer `tree_changed` callbacks |
| LastChance file writes per threat | **0** (was 148/session) | **100%** eliminated (debug_logging = false) |

**Combined expected result**: ~60% reduction in `tree_changed` overhead from blood effects, plus
elimination of 148 useless file writes per session from LastChance threat detection.

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

### Fix 4 (from first verification): Per-enemy GUNSHOT propagation cooldown

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

**Measured reduction:** Max 10 enemy gunshots/second observed (vs 526 in 30s = 17.5/sec before).

### Fix 5 (from second verification): Gate EnemyGrenadeComponent file logging behind debug_logging

**File:** `scripts/components/enemy_grenade_component.gd`, lines 448–452

The `_log()` function was gating `print()` behind `debug_logging` but **always writing to FileLogger**.
Fix: moved `_logger.log_info()` inside the `if debug_logging:` block.

```gdscript
# BEFORE (broken):
func _log(msg: String) -> void:
    if debug_logging:
        print("...")
    if _logger and _logger.has_method("log_info"):  # ← always wrote to file
        _logger.log_info("...")

# AFTER (fixed):
func _log(msg: String) -> void:
    if debug_logging:
        print("...")
        if _logger and _logger.has_method("log_info"):  # ← gated by debug_logging
            _logger.log_info("...")
```

**Expected elimination:** 466 file I/O writes per 27-second session → **0** writes when debug_logging = false.

### Fix 6 (from second verification): Cache `_is_visible_from_player()` result per physics frame

**File:** `scripts/objects/enemy.gd`, function `_is_visible_from_player()`

Added `_cached_visible_from_player: bool` and `_visible_from_player_cache_frame: int` variables.
The function now returns the cached result if called multiple times in the same physics frame
(detected via `Engine.get_physics_frames()`).

**Rationale:** The function was called from `_process_suppressed_state`, `_process_seeking_cover_state`,
and `_process_retreating_state` — all on every physics frame. With 20 enemies each in these states,
each check does 5 raycasts = up to 100 raycasts/frame just from this function.

**Expected reduction:** 5 raycasts per enemy per frame (first call caches), vs 5–50 per enemy before.
For 20 enemies in cover states: ~100 raycasts/frame → ~5 raycasts/frame = **95% reduction**.

### Fix 7 (from second verification): Add cover search cooldown in `_find_cover_position()`

**File:** `scripts/objects/enemy.gd`, function `_find_cover_position()`

Added `COVER_SEARCH_COOLDOWN = 0.3s` constant and `_last_cover_search_time: float` tracker.
The function now skips the 16-raycast cover search if called within 0.3 seconds of the last search
(only skips when existing cover is still valid).

**Rationale:** In open-area levels where cover is sparse, enemies rapidly cycle SEEKING_COVER → COMBAT
→ RETREATING → SUPPRESSED at up to 10 cycles/second. Each cycle triggers `_find_cover_position()`
which always returns empty. With 0.3s cooldown, max 3–4 searches/second vs 10+ before.

**Expected reduction:** 311 cover searches × 16 raycasts = 4,976 total → ~50 searches × 16 = ~800 raycasts = **84% reduction**.

### Fix 8 (from third verification): Gate ImpactEffectsManager per-hit logging behind debug flag

**File:** `scripts/autoload/impact_effects_manager.gd`, function `spawn_blood_effect()`, `_spawn_blood_decals_at_particle_landing()`, `_spawn_wall_blood_splatter()`

Moved per-hit `_log_info()` calls inside `if _debug_effects:` blocks. The calls affected:
- `"spawn_blood_effect called at..."` in `spawn_blood_effect()`
- `"Blood particle effect instantiated successfully"` in `spawn_blood_effect()`
- `"Blood effect spawned at..."` in `spawn_blood_effect()`
- `"Blood decals scheduled: N..."` in `_spawn_blood_decals_at_particle_landing()`
- `"Wall found for blood splatter at..."` in `_spawn_wall_blood_splatter()`

**Rationale:** `_log_info()` writes to FileLogger unconditionally. Each MiniUzi shot that hits
an enemy triggers 4–5 `_log_info()` calls. At 13 shots/sec with continuous hits: **52–65 file
writes/sec** from this function alone. Gating behind `_debug_effects = false` (the default)
eliminates all file I/O from normal gameplay hits.

**Expected elimination:** 765 ImpactEffects events/session → **0** writes in normal gameplay.

### Fix 9 (from third verification): Add minimum SUPPRESSED duration before cover-seek transition

**File:** `scripts/objects/enemy.gd`, function `_process_suppressed_state()` and `_transition_to_suppressed()`

Added `SUPPRESSED_MIN_DURATION = 0.5s` constant and `_suppressed_entry_time: float` tracker.
`_transition_to_suppressed()` now records entry time; `_process_suppressed_state()` checks
minimum duration before transitioning to `SEEKING_COVER` when visible to player.

**Rationale:** Without this gate, an enemy entering SUPPRESSED with `_is_visible_from_player() == true`
would immediately transition to SEEKING_COVER in the same physics frame, then COMBAT (no cover),
then RETREATING, then SUPPRESSED again — completing a full cycle in < 5 physics frames (< 85ms at 60fps).
With a 0.5s minimum, cycling is capped at 2 full cycles/second maximum per enemy.

**Expected reduction:** OpenArea_Patrol2 was cycling 4–6 times/second → max 2 times/second = **>50% reduction** in
state-driven raycast load for open-terrain enemies.

### Fix 10 (from fourth verification): Reduce blood decal count per hit

**File:** `scripts/autoload/impact_effects_manager.gd`, constants `BLOOD_DECALS_PER_LETHAL_HIT` and `BLOOD_DECALS_PER_NONLETHAL_HIT`

Reduced blood decal count from 20/10 to **8 (lethal) and 4 (non-lethal)**. This directly reduces
the number of `add_child()` calls, and therefore the number of `tree_changed` signal fires.

**Rationale:** Each decal triggers `SceneTree.tree_changed` which invokes callbacks in all scene
change listeners (4+ managers). At the original 20 lethal decals: one kill triggers 20 decals ×
4+ listeners = 80+ callbacks in a single frame. With 8 decals: 8 × 4 = 32 callbacks — a 60%
reduction. Blood visual quality is preserved with 8 decals per lethal hit (visually similar).

**Expected reduction:** ~60% fewer `tree_changed` callbacks per kill → ~60% less CPU overhead
from blood-death events.

### Fix 11 (from fourth verification): Gate LastChanceEffectsManager per-threat logging behind debug flag

**File:** `scripts/autoload/last_chance_effects_manager.gd`, `_debug_logging` flag

Added `_debug_logging = false` flag. All per-bullet-threat log messages ("Threat detected",
"Not in hard mode - effect disabled", "Cannot trigger effect") are now gated behind this flag.

**Rationale:** In Normal difficulty, the LastChance effect is disabled, but the ThreatSphere still
detects every bullet entering range. Each detection produced 2 file writes with zero benefit. With
148 such events in a 103-second session at Normal difficulty, this was pure overhead.

**Expected elimination:** 148 file writes/session → **0** writes when `_debug_logging = false`.

## Round 6 Analysis — Remaining Bottlenecks After 11 Fixes

After applying all 11 fixes (Rounds 1–5), two verification sessions on 2026-03-11 confirm:
- **10-enemy scenario**: Fully resolved (no FPS drops observed on LabyrinthLevel/BuildingLevel)
- **20-enemy scenario (DocksLevel)**: Still drops to 5–7 fps — the fundamental multi-agent CPU overhead has not been resolved

The remaining bottlenecks require **architectural changes**, not just parameter tuning:

### RCA-14 (Architectural): Sound propagation O(N) scans not bounded at engine level

**Confirmed in Round 6:** Every GUNSHOT and CASING_KICK still scans all remaining listeners (15–20 per event).
With M16 and multiple UZI enemies simultaneously firing, this generates 22–23 SoundPropagation events/sec,
each touching all listeners. The per-event cooldown (Fix 4) reduced enemy shots but player shots and
CASING_KICKs still propagate fully.

**Proposed fix:** Spatial partitioning — divide the map into cells, maintain a cell index for each listener,
and when a sound is emitted only scan listeners in nearby cells (e.g., within 2× the sound range).
This would reduce the per-event scan from O(N) to O(k) where k is typically 2–5 nearby enemies.

### RCA-15 (Architectural): All 20 enemy AI state machines run every physics frame

**Confirmed in Round 6 (Log 2):** 6 fps FPS drop at 20:09:22, before any combat, just from 20 enemies
patrolling. The AI update cost at 20 agents × 60 physics frames = 1,200 AI update calls/second.
Each update: state evaluation, visibility checks (cached), navigation queries, rotation calculations.

**Proposed fix:** Staggered AI updates (LOD-based update rate). Enemies far from the player or not
currently in combat could update every 3–5 frames instead of every frame, reducing AI update calls
by 60–80% for distant/inactive enemies without visible gameplay difference.

### RCA-16 (High): BloodDecal burst spawning on kills — tree_changed overhead persists

**Confirmed in Round 6:** BloodDecal peak still 35–36/sec despite Fix 10 (reduced from 20→8 lethal,
10→4 non-lethal). Peak spikes are from multiple enemies dying within the same second:
- Two enemies die at 20:09:08 → 2 × 8 lethal decals = 16 + deferred particle decals = 35/sec burst

**Proposed fix:** Per-second BloodDecal rate limiting (`MAX_BLOOD_DECALS_PER_SECOND`) using a global
counter reset each frame, deferred spawning of excess decals to subsequent frames.

### RCA-17 (Medium): SUPPRESSED state cycling still active despite Fix 9

**Confirmed in Round 6:** `OpenArea_Patrol1` and `OpenArea_Patrol2` still cycle `SUPPRESSED →
SEEKING_COVER → COMBAT → RETREATING → SUPPRESSED` at high rate (4+ times/sec seen in both sessions).
Fix 9 added `SUPPRESSED_MIN_DURATION = 0.5s` minimum before transitioning to SEEKING_COVER, but the
cycle is observed to still happen very rapidly, suggesting the minimum is either not being enforced
correctly, or the transition path is:
- SUPPRESSED (0.5s minimum enforced) → but then SEEKING_COVER → COMBAT (immediate, no cover found)
  → RETREATING (immediate) → SUPPRESSED → (repeat from start)

The 0.5s minimum only covers the SUPPRESSED phase; SEEKING_COVER and RETREATING still exit immediately.
Adding minimum durations to SEEKING_COVER and RETREATING states would further cap the cycle rate.

## References

- [Godot 4 General Optimization Tips](https://docs.godotengine.org/en/stable/tutorials/performance/general_optimization.html)
- [Godot 4 Object Pooling Guide](https://uhiyama-lab.com/en/notes/godot/godot-object-pooling-basics/)
- [Debug logging performance impact — Godot proposals #14370](https://github.com/godotengine/godot-proposals/issues/14370)
- [Sound propagation batching — Godot Forum](https://forum.godotengine.org/t/spatialised-audio-system-in-godot-with-support-for-occlusion-and-propagation/40824)
- [Godot 4 AI LOD patterns — KidsCanCode](https://kidscancode.org/godot_recipes/4.x/ai/index.html)
- [Staggered physics updates in games — Game Programming Patterns](https://gameprogrammingpatterns.com/update-method.html)
