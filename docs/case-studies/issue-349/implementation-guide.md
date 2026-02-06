# Implementation Guide: Enemy Ricochet & Penetration Targeting

## Overview

This guide provides detailed implementation specifications for adding ricochet and penetration shot prediction to enemy AI.

## Part 1: Wallbang (Penetration) Targeting

### Algorithm

```
FUNCTION check_wallbang_opportunity(enemy_pos, player_predicted_pos) -> WallbangInfo:
    # 1. Cast ray from enemy to player's predicted position
    space_state = get_world_2d().direct_space_state
    query = PhysicsRayQueryParameters2D.create(enemy_pos, player_predicted_pos)
    query.collision_mask = WALL_LAYER_MASK  # Only detect walls

    # 2. Collect all wall intersections
    walls_hit = []
    current_pos = enemy_pos
    remaining_distance = enemy_pos.distance_to(player_predicted_pos)

    WHILE remaining_distance > 0:
        result = space_state.intersect_ray(query)
        IF result.is_empty():
            BREAK  # No more walls

        walls_hit.append({
            "entry_point": result.position,
            "body": result.collider
        })

        # Move past this wall to check for more
        current_pos = result.position + (player_predicted_pos - enemy_pos).normalized() * 1.0
        query = PhysicsRayQueryParameters2D.create(current_pos, player_predicted_pos)
        query.collision_mask = WALL_LAYER_MASK
        remaining_distance = current_pos.distance_to(player_predicted_pos)

    # 3. Calculate total wall thickness
    total_thickness = 0.0
    FOR each wall in walls_hit:
        thickness = estimate_wall_thickness(wall.entry_point, wall.body, direction)
        total_thickness += thickness

    # 4. Check if penetrable
    IF total_thickness <= caliber_data.max_penetration_distance:
        RETURN WallbangInfo {
            valid: true,
            aim_point: player_predicted_pos,
            wall_thickness: total_thickness,
            damage_estimate: calculate_post_penetration_damage(total_thickness)
        }

    RETURN WallbangInfo { valid: false }


FUNCTION estimate_wall_thickness(entry_point, wall_body, direction) -> float:
    # Cast ray from inside the wall to find exit point
    # Use binary search or step-based approach

    step_size = 5.0  # pixels
    max_steps = 20   # max 100 pixels
    current_pos = entry_point + direction * step_size

    FOR i in range(max_steps):
        # Check if we're still inside the wall
        query = PhysicsRayQueryParameters2D.create(
            current_pos - direction * 2.0,  # slightly behind
            current_pos + direction * 2.0   # slightly ahead
        )
        result = space_state.intersect_ray(query)

        IF result.is_empty() OR result.collider != wall_body:
            # Exited the wall
            RETURN current_pos.distance_to(entry_point)

        current_pos += direction * step_size

    RETURN max_steps * step_size  # Maximum thickness
```

### GDScript Implementation Skeleton

