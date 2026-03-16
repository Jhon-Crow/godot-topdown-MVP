# Case Study: Issue #1005 - Explosion Scorch Marks

## Issue Summary

**Title:** после взрыва гранаты должен оставаться след (After grenade explosion there should be a trail/mark)

**Description (translated):**
After a grenade explosion, there should remain a black mark on the floor:
- **Flashbang (светошумовая):** Size equal to the grenade itself, almost invisible
- **Offensive/Frag grenade (наступательная):** 2x larger, burnt mark
- **F-1/Defensive grenade (Ф-1):** 2x larger than offensive grenade

## Current Grenade System Analysis

### Grenade Types and Their Properties

| Grenade Type | Class | Effect Radius | Behavior |
|-------------|-------|---------------|----------|
| Flashbang | `FlashbangGrenade` | 400px | Timer-based (4s), blinds/stuns enemies |
| Frag (Offensive) | `FragGrenade` | 225px | Impact-triggered, 4 shrapnel, 99 damage |
| Defensive (F-1) | `DefensiveGrenade` | 700px | Timer-based (4s), 40 shrapnel, 99 damage |

### Scorch Mark Sizes (per requirements)

Based on the issue requirements:
- **Flashbang:** Size of the grenade itself (~16-20px radius), nearly invisible (low alpha)
- **Offensive/Frag:** 2x grenade size (~32-40px radius), burnt appearance
- **F-1/Defensive:** 2x offensive size (~64-80px radius), largest burnt mark

## Technical Approach

### Existing Infrastructure

The codebase already has similar persistent decal systems:
1. **BloodDecal** (`scripts/effects/blood_decal.gd`): Persistent blood stains on floor
2. **BulletHole** (`scripts/effects/bullet_hole.gd`): Persistent bullet holes on walls

Both use:
- `Sprite2D` as base node
- `GradientTexture2D` for radial gradient appearance
- Optional auto-fade functionality
- Z-index management for proper layering

### Implementation Plan

1. **Create ExplosionScorchMark effect:**
   - New scene: `scenes/effects/ExplosionScorchMark.tscn`
   - New script: `scripts/effects/explosion_scorch_mark.gd`
   - Use radial gradient texture (black/gray center fading to transparent)

2. **Scorch Mark Configuration:**
   - Configurable radius based on grenade type
   - Configurable alpha/visibility
   - Optional auto-fade for performance on older devices

3. **Integration Points:**
   - `grenade_base.gd`: Add base method `_spawn_scorch_mark()`
   - Each grenade type overrides with specific size/style
   - Or use ImpactEffectsManager for centralized spawning

### Visual Design

**Scorch Mark Gradient:**
- Center: Dark black/charcoal (RGB: 0.05, 0.05, 0.05)
- Mid: Gray with slight brown tint (RGB: 0.15, 0.12, 0.10)
- Edge: Transparent fade

**Alpha Values:**
- Flashbang: 0.15 (almost invisible)
- Frag: 0.6 (noticeable)
- F-1: 0.7 (prominent)

## Research Sources

- [Godot Decals Documentation](https://docs.godotengine.org/en/stable/tutorials/3d/using_decals.html)
- [Godot Forum: 3D World Damaging](https://forum.godotengine.org/t/3d-world-damaging-e-g-cuts-on-trees-burn-marks-from-an-explosion-etc/95549)
- [Godot Shaders: Explosion VFX](https://godotshaders.com/shader-tag/explosion/)

## Implementation Notes

For 2D top-down games like this project, using `Sprite2D` with `GradientTexture2D` is more appropriate than 3D Decals. This approach:
- Matches existing codebase patterns (BloodDecal, BulletHole)
- Simple and performant for 2D
- Easy to configure radius and opacity per grenade type
