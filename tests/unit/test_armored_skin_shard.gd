extends GutTest
## Unit tests for armored_skin_shard.gd projectile.
##
## Tests shard speed, lifetime, damage, trail, and deceleration behavior
## for the glass/crystal shard projectile from the Armored Skin passive item.


# ============================================================================
# Mock Classes
# ============================================================================


class MockArmoredSkinShard:
	## Speed of the shard in pixels per second.
	var speed: float = 1600.0

	## Maximum lifetime in seconds before auto-destruction.
	var lifetime: float = 0.7

	## Damage dealt on hit.
	var damage: int = 5

	## Maximum number of trail points to maintain.
	var trail_length: int = 5

	## Direction the shard travels.
	var direction: Vector2 = Vector2.RIGHT

	## Instance ID of the player who triggered this shard.
	var source_id: int = -1

	## Timer tracking remaining lifetime.
	var _time_alive: float = 0.0

	## History of global positions for the trail effect.
	var _position_history: Array = []

	## Current position.
	var position: Vector2 = Vector2.ZERO

	## Whether the shard has been destroyed.
	var _destroyed: bool = false

	## Simulate movement with deceleration for one frame.
	func simulate_physics_step(delta: float) -> void:
		if _destroyed:
			return

		# Move in the set direction
		var movement := direction * speed * delta
		position += movement

		# Decelerate gradually (matches armored_skin_shard.gd)
		speed = maxf(speed * 0.994, 150.0)

		# Update trail
		_position_history.push_front(position)
		while _position_history.size() > trail_length:
			_position_history.pop_back()

		# Track lifetime
		_time_alive += delta
		if _time_alive >= lifetime:
			_destroy()

	## Destroy the shard.
	func _destroy() -> void:
		_destroyed = true

	## Get rotation based on direction.
	func get_rotation() -> float:
		return direction.angle()


var shard: MockArmoredSkinShard


func before_each() -> void:
	shard = MockArmoredSkinShard.new()


func after_each() -> void:
	shard = null


# ============================================================================
# Default Configuration Tests
# ============================================================================


func test_default_speed() -> void:
	assert_eq(shard.speed, 1600.0,
		"Default speed should be 1600.0 pixels per second")


func test_default_lifetime() -> void:
	assert_eq(shard.lifetime, 0.7,
		"Default lifetime should be 0.7 seconds")


func test_default_damage() -> void:
	assert_eq(shard.damage, 5,
		"Default damage should be 5 (Issue #1488)")


func test_default_trail_length() -> void:
	assert_eq(shard.trail_length, 5,
		"Default trail length should be 5")


func test_default_direction() -> void:
	assert_eq(shard.direction, Vector2.RIGHT,
		"Default direction should be RIGHT")


# ============================================================================
# Movement Tests
# ============================================================================


func test_movement_in_direction() -> void:
	shard.direction = Vector2.RIGHT
	shard.simulate_physics_step(0.016)  # ~60 FPS

	assert_gt(shard.position.x, 0.0,
		"Shard should move to the right")
	assert_almost_eq(shard.position.y, 0.0, 0.01,
		"Shard should not move vertically when moving right")


func test_movement_distance_first_frame() -> void:
	var initial_speed := shard.speed
	var delta := 0.016
	shard.simulate_physics_step(delta)

	var expected_x := initial_speed * delta
	assert_almost_eq(shard.position.x, expected_x, 0.1,
		"First frame movement should use initial speed")


func test_deceleration_reduces_speed() -> void:
	var initial_speed := shard.speed
	shard.simulate_physics_step(0.016)

	assert_lt(shard.speed, initial_speed,
		"Speed should decrease after deceleration")


func test_deceleration_has_minimum_speed() -> void:
	# Run many frames to reach minimum speed
	for i in range(1000):
		shard.simulate_physics_step(0.001)
		if shard._destroyed:
			break

	# Speed should never go below 150.0
	assert_gte(shard.speed, 150.0,
		"Speed should never go below minimum of 150.0")


func test_deceleration_factor() -> void:
	var speed_before := shard.speed
	shard.simulate_physics_step(0.016)
	# After one step: speed * 0.994 (clamped to min 150)
	var expected_speed := maxf(speed_before * 0.994, 150.0)
	assert_almost_eq(shard.speed, expected_speed, 0.01,
		"Speed should decelerate by factor of 0.994 per step")


# ============================================================================
# Lifetime Tests
# ============================================================================


func test_shard_alive_before_lifetime() -> void:
	shard.simulate_physics_step(0.5)
	assert_false(shard._destroyed,
		"Shard should be alive before lifetime expires")


func test_shard_destroyed_after_lifetime() -> void:
	# Simulate enough frames to exceed 0.7 second lifetime
	var total_time := 0.0
	var delta := 0.016
	while total_time < 1.0:
		shard.simulate_physics_step(delta)
		total_time += delta
		if shard._destroyed:
			break

	assert_true(shard._destroyed,
		"Shard should be destroyed after lifetime expires")


# ============================================================================
# Trail Tests
# ============================================================================


func test_trail_builds_up() -> void:
	shard.simulate_physics_step(0.016)
	assert_eq(shard._position_history.size(), 1,
		"Trail should have 1 point after first frame")

	shard.simulate_physics_step(0.016)
	assert_eq(shard._position_history.size(), 2,
		"Trail should have 2 points after second frame")


func test_trail_capped_at_trail_length() -> void:
	for i in range(10):
		shard.simulate_physics_step(0.016)

	assert_le(shard._position_history.size(), shard.trail_length,
		"Trail should not exceed trail_length")


# ============================================================================
# Rotation Tests
# ============================================================================


func test_rotation_matches_direction_right() -> void:
	shard.direction = Vector2.RIGHT
	assert_almost_eq(shard.get_rotation(), 0.0, 0.01,
		"Rotation should be 0 for right direction")


func test_rotation_matches_direction_down() -> void:
	shard.direction = Vector2.DOWN
	assert_almost_eq(shard.get_rotation(), PI / 2.0, 0.01,
		"Rotation should be PI/2 for down direction")
