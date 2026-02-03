# Issue #403 Case Study: Silenced Pistol One-Shot Kill Bug

## Problem Description

The silenced pistol was not one-shotting enemies despite having configured damage values (first 5, then 10).

### User Reports

1. **First Report**: "pistol doesn't one-shot, 10+13 ammo instead of 10"
2. **Second Report**: "pistol still doesn't one-shot, should use 9x19 7H31 armor-piercing bullets with damage 10"

## Root Cause Analysis

### Bug #1: Damage Never Applied to Bullets (Fixed in v2)

**Location**: `Scripts/Weapons/SilencedPistol.cs:SpawnBullet()` and `Scripts/AbstractClasses/BaseWeapon.cs:SpawnBullet()`

**Problem**: The `SpawnBullet()` method was not setting `bullet.Damage = WeaponData.Damage`. Bullets spawned with their default damage value (1.0) instead of the weapon's configured damage.

**Fix**: Added `bullet.Damage = WeaponData.Damage` in both SilencedPistol and BaseWeapon SpawnBullet methods.

### Bug #2: Ammo Count Wrong (Fixed in v2)

**Location**: `Scripts/Data/MagazineData.cs:MagazineInventory.Initialize()`

**Problem**: `Initialize(0, magazineCapacity, false)` still created a full magazine even when magazineCount=0.

**Fix**: Added check to set `CurrentMagazine = null` when `magazineCount <= 0`.

### Bug #3: Enemy Ignores Bullet Damage (Fixed in v3) - ROOT CAUSE

**Location**: `scripts/objects/enemy.gd:on_hit_with_bullet_info()`

**Problem**: The enemy's `on_hit()` function **always subtracted exactly 1 HP** (`_current_health -= 1`), completely ignoring the bullet's damage value.

**Evidence from game log** (`game_log_20260203_110826.txt`):
```
[11:08:32] [ENEMY] [Enemy3] Hit taken, health: 2/3
```
Enemy3 had 3 HP and after being hit, had 2 HP remaining - meaning only 1 damage was applied despite the weapon having 5 damage configured.

**Root Cause Chain**:
1. C# Bullet correctly sets `bullet.Damage = WeaponData.Damage` (5.0)
2. Bullet hits enemy's HitArea (an Area2D)
3. Bullet calls `area.Call("on_hit")` - the GDScript method
4. GDScript's `on_hit()` doesn't accept any damage parameter
5. `on_hit_with_bullet_info()` always does `_current_health -= 1`

**Fix**:
1. Added `take_damage(amount)` function to enemy.gd (IDamageable-style interface for C#)
2. Modified `on_hit_with_bullet_info()` to accept a damage parameter (default 1.0 for backward compatibility)
3. Updated Bullet.cs to call `take_damage(damage)` on the enemy parent when the method exists

## Timeline of Events

### Session 1 (Initial Implementation)
- Created SilencedPistol weapon with damage=5 in WeaponData
- Implemented dynamic ammo distribution based on enemy count
- Bug: Weapon damage never transferred to bullets

### Session 2 (First Bug Fix)
- Fixed Bug #1: Added `bullet.Damage = WeaponData.Damage` in SpawnBullet
- Fixed Bug #2: MagazineInventory now properly handles magazineCount=0
- Bug persists: Enemy still only takes 1 damage per hit

### Session 3 (Root Cause Fix)
- Investigated game log showing enemy losing only 1 HP per hit
- Discovered enemy.gd ignores damage parameter entirely
- Added `take_damage(amount)` function to enemy.gd
- Updated Bullet.cs to call `take_damage` with actual damage value
- Increased damage from 5 to 10 (9x19 7H31 armor-piercing spec)

## Technical Details

### Damage Flow (Before Fix)
```
WeaponData.Damage (5.0)
  -> SilencedPistol.SpawnBullet()
    -> bullet.Damage = 5.0
      -> Bullet hits HitArea
        -> area.Call("on_hit")  [NO DAMAGE PARAM]
          -> enemy._current_health -= 1  [ALWAYS 1]
```

### Damage Flow (After Fix)
```
WeaponData.Damage (10.0)
  -> SilencedPistol.SpawnBullet()
    -> bullet.Damage = 10.0
      -> Bullet hits HitArea
        -> parent.Call("take_damage", 10.0)  [DAMAGE PASSED]
          -> enemy._current_health -= 10  [CORRECT]
```

### Files Modified

1. **scripts/objects/enemy.gd**
   - Added `take_damage(amount)` function for C# bullet compatibility
   - Modified `on_hit_with_bullet_info()` to accept damage parameter
   - Changed `_current_health -= 1` to `_current_health -= actual_damage`

2. **Scripts/Projectiles/Bullet.cs**
   - Added check for `take_damage` method on parent node (enemy)
   - Calls `parent.Call("take_damage", GetEffectiveDamage())` when available
   - Falls back to legacy `on_hit()` for backward compatibility

3. **resources/weapons/SilencedPistolData.tres**
   - Updated `Damage = 5.0` to `Damage = 10.0` (9x19 7H31 armor-piercing spec)

## Lessons Learned

1. **Interface Mismatch**: C# and GDScript components need explicit damage-passing interfaces
2. **Test Damage Flow**: Always verify damage reaches the target entity, not just that bullets are spawned
3. **Log Evidence**: Game logs showing "health: 2/3" were key evidence that only 1 damage was applied
4. **Default Parameters**: Using default parameter values (1.0) preserves backward compatibility

## Expected Behavior After Fix

- Silenced pistol bullets deal 10 damage
- All enemies (health 2-4) die in one shot
- Damage is properly logged in game logs as "damage: 10"
