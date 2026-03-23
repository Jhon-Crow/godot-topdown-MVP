# Case Study: Illusion Copies via Visual Effects (Issue #1353)

## Problem Statement

Issue #1353 requests replacing the clone-spawning approach for illusion copies
(from PR #1130) with a visual-effects-based approach. The original implementation
spawned real `Enemy` instances as illusion copies, which caused severe performance
issues (4-7 FPS) due to each clone having ~50+ child nodes with full AI, physics,
navigation, and component systems.

## Context: PR #1130 (Previous Approach)

PR #1130 introduced the Gas Mask Enemy with chemical grenades that spawned
`illusion_enemy.gd` instances. The performance fix in that PR attempted to:
- Strip non-essential child nodes from inner Enemy instances
- Recursively disable all processing callbacks on remaining descendants
- Null out freed component references to prevent crashes

Despite these optimizations, the approach was fundamentally expensive because
it instantiated full `Enemy` scenes and then tried to strip them down.

## Analysis of Root Cause

The performance issue stems from Godot's node architecture:
1. Each `Enemy.tscn` instantiation creates ~50+ nodes (CharacterBody2D, multiple
   Sprite2D, RayCast2D, NavigationAgent2D, CollisionShape2D, Area2D, etc.)
2. Even with `set_physics_process(false)`, many child components still ran
   `_process()` callbacks
3. `NavigationAgent2D` and `RayCast2D` nodes have internal processing overhead
4. The GDScript `_ready()` chain fires for all child nodes, triggering component
   initialization that is immediately discarded

## Solution: Visual-Only Illusion Effect

### Architecture

Instead of spawning real enemies and stripping them down, we create a lightweight
visual-only system:

```
IllusionEffect (Node2D, ~6 nodes total)
  |-- IllusionModel (Node2D)
  |     |-- Body (Sprite2D + illusion shader)
  |     |-- Head (Sprite2D + illusion shader)
  |     |-- LeftArm (Sprite2D + illusion shader)
  |     |-- RightArm (Sprite2D + illusion shader)
  |     |-- WeaponMount/WeaponSprite (Sprite2D + illusion shader)
  |-- IllusionHitArea (Area2D, for bullet detection)
        |-- HitCollisionShape (CollisionShape2D)
```

Compare with a real Enemy:
```
Enemy (CharacterBody2D, ~50+ nodes)
  |-- EnemyModel (Node2D with 5+ sprites)
  |-- CollisionShape2D
  |-- RayCast2D
  |-- NavigationAgent2D
  |-- HitArea (Area2D)
  |-- DebugLabel
  |-- BloodyFeetComponent
  |-- CasingPusher
  |-- (10+ dynamically added components)
```

### Key Design Decisions

1. **Sprite copying instead of scene instantiation**: We copy only the texture
   references and transform data from the original enemy's sprites, avoiding
   the entire Enemy initialization chain.

2. **Shader-based visual distinction**: The `illusion_clone.gdshader` applies a
   ghostly cyan-green tint with flickering, making illusions visually distinct
   from real enemies while using zero additional nodes.

3. **Phantom bullets**: Illusion copies fire "phantom" bullets (`is_phantom = true`)
   that only damage the player, not enemies. This is enforced in `bullet.gd`'s
   `_on_area_entered` with a simple group check.

4. **1 HP destruction**: Illusions have a lightweight `IllusionHitArea` that
   implements the same `on_hit()` interface as real enemies, allowing existing
   bullets to destroy them without any special handling.

5. **Chemical cloud as trigger**: The `ChemicalCloud` spawns illusions for ALL
   enemies on the map when the player is within the cloud radius, capped at 12
   total illusions globally.

### Performance Comparison

| Metric | Real Clone (PR #1130) | Visual Effect (This PR) |
|--------|----------------------|------------------------|
| Nodes per copy | ~50+ | ~8 |
| Per-frame callbacks | Many (components) | 1 (_physics_process) |
| NavigationAgent2D | Yes (disabled) | None |
| RayCast2D | Yes (disabled) | None |
| AI state machine | Yes (disabled) | None |
| Component initialization | Full then stripped | None |
| Memory per copy | High | Low |

### Components

| File | Purpose |
|------|---------|
| `scripts/shaders/illusion_clone.gdshader` | Ghostly visual shader |
| `scripts/effects/illusion_effect.gd` | Visual-only enemy copy |
| `scripts/effects/illusion_hit_area.gd` | Bullet detection for illusions |
| `scripts/effects/chemical_cloud.gd` | Gas cloud triggering illusions |
| `scripts/projectiles/chemical_gas_grenade.gd` | Grenade releasing chemical cloud |
| `scripts/components/gas_mask_grenade_component.gd` | Enemy component for throwing |
| `scenes/projectiles/ChemicalGasGrenade.tscn` | Grenade scene |

### Integration Points

- `scripts/objects/enemy.gd`: `is_gas_mask` export flag, component wiring,
  head sprite swap, combat-state grenade throw
- `scripts/projectiles/bullet.gd`: `is_phantom` flag, player-only damage check
- `scripts/ui/experimental_menu.gd`: Gas Mask Enemy spawner entry (item #15)
- `scripts/ui/enemies_table_menu.gd`: GasMask feature column

## References

- [Godot Forum: Sprite After-image](https://forum.godotengine.org/t/sprite-after-image-in-2d-game/78758)
- [Godot Shaders: Ghost tag](https://godotshaders.com/shader-tag/ghost/)
- Existing shader patterns in the codebase:
  - `invisibility_cloak.gdshader` (Predator-style ripple)
  - `force_field.gdshader` (translucent bubble)
  - `motion_trail.gdshader` (flame trail effect)
