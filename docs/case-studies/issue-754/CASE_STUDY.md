# Case Study: Issue #754 - Enemies Shoot at Player's Muzzle Flash

## Issue Summary

**Issue Number:** #754
**Title:** Enemies shoot at muzzle flash (враги должны стрелять по вспышкам оружия)
**Status:** Open
**Author:** Jhon-Crow

### Original Description (Russian)
> враги должны стрелять по вспышкам оружия игрока если нет возможности стрелять по игроку (игрок не виден и сейчас не кидается граната). должно работать для всего оружия. впиши это поведение в существующий GOAP.

### Translation
> Enemies should shoot at the player's weapon muzzle flash if they cannot shoot directly at the player (player not visible AND no grenade is currently being thrown). This behavior should work for all weapons. Implement this behavior into the existing GOAP system.

---

## Problem Analysis

### Scenario Description

When the player is behind cover (not visible to enemies), but fires their weapon:
1. The muzzle flash creates a brief visual cue at the weapon's barrel
2. Enemies who can see the muzzle flash (even though they cannot see the player) should be able to:
   - Estimate the player's position based on the flash location
   - Fire suppressive rounds at the flash position
   - Integrate this behavior into GOAP planning

### Condition for Activation

The muzzle flash shooting behavior should activate ONLY when:
1. `player_visible == false` - Enemy cannot directly see the player
2. `!player.is_preparing_grenade()` - Player is NOT currently preparing/throwing a grenade

The grenade condition ensures enemies don't waste ammunition shooting at muzzle flash when the player is exposed and throwing a grenade (they should shoot the player directly in that case).

---

## Current Codebase Analysis

### Existing Systems to Leverage

#### 1. Muzzle Flash System (`scripts/effects/muzzle_flash.gd`)

The muzzle flash is a visual effect with:
- Duration: `FLASH_DURATION = 0.3` seconds
- Point light with `LIGHT_START_ENERGY = 4.5`
- GPUParticles2D for visual effect
- Spawned at bullet spawn position when player shoots

#### 2. ImpactEffectsManager (`scripts/autoload/impact_effects_manager.gd`)

The `spawn_muzzle_flash(position, direction)` function:
- Creates muzzle flash at given position
- Direction determines flash orientation
- Called when player fires weapon

#### 3. Enemy Memory System (`scripts/ai/enemy_memory.gd`)

Confidence-based memory system:
- `VISUAL_DETECTION_CONFIDENCE = 1.0`
- `SOUND_GUNSHOT_CONFIDENCE = 0.7`
- Supports position updates with confidence levels
- Decays over time

#### 4. Flashlight Detection Component (`scripts/components/flashlight_detection_component.gd`)

**Key pattern to follow** - this component:
- Detects visual cues (flashlight beam)
- Estimates player position from the light source
- Integrates with GOAP via world state flags
- Uses raycasts for line-of-sight verification

#### 5. Sound Propagation System (`scripts/autoload/sound_propagation.gd`)

Already detects gunshots:
- `SoundType.GUNSHOT` propagates ~1469px (viewport diagonal)
- Enemies already hear gunshots and update memory
- But sound doesn't provide visual targeting

#### 6. GOAP System (`scripts/ai/enemy_actions.gd`)

Existing investigation actions:
- `InvestigateFlashlightAction` - investigates flashlight sources
- `InvestigateHighConfidenceAction` - pursues high-confidence positions
- Enemy world state includes `player_visible`, `has_suspected_position`, etc.

---

## Proposed Solution Architecture

### Solution Overview

Create a `MuzzleFlashDetectionComponent` similar to `FlashlightDetectionComponent` that:
1. Tracks active muzzle flash positions globally (via ImpactEffectsManager)
2. Allows enemies to detect visible muzzle flashes within their FOV
3. Updates enemy memory with estimated player position
4. Adds a GOAP action for shooting at detected muzzle flash

### Component Diagram

```
Player fires weapon
        │
        ▼
ImpactEffectsManager.spawn_muzzle_flash()
        │
        ├── Creates MuzzleFlash node
        │
        └── Registers flash position + direction + timestamp
                │
                ▼
Enemy._process() → MuzzleFlashDetectionComponent.check_muzzle_flash()
        │
        ├── Check if any flash is within enemy FOV
        ├── Check line-of-sight to flash position
        ├── Check conditions: !player_visible && !player.is_preparing_grenade()
        │
        ▼
If flash detected:
        │
        ├── Update enemy memory with flash position (confidence ~0.65)
        ├── Set GOAP world state: "muzzle_flash_detected" = true
        │
        ▼
GOAP Planner selects: ShootAtMuzzleFlashAction
        │
        ▼
Enemy shoots suppressive fire at estimated player position
```

