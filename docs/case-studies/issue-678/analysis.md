# Case Study: Issue #678 — Breaker Bullets (Пули с прерывателем)

## Issue Summary

**Title**: добавь предмет в слот активируемого - пули с прерывателем
**Translation**: Add an item to the activatable slot — breaker bullets

## Requirements

The breaker bullet is a **passive** active item in the "activatable" category in the armory.
When selected, the player's weapon fires breaker bullets with the following behavior:

### Bullet Behavior
1. **Pre-detonation**: 60px before collision with a wall/obstacle, the bullet explodes
2. **Explosion**: Deals 1 damage in a 15px radius
3. **Shrapnel cone**: In the direction of bullet movement (in a sector like a flashlight), shrapnel flies
4. **Shrapnel count**: bullet damage × 10 (e.g., 1 damage bullet = 10 shrapnel)
5. **Shrapnel damage**: 0.1 each
6. **Shrapnel constraints**: No ricochet, no wall penetration
7. **Smoke trails**: Each shrapnel piece has an uneven/smoky tracer behind it

### Visual Reference
- Images show white phosphorus/incendiary munitions with smoke trails
- Central detonation point with fragments spreading in a forward cone
- Each fragment trailing smoke/vapor

## Architecture Analysis

### Existing Systems Used

| System | File | Purpose |
|--------|------|---------|
| ActiveItemManager | `scripts/autoload/active_item_manager.gd` | Manages activatable items (Flashlight, etc.) |
| Bullet | `scripts/projectiles/bullet.gd` | Base bullet projectile |
| Shrapnel | `scripts/projectiles/shrapnel.gd` | Existing shrapnel from frag grenade |
| Frag Grenade | `scripts/projectiles/frag_grenade.gd` | Reference for explosion + shrapnel spawning |
| Armory Menu | `scripts/ui/armory_menu.gd` | UI for item selection |
| Player | `scripts/characters/player.gd` | Bullet spawning and active item init |

### Implementation Strategy

#### 1. ActiveItemManager — Add BREAKER_BULLETS type
- Add `BREAKER_BULLETS` enum value to `ActiveItemType`
- Add item data (name, icon, description)
- Add helper method `has_breaker_bullets()`

#### 2. Breaker Bullet Shrapnel — New script
- Create `scripts/projectiles/breaker_shrapnel.gd`
- Based on existing `shrapnel.gd` but:
  - No ricochet (destroyed on wall hit)
  - No wall penetration
  - Damage = 0.1 per piece
  - Smoky trail effect (wider, more uneven Line2D with noise)

#### 3. Breaker Bullet Scene — New scene
- Create `scenes/projectiles/BreakerShrapnel.tscn`
- Based on `Shrapnel.tscn` but with smoky trail appearance

#### 4. Bullet Modification — Breaker behavior
- Modify `bullet.gd` to check if breaker bullets are active
- 60px before wall collision: trigger explosion
- Forward raycast each physics frame to detect walls ahead
- On detonation: spawn explosion effect + shrapnel in cone

#### 5. Player Integration
- Check `ActiveItemManager.has_breaker_bullets()` in player
- No special input needed (passive item)

## Bug Report Analysis (PR #690 Feedback)

### User Report
The user (Jhon-Crow) reported on 2026-02-08 that breaker bullets "don't work" and provided
a game log file (`game_log_20260209_014244.txt`).

### Root Cause Analysis

**Timeline from game log:**
1. `01:42:44` — Level loads, Player initializes
2. `01:42:53` — User selects "Breaker Bullets" in armory menu
3. `01:42:53` — `[ActiveItemManager] Active item changed from None to Breaker Bullets`
4. `01:42:54` — Level restarts, Player re-initializes
5. `01:42:54` — `[Player.Flashlight] No flashlight selected` log appears
6. **NO `[Player.BreakerBullets]` log appears — neither "active" nor "not selected"**
7. Bullets fire normally (wall penetration, ricochet) — no breaker behavior

**Root Cause:** The Player scene (`scenes/characters/csharp/Player.tscn`) uses a **C# script**
(`Scripts/Characters/Player.cs`), NOT the GDScript file (`scripts/characters/player.gd`).

All level scenes reference the C# Player:
```
scenes/levels/BuildingLevel.tscn → scenes/characters/csharp/Player.tscn → Scripts/Characters/Player.cs
```

The original implementation added `_init_breaker_bullets()` and `_breaker_bullets_active` to
`player.gd`, which is never loaded by the actual game. The `Player.cs` script never had any
breaker bullets integration.

**Evidence from the log:**
- The `_init_breaker_bullets()` function has two possible log outputs ("active" and "not selected")
- Neither appears in the log, confirming the function never executes
- The flashlight init in `Player.cs` (`InitFlashlight()`) DOES log, confirming C# is the runtime

### Fix Applied

1. Added `InitBreakerBullets()` to `Player.cs` following the exact pattern of `InitFlashlight()`
   and `InitTeleportBracers()` — checks ActiveItemManager via `has_breaker_bullets()` method call
2. Added `IsBreakerBulletActive` property to `BaseWeapon.cs` — set on weapon during init
3. `BaseWeapon.SpawnBullet()` now sets `is_breaker_bullet = true` on spawned bullets when active
4. `EquipWeapon()` propagates the breaker flag to newly equipped weapons

### Additional Fix: Icon
Replaced the yellow oval icon with a proper bullet + explosion/shrapnel icon.

## Known Components That Could Help

### Godot Engine Features
- **Line2D** with gradient and width curve — for smoky trails
- **Noise texture** — for uneven trail effect
- **RayCast2D** or `direct_space_state.intersect_ray()` — for detecting walls ahead at 60px
- **Area2D** — for explosion damage radius

### Existing Codebase Patterns
- `frag_grenade.gd::_spawn_shrapnel()` — pattern for spawning multiple shrapnel in directions
- `shrapnel.gd` — base shrapnel behavior (movement, trail, collision)
- `bullet.gd::_get_surface_normal()` — raycast pattern for wall detection
- `flashlight_effect.gd` — cone/sector geometry reference

## Cone/Sector Calculation

The shrapnel should spread in a cone in the direction of bullet travel.
Using a half-angle of ~30° (60° total sector), similar to a flashlight cone:

```
shrapnel_angle = bullet_direction + random_offset_in_sector
where offset ∈ [-half_angle, +half_angle]
```

## Damage Calculation Example

For a standard M16 bullet (damage = 1.0):
- Explosion damage: 1 (in 15px radius)
- Shrapnel count: 1.0 × 10 = 10 pieces
- Each shrapnel damage: 0.1
- Total potential shrapnel damage: 10 × 0.1 = 1.0
- Total potential damage: 1 (explosion) + 1.0 (shrapnel) = 2.0
