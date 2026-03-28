# Issue #1626: Add Puddles Appearing on Docks Map

## Issue Description (Russian, translated)
Add appearance of puddles on the Docks map. From the very start, puddles should begin to appear; after ~30 seconds they should be normal sized; after ~60 seconds - large, and so on.
Puddles should be logically positioned.

## Context

### Docks Level Map
- Map size: ~5000x4000 pixels (floor: 64–5064 x, 200–4064 y)
- Theme: industrial docks with warehouses, shipping containers, cranes
- Has rain effect (Issue #1394) already applied
- Two indoor warehouses: WarehouseA (~400,1800), WarehouseB (~4400,2800)

### Key Areas on Map (logical puddle locations near water/low ground):
- Near water edge (y ≈ 200–400): water runoff areas
- Loading dock (x≈4000, y≈1600): near cranes, water likely pools
- Container yard open spaces: flat areas between containers
- Crane platform entrance (x≈400, y≈500): near water
- Open areas along the floor

## Existing Effects System

### Similar implementations studied:
1. **BloodDecal** (scripts/effects/blood_decal.gd): Uses Sprite2D with GradientTexture2D (radial gradient), grows/fades via tweens, has Area2D for collision detection. Good pattern for puddles.
2. **RainEffect** (scripts/effects/rain_effect.gd): GPUParticles2D for atmospheric effects, world-space tracking.
3. **BloodDecal scene**: Radial gradient texture, circle-shaped sprite, modulate alpha for fade.

### Architecture Decision
Puddles should:
- Be `Sprite2D` nodes with radial gradient textures (blue-grey water color)
- Start invisible (scale=0 or alpha=0) and grow over time via tween
- Be managed by a `PuddleManager` node in the scene
- Have pre-defined logical positions near water/drainage areas
- Grow in 3 phases: small (0–30s), medium (30–60s), large (60s+)
- NOT appear inside warehouses (consistent with rain exclusion zones)

## Solution Design

### Files to create:
1. `scripts/effects/puddle_effect.gd` — individual puddle behavior (grow phases, visual)
2. `scenes/effects/PuddleEffect.tscn` — scene with Sprite2D + gradient texture
3. `scripts/levels/puddle_manager.gd` — manages all puddles on Docks level
4. Integrate into `scenes/levels/DocksLevel.tscn`
5. Integrate into `scripts/levels/docks_level.gd` (_setup_puddles method)

### Puddle positions (logical — near water/drains, open exposed areas):
```
Near water edge / crane area:
  (400, 380) - crane platform base, water runoff
  (250, 450) - near water wall
  (550, 600) - crane platform side

Open area north:
  (1200, 350) - exposed to rain, flat area
  (1800, 400) - open area north
  (2500, 320) - mid-north open

Loading dock / east side:
  (3800, 1500) - loading dock area
  (4200, 1400) - near cranes
  (4600, 1600) - loading dock far

Open area mid:
  (1500, 1400) - open mid-left
  (2200, 1200) - open mid
  (2800, 1600) - mid open

Container yard A (east):
  (3500, 500) - between containers
  (4000, 350) - container yard A

Open area south:
  (1200, 3200) - south open
  (2500, 3400) - south mid
  (3200, 3600) - south east

Near exit / south:
  (400, 3500) - near player start area
  (1000, 3800) - south open
```

## Known Godot Patterns for Growing Effects
- Use `create_tween().tween_property(sprite, "scale", target_scale, duration)` for smooth growth
- Multiple phases achieved with sequential tween steps or timer-based callbacks
- `z_index = -1` to appear below characters but above floor

---

## Bug Report: Puddles Not Appearing — Root Cause Analysis (2026-03-28)

### User Report
Owner reported: "не появляются" (they do not appear). Log file: `game_log_20260328_082042.txt`.

### Timeline from Log

| Time | Event |
|------|-------|
| 08:20:48 | DocksLevel loaded, rain started |
| 08:20:48 | `[PuddleManager] Puddle manager ready: 23 puddles spawned` |
| 08:20:48 | `[DocksLevel] Puddle system ready (PuddleManager found)` |
| 08:20:48–08:22:18 | Player played for 90 seconds, saw NO puddles |
| 08:22:18 | Player restarted scene |
| 08:22:19 | Same initialization, same result |

### Root Cause: Incorrect z_index — Puddles Hidden Behind Floor

In Godot 4, `z_index` controls the 2D rendering order. Higher value = rendered on top.

| Node | z_index (before fix) | Effective absolute z |
|------|---------------------|----------------------|
| `Environment/Floor` (ColorRect) | 0 (default) | **0** |
| `PuddleManager` (Node2D) | **-1** ← bug | **-1** |
| `PuddleEffect` (Sprite2D, child of manager) | -1 (relative) | **-2** |

The floor ColorRect (z=0) was drawn on top of all puddles (z=-2), completely hiding them. The puddle grow animations were executing correctly — the tweens ran, scale changed from 0 to SMALL_SCALE and beyond — but the pixels were always covered by the floor's opaque color.

Note: The original design comment in `analysis.md` said `z_index = -1` to appear "below characters but above floor", but this was incorrectly applied to the PuddleManager parent (making the effective z even more negative), rather than using z=1 for the manager.

### Fix

Changed `z_index` values so puddles render above the floor (z=0):

1. **`scenes/levels/DocksLevel.tscn`** — `PuddleManager`: `z_index = -1` → `z_index = 1`
2. **`scenes/effects/PuddleEffect.tscn`** — `PuddleEffect` Sprite2D: `z_index = -1` → `z_index = 0`

Effective z of each puddle = 1 (manager) + 0 (sprite) = **1**, above floor (z=0), below RainEffect (z=100).

### References
- Game log: `game_log_20260328_082042.txt` (in this folder)
- [Godot 4 z_index docs](https://docs.godotengine.org/en/stable/classes/class_canvasitem.html#class-canvasitem-property-z-index)
- PR: https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1656
