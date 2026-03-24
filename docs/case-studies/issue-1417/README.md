# Issue #1417: Drone and Drone Operator Update

## Problem Statement

The drone entity (introduced in Issue #1397) has minimal behavior — it moves slowly toward the player with no detection logic, no combat mode, and no explosion on contact. The issue requests a full combat AI overhaul for the drone:

1. **Search mode** (like a normal enemy) but with **360° unlimited FOV** (no angle restriction)
2. **Combat mode** triggered on player detection:
   - Red LED indicator light
   - Beeping/morse-code-like sound
3. **3x speed movement** in combat mode, flying directly at the player
4. **Obstacle avoidance with drift** — the drone still maneuvers around obstacles but drifts on turns due to high speed
5. **RPG-strength explosion** on collision in combat mode (same damage/radius as RPG rocket, but **no wall penetration**)

## Root Cause Analysis

The original drone was a minimal implementation ("residual principle" per Issue #1397):
- `DroneComponent` had a simple `_physics_process` that moved toward the player at 150 px/s
- No detection/search state, no combat transitions
- No explosion mechanics on contact
- No NavigationAgent2D for obstacle avoidance
- No audio feedback

### User-Reported Bug: "Drone not released" (2026-03-24)

**Symptom**: User reported "теперь не выпускает дрона" (now doesn't release the drone).

**Investigation** (from `game_log_20260324_125142.txt`):
- Drone operator IS deploying the drone (logs show "Drone deployed at (X, Y)")
- Drone entity IS present in the scene (grenade collision with "Drone" detected)
- But NO drone behavior logs appear — no "Visual setup complete", no "Initialized by operator", no "COMBAT mode activated"

**Root Causes Identified**:
1. **RayCast2D `enabled = false` in scene** — While `force_raycast_update()` should work with disabled raycasts, this is fragile. Set to `enabled = true` for reliability.
2. **Missing deferred player search** — `_find_player()` was called in `_ready()` before the scene tree might be fully settled after dynamic spawning via `add_child()`. Changed to `call_deferred("_deferred_find_player")` for robustness.
3. **Insufficient logging** — No diagnostic logs in `_ready()`, `_physics_process()`, or player search. Without logs, impossible to diagnose why the drone appears inert.
4. **NavigationAgent2D usage** — Combat code had redundant/confused navigation logic. Simplified to single path with proper fallback to direct movement.
5. **No player reference from operator** — When `initialize(operator)` is called, the operator already has a `_player` reference that could be shared, avoiding the need for the drone to independently search for the player.

**Fixes Applied**:
- Enabled RayCast2D in scene file
- Deferred player search with comprehensive logging
- Added player reference sharing from operator during initialization
- Simplified NavigationAgent2D combat movement logic
- Added periodic logging when player not found
- Added ready/initialization status logging

## Solution Design

### 1. Drone AI States

State machine in `DroneComponent`:
- **SEARCHING**: Drone patrols near spawn position, checks for player visibility using line-of-sight with unlimited range and 360° FOV. LED is green.
- **COMBAT**: Triggered when player is detected (after 0.3s confirmation). LED turns red, beeping starts, drone accelerates to 3x speed and navigates toward player.

### 2. Player Detection

- Use raycasting for line-of-sight checks (RayCast2D, collision_mask = 4 = obstacles only)
- Detection range: unlimited (0)
- FOV angle: 360° (no angle restriction, as specified in issue)
- Detection delay: 0.3s to give player brief reaction window

### 3. Combat Movement

- Combat speed: `DRONE_SPEED * 3.0` = 450 px/s
- Use NavigationAgent2D for pathfinding around obstacles
- Drift on turns via lerp with factor 0.03

### 4. Explosion on Contact

- Reuse RPG rocket explosion mechanics (radius: 150px, damage: 3)
- No wall penetration (line-of-sight check for damage)
- Explosion visual effects and sound

### 5. Audio Feedback

- Generate beeping sound using AudioStreamGenerator (880Hz sine wave)
- Morse-code-like pattern: 3 short beeps + pause
- Play continuously while in COMBAT mode

## Implementation Components

### Modified Files
- `scripts/components/drone_component.gd` — Full AI state machine, detection, combat movement, drift, explosion
- `scripts/objects/drone.gd` — LED color changes, collision handling, lifecycle signals
- `scenes/objects/Drone.tscn` — Add NavigationAgent2D, RayCast2D nodes (enabled)

### New Files
- `tests/unit/test_drone_combat.gd` — Unit tests for drone combat behavior

### Log Data
- `docs/case-studies/issue-1417/game_log_20260324_125142.txt` — User-provided game log showing drone deployment but no behavior

## References

- Issue #1397 (PR #1398): Original drone operator implementation
- `scripts/projectiles/rpg_rocket.gd`: RPG explosion mechanics (reused for drone)
- `scripts/objects/enemy.gd`: Enemy AI state machine and vision system (pattern reference)
- `scripts/ui/armory_menu.gd`: AudioStreamGenerator beep generation pattern
