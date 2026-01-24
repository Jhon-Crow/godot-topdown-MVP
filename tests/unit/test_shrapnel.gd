extends GutTest
## Unit tests for Shrapnel projectile.
##
## Tests the shrapnel mechanics including movement, ricochet behavior,
## lifetime management, damage dealing, and trail effects.


# ============================================================================
# Mock Shrapnel for Logic Tests
# ============================================================================


class MockShrapnel:
	## Speed of the shrapnel in pixels per second.
	var speed: float = 5000.0

	## Maximum lifetime in seconds.
	var lifetime: float = 2.0

	## Maximum number of ricochets before destruction.
	var max_ricochets: int = 3

	## Damage dealt on hit.
	var damage: int = 1

	## Maximum number of trail points.
	var trail_length: int = 6

	## Direction the shrapnel travels.
	var direction: Vector2 = Vector2.RIGHT

	## Instance ID of the entity that caused this shrapnel.
	var source_id: int = -1

	## Timer tracking remaining lifetime.
	var _time_alive: float = 0.0

	## Number of ricochets that have occurred.
	var _ricochet_count: int = 0

	## History of positions for the trail effect.
	var _position_history: Array[Vector2] = []

	## Velocity retention after each ricochet.
	const VELOCITY_RETENTION: float = 0.8

	## Random angle deviation for ricochet direction in degrees.
	const RICOCHET_ANGLE_DEVIATION: float = 15.0

	## Position simulation.
	var global_position: Vector2 = Vector2.ZERO
	var position: Vector2 = Vector2.ZERO

	## Rotation.
	var rotation: float = 0.0

	## Track destroyed state.
	var _destroyed: bool = false

	## Track hits.
	var hits: Array = []

	## Track ricochet events.
	var ricochet_events: Array = []

	## Simulate physics process.
	func physics_process(delta: float) -> void:
		if _destroyed:
			return

		# Move in the set direction
		var movement := direction * speed * delta
		position += movement
		global_position = position

		# Update trail effect
		_update_trail()

		# Track lifetime
		_time_alive += delta
		if _time_alive >= lifetime:
			_destroyed = true

	## Update rotation.
	func _update_rotation() -> void:
		rotation = direction.angle()

	## Update trail.
	func _update_trail() -> void:
		_position_history.push_front(global_position)

		while _position_history.size() > trail_length:
			_position_history.pop_back()

	## Simulate hitting a body.
	func on_body_entered(body_type: String, body_instance_id: int, is_alive: bool = true) -> bool:
		if _destroyed:
			return false

		# Don't collide with the source
		if source_id == body_instance_id:
			return false

		# Pass through dead entities
		if not is_alive:
			return false

		# Hit a static body - try to ricochet
		if body_type == "wall":
			# Try to ricochet
			if _try_ricochet():
				return true  # Continued
			else:
				_destroyed = true
				return false

		# Hit something else
		hits.append({"type": body_type, "id": body_instance_id})
		_destroyed = true
		return false

	## Try to ricochet.
	func _try_ricochet() -> bool:
		if _ricochet_count >= max_ricochets:
			return false

		_perform_ricochet(Vector2.UP)  # Simplified - always ricochet up
		return true

	## Perform ricochet with given surface normal.
	func _perform_ricochet(surface_normal: Vector2) -> void:
		_ricochet_count += 1

		# Calculate reflected direction
		var reflected := direction - 2.0 * direction.dot(surface_normal) * surface_normal
		reflected = reflected.normalized()

		# Update direction (without random deviation for testing)
		direction = reflected
		_update_rotation()

		# Reduce velocity
		speed *= VELOCITY_RETENTION

		# Move slightly away from surface
		global_position += direction * 5.0
		position = global_position

		# Clear trail
		_position_history.clear()

		ricochet_events.append({
			"normal": surface_normal,
			"new_direction": direction,
			"count": _ricochet_count
		})

	## Simulate hitting an area (target).
	func on_area_entered(parent_instance_id: int, is_alive: bool, has_hit_method: bool) -> bool:
		if _destroyed:
			return false

		if source_id == parent_instance_id:
			return false

		if not is_alive:
			return false

		if not has_hit_method:
			return false

		hits.append({"type": "target", "id": parent_instance_id})
		_destroyed = true
		return true

	## Check if destroyed.
	func is_destroyed() -> bool:
		return _destroyed

	## Get ricochet count.
	func get_ricochet_count() -> int:
		return _ricochet_count


