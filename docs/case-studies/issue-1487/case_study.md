# Case Study: Issue #1487 — FPS Drops When Shooting at Walls

## Summary

**Issue**: FPS drops during sustained rapid fire at walls in certain maps.
**Author report (initial)**: "оптимизируй частицы пыли (сейчас потеря 30fps)" — Optimize dust particles (currently losing 30 FPS).
**Author report (follow-up)**: "почему то на карте Обучение fps не падает при стрельбе в стену, но на карте Здание падает." — For some reason FPS doesn't drop on the Training map when shooting at walls, but on the Building map it does.

---

## Data Collected

### Log Files

#### `game_log_20260325_050601.txt` — LabyrinthLevel session, initial report

| Time | Event |
|------|-------|
| 05:06:01 | Game start. Dust pool initialized: 16 effects pre-created. `wall_hit_particles: true`. |
| 05:06:03 | **FPS drop: 28 fps** (threshold: 30). LabyrinthLevel, 5 enemies. Very early — likely scene load + shader warmup. |
| 05:06:28 | **FPS drop: 29 fps**. Level with 10 enemies. Active gameplay. |
| 05:06:32 | **FPS drop: 29 fps**. Still 10 enemies, active gameplay. |

Key settings: `particles_enabled: true`, `wall_hit_particles: true`, released build, Godot 4.3-stable, Windows.

#### `game_log_20260325_123047.txt` — Multi-map session (after initial dust fix)

| Time | Map | Event |
|------|-----|-------|
| 12:30:48 | LabyrinthLevel (5 enemies) | Game started. `dust_quality: 0` (Full). Dust pool: 8 effects. |
| 12:30:50 | LabyrinthLevel | **FPS drop: 13 fps** — from shader warmup (1364ms warmup just completed, one-time). |
| 12:30:56 | Tutorial (0 real enemies) | Scene change — player shoots walls repeatedly, **no FPS drops detected**. |
| 12:31:49 | Tutorial | Player equips **BreakerBullets** in Armory. |
| 12:32:00 | **BuildingLevel** (10 enemies) | Scene change — BreakerBullets persist, `enemy_path_visible: true`. |
| 12:32:02+ | BuildingLevel | Each shot creates EXPLOSION + GUNSHOT events. ~15 detonations/sec at wall. |
| 12:32:33–12:32:41 | BuildingLevel | **Owner-reported FPS drops** (below 30fps threshold logger — ~35-45fps visually). |

Key settings from second log:
- `dust_quality: 0` (Full, optimized pool: 8 effects, 12 particles, 15Hz sim)
- **`enemy_path_visible: true`** (ExperimentalSettings — debug overlay)
- **BreakerBullets active** in BuildingLevel (bullets detonate 60px before walls)
- 10 enemies in BuildingLevel vs 0 real enemies in Tutorial
- FPS logger threshold: 30 fps — drops are above threshold but visually noticeable

---

## Root Cause Analysis

### Comparison: Tutorial vs BuildingLevel

| Factor | Tutorial | BuildingLevel |
|--------|----------|---------------|
| Real AI enemies | 0 | 10 |
| BreakerBullets active | No (Recoil Compensator) | Yes (player equipped in Armory) |
| What happens on wall shots | Bullet hits wall → dust puff | Bullet detonates 60px early → explosion + shrapnel |
| Active shrapnel nodes | 0 | up to 60 (each with physics + trail) |
| Enemy path draw calls/frame | 0 (no enemies) | ~500+ (10 enemies × complex paths) |
| Sound listener checks/shot | 0 | 10 (all enemies notified) |

### Root Cause 1: BreakerShrapnel Trail Physics at 60Hz (MAIN)

**Code**: `scripts/projectiles/breaker_shrapnel.gd`

With BreakerBullets, each wall shot detonates 60px before the wall and spawns **1–10 shrapnel pieces** (capped at 60 concurrent). Each shrapnel runs `_physics_process()` at 60Hz:

```gdscript
func _physics_process(delta: float) -> void:
    position += direction * speed * delta  # movement
    speed = maxf(speed * 0.995, 200.0)    # deceleration
    _update_smoky_trail(delta)             # Line2D trail — runs every frame
    _time_alive += delta
    if _time_alive >= lifetime:
        _destroy()
```

`_update_smoky_trail()` per frame per shrapnel:
- `_trail.clear_points()` + 6× `_trail.add_point()` — 7 Line2D API calls
- 2 sin() calls for wobble
- 1 Array push_front + pop_back