```gdscript
## scripts/objects/enemy.gd additions

## Wallbang opportunity data structure
class WallbangInfo:
    var valid: bool = false
    var aim_point: Vector2 = Vector2.ZERO
    var wall_thickness: float = 0.0
    var damage_multiplier: float = 1.0
    var last_check_time: float = 0.0

## Cached wallbang opportunity
var _wallbang_info: WallbangInfo = WallbangInfo.new()

## Wallbang check interval (seconds)
const WALLBANG_CHECK_INTERVAL: float = 0.5

## Enable/disable wallbang shots
@export var enable_wallbang_shots: bool = true

## Minimum damage multiplier to attempt wallbang (filter out weak shots)
@export var wallbang_min_damage_threshold: float = 0.3


func _check_wallbang_opportunity() -> void:
    if not enable_wallbang_shots:
        return

    var current_time := Time.get_ticks_msec() / 1000.0
    if current_time - _wallbang_info.last_check_time < WALLBANG_CHECK_INTERVAL:
        return

    _wallbang_info.last_check_time = current_time
    _wallbang_info.valid = false

    if _player == null:
        return

    # Get predicted player position
    var target_pos := _calculate_lead_prediction()

    # Check if we have direct line of sight (no wallbang needed)
    if _can_see_player:
        return

    # Cast ray to find walls
    var space_state := get_world_2d().direct_space_state
    var direction := (target_pos - global_position).normalized()
    var query := PhysicsRayQueryParameters2D.create(global_position, target_pos)
    query.collision_mask = 4  # Wall layer
    query.exclude = [self]

    var result := space_state.intersect_ray(query)
    if result.is_empty():
        return  # No wall in the way (shouldn't happen if player not visible)

    # Estimate wall thickness
    var entry_point: Vector2 = result.position
    var thickness := _estimate_wall_thickness(entry_point, result.collider, direction)

    # Get caliber penetration data
    var max_penetration := DEFAULT_MAX_PENETRATION_DISTANCE
    var damage_mult := DEFAULT_POST_PENETRATION_DAMAGE_MULTIPLIER
    # Note: Would need to access bullet's caliber_data

    if thickness <= max_penetration:
        _wallbang_info.valid = true
        _wallbang_info.aim_point = target_pos
        _wallbang_info.wall_thickness = thickness
        _wallbang_info.damage_multiplier = pow(damage_mult, ceil(thickness / 24.0))

        if _wallbang_info.damage_multiplier >= wallbang_min_damage_threshold:
            _log_debug("Wallbang opportunity found: thickness=%.1f, damage=%.1f%%" % [
                thickness, _wallbang_info.damage_multiplier * 100
            ])


func _estimate_wall_thickness(entry_point: Vector2, wall_body: Object, direction: Vector2) -> float:
    var space_state := get_world_2d().direct_space_state
    var step_size := 5.0
    var max_thickness := 100.0
    var current_pos := entry_point + direction * step_size

    for i in range(int(max_thickness / step_size)):
        var check_start := current_pos - direction * 2.0
        var check_end := current_pos + direction * 2.0
        var query := PhysicsRayQueryParameters2D.create(check_start, check_end)
        query.collision_mask = 4

        var result := space_state.intersect_ray(query)
        if result.is_empty() or result.collider != wall_body:
            return current_pos.distance_to(entry_point)

        current_pos += direction * step_size

    return max_thickness
```

---

## Part 2: Ricochet Targeting (Single Bounce)

### Mirror Point Algorithm

For a single ricochet shot, we use the "mirror point" technique from billiards:

```
FUNCTION find_single_ricochet_path(enemy_pos, player_pos, walls) -> RicochetPath:
    best_path = null

    FOR each wall_segment in walls:
        # Calculate mirror point of player across the wall line
        mirror_player = reflect_point_across_line(player_pos, wall_segment)

        # Check if line from enemy to mirror point intersects the wall
        intersection = line_segment_intersection(
            enemy_pos, mirror_player,
            wall_segment.start, wall_segment.end
        )

        IF intersection.valid:
            # This is a valid ricochet point!
            aim_point = intersection.point

            # Verify line of sight to aim point (no obstacles)
            IF has_line_of_sight(enemy_pos, aim_point):
                # Verify reflected shot can reach player
                reflection_dir = (mirror_player - aim_point).normalized()
                IF can_reach_player(aim_point, reflection_dir, player_pos):
                    # Calculate ricochet probability
                    surface_normal = wall_segment.get_normal()
                    impact_angle = calculate_impact_angle(aim_point - enemy_pos, surface_normal)
                    probability = calculate_ricochet_probability(impact_angle)

                    IF probability > MIN_RICOCHET_THRESHOLD:
                        path = RicochetPath {
                            aim_point: aim_point,
                            bounce_point: aim_point,
                            final_target: player_pos,
                            probability: probability,
                            total_distance: enemy_pos.distance_to(aim_point) + aim_point.distance_to(player_pos)
                        }

                        IF best_path == null OR path.probability > best_path.probability:
                            best_path = path

    RETURN best_path


FUNCTION reflect_point_across_line(point, line) -> Vector2:
    # Project point onto line and reflect
    line_dir = (line.end - line.start).normalized()
    line_normal = Vector2(-line_dir.y, line_dir.x)

    # Vector from line start to point
    to_point = point - line.start

    # Distance from point to line (signed)
    dist_to_line = to_point.dot(line_normal)

    # Mirror point is 2x distance on the other side
    mirror = point - 2.0 * dist_to_line * line_normal

    RETURN mirror
```

