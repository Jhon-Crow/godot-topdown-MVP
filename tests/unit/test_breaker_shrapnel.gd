extends GutTest
## Unit tests for BreakerShrapnel projectile (Issue #678).
##
## Tests the breaker shrapnel mechanics including movement, no-ricochet behavior,
## lifetime management, fractional damage dealing, and smoky trail effects.


# ============================================================================
# Mock BreakerShrapnel for Logic Tests
# ============================================================================


class MockBreakerShrapnel:
	## Speed of the shrapnel in pixels per second.
	var speed: float = 1800.0

	## Maximum lifetime in seconds.
	var lifetime: float = 1.5

	## Damage dealt on hit.
	var damage: float = 0.1

	## Maximum number of trail points.
	var trail_length: int = 10

	## Direction the shrapnel travels.
	var direction: Vector2 = Vector2.RIGHT

	## Instance ID of the source (bullet shooter).
	var source_id: int = -1

	## Timer tracking remaining lifetime.
	var _time_alive: float = 0.0

	## History of positions for the trail effect.
	var _position_history: Array[Vector2] = []

	## Noise offset for trail wobble.
	var _trail_noise_offset: float = 0.0

	## Noise speed for trail wobble.
	var _trail_noise_speed: float = 10.0

	## Position simulation.
	var global_position: Vector2 = Vector2.ZERO
	var position: Vector2 = Vector2.ZERO

	## Rotation.
	var rotation: float = 0.0

	## Track destroyed state.
	var _destroyed: bool = false

	## Track hits.
	var hits: Array = []

	## Simulate physics process.
	func physics_process(delta: float) -> void:
		if _destroyed:
			return

		# Move in the set direction
		var movement := direction * speed * delta
		position += movement
		global_position = position

		# Slow down gradually
		speed = maxf(speed * 0.995, 200.0)

		# Update smoky trail
		_update_smoky_trail(delta)

		# Track lifetime
		_time_alive += delta
		if _time_alive >= lifetime:
			_destroyed = true

	## Update rotation.
	func _update_rotation() -> void:
		rotation = direction.angle()

	## Update smoky trail with wobble.
	func _update_smoky_trail(delta: float) -> void:
		_trail_noise_offset += _trail_noise_speed * delta

		var perpendicular := Vector2(-direction.y, direction.x).normalized()
		var wobble_amount := sin(_trail_noise_offset) * 1.5 + sin(_trail_noise_offset * 2.3) * 0.8
		var wobbled_pos := global_position + perpendicular * wobble_amount

		_position_history.push_front(wobbled_pos)

		while _position_history.size() > trail_length:
			_position_history.pop_back()

	## Simulate hitting a body — breaker shrapnel does NOT ricochet.
	func on_body_entered(body_type: String, body_instance_id: int, is_alive: bool = true) -> bool:
		if _destroyed:
			return false

		# Don't collide with the source
		if source_id == body_instance_id:
			return false

		# Pass through dead entities
		if not is_alive:
			return false

		# Hit a wall — destroy immediately (NO ricochet)
		if body_type == "wall":
			_destroyed = true
			return false

		# Hit other bodies — destroy
		_destroyed = true
		return false

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

		hits.append({"type": "target", "id": parent_instance_id, "damage": damage})
		_destroyed = true
		return true

	## Check if destroyed.
	func is_destroyed() -> bool:
		return _destroyed


var shrapnel: MockBreakerShrapnel


func before_each() -> void:
	shrapnel = MockBreakerShrapnel.new()


func after_each() -> void:
	shrapnel = null


# ============================================================================
# Default Configuration Tests
# ============================================================================


func test_default_speed() -> void:
	assert_eq(shrapnel.speed, 1800.0,
		"Default speed should be 1800 px/s")


func test_default_lifetime() -> void:
	assert_eq(shrapnel.lifetime, 1.5,
		"Default lifetime should be 1.5 seconds")


func test_default_damage() -> void:
	assert_eq(shrapnel.damage, 0.1,
		"Default damage should be 0.1")


func test_default_trail_length() -> void:
	assert_eq(shrapnel.trail_length, 10,
		"Default trail length should be 10")


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


func test_not_destroyed_initially() -> void:
	assert_false(shrapnel.is_destroyed())


# ============================================================================
# Movement Tests
# ============================================================================


func test_moves_in_direction() -> void:
	shrapnel.global_position = Vector2.ZERO
	shrapnel.position = Vector2.ZERO
	shrapnel.physics_process(0.01)  # 10ms

	# Should move right by speed * delta = 1800 * 0.01 = 18
	assert_almost_eq(shrapnel.position.x, 18.0, 0.01)
	assert_eq(shrapnel.position.y, 0.0)


