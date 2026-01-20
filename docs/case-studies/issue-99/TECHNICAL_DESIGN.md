# Technical Design: Group Tactical AI System

## Overview

This document details the technical implementation of group tactical behavior for enemy AI, based on military tactical principles and integrated with the existing GOAP system.

## Constants and Configuration

### Communication Range

```gdscript
## Distance at which enemies can communicate verbally (1/4 viewport diagonal)
## Calculated: sqrt(1280² + 720²) / 4 ≈ 367 pixels, rounded to 360
const SQUAD_COMMUNICATION_RANGE: float = 360.0

## Minimum squad size for coordinated tactics
const MIN_SQUAD_SIZE: int = 2

## Maximum squad size (larger groups split into multiple squads)
const MAX_SQUAD_SIZE: int = 5
```

### Timing Constants

```gdscript
## How often to update squad membership (seconds)
const SQUAD_UPDATE_INTERVAL: float = 0.5

## Delay before coordinated actions begin (allows formation)
const SQUAD_COORDINATION_DELAY: float = 1.0

## Suppression duration before flanker moves (seconds)
const SUPPRESSION_DURATION_BEFORE_FLANK: float = 2.0

## Maximum time to wait for squad coordination
const SQUAD_COORDINATION_TIMEOUT: float = 5.0
```

## Data Structures

### SquadRole Enum

```gdscript
## Tactical roles for squad members
enum SquadRole {
    NONE,           ## Operating independently (no squad)
    LEADER,         ## Makes tactical decisions, coordinates timing
    SUPPRESSOR,     ## Provides covering fire to pin player
    FLANKER,        ## Moves to flank position under cover of suppression
    ASSAULT,        ## Primary attacker after flanker is in position
    REAR_GUARD      ## Covers retreat path, rear security
}
```

### SquadInfo Class

```gdscript
## Information about a tactical squad
class SquadInfo:
    var members: Array[Node2D] = []          ## All squad members
    var leader: Node2D = null                ## Elected leader
    var center_position: Vector2             ## Average position of squad
    var formation_ready: bool = false        ## Whether squad is formed up
    var current_tactic: String = ""          ## Active coordinated tactic
    var suppression_active: bool = false     ## Suppressor is firing
    var flanker_in_position: bool = false    ## Flanker reached target
```

## New Instance Variables in enemy.gd

```gdscript
## --- Squad Coordination Variables ---
## Current squad this enemy belongs to
var _squad_members: Array[Node2D] = []

## Current role in the squad
var _squad_role: SquadRole = SquadRole.NONE

## Whether this enemy is the squad leader
var _is_squad_leader: bool = false

## Timer for squad membership updates
var _squad_update_timer: float = 0.0

## Last known positions of squad members (for coordination)
var _squad_member_positions: Dictionary = {}

## Whether squad coordination is active
var _squad_coordination_active: bool = false

## Timer for coordination delay
var _squad_coordination_timer: float = 0.0

## Target position for coordinated movement
var _squad_target_position: Vector2 = Vector2.ZERO

## Whether this enemy is providing suppression fire
var _providing_suppression: bool = false

## Timer for suppression duration
var _suppression_timer: float = 0.0
```

## Core Functions

### Squad Detection

```gdscript
## Find all enemies within communication range
## Returns array of enemy nodes that can form a squad
func _find_nearby_squad_members() -> Array[Node2D]:
    var nearby: Array[Node2D] = []
    var enemies := get_tree().get_nodes_in_group("enemies")

    for enemy in enemies:
        if enemy == self:
            continue
        if not is_instance_valid(enemy):
            continue
        if not enemy.has_method("is_alive") or not enemy.is_alive():
            continue

        var distance := global_position.distance_to(enemy.global_position)
        if distance <= SQUAD_COMMUNICATION_RANGE:
            nearby.append(enemy)

    return nearby
```

### Leader Election

```gdscript
## Elect squad leader based on tactical criteria
## Leader is the enemy closest to the player (best awareness)
## Ties broken by health (more health = more reliable leader)
func _elect_squad_leader(squad: Array[Node2D]) -> Node2D:
    if squad.is_empty():
        return null
    if _player == null:
        return squad[0]  # Fallback to first member

    var best_leader: Node2D = null
    var best_score: float = INF

    for member in squad:
        if not is_instance_valid(member):
            continue

        var distance := member.global_position.distance_to(_player.global_position)
        # Lower distance = better (closer has better awareness)
        # Use negative health as tiebreaker (more health = better)
        var health_bonus := 0.0
        if member.has_method("get_health_ratio"):
            health_bonus = -member.get_health_ratio() * 10.0

        var score := distance + health_bonus
        if score < best_score:
            best_score = score
            best_leader = member

    return best_leader
```

### Role Assignment