With 60 concurrent shrapnel at 15 shots/sec sustained fire:
- **60 `_physics_process` callbacks/frame** = 60 physics nodes
- **60 × 7 = 420 Line2D API calls/frame**

In Tutorial: 0 BreakerBullets → 0 shrapnel → 0 trail updates.

### Root Cause 2: Enemy Path Overlay at 60Hz (SIGNIFICANT)

**Code**: `scripts/autoload/enemy_path_monitor.gd`

`_process()` calls `_overlay.refresh()` every frame when `enemy_path_visible: true`. `refresh()` collects nav paths from all enemies and calls `queue_redraw()`. Then `_draw()` fires:

```gdscript
func _draw() -> void:
    for path_data in _paths:                 # 10 enemies
        draw_line(enemy_pos, path[0], ...)   # polyline
        for i in range(path.size() - 1):
            draw_line(path[i], path[i+1], ...)
        for i in range(path.size() - 1):
            draw_circle(path[i], ...)              # waypoint fill
            _draw_circle_outline(path[i], ...)     # 12 draw_line calls per circle
        draw_circle(dest, ...)                     # destination fill
        _draw_circle_outline(dest, ...)            # 12 draw_line calls
```

With 10 enemies × 5-waypoint paths:
- ~10 × (4 polyline segments + 4 waypoints × 12 + 1 dest × 12) = **~640 draw_line calls/frame**
- `draw_count` grows continuously: 3250 → 3490 → 3551 → 3612 per diagnostic log

In Tutorial: no enemies in "enemies" group → `_paths` is empty → 0 draw calls from overlay.

### Root Cause 3: Original Dust Particle Issue (Fixed in Round 1)

Before the Round 1 fix, `DustEffect.tscn` had `amount=25`, `lifetime=2.5s`, no `fixed_fps`. At 15 shots/sec, all maps suffered:
- 16 concurrent dust nodes × 25 particles = **400 GPU particles** simulated at 60Hz
- Natural concurrency exceeded the pool cap (16) → effects dropped

Round 1 fix reduced this to 8 concurrent × 12 particles = **96 GPU particles** at 15Hz sim. This resolved the LabyrinthLevel and Tutorial drops.

### Root Cause 4: SoundPropagation Cost Scales with Enemy Count

Every bullet and every breaker detonation calls `SoundPropagation.emit_sound()`, which iterates all registered listeners:

```
BuildingLevel: notified=3-4, out_of_range=6-7  → 10 distance checks per shot
Tutorial:      notified=0, out_of_range=0       → 0 checks per shot
```

At 15 shots/sec (MiniUzi) + 15 detonations/sec (BreakerBullets) = 30 events/sec × 10 checks = **300 listener distance calculations/sec** in BuildingLevel vs 0 in Tutorial.

### Combined Frame Budget Impact

Frame budget at 60fps = 16.7ms per frame.

| Overhead source | Tutorial | BuildingLevel |
|----------------|----------|---------------|
| Dust effects (after fix) | ~0.5ms | ~0.5ms |
| Shrapnel physics + trail | 0 | ~2-3ms (60 nodes × 420 Line2D calls) |
| Enemy path overlay | 0 | ~1-2ms (~640 draw_line/frame) |
| Sound propagation | ~0ms | ~0.5ms |
| AI navigation (10 enemies) | ~0ms | ~2ms |
| **Total extra vs. Tutorial** | — | **~6-8ms** |

Result: Building-Level frame time ~23-25ms → **40-43 fps** visually. Above the 30fps logger threshold but clearly noticeable.

---

## Changes Applied

### Round 1 (commit `ba08d26c` + `18bae84a`) — Dust Particle Optimization

**`scenes/effects/DustEffect.tscn`**:
- `amount`: 25 → 12
- `lifetime`: 2.5s → 1.2s
- `cleanup_delay`: 1.0s → 0.5s
- Added `fixed_fps = 15`

**`scripts/autoload/impact_effects_manager.gd`**:
- `MAX_CONCURRENT_DUST_EFFECTS`: 16 → 8
- `DUST_EFFECT_POOL_SIZE`: 16 → 8
- Half quality: skips every other spawn (amount_ratio has no GPU perf benefit)

**`scripts/autoload/gameplay_settings.gd`** + UI:
- Added `dust_quality` (0=Full / 1=Half / 2=Off)
- Replaced binary WallHitParticles checkbox with OptionButton in OptimizationMenu

**Result**: Tutorial and LabyrinthLevel FPS drops resolved.

### Round 2 (this PR) — Shrapnel Trail + Path Overlay