func test_moves_in_custom_direction() -> void:
	shrapnel.global_position = Vector2.ZERO
	shrapnel.position = Vector2.ZERO
	shrapnel.direction = Vector2.DOWN
	shrapnel.physics_process(0.01)

	assert_eq(shrapnel.position.x, 0.0)
	assert_almost_eq(shrapnel.position.y, 18.0, 0.01)


func test_speed_decreases_gradually() -> void:
	var initial_speed := shrapnel.speed
	shrapnel.physics_process(0.1)

	assert_lt(shrapnel.speed, initial_speed,
		"Speed should decrease due to air resistance")
	assert_gt(shrapnel.speed, 200.0,
		"Speed should not go below minimum")


func test_speed_minimum_floor() -> void:
	# Set very low speed - should never go below 200
	shrapnel.speed = 201.0
	for i in range(100):
		shrapnel.physics_process(0.01)

	assert_ge(shrapnel.speed, 200.0,
		"Speed should never go below 200")


# ============================================================================
# Lifetime Tests
# ============================================================================


func test_time_alive_increases() -> void:
	shrapnel.physics_process(0.5)
	assert_eq(shrapnel._time_alive, 0.5)


func test_destroyed_after_lifetime() -> void:
	shrapnel.physics_process(2.0)  # Past 1.5 lifetime
	assert_true(shrapnel.is_destroyed())


func test_not_destroyed_before_lifetime() -> void:
	shrapnel.physics_process(1.0)
	assert_false(shrapnel.is_destroyed())


func test_destroyed_at_exact_lifetime() -> void:
	shrapnel.physics_process(1.5)
	assert_true(shrapnel.is_destroyed())


# ============================================================================
# No Ricochet Tests (Key difference from normal Shrapnel)
# ============================================================================


func test_destroyed_on_wall_hit() -> void:
	shrapnel.on_body_entered("wall", 123, true)

	assert_true(shrapnel.is_destroyed(),
		"Breaker shrapnel should be destroyed on wall hit (no ricochet)")


func test_multiple_wall_hits_dont_happen() -> void:
	# First wall hit destroys it
	shrapnel.on_body_entered("wall", 123, true)
	assert_true(shrapnel.is_destroyed())

	# Second hit should be ignored (already destroyed)
	var result := shrapnel.on_body_entered("wall", 124, true)
	assert_false(result)


# ============================================================================
# Source ID Tests
# ============================================================================


func test_ignores_source_body() -> void:
	shrapnel.source_id = 100
	var result := shrapnel.on_body_entered("wall", 100, true)

	assert_false(result)
	assert_false(shrapnel.is_destroyed(),
		"Should not be destroyed by collision with source")


func test_ignores_source_area() -> void:
	shrapnel.source_id = 100
	var result := shrapnel.on_area_entered(100, true, true)

	assert_false(result)
	assert_false(shrapnel.is_destroyed())


func test_does_not_ignore_different_source() -> void:
	shrapnel.source_id = 100
	shrapnel.on_body_entered("wall", 200, true)

	assert_true(shrapnel.is_destroyed())


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
# Damage Tests
# ============================================================================


func test_registers_fractional_damage() -> void:
	shrapnel.on_area_entered(456, true, true)

	assert_eq(shrapnel.hits[0]["damage"], 0.1,
		"Breaker shrapnel should deal 0.1 damage")


func test_custom_damage_value() -> void:
	shrapnel.damage = 0.2
	shrapnel.on_area_entered(456, true, true)

	assert_eq(shrapnel.hits[0]["damage"], 0.2)


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


func test_trail_has_wobble_offset() -> void:
	# The trail positions should not perfectly follow the movement line
	# because of the noise-based wobble
	shrapnel.global_position = Vector2.ZERO
	shrapnel.position = Vector2.ZERO
	shrapnel.direction = Vector2.RIGHT

	for i in range(5):
		shrapnel.physics_process(0.05)

	# Check that at least one trail point has a non-zero y component
	# (perpendicular wobble)
	var has_wobble := false
	for pos in shrapnel._position_history:
		if abs(pos.y) > 0.01:
			has_wobble = true
			break

	assert_true(has_wobble,
		"Trail should have perpendicular wobble from noise")


func test_noise_offset_advances() -> void:
	var initial_offset := shrapnel._trail_noise_offset
	shrapnel.physics_process(0.1)

	assert_gt(shrapnel._trail_noise_offset, initial_offset,
		"Noise offset should increase over time")


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


# ============================================================================
# Edge Cases
# ============================================================================


func test_zero_lifetime_immediately_destroyed() -> void:
	shrapnel.lifetime = 0.0
	shrapnel.physics_process(0.01)
	assert_true(shrapnel.is_destroyed())


func test_no_movement_after_destroyed() -> void:
	shrapnel._destroyed = true
	shrapnel.position = Vector2(100, 100)
	shrapnel.physics_process(1.0)
	assert_eq(shrapnel.position, Vector2(100, 100),
		"Should not move when destroyed")
