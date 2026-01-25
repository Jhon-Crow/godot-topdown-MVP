# Case Study: Issue #343 - First Shot Lag When Hitting Enemy

## Issue Summary

**Title:** fix пролаг при первом выстреле во врага (fix lag on first shot at enemy)

**Description (translated):** On the first shot after entering the game (at the enemy), the game noticeably lags. After restarts, everything works fine.

**Repository:** Jhon-Crow/godot-topdown-MVP

## Timeline of Events

### Sequence of Events During First Shot at Enemy

1. **Player enters game** - Scene loads with preloaded effect scenes
2. **Player shoots bullet** - Bullet scene is instantiated (already preloaded, fast)
3. **Bullet hits enemy** - `_on_area_entered` triggers in `bullet.gd:330-361`
4. **Hit effects triggered** - `_trigger_player_hit_effects()` called in `bullet.gd:358-359`
5. **Blood effect spawned** - `ImpactEffectsManager.spawn_blood_effect()` called
6. **GPUParticles2D shader compilation** - **FIRST TIME LAG OCCURS HERE**
7. **HitEffectsManager triggered** - Saturation shader loaded
8. **Saturation shader compilation** - **ADDITIONAL LAG HERE**
9. **Game freezes** - Shader compilation blocks main thread

### Why Subsequent Shots Are Fast

After the first shot, all shaders are compiled and cached by the GPU. The GPU driver stores these compiled shaders in memory, so subsequent instantiations of the same particle effects use the already-compiled shaders.

## Root Cause Analysis

### Primary Cause: GPU Shader Compilation at Runtime

The root cause is **runtime shader compilation** of `GPUParticles2D` effects. Godot 4.x defers shader compilation until first use, causing noticeable frame stutters.

**Evidence from codebase:**

1. **BloodEffect.tscn (line 32):** Uses `GPUParticles2D` with `ParticleProcessMaterial`
2. **DustEffect.tscn (line 32):** Uses `GPUParticles2D` with `ParticleProcessMaterial`
3. **SparksEffect.tscn (line 32):** Uses `GPUParticles2D` with `ParticleProcessMaterial`

Each `ParticleProcessMaterial` generates a unique shader that must be compiled by the GPU driver the first time it's used.

### Secondary Cause: Screen Effect Shader

The `HitEffectsManager` loads a saturation shader (`saturation.gdshader`) which also requires compilation:

```gdscript
# hit_effects_manager.gd:56-63
var shader := load("res://scripts/shaders/saturation.gdshader") as Shader
if shader:
    var material := ShaderMaterial.new()
    material.shader = shader
    material.set_shader_parameter("saturation_boost", 0.0)
    _saturation_rect.material = material
```

### Affected Code Paths

1. **bullet.gd:607-610** - Triggers `_trigger_player_hit_effects()` when player bullet hits enemy
2. **impact_effects_manager.gd:215-264** - `spawn_blood_effect()` instantiates GPUParticles2D
3. **hit_effects_manager.gd:89-91** - `on_player_hit_enemy()` activates saturation shader

## Evidence from External Sources

