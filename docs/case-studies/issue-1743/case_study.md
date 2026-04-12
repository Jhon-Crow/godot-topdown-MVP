# Case Study: Issue #1743 — First-Shot Lag (пролаг при первом выстреле)

## Overview

- **Issue**: [#1743](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1743)
- **Title**: fix пролаг при первом выстреле (fix lag on first shot)
- **Log file**: `game_log_20260330_112745.txt` (2511 lines)
- **Game build**: Godot 4.3-stable, release build on Windows
- **Weapon**: AK-GL (ak_gl), C# weapon (`AKGL.cs`)

---

## Timeline Reconstruction from Log

### Initial Setup
```
[11:27:45] [INFO] GAME LOG STARTED
[11:27:46] [INFO] [ImpactEffects] Starting particle shader warmup (Issue #343 fix)...
[11:27:46] [INFO] [PenultimateHit] Starting shader warmup (Issue #343 fix)...
[11:27:46] [INFO] [LastChance] Starting shader warmup (Issue #343 fix)...
[11:27:47] [INFO] [CinemaEffects] Starting cinema shader warmup (Issue #343 fix)...
```

Multiple shader warmups started at game launch.

### Warmup Completion
```
[11:27:49] [INFO] [PenultimateHit] Shader warmup complete in 3482 ms
[11:27:49] [INFO] [LastChance] Shader warmup complete in 3474 ms
[11:27:49] [INFO] [CinemaEffects] Cinema shader warmup complete in 2121 ms
[11:27:52] [INFO] [ImpactEffects] Particle shader warmup complete: 7 effects warmed up in 6374 ms
```

All warmups completed. ImpactEffects took longest (6374 ms) and covered 7 effects.

### First FPS Drop (BeachLevel, ~1 second in)
```
[11:27:52] [INFO] [ImpactEffects] Particle shader warmup complete: 7 effects warmed up in 6374 ms
[11:27:52] [INFO] [SceneLoader] Background load started successfully
[11:27:53] [WARN] [FPS] Drop detected: 17 fps (threshold: 30)
[11:27:53] [INFO] [ReplayManager] Recording frame 60 (1,0s): player_valid=True, enemies=8
```

Only 1 second after level start → first shot by player.

### Pattern: FPS Drop on Every Level Restart at ~1 second
```
[11:28:04] [WARN] [FPS] Drop detected: 7 fps (threshold: 30)   — LabyrinthLevel restart 1
[11:28:10] [WARN] [FPS] Drop detected: 10 fps (threshold: 30)  — LabyrinthLevel restart 2
[11:28:16] [WARN] [FPS] Drop detected: 10 fps (threshold: 30)  — LabyrinthLevel restart 3
[11:28:20] [WARN] [FPS] Drop detected: 8 fps (threshold: 30)   — LabyrinthLevel restart 4
[11:28:26] [WARN] [FPS] Drop detected: 6 fps (threshold: 30)   — LabyrinthLevel restart 5
[11:28:28] [WARN] [FPS] Drop detected: 6 fps (threshold: 30)   — LabyrinthLevel restart 6
[11:28:30] [WARN] [FPS] Drop detected: 1 fps (threshold: 30)   — LabyrinthLevel restart 7
```

**All FPS drops occur at exactly "Recording frame 60" (1 second)**, consistent with the player firing their first shot approximately 1 second after each level start.

---

## Root Cause Analysis

### What Issue #343 Fixed
Issue #343 ("fix пролаг при первом выстреле во врага") was fixed by adding shader warmup for **visual effects that play when a bullet hits enemies**:
- `DustEffect` (GPUParticles2D)
- `BloodEffect` (GPUParticles2D)  
- `SparksEffect` (GPUParticles2D)
- `BloodDecal` (Sprite2D with GradientTexture2D)
- `BulletHole` (Sprite2D)
- `MuzzleFlash` (GPUParticles2D + PointLight2D)
- `FlashbangEffect` (PointLight2D)

These are all effects that trigger **after the bullet hits something**. The warmup pre-compiled the GPU shaders for all of these.

### What #343 Did NOT Fix (Root Cause of #1743)

The warmup **does not include the bullet projectile scene itself**:

**`scenes/projectiles/csharp/Bullet.tscn`**:
```
[node name="Bullet" type="Area2D"]
[node name="Sprite2D" type="Sprite2D" parent="."]
    texture = PlaceholderTexture2D
[node name="Trail" type="Line2D" parent="."]
    width = 3.0
    width_curve = SubResource("Curve_trail")
    gradient = SubResource("Gradient_trail")    ← GRADIENT SHADER
[node name="CollisionShape2D" type="CollisionShape2D" parent="."]
```

The `Line2D` node with a `gradient` resource uses an internal Godot CanvasItem shader that is compiled on first use. When the player fires the first shot:

1. `BaseWeapon.SpawnBullet()` calls `BulletScene.Instantiate<Node2D>()`
2. `AddChild(bullet)` adds the bullet to the scene tree
3. The GPU encounters the `Line2D` + `Gradient` combination **for the first time**
4. Godot's rendering pipeline compiles the gradient rendering shader JIT
5. This shader compilation causes a **multi-frame stall** → FPS drop

Additionally:
- **Casing scene** (`scenes/effects/Casing.tscn`) is also instantiated for the first time on the first shot
- The **first physics body activation** in the Area2D/CollisionShape2D system may cause initialization overhead

### Why FPS Drop Gets Worse Over Restarts

Looking at the log, the FPS drops progressively worsen:
- Restart 1: 7 fps
- Restart 7: 1 fps

This is because blood decals accumulate across restarts. At the last restart:
```
[11:28:30] 13+ BloodDecal nodes created simultaneously
[11:28:30] [WARN] [FPS] Drop detected: 1 fps (threshold: 30)
```

The accumulated blood decals + first bullet instantiation + shader compilation combine for the worst drop. However, the root cause of the **first-shot-specific** lag is the unwarmed bullet and casing scenes.

### Additional Context: Why After Restarts It Stays Bad

The `_warmup_completed` flag in `ImpactEffectsManager` is `true` after the first warmup — so scene reloads do **not** re-run warmup. This is correct behavior for particle effects (they're already compiled). But since bullet/casing were never warmed up, every level start suffers from the first-shot stall.

---

## Technical Details

### Godot 4 Shader Compilation
Godot 4 compiles shaders just-in-time when a new visual element is first rendered:
- GPUParticles2D: compiles particle compute and render shaders
- Line2D with gradient: compiles gradient rendering shader
- First physics body: may trigger broadphase initialization

References:
- https://github.com/godotengine/godot/issues/34627 (Particles huge lag spike on first instance)
- https://github.com/godotengine/godot/issues/87891 (GPUParticles2D first-frame stall)
- https://forum.godotengine.org/t/particles-huge-lag-spike-on-first-instance/45839

### The Existing Warmup Pattern
The `impact_effects_manager.gd` warmup:
1. Instantiates each effect scene
2. Positions it at viewport center (must be on-screen for GPU to compile shaders)
3. Makes it nearly invisible (alpha = 0.01)
4. Sets z_index = -100 (behind everything)
5. Starts rendering/emission
6. Waits 3 frames for GPU compilation to complete
7. Removes warmup instances

---

## Proposed Solution

Add the **bullet scene** and **casing scene** to the `_warmup_particle_shaders()` function in `scripts/autoload/impact_effects_manager.gd`.

The fix should:
1. Load the bullet scene path (same as `Player.cs` uses: `res://scenes/projectiles/csharp/Bullet.tscn`)
2. Instantiate a bullet at viewport center with alpha = 0.01
3. Add to scene, wait 3 frames, remove
4. Do the same for the casing scene (`res://scenes/effects/Casing.tscn`)

This follows the exact same pattern used for MuzzleFlash warmup.

**Files to modify**:
- `scripts/autoload/impact_effects_manager.gd` — add bullet/casing warmup to `_warmup_particle_shaders()`

---

## Evidence Summary

| Time | Event | FPS |
|------|-------|-----|
| 11:27:52 | Warmup complete (7 effects) | - |
| 11:27:53 | Frame 60 (1s) — likely first shot | 17 fps |
| 11:28:04 | Frame 60 (1s) after restart — first shot | 7 fps |
| 11:28:10 | Frame 60 (1s) after restart — first shot | 10 fps |
| 11:28:30 | Frame 60 (1s) after restart — first shot + blood decals | 1 fps |
