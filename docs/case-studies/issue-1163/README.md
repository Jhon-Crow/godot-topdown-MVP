# Case Study: Issue #1163 — Sniper Enemy Special Behavior

## Issue Summary

**Title:** update враг снайпер (update enemy sniper)

**Requirements:**
1. The sniper enemy should stay at maximum distance from the player and shoot from there.
2. When the player is not visible, the sniper should shoot approximately where the player might be — even through cover — since the sniper rifle (ASVK) penetrates cover.

## Context

The sniper enemy was introduced in Issue #1125, which added the SNIPER_RIFLE weapon type (ASVK anti-materiel rifle) to the enemy system. The PR added:
- Weapon config (slow fire rate ~0.33 rps, near-instant bullet speed 10,000 px/s, 5-round magazine)
- Enemy sniper bullet scene: `SniperBulletEnemy.tscn` with `MaxWallPenetrations = 2`
- Sound effects (non-positional ASVK shot)

However, Issue #1125 only added the weapon type without any special AI behavior. The sniper enemy behaves like a standard rifle enemy: it advances toward the player to get within `COMBAT_DIRECT_CONTACT_DISTANCE` (250 px) before shooting. This is the opposite of what a sniper should do.

## Current Behavior Analysis

### Standard Combat State (`_process_combat_state`)

The standard combat cycle:
1. **Approach phase**: Move toward player until within `COMBAT_DIRECT_CONTACT_DISTANCE` (250 px) OR `COMBAT_APPROACH_MAX_TIME` (2s) elapses.
2. **Exposed phase**: Stand still and shoot for 2-3 seconds.
3. **Return to cover** via `SEEKING_COVER`.

Problems for a sniper:
- Sniper advances too close (250 px = close combat)
- Sniper retreats to cover when under fire (should maintain distance)
- No "blind fire" when player is in cover

### Existing Special-Case Patterns

- **RPG** (`_is_rpg_weapon`): Fires immediately at max range without approach phase.
- **Machine Gun** (`weapon_type == WeaponType.MACHINE_GUN`): Holds position and fires suppressive corridor fire at last-known player position.
- **Machete** (`_is_melee_weapon`): Rushes player directly without cover-seeking.

Each of these uses early-return guards in `_process_combat_state` to override standard behavior.

## Design Analysis

### Sniper Behavioral Model

Real-world snipers follow these principles:
1. **Standoff distance** — Engage from maximum effective range, far outside return-fire range.
2. **Positional fire** — Shoot at last-known position (or predicted position) through cover when line of sight is lost.
3. **Kiting behavior** — Actively back away when the player closes distance.
4. **Limited mobility** — A sniper rifle has a very slow fire rate (3s between shots), so the sniper needs time to aim and fire from a stable position.

### Distance Parameters

- `COMBAT_DIRECT_CONTACT_DISTANCE` = 250 px (current close-combat threshold — too close for sniper)
- Sniper preferred distance: **500–600 px** (sniper effective range in game units)
- Sniper minimum safe distance: **350 px** (closer than this → actively retreat)
- Bullet speed: 10,000 px/s (near-instant, no lead prediction needed)

### Blind Fire (Through Cover) Behavior

When the player is in cover but the sniper knows the approximate position (via memory/last known position), the sniper should fire at the predicted position. This is uniquely enabled because:
- `SniperBulletEnemy.tscn` has `MaxWallPenetrations = 2`
- The bullet will physically penetrate through cover objects
- The enemy already has `_last_known_player_position` for exactly this purpose

This is consistent with the machine gunner's corridor suppression behavior pattern.

## Known Libraries / Existing Components

| Component | Purpose |
|-----------|---------|
| `PlayerPredictionComponent` | Predicts player position when LOS lost |
| `EnemyMemory` | Confidence-based last-known-position tracking |
| `SuppressiveFireComponent` | Fires at last-known position through walls (existing pattern) |
| `_machine_gunner_fire_at_corridor()` | Reference implementation for blind fire |

## Proposed Solution

### Implementation Plan

1. **Add constants** for sniper preferred/minimum distance:
   ```gdscript
   const SNIPER_PREFERRED_DISTANCE: float = 550.0  ## Preferred engagement range
   const SNIPER_MIN_DISTANCE: float = 350.0          ## Below this: actively retreat
   const SNIPER_BLIND_FIRE_COOLDOWN: float = 5.0     ## How often to blind-fire at predicted position
   ```

2. **Add state variables**:
   ```gdscript
   var _sniper_blind_fire_timer: float = 0.0  ## Timer for blind fire when player in cover
   ```

3. **Override `_process_combat_state`** for `SNIPER_RIFLE`:
   - Check `if weapon_type == WeaponType.SNIPER_RIFLE`
   - If player is too close (`dist < SNIPER_MIN_DISTANCE`): move away using navigation
   - If player is at good range and visible: aim and shoot
   - If player not visible: try blind fire at last-known/predicted position

4. **Override pursuit behavior**: When player is in cover and sniper has memory of their location, fire through the cover wall.

### Key Behaviors

#### 1. Distance Maintenance (Kiting)
When the player is within `SNIPER_MIN_DISTANCE`, the sniper moves away from the player along the line connecting them. Navigation agent is used to avoid walls while retreating. This replaces the standard approach behavior.

#### 2. Long-Range Shooting
The sniper does NOT need to approach the player. If the player is visible at ANY distance ≥ `SNIPER_MIN_DISTANCE`, the sniper stands still and shoots. The ASVK fires slowly (3s cooldown), so the enemy waits between shots.

#### 3. Blind Fire Through Cover
When the player is not visible but the enemy has a `_last_known_player_position`:
- A cooldown timer prevents spamming
- The sniper fires directly at the last known position
- Since `SniperBulletEnemy.tscn` has `MaxWallPenetrations = 2`, the bullet goes through cover
- This is consistent with Issue #1163 requirement 2

#### 4. Suppression Interplay
The standard suppression/retreat system should be partially suppressed for the sniper — a sniper should NOT flinch and retreat to cover the same way as a rifle enemy. Instead, the sniper should:
- Maintain its firing position as long as the player is at range
- Only seek cover if the player gets very close (melee distance)

## References

- Issue #1125: Added sniper weapon type (ASVK) to enemy system
- Issue #1033: Machine gunner blind fire pattern (reference implementation)
- Issue #583: RPG enemy long-range engagement pattern (reference implementation)
- `scripts/objects/enemy.gd`: Main AI state machine
- `scripts/components/weapon_config_component.gd`: Weapon type 7 (SNIPER_RIFLE)
- `scenes/projectiles/csharp/SniperBulletEnemy.tscn`: Sniper bullet with wall penetration
- `scripts/ai/player_prediction_component.gd`: Player position prediction when LOS lost
- `scripts/ai/enemy_memory.gd`: Memory system for last known player position
