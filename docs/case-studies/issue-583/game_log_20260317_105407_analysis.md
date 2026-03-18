# Game Log Analysis: game_log_20260317_105407.txt

**Date:** 2026-03-17
**Issue:** #583 — RPG enemy
**Session:** Rocket propulsion fix (integrate_forces)

## Observed Behavior

From the game log, rockets ARE being spawned and velocity is set:
- `[RPG] Rocket launched at (283.9565, 941.2652) dir=(-0.553985, -0.832527) vel=(-443.1876, -666.0216)`
- `[RPG] Rocket launched at (197.448, 367.6573) dir=(1, 0) vel=(800, 0)`
- `[RPG] Rocket launched at (3620.243, 1408.699) dir=(-0.999738, 0.022899) vel=(-799.7902, 18.31904)`

**User report:** "ракета летит как физический объект (ведёт себя как пустая пластмассовая бутылка)"
Translation: "Rocket flies like a physical object (behaves like an empty plastic bottle)"

## Root Cause Analysis

The rocket used `RigidBody2D` with `linear_velocity` set at spawn. While initial velocity is correct, the Godot 4 physics engine applies collision impulses when the rocket touches walls or other bodies. Without propulsion enforcement:

1. Rocket hits a wall at an angle → physics resolves collision → applies impulse → velocity changes direction
2. Without gravity or damping, the rocket slides along the wall surface
3. This looks like a "plastic bottle rolling" behavior
4. The rocket might not even trigger `body_entered` if it's sliding along the surface rather than impacting it directly

## Fix Applied

Replaced `_physics_process` velocity management with `_integrate_forces(state)`:

### Why `_integrate_forces` works

`_integrate_forces` runs inside the physics server each step and allows direct override of the body state. By setting `state.linear_velocity = direction * speed` every physics frame, we enforce the rocket's propulsion — any impulses from collisions are overridden on the next frame.

This is analogous to how real rocket propulsion works: the engine continuously accelerates the projectile in one direction, making it nearly impossible for external forces to deflect it significantly.

### Realistic RPG-7 acceleration model

Real RPG-7 ballistics:
- Initial propellant charge: launches at ~115 m/s
- Sustainer rocket motor ignites ~10m from muzzle, accelerates to ~300 m/s
- After boost phase (~11m): coasts at ~300 m/s to target

Scaled to game (100px ≈ 1m):
- `speed_initial = 300 px/s` (initial launch, like the propellant charge)
- `speed = 800 px/s` (cruise speed after motor activation)
- `accel_distance = 1000 px` (≈10m boost phase)
- Smooth ease-in curve: `t * t` interpolation

### Collision on all body types

Added `AnimatableBody2D` to collision check and added `_on_area_entered` for grenade shockwave detection.

## Changes

- `scripts/projectiles/rpg_rocket.gd`: Added `_integrate_forces`, `speed_initial`, `accel_distance`, `_current_speed`, `_distance_traveled`, `_on_area_entered`
- `scenes/projectiles/RpgRocket.tscn`: Updated `max_contacts_reported = 8`
