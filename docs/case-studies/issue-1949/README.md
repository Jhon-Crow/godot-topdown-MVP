# Issue 1949: Breaker bullets lost on fallback weapon selection

## Issue

Breaker bullets stopped behaving as breaker bullets on Building, Double Corridor,
City, Decadence, Labyrinth Complex, and Sewer. The player still had Breaker
Bullets selected, but shots from the selected weapon behaved like normal bullets.

## Evidence

The attached session log is preserved at:

- `docs/case-studies/issue-1949/game_log_20260504_015203.txt`

The log shows the passive item loading correctly, then being applied only to the
startup weapon:

- `ActiveItemManager` restores and selects Breaker Bullets.
- Each affected scene logs `Set IsBreakerBulletActive on weapon: MakarovPM`.
- The same scene then applies the selected weapon later, for example `ak_gl
  (AKGL)`, through `ApplySelectedWeaponFromGameManager`.
- Before this fix there was no second breaker sync after `CurrentWeapon = weapon`
  in the deferred selected-weapon path.

An online/repository search did not reveal a map collision-data difference that
explained the failure. The decisive pattern came from the local log: the maps
all replace the default weapon after active-item initialization.

## Root Cause

`InitBreakerBullets()` set `CurrentWeapon.IsBreakerBulletActive` during player
startup. On the affected C# fallback levels, `CurrentWeapon` was still the
default `MakarovPM` at that point. The deferred GameManager weapon selection
then replaced `CurrentWeapon` with the selected weapon, but did not propagate the
passive breaker-bullet flag to that new weapon.

## Fix

`Player` now uses a shared `SyncBreakerBulletsToCurrentWeapon()` helper:

- `InitBreakerBullets()` applies the passive state through the helper.
- `EquipWeapon()` reapplies it when weapons are swapped normally.
- `ApplySelectedWeaponFromGameManager()` reapplies it immediately after the
  deferred fallback assigns the selected weapon to `CurrentWeapon`.

The regression test `test_csharp_deferred_weapon_selection_keeps_breaker_bullets_active`
guards the C# fallback contract that caused the map-specific failure.
