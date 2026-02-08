# Case Study: Issue #675 - Aggression Gas Grenade

## Issue Summary

**Title**: добавь гранату с газом агрессии (Add aggression gas grenade)
**Author**: Jhon-Crow
**Repository**: Jhon-Crow/godot-topdown-MVP

### Requirements (translated from Russian)

1. **Activation**: 4 seconds after activation (timer-based, like flashbang/defensive)
2. **Gas Cloud**: Releases a gas cloud slightly larger than the offensive grenade radius (>225px, using 300px)
3. **Enemy Behavior in Gas**:
   - Enemies inside the cloud begin perceiving other enemies as hostile
   - They attack each other
   - Attacked enemies perceive their aggressors as hostile and retaliate
4. **Effect Duration**: 10 seconds per enemy (refreshed if they touch the gas again)
5. **Gas Duration**: Cloud dissipates after 20 seconds

## Architecture Analysis

### Existing Grenade System

The codebase has a well-established grenade hierarchy:

| Grenade Type | Class | Trigger | Radius | Effect |
|---|---|---|---|---|
| Flashbang | FlashbangGrenade | 4s timer | 400px | Blindness (12s) + Stun (6s) |
| Frag (Offensive) | FragGrenade | Impact | 225px | 99 damage + 4 shrapnel |
| Defensive (F-1) | DefensiveGrenade | 4s timer | 700px | 99 damage + 40 shrapnel |

All grenades extend `GrenadeBase` which provides:
- Timer-based detonation (4s default)
- Physics-based throwing (velocity, friction, mass)
- Blink effect as timer expires
- Sound propagation on explosion/landing
- Group membership ("grenades") for avoidance

### Status Effects System

`StatusEffectsManager` (autoload) tracks effects per entity instance ID:
- Currently supports: Blindness, Stun
- Auto-expiration with duration
- Visual tint feedback (yellow=blind, blue=stun)
- Clean API: `apply_blindness(entity, duration)`, `is_blinded(entity)`

### Enemy AI Targeting

Current targeting is **player-only**:
- `_player` reference found via group "player"
- `_can_see_player` flag updated each frame via `_check_player_visibility()`
- `_aim_at_player()` rotates toward player
- `_shoot()` fires at `_player.global_position`
- No built-in NPC-to-NPC hostility

## Solution Design

### Approach: Minimal-Invasion Aggression System

The solution adds aggression as a new status effect while keeping changes minimal:

1. **AggressionGasGrenade** (new class extending GrenadeBase)
   - Timer-based (4s fuse), inherits all throwing mechanics
   - On explode: spawns a persistent AggressionCloud node
   - Grenade itself is destroyed; cloud persists 20s

2. **AggressionCloud** (new standalone Node2D)
   - Area2D with circular collision shape (300px radius)
   - Detects enemies entering/staying in cloud
   - Applies aggression effect (10s duration, refreshable)
   - Green gas visual effect
   - Self-destructs after 20 seconds

3. **StatusEffectsManager** modifications
   - New "aggression" effect type alongside blindness/stun
   - `apply_aggression(entity, duration)` / `is_aggressive(entity)`
   - Green tint visual (Color(0.5, 1.0, 0.5))
   - Tracks aggressor targets per entity

4. **Enemy.gd** modifications
   - New `_is_aggressive` flag (like `_is_blinded`, `_is_stunned`)
   - `_aggression_target` - enemy to attack when aggressive
   - Modified `_process_ai_state()` - when aggressive, target nearby enemies
   - Modified `_shoot()` - when aggressive, shoot at aggression target
   - `on_hit_with_info()` - when hit by aggressive enemy, become aggressive toward attacker

5. **GrenadeManager** registration
   - New `AGGRESSION` enum value
   - Scene path and metadata

### Key Design Decisions

- **Cloud as separate node**: Unlike instant-effect grenades, the gas persists. Spawning
  a separate node on explode is cleaner than keeping the grenade alive.
- **StatusEffectsManager integration**: Using the existing effect system ensures proper
  cleanup, visual feedback, and duration management.
- **Enemy targeting override**: Adding an aggression target directly to enemy.gd is the
  simplest approach. When `_is_aggressive`, the enemy uses `_aggression_target` instead
  of `_player` for all combat logic.
- **Retaliation mechanic**: When an enemy is hit and the attacker has an enemy instance ID,
  the victim becomes aggressive toward the attacker. This creates mutual hostility chains.

## Online Research

No existing Godot plugins or libraries specifically handle temporary faction switching.
This is a custom game mechanic that requires modifying the enemy AI directly. The general
pattern (temporary status effect + modified targeting) is a well-known game design pattern
seen in games like:
- **Dishonored** (Berserk darts)
- **BioShock** (Enrage plasmid)
- **Far Cry** (Rage syringes)

## Files Modified

| File | Change |
|---|---|
| `scripts/projectiles/aggression_gas_grenade.gd` | New grenade class |
| `scripts/effects/aggression_cloud.gd` | New persistent gas cloud |
| `scripts/components/aggression_component.gd` | Aggression targeting component (extracted from enemy.gd) |
| `scenes/projectiles/AggressionGasGrenade.tscn` | New grenade scene |
| `scripts/autoload/status_effects_manager.gd` | Add aggression effect |
| `scripts/objects/enemy.gd` | Minimal aggression integration (delegates to component) |
| `scripts/autoload/grenade_manager.gd` | Register new grenade type |
