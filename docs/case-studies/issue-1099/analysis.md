# Case Study: Issue #1099 — Dust Effect on Wall Destruction (Breaching Charges)

## Issue Summary

**Title:** update: breaching charges
**Request (translated from Russian):** Add a dust effect at the location of the wall immediately after the explosion. Make it maximally optimized (so it definitely doesn't cause frame drops). Implement it.

## Context

Breaching charges are a gameplay item where the player places C4-like explosive charges on walls, then detonates them to create a passage. The detonation already produces:
- A directional cone explosion flash effect (`ExplosionFlash.tscn`)
- Wall passage carving (collision + visual split)
- Enemy stun/blind effects
- Explosion sound

Missing: a **dust/debris cloud** that appears at the wall position immediately after the explosion, to sell the destructive impact visually.

## Existing Infrastructure

### DustEffect.tscn
Path: `res://scenes/effects/DustEffect.tscn`

Already exists and is used for bullet impacts. It is a `GPUParticles2D` with:
- **25 particles**, one-shot, explosiveness = 0.85 (near-instant burst)
- Lifetime = 2.5s, spread = 80°, radius = 5px emission sphere
- Brownish/beige color gradient (0.65→0.5 alpha fade) — perfect for dust/debris
- Attached `effect_cleanup.gd` script: auto-frees after `lifetime + cleanup_delay`

### ImpactEffectsManager (autoload)
Path: `res://scripts/autoload/impact_effects_manager.gd`

Provides `spawn_dust_effect(position, surface_normal, caliber_data)` which:
1. Loads `DustEffect.tscn` (cached on first call)
2. Instantiates and positions the effect
3. Rotates it to face away from surface normal
4. Scales based on caliber data
5. Adds to scene tree and sets `emitting = true`

### BreachingChargesEffect (the file to modify)
Path: `res://scripts/effects/breaching_charges_effect.gd`

The `detonate()` function already calls `_spawn_explosion_effect()`. We need to add a call to `_spawn_dust_effect_at_wall()` after opening the wall passage.

## Performance Analysis

### Why DustEffect is Safe for Performance

1. **Particle count is small**: 25 particles per effect, one-shot
2. **`one_shot = true`**: stops emitting after one burst, no continuous updates
3. **`explosiveness = 0.85`**: all particles burst near-instantly, minimal per-frame overhead after first frame
4. **Auto-cleanup**: `effect_cleanup.gd` calls `queue_free()` after `lifetime + cleanup_delay`, so nodes don't accumulate
5. **Breaching charges are rare events**: max 2 per battle, so this fires at most 2× per level
6. **ImpactEffectsManager caches the scene**: `_dust_effect_scene` is loaded once via `preload`/lazy-load, no repeated disk I/O

### Optimization Approach (Multiple Spawn Points)

For a wall breach, spawning 3 dust puffs spread along the breach width gives a realistic debris cloud:
- One at the breach center
- One slightly to the left
- One slightly to the right

This keeps total particle count at 75 per detonation (3 × 25), well within acceptable budget.

Alternatively, a single larger dust spawn at the breach center (scaled up) is even simpler and equally effective.

**Chosen approach**: Spawn **2–3 dust effect instances** at the breach position with slight offsets and varied rotations, using ImpactEffectsManager's existing `spawn_dust_effect` method. This reuses existing infrastructure, avoids code duplication, and is trivially cheap (75 particles, one-shot, auto-cleaned up).

## Known Components / Libraries

- **Godot 4 GPUParticles2D**: hardware-accelerated particle system, ideal for dust/debris
- **DustEffect.tscn**: already in this project, already tuned for wall impacts
- **ImpactEffectsManager**: already handles all impact effect pooling/spawning
- **effect_cleanup.gd**: auto-cleanup already attached to DustEffect

## Proposed Solution

In `breaching_charges_effect.gd`, add a `_spawn_wall_dust_effect(det_pos, det_dir)` function that:
1. Gets the `ImpactEffectsManager` autoload from the scene tree
2. Calls `spawn_dust_effect` 3 times with:
   - Position: `det_pos` (center), `det_pos + perp * 20` (left), `det_pos - perp * 20` (right)
   - Normal: `det_dir` (direction the blast went, i.e., away from player into wall)
3. Is called from `detonate()` after `_open_wall_passage` calls

This is minimal, maximally optimized, and reuses existing infrastructure.

## References

- Godot 4 GPUParticles2D docs: https://docs.godotengine.org/en/stable/classes/class_gpuparticles2d.html
- Issue #1043: initial breaching charges feature
- Issue #1087: directional explosion cone
- Issue #1093: corner fill fixes
