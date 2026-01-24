# Proposed Solutions: Issue #330

This document details the technical implementation approaches for solving the two requirements from Issue #330.

## Requirements Summary

1. **Collective Search Behavior** - Enemies should coordinate to search different areas, not cluster together
2. **Persistent Search After Contact** - Enemies should not return to IDLE after combat contact; they should search until they find the player

---

## Solution A: Global Search Coordinator (Recommended for Requirement #1)

### Overview

Create a central `SearchCoordinator` autoload that manages all enemies in SEARCHING state and distributes waypoints to prevent overlap.

### Implementation

#### New File: `scripts/ai/search_coordinator.gd`

```gdscript
extends Node
class_name SearchCoordinator

## Manages coordinated enemy search behavior to prevent clustering.
## Enemies register when entering SEARCHING state and receive unique waypoints.

## Active searchers: enemy instance_id -> SearcherData
var _searchers: Dictionary = {}

## Global visited zones: zone_key -> true (shared across all enemies)
var _global_visited_zones: Dictionary = {}

## Current search center (set when first enemy registers)
var _current_search_center: Vector2 = Vector2.ZERO

## Search configuration
const ZONE_SNAP_SIZE: float = 50.0
const INITIAL_RADIUS: float = 100.0
const RADIUS_EXPANSION: float = 75.0
const MAX_RADIUS: float = 600.0  # Increased from 400 for coordinated search
const WAYPOINT_SPACING: float = 75.0

## Data for each registered searcher
class SearcherData:
    var enemy: Node
    var sector_index: int
    var assigned_waypoints: Array[Vector2]
    var current_waypoint_index: int = 0
    var search_radius: float = INITIAL_RADIUS

## Register an enemy for coordinated search
func register_searcher(enemy: Node, center: Vector2) -> void:
    if _searchers.is_empty():
        _current_search_center = center
        _global_visited_zones.clear()

    var data := SearcherData.new()
    data.enemy = enemy
    data.sector_index = _searchers.size()  # Assign next sector
    _searchers[enemy.get_instance_id()] = data

    _redistribute_waypoints()
    _log("Registered %s as searcher #%d" % [enemy.name, data.sector_index])

## Unregister an enemy when leaving SEARCHING state
func unregister_searcher(enemy: Node) -> void:
    var id := enemy.get_instance_id()
    if _searchers.has(id):
        _searchers.erase(id)
        _redistribute_waypoints()
        _log("Unregistered %s" % enemy.name)

    if _searchers.is_empty():
        _current_search_center = Vector2.ZERO

## Get next waypoint for an enemy
func get_next_waypoint(enemy: Node) -> Vector2:
    var id := enemy.get_instance_id()
    if not _searchers.has(id):
        return Vector2.ZERO

    var data: SearcherData = _searchers[id]

    if data.current_waypoint_index >= data.assigned_waypoints.size():
        # Expand search for this enemy
        data.search_radius += RADIUS_EXPANSION
        if data.search_radius > MAX_RADIUS:
            return Vector2.ZERO  # No more waypoints

        _assign_sector_waypoints(data)
        data.current_waypoint_index = 0

    if data.assigned_waypoints.is_empty():
        return Vector2.ZERO

    var waypoint := data.assigned_waypoints[data.current_waypoint_index]
    data.current_waypoint_index += 1
    return waypoint

## Mark a zone as searched (globally)
func mark_zone_searched(pos: Vector2) -> void:
    var key := _get_zone_key(pos)
    _global_visited_zones[key] = true

## Check if a zone has been searched by any enemy
func is_zone_searched(pos: Vector2) -> bool:
    return _global_visited_zones.has(_get_zone_key(pos))

## Get the number of active searchers
func get_searcher_count() -> int:
    return _searchers.size()

## Redistribute waypoints among all searchers using sector-based assignment
func _redistribute_waypoints() -> void:
    if _searchers.is_empty():
        return

    var num_searchers := _searchers.size()
    var sector_angle := 2 * PI / num_searchers

    var idx := 0
    for id in _searchers:
        var data: SearcherData = _searchers[id]
        data.sector_index = idx
        _assign_sector_waypoints(data)
        idx += 1

## Assign waypoints within an enemy's designated sector
func _assign_sector_waypoints(data: SearcherData) -> void:
    data.assigned_waypoints.clear()
    data.current_waypoint_index = 0

    var num_searchers := maxf(_searchers.size(), 1)
    var sector_angle := 2 * PI / num_searchers
    var sector_start := sector_angle * data.sector_index
    var sector_end := sector_start + sector_angle

    # Generate waypoints in expanding spiral within sector
    var current_radius := INITIAL_RADIUS
    while current_radius <= data.search_radius:
        # Calculate number of points at this radius based on circumference
        var circumference := 2 * PI * current_radius
        var num_points := int(circumference / WAYPOINT_SPACING)

        for i in range(num_points):
            var angle := (2 * PI / num_points) * i

            # Check if angle is within this enemy's sector
            var normalized_angle := fmod(angle, 2 * PI)
            if normalized_angle < 0:
                normalized_angle += 2 * PI

            if normalized_angle >= sector_start and normalized_angle < sector_end:
                var pos := _current_search_center + Vector2.from_angle(angle) * current_radius

                # Skip if already visited
                if not is_zone_searched(pos):
                    data.assigned_waypoints.append(pos)

        current_radius += WAYPOINT_SPACING

    _log("Assigned %d waypoints to sector %d (r=%.0f)" % [
        data.assigned_waypoints.size(),
        data.sector_index,
        data.search_radius
    ])

func _get_zone_key(pos: Vector2) -> String:
    var sx := int(pos.x / ZONE_SNAP_SIZE) * int(ZONE_SNAP_SIZE)
    var sy := int(pos.y / ZONE_SNAP_SIZE) * int(ZONE_SNAP_SIZE)
    return "%d,%d" % [sx, sy]

func _log(msg: String) -> void:
    var file_logger: Node = get_node_or_null("/root/FileLogger")
    if file_logger and file_logger.has_method("log_info"):
        file_logger.log_info("[SearchCoordinator] " + msg)
```