### GDScript Implementation Skeleton

```gdscript
## scripts/objects/enemy.gd additions for ricochet

## Ricochet path data structure
class RicochetPath:
    var valid: bool = false
    var aim_point: Vector2 = Vector2.ZERO      # Where to aim (wall point)
    var bounce_point: Vector2 = Vector2.ZERO   # Where bullet bounces
    var final_target: Vector2 = Vector2.ZERO   # Player position
    var probability: float = 0.0               # Ricochet success probability
    var bounce_count: int = 0                  # Number of bounces (1 or 2)
    var last_check_time: float = 0.0

## Cached ricochet path
var _ricochet_path: RicochetPath = RicochetPath.new()

## Ricochet check interval (seconds)
const RICOCHET_CHECK_INTERVAL: float = 0.3

## Enable/disable ricochet shots
@export var enable_ricochet_shots: bool = true

## Minimum ricochet probability to attempt (filter out unlikely shots)
@export var ricochet_min_probability_threshold: float = 0.5

## Maximum distance to search for ricochet walls
@export var ricochet_search_radius: float = 500.0

## Maximum total ricochet path distance (enemy → wall → player)
@export var ricochet_max_total_distance: float = 800.0


func _find_ricochet_path() -> void:
    if not enable_ricochet_shots:
        return

    var current_time := Time.get_ticks_msec() / 1000.0
    if current_time - _ricochet_path.last_check_time < RICOCHET_CHECK_INTERVAL:
        return

    _ricochet_path.last_check_time = current_time
    _ricochet_path.valid = false

    if _player == null:
        return

    # Skip if we have direct LOS (prefer direct shots)
    if _can_see_player:
        return

    var player_pos := _calculate_lead_prediction()

    # Get nearby wall segments
    var walls := _get_nearby_wall_segments(ricochet_search_radius)

    var best_probability := 0.0

    for wall in walls:
        var path := _calculate_ricochet_for_wall(wall, player_pos)
        if path.valid and path.probability > best_probability:
            _ricochet_path = path
            best_probability = path.probability

    if _ricochet_path.valid:
        _log_debug("Ricochet path found: aim=%v, probability=%.1f%%" % [
            _ricochet_path.aim_point, _ricochet_path.probability * 100
        ])


func _calculate_ricochet_for_wall(wall: Dictionary, player_pos: Vector2) -> RicochetPath:
    var path := RicochetPath.new()

    # Get wall line
    var wall_start: Vector2 = wall.start
    var wall_end: Vector2 = wall.end
    var wall_dir := (wall_end - wall_start).normalized()
    var wall_normal := Vector2(-wall_dir.y, wall_dir.x)

    # Calculate mirror point of player across wall
    var to_player := player_pos - wall_start
    var dist_to_wall := to_player.dot(wall_normal)
    var mirror_player := player_pos - 2.0 * dist_to_wall * wall_normal

    # Find intersection of enemy→mirror line with wall segment
    var intersection := _line_segment_intersection(
        global_position, mirror_player,
        wall_start, wall_end
    )

    if not intersection.valid:
        return path

    var aim_point: Vector2 = intersection.point

    # Check LOS from enemy to aim point
    if not _has_clear_shot_to(aim_point):
        return path

    # Calculate impact angle and probability
    var incoming_dir := (aim_point - global_position).normalized()
    var impact_angle := _calculate_bullet_impact_angle(incoming_dir, wall_normal)
    var probability := _calculate_ricochet_probability_for_angle(impact_angle)

    if probability < ricochet_min_probability_threshold:
        return path

    # Verify reflected path reaches player
    var reflected_dir := incoming_dir - 2.0 * incoming_dir.dot(wall_normal) * wall_normal
    if not _reflected_path_reaches_target(aim_point, reflected_dir, player_pos):
        return path

    # Check total distance
    var total_dist := global_position.distance_to(aim_point) + aim_point.distance_to(player_pos)
    if total_dist > ricochet_max_total_distance:
        return path

    path.valid = true
    path.aim_point = aim_point
    path.bounce_point = aim_point
    path.final_target = player_pos
    path.probability = probability
    path.bounce_count = 1

    return path


func _line_segment_intersection(p1: Vector2, p2: Vector2, p3: Vector2, p4: Vector2) -> Dictionary:
    # Line 1: p1 to p2
    # Line 2: p3 to p4

    var d1 := p2 - p1
    var d2 := p4 - p3
    var d3 := p1 - p3

    var cross := d1.x * d2.y - d1.y * d2.x

    if abs(cross) < 0.0001:
        return {"valid": false}  # Lines are parallel

    var t := (d3.x * d2.y - d3.y * d2.x) / cross
    var u := (d3.x * d1.y - d3.y * d1.x) / cross

    # Check if intersection is within both segments
    if t >= 0.0 and t <= 1.0 and u >= 0.0 and u <= 1.0:
        return {
            "valid": true,
            "point": p1 + t * d1
        }

    return {"valid": false}


func _get_nearby_wall_segments(radius: float) -> Array:
    # This would use existing raycast infrastructure or
    # query the tilemap for nearby wall tiles
    # Returns array of {start: Vector2, end: Vector2} dictionaries

    var walls: Array = []
    var space_state := get_world_2d().direct_space_state

    # Sample walls by casting rays in multiple directions
    for angle in range(0, 360, 15):  # Every 15 degrees
        var direction := Vector2.from_angle(deg_to_rad(angle))
        var query := PhysicsRayQueryParameters2D.create(
            global_position,
            global_position + direction * radius
        )
        query.collision_mask = 4  # Walls
        query.exclude = [self]

        var result := space_state.intersect_ray(query)
        if not result.is_empty():
            # Estimate wall segment from hit point and normal
            var hit_point: Vector2 = result.position
            var normal: Vector2 = result.normal
            var wall_dir := Vector2(-normal.y, normal.x)

            # Create approximate wall segment
            var wall := {
                "start": hit_point - wall_dir * 100.0,
                "end": hit_point + wall_dir * 100.0,
                "normal": normal
            }

            # Avoid duplicates
            var is_duplicate := false
            for existing in walls:
                if hit_point.distance_to(existing.start) < 50.0:
                    is_duplicate = true
                    break

            if not is_duplicate:
                walls.append(wall)

    return walls


func _calculate_bullet_impact_angle(direction: Vector2, surface_normal: Vector2) -> float:
    # Same as bullet.gd:_calculate_impact_angle
    var dot := absf(direction.normalized().dot(surface_normal.normalized()))
    dot = clampf(dot, 0.0, 1.0)
    return asin(dot)  # Returns grazing angle in radians


func _calculate_ricochet_probability_for_angle(impact_angle_rad: float) -> float:
    var impact_angle_deg := rad_to_deg(impact_angle_rad)
    var max_angle := 90.0

    if impact_angle_deg > max_angle:
        return 0.0

    # Match bullet.gd probability curve
    var normalized_angle := impact_angle_deg / 90.0
    var power_factor := pow(normalized_angle, 2.17)
    var angle_factor := (1.0 - power_factor) * 0.9 + 0.1

    return angle_factor


func _has_clear_shot_to(target: Vector2) -> bool:
    var space_state := get_world_2d().direct_space_state
    var query := PhysicsRayQueryParameters2D.create(global_position, target)
    query.collision_mask = 4  # Walls
    query.exclude = [self]

    var result := space_state.intersect_ray(query)
    if result.is_empty():
        return true

    # Allow if very close to target (rounding errors)
    return result.position.distance_to(target) < 5.0


func _reflected_path_reaches_target(start: Vector2, direction: Vector2, target: Vector2) -> bool:
    # Check if the reflected ray passes near the target
    var to_target := target - start
    var projected := to_target.project(direction)

    # Target must be in the direction of reflection
    if projected.dot(direction) < 0:
        return false

    # Check perpendicular distance to target
    var perp_dist := (to_target - projected).length()

    # Allow some tolerance for player hitbox size
    return perp_dist < 50.0  # Player roughly 50px wide
```