```gdscript
## Assign tactical roles to squad members based on position and situation
## Called by the squad leader
func _assign_squad_roles() -> void:
    if not _is_squad_leader:
        return
    if _squad_members.size() < MIN_SQUAD_SIZE:
        return
    if _player == null:
        return

    var player_pos := _player.global_position
    var player_facing := _get_player_facing_direction()

    # Sort squad members by angle to player's facing direction
    var members_by_flank: Array = []
    for member in _squad_members:
        if not is_instance_valid(member):
            continue
        var to_member := member.global_position - player_pos
        var angle_to_member := to_member.angle()
        var angle_diff := abs(angle_difference(player_facing.angle(), angle_to_member))
        members_by_flank.append({"enemy": member, "angle_diff": angle_diff})

    members_by_flank.sort_custom(func(a, b): return a.angle_diff > b.angle_diff)

    # Assign roles:
    # - Enemy most to the side = FLANKER
    # - Enemy most in front (player looking at) = SUPPRESSOR
    # - Leader = ASSAULT (after flanker is in position)
    # - Others = REAR_GUARD or ASSAULT

    var role_index := 0
    for member_info in members_by_flank:
        var member: Node2D = member_info.enemy
        var role: SquadRole

        if role_index == 0:
            role = SquadRole.FLANKER
        elif role_index == 1:
            role = SquadRole.SUPPRESSOR
        elif role_index == 2:
            role = SquadRole.ASSAULT
        else:
            role = SquadRole.REAR_GUARD

        if member.has_method("set_squad_role"):
            member.set_squad_role(role)

        role_index += 1

    # Leader takes ASSAULT role but coordinates timing
    _squad_role = SquadRole.LEADER
```

### Get Player Facing Direction

```gdscript
## Get the direction the player is currently facing
func _get_player_facing_direction() -> Vector2:
    if _player == null:
        return Vector2.RIGHT

    if _player.has_method("get_aim_direction"):
        return _player.get_aim_direction()

    # Fallback: use player's rotation
    return Vector2.from_angle(_player.rotation)
```

## New GOAP World State Updates

Add to `_update_goap_world_state()`:

```gdscript
# Squad coordination state
_goap_world_state["squad_size"] = _squad_members.size() + 1  # Include self
_goap_world_state["has_squad"] = _squad_members.size() >= MIN_SQUAD_SIZE - 1
_goap_world_state["squad_role"] = _squad_role
_goap_world_state["is_squad_leader"] = _is_squad_leader
_goap_world_state["squad_suppressing"] = _is_suppression_active()
_goap_world_state["squad_flanker_ready"] = _is_flanker_in_position()
```

## New GOAP Actions

### ProvideSuppressionAction

```gdscript
## Action to provide suppression fire while squadmates flank
class ProvideSuppressionAction extends GOAPAction:
    func _init() -> void:
        super._init("provide_suppression", 0.8)
        preconditions = {
            "player_visible": true,
            "has_squad": true
        }
        effects = {
            "squad_suppressing": true,
            "player_engaged": true
        }

    func get_cost(agent: Node, world_state: Dictionary) -> float:
        var role = world_state.get("squad_role", 0)
        # Only low cost if this enemy is assigned SUPPRESSOR role
        if role == SquadRole.SUPPRESSOR:
            return 0.3  # High priority
        return 10.0  # Very low priority for other roles
```

### CoordinatedFlankAction

```gdscript
## Action to flank while suppressor provides cover
class CoordinatedFlankAction extends GOAPAction:
    func _init() -> void:
        super._init("coordinated_flank", 0.6)
        preconditions = {
            "has_squad": true,
            "squad_suppressing": true
        }
        effects = {
            "at_flank_position": true,
            "player_visible": true
        }

    func get_cost(agent: Node, world_state: Dictionary) -> float:
        var role = world_state.get("squad_role", 0)
        # Only low cost if this enemy is assigned FLANKER role
        if role == SquadRole.FLANKER:
            return 0.4  # High priority when suppression is active
        return 10.0  # Very low priority for other roles
```

### CoordinatedAssaultAction

```gdscript
## Action for coordinated assault after flanker is in position
class CoordinatedAssaultAction extends GOAPAction:
    func _init() -> void:
        super._init("coordinated_assault", 0.4)
        preconditions = {
            "player_visible": true,
            "has_squad": true,
            "squad_flanker_ready": true
        }
        effects = {
            "player_engaged": true,
            "is_assaulting": true
        }

    func get_cost(agent: Node, world_state: Dictionary) -> float:
        var role = world_state.get("squad_role", 0)
        # Low cost for ASSAULT and LEADER roles
        if role in [SquadRole.ASSAULT, SquadRole.LEADER]:
            return 0.3  # High priority
        return 5.0  # Medium priority for others
```

