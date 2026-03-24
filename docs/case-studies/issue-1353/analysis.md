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

2. **Visually indistinguishable copies**: Illusion copies render with the original
   enemy's exact textures and materials — no shader tint or flickering. They are
   intentionally impossible to distinguish from real enemies, making the gas mask
   enemy's ability a true deception tool. Only a fade-out in the last 3s hints
   at which copies are about to expire.

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

## Bug Fix: Grenade Not Exploding (2026-03-23)

### Symptom
After the initial implementation, the Gas Mask Enemy's chemical grenade was thrown
but never exploded — the gas cloud was never spawned and no illusion copies appeared.
The game log showed "Chemical grenade thrown at..." but no subsequent "[ChemicalGasGrenade]
Gas released" or "[ChemicalCloud]" messages. FPS dropped to 2-3 FPS due to enemies
continuing to fire at the player while the grenade sat frozen.

### Root Cause
`gas_mask_grenade_component.gd` was setting `grenade.linear_velocity` directly after
adding the grenade to the scene tree, but `GrenadeBase._ready()` sets `freeze = true`
on initialization. This caused two problems:

1. **Grenade frozen in place**: With `freeze = true`, the RigidBody2D ignores all
   velocity/force changes. The grenade stayed at the enemy's position.
2. **Timer never activated**: `activate_timer()` was never called, so the 4-second
   fuse never started. The fallback auto-activation (line 180-184 of `grenade_base.gd`)
   only triggers when `freeze` transitions from true to false, but no code ever
   set `freeze = false`.

### Evidence from Game Log
- `game_log_20260323_051959.txt` (saved in `logs/`)
- Line 2576: `[GrenadeBase] Grenade created at (1652.18, 980.1863) (frozen)` — created frozen
- Line 2577: `[GasMaskGrenade] Chemical grenade thrown at (1394.439, 1156.662)` — component
  logged the throw, but no timer activation or unfreeze messages followed
- No "[ChemicalGasGrenade] Gas released" or "[ChemicalCloud]" log entries exist

### Fix
Updated `gas_mask_grenade_component.gd` `_throw_grenade()` to match the pattern used
by `enemy_grenade_component.gd` (line 416-427) and `grenadier_grenade_component.gd`
(line 348-358):

1. Call `grenade.activate_timer()` to start the fuse countdown
2. Call `grenade.throw_grenade(direction, distance)` which handles both unfreezing
   and velocity application
3. Fallback to manual `freeze = false` + `linear_velocity` if `throw_grenade()`
   method is not available

### Comparison with Working Components
```
# enemy_grenade_component.gd (working):
if grenade.has_method("activate_timer"):
    grenade.activate_timer()
if grenade.has_method("throw_grenade"):
    grenade.throw_grenade(dir, dist)

# gas_mask_grenade_component.gd (broken):
grenade.linear_velocity = direction * throw_speed   # <-- ignored, grenade is frozen
```

## Bug Fix: Grenade Throw Delay + Distinguishable Illusions (2026-03-23)

### Symptoms (reported by repo owner)
1. **Enemy doesn't throw grenade immediately** — noticeable delay from combat entry
   to the first chemical grenade throw.
2. **Illusion copies are distinguishable from originals** — the ghostly cyan-green
   shader tint and flickering made illusions easy to tell apart from real enemies.

### Root Cause Analysis

**Issue 1: Grenade throw delay**
The gas mask enemy only attempted to throw a grenade in `_transition_to_combat()`,
which fires once when entering COMBAT state. Several factors caused delays:
- `throw_delay = 0.4s` added a small wait before each throw
- `throw_cooldown = 4.0s` prevented retries after a failed first attempt
- `min_throw_distance = 275px` / `max_throw_distance = 600px` were too restrictive,
  causing `_can_throw()` to fail when the player was outside the narrow distance range
- No retry logic: if `_can_throw()` returned false at combat entry, the enemy NEVER
  retried until it re-entered COMBAT state (which requires losing and re-detecting player)

Evidence from game log `game_log_20260323_054448.txt`:
- GasMaskGrenadeComponent ready at 05:44:59
- First grenade thrown at 05:45:07 (8 seconds later)
- The enemy was in combat but out of throw range for most of that time

**Issue 2: Distinguishable illusions**
The `illusion_clone.gdshader` applied:
- Semi-transparency (opacity = 0.55)
- Cyan-green tint (tint_strength = 0.35)
- Flickering animation
- Edge glow effect

These visual effects made illusions obvious to distinguish from real enemies,
defeating the purpose of the illusion mechanic.

### Fix

**For throw delay:**
1. Added continuous grenade throw attempts in `_process_combat_state()` so the
   enemy keeps trying every frame while in combat (respects cooldown/conditions)
2. Reduced `throw_cooldown` from 4.0s to 1.0s
3. Reduced `throw_delay` from 0.4s to 0.1s (near-instant)
4. Expanded distance range: `min_throw_distance` 275→100px, `max_throw_distance` 600→900px

**For indistinguishable illusions:**
1. Removed shader material application — sprites are copied with original textures,
   colors, and materials, making illusions visually identical to real enemies
2. Only visual distinction is a fade-out in the last 3 seconds (using modulate alpha)
3. Retained `illusion_clone.gdshader` file for potential future use but no longer
   applied to illusion copies

### Game Log Files
- `logs/game_log_20260323_054321.txt` — first test session after grenade fix
- `logs/game_log_20260323_054448.txt` — second test session, longer gameplay

## References

- [Godot Forum: Sprite After-image](https://forum.godotengine.org/t/sprite-after-image-in-2d-game/78758)
- [Godot Shaders: Ghost tag](https://godotshaders.com/shader-tag/ghost/)
- Existing shader patterns in the codebase:
  - `invisibility_cloak.gdshader` (Predator-style ripple)
  - `force_field.gdshader` (translucent bubble)
  - `motion_trail.gdshader` (flame trail effect)