### New Components to Create

#### 1. MuzzleFlashDetectionComponent (`scripts/components/muzzle_flash_detection_component.gd`)

```gdscript
class_name MuzzleFlashDetectionComponent
extends RefCounted
## Component for detecting player weapon muzzle flashes (Issue #754).
##
## When the enemy cannot see the player but can see their muzzle flash,
## they estimate the player's position from the flash location and direction.
## This enables suppressive fire behavior.

## Confidence level when detecting player via muzzle flash.
## Lower than flashlight (0.75) because flash is very brief (~0.3s).
## Higher than sound only (0.5) because it provides directional info.
const MUZZLE_FLASH_DETECTION_CONFIDENCE: float = 0.65

## Maximum detection range for muzzle flash (in pixels).
## Should be within enemy FOV range - flashes are bright but brief.
const MUZZLE_FLASH_MAX_RANGE: float = 500.0

## Maximum age of a muzzle flash to still be detectable (seconds).
## Matches FLASH_DURATION from muzzle_flash.gd
const FLASH_MAX_AGE: float = 0.3

## Whether the enemy currently detects a muzzle flash.
var detected: bool = false

## The estimated player position based on the muzzle flash.
var estimated_player_position: Vector2 = Vector2.ZERO

## The direction the weapon was pointing (from flash direction).
var flash_direction: Vector2 = Vector2.ZERO

## Debug logging flag.
var debug_logging: bool = false

## Reference to ImpactEffectsManager for flash tracking.
var _impact_manager: Node = null


func check_muzzle_flash(
    enemy_pos: Vector2,
    enemy_facing_angle: float,
    enemy_fov_deg: float,
    enemy_fov_enabled: bool,
    player: Node2D,
    raycast: RayCast2D,
    can_see_player: bool
) -> bool:
    # Reset detection state
    detected = false
    estimated_player_position = Vector2.ZERO
    flash_direction = Vector2.ZERO

    # Condition 1: Only detect if player is NOT visible
    if can_see_player:
        return false

    # Condition 2: Only detect if player is NOT preparing/throwing grenade
    if player and player.has_method("is_preparing_grenade"):
        if player.is_preparing_grenade():
            return false

    # Get active muzzle flashes from ImpactEffectsManager
    if _impact_manager == null:
        _impact_manager = player.get_node_or_null("/root/ImpactEffectsManager")
    if _impact_manager == null:
        return false

    # Check active flashes (need to add get_active_muzzle_flashes method)
    if not _impact_manager.has_method("get_active_muzzle_flashes"):
        return false

    var active_flashes: Array = _impact_manager.get_active_muzzle_flashes()

    for flash in active_flashes:
        var flash_pos: Vector2 = flash.position
        var flash_dir: Vector2 = flash.direction
        var flash_age: float = flash.age

        # Check flash age
        if flash_age > FLASH_MAX_AGE:
            continue

        # Check distance
        var dist: float = enemy_pos.distance_to(flash_pos)
        if dist > MUZZLE_FLASH_MAX_RANGE:
            continue

        # Check FOV (if enabled)
        if enemy_fov_enabled and enemy_fov_deg > 0.0:
            var enemy_facing_dir := Vector2.from_angle(enemy_facing_angle)
            var dir_to_flash := (flash_pos - enemy_pos).normalized()
            var dot := enemy_facing_dir.dot(dir_to_flash)
            var fov_half_angle := deg_to_rad(enemy_fov_deg / 2.0)
            if dot < cos(fov_half_angle):
                continue  # Outside FOV

        # Check line-of-sight to flash
        if raycast != null:
            var has_los := _check_los_to_flash(enemy_pos, flash_pos, raycast)
            if not has_los:
                continue

        # Detection confirmed
        detected = true
        # Estimate player position: flash position minus direction * weapon offset
        # The player is behind the flash, in the opposite direction
        estimated_player_position = flash_pos - flash_dir * 30.0  # ~bullet_spawn_offset
        flash_direction = flash_dir
        return true

    return false


## Check line-of-sight from enemy to muzzle flash position.
func _check_los_to_flash(enemy_pos: Vector2, flash_pos: Vector2, raycast: RayCast2D) -> bool:
    if raycast == null:
        return true

    var original_target := raycast.target_position
    var original_enabled := raycast.enabled

    raycast.target_position = flash_pos - enemy_pos
    raycast.enabled = true
    raycast.force_raycast_update()

    var has_los := true
    if raycast.is_colliding():
        var collision_point := raycast.get_collision_point()
        var dist_to_flash := enemy_pos.distance_to(flash_pos)
        var dist_to_collision := enemy_pos.distance_to(collision_point)
        has_los = dist_to_collision >= dist_to_flash - 10.0

    raycast.target_position = original_target
    raycast.enabled = original_enabled

    return has_los


func reset() -> void:
    detected = false
    estimated_player_position = Vector2.ZERO
    flash_direction = Vector2.ZERO
```

