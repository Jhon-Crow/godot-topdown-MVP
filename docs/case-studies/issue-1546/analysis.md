# Issue #1546 Case Study: Fix Rain Effect

## Requirements (from issue)
1. Make streaks (falling drops) **longer**
2. Circles (splash ripples) must appear **at the location where streaks disappear** (to look like a complete drop animation)
3. Rain should **not follow the player**, but should cover the entire Docks map (except buildings)

## Current Implementation Analysis

### RainEffect.tscn
- `CanvasLayer` at layer=5 — renders in screen space, NOT world space
- `RainStreaks` at `Vector2(640, 360)` (screen center)
  - Emits particles in a 1280x720 box around screen center
  - `radial_velocity_min=-140, radial_velocity_max=-80` — inward toward center
  - Streak texture: 2x6 pixels, scale 0.8–1.5
  - Lifetime: 0.15s
- `RainSplashes` at `Vector2(640, 360)` (screen center)
  - Emits in full 360° spread

### Problems
1. **Streaks too short**: texture is only 6px tall, needs to be larger
2. **Splash alignment**: With inward radial velocity, streaks START at random positions in the emission box and move TOWARD center (640,360). So they end near center — splash at center is geometrically correct. But visually, they disappear at many different points near center, not exactly at the same spot.
3. **Screen space vs World space**: CanvasLayer renders over screen, so rain IS always visible. But the issue says it should cover the whole map, not follow the player. The problem is that with screen-space particles, when the player moves, the rain appears to "scroll" with the camera, so particles that spawn on one side of the screen can disappear off the other side. This gives the impression rain follows the player.

## Solution Design

### Fix 1: Longer streaks
- Increase streak texture height from 6 to 16 pixels
- Increase scale range: 1.0–2.5 (was 0.8–1.5)
- This makes each drop visually longer

### Fix 2: Splash at streak endpoint
- With inward radial_velocity: streaks START at random positions in emission_box (1280x720) and converge toward center (640,360)
- Average streak travel: radial_velocity=-110 (avg), lifetime=0.15s → travel ≈ 16.5px inward
- Streaks don't fully reach center in 0.15s — they end partway along the inward path
- The splash emitter should be at the SAME center (640,360) with the emission box matching where streaks end
- Actually the best approach: splash emission box should be slightly smaller than streak emission box, because streaks moved ~16.5px inward from their spawn position
- OR: make splash follow the streaks by using a smaller emission box offset by radial travel

### Fix 3: World-space rain over entire Docks map
- **Approach A (World-space particles)**: Remove CanvasLayer, place particles in world space. Emission box = entire Docks map (5000x4000). Pro: true world-space coverage. Con: need 1000s of particles to fill 5000x4000px, too expensive.
- **Approach B (Large screen-space with fixed emitter)**: Keep CanvasLayer but make emission box larger so particles appear to come from outside screen. Already done, but doesn't fix "follows player" feeling.
- **Approach C (Fixed-world, camera-following emitter position)**: Keep CanvasLayer but update emitter position each frame to track the camera. This way, particles always emit around the camera center, covering the visible area. Rain appears stationary relative to the world because the emission box is always centered on the camera.
- **Approach D (World-space, dynamic emission around camera)**: Remove CanvasLayer, put GPUParticles2D in world space but update their position to match camera each frame, with large emission box.

**Selected: Keep CanvasLayer (screen space) but the emitter already covers the screen**. The real issue is that in the current screen-space setup, rain already covers the screen. The "follows player" complaint is about visual perception — when the player moves, the existing particles on screen don't move with the camera, so they visually slide off screen. This actually is the correct behavior for world-space rain!

Actually re-reading the Godot docs: `CanvasLayer` renders at a fixed position relative to the viewport. Since the emitter is at `Vector2(640, 360)` (screen center), particles spawn in screen space. When the camera moves, the particles stay fixed on screen. This IS correct for a rain effect that covers the screen.

The issue says "rain should not follow the player" — maybe the current behavior has the rain following the player in world space somehow? Let me reconsider.

Actually the current setup IS screen-space, so it already doesn't follow the player in world-space. But visually it always looks like a rain column following the player. The request might be asking for rain to be spread across the whole map in world space, so when the player is at one corner, they see rain only where it's raining, and when indoors they see no rain.

**Final interpretation**: Switch from screen-space CanvasLayer to world-space particles. The emission box must be huge (covering the entire map) but this is impractical. Instead, use a large emission box in world space centered on the camera, so rain appears to come from all directions without being anchored to the player's movement pattern.

**Practical solution**: Keep the CanvasLayer for rendering (so rain renders on top of everything), but change the particle system so that:
- Emission box covers a large area (already 1280x720)
- Rain moves straight down (not radially) so it doesn't look anchored to screen center
- The CanvasLayer approach already means rain doesn't move with world

For world-space coverage: The current CanvasLayer IS correct. The rain already covers the screen. The "not follow the player" requirement might mean the rain should use straight downward streaks instead of radial (which looks like rain swirling around the player center).

**Revised fix**:
1. Keep CanvasLayer
2. Change streaks from radial inward to straight downward (direction=(0,1,0))
3. Emission box = full screen + margin
4. Splash emitter: particles spawn at same position as where streaks land (bottom of screen)
5. Longer streaks: bigger texture + higher scale
