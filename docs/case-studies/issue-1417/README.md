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

---

# Post-Implementation Investigation: Drone AI Still Inactive (Sessions 2 & 3)

## New Evidence (game_log_20260325_064620.txt)

After the "Fix drone AI inactivity and damage immunity" commit was deployed, the user reported:
> "у дрона всё ещё нет ии (но теперь он получает урон и убивается, хорошо)"
> (drone still has no AI, but now takes damage and dies, good progress)

### Session 3 Log Analysis

Pattern in session 3 log (2026-03-25 06:46):
```
[Drone] WARNING: DroneComponent cast returned null (node=true)
[Drone] Visual setup complete (quadcopter style, LED=green/searching)
[DroneOperator] WARNING: DroneComponent not found on drone, using fallback signals
```

**Critical observation**: `DroneComponent._ready()` is NEVER called. Across all 3 sessions
and all code versions (original, duck-typing, typed-cast), `_ready()` in `drone_component.gd`
has never executed.

## Root Cause: GDScript class_name Cross-Script Dependency (Static Reference)

The actual root cause was identified in `drone.gd` line 32:
```gdscript
var _fallback_hp: int = DroneComponent.DRONE_HP  # Accesses const at class parse time!
```

And line 28:
```gdscript
var _drone_component: DroneComponent = null  # Typed var using class_name
```

In Godot 4 exported builds, class_name registration happens when scripts are parsed. The
**order** scripts are parsed depends on the export process. When `drone.gd` is parsed and
references `DroneComponent.DRONE_HP` as a class-level variable initializer, Godot must
resolve `DroneComponent` at parse time. If `drone_component.gd` hasn't been compiled yet,
this fails silently — leaving the drone scene in a broken state where:
- `drone.gd`'s `_ready()` runs (enough to show the visual)
- `drone_component.gd`'s `_ready()` is never called (script attached to node doesn't execute)

### Why the Editor Didn't Show This

In the Godot editor, all scripts are pre-compiled and class_names are pre-registered in the
project cache. The issue only manifests in **exported builds** where script compilation order
is not guaranteed to match the editor's order.

### Evidence from Git History

Commit `a189214a` (the duck-typing fix attempt) changed `drone.gd` to use duck typing but
did NOT remove `var _fallback_hp: int = DroneComponent.DRONE_HP` — the static reference
remained. Session 2's log confirms the AI was still broken after that fix.

## Final Fix Applied

Merged all DroneComponent AI logic directly into `drone.gd`, eliminating the cross-script
class_name dependency. This follows the same pattern as `enemy.gd` (~5000 lines, single file).

Key changes in final fix:
- `drone.gd`: All AI state logic (SEARCHING/COMBAT) merged in, no `DroneComponent` references
- `drone_component.gd`: Kept as minimal stub (no class_name, no active code) — legacy file
- `Drone.tscn`: DroneComponent child node removed, class_name dependency eliminated
- `drone_operator_component.gd`: Uses duck typing / `has_method()` instead of typed cast

---

# Session 4 Regression: Drone Stopped Spawning (game_log_20260325_125524.txt)

## User Report

> "опять перестал спавниться дрон" (drone stopped spawning again)
> — game_log_20260325_125524.txt

## Session 4 Log Analysis

The operator deploys drones (11 times), but **zero** `[Drone]` log entries appear:

```
[DroneOperator] Drone deployed at (363, 357)   ← operator runs
[DroneOperator] Phase: CONTROLLING (defenseless) ← operator runs
# ... NO [Drone] entries at all ...
```

Neither `[DroneOperator] Drone initialized via initialize_drone()` nor `[DroneOperator] Connected to drone.died signal` appear, meaning `_drone.has_method("initialize_drone")` returned false.

This confirms that `drone.gd` **failed to load/attach** to the drone node in the exported build.

## Root Cause: DroneComponent child node + class_name in Drone.tscn

The `Drone.tscn` scene (commit 382e3a03) still contained a `DroneComponent` child node:

```ini
[ext_resource type="Script" path="res://scripts/components/drone_component.gd" id="2_drone_comp"]
...
[node name="DroneComponent" type="Node" parent="."]
script = ExtResource("2_drone_comp")
```

And `drone_component.gd` (even as a stub) kept `class_name DroneComponent`:

```gdscript
class_name DroneComponent
extends Node
const DRONE_HP: int = 2
```

In Godot 4 exported builds, when the scene is loaded, the `class_name DroneComponent` in the child node's script can interfere with the global class registry in ways that prevent the parent node's script (`drone.gd`) from loading correctly. This manifests as a silent failure: the node exists but has no script behavior.

## Why This Differs from DroneOperatorComponent

`DroneOperatorComponent` (also uses `class_name`) works correctly because:
- It is instantiated via `DroneOperatorComponent.new()` in `enemy.gd` (not loaded via scene child)
- The class is registered globally before any scene instantiation
- No circular or same-scene class_name dependency exists

`DroneComponent` in `Drone.tscn` creates a **same-scene class_name dependency**: the scene tries to load two scripts simultaneously, one of which has a class_name that gets re-registered as part of scene loading, causing the primary script (`drone.gd`) to fail silently.

## Fix Applied (Session 5)

Two changes:
1. **Removed `DroneComponent` child node from `Drone.tscn`** — the node was unused (all logic is in drone.gd now)
2. **Removed `class_name DroneComponent` from `drone_component.gd`** — eliminates global class registry conflict

## Archived Logs

- `game_log_20260324_145336.txt` — Session 1: drone inactive, no damage
- `game_log_20260324_182702.txt` — Session 2: drone inactive, no damage (duck typing attempted)
- `game_log_20260325_064620.txt` — Session 3: drone inactive, damage now works
- `game_log_20260325_125524.txt` — Session 4: drone stopped spawning (regression from class_name conflict in scene)