var shrapnel: MockShrapnel


func before_each() -> void:
	shrapnel = MockShrapnel.new()


func after_each() -> void:
	shrapnel = null


# ============================================================================
# Default Configuration Tests
# ============================================================================


func test_default_speed() -> void:
	assert_eq(shrapnel.speed, 5000.0,
		"Default speed should be 5000 px/s (2x assault rifle)")


func test_default_lifetime() -> void:
	assert_eq(shrapnel.lifetime, 2.0,
		"Default lifetime should be 2 seconds")


func test_default_max_ricochets() -> void:
	assert_eq(shrapnel.max_ricochets, 3,
		"Default max ricochets should be 3")


func test_default_damage() -> void:
	assert_eq(shrapnel.damage, 1,
		"Default damage should be 1")


func test_default_trail_length() -> void:
	assert_eq(shrapnel.trail_length, 6,
		"Default trail length should be 6")


func test_velocity_retention_constant() -> void:
	assert_eq(MockShrapnel.VELOCITY_RETENTION, 0.8,
		"Velocity retention should be 0.8 (80%)")


func test_ricochet_angle_deviation_constant() -> void:
	assert_eq(MockShrapnel.RICOCHET_ANGLE_DEVIATION, 15.0,
		"Ricochet angle deviation should be 15 degrees")


# ============================================================================
# Initial State Tests
# ============================================================================


func test_direction_default() -> void:
	assert_eq(shrapnel.direction, Vector2.RIGHT,
		"Default direction should be RIGHT")


func test_source_id_default() -> void:
	assert_eq(shrapnel.source_id, -1,
		"Default source ID should be -1")


func test_time_alive_starts_at_zero() -> void:
	assert_eq(shrapnel._time_alive, 0.0,
		"Time alive should start at 0")


func test_ricochet_count_starts_at_zero() -> void:
	assert_eq(shrapnel._ricochet_count, 0,
		"Ricochet count should start at 0")


func test_not_destroyed_initially() -> void:
	assert_false(shrapnel.is_destroyed())


# ============================================================================
# Movement Tests
# ============================================================================


func test_moves_in_direction() -> void:
	shrapnel.global_position = Vector2.ZERO
	shrapnel.position = Vector2.ZERO
	shrapnel.physics_process(0.01)  # 10ms

	# Should move right by speed * delta = 5000 * 0.01 = 50
	assert_eq(shrapnel.position.x, 50.0)
	assert_eq(shrapnel.position.y, 0.0)


func test_moves_in_custom_direction() -> void:
	shrapnel.global_position = Vector2.ZERO
	shrapnel.position = Vector2.ZERO
	shrapnel.direction = Vector2.DOWN
	shrapnel.physics_process(0.01)

	assert_eq(shrapnel.position.x, 0.0)
	assert_eq(shrapnel.position.y, 50.0)


func test_moves_in_diagonal_direction() -> void:
	shrapnel.global_position = Vector2.ZERO
	shrapnel.position = Vector2.ZERO
	shrapnel.direction = Vector2(1, 1).normalized()
	shrapnel.physics_process(0.01)

	# Should move diagonally
	var expected_movement := Vector2(1, 1).normalized() * 50.0
	assert_almost_eq(shrapnel.position.x, expected_movement.x, 0.01)
	assert_almost_eq(shrapnel.position.y, expected_movement.y, 0.01)


func test_movement_accumulates() -> void:
	shrapnel.global_position = Vector2.ZERO
	shrapnel.position = Vector2.ZERO
	shrapnel.physics_process(0.01)
	shrapnel.physics_process(0.01)
	shrapnel.physics_process(0.01)

	assert_eq(shrapnel.position.x, 150.0)


# ============================================================================
# Lifetime Tests
# ============================================================================