#### 2. New GOAP Action: ShootAtMuzzleFlashAction

```gdscript
## Action to shoot at detected muzzle flash position (Issue #754).
## When enemy cannot see the player but can see their muzzle flash,
## fire suppressive rounds at the estimated position.
class ShootAtMuzzleFlashAction extends GOAPAction:
    func _init() -> void:
        super._init("shoot_at_muzzle_flash", 1.8)
        preconditions = {
            "player_visible": false,
            "muzzle_flash_detected": true
        }
        effects = {
            "suppressive_fire_delivered": true
        }

    func get_cost(_agent: Node, world_state: Dictionary) -> float:
        # Higher priority when recently detected (fresh flash)
        if world_state.get("muzzle_flash_detected", false):
            return 1.5  # Lower cost than patrol, higher than direct engagement
        return 100.0
```

#### 3. Modifications to ImpactEffectsManager

Add tracking for active muzzle flashes:

```gdscript
## Active muzzle flash data for enemy detection (Issue #754)
var _active_muzzle_flashes: Array = []

## Structure for flash data
class MuzzleFlashData:
    var position: Vector2
    var direction: Vector2
    var timestamp: float

func spawn_muzzle_flash(position: Vector2, direction: Vector2, ...) -> void:
    # ... existing code ...

    # Track flash for enemy detection (Issue #754)
    var flash_data := MuzzleFlashData.new()
    flash_data.position = position
    flash_data.direction = direction.normalized()
    flash_data.timestamp = Time.get_ticks_msec() / 1000.0
    _active_muzzle_flashes.append(flash_data)

func get_active_muzzle_flashes() -> Array:
    var current_time := Time.get_ticks_msec() / 1000.0
    # Clean up old flashes
    _active_muzzle_flashes = _active_muzzle_flashes.filter(
        func(f): return current_time - f.timestamp < 0.5
    )
    # Return with age calculated
    var result := []
    for flash in _active_muzzle_flashes:
        result.append({
            "position": flash.position,
            "direction": flash.direction,
            "age": current_time - flash.timestamp
        })
    return result
```

#### 4. Modifications to Enemy (`scripts/objects/enemy.gd`)

```gdscript
## Muzzle flash detection component (Issue #754)
var _muzzle_flash_detection: MuzzleFlashDetectionComponent = null

func _ready() -> void:
    # ... existing code ...
    _setup_muzzle_flash_detection()

func _setup_muzzle_flash_detection() -> void:
    _muzzle_flash_detection = MuzzleFlashDetectionComponent.new()

func _check_player_visibility() -> void:
    # ... existing visibility code ...

    # Check for muzzle flash when player is NOT visible (Issue #754)
    if _muzzle_flash_detection and _player and not _can_see_player:
        var flash_detected := _muzzle_flash_detection.check_muzzle_flash(
            global_position,
            _enemy_model.global_rotation if _enemy_model else rotation,
            fov_angle,
            fov_enabled and _is_fov_globally_enabled(),
            _player,
            _raycast,
            _can_see_player
        )

        if flash_detected:
            _goap_world_state["muzzle_flash_detected"] = true
            # Update memory with estimated position
            if _memory:
                _memory.update_position(
                    _muzzle_flash_detection.estimated_player_position,
                    MuzzleFlashDetectionComponent.MUZZLE_FLASH_DETECTION_CONFIDENCE
                )
        else:
            _goap_world_state["muzzle_flash_detected"] = false
```

---

## Implementation Considerations

### Confidence Level for Muzzle Flash

Suggested: **0.65** (between sound 0.5-0.7 and flashlight 0.75)

Rationale:
- More reliable than pure sound (provides visual direction)
- Less reliable than flashlight (very brief duration)
- Should trigger investigation but not full pursuit

### Suppressive Fire Behavior

