# Case Study: Issue #1417 — Drone and Drone Operator Update

## Issue Summary

Update the drone entity (spawned by the Drone Operator enemy, Issue #1397) with new combat behaviors:
1. Drone starts in **search mode** with 360° unlimited FOV vision
2. On detecting player → transitions to **combat mode** with red LED and beeping sound (morse-like)
3. Combat speed = 3× normal speed, flies directly at player (kamikaze)
4. Navigates obstacles in combat using NavigationAgent2D, but **drifts on turns** due to high speed
5. On collision with player → **explodes like RPG** (same 150px radius, 3 HP damage, no wall penetration)

## Root Cause Analysis

The original drone implementation (PR #1398) was minimal by design ("residual principle"):
- Simple direct movement toward player at 150 px/s
- No state machine (always moved toward player)
- No vision/detection system (always knew player position)
- No explosion on contact (just hovered near player)
- No obstacle avoidance (direct CharacterBody2D movement only)

### Game Log Evidence

From `game_log_20260324_135947.txt`:
- Drone operator spawns and deploys successfully (line 486-489)
- Drone deploys at correct offset from operator (line 488: "Drone deployed at (509, 900)")
- No drone behavior logs after deployment — confirming the drone was non-functional in gameplay
- The user comment "дрон не добавляется" (drone is not added) confirms the drone existed but had no meaningful gameplay impact

## Solution

### Architecture

Converted DroneComponent from a simple movement script to a two-state behavior system:

```
DroneState.SEARCHING → (player detected via LOS) → DroneState.COMBAT
```

### Key Changes

| File | Change |
|------|--------|
| `scripts/components/drone_component.gd` | Complete rewrite: SEARCHING/COMBAT states, 360° LOS detection, NavigationAgent2D pathfinding, 3× combat speed, drift inertia, RPG-like explosion, beeping sound |
| `scripts/objects/drone.gd` | Combat visual updates: LED color (green→red), pulsing PointLight2D glow, faster rotor animation in combat |
| `scenes/objects/Drone.tscn` | Added NavigationAgent2D node for obstacle avoidance, updated collision_mask to 7 |

### Behavior Details

**Search Mode (SEARCHING)**
- 360° vision (no FOV angle restriction)
- Line-of-sight raycast against obstacle layer (mask 4)
- Hovers in place until player is detected

**Combat Mode (COMBAT)**
- Red LED with pulsing PointLight2D glow
- Procedural beeping sound (1200 Hz sine wave, morse-like pattern: dot-dot-dash-dot)
- Speed: 450 px/s (3× the 150 px/s search speed)
- NavigationAgent2D pathfinding around obstacles
- Drift/inertia: `DRIFT_FACTOR = 0.85` (drone preserves 85% of current direction each frame)
- Collision check: explodes when within 24px of player or on CharacterBody2D collision with player

**Explosion**
- Same parameters as RPG rocket: 150px radius, 3 HP damage
- Line-of-sight check for damage (walls block damage)
- **No wall penetration** (unlike RPG which carves passages via WallBreachHelper)
- Reuses existing explosion systems: ImpactEffectsManager, SoundPropagation, AudioManager, PowerFantasy

### Drift Physics

The drift system creates visible "sliding" on turns:
```
current_direction = (current_direction × 0.85 + desired_direction × 0.15).normalized()
velocity = current_direction × 450
```
This makes the drone overshoot on corners, creating the "заносит при поворотах" (drifts on turns) effect.

## Test Coverage

- `test_drone_component.gd`: 28 test cases covering constants, states, damage, combat transition, drift physics, explosion
- `test_drone.gd`: 14 test cases covering visuals, groups, states, combat LED color, rotor speed in combat
