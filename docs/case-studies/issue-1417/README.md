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

## Solution Design

### 1. Drone AI States

Add a state machine to `DroneComponent`:
- **SEARCHING**: Drone moves in a pattern (patrol or hover), checks for player visibility using line-of-sight with unlimited range and 360° FOV. LED is green/blue.
- **COMBAT**: Triggered when player is detected. LED turns red, beeping starts, drone accelerates to 3x speed and navigates toward player with collision intent.

### 2. Player Detection

- Use raycasting for line-of-sight checks (similar to enemy vision)
- Detection range: unlimited (0)
- FOV angle: 360° (no angle restriction, as specified in issue)
- Detection delay: short (0.3s) to give player brief reaction window

### 3. Combat Movement

- Combat speed: `DRONE_SPEED * 3.0` = 450 px/s
- Use NavigationAgent2D for pathfinding around obstacles
- Apply drift on turns: when turning, the drone's velocity lags behind the desired direction, creating a sliding/drifting effect using linear interpolation with a turn factor

### 4. Drift Mechanics

- Track desired direction vs actual velocity direction
- Use `lerp` with a drift factor (0.02-0.05 per frame) so the drone gradually turns
- At 3x speed, the momentum carries the drone past turn points
- Visual: drone body rotates toward target but velocity trails behind

### 5. Explosion on Contact

- Reuse RPG rocket explosion mechanics (radius: 150px, damage: 3)
- No wall penetration (unlike RPG rocket)
- Line-of-sight check for damage (blocked by obstacles)
- Explosion visual effects and sound

### 6. Audio Feedback

- Generate beeping sound using AudioStreamGenerator (sine wave pattern)
- Morse-code-like pattern: short beeps with varying intervals
- Play continuously while in COMBAT mode

## Implementation Components

### Modified Files
- `scripts/components/drone_component.gd` — Full AI state machine, detection, combat movement, drift, explosion
- `scripts/objects/drone.gd` — LED color changes, collision handling, audio player setup
- `scenes/objects/Drone.tscn` — Add NavigationAgent2D, RayCast2D nodes

### New Files
- `tests/unit/test_drone_combat.gd` — Unit tests for drone combat behavior

## References

- Issue #1397 (PR #1398): Original drone operator implementation
- `scripts/projectiles/rpg_rocket.gd`: RPG explosion mechanics (reused for drone)
- `scripts/objects/enemy.gd`: Enemy AI state machine and vision system (pattern reference)
- `scripts/ui/armory_menu.gd`: AudioStreamGenerator beep generation pattern