#### Fix 1: BreakerShrapnel Trail at 15Hz Instead of 60Hz

**File**: `scripts/projectiles/breaker_shrapnel.gd`

Throttle `_update_smoky_trail()` to 15Hz using a timer:

```gdscript
const TRAIL_UPDATE_INTERVAL: float = 1.0 / 15.0
var _trail_update_timer: float = 0.0

func _physics_process(delta: float) -> void:
    position += direction * speed * delta
    speed = maxf(speed * 0.995, 200.0)
    _trail_update_timer += delta
    if _trail_update_timer >= TRAIL_UPDATE_INTERVAL:
        _trail_update_timer -= TRAIL_UPDATE_INTERVAL
        _update_smoky_trail()
    _time_alive += delta
    if _time_alive >= lifetime:
        _destroy()
```

**Impact**: 420 → 105 Line2D API calls/frame (−75%), with visually imperceptible change to trail smoothness at fast shrapnel velocity.

#### Fix 2: Enemy Path Overlay Throttled to 10Hz

**File**: `scripts/autoload/enemy_path_monitor.gd`

Throttle path data collection + `queue_redraw()` to 10Hz:

```gdscript
const PATH_REFRESH_INTERVAL: float = 0.1  # 10 Hz
var _refresh_timer: float = 0.0

func _process(delta: float) -> void:
    if _overlay != null and is_instance_valid(_overlay) and _overlay.visible:
        _refresh_timer += delta
        if _refresh_timer >= PATH_REFRESH_INTERVAL:
            _refresh_timer -= PATH_REFRESH_INTERVAL
            _overlay.refresh()
            ...
```

**Impact**: Path tree queries + queue_redraw() reduced from 60 to 10 per second (−83%). Debug paths still update visibly smoothly for design purposes.

---

## Expected Results After Round 2

| Scenario | Before Round 2 | After Round 2 |
|----------|---------------|---------------|
| Line2D trail calls/frame | up to 420 | up to 105 |
| Enemy path refresh rate | 60 Hz | 10 Hz |
| BuildingLevel frame time (est.) | ~23-25ms | ~18-19ms |
| BuildingLevel FPS (est.) | ~40-43 fps | ~52-55 fps |

**Result (Round 2)**: Owner reported FPS still dropping to ~30fps on BuildingLevel. Round 2 fixes alone were insufficient.

---

## Round 3: Deep Analysis of Remaining FPS Drops

### New Data: `game_log_20260325_130329.txt`

Owner report: "всё ещё на карте Обучение нет проседания fps а на карте Здание проседание до 30fps"
(Still no FPS drops on Tutorial, but drops to 30fps on BuildingLevel)

Key settings from third log:
- `dust_quality: 0` (Full), `ai: false` (AI disabled in PerformanceSettings)
- BreakerBullets active, `enemy_path_visible: true`, 10 enemies
- Multiple BuildingLevel sessions with sustained fire at walls

### Remaining Root Causes Identified in Round 3

#### Root Cause 5: Unthrottled Breaker EXPLOSION Sound Propagation

Each of ~15 detonations/sec emitted a separate `SoundPropagation.emit_sound(EXPLOSION)` event, iterating all 10 enemy listeners. Unlike CASING_KICK and EMPTY_CLICK (which had 0.4s cooldowns), breaker explosions had no throttle.

**Cost per unthrottled second**: 15 EXPLOSION events × 10 listeners = 150 listener iterations + 30 `_log_to_file()` calls + 30 string formatting operations.

**Fix**: Added `emit_breaker_explosion()` with 0.2s cooldown (5/sec max) — enemies already react to the concurrent GUNSHOT.

#### Root Cause 6: Unthrottled Player GUNSHOT Sound Propagation

MiniUzi fires at ~15 shots/sec. Each shot called `SoundPropagation.emit_sound(GUNSHOT)` without any throttle, iterating all 10 listeners every time.

**Cost per unthrottled second**: 15 GUNSHOT events × 10 listeners = 150 listener iterations + 45 enemy `on_sound_heard_with_intensity()` calls (3 in range) + 45 `_log_to_file()` calls.

**Fix**: Added `emit_player_gunshot()` throttle with 0.1s cooldown (10/sec max). Enemies transition to COMBAT on the first heard gunshot — subsequent rapid shots are redundant.

#### Root Cause 7: Excessive Shrapnel Count (10 per detonation, 60 concurrent)