### Godot Forum Discussion (Solved)
[Source: Godot Forum - Lag spike on first firing a bullet](https://forum.godotengine.org/t/solved-lag-spike-on-first-firing-a-bullet-in-debug/49725)

- Same symptoms: ~0.5s freeze on first shot, subsequent shots smooth
- Root cause: Shader compilation for particles
- One workaround: Changing renderer (but not ideal for production)

### Godot GitHub Issues

1. **Issue #34627** - Lag hiccup in first instance of preloaded scene with CPUParticles
   - Confirmed cause: "This is caused by shaders compiling" (Clay John, Godot team)

2. **Issue #87891** - GPUParticles first instance lag
   - Recommended fix: "Render at least one frame with the object(s) visible, hidden behind some loading screen"

3. **Proposal #1801** - PackedScene.instance() should not cause lag
   - Describes 40-60ms lag per instance for complex scenes
   - Proposed interactive instancing to spread load across frames

## Technical Details

### GPUParticles2D Shader Compilation

Each `GPUParticles2D` with a unique `ParticleProcessMaterial` generates a custom compute shader:

| Effect | Material Properties | Shader Complexity |
|--------|---------------------|-------------------|
| BloodEffect | 45 particles, gravity 450, damping 5-15 | Medium |
| DustEffect | 25 particles, gravity 30, damping 20-50 | Medium |
| SparksEffect | 15 particles, gravity 500, damping 10-30 | Medium |

### Screen Shader Compilation

The saturation shader uses `hint_screen_texture` which requires specific framebuffer setup:

```glsl
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
```

This type of shader requires coordination with the rendering pipeline, adding to compilation time.

## Solution: Warmup System

### Recommended Approach

Implement a **shader warmup system** that pre-renders all GPU-dependent effects off-screen during level loading. This forces shader compilation before gameplay begins.

### Implementation Strategy

1. **Create warmup manager** - An autoload that runs during scene initialization
2. **Pre-render all effects** - Instantiate each particle effect type once off-screen
3. **Trigger one emission cycle** - Force the GPU to compile shaders
4. **Clean up warmup instances** - Remove after shaders are cached

### Warmup Points in Code

The warmup should occur in:
- `ImpactEffectsManager._ready()` - After effect scenes are preloaded
- Before any gameplay starts (can be hidden behind loading screen)

### Implementation Code

```gdscript
# Add to impact_effects_manager.gd

## Performs warmup to pre-compile all particle shaders.
## Call this during loading to avoid first-hit stutters.
func warmup_effects() -> void:
    _log_info("Starting shader warmup...")

    # Create off-screen position for warmup
    var warmup_pos := Vector2(-10000, -10000)

    # Warmup each effect type
    var effects_to_warmup: Array[PackedScene] = [
        _dust_effect_scene,
        _blood_effect_scene,
        _sparks_effect_scene
    ]

    for scene in effects_to_warmup:
        if scene == null:
            continue

        var effect: GPUParticles2D = scene.instantiate() as GPUParticles2D
        if effect == null:
            continue

        effect.global_position = warmup_pos
        effect.emitting = true
        add_child(effect)

        # Wait one frame to ensure GPU processes the particles
        await get_tree().process_frame

        # Clean up
        effect.queue_free()

    _log_info("Shader warmup complete")
```

### For HitEffectsManager

The saturation shader warmup should happen in `_ready()`:

```gdscript
# Add to hit_effects_manager.gd after creating _saturation_rect

## Warmup the saturation shader by briefly showing and hiding the effect
func _warmup_saturation_shader() -> void:
    if _saturation_rect == null or _saturation_rect.material == null:
        return

    # Briefly enable to force shader compilation
    _saturation_rect.visible = true
    var material := _saturation_rect.material as ShaderMaterial
    if material:
        material.set_shader_parameter("saturation_boost", 0.0)

    # Wait one frame for GPU to process
    await get_tree().process_frame

    # Hide again
    _saturation_rect.visible = false
```

## Alternative Solutions

### 1. Use CPUParticles2D Instead

**Pros:**
- CPU-based, no shader compilation
- More consistent performance

**Cons:**
- Lower particle count capability
- Different visual appearance
- Previously tried and caused rendering issues (see issue-257)

### 2. Use Compatibility Renderer

**Pros:**
- May avoid some shader compilation issues

**Cons:**
- Reduced visual quality
- Not all GPUParticles2D features supported

### 3. Background Thread Shader Compilation

Godot 4.x has experimental support for background shader compilation, but it's not fully reliable yet.

## Testing the Fix

### Before Fix
1. Start game fresh
2. Shoot enemy
3. Observe ~0.5s freeze

### After Fix
1. Start game fresh
2. Wait for loading (warmup happens automatically)
3. Shoot enemy
4. No visible freeze

### Verification Steps
1. Add timing measurement to `spawn_blood_effect()`:
   ```gdscript
   var start_time := Time.get_ticks_msec()
   # ... spawn effect ...
   var elapsed := Time.get_ticks_msec() - start_time
   _log_info("Blood effect spawn took %d ms" % elapsed)
   ```
2. First shot should now show <5ms instead of 300-500ms

## References

### External Sources
- [Godot Forum - Solved: Lag spike on first firing a bullet](https://forum.godotengine.org/t/solved-lag-spike-on-first-firing-a-bullet-in-debug/49725)
- [Godot Forum - Particles huge lag spike on first instance](https://forum.godotengine.org/t/particles-huge-lag-spike-on-first-instance/45839)
- [Godot GitHub Issue #34627 - CPUParticles lag hiccup](https://github.com/godotengine/godot/issues/34627)
- [Godot GitHub Issue #87891 - GPUParticles first instance lag](https://github.com/godotengine/godot/issues/87891)
- [Godot Proposal #1801 - PackedScene.instance() lag](https://github.com/godotengine/godot-proposals/issues/1801)
- [Godot Docs - Fixing jitter, stutter and input lag](https://docs.godotengine.org/en/stable/tutorials/rendering/jitter_stutter.html)

### Codebase Files
- `scripts/autoload/impact_effects_manager.gd` - Effect spawning
- `scripts/autoload/hit_effects_manager.gd` - Hit feedback effects
- `scripts/projectiles/bullet.gd` - Bullet collision handling
- `scenes/effects/BloodEffect.tscn` - Blood particle effect
- `scenes/effects/DustEffect.tscn` - Dust particle effect
- `scenes/effects/SparksEffect.tscn` - Sparks particle effect
- `scripts/shaders/saturation.gdshader` - Screen saturation effect

## Conclusion

The first-shot lag is a well-documented Godot engine behavior caused by just-in-time shader compilation for GPUParticles2D effects. The recommended fix is implementing a warmup system that pre-compiles these shaders during level loading, before gameplay begins. This is a standard industry practice for GPU-intensive games.