### CrossCoverAction

```gdscript
## Action for bounding overwatch movement between covers
class CrossCoverAction extends GOAPAction:
    func _init() -> void:
        super._init("cross_cover", 1.5)
        preconditions = {
            "has_squad": true,
            "squad_suppressing": true,
            "in_cover": true
        }
        effects = {
            "advanced_position": true,
            "in_cover": true
        }

    func get_cost(agent: Node, world_state: Dictionary) -> float:
        # Lower cost when squad is providing suppression
        if world_state.get("squad_suppressing", false):
            return 0.8
        return 3.0
```

## State Processing Updates

### Suppression State Processing

```gdscript
## Process suppression behavior when providing cover fire
func _process_suppression_state(delta: float) -> void:
    if _player == null:
        return

    _suppression_timer += delta

    # Face player and shoot at a moderate rate
    var target_pos := _player.global_position
    var direction := (target_pos - global_position).normalized()
    _rotate_toward_direction(direction, delta)

    # Shoot to suppress (don't need perfect accuracy)
    if _can_shoot() and _detection_delay_elapsed:
        _shoot_with_spread(direction, SUPPRESSION_SPREAD)

    # Signal to flankers that suppression is active
    _providing_suppression = true

    # Check if we should stop suppression
    if not _can_see_player:
        _providing_suppression = false
        _transition_to_state(AIState.IN_COVER)

    # Transition to assault if flanker is in position
    if _is_flanker_in_position() and _suppression_timer > SUPPRESSION_DURATION_BEFORE_FLANK:
        _providing_suppression = false
        _transition_to_state(AIState.ASSAULT)
```

## Squad Communication System

### Broadcast to Squad

```gdscript
## Send a tactical message to all squad members
func _broadcast_to_squad(message_type: String, data: Dictionary = {}) -> void:
    for member in _squad_members:
        if not is_instance_valid(member):
            continue
        if member.has_method("receive_squad_message"):
            member.receive_squad_message(message_type, self, data)

## Receive a message from a squad member
func receive_squad_message(message_type: String, sender: Node2D, data: Dictionary) -> void:
    match message_type:
        "suppression_started":
            # Flanker can start moving
            if _squad_role == SquadRole.FLANKER:
                _squad_coordination_active = true
        "flanker_in_position":
            # All can assault
            if _squad_role in [SquadRole.LEADER, SquadRole.ASSAULT]:
                _start_coordinated_assault()
        "player_position":
            # Update last known player position
            _last_known_player_position = data.get("position", Vector2.ZERO)
        "retreat_called":
            # All squad members should retreat
            _initiate_squad_retreat()
```

## Integration with Existing Systems

### Modified _count_enemies_in_combat

The existing function will remain but we add a new one for squad awareness:

```gdscript
## Count squad members in combat (only within communication range)
func _count_squad_in_combat() -> int:
    var count := 0
    for member in _squad_members:
        if not is_instance_valid(member):
            continue
        if member.has_method("get_current_state"):
            var state = member.get_current_state()
            if state in [AIState.COMBAT, AIState.ASSAULT, AIState.IN_COVER]:
                count += 1
    if _current_state in [AIState.COMBAT, AIState.ASSAULT, AIState.IN_COVER]:
        count += 1
    return count
```

### Priority System

Squad actions have costs adjusted so they are preferred over individual actions when a squad is present:

| Action | Base Cost | With Squad (Correct Role) |
|--------|-----------|--------------------------|
| EngagePlayerAction | 1.0 | 1.0 (unchanged) |
| FlankPlayerAction | 3.0 | 3.0 (unchanged) |
| ProvideSuppressionAction | 10.0 | 0.3 (SUPPRESSOR only) |
| CoordinatedFlankAction | 10.0 | 0.4 (FLANKER only) |
| CoordinatedAssaultAction | 5.0 | 0.3 (ASSAULT/LEADER) |

## Testing Scenarios

### Test 1: Two Enemies in Range
- Expected: One suppressor, one flanker
- Verify: Flanker waits for suppression before moving

### Test 2: Three Enemies in Range
- Expected: Suppressor, flanker, assault
- Verify: Assault waits for flanker in position

### Test 3: Enemies Out of Range
- Expected: Individual behavior (existing)
- Verify: No squad role assignment

### Test 4: Squad Member Dies
- Expected: Role reassignment
- Verify: Remaining enemies adapt

### Test 5: Player Breaks Line of Sight
- Expected: Squad pursues together
- Verify: Maintain communication range

## Performance Considerations

1. **Squad update interval**: 0.5s prevents constant recalculation
2. **Limited squad size**: Max 5 prevents O(n²) explosion
3. **Lazy evaluation**: Only active squads process coordination
4. **Early exits**: Quick checks before expensive operations
