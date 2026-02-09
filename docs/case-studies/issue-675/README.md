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

## Owner Feedback & Bug Fixes (PR #687 Review)

The repo owner (Jhon-Crow) identified several visual/behavioral issues in the initial implementation:

> "Визуально и значок и моделька газовой выглядит так же как светошумовая и взрывается так же, а должна не взрываться, а выпускать облако красноватого газа."
> (Translation: "Visually both the icon and the gas grenade model look the same as the flashbang and it explodes the same way, but it should not explode — it should release a reddish gas cloud.")

### Root Causes Identified

1. **Sprite too similar to flashbang**: Both used simple green-tinted circles (~16x16).
   - **Fix**: Created a distinct dark red/maroon canister sprite with metallic top.

2. **Explosion-like blink effect**: `GrenadeBase._update_blink_effect()` made the grenade blink green/white as the timer counted down — identical to explosive grenades.
   - **Fix**: Overrode `_update_blink_effect()` with a smooth reddish pulse that intensifies as gas release approaches (sinusoidal, not blinking).

3. **PowerFantasy explosion triggered**: `GrenadeBase._explode()` called `PowerFantasyEffectsManager.on_grenade_exploded()` which triggered an explosion visual shockwave effect.
   - **Fix**: Overrode `_explode()` to skip the PowerFantasy effect entirely.

4. **Casing scatter on gas release**: `_on_explode()` called `_scatter_casings()` which scattered casings like a real explosion.
   - **Fix**: Removed `_scatter_casings()` call from `_on_explode()`.

5. **Gas cloud was green instead of reddish**: Cloud visual used `Color(0.3, 0.9, 0.3, 0.35)` (green).
   - **Fix**: Changed to `Color(0.9, 0.25, 0.2, 0.35)` (reddish).

6. **Enemy aggression tint was green**: `StatusEffectsManager` applied `Color(0.5, 1.0, 0.5, 1.0)` (green) tint.
   - **Fix**: Changed to `Color(1.0, 0.5, 0.45, 1.0)` (reddish) to match gas color.

### Timeline

1. Initial implementation: Green gas cloud, green tints, explosion-like behavior
2. Owner feedback #1: Visual colors should be reddish, not green
3. Fix iteration #1: Reddish color scheme, distinct canister sprite, gas-release behavior
4. Owner feedback #2 (2026-02-09): Grenade still explodes like flashbang, applies blindness/stun instead of aggression. Requested specific anger mark icon for aggression status
5. Root cause analysis: C# `GrenadeTimer.cs` only knows `Flashbang` and `Frag` types — AggressionGas defaults to Flashbang behavior
6. Fix iteration #2: Added `AggressionGas` enum to C# GrenadeTimer, Player.cs, and GrenadeTimerHelper.cs. C# defers to GDScript for gas release. Added anger mark animation to StatusEffectAnimationComponent

### Root Cause Analysis (Bug: Grenade Acts Like Flashbang)

**Symptom**: AggressionGasGrenade explodes with flashbang visual, applies blindness (12s) and stun (6s) instead of spawning gas cloud.

**Evidence from game logs** (`game_log_20260209_040549.txt`, `game_log_20260209_040720.txt`):
```
[GrenadeTimer] Applying flashbang effects (radius: 400, blindness: 12s, stun: 6s)
[FlashbangStatus] Flashbang: blind=8.3s, stun=4.2s
[GrenadeTimer] Applied flashbang to enemy at distance 122.6 (intensity: 0.69)
[GrenadeTimer] Spawned shadow-enabled flashbang effect at (597.77, 682.29)
```
No aggression-related log entries present.

**Root cause chain**:
1. `Player.cs:AddGrenadeTimerComponent()` (line 2940-2946) determines grenade type from scene path: checks only for "Frag", defaults everything else to `Flashbang`
2. `AggressionGasGrenade.tscn` scene path = `res://scenes/projectiles/AggressionGasGrenade.tscn` — does NOT contain "Frag"
3. C# `GrenadeTimer` enum only had `Flashbang` and `Frag` (no `AggressionGas`)
4. `GrenadeTimer.Explode()` (line 336-343): `if Frag → ApplyFragExplosion() else → ApplyFlashbangExplosion()`
5. Result: AggressionGas is treated as Flashbang in every C# code path

**Architecture lesson**: The hybrid C#/GDScript system (C# as export fallback, GDScript for gameplay) requires ALL grenade types to be registered in BOTH languages. The C# code was designed for 2 types and wasn't extensible by default.

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
| `scripts/projectiles/aggression_gas_grenade.gd` | New grenade class — overrides blink/explode for gas-release behavior |
| `scripts/effects/aggression_cloud.gd` | New persistent reddish gas cloud |
| `scripts/components/aggression_component.gd` | Aggression targeting component (extracted from enemy.gd) |
| `scenes/projectiles/AggressionGasGrenade.tscn` | New grenade scene |
| `assets/sprites/weapons/aggression_gas_grenade.png` | Dark red canister sprite (distinct from flashbang) |
| `scripts/autoload/status_effects_manager.gd` | Add aggression effect with reddish tint |
| `scripts/objects/enemy.gd` | Minimal aggression integration (delegates to component), connect animation |
| `scripts/autoload/grenade_manager.gd` | Register new grenade type |
| `Scripts/Projectiles/GrenadeTimer.cs` | **FIX**: Add `AggressionGas` type, defer to GDScript for gas release |
| `Scripts/Characters/Player.cs` | **FIX**: Detect "Aggression" in scene path for correct C# type |
| `Scripts/Autoload/GrenadeTimerHelper.cs` | **FIX**: Handle "AggressionGas" type string |
| `scripts/components/status_effect_animation_component.gd` | Add anger mark animation for aggression status (Issue #675) |