---

## Part 3: Double Ricochet Targeting

### Algorithm Extension

```
FUNCTION find_double_ricochet_path(enemy_pos, player_pos, walls) -> RicochetPath:
    best_path = null

    # First, find all valid first-bounce points
    FOR each wall1 in walls:
        FOR each wall2 in walls:
            IF wall1 == wall2:
                CONTINUE

            # Mirror player across wall2 to get intermediate target
            mirror1 = reflect_point_across_line(player_pos, wall2)

            # Mirror that across wall1 to get aim target
            mirror2 = reflect_point_across_line(mirror1, wall1)

            # Find where enemy → mirror2 hits wall1
            intersection1 = line_segment_intersection(enemy_pos, mirror2, wall1)
            IF NOT intersection1.valid:
                CONTINUE

            bounce1 = intersection1.point

            # Find where bounce1 → mirror1 hits wall2
            intersection2 = line_segment_intersection(bounce1, mirror1, wall2)
            IF NOT intersection2.valid:
                CONTINUE

            bounce2 = intersection2.point

            # Validate entire path
            IF has_line_of_sight(enemy_pos, bounce1) AND
               has_line_of_sight(bounce1, bounce2) AND
               can_reach_player(bounce2, player_pos):

                prob1 = calculate_ricochet_probability(bounce1)
                prob2 = calculate_ricochet_probability(bounce2)
                combined_prob = prob1 * prob2

                IF combined_prob > MIN_DOUBLE_RICOCHET_THRESHOLD:
                    path = RicochetPath {
                        aim_point: bounce1,
                        bounces: [bounce1, bounce2],
                        probability: combined_prob,
                        bounce_count: 2
                    }

                    IF best_path == null OR path.probability > best_path.probability:
                        best_path = path

    RETURN best_path
```

