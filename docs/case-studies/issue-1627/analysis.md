# Case Study: Issue #1627 — Snow Interaction on Winter Forest Map

## Issue Summary

**Title:** Add snow to the Winter Forest map
**Author:** Jhon-Crow
**Labels:** (none)
**Status:** Open

**Requirements (translated from Russian):**
1. Snow surface should have a subtle texture (bumps/unevenness) — not flat white
2. Player and enemy movement should leave footprints in the snow
3. Blood should stain and soak into snow (absorbed, not pooling into puddles); stained snow must NOT generate bloody footprints when stepped on
4. Blood footprint trails on snow should end sooner (fewer steps before disappearing)

## Existing Systems Relevant to This Issue

### 1. SnowEffect (`scripts/effects/snow_effect.gd`, `scenes/effects/SnowEffect.tscn`)
- Falling snowflake particle system (visual overhead snow)
- Already integrated in `WinterForestLevel.tscn`
- NOT related to the surface — this is atmospheric snow only

### 2. WinterForestLevel (`scenes/levels/WinterForestLevel.tscn`)
- Snow ground: a `ColorRect` named "Snow" with color `Color(0.88, 0.9, 0.93, 1)` (flat bluish-white)
- No texture, no shader, no surface interaction

### 3. BloodyFeetComponent (`scripts/components/bloody_feet_component.gd`)
- Tracks when characters step in blood → spawns `BloodFootprint` decals
- Key parameters: `blood_steps_count` (default 12), `step_distance` (30px), `initial_alpha` (0.8), `alpha_decay_rate` (0.06)
- Issue requirement: on snow, blood trails should end sooner → need `blood_steps_count` reduced on snow maps

### 4. BloodDecal (`scripts/effects/blood_decal.gd`)
- Persistent blood stains on floor
- Has `is_puddle` flag → characters stepping on puddles get `BloodyFeetComponent` triggered
- Issue requirement: blood on snow should NOT act as a puddle (no bloody footprints from blood on snow)

### 5. WaterBloodDiffusion (`scripts/effects/water_blood_diffusion.gd`)
- Template for non-puddle blood absorption (blood spreads/fades in water)
- Can serve as a reference for a `SnowBloodAbsorption` effect

### 6. Existing shaders (`scripts/shaders/realistic_water.gdshader`, etc.)
- The water shader shows the pattern: procedural noise-based texture applied via `ShaderMaterial` on a `ColorRect`
- Same approach can create a snow surface with bump texture

## Solution Design

### Component A: Snow Surface Shader (`scripts/shaders/snow_surface.gdshader`)
- Procedural noise to create gentle bumpiness on the snow plane
- Subtle blue-white color variation from noise
- No uniforms needed at runtime (static texture)

### Component B: SnowFootprint (`scripts/effects/snow_footprint.gd` + `.tscn`)
- Similar to `BloodFootprint` but renders as compressed snow (slightly darker/blue-grey indentation)
- Persistent decal, no fade (snow footprints stay until level reload)
- Spawned by `SnowFeetComponent` (see below)

### Component C: SnowFeetComponent (`scripts/components/snow_feet_component.gd`)
- Mirror of `BloodyFeetComponent` but for snow
- Triggers whenever character is on snow surface (always on Winter Forest map)
- Spawns `SnowFootprint` at step intervals
- Does NOT require stepping in anything — snow is always "stepable"

### Component D: SnowBloodAbsorption (`scripts/effects/snow_blood_absorption.gd`)
- Spawned when `BloodEffect` hits the snow surface (replaces or supplements `BloodDecal`)
- Renders as a blood-stained snow patch (red-tinted snow color)
- Does NOT add to `blood_puddle` group → no bloody footprints generated
- Slowly fades (absorbed into snow) over 15-20 seconds

### Integration Changes
1. WinterForestLevel: Apply snow surface shader to "Snow" `ColorRect`
2. WinterForestLevel: Add `SnowSurface` marker node (group "snow_surface") so `SnowFeetComponent` knows it's on snow
3. Player and Enemy: Add `SnowFeetComponent` (or configure via level script)
4. BloodyFeetComponent: Add `blood_steps_on_snow` export (default 6) reduced when on snow map
5. BloodEffect/BloodDecal: Check for snow surface → spawn `SnowBloodAbsorption` instead of standard puddle

## Implementation Priority

| Component | Priority | Notes |
|-----------|----------|-------|
| Snow surface shader | High | Requirement #1 — visual texture |
| SnowFootprint + SnowFeetComponent | High | Requirement #2 — player/enemy tracks |
| SnowBloodAbsorption | High | Requirement #3 — blood soaks snow |
| BloodyFeetComponent short trails | Medium | Requirement #4 — fewer blood steps |

## References
- Issue #1445: WaterBloodDiffusion — blood-in-water without puddle (close analogue)
- Issue #1548/1569: SnowEffect — falling snow particles (already in scene)
- Issue #407: BloodyFeetComponent performance fix (signal-based detection)
- Godot docs: ShaderMaterial on ColorRect, GPUParticles2D
