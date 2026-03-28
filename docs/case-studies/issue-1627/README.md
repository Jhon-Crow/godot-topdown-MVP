# Case Study: Snow Interaction System for Winter Forest Map (Issue #1627)

## Problem Statement

The Winter Forest level (`WinterForestLevel.tscn`) has a snow-covered ground rendered as a
plain `ColorRect` (`Color(0.88, 0.9, 0.93, 1)`) overlaid with a falling-snow particle effect
(`SnowEffect.tscn`). The issue requests realistic snow interaction:

1. **Snow surface texture** — slight visual unevenness/irregularities on the ground snow layer.
2. **Footprints in snow** — player and enemy movement should leave visible tracks.
3. **Blood absorbed by snow** — blood should recolor/stain the snow without forming a standing
   puddle. Stained snow must **not** create bloody footprints when stepped on.
4. **Faster bloody-footprint fade** — when walking through blood stains on snow, the blood
   trail on boots should disappear in fewer steps than on dry floor.

---

## Existing Systems Analysis

### Snow (particle layer)
- `scripts/effects/snow_effect.gd` — two-layer `GPUParticles2D` world-space emitter that
  tracks the camera center so new flakes always appear within the viewport.
- `scenes/effects/SnowEffect.tscn` — defines SnowFlakesLarge (80 particles, 2 s lifetime)
  and SnowFlakesSmall (120 particles, 2.5 s lifetime). Both use additive blend + fade-out
  gradient.

### Blood system
- `scripts/effects/blood_decal.gd` (`BloodDecal`) — persistent floor stain, `Sprite2D`,
  joins `blood_puddle` group, sets up `Area2D` with `CircleShape2D` so characters can detect
  it via signals. Supports optional auto-fade.
- `scripts/effects/blood_footprint.gd` (`BloodFootprint`) — individual boot print,
  `Sprite2D`, alpha set at spawn time. Alternates left/right textures
  (`assets/sprites/effects/boot_print_left.png`, `boot_print_right.png`).
- `scripts/components/bloody_feet_component.gd` (`BloodyFeetComponent`) — attached to any
  `CharacterBody2D`; detects `blood_puddle` areas via signals + throttled fallback; spawns
  footprints at `step_distance` intervals with decreasing alpha over `blood_steps_count`
  steps.

### Blood detection protocol
Blood puddles join the `"blood_puddle"` group and expose a `monitorable` `Area2D` on
collision layer 7 (bitmask 64). `BloodyFeetComponent` creates a `monitoring` `Area2D` on the
character and connects `area_entered`/`area_exited` signals.

---

## Root Cause

There is no snow-surface interaction system at all. The white `ColorRect` representing snow
is a purely passive visual element. No component detects characters walking over it, no
decal system marks footprints in snow, and the existing `BloodDecal` system spawns
interactive puddles that invite further bloody tracking — the opposite of what snow-absorbed
blood should do.

---

## Solution Design

### A. Snow Footprints — `SnowyFeetComponent`

Mirrors `BloodyFeetComponent` but detects proximity to the snow surface rather than blood
puddles. Because the entire Winter Forest floor is snow, detection is simpler: the component
is enabled/disabled by the level script rather than by area overlap. Footprints fade across
`snow_steps_count` steps (default 8, fewer than blood's 12) since snow shows lighter marks.

**Scene:** `SnowFootprint.tscn` — `Sprite2D` that re-uses the same boot-print textures
(white-tinted instead of red) and fades to invisible over its lifetime.

**Script:** `snow_footprint.gd` — identical interface to `BloodFootprint` but defaults to a
near-white tint, no `blood_puddle` group membership.

**Component:** `snowy_feet_component.gd` — attached alongside `BloodyFeetComponent` on each
character in the Winter Forest level. Spawns `SnowFootprint` instances at `step_distance`
intervals. Uses a separate scene path and tint so footprints are visually distinct from
bloody ones.

### B. Snow Blood Decal — `SnowBloodDecal`

Replaces `BloodDecal` for hits that occur on the Winter Forest snow ground. Key differences:

| Property | `BloodDecal` | `SnowBloodDecal` |
|----------|-------------|-----------------|
| `is_puddle` default | `true` | `false` |
| Group membership | `"blood_puddle"` | `"snow_blood_stain"` |
| Area2D monitorable | yes | no |
| Auto fade | optional | yes (30 s delay, 5 s fade) |
| Appearance | opaque red stain | semi-transparent, desaturated |

Because `SnowBloodDecal` does **not** join `"blood_puddle"`, `BloodyFeetComponent` never
detects it, so no bloody footprints propagate from blood-stained snow.

### C. Faster Bloody Footprints on Snow — `on_snow` flag in `BloodyFeetComponent`

A new exported bool `on_snow: bool = false` is added. When `true`, `blood_steps_count` is
halved (floored at 2) when the component first picks up blood. The Winter Forest level
script sets this flag after instantiating characters.

### D. Snow Surface Texture (visual irregularities)

The plain `ColorRect` snow layer is supplemented with a subtle `NoiseTexture2D`-based
`TextureRect` rendered at low opacity, giving the impression of uneven drifted snow without
requiring imported art assets. This is added directly in the `.tscn` scene.

---

## Files Changed / Added

| File | Change |
|------|--------|
| `scripts/effects/snow_footprint.gd` | **NEW** — `SnowFootprint` Sprite2D class |
| `scenes/effects/SnowFootprint.tscn` | **NEW** — scene for snow footprint decal |
| `scripts/components/snowy_feet_component.gd` | **NEW** — component spawning snow footprints |
| `scripts/effects/snow_blood_decal.gd` | **NEW** — `SnowBloodDecal`, blood absorbed by snow |
| `scenes/effects/SnowBloodDecal.tscn` | **NEW** — scene for snow blood stain decal |
| `scripts/components/bloody_feet_component.gd` | **MODIFIED** — `on_snow` flag for faster fade |
| `scripts/levels/winter_forest_level.gd` | **MODIFIED** — wires up new components |
| `scenes/levels/WinterForestLevel.tscn` | **MODIFIED** — adds SnowTexture layer; injects components |
| `tests/unit/test_snowy_feet_component.gd` | **NEW** — unit tests |
| `tests/unit/test_snow_blood_decal.gd` | **NEW** — unit tests |

---

## References

- Issue #1440 — Winter Forest level design (map size, layout, color palette)
- Issue #1571 — SnowEffect scene resource ordering (load_steps must match sub_resource count)
- Issue #1585 — Time-stop freeze for precipitation effects (process_mode approach)
- Issue #407 — BloodyFeetComponent performance fix (signal-based detection)
- `scripts/effects/blood_decal.gd` — reference implementation for decal pattern
- `scripts/components/bloody_feet_component.gd` — reference for footprint component pattern
