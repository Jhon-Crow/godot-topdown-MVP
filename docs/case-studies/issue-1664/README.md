# Case Study: Issue #1664 — Fix drone operator dodges (уворот дроновода)

## Summary

The drone operator enemy has a broken evasion mechanic in ACTIVE phase.
The fix requested: in ACTIVE phase the drone operator should behave **exactly like the teleport enemy** —
teleport to cover when under fire, teleport on first bullet hit, teleport when flanking, etc.

## Current State (before fix)

`DroneOperatorComponent` in ACTIVE phase creates a `MacheteComponent` for dodge:
- `_setup_dodge_component()` — creates `MacheteComponent`, configures lateral sidestep.
- `_dodge_component.try_dodge(bullet_direction)` — triggers perpendicular lateral dash.
- `enemy.gd` lines 1448-1450: calls `try_dodge` / `get_dodge_velocity` from drone operator.

Problems:
1. Issue says dodge "doesn't work" (не работает). The `MacheteComponent` lateral sidestep
   was the _design_ for Issue #1540 but the owner now wants teleport behavior instead.
2. The `EnemyTeleportComponent` already has all the right logic:
   - `try_damage_teleport()` — immediate teleport on first hit
   - `try_teleport(cover_position)` — teleport to cover under fire
   - `try_teleport(flank_target)` — teleport when flanking
   - Cooldown, min/max distance, nav-map validation, blue particle effects

## Root Cause

The drone operator ACTIVE phase uses `MacheteComponent` (lateral dodge) when it should use
`EnemyTeleportComponent` (teleport to cover / flank), which is what all "teleporter" enemies use.

## Solution

1. **`DroneOperatorComponent`**: Replace `MacheteComponent` dodge with `EnemyTeleportComponent`.
   - Remove `_dodge_component: MacheteComponent`
   - Add `_teleport_component: EnemyTeleportComponent`
   - In `_transition_to_active()`, call `_setup_teleport_component()` (creates & adds child)
   - Expose: `is_teleporting()`, `update_teleport(delta)`, `try_damage_teleport(cover, flank)`, `try_teleport(pos)`
   - Remove old dodge API: `is_dodging()`, `try_dodge()`, `get_dodge_velocity()`

2. **`enemy.gd`**: Replace drone operator dodge logic with teleport logic.
   - Lines 1448-1450: replace `try_dodge` / `is_dodging` / `get_dodge_velocity` with
     `_teleport_component` style calls: under fire → teleport to cover; flanking → teleport to flank.
   - Line 918: remove dodge velocity override (no longer needed)
   - Lines 4269-4273: add drone operator `try_damage_teleport` call alongside the normal teleporter.

3. **Tests**: Update `test_drone_operator.gd` to verify teleport behavior instead of machete dodge.

## Files Changed

- `scripts/components/drone_operator_component.gd`
- `scripts/objects/enemy.gd`
- `tests/unit/test_drone_operator.gd`
