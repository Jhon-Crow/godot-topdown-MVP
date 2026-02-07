# Case Study: Issue #574 — Enemies Should Detect Player by Flashlight

## Overview

- **Issue**: [#574](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/574) — враги должны определять, где игрок находится по фонарику
- **PR**: [#587](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/587)
- **Date**: 2026-02-07
- **Severity**: Feature request (AI enhancement)
- **Status**: Implementation

## Issue Description

The owner requested two new enemy AI behaviors related to the player's flashlight:

1. **Flashlight-based detection**: When an enemy sees the player's flashlight beam, they should immediately determine the player's approximate location (at least the direction the light is shining from)
2. **Lit passage avoidance**: Enemies should not enter a passage illuminated by the player's flashlight if there's an alternative route to the room containing the player

Both behaviors must be integrated into the existing GOAP (Goal-Oriented Action Planning) system.

## Research: Flashlight Detection in Games

### Industry Approaches

| Game | Detection Method | Key Insight |
|------|-----------------|-------------|
| **Splinter Cell: Blacklist** | Multi-bone raycasting + visibility meter + TEAS positional nodes | Tactical Environment Awareness System tracks light states with timestamps |
| **Thief: The Dark Project** | Light gem (player visibility indicator) + light mapping surface cache | 18-month iteration to get the feedback loop right for stealth |
| **Alien: Isolation** | 4 distinct view cones (normal, focused, peripheral, close) | Flashlight dangerous for sound, not light (for xenomorph); humans do react to light |
| **Metal Gear Solid V** | Reduced vision range in darkness + dynamic AI adaptation | Enemies equip flashlights/NVGs if player frequently operates at night |
| **F.E.A.R.** | GOAP-based action planning with avoidance behaviors | Demonstrated GOAP planners naturally handle avoidance via cost functions |

### Detection Algorithm: Dot Product Cone Test

The standard approach for flashlight-to-enemy detection uses the **dot product cone test**:

```
# Is the enemy within the flashlight beam?
direction_to_enemy = (enemy_pos - flashlight_origin).normalized()
dot = flashlight_direction.dot(direction_to_enemy)
is_in_beam = dot > cos(beam_half_angle)
```

Combined with:
1. **Line-of-sight verification** via RayCast2D (light doesn't pass through walls — already handled by shadow_enabled=true)
2. **Distance attenuation** using inverse square law
3. **Back-tracing**: Enemy infers player position as the beam origin (flashlight_origin)

### Passage Avoidance

Two main approaches exist:

1. **Influence map / weighted pathfinding**: Assign higher navigation costs to lit areas, making the GOAP planner prefer alternative routes
2. **GOAP action with preconditions**: Add an `AvoidFlashlightAction` that activates when a passage is lit, with effects that route the enemy through alternative paths

For this project, the GOAP approach is most appropriate since the codebase already uses GOAP planning.

### Relevant Godot 4 Capabilities

- `PointLight2D` with `shadow_enabled` already prevents light through walls
- `NavigationAgent2D` supports weighted pathfinding via navigation layers
- `RayCast2D` for line-of-sight checks (already used extensively in enemy.gd)
- Dot product math via `Vector2.dot()` for cone intersection tests

## Codebase Analysis

### Existing Systems Leveraged

| Component | File | Role in Solution |
|-----------|------|-----------------|
| GOAP Planner | `scripts/ai/goap_planner.gd` | Plans action sequences using A* search |
| Enemy Actions | `scripts/ai/enemy_actions.gd` | 20+ GOAP actions — new actions added here |
| Enemy Memory | `scripts/ai/enemy_memory.gd` | Confidence-based position tracking — flashlight adds 0.75 confidence |
| Flashlight Effect | `scripts/effects/flashlight_effect.gd` | PointLight2D with 18° beam, shadow-enabled |
| Player | `scripts/characters/player.gd` | Flashlight equipped via ActiveItemManager |
| Sound Propagation | `scripts/autoload/sound_propagation.gd` | Pattern for sensory detection — flashlight follows similar architecture |
| Grenade Avoidance | `scripts/components/grenade_avoidance_component.gd` | Architectural template for avoidance behavior |

### Architecture Decision

Following the component-based pattern established by `GrenadeAvoidanceComponent` and `VisionComponent`, the flashlight detection is implemented as a new `FlashlightDetectionComponent` that:

1. **Detects** if the enemy can see the flashlight beam (cone intersection + LOS)
2. **Estimates** the player's position from the beam origin
3. **Updates** enemy memory with flashlight-based confidence (0.75)
4. **Provides** passage lighting data for GOAP avoidance actions

### New GOAP Actions

| Action | Precondition | Effect | Cost |
|--------|-------------|--------|------|
| `InvestigateFlashlightAction` | `flashlight_detected: true`, `player_visible: false` | `is_pursuing: true` | 1.3 (high priority) |
| `AvoidFlashlightPassageAction` | `passage_lit_by_flashlight: true`, `has_alternate_route: true` | `avoided_lit_passage: true` | 2.0 |

## Implementation Details

### FlashlightDetectionComponent

Core detection logic:
- **Cone intersection test**: Uses dot product to check if enemy position falls within the flashlight beam cone (18° total, 9° half-angle)
- **LOS verification**: RayCast2D ensures no walls block the beam from reaching the enemy
- **Distance limit**: Detection limited to `LIGHT_TEXTURE_SCALE * 100` pixels (600px effective range matching visual beam)
- **Back-tracing**: When beam is detected, the flashlight origin position (player weapon barrel) is used as the suspected player position
- **Confidence**: Flashlight detection provides 0.75 confidence (between gunshot at 0.7 and visual at 1.0)

### Passage Avoidance Logic

When the flashlight illuminates a passage/doorway:
1. Enemy checks if the beam covers the passage it would traverse
2. If alternative navigation path exists (different door to the same room), increase the cost of traversing the lit passage
3. The GOAP planner naturally selects the alternative route due to lower cost

## Sources

- [Bringing Balance to Stealth AI in Splinter Cell: Blacklist — Game Developer](https://www.gamedeveloper.com/design/bringing-balance-to-stealth-ai-in-splinter-cell-blacklist)
- [Modeling AI Perception and Awareness in Splinter Cell: Blacklist — GDC Vault](https://www.gdcvault.com/play/1020195/Modeling-AI-Perception-and-Awareness)
- [Building the original Thief's revolutionary stealth system — Game Developer](https://www.gamedeveloper.com/design/building-the-original-i-thief-s-i-revolutionary-stealth-system)
- [Revisiting the AI of Alien: Isolation — Game Developer](https://www.gamedeveloper.com/design/revisiting-the-ai-of-alien-isolation)
- [Building the AI of F.E.A.R. with GOAP — Game Developer](https://www.gamedeveloper.com/design/building-the-ai-of-f-e-a-r-with-goal-oriented-action-planning)
- [Stanford — Movement Costs for Pathfinders](http://theory.stanford.edu/~amitp/GameProgramming/MovementCosts.html)
- [Godot Engine — 2D Navigation Overview](https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_introduction_2d.html)
- [Godot Engine — Vector Math Documentation](https://docs.godotengine.org/en/stable/tutorials/math/vector_math.html)