**Note:** Double ricochet is computationally expensive (O(n²) wall combinations). Consider:
- Only computing when stationary for extended time
- Limiting to specific game modes
- Heavy throttling (once per second)

---

## Part 4: Integration with Shooting System

### Modified `_shoot()` Function

```gdscript
func _shoot() -> void:
    if bullet_scene == null or _player == null:
        return

    if not _can_shoot():
        return

    var target_position: Vector2
    var shot_type: String = "direct"

    # Priority: Direct shot > Ricochet > Wallbang
    if _can_see_player:
        # Direct shot
        target_position = _player.global_position
        if enable_lead_prediction:
            target_position = _calculate_lead_prediction()
        shot_type = "direct"

    elif enable_ricochet_shots and _ricochet_path.valid:
        # Ricochet shot - aim at wall bounce point
        target_position = _ricochet_path.aim_point
        shot_type = "ricochet"
        _log_debug("Taking RICOCHET shot at %v (%.0f%% probability)" % [
            target_position, _ricochet_path.probability * 100
        ])

    elif enable_wallbang_shots and _wallbang_info.valid:
        # Wallbang shot - aim through wall
        target_position = _wallbang_info.aim_point
        shot_type = "wallbang"
        _log_debug("Taking WALLBANG shot at %v (%.1f thickness)" % [
            target_position, _wallbang_info.wall_thickness
        ])

    else:
        # No valid shot opportunity
        return

    # Check if shot should be taken
    if not _should_shoot_at_target(target_position):
        return

    # Rest of shooting logic...
    var weapon_forward := _get_weapon_forward_direction()
    var bullet_spawn_pos := _get_bullet_spawn_position(weapon_forward)

    # Aim check
    var to_target := (target_position - global_position).normalized()
    var aim_dot := weapon_forward.dot(to_target)
    if aim_dot < AIM_TOLERANCE_DOT:
        return

    # Create and fire bullet
    var direction := weapon_forward
    var bullet := bullet_scene.instantiate()
    bullet.global_position = bullet_spawn_pos
    bullet.direction = direction
    bullet.shooter_id = get_instance_id()
    bullet.shooter_position = bullet_spawn_pos

    get_tree().current_scene.add_child(bullet)
    # ... rest of _shoot() ...
```

