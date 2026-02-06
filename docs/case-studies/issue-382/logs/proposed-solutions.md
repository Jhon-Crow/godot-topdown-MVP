# Proposed Solutions for Issue #382

## Overview

This document outlines three implementation approaches for tactical enemy grenade throwing, ordered by complexity and feature completeness.

---

## Solution A: Minimal Implementation (Component Extension)

**Complexity**: Medium
**Estimated Lines**: ~250 new/modified

### Description

Extend the existing `EnemyGrenadeComponent` to add the new trigger condition and basic ally notification, without full assault coordination.

### Implementation

#### 1. New Trigger: Player Seen Then Hidden

Add to `EnemyGrenadeComponent`:

```gdscript
# Trigger 8: Player Seen Then Hidden
var _player_was_seen: bool = false
var _player_hidden_timer: float = 0.0
const PLAYER_HIDDEN_TACTICAL_WINDOW: float = 3.0  # Seconds after player hides

func _t8(can_see: bool, memory_has_target: bool) -> bool:
    if can_see:
        _player_was_seen = true
        _player_hidden_timer = 0.0
        return false

    if _player_was_seen and memory_has_target:
        return _player_hidden_timer >= PLAYER_HIDDEN_TACTICAL_WINDOW

    return false

func update(delta: float, can_see: bool, ...):
    # ... existing code ...

    # Trigger 8: Player seen then hidden
    if _player_was_seen and not can_see:
        _player_hidden_timer += delta
    elif can_see:
        _player_hidden_timer = 0.0
```

#### 2. Basic Ally Warning (Signal-based)

```gdscript
# In EnemyGrenadeComponent
signal grenade_warning(thrower: Node, target_position: Vector2, blast_radius: float)

func _execute_throw(target: Vector2, ...):
    # Broadcast warning before throw
    var blast_radius := _get_blast_radius()
    grenade_warning.emit(_enemy, target, blast_radius)

    # Existing delay
    if throw_delay > 0.0:
        await get_tree().create_timer(throw_delay).timeout

    # ... rest of existing throw code ...
```

#### 3. Enemy.gd Integration

```gdscript
# In enemy.gd _setup_grenade_component()
_grenade_component.grenade_warning.connect(_on_ally_grenade_warning)

func _on_ally_grenade_warning(thrower: Node, target: Vector2, blast_radius: float):
    if thrower == self:
        return  # Don't evacuate from own grenade

    var distance_to_blast := global_position.distance_to(target)
    if distance_to_blast < blast_radius + 50.0:  # Add margin
        _start_evacuation(target, blast_radius)

func _start_evacuation(blast_center: Vector2, radius: float):
    # Simple evacuation: move away from blast
    var away_direction := (global_position - blast_center).normalized()
    var safe_distance := radius + 100.0
    _cover_position = global_position + away_direction * safe_distance
    _transition_to_seeking_cover()
```

### Pros
- Minimal changes to existing code
- Uses existing signal system
- Easy to test and debug

### Cons
- No coordinated assault after explosion
- Simple evacuation (no pathfinding)
- No waiting for explosion logic

---

## Solution B: Coordinator Pattern (New Autoload)

**Complexity**: High
**Estimated Lines**: ~450 new

### Description

Introduce a `TacticalGrenadeCoordinator` autoload that manages inter-enemy communication, evacuation, and assault coordination.

### Implementation

#### 1. TacticalGrenadeCoordinator Autoload

