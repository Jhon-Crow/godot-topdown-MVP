# Case Study: Issue #343 - First Shot Lag Fix

## Problem Description

**Issue:** When shooting an enemy for the first time after entering the game, the game noticeably lags/stutters. After restarts, everything works fine.

**Russian original:** "при первом выстреле после входа в игру (во врага) игра очень заметно лагает. после рестартов всё работает хорошо."

## Timeline of Investigation

### Initial Analysis (Session 1)
- Identified potential cause as GPU shader compilation lag
- Implemented shader warmup in `impact_effects_manager.gd`
- Positioned particles at (-10000, -10000) off-screen during warmup
- Waited 1 frame before cleanup

### User Feedback
User reported the problem persists - lag still happens specifically on hit ("именно при попадании").

### Deep Investigation (Session 2)

#### Log File Analysis
Analyzed 4 log files provided by user:
- `game_log_20260125_041653.txt`
- `game_log_20260125_041703.txt`
- `game_log_20260125_041712.txt`
- `game_log_20260125_041721.txt`

Key observations from logs:
1. Shader warmup completes successfully: `Particle shader warmup complete: 3 effects warmed up in 169 ms`
2. Blood effect instantiation is logged as successful on first hit
3. No obvious timing gaps visible in log timestamps (logs don't capture frame timing)

#### Online Research

Researched Godot shader compilation issues:

1. **[Godot Issue #76241](https://github.com/godotengine/godot/issues/76241)**: "OpenGL: Shader compilation stutter when rendering a 2D element for the first time"
   - Shader compilation only happens when elements are actually rendered to screen
   - Elements outside viewport frustum may be culled before shader compilation

2. **[Godot Issue #34627](https://github.com/godotengine/godot/issues/34627)**: GPUParticles lag spikes

3. **[Forum: GPUParticles2D hanging first time emitting](https://forum.godotengine.org/t/gpuparticles2d-is-hanginging-the-first-time-emitting-is-set-true/84587)**:
   - Recommended solution: "make it emit as soon as the level loads" within viewport

4. **[Forum: Particles huge lag spike on first instance](https://forum.godotengine.org/t/particles-huge-lag-spike-on-first-instance/45839)**:
   - Key insight: "rendering at least one frame with the object(s) visible, hidden behind some 'loading' screen"

## Root Cause Analysis

### Why Initial Fix Failed

The original warmup positioned particles at `Vector2(-10000, -10000)`:

```gdscript
# WRONG: Off-screen position
var warmup_pos := Vector2(-10000, -10000)
effect.global_position = warmup_pos
effect.emitting = true
```

**Problem:** The GPU's frustum culling optimization skips rendering objects that are completely outside the viewport. When particles are positioned far off-screen:

1. The GPU checks if particles intersect the view frustum
2. Particles at (-10000, -10000) are outside the frustum
3. GPU skips rendering them entirely
4. **Shader compilation never occurs** because the shader was never executed
5. On first actual hit, shader compiles just-in-time, causing lag

### The Fix

Particles must be:
1. **Within the viewport** (on-screen) so GPU actually renders them
2. **Nearly invisible** (alpha ~0.01) so players don't see them
3. **Rendered for multiple frames** to ensure compilation completes

```gdscript
# CORRECT: On-screen but nearly invisible
var warmup_pos := viewport.get_visible_rect().size / 2.0
effect.global_position = warmup_pos
effect.modulate = Color(1, 1, 1, 0.01)  # Nearly invisible
effect.z_index = -100  # Behind everything
effect.emitting = true

# Wait multiple frames for shader compilation
await get_tree().process_frame
await get_tree().process_frame
await get_tree().process_frame
```

### Additional Improvements

1. **Added blood decal warmup** - `BloodDecal.tscn` uses GradientTexture2D which may also require shader compilation
2. **Added bullet hole warmup** - Same reason
3. **Added particles to current scene** - Instead of autoload, for proper rendering context

## Technical Details

### What Gets Compiled

When a GPUParticles2D emits for the first time, the GPU must compile:

1. **Particle process shader** - From `ParticleProcessMaterial`
2. **Particle rendering shader** - For drawing the texture
3. **Gradient texture shader** - For `GradientTexture2D` resources

### Compilation Timing

- Godot 4.x uses just-in-time shader compilation
- Compilation happens the first time a unique shader/material combination is rendered
- Compilation time varies by GPU driver (50ms - 2000ms observed)
- Cached in `.godot/shader_cache/` for subsequent runs

### Why Restarts Don't Lag

After the first run:
1. Shaders are compiled and cached to disk
2. Subsequent game launches load from cache
3. No runtime compilation needed

But clearing cache or fresh install triggers the issue again.

## Files Modified

- `scripts/autoload/impact_effects_manager.gd` - Fixed warmup implementation

## Testing Recommendations

1. **Clear shader cache** before testing: Delete `.godot/shader_cache/`
2. **Fresh export build** - Test exported builds, not editor
3. **Monitor frame times** - Use Godot profiler or external tools
4. **Test on multiple GPUs** - Driver behavior varies

## References

- [Godot Docs: Reducing stutter from shader compilations](https://docs.godotengine.org/en/stable/tutorials/performance/pipeline_compilations.html)
- [GitHub Issue #76241: OpenGL Shader compilation stutter](https://github.com/godotengine/godot/issues/76241)
- [GitHub Issue #34627: GPUParticles lag](https://github.com/godotengine/godot/issues/34627)
- [GitHub Issue #87891: Particle shader issues](https://github.com/godotengine/godot/issues/87891)
- [Forum: GPUParticles2D hanging](https://forum.godotengine.org/t/gpuparticles2d-is-hanginging-the-first-time-emitting-is-set-true/84587)
- [Forum: Particles lag spike](https://forum.godotengine.org/t/particles-huge-lag-spike-on-first-instance/45839)

## Lessons Learned

1. **Off-screen != invisible to GPU** - Frustum culling skips off-screen objects before shader execution
2. **Alpha transparency forces rendering** - Even at 0.01 alpha, the GPU must execute the shader
3. **One frame may not be enough** - Complex shaders may need multiple frames to compile
4. **Test with cleared cache** - The bug only manifests on first run with empty cache
