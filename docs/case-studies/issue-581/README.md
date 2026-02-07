# Case Study: Issue #581 - Sniper Enemy Type

## Overview

**Issue:** [#581 - добавить новый тип врагов - снайпер](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/581)
**Type:** New Feature
**Priority:** Enhancement

## Requirements

### Sniper Enemy Specifications
1. **Weapon:** ASVK with red laser sight
2. **Positioning:** Stays in the farthest cover while maintaining ability to hit potential player positions
3. **Movement:** Does NOT approach the player; stays stationary in cover
4. **Intelligence:** Learns positions where the player was seen or is suspected to be
5. **Accuracy/Spread:**
   - Through 1 wall: 10 degrees spread (5 degrees each side)
   - Through 2 walls: 15 degrees spread
   - Direct line of sight at 2 viewports distance: 0 degrees (perfect accuracy)
   - Direct line of sight at 1 viewport distance: 3 degrees spread
   - Direct line of sight under 1 viewport distance: 5 degrees spread
6. **Rotation:** Very slow turning (same as player with ASVK)

### City Map Specifications
- Large map with uniform box-like buildings
- Contains 2 sniper enemies placed strategically

## Architecture Analysis

### Existing Systems to Leverage

#### Enemy AI System (`scripts/objects/enemy.gd`)
- Complete state machine with 11 states (IDLE, COMBAT, SEEKING_COVER, IN_COVER, etc.)
- Built-in cover detection via 16 raycasts
- Memory system (`EnemyMemory`) for tracking player position
- `PlayerPredictionComponent` for movement prediction
- Weapon configuration via `WeaponConfigComponent`
- Progressive spread system (Issue #516)

#### Player's ASVK Implementation (`Scripts/Weapons/SniperRifle.cs`)
- Hitscan shooting with wall penetration (up to 2 walls)
- Slow rotation (0.04x normal sensitivity = ~25x slower)
- Smoke tracer visual effect
- 12.7x108mm caliber (50 damage per hit)
- 5000px max range

#### Cover System (`scripts/components/cover_component.gd`)
- 16-directional raycast cover detection
- Distance-based scoring
- Hidden position preference weighting

### Design Decisions

1. **Extend existing enemy.gd** rather than creating a separate class
   - Add SNIPER weapon type (enum value 3) to WeaponType
   - Add sniper-specific behavior flags and overrides
   - Minimizes code duplication while leveraging existing tactical AI

2. **Hitscan shooting for sniper enemy** (GDScript implementation)
   - Similar to C# SniperRifle but adapted for enemy AI
   - Wall penetration counting with spread adjustment
   - Smoke tracer spawning via existing effect system

3. **Red laser sight** via Line2D
   - Always visible (not limited to Power Fantasy mode)
   - Red color to differentiate from player's blue laser

4. **Cover selection** biased toward maximum distance from player
   - Override cover scoring to prefer farthest positions
   - Only select cover with line-of-fire to player area

## Implementation Plan

### Phase 1: Weapon Configuration
- Add SNIPER (3) to WeaponType enum
- Add SNIPER config to WeaponConfigComponent
- Configure: slow fire rate, high damage, wall penetration

### Phase 2: Sniper AI Behavior
- Add sniper-specific state processing
- Override cover selection to prefer distant positions
- Implement slow rotation matching player ASVK
- Add hitscan shooting with wall penetration
- Implement distance/wall-based spread system
- Add red laser sight

### Phase 3: City Map
- Create large map with grid-like building layout
- Place 2 sniper enemies in strategic positions
- Setup navigation mesh for pathfinding

## References

- ASVK rifle: Russian anti-materiel rifle, 12.7x108mm caliber
- Existing player ASVK implementation: `Scripts/Weapons/SniperRifle.cs` (1796 lines)
- Enemy AI base: `scripts/objects/enemy.gd` (3878 lines)
- Weapon configs: `scripts/components/weapon_config_component.gd`
