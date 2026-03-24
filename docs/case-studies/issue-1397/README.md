# Case Study: Issue #1397 — Drone Operator and Drone Enemies

## Issue Summary

Add two new enemy types to the spawner system (not placed on maps):

### Drone Operator (Дроновод)
1. Enemy wearing a VR headset. After spawning, takes nearest cover (or corner) and deploys a drone.
2. While the drone is alive, the operator is completely defenseless (doesn't move, doesn't see surroundings).
3. After the drone is destroyed, pulls out a silenced pistol with laser sight and acts like a normal enemy.
4. When bullets enter the operator's threat sphere, instead of being suppressed, performs a Dash (like the player's Dash item) to dodge. Can perform 4 consecutive dashes, then enters cooldown (same duration as player Dash cooldown).

### Drone (minimal implementation)
- Spawns from the operator
- Can receive damage and be destroyed
- Minimal AI for now (residual principle)

## Architecture Analysis

### Existing Patterns Used

The codebase uses a **component-based architecture** for enemy specializations:
- `EnemyShieldComponent` — SWAT shield mechanics (Issue #1242)
- `EnemyForceFieldComponent` — Force field (Issue #1034)
- `EnemyTeleportComponent` — Teleportation (Issue #752)
- `EnemyInvisibilityComponent` — Invisibility cloak (Issue #1121)
- `GasMaskGrenadeComponent` — Chemical grenades (Issue #1353)

Each component follows the same pattern:
1. Created as a `class_name` extending `Node`
2. Instantiated in `enemy.gd _ready()` based on an `@export` flag
3. Has `setup()` and `update(delta)` methods called from the parent enemy
4. Uses `FileLogger.info()` for logging

### Key Systems Referenced

1. **Dash/Рывок System** (`scripts/effects/dash_effect.gd`):
   - 3 charges, chain-dash, cooldown 1.2s
   - Afterimage trail (cyan-blue tint)
   - Damage immunity during dash
   - Adapted for drone operator: 4 charges, same cooldown

2. **Cover System** (`scripts/components/cover_component.gd`):
   - 16 raycasts for cover detection
   - Used by drone operator to find initial cover position

3. **Threat Sphere** (in `enemy.gd`):
   - Area2D detecting bullets within radius
   - Triggers suppression — drone operator overrides this to trigger dash instead

4. **Silenced Pistol** (`Scripts/Weapons/SilencedPistol.cs`):
   - PM weapon type (5) with silent shots
   - Green laser sight
   - Used by drone operator after drone is destroyed

5. **Weapon Type System** (`scripts/components/weapon_config_component.gd`):
   - 9 weapon types (0-8)
   - PM pistol is type 5 — closest to silenced pistol behavior

## Implementation Plan

### New Files
1. `scripts/components/drone_operator_component.gd` — Drone operator behavior component
2. `scripts/components/drone_component.gd` — Drone entity component
3. `scenes/objects/EnemyDroneOperator.tscn` — Drone operator scene
4. `scenes/objects/Drone.tscn` — Drone scene
5. `tests/unit/test_drone_operator.gd` — Unit tests

### Modifications to Existing Files
1. `scripts/objects/enemy.gd` — Add `is_drone_operator` export flag and component setup
2. `scripts/ui/experimental_menu.gd` — Add spawner entries
3. `scripts/autoload/game_manager.gd` — Add F8 spawn entries
4. `tests/unit/test_enemy_spawner_1342.gd` — Update spawner tests

## Bug Fixes (PR #1398 Feedback — 2026-03-24)

### Root Cause Analysis

Three bugs were reported after initial implementation:

#### Bug 1: Drone never spawned
**Symptom**: Drone operator goes into SEEKING_COVER but never deploys the drone.
**Root Cause**: `_update_deploying()` only checked for `IN_COVER` state (AIState == 3) to trigger drone deployment. On maps without cover objects (e.g., Tutorial), the SEEKING_COVER state either stays indefinitely or transitions to COMBAT (AIState == 1) when no cover position is found — but the component never detected either case.
**Fix**: Added fallback: deploy drone if (a) AI transitions to COMBAT state, or (b) cover-seeking exceeds MAX_COVER_SEEK_TIME (3 seconds).
**Evidence**: Game log shows `state=SEEKING_COVER` at line 397, operator killed at line 427 — no drone deployment log entry between.

#### Bug 2: VR headset rotated 90 degrees
**Symptom**: VR headset visor appears as a vertical strip on the side of the head instead of a horizontal band across the face.
**Root Cause**: Polygon2D vertices `(3,-5)...(7,5)` created a tall/narrow shape (4px wide × 10px tall), but enemy sprites face right, so the visor should be a wide horizontal band across the eyes.
**Fix**: Changed vertices to `(-5,-2)...(5,2)` — a 10px wide × 4px tall horizontal band centered on the head.

#### Bug 3: Weapon visible during CONTROLLING phase
**Symptom**: Drone operator holds a rifle while supposedly controlling the drone via VR headset.
**Root Cause**: No mechanism to hide the weapon sprite during DEPLOYING/CONTROLLING phases.
**Fix**: Added tablet visual (dark rectangle + green screen) on the weapon mount. During DEPLOYING/CONTROLLING, the weapon sprite is hidden and the tablet is shown. During ACTIVE phase, the tablet is hidden and the weapon sprite is restored.

### Game Log Analysis
- Log file: `game_log_20260324_084300.txt`
- Operator spawned at (350, 360) on Tutorial map at 08:43:30
- Entered SEEKING_COVER at 08:43:33, never found cover (open map)
- Hit by player bullets at 08:43:35, transitioned to COMBAT
- Died at 08:43:36 — no drone was ever deployed

## References
- Issue: https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1397
- Player Dash: `scripts/effects/dash_effect.gd`
- Shield component pattern: `scripts/components/enemy_shield_component.gd`
- Spawner: `scripts/ui/experimental_menu.gd` lines 505-524