```gdscript
# scripts/autoload/tactical_grenade_coordinator.gd
extends Node
class_name TacticalGrenadeCoordinator

## Manages tactical grenade coordination between enemies.
##
## Handles:
## - Grenade throw announcements
## - Ally evacuation from blast zones
## - Post-explosion assault coordination

signal grenade_announced(thrower: Node, target: Vector2, blast_radius: float)
signal grenade_exploded(position: Vector2, thrower: Node)
signal assault_begin(passage_direction: Vector2)

## Active grenade warnings
var _active_warnings: Array[Dictionary] = []

## Enemies waiting for assault
var _assault_queue: Array[Node] = []

## Assault passage direction (from thrower)
var _assault_direction: Vector2 = Vector2.ZERO


## Announce upcoming grenade throw.
## Called by thrower before throwing.
func announce_throw(thrower: Node, target: Vector2, blast_radius: float) -> void:
    var warning := {
        "thrower": thrower,
        "target": target,
        "blast_radius": blast_radius,
        "time": Time.get_ticks_msec() / 1000.0
    }
    _active_warnings.append(warning)
    _assault_direction = (target - thrower.global_position).normalized()

    grenade_announced.emit(thrower, target, blast_radius)


## Check if an enemy is in any active danger zone.
func is_in_danger_zone(enemy_position: Vector2) -> bool:
    for warning in _active_warnings:
        var dist := enemy_position.distance_to(warning.target)
        if dist < warning.blast_radius + 50.0:
            return true
    return false


## Get the nearest danger zone for evacuation calculation.
func get_nearest_danger_zone(enemy_position: Vector2) -> Dictionary:
    var nearest := {}
    var min_dist := INF

    for warning in _active_warnings:
        var dist := enemy_position.distance_to(warning.target)
        if dist < min_dist:
            min_dist = dist
            nearest = warning

    return nearest


## Calculate evacuation direction for an enemy.
func calculate_evacuation_direction(enemy: Node, enemy_position: Vector2) -> Vector2:
    var danger := get_nearest_danger_zone(enemy_position)
    if danger.is_empty():
        return Vector2.ZERO

    # Primary: away from blast center
    var away := (enemy_position - danger.target).normalized()

    # Check if path is blocked (using enemy's navigation)
    var nav_agent: NavigationAgent2D = enemy.get_node_or_null("NavigationAgent2D")
    if nav_agent:
        var test_pos := enemy_position + away * (danger.blast_radius + 100.0)
        nav_agent.target_position = test_pos
        if nav_agent.is_navigation_finished() or not nav_agent.is_target_reachable():
            # Try perpendicular directions
            var left := away.rotated(PI / 2)
            var right := away.rotated(-PI / 2)
            # Choose direction that moves away from blast
            if (enemy_position + left * 50.0).distance_to(danger.target) > \
               (enemy_position + right * 50.0).distance_to(danger.target):
                away = left
            else:
                away = right

    return away


## Register enemy as waiting for assault.
func register_for_assault(enemy: Node) -> void:
    if enemy not in _assault_queue:
        _assault_queue.append(enemy)


## Called when grenade explodes.
func on_grenade_exploded(position: Vector2, thrower: Node = null) -> void:
    # Remove related warning
    for i in range(_active_warnings.size() - 1, -1, -1):
        if _active_warnings[i].target.distance_to(position) < 50.0:
            _active_warnings.remove_at(i)
            break

    grenade_exploded.emit(position, thrower)

    # Trigger assault
    if _assault_queue.size() > 0:
        assault_begin.emit(_assault_direction)
        _assault_queue.clear()


## Clear all warnings (e.g., on level reset).
func clear() -> void:
    _active_warnings.clear()
    _assault_queue.clear()
```

#### 2. Register in project.godot

```
[autoload]
TacticalGrenadeCoordinator="*res://scripts/autoload/tactical_grenade_coordinator.gd"
```

#### 3. New GOAP Actions

```gdscript
# In scripts/ai/enemy_actions.gd

## Action to evacuate from grenade blast zone.
class EvacuateGrenadeZoneAction extends GOAPAction:
    func _init() -> void:
        super._init("evacuate_grenade_zone", 0.0)  # Highest priority
        preconditions = {
            "in_grenade_zone": true
        }
        effects = {
            "in_grenade_zone": false,
            "waiting_for_assault": true
        }

    func get_cost(_agent: Node, _world_state: Dictionary) -> float:
        return 0.0  # Always highest priority - survival


## Action to wait for grenade explosion before assault.
class WaitForAssaultAction extends GOAPAction:
    func _init() -> void:
        super._init("wait_for_assault", 0.1)
        preconditions = {
            "waiting_for_assault": true
        }
        effects = {
            "in_assault_position": true
        }


## Action to assault after grenade explosion.
class PostGrenadeAssaultAction extends GOAPAction:
    func _init() -> void:
        super._init("post_grenade_assault", 0.2)
        preconditions = {
            "grenade_exploded": true,
            "in_assault_position": true
        }
        effects = {
            "player_engaged": true
        }
```

#### 4. Enemy.gd Integration

```gdscript
# Add new world state keys
_goap_world_state["in_grenade_zone"] = false
_goap_world_state["waiting_for_assault"] = false
_goap_world_state["grenade_exploded"] = false
_goap_world_state["in_assault_position"] = false

# Connect to coordinator in _ready()
var coordinator := get_node_or_null("/root/TacticalGrenadeCoordinator")
if coordinator:
    coordinator.grenade_announced.connect(_on_grenade_announced)
    coordinator.grenade_exploded.connect(_on_coordinator_grenade_exploded)
    coordinator.assault_begin.connect(_on_assault_begin)

func _on_grenade_announced(thrower: Node, target: Vector2, blast_radius: float):
    if thrower == self:
        return
    _goap_world_state["in_grenade_zone"] = \
        TacticalGrenadeCoordinator.is_in_danger_zone(global_position)

func _on_coordinator_grenade_exploded(position: Vector2, thrower: Node):
    _goap_world_state["grenade_exploded"] = true
    _goap_world_state["in_grenade_zone"] = false

func _on_assault_begin(passage_direction: Vector2):
    if _goap_world_state.get("waiting_for_assault", false):
        _begin_coordinated_assault(passage_direction)
```

### Pros
- Full assault coordination
- Clean separation of concerns
- Extensible for future squad tactics
- GOAP integration for AI decisions

