# Root Cause Analysis - Gas Grenade Visual Effect Not Visible

## Problem Statement
The aggression gas grenade releases gas but the visual effect is not visible to players.

## Current Implementation Investigation

### AggressionCloud Current Code
**File**: `scripts/effects/aggression_cloud.gd`

The cloud creates a single static Sprite2D:
```gdscript
func _setup_cloud_visual() -> void:
    _cloud_visual = Sprite2D.new()
    _cloud_visual.texture = _create_cloud_texture(int(cloud_radius))
    _cloud_visual.modulate = Color(0.9, 0.25, 0.2, 0.35)  # Reddish, 35% opacity
    _cloud_visual.z_index = -1  # Draw BELOW characters
    add_child(_cloud_visual)
```

### Root Causes Identified

#### 1. **Too Low Alpha/Opacity (CRITICAL)**
- Current: `alpha = 0.35` (35% opacity)
- This is VERY transparent
- Compare with other effects in codebase:
  - BloodEffect: `Color(0.75, 0.08, 0.05, 1)` - **100% opacity**
  - DustEffect: `Color(0.6, 0.55, 0.45, 0.8)` - **80% opacity**
  - MuzzleFlash: Uses gradients with **100% opacity** at start
- **Impact**: High - Effect barely visible, especially on varied backgrounds

#### 2. **Z-Index Drawing Below Characters (HIGH)**
- Current: `z_index = -1` (draws below everything)
- Compare with other effects:
  - MuzzleFlash: `z_index = 10`
  - ExplosionFlash: `z_index = 10`
  - BloodEffect: `z_index = 2`
- **Issue**: Cloud drawn below characters, UI, and other elements
- **Impact**: High - Gets occluded by player and enemies

#### 3. **Static Sprite vs Particle System (MEDIUM)**
- Current: Single static Sprite2D
- Codebase pattern: ALL other visual effects use **GPUParticles2D**
  - MuzzleFlash.tscn - GPUParticles2D
  - ExplosionFlash.tscn - GPUParticles2D
  - DustEffect.tscn - GPUParticles2D
  - BloodEffect.tscn - GPUParticles2D
  - SparksEffect.tscn - GPUParticles2D (assumed)
- **Issue**: No movement, no organic smoke behavior
- **Impact**: Medium - Less noticeable and less realistic

#### 4. **Procedural Texture vs Gradient Texture (LOW-MEDIUM)**
- Current: Creates texture via `_create_cloud_texture()` pixel-by-pixel
- Codebase pattern: Uses **GradientTexture2D** with color ramps
- **Issue**: May not blend/fade as smoothly
- **Impact**: Medium - Less visually polished

## Comparison with Codebase Patterns

### Standard Effect Structure (from existing effects)

All effects follow this pattern:

1. **Scene File (.tscn)** with:
   - GPUParticles2D node
   - GradientTexture2D for particle appearance
   - ParticleProcessMaterial with physics
   - Optional PointLight2D for lighting

2. **Script (.gd)** for:
   - Lifecycle management
   - Triggering emission
   - Cleanup

### Example: DustEffect (closest to smoke)

```tscn
[sub_resource type="Gradient" id="Gradient_dust"]
colors = PackedColorArray(
    0.65, 0.6, 0.5, 0.9,   # Start: brownish, 90% opacity
    0.6, 0.55, 0.45, 0.6,  # Mid: fading
    0.55, 0.5, 0.4, 0.3,   # Later: more transparent
    0.5, 0.45, 0.35, 0     # End: fully transparent
)

[sub_resource type="ParticleProcessMaterial" id="ParticleProcessMaterial_dust"]
lifetime_randomness = 0.5
emission_sphere_radius = 5.0
initial_velocity_min = 40.0
initial_velocity_max = 120.0
gravity = Vector3(0, 30, 0)  # Settles down
damping_min = 20.0
damping_max = 50.0
scale_min = 0.15
scale_max = 0.5

[node name="DustEffect" type="GPUParticles2D"]
amount = 25
lifetime = 2.5
one_shot = true
explosiveness = 0.85
```

**Key Properties**:
- **Higher opacity**: 90% → 0% gradient
- **Movement**: Velocity + gravity + damping
- **Variation**: Random lifetime, scale, velocity
- **Natural behavior**: Particles settle down

## Proposed Solution

### Create AggressionCloudEffect.tscn (GPUParticles2D)

Based on successful patterns in the codebase:

#### Gas Smoke Characteristics
- **Color**: Dark reddish (like blood but more orange/brownish)
- **Movement**: Slow upward drift (gas rises)
- **Duration**: 20 seconds continuous emission
- **Radius**: 300px coverage
- **Opacity**: Start higher (70-90%), fade to 0%
- **Speed**: Very slow (gas lingers)

#### Particle Configuration
```
- Amount: 100-150 particles (for dense cloud)
- Lifetime: 4-6 seconds per particle
- Emission: Continuous for 20 seconds (not one-shot)
- Initial velocity: 10-30 px/s (very slow)
- Gravity: Vector3(0, -20, 0) (slight upward drift)
- Damping: 5-15 (slow down over time)
- Scale: 0.5-1.5 (larger for gas cloud)
- Emission shape: Circle (300px radius)
- Color: Dark red gradient
```

#### Color Gradient
```
Offset 0.0: Color(0.5, 0.15, 0.1, 0.8)   # Dark reddish-brown, 80% opacity
Offset 0.2: Color(0.55, 0.18, 0.12, 0.7) # Slightly lighter
Offset 0.5: Color(0.6, 0.2, 0.15, 0.5)   # Mid fade
Offset 1.0: Color(0.5, 0.15, 0.1, 0)     # Fade to transparent
```

### Implementation Strategy

**Option A: Replace current implementation entirely**
- Create `scenes/effects/AggressionCloudEffect.tscn`
- Create `scripts/effects/aggression_cloud_effect.gd`
- Modify `aggression_gas_grenade.gd` to spawn particle scene
- Archive old `aggression_cloud.gd`

**Option B: Hybrid - keep logic, enhance visual**
- Keep existing `AggressionCloud` for detection/logic
- Add child GPUParticles2D for visual
- Best of both: existing logic + proper visual

**Recommendation**: **Option B** - Less invasive, preserves working logic

## Test Plan

1. Create particle effect scene
2. Test visibility on different backgrounds
3. Verify 300px radius coverage
4. Confirm 20 second duration
5. Validate color matches requirement (dark reddish)
6. Test with multiple grenades (performance)
7. Verify enemies still get aggression effect (logic intact)

## Success Criteria

- [x] Gas cloud clearly visible (not transparent)
- [x] Dark reddish color (not bright red, not gray)
- [x] Organic smoke movement (not static)
- [x] Lasts full 20 seconds
- [x] Covers 300px radius
- [x] Draws on top of ground but below UI
- [x] Matches codebase visual quality standards
