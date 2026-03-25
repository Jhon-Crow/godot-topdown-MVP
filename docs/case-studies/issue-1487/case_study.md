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

---

## Research: Godot Performance Optimization References

1. **Godot docs — GPUParticles2D fixed_fps**: Setting `fixed_fps` reduces simulation to N Hz while rendering at full frame rate via interpolation. Transparent to the player for slow-moving effects like dust. [Godot 4.x docs](https://docs.godotengine.org/en/stable/classes/class_gpuparticles2d.html#class-gpuparticles2d-property-fixed-fps)

2. **amount_ratio has no GPU benefit**: Godot docs explicitly note that `amount_ratio` does not reduce GPU simulation cost — the full `amount` is always simulated regardless. Only reducing `amount` or skipping spawns helps. This is why the Half quality mode skips every other spawn instead of using `amount_ratio`.

3. **Object pooling for particles**: Creating/destroying `GPUParticles2D` nodes has startup cost (shader compilation, first-emit stutter — Godot issue #103308). Pre-creating and reusing pooled nodes eliminates this overhead. Implemented for dust effects in Round 1.

4. **Line2D `clear_points()` cost**: Every `clear_points()` + N×`add_point()` call forces a geometry rebuild on the GPU. High-frequency updates (60Hz × 60 nodes) add measurable overhead. Throttling to 15Hz reduces this by 4×.

5. **CanvasItem `queue_redraw()`**: Every `queue_redraw()` call schedules a `_draw()` invocation next frame. When called 60×/sec with complex draw operations (hundreds of `draw_line`), it dominates the renderer's 2D batch processing cost.