When shooting at muzzle flash:
1. Fire 2-3 rounds toward estimated position
2. Add spread/inaccuracy (e.g., ±0.2 radians)
3. Short burst, then return to cover
4. Don't waste entire magazine on suppression

### Performance Optimization

- Only check muzzle flash when `player_visible == false`
- Use interval checking (e.g., every 0.15s) like FlashlightDetectionComponent
- Clean up expired flash data regularly
- Limit active flash tracking to most recent N flashes

### Integration with Existing Systems

1. **Sound Propagation**: Muzzle flash detection complements existing gunshot sound detection
2. **Enemy Memory**: Uses same confidence/decay system
3. **GOAP Planning**: New action integrates with existing action set
4. **Flashlight Detection**: Follows same detection pattern

---

## References

### Online Research

1. [Building the AI of F.E.A.R. with Goal Oriented Action Planning](https://www.gamedeveloper.com/design/building-the-ai-of-f-e-a-r-with-goal-oriented-action-planning) - Classic GOAP implementation reference
2. [Goal Oriented Action Planning](https://medium.com/@vedantchaudhari/goal-oriented-action-planning-34035ed40d0b) - GOAP architecture overview
3. [GOAP Theory](https://goap.crashkonijn.com/readme/theory) - Goal selection and plan interruption
4. [ARMA AI Muzzle Flash Detection](https://steamcommunity.com/app/107410/discussions/0/558752449933013721/?l=brazilian) - Example of AI seeing muzzle flashes at night
5. [GROUND BRANCH AI Updates](https://www.groundbranch.com/2024/03/21/) - Suppressive fire and muzzle flash visibility for AI
6. [Predictive Aim Mathematics for AI Targeting](https://www.gamedeveloper.com/programming/predictive-aim-mathematics-for-ai-targeting) - AI targeting calculations

### Related Codebase Files

- `scripts/effects/muzzle_flash.gd` - Muzzle flash visual effect
- `scripts/autoload/impact_effects_manager.gd` - Flash spawning
- `scripts/ai/enemy_actions.gd` - GOAP actions
- `scripts/ai/enemy_memory.gd` - Memory system
- `scripts/ai/goap_planner.gd` - GOAP planner
- `scripts/components/flashlight_detection_component.gd` - Pattern to follow
- `scripts/autoload/sound_propagation.gd` - Sound detection pattern
- `scripts/objects/enemy.gd` - Enemy AI integration

### Related Issues

- Issue #574 - Flashlight detection (similar visual detection pattern)
- Issue #297 - Enemy memory confidence system
- Issue #298 - Player prediction component

---

## Estimated Complexity

**Medium** - Requires:
- 1 new component class (~150 lines)
- 1 new GOAP action (~25 lines)
- Modifications to ImpactEffectsManager (~30 lines)
- Modifications to Enemy (~40 lines)
- Total: ~245 lines of new/modified code

**Risk Level**: Low - follows established patterns in codebase

---

## Implementation Status

### Implemented (PR #800)

The muzzle flash detection feature has been implemented with the following components:

1. **MuzzleFlashDetectionComponent** (`scripts/components/muzzle_flash_detection_component.gd`)
   - Detects player weapon muzzle flashes within enemy FOV
   - Estimates player position from flash location and direction
   - Uses interval-based checking (0.1s) to reduce overhead
   - Respects activation conditions: player not visible AND not preparing grenade

2. **ImpactEffectsManager modifications** (`scripts/autoload/impact_effects_manager.gd`)
   - Added `_active_muzzle_flashes` array to track recent flashes
   - Added `_track_muzzle_flash()` function called when spawning muzzle flash
   - Added `get_active_muzzle_flashes()` public function for enemy detection
   - Flash tracking limited to 10 entries, auto-cleaned after 0.5s

3. **ShootAtMuzzleFlashAction** (`scripts/ai/enemy_actions.gd`)
   - New GOAP action for suppressive fire at muzzle flash position
   - Preconditions: `player_visible=false`, `muzzle_flash_detected=true`, `player_preparing_grenade=false`
   - Cost: 1.0 (higher priority than patrol, similar to flashlight investigation)

4. **Enemy integration** (`scripts/objects/enemy.gd`)
   - Added `_muzzle_flash_detection` component initialization
   - Added GOAP world state: `muzzle_flash_detected`, `player_preparing_grenade`
   - Detection logic in `_update_memory()` following flashlight detection pattern
   - Updates enemy memory with estimated player position at confidence 0.65

### Test Data

Game log from testing session saved to: `docs/case-studies/issue-754/game_log_20260216_003239.txt`