#### Changes to `enemy.gd`

```gdscript
# Add reference to coordinator
var _search_coordinator: Node = null

func _ready() -> void:
    # ... existing code ...
    _search_coordinator = get_node_or_null("/root/SearchCoordinator")

func _transition_to_searching(center_position: Vector2) -> void:
    _current_state = AIState.SEARCHING
    _search_state_timer = 0.0
    _search_scan_timer = 0.0
    _search_moving_to_waypoint = true

    # Register with coordinator instead of generating own waypoints
    if _search_coordinator:
        _search_coordinator.register_searcher(self, center_position)
    else:
        # Fallback to individual search (legacy behavior)
        _search_center = center_position
        _search_radius = SEARCH_INITIAL_RADIUS
        _search_visited_zones.clear()
        _generate_search_waypoints()

func _process_searching_state(delta: float) -> void:
    _search_state_timer += delta

    # Timeout handling (modified in Solution B)
    if _search_state_timer >= SEARCH_MAX_DURATION:
        _end_search("timeout")
        return

    if _can_see_player:
        _end_search("player_found")
        _transition_to_combat()
        return

    # Get waypoint from coordinator
    if _search_coordinator:
        var waypoint := _search_coordinator.get_next_waypoint(self)
        if waypoint == Vector2.ZERO:
            _end_search("no_more_waypoints")
            return
        _navigate_to_waypoint(waypoint, delta)
    else:
        # Legacy individual search
        _process_individual_search(delta)

func _end_search(reason: String) -> void:
    if _search_coordinator:
        _search_coordinator.unregister_searcher(self)
    _log_to_file("SEARCHING ended: %s" % reason)

    match reason:
        "player_found":
            pass  # Will transition to COMBAT
        _:
            _transition_to_idle()
```

### Visual Representation

```
Search Area with 4 Enemies (Sector-Based):

             Sector 0 (Enemy1)
                   |
        +----------+----------+
        |    /     |     \    |
        |   /   X  |  X   \   |
Sector  |  /       |       \  | Sector 1
3       | /        +        \ | (Enemy2)
(Enemy4)|X         |         X|
        | \        +        / |
        |  \       |       /  |
        |   \   X  |  X   /   |
        +----------+----------+
                   |
             Sector 2 (Enemy3)

X = Waypoint assigned to sector owner
```

---

## Solution B: Persistent Search After Contact (Requirement #2)

### Overview

Track whether an enemy has made combat contact with the player. If so, extend or remove the search timeout.

### Implementation

#### Changes to `enemy.gd`

```gdscript
## Track if this enemy has engaged the player in combat
var _has_engaged_player: bool = false

## Extended search duration after combat contact
const SEARCH_MAX_DURATION_AFTER_CONTACT: float = 120.0  # 2 minutes

## Set when entering combat
func _transition_to_combat() -> void:
    _current_state = AIState.COMBAT
    _has_engaged_player = true  # Mark that we've had contact
    # ... rest of existing code ...

## Modified timeout logic
func _process_searching_state(delta: float) -> void:
    _search_state_timer += delta

    # Different timeout based on contact history
    var max_duration: float
    if _has_engaged_player:
        max_duration = SEARCH_MAX_DURATION_AFTER_CONTACT
    else:
        max_duration = SEARCH_MAX_DURATION

    if _search_state_timer >= max_duration:
        _log_to_file("SEARCHING timeout after %.1fs (engaged=%s)" % [
            _search_state_timer, _has_engaged_player
        ])
        _transition_to_idle()
        return

    # ... rest of existing search logic ...

## Reset engagement flag on respawn or level restart
func _initialize_health() -> void:
    _max_health = randi_range(min_health, max_health)
    _current_health = _max_health
    _is_alive = true
    _has_engaged_player = false  # Reset on respawn

func _transition_to_idle() -> void:
    _current_state = AIState.IDLE
    _hits_taken_in_encounter = 0
    _in_alarm_mode = false
    _cover_burst_pending = false
    # Do NOT reset _has_engaged_player here - persistent until death/respawn
```