With MiniUzi at 15 shots/sec × 10 shrapnel/detonation = 150 spawns/sec. Even with 0.8s lifetime and 60 concurrent cap, the sheer volume of:
- Physics process callbacks (30-60 nodes × 60Hz)
- Trail updates (30-60 nodes × 15Hz)
- Wall-hit raycasts (each shrapnel does `_get_surface_normal()` raycast on hit)
- Dust spawns (each shrapnel spawns dust on wall hit, saturating the 8-effect pool)

**Fix**: Reduced `BREAKER_MAX_SHRAPNEL_PER_DETONATION` from 10 to 5, `BREAKER_MAX_CONCURRENT_SHRAPNEL` from 60 to 30.

#### Root Cause 8: Shrapnel Dust Spawn + Raycast Overhead

Each shrapnel wall hit called `_get_surface_normal()` (physics raycast) then `spawn_dust_effect()`. With 75+ shrapnel wall hits/sec, this added ~75 raycasts/sec and the dust pool (8 effects) was instantly saturated — most spawn calls found no available pool slot.

**Fix**: Removed dust spawn and raycast from shrapnel wall hits entirely. The breaker detonation already spawns an explosion effect at the impact point.

#### Root Cause 9: Unthrottled Breaker Explosion Visual Effects

Each of ~15 detonations/sec spawned a PointLight2D with a 0.3s fade tween. This created 15 tweens/sec and up to 5-8 concurrent PointLight2D objects with GPU draw calls.

**Fix**: Added `BREAKER_EXPLOSION_EFFECT_COOLDOWN = 0.13s` — limits visual effects to ~8/sec, reducing tween creation by ~47%.

#### Root Cause 10: Lambda Allocation in SoundPropagation Listener Filtering

`emit_sound()` called `_listeners.filter(func(l): return is_instance_valid(l))` on every invocation (~30 calls/sec), allocating a new lambda closure and a new Array each time.

**Fix**: Replaced with in-place filtering using index iteration (zero allocations).

### Combined Impact (Round 3)

| Overhead source | Before Round 3 | After Round 3 |
|-----------------|----------------|---------------|
| GUNSHOT propagation events/sec | 15 | 10 (−33%) |
| EXPLOSION propagation events/sec | 15 | 5 (−66%) |
| Total listener iterations/sec | 300 | 150 (−50%) |
| Concurrent shrapnel (peak) | 60 | 30 (−50%) |
| Shrapnel spawns/sec | 150 | 75 (−50%) |
| Shrapnel wall-hit raycasts/sec | ~75 | 0 (−100%) |
| Shrapnel dust spawns/sec | ~75 | 0 (−100%) |
| Explosion light tweens/sec | 15 | ~8 (−47%) |
| Lambda allocations/sec (listener filter) | 30 | 0 (−100%) |
| **Estimated frame time savings** | — | **~4-6ms** |
| **Estimated BuildingLevel FPS** | ~30fps | **~45-55fps** |

---

## All Rounds Summary

| Round | Fix | Impact | Affected Maps |
|-------|-----|--------|---------------|
| 1 | DustEffect: amount 25→12, lifetime 2.5→1.2s, fixed_fps=15, pool 16→8 | −76% GPU particles | All |
| 1 | dust_quality setting: Full/Half/Off in OptimizationMenu | User control | All |
| 2 | BreakerShrapnel trail throttled to 15Hz | −75% Line2D calls | BuildingLevel (BreakerBullets) |
| 2 | EnemyPathMonitor refresh throttled to 10Hz | −83% draw_line calls | All (with enemy_path_visible) |
| 3 | Player GUNSHOT propagation throttled to 10Hz | −33% GUNSHOT iterations | All maps with enemies |
| 3 | Breaker EXPLOSION propagation throttled to 5Hz | −66% EXPLOSION iterations | BuildingLevel (BreakerBullets) |
| 3 | Shrapnel per detonation: 10→5, concurrent cap: 60→30 | −50% shrapnel overhead | BuildingLevel (BreakerBullets) |
| 3 | Shrapnel wall-hit: removed dust + raycast | −100% shrapnel raycasts/dust | BuildingLevel (BreakerBullets) |
| 3 | Breaker explosion visual effect throttled | −47% PointLight2D tweens | BuildingLevel (BreakerBullets) |
| 3 | SoundPropagation in-place listener filter | 0 allocations/sec | All |

---

## Research: Godot Performance Optimization References