func test_time_alive_increases() -> void:
	shrapnel.physics_process(0.5)

	assert_eq(shrapnel._time_alive, 0.5)


func test_destroyed_after_lifetime() -> void:
	shrapnel.physics_process(2.5)  # Past 2.0 lifetime

	assert_true(shrapnel.is_destroyed())


func test_not_destroyed_before_lifetime() -> void:
	shrapnel.physics_process(1.5)

	assert_false(shrapnel.is_destroyed())


func test_destroyed_at_exact_lifetime() -> void:
	shrapnel.physics_process(2.0)

	assert_true(shrapnel.is_destroyed())


func test_custom_lifetime() -> void:
	shrapnel.lifetime = 5.0
	shrapnel.physics_process(4.0)

	assert_false(shrapnel.is_destroyed())

	shrapnel.physics_process(1.5)

	assert_true(shrapnel.is_destroyed())


# ============================================================================
# Trail Tests
# ============================================================================


func test_trail_adds_position() -> void:
	shrapnel.global_position = Vector2(100, 100)
	shrapnel.position = Vector2(100, 100)
	shrapnel.physics_process(0.01)

	assert_gt(shrapnel._position_history.size(), 0)


func test_trail_limited_to_max_length() -> void:
	for i in range(20):
		shrapnel.physics_process(0.01)

	assert_le(shrapnel._position_history.size(), shrapnel.trail_length)


func test_trail_oldest_positions_removed() -> void:
	shrapnel.global_position = Vector2(0, 0)
	shrapnel.position = Vector2(0, 0)

	for i in range(10):
		shrapnel.physics_process(0.01)

	# Oldest position should NOT be (0,0) anymore (it's been pushed out)
	var oldest := shrapnel._position_history[shrapnel._position_history.size() - 1]
	assert_ne(oldest, Vector2(0, 0))


# ============================================================================
# Ricochet Tests
# ============================================================================


func test_ricochet_on_wall_hit() -> void:
	shrapnel.on_body_entered("wall", 123, true)

	assert_eq(shrapnel.get_ricochet_count(), 1)
	assert_false(shrapnel.is_destroyed())


func test_ricochet_increments_count() -> void:
	shrapnel.on_body_entered("wall", 123, true)
	shrapnel.on_body_entered("wall", 124, true)
	shrapnel.on_body_entered("wall", 125, true)

	assert_eq(shrapnel.get_ricochet_count(), 3)


func test_destroyed_after_max_ricochets() -> void:
	shrapnel.on_body_entered("wall", 123, true)
	shrapnel.on_body_entered("wall", 124, true)
	shrapnel.on_body_entered("wall", 125, true)
	shrapnel.on_body_entered("wall", 126, true)  # 4th ricochet

	assert_true(shrapnel.is_destroyed())


func test_ricochet_reduces_speed() -> void:
	var initial_speed := shrapnel.speed
	shrapnel.on_body_entered("wall", 123, true)

	assert_eq(shrapnel.speed, initial_speed * 0.8)


func test_ricochet_changes_direction() -> void:
	var initial_direction := shrapnel.direction
	shrapnel.on_body_entered("wall", 123, true)

	assert_ne(shrapnel.direction, initial_direction)


func test_ricochet_clears_trail() -> void:
	shrapnel.physics_process(0.1)  # Build up trail
	shrapnel.on_body_entered("wall", 123, true)

	assert_true(shrapnel._position_history.is_empty())


func test_multiple_ricochets_compound_speed_loss() -> void:
	var initial_speed := shrapnel.speed
	shrapnel.on_body_entered("wall", 123, true)
	shrapnel.on_body_entered("wall", 124, true)
	shrapnel.on_body_entered("wall", 125, true)

	var expected_speed := initial_speed * 0.8 * 0.8 * 0.8  # 0.512 of original
	assert_almost_eq(shrapnel.speed, expected_speed, 0.01)


# ============================================================================
# Source ID Tests
# ============================================================================


func test_ignores_source_body() -> void:
	shrapnel.source_id = 100

	var result := shrapnel.on_body_entered("wall", 100, true)

	assert_false(result)
	assert_eq(shrapnel.get_ricochet_count(), 0)