### Update AI Targeting in `_process_combat()`

```gdscript
func _process_combat(delta: float) -> void:
    # Existing combat logic...

    # Update ricochet and wallbang opportunities
    _check_wallbang_opportunity()
    _find_ricochet_path()

    # Calculate target position based on available shots
    var aim_target: Vector2

    if _can_see_player:
        aim_target = _player.global_position
        if enable_lead_prediction:
            aim_target = _calculate_lead_prediction()
    elif _ricochet_path.valid:
        aim_target = _ricochet_path.aim_point
    elif _wallbang_info.valid:
        aim_target = _wallbang_info.aim_point
    else:
        aim_target = _last_known_player_position

    # Rotate toward aim target
    _rotate_toward_target(aim_target, delta)

    # ... rest of combat processing ...
```

---

## Part 5: Testing

### Unit Test Cases

```gdscript
## tests/unit/test_enemy_ricochet_targeting.gd

extends GutTest

func test_mirror_point_calculation():
    # Test reflecting a point across a horizontal line
    var point = Vector2(100, 100)
    var line_start = Vector2(0, 50)
    var line_end = Vector2(200, 50)

    var mirror = _reflect_point_across_line(point, line_start, line_end)

    assert_almost_eq(mirror.y, 0.0, 0.1, "Mirror Y should be reflected")
    assert_almost_eq(mirror.x, 100.0, 0.1, "Mirror X should be preserved")


func test_ricochet_probability_grazing_angle():
    var enemy = _create_test_enemy()

    # Grazing angle (0°) should have high probability
    var prob = enemy.call("_calculate_ricochet_probability_for_angle", 0.0)
    assert_gt(prob, 0.9, "Grazing angle should have >90% probability")


func test_ricochet_probability_perpendicular():
    var enemy = _create_test_enemy()

    # Perpendicular angle (90°) should have low probability
    var prob = enemy.call("_calculate_ricochet_probability_for_angle", PI / 2.0)
    assert_almost_eq(prob, 0.1, 0.05, "Perpendicular angle should have ~10% probability")


func test_wallbang_detects_thin_wall():
    # Setup: enemy → thin wall (24px) → player
    # Should detect wallbang opportunity
    pass


func test_wallbang_rejects_thick_wall():
    # Setup: enemy → thick wall (100px) → player
    # Should not detect wallbang opportunity
    pass


func test_ricochet_finds_valid_path():
    # Setup: enemy behind corner, player around corner
    # Wall at 45° angle allows ricochet
    pass
```

### Integration Tests

```gdscript
## tests/integration/test_enemy_advanced_targeting.gd

func test_enemy_uses_ricochet_when_player_behind_cover():
    # 1. Position player behind cover
    # 2. Position enemy with wall angle for ricochet
    # 3. Wait for enemy to calculate ricochet path
    # 4. Verify enemy aims at ricochet point
    # 5. Fire bullet and verify ricochet hits player
    pass


func test_enemy_uses_wallbang_through_thin_wall():
    # 1. Position player behind thin wall
    # 2. Position enemy with clear line through wall
    # 3. Wait for enemy to calculate wallbang opportunity
    # 4. Verify enemy aims through wall
    # 5. Fire bullet and verify penetration hit
    pass
```

---

## Performance Benchmarks

Target performance on reference hardware:

| Metric | Target |
|--------|--------|
| Ricochet path calculation | < 0.5ms per enemy |
| Wallbang check | < 0.1ms per enemy |
| 10 enemies simultaneous | < 5ms total per frame |
| Memory per enemy | < 1KB for cached paths |
