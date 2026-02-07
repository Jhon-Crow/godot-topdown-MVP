# Case Study: Issue #570 - Fix Night Mode

## Issue Summary

Night mode (Realistic Visibility / Fog of War, Issue #540) has four bugs:
1. Laser sight not visible in night mode on Power Fantasy difficulty
2. Silenced pistol laser sight not visible in night mode
3. Night mode doesn't work on ПОЛИГОН (TestTier level)
4. Player weapons not visible in night mode except M16

## Root Cause Analysis

### Single Root Cause for All Four Bugs

All four bugs share the same root cause: **timing mismatch between night mode initialization and weapon loading**.

#### How Night Mode Works

The `RealisticVisibilityComponent` (added in Issue #540) uses:
- `CanvasModulate` to darken the entire scene (fog of war)
- `PointLight2D` to illuminate the area around the player
- `CanvasItemMaterial.LIGHT_MODE_UNSHADED` applied recursively to all player children to ensure the player model, weapons, laser sights, and grenade trajectory remain visible in the dark

#### The Timing Problem

The execution order is:
1. Level `_ready()` calls `_setup_player_tracking()`
2. `_setup_player_tracking()` calls `_setup_realistic_visibility()` which adds `RealisticVisibilityComponent` to the player
3. `RealisticVisibilityComponent._ready()` applies unshaded material to **all current children** of the player
4. `_setup_player_tracking()` then calls `_setup_selected_weapon()` which **swaps the default AssaultRifle** for the selected weapon

At step 3, only the default AssaultRifle (M16) and its LaserSight are present as children. At step 4, the M16 is removed and a new weapon (Shotgun, MiniUzi, SilencedPistol, or SniperRifle) is added. The new weapon and its children (laser sight Line2D, weapon sprite) **never receive the unshaded material** because the recursive application already completed.

Additionally, some weapons create their laser sights programmatically in their C# `_Ready()` method (e.g., `SniperRifle.CreateLaserSight()` creates "PowerFantasyLaser"). Even if the weapon itself received unshaded material, its programmatically-created children would not.

#### Per-Bug Breakdown

| Bug | Weapon | Why Invisible |
|-----|--------|--------------|
| 1. Power Fantasy laser | SniperRifle | `PowerFantasyLaser` created in `_Ready()` after unshaded pass |
| 2. Silenced pistol laser | SilencedPistol | Weapon added after unshaded pass; `LaserSight` also created in `_Ready()` |
| 3. Night mode on ПОЛИГОН | All weapons | Same issue - weapons swapped after visibility component initialization |
| 4. Weapons except M16 | All non-M16 | M16 is the only weapon present in the Player.tscn scene at initialization time |

### Why M16 Works

The M16 (AssaultRifle) is the **default weapon** defined directly in the Player scene file (`Player.tscn`). It exists as a child of the player before `_setup_selected_weapon()` runs. Therefore, when `RealisticVisibilityComponent._ready()` recursively applies unshaded material, the M16 and its LaserSight are already in the tree and receive the material correctly.

## Solution

### Approach: Dynamic Child Monitoring

The fix adds **automatic monitoring** of new children added to the player node. When night mode is active, any newly added child (weapon, laser sight, sprite) automatically receives the unshaded material.

### Implementation Details

Three new methods added to `RealisticVisibilityComponent`:

1. **`_on_player_child_added(child)`** - Connected to `_player.child_entered_tree` signal. Triggered when any new child is added to the player (e.g., weapon swap). Uses `call_deferred()` to ensure the child's own `_Ready()` has run first (creating its laser sight children).

2. **`_apply_unshaded_to_new_child(child)`** - Deferred handler that applies unshaded material to the new child and all its descendants. Also connects to the child's `child_entered_tree` to monitor for grandchildren (laser sights created by weapon scripts).

3. **`_on_weapon_child_added(child)`** - Handles children added to weapons (e.g., laser sight Line2D created in weapon `_Ready()`).

### Why `call_deferred` is Critical

Without deferring, the unshaded material would be applied to the weapon node before its `_Ready()` runs. Since weapons create their laser sight Line2D nodes in `_Ready()`, the laser would be missed. By deferring, we ensure:
1. The weapon's `_Ready()` runs and creates the LaserSight
2. Then we apply unshaded material to the weapon AND its newly created LaserSight

### Signal Chain

```
Player.add_child(weapon)
  -> child_entered_tree signal
    -> _on_player_child_added(weapon) [DEFERRED]
      -> _apply_unshaded_to_new_child(weapon)
        -> Apply unshaded to weapon
        -> Apply unshaded to weapon's children (LaserSight, Sprite)
        -> Connect to weapon.child_entered_tree
          -> _on_weapon_child_added() for any future children
```

## Files Changed

| File | Change |
|------|--------|
| `scripts/components/realistic_visibility_component.gd` | Added dynamic child monitoring via `child_entered_tree` signal |
| `tests/unit/test_realistic_visibility.gd` | Added 8 regression tests for dynamic weapon visibility |

## Test Coverage

New tests verify:
- Dynamically added weapons receive unshaded material when night mode is active
- Dynamically added weapons do NOT receive unshaded material when night mode is inactive
- Laser sights created by weapon scripts receive unshaded material
- PowerFantasyLaser receives unshaded material
- Multiple weapon swaps all work correctly
- Unshaded tracking is cleared when night mode is disabled
- Complete weapon swap scenario (remove M16 -> add SilencedPistol -> LaserSight created)

## Game Logs

Four game logs from the issue reporter are included in this directory, documenting the night mode behavior during testing sessions on 2026-02-07.
