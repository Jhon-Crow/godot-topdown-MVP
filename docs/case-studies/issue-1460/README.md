# Case Study: FPS Drop During F-1 Grenade Explosion (Issue #1460)

## Problem

FPS drops by ~22 frames (from ~40 to ~18 fps) when the F-1 defensive grenade explodes
with particles enabled. Affects blood particles, dust from wall hits, and explosion effects.

## Environment

- OS: Windows
- Engine: Godot 4.3-stable
- Build: Release (not debug)
- Map: LabyrinthLevel
- Settings: blood_amount=1.00, wall_hit_particles=true, particles=true

## Root Cause Analysis

### Primary Bottleneck: Bulk Damage via Individual on_hit Calls

The `_apply_explosion_damage()` in `defensive_grenade.gd` applies 99 damage by calling
`enemy.on_hit_with_info()` **99 times in a loop** per enemy:

```gdscript
for i in range(final_damage):
    enemy.on_hit_with_info(hit_direction, null)
```

Each `on_hit_with_info()` call triggers:
- Blood particle effect instantiation (GPUParticles2D — NOT pooled)
- Blood decal spawning (15-30 Sprite2D nodes)
- Audio playback
- Hit flash animation
- Health update & visual refresh

With 2 enemies in blast radius: **99 × 2 = 198 blood particle instantiations** in a single
frame. This is the dominant cause of the FPS drop.

### Secondary Bottleneck: Simultaneous Shrapnel Spawning

40 shrapnel pieces are spawned synchronously in `_spawn_shrapnel()`. Each shrapnel:
- Is an Area2D with collision shapes, Line2D trail
- Immediately starts physics processing
- Can hit walls and spawn dust effects (pooled, but still capped at 16 concurrent)

All 40 are added to the scene tree in a single frame.

### Tertiary Factors

- Blood effects use `_blood_effect_scene.instantiate()` every time (no pooling)
- Dust effects ARE pooled (Issue #1145) but blood effects are not
- Explosion light is pooled (Issue #724) — not a bottleneck

## Log Evidence

From `game_log_20260324_204241.txt`:
```
[20:46:08] [DefensiveGrenade] Spawned shrapnel #1..#40
[20:46:09] [WARN] [FPS] Drop detected: 18 fps (threshold: 30)
[20:46:10] [WARN] [FPS] Drop detected: 28 fps (threshold: 30)
```

FPS drops to 18 immediately after explosion, recovers to 28 next frame, then normal.

## Solution

### Fix 1: Bulk Damage Instead of Per-Hit Loop

Replace the 99-iteration `on_hit_with_info()` loop with a single call using
`on_hit_with_bullet_info()` which accepts a `damage` parameter. This reduces
198 blood effect spawns to just 2 (one per enemy).

### Fix 2: Blood Effect Pooling

Pool GPUParticles2D blood effects the same way dust effects are already pooled
(Issue #1145 pattern). Pre-create a pool at startup, reuse instead of instantiate.

### Fix 3: Stagger Shrapnel Spawning

Spread the 40 shrapnel spawns across multiple frames using batched deferred calls.
Spawn ~10 shrapnel per frame over 4 frames. This is imperceptible to the player
(total spread is ~67ms at 60fps) but prevents a single-frame CPU spike.

## References

- [Godot Issue #103308](https://github.com/godotengine/godot/issues/103308) — GPUParticles2D first-emit stutter
- [Godot Issue #71182](https://github.com/godotengine/godot/issues/71182) — Node creation 4x slower in Godot 4 vs 3
- [Godot Issue #114959](https://github.com/godotengine/godot/issues/114959) — GPUParticles2D blocks main thread
- [Godot Docs: Pipeline Compilations](https://docs.godotengine.org/en/stable/tutorials/performance/pipeline_compilations.html)
- [Godot Forum: Optimizing chain explosions](https://forum.godotengine.org/t/optimizing-for-chains-of-explosions/117796)
- [Object Pooling Guide for Godot](https://uhiyama-lab.com/en/notes/godot/godot-object-pooling-basics/)