### Cons
- More complex implementation
- New autoload required
- More testing needed

---

## Solution C: Full Tactical System (Component Suite)

**Complexity**: Very High
**Estimated Lines**: ~700+ new

### Description

Complete implementation with all requested features including:
- Advanced cover analysis for "ignoring one cover"
- Post-throw positioning
- Grenade type-specific behavior (offensive vs non-lethal)
- Full assault through passage mechanic

### Additional Components

#### 1. TacticalCoverAnalyzer

```gdscript
# scripts/components/tactical_cover_analyzer.gd
class_name TacticalCoverAnalyzer
extends Node

## Analyzes cover positions considering grenade mechanics.
##
## Provides:
## - Cover that protects from player rays (ignoring one obstacle)
## - Cover that protects from explosion rays
## - Safe distance calculations

@export var ray_count: int = 36  # Every 10 degrees

## Find cover position that protects from rays emanating from a point,
## while being within throwing range.
func find_throw_position(
    current_pos: Vector2,
    player_pos: Vector2,
    max_throw_distance: float,
    ignore_first_obstacle: bool = true
) -> Vector2:
    # Cast rays from player in all directions
    # Find positions that are:
    # 1. Within throw distance
    # 2. Have cover between position and player
    # 3. (Optional) Allow one cover to be bypassed
    pass

## Find cover that protects from explosion rays.
func find_explosion_cover(
    current_pos: Vector2,
    explosion_pos: Vector2,
    blast_radius: float
) -> Vector2:
    # Find cover that blocks line of sight to explosion point
    # Must be reachable before explosion
    pass
```

#### 2. PostThrowBehaviorComponent

```gdscript
# scripts/components/post_throw_behavior_component.gd
class_name PostThrowBehaviorComponent
extends Node

## Manages enemy behavior after throwing a grenade.
##
## Handles:
## - Aiming at impact location
## - Moving to safe distance
## - Seeking cover for non-lethal grenades
## - Assault through throw passage

var _grenade_type: String = "frag"  # or "flashbang"
var _throw_target: Vector2 = Vector2.ZERO
var _throw_passage_direction: Vector2 = Vector2.ZERO

func on_grenade_thrown(grenade: Node, target: Vector2):
    _throw_target = target
    _throw_passage_direction = (target - get_parent().global_position).normalized()

    # Determine grenade type
    if grenade is FragGrenade:
        _grenade_type = "frag"
    else:
        _grenade_type = "flashbang"

func get_post_throw_behavior() -> String:
    match _grenade_type:
        "frag":
            return "aim_and_approach"
        "flashbang":
            return "seek_cover_then_assault"
        _:
            return "aim_and_approach"

func get_assault_direction() -> Vector2:
    return _throw_passage_direction
```

#### 3. Extended Enemy States

Add new AI states:

```gdscript
enum AIState {
    # ... existing states ...
    EVACUATING_GRENADE,    # Fleeing from ally grenade blast zone
    WAITING_FOR_EXPLOSION, # Holding position until grenade explodes
    COORDINATED_ASSAULT,   # Assaulting after grenade explosion
}
```

### Implementation Phases

**Phase 1**: Basic trigger and warning (Solution A)
**Phase 2**: Coordinator and GOAP actions (Solution B)
**Phase 3**: Advanced cover analysis
**Phase 4**: Post-throw behavior
**Phase 5**: Full assault coordination

### Pros
- Complete feature implementation
- Professional-grade tactical AI
- All requirements satisfied

### Cons
- Significant development time
- May approach code line limits
- Complex testing requirements

---

## Recommendation

### For Quick Implementation
Use **Solution A** to add the basic tactical grenade trigger and simple ally notification. This can be done within the existing architecture with minimal risk.

### For Full Feature Set
Use **Solution B** as the foundation, implementing the `TacticalGrenadeCoordinator` and new GOAP actions. This provides:
- Proper inter-enemy communication
- Assault coordination
- Clean architecture for future extensions

### Future Considerations

1. The disabled `AssaultPlayerAction` (issue #169) should be re-evaluated in the context of post-grenade assault
2. Consider extracting more logic from enemy.gd to stay within the 5000-line limit
3. Add debugging visualization for grenade zones and evacuation paths

---

## Testing Strategy

### Unit Tests

1. Trigger 8 detection (player seen then hidden)
2. Evacuation direction calculation
3. Danger zone detection
4. Assault queue management

### Integration Tests

1. Multi-enemy evacuation without collisions
2. Grenade throw + explosion + assault sequence
3. GOAP plan selection with new actions
4. Interaction with existing grenade triggers

### Manual Testing Scenarios

1. Single enemy, player peeks and hides
2. Multiple enemies, one throws grenade
3. Ally in blast zone evacuates correctly
4. Post-explosion assault through doorway
5. Non-lethal grenade cover-seeking behavior