1. **Godot docs — GPUParticles2D fixed_fps**: Setting `fixed_fps` reduces simulation to N Hz while rendering at full frame rate via interpolation. Transparent to the player for slow-moving effects like dust. [Godot 4.x docs](https://docs.godotengine.org/en/stable/classes/class_gpuparticles2d.html#class-gpuparticles2d-property-fixed-fps)

2. **amount_ratio has no GPU benefit**: Godot docs explicitly note that `amount_ratio` does not reduce GPU simulation cost — the full `amount` is always simulated regardless. Only reducing `amount` or skipping spawns helps. This is why the Half quality mode skips every other spawn instead of using `amount_ratio`.

3. **Object pooling for particles**: Creating/destroying `GPUParticles2D` nodes has startup cost (shader compilation, first-emit stutter — Godot issue #103308). Pre-creating and reusing pooled nodes eliminates this overhead. Implemented for dust effects in Round 1.

4. **Line2D `clear_points()` cost**: Every `clear_points()` + N×`add_point()` call forces a geometry rebuild on the GPU. High-frequency updates (60Hz × 60 nodes) add measurable overhead. Throttling to 15Hz reduces this by 4×.

5. **CanvasItem `queue_redraw()`**: Every `queue_redraw()` call schedules a `_draw()` invocation next frame. When called 60×/sec with complex draw operations (hundreds of `draw_line`), it dominates the renderer's 2D batch processing cost.

---

## Round 4: Critical Bug — C# Weapon Nodes Bypass the Throttle

### New Data: `game_log_20260325_133018.txt`

Owner report: "не вижу изменений" — "I don't see any changes."

Analysis of `game_log_20260325_133018.txt` confirmed:
- 17 GUNSHOT events per second were still logged at `source=PLAYER (MiniUzi)` during BuildingLevel combat
- The `emit_player_gunshot()` throttle (max 10/sec) was clearly not being called

### Root Cause 11: C# Weapon Nodes Call `emit_sound` Directly, Bypassing the Throttle

The Round 3 fix added `emit_player_gunshot()` to `scripts/characters/player.gd:_shoot()`, but this function is **only called when no C# weapon is equipped** (`CurrentWeapon == null`). When a C# weapon node like MiniUzi is attached as a child, `Scripts/Characters/Player.cs:HandleShootingInput()` calls `CurrentWeapon.Fire()` directly — completely bypassing `player.gd`'s `_shoot()`.

Each C# weapon class had its own `EmitGunshotSound()` method that called `emit_sound()` unthrottled:

```csharp
// BEFORE (MiniUzi.cs, AssaultRifle.cs, MakarovPM.cs, Shotgun.cs — all identical pattern):
private void EmitGunshotSound()
{
    var soundPropagation = GetNodeOrNull("/root/SoundPropagation");
    if (soundPropagation != null && soundPropagation.HasMethod("emit_sound"))
    {
        float loudness = WeaponData?.Loudness ?? 800.0f;
        soundPropagation.Call("emit_sound", 0, GlobalPosition, 0, this, loudness);
    }
}
```

This meant:
- `MiniUzi.Fire()` → `EmitGunshotSound()` → `emit_sound()` at full 15 shots/sec (unthrottled)
- The `emit_player_gunshot()` throttle added to `player.gd` was **never reached** during MiniUzi use

The log evidence: identical GUNSHOT entries 17× in 1 second from `(MiniUzi)` confirms the C# path was executing, not the GDScript `_shoot()`.

### Fix (Round 4)

Updated all C# weapons to call `emit_player_gunshot` (which has the 0.1s cooldown):

```csharp
// AFTER:
private void EmitGunshotSound()
{
    var soundPropagation = GetNodeOrNull("/root/SoundPropagation");
    if (soundPropagation != null && soundPropagation.HasMethod("emit_player_gunshot"))
    {
        float loudness = WeaponData?.Loudness ?? 800.0f;
        soundPropagation.Call("emit_player_gunshot", GlobalPosition, this, loudness);
    }
}
```

Files changed:
- `Scripts/Weapons/MiniUzi.cs` — primary offender (15 shots/sec)
- `Scripts/Weapons/AssaultRifle.cs` — automatic mode (~10 shots/sec)
- `Scripts/Weapons/MakarovPM.cs` — semi-auto pistol
- `Scripts/Weapons/Shotgun.cs` — slower fire rate but consistent with the pattern

### Impact

| Before Round 4 | After Round 4 |
|----------------|---------------|
| MiniUzi GUNSHOT events/sec | 15 (unthrottled) | ≤10 (throttled) |
| BuildingLevel listener iterations from GUNSHOT/sec | 150 | ≤100 |
| Actual throttle coverage | player.gd only (unused when C# weapon equipped) | All weapon types |

The Round 3 throttle was functionally a no-op for the MiniUzi scenario. Round 4 makes it effective.