func test_ignores_source_area() -> void:
	shrapnel.source_id = 100

	var result := shrapnel.on_area_entered(100, true, true)

	assert_false(result)
	assert_false(shrapnel.is_destroyed())


func test_does_not_ignore_different_source() -> void:
	shrapnel.source_id = 100

	shrapnel.on_body_entered("wall", 200, true)

	assert_eq(shrapnel.get_ricochet_count(), 1)


# ============================================================================
# Dead Entity Pass-through Tests
# ============================================================================


func test_passes_through_dead_body() -> void:
	var result := shrapnel.on_body_entered("enemy", 123, false)  # Not alive

	assert_false(result)
	assert_false(shrapnel.is_destroyed())


func test_passes_through_dead_area_target() -> void:
	var result := shrapnel.on_area_entered(123, false, true)  # Not alive

	assert_false(result)
	assert_false(shrapnel.is_destroyed())


func test_hits_alive_target() -> void:
	shrapnel.on_area_entered(123, true, true)

	assert_true(shrapnel.is_destroyed())
	assert_eq(shrapnel.hits.size(), 1)


# ============================================================================
# Target Hit Tests
# ============================================================================


func test_registers_target_hit() -> void:
	shrapnel.on_area_entered(456, true, true)

	assert_eq(shrapnel.hits[0]["type"], "target")
	assert_eq(shrapnel.hits[0]["id"], 456)


func test_destroyed_on_target_hit() -> void:
	shrapnel.on_area_entered(456, true, true)

	assert_true(shrapnel.is_destroyed())


func test_ignores_area_without_hit_method() -> void:
	var result := shrapnel.on_area_entered(456, true, false)

	assert_false(result)
	assert_false(shrapnel.is_destroyed())


# ============================================================================
# Rotation Tests
# ============================================================================


func test_rotation_matches_direction_right() -> void:
	shrapnel.direction = Vector2.RIGHT
	shrapnel._update_rotation()

	assert_eq(shrapnel.rotation, 0.0)


func test_rotation_matches_direction_down() -> void:
	shrapnel.direction = Vector2.DOWN
	shrapnel._update_rotation()

	assert_almost_eq(shrapnel.rotation, PI / 2, 0.01)


func test_rotation_matches_direction_left() -> void:
	shrapnel.direction = Vector2.LEFT
	shrapnel._update_rotation()

	assert_almost_eq(shrapnel.rotation, PI, 0.01)


func test_rotation_matches_direction_up() -> void:
	shrapnel.direction = Vector2.UP
	shrapnel._update_rotation()

	assert_almost_eq(shrapnel.rotation, -PI / 2, 0.01)


# ============================================================================
# Edge Cases Tests
# ============================================================================


func test_zero_lifetime_immediately_destroyed() -> void:
	shrapnel.lifetime = 0.0
	shrapnel.physics_process(0.01)

	assert_true(shrapnel.is_destroyed())


func test_zero_speed_no_movement() -> void:
	shrapnel.speed = 0.0
	shrapnel.physics_process(1.0)

	assert_eq(shrapnel.position, Vector2.ZERO)


func test_no_movement_after_destroyed() -> void:
	shrapnel._destroyed = true
	shrapnel.position = Vector2(100, 100)
	shrapnel.physics_process(1.0)

	assert_eq(shrapnel.position, Vector2(100, 100),
		"Should not move when destroyed")


func test_max_ricochets_zero() -> void:
	shrapnel.max_ricochets = 0
	shrapnel.on_body_entered("wall", 123, true)

	assert_true(shrapnel.is_destroyed(),
		"Should be destroyed immediately with 0 max ricochets")


func test_very_small_delta() -> void:
	shrapnel.physics_process(0.0001)

	assert_almost_eq(shrapnel.position.x, 0.5, 0.001)
	assert_almost_eq(shrapnel._time_alive, 0.0001, 0.00001)


func test_negative_source_id_matches_default() -> void:
	# Default source_id is -1, which is unlikely to match any real instance
	shrapnel.on_body_entered("wall", -1, true)

	# Should not ricochet because it matches source
	assert_eq(shrapnel.get_ricochet_count(), 0)
