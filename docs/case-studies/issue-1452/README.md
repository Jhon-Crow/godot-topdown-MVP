# Case Study: Update Level Editor — Add Placeable Objects (Issue #1452)

## Problem Statement

The level editor (Issue #1442, PR #1443) supports walls, enemies, cover objects, and player spawn. The user requested adding more placeable objects:
1. Trees (like the Winter Forest level from PR #1441)
2. Various light sources
3. Decorative objects (rocks, stumps, logs, etc.)

## Research

### Winter Forest Tree Implementation (PR #1441)

The Winter Forest level demonstrates trees with two components:
- **Trunk**: StaticBody2D (collision_layer=4) with LightOccluder2D — provides physical cover and blocks light
- **Crown**: Polygon2D at z_index=10 with semi-transparent color — overlays and visually hides characters underneath

Key properties from Winter Forest:
- Trunk sizes: 40x40 px (typical)
- Crown radii: 44–56 px
- Trunk colors: brown tones (0.33–0.37, 0.23–0.27, 0.16–0.20)
- Crown colors: green with alpha 0.55 (e.g., Color(0.2, 0.35, 0.2, 0.55))

### Existing Light Sources in Codebase

Several levels use PointLight2D:
- **CityLevel**: Urban lighting with point lights
- **DecadenceLevel**: Neon-colored gradient lights
- **FlashlightEffect**: PointLight2D with shadow_enabled, energy 8.0, warm white color
- **MuzzleFlash/ExplosionFlash**: Temporary light effects

Common light pattern: PointLight2D with GradientTexture2D (radial fill), configurable energy, color, shadow.

### Hotline Miami 2 Editor Reference

HM2's editor includes placeable:
- Furniture (tables, desks, shelves)
- Environmental objects (plants, barrels, crates)
- No built-in tree or light placement (these are level-specific)

## Solution Design

### New Object Types

#### Trees (4 types)
| Type | Trunk Size | Crown Radius | Visual Style |
|------|-----------|--------------|--------------|
| Oak | 40x40 | 56 | Dark brown trunk, green crown |
| Pine | 32x32 | 44 | Darker trunk, deeper green crown |
| Birch | 24x36 | 48 | Light/white trunk, yellow-green crown |
| Dead | 36x36 | 0 | Gray-brown trunk, no crown |

Each tree trunk is a StaticBody2D with collision and LightOccluder2D. Live trees have a semi-transparent Polygon2D crown at z_index=10 that hides characters underneath — matching the tactical concealment mechanic from the Winter Forest level.

#### Light Sources (5 types)
| Type | Color | Energy | Radius | Shadows |
|------|-------|--------|--------|---------|
| Street Lamp | Warm white | 1.5 | 256 | Yes |
| Campfire | Orange | 2.0 | 192 | Yes |
| Spotlight | Bright white | 3.0 | 320 | Yes |
| Ambient | Cool blue | 0.8 | 400 | No |
| Neon | Pink/magenta | 2.5 | 200 | No |

Each creates a PointLight2D with a radial GradientTexture2D and optional shadow casting.

#### Decorations (6 types)
| Type | Size | Has Collision | Visual |
|------|------|--------------|--------|
| Rock | 40x32 | Yes | Gray-brown |
| Stump | 32x32 | Yes | Dark brown |
| Log | 80x24 | Yes | Medium brown |
| Bush | 48x40 | No | Semi-transparent green |
| Small Crate | 32x32 | Yes | Tan/brown |
| Trash | 24x24 | No | Dark gray |

### Data Format (v2)

The LevelData format version was bumped from 1 to 2. New arrays are added:
- `trees`: `[{"x", "y", "type"}]`
- `lights`: `[{"x", "y", "type", "color", "energy", "radius"}]`
- `decorations`: `[{"x", "y", "type"}]`

v1 levels load gracefully with empty arrays for new fields.

### Editor UI Changes

- Tools 6/7/8 repurposed: Tree [6], Light [7], Decor [8] (was Select [6])
- Dynamic subtype selector panel changes based on selected tool
- Eraser tool updated to erase all new object types

## Alternatives Considered

### Sprite-based Objects
Using actual sprite textures instead of ColorRect/Polygon2D primitives. Rejected because the project's editor creates levels programmatically without depending on specific sprite assets, keeping levels portable via JSON.

### Single "Object" Tool with Categories
One generic placement tool with a category dropdown. Rejected in favor of dedicated tools because each object type has different properties (trees have crowns, lights have energy/radius, etc.).

## Testing

- Unit tests for LevelData v2 serialization (trees, lights, decorations)
- Backward compatibility test for v1 levels
- Roundtrip JSON serialization tests for all new object types
- Editor tool selection and placement tests
