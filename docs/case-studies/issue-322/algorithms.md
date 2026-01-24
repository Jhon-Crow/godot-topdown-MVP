# Search Algorithms Reference

This document provides detailed algorithm implementations for the enemy search state feature (Issue #322).

## 1. Expanding Square Search Algorithm

The expanding square search is a systematic pattern used in Search and Rescue operations.

### Core Algorithm

```gdscript
class_name ExpandingSquareSearch
extends RefCounted

## Search configuration
var center: Vector2
var initial_leg_length: float
var expansion_rate: float
var max_radius: float

## Search state
var current_position: Vector2
var leg_length: float
var direction: int = 0  # 0=North, 1=East, 2=South, 3=West
var legs_completed: int = 0
var points_in_current_leg: int = 0
var points_per_leg: int

## Direction vectors (clockwise from North)
const DIRECTIONS := [
    Vector2(0, -1),   # North (up in Godot 2D)
    Vector2(1, 0),    # East
    Vector2(0, 1),    # South (down in Godot 2D)
    Vector2(-1, 0)    # West
]

func _init(search_center: Vector2, initial_length: float = 50.0,
           expansion: float = 25.0, max_search_radius: float = 500.0) -> void:
    center = search_center
    initial_leg_length = initial_length
    expansion_rate = expansion
    max_radius = max_search_radius
    reset()

func reset() -> void:
    current_position = center
    leg_length = initial_leg_length
    direction = 0
    legs_completed = 0
    points_in_current_leg = 0
    points_per_leg = max(1, int(leg_length / 25.0))  # Point every 25 pixels

func get_next_waypoint() -> Vector2:
    # Check if we've exceeded max radius
    if current_position.distance_to(center) > max_radius:
        return Vector2.INF  # Signal search complete

    # Move to next point in current leg
    var step_size := leg_length / points_per_leg
    current_position += DIRECTIONS[direction] * step_size
    points_in_current_leg += 1

    # Check if leg is complete
    if points_in_current_leg >= points_per_leg:
        points_in_current_leg = 0
        legs_completed += 1
        direction = (direction + 1) % 4

        # Expand every 2 legs (after completing a full "L" shape)
        if legs_completed % 2 == 0:
            leg_length += expansion_rate
            points_per_leg = max(1, int(leg_length / 25.0))

    return current_position

func get_all_waypoints() -> Array[Vector2]:
    var waypoints: Array[Vector2] = []
    reset()

    var waypoint := get_next_waypoint()
    while waypoint != Vector2.INF:
        waypoints.append(waypoint)
        waypoint = get_next_waypoint()

    reset()
    return waypoints
```

### Visualization

```
        1→→→2
        ↑   ↓
    ←←←←0   ↓
    ↓       ↓
    ↓   ←←←←3
    ↓   ↑
    5→→→4

Leg 0: 1 unit N (starts at center)
Leg 1: 1 unit E
Leg 2: 2 units S
Leg 3: 2 units W
Leg 4: 3 units N
Leg 5: 3 units E
... and so on
```

## 2. Left-Hand Rule (Wall Following)

The left-hand rule is a maze-solving algorithm that follows walls on the left side.

### Core Algorithm

```gdscript
class_name WallFollower
extends RefCounted

enum Direction { NORTH, EAST, SOUTH, WEST }

var current_direction: Direction = Direction.NORTH
var use_left_hand: bool = true  # false for right-hand rule

const DIRECTION_VECTORS := {
    Direction.NORTH: Vector2(0, -1),
    Direction.EAST: Vector2(1, 0),
    Direction.SOUTH: Vector2(0, 1),
    Direction.WEST: Vector2(-1, 0)
}

func get_left_direction() -> Direction:
    # Rotate 90 degrees counter-clockwise
    return (current_direction - 1 + 4) % 4 as Direction

func get_right_direction() -> Direction:
    # Rotate 90 degrees clockwise
    return (current_direction + 1) % 4 as Direction

func get_opposite_direction() -> Direction:
    return (current_direction + 2) % 4 as Direction

## Returns the next movement direction based on wall configuration
## Parameters:
##   can_move_forward: bool - is there a wall ahead?
##   can_move_left: bool - is there a wall on left?
##   can_move_right: bool - is there a wall on right?
func get_next_direction(can_move_forward: bool, can_move_left: bool,
                        can_move_right: bool) -> Direction:
    if use_left_hand:
        # Left-hand rule priority: left > forward > right > back
        if can_move_left:
            current_direction = get_left_direction()
        elif can_move_forward:
            pass  # Keep current direction
        elif can_move_right:
            current_direction = get_right_direction()
        else:
            # Dead end - turn around
            current_direction = get_opposite_direction()
    else:
        # Right-hand rule priority: right > forward > left > back
        if can_move_right:
            current_direction = get_right_direction()
        elif can_move_forward:
            pass  # Keep current direction
        elif can_move_left:
            current_direction = get_left_direction()
        else:
            current_direction = get_opposite_direction()

    return current_direction

func get_direction_vector() -> Vector2:
    return DIRECTION_VECTORS[current_direction]
```

### Integration with Raycasts

```gdscript
## In enemy script
func _check_wall_directions(ray_length: float = 50.0) -> Dictionary:
    var space_state := get_world_2d().direct_space_state
    var directions := {
        "forward": false,
        "left": false,
        "right": false
    }

    var forward := _wall_follower.get_direction_vector()
    var left := forward.rotated(-PI/2)
    var right := forward.rotated(PI/2)

    # Check forward
    var query := PhysicsRayQueryParameters2D.create(
        global_position,
        global_position + forward * ray_length,
        collision_mask
    )
    directions["forward"] = space_state.intersect_ray(query) == {}

    # Check left
    query.to = global_position + left * ray_length
    directions["left"] = space_state.intersect_ray(query) == {}

    # Check right
    query.to = global_position + right * ray_length
    directions["right"] = space_state.intersect_ray(query) == {}

    return directions
```

## 3. Hybrid Search Pattern

Combines expanding square with navigation validation and wall-following fallback.

```gdscript
class_name HybridSearchPattern
extends RefCounted

var expanding_search: ExpandingSquareSearch
var wall_follower: WallFollower
var nav_server: NavigationServer2D
var nav_map: RID

var waypoints: Array[Vector2] = []
var current_index: int = 0
var is_wall_following: bool = false
var wall_follow_timeout: float = 0.0

const WALL_FOLLOW_DURATION := 2.0  # Seconds to wall-follow before resuming

func _init(center: Vector2, nav_map_rid: RID) -> void:
    expanding_search = ExpandingSquareSearch.new(center)
    wall_follower = WallFollower.new()
    nav_map = nav_map_rid
    _generate_validated_waypoints()

func _generate_validated_waypoints() -> void:
    var raw_waypoints := expanding_search.get_all_waypoints()
    waypoints.clear()

    for wp in raw_waypoints:
        # Validate waypoint is on navigation mesh
        var closest := NavigationServer2D.map_get_closest_point(nav_map, wp)
        if closest.distance_to(wp) < 25.0:  # Within tolerance
            waypoints.append(closest)

func get_current_target() -> Vector2:
    if current_index >= waypoints.size():
        return Vector2.INF  # Search complete
    return waypoints[current_index]

func advance_to_next() -> void:
    current_index += 1
    is_wall_following = false

func get_waypoint_count() -> int:
    return waypoints.size()

func get_progress() -> float:
    if waypoints.is_empty():
        return 1.0
    return float(current_index) / float(waypoints.size())

func start_wall_following() -> void:
    is_wall_following = true
    wall_follow_timeout = WALL_FOLLOW_DURATION

func update_wall_following(delta: float) -> bool:
    wall_follow_timeout -= delta
    return wall_follow_timeout > 0.0

func reset() -> void:
    current_index = 0
    is_wall_following = false
    expanding_search.reset()
    _generate_validated_waypoints()
```

## 4. Search State Implementation

Example `SearchingState` class for the enemy AI:

```gdscript
class_name SearchingState
extends EnemyState

var search_pattern: HybridSearchPattern
var scan_timer: float = 0.0
var local_scan_completed: bool = false

const SCAN_DURATION := 0.5  # Seconds to scan at each waypoint
const SCAN_CONE_ANGLE := deg_to_rad(90.0)  # Vision cone for scanning
const SCAN_DISTANCE := 200.0

func _init(enemy_ref: Node2D) -> void:
    super._init(enemy_ref)
    state_name = "searching"

func enter() -> void:
    # Initialize search pattern centered on suspected position
    var search_center := enemy._memory.suspected_position if enemy._memory else enemy.global_position
    var nav_map := enemy.get_world_2d().navigation_map
    search_pattern = HybridSearchPattern.new(search_center, nav_map)
    scan_timer = 0.0
    local_scan_completed = false
    enemy._log_to_file("SEARCHING: Started at %s with %d waypoints" % [
        search_center, search_pattern.get_waypoint_count()
    ])

func exit() -> void:
    search_pattern = null

func process(delta: float) -> EnemyState:
    # Check if player became visible
    if enemy._can_see_player:
        enemy._log_to_file("SEARCHING: Player found! Transitioning to COMBAT")
        return null  # Signal transition to COMBAT

    # Check if under fire
    if enemy._under_fire:
        return null  # Signal transition to defensive state

    # Get current search target
    var target := search_pattern.get_current_target()
    if target == Vector2.INF:
        # Search complete - return to patrol
        enemy._log_to_file("SEARCHING: Complete (%.0f%% coverage), returning to IDLE" % [
            search_pattern.get_progress() * 100
        ])
        return null  # Signal transition to IDLE

    # Check if reached current waypoint
    var distance_to_target := enemy.global_position.distance_to(target)
    if distance_to_target < 15.0:
        if not local_scan_completed:
            # Perform local scan at this position
            _perform_local_scan(delta)
        else:
            # Move to next waypoint
            search_pattern.advance_to_next()
            local_scan_completed = false
            scan_timer = 0.0
    else:
        # Move toward current waypoint
        enemy._move_to_target_nav(target, enemy.move_speed)
        # Aim in movement direction
        var move_dir := (target - enemy.global_position).normalized()
        enemy._rotate_toward_direction(move_dir)

    return null

func _perform_local_scan(delta: float) -> void:
    enemy.velocity = Vector2.ZERO
    scan_timer += delta

    # Rotate to scan area
    var scan_progress := scan_timer / SCAN_DURATION
    var scan_angle := lerp(-SCAN_CONE_ANGLE/2, SCAN_CONE_ANGLE/2, scan_progress)
    var base_direction := (search_pattern.get_current_target() - enemy.global_position).normalized()
    var scan_direction := base_direction.rotated(scan_angle)
    enemy._rotate_toward_direction(scan_direction)

    # Cast vision ray in scan direction
    if enemy._cast_vision_ray(scan_direction, SCAN_DISTANCE):
        # Player detected during scan!
        local_scan_completed = true
        return

    if scan_timer >= SCAN_DURATION:
        local_scan_completed = true
```

## 5. GOAP Action for Search

```gdscript
## Action to search an area when confidence is low and pursuit failed.
## Triggers systematic area search using expanding square pattern.
class SearchAreaAction extends GOAPAction:
    func _init() -> void:
        super._init("search_area", 3.0)
        preconditions = {
            "player_visible": false,
            "has_suspected_position": true,
            "confidence_low": true,
            "pursuit_failed": true  # New world state
        }
        effects = {
            "area_searched": true,
            "has_suspected_position": false  # Clear suspicion after search
        }

    func get_cost(_agent: Node, world_state: Dictionary) -> float:
        var confidence: float = world_state.get("position_confidence", 0.0)
        # Higher cost as confidence decreases (less likely to find player)
        return 3.0 + (0.5 - confidence) * 2.0
```

## References

- [Wikipedia - Maze-solving algorithm](https://en.wikipedia.org/wiki/Maze-solving_algorithm)
- [NASA - Rectangular Spiral Search](https://ntrs.nasa.gov/citations/20080047208)
- [IAMSAR Search Patterns](https://owaysonline.com/iamsar-search-patterns/)
- [McGill Robotics - Spiral Search](https://cim.mcgill.ca/~mrl/pubs/scottyb/burl-aaai99.pdf)
- [Godot NavigationServer2D](https://docs.godotengine.org/en/stable/classes/class_navigationserver2d.html)