### Alternative: No Timeout After Contact

For more aggressive search behavior (enemies never give up):

```gdscript
func _process_searching_state(delta: float) -> void:
    _search_state_timer += delta

    # Only timeout if enemy has NEVER engaged player
    if not _has_engaged_player and _search_state_timer >= SEARCH_MAX_DURATION:
        _log_to_file("SEARCHING timeout (patrol enemy, no contact)")
        _transition_to_idle()
        return

    # For engaged enemies: only stop when max radius reached AND all zones searched
    if _has_engaged_player:
        if _search_radius >= SEARCH_MAX_RADIUS and _all_zones_searched():
            _log_to_file("SEARCHING completed: max area searched (engaged enemy)")
            _expand_patrol_area()  # Maybe start patrolling the searched area
            return

    # ... rest of search logic ...
```

---

## Solution C: Combined Implementation (Both Requirements)

### Changes Summary

1. **Add SearchCoordinator autoload**
   - New file: `scripts/ai/search_coordinator.gd`
   - Register in `project.godot` autoloads

2. **Modify enemy.gd**
   - Add `_search_coordinator` reference
   - Add `_has_engaged_player` flag
   - Modify `_transition_to_searching()` to use coordinator
   - Modify `_process_searching_state()` for coordinated waypoints + conditional timeout
   - Add `_end_search()` helper function

3. **Modify project.godot**
   ```
   [autoload]
   SearchCoordinator="*res://scripts/ai/search_coordinator.gd"
   ```

### Behavior Matrix

| Scenario | Timeout | Coordination |
|----------|---------|--------------|
| Patrol enemy hears gunshot | 30s | Individual (no coordinator) |
| Enemy loses sight during combat | 120s | Coordinated sectors |
| Enemy after Last Chance effect | 120s | Coordinated sectors |
| Multiple enemies after Last Chance | 120s each | All coordinated |

---

## Solution D: F.E.A.R.-Style Pair System (Advanced)

### Overview

Pair enemies together for cover-buddy behavior during search.

### Implementation Sketch

```gdscript
# In SearchCoordinator
class SearchPair:
    var leader: Node
    var follower: Node
    var pair_sector: int

func _form_pairs() -> Array[SearchPair]:
    var pairs: Array[SearchPair] = []
    var searcher_list := _searchers.values()

    for i in range(0, searcher_list.size(), 2):
        var pair := SearchPair.new()
        pair.leader = searcher_list[i].enemy
        if i + 1 < searcher_list.size():
            pair.follower = searcher_list[i + 1].enemy
        pair.pair_sector = i / 2
        pairs.append(pair)

    return pairs

# In enemy.gd
var _search_partner: Node = null
var _is_search_leader: bool = true

func _process_coordinated_search(delta: float) -> void:
    if _is_search_leader:
        # Leader moves to waypoints
        _navigate_to_waypoint(current_waypoint, delta)
    else:
        # Follower maintains offset and covers leader
        var offset := Vector2(30, 30).rotated(_search_partner.rotation)
        var follow_pos := _search_partner.global_position + offset
        _navigate_to_position(follow_pos, delta)
        _face_direction_opposite_to_leader()
```

---

## Recommendation

For Issue #330, I recommend implementing **Solution C (Combined)** as it:

1. Addresses both user requirements
2. Uses a proven pattern (F.E.A.R.-style Squad Manager)
3. Is modular (coordinator is separate from enemy logic)
4. Maintains backwards compatibility (fallback to individual search)
5. Can be extended later with pair systems (Solution D)

### Implementation Priority

1. **Phase 1:** Persistent search after contact (quick fix, high impact)
2. **Phase 2:** Global search coordinator (more complex, solves clustering)
3. **Phase 3:** Pair system and audio cues (polish, optional)

### Testing Checklist

- [ ] Single enemy enters SEARCHING - behaves normally
- [ ] Multiple enemies enter SEARCHING - each covers different sector
- [ ] Enemy after combat contact - searches longer than 30s
- [ ] Patrol enemy investigating sound - still times out at 30s
- [ ] Player found during extended search - transitions to COMBAT
- [ ] All zones searched at max radius - graceful termination
- [ ] Enemy dies during search - properly unregisters
- [ ] New enemy joins during active search - gets assigned empty sector
