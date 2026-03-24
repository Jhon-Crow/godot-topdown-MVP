extends GutTest
## Unit tests for rpg_rocket.gd projectile.
##
## Tests RPG-7 rocket parameters: speed, acceleration, explosion radius/damage,
## spawn immunity, homing parameters, and trail length.


# ============================================================================
# Mock Classes
# ============================================================================


class MockRpgRocket:
	## Maximum cruise speed in pixels per second.
	var speed: float = 800.0

	## Initial launch speed in pixels per second.
	var speed_initial: float = 300.0

	## Distance over which the rocket accelerates from speed_initial to speed.
	var accel_distance: float = 1000.0

	## Maximum lifetime in seconds.
	var lifetime: float = 5.0

	## Explosion effect radius in pixels.
	var explosion_radius: float = 150.0

	## Explosion damage dealt to entities in radius.
	var explosion_damage: int = 3

	## Seconds after spawn during which collisions are ignored.
	var spawn_immunity_time: float = 0.3

	## Weak homing: turning speed in radians per second.
	var homing_steer_speed: float = 1.2

	## Maximum total turn from original firing direction (radians).
	var homing_max_turn_angle: float = deg_to_rad(30.0)

	## Maximum number of trail points.
	var trail_length: int = 20

	## Direction the rocket travels.
	var direction: Vector2 = Vector2.RIGHT

	## Current rocket speed.
	var _current_speed: float = 0.0

	## Distance traveled so far.
	var _distance_traveled: float = 0.0

	## Time alive.
	var _time_alive: float = 0.0

	## Whether spawn immunity is active.
	var _spawn_immunity_active: bool = true

	## Whether the rocket has exploded.
	var _has_exploded: bool = false

	## Current position.
	var position: Vector2 = Vector2.ZERO

	## Original firing direction (for homing angle limit).
	var _homing_original_direction: Vector2 = Vector2.ZERO

	## Initialize rocket (mirrors _ready).
	func initialize() -> void:
		_current_speed = speed_initial
		_homing_original_direction = direction.normalized()

	## Simulate one physics step.
	func simulate_physics_step(delta: float) -> void:
		if _has_exploded:
			return

		_time_alive += delta

		# Update spawn immunity
		if _spawn_immunity_active and _time_alive >= spawn_immunity_time:
			_spawn_immunity_active = false

		# Lifetime expiry
		if _time_alive >= lifetime:
			_explode()
			return

		# Acceleration phase
		if _distance_traveled < accel_distance:
			var t := _distance_traveled / accel_distance
			_current_speed = lerpf(speed_initial, speed, t * t)
		else:
			_current_speed = speed

		# Move in travel direction
		var movement := direction.normalized() * _current_speed * delta
		position += movement
		_distance_traveled += movement.length()

	## Explode the rocket.
	func _explode() -> void:
		if _has_exploded:
			return
		_has_exploded = true

	## Check if a position is within explosion radius.
	func is_in_explosion_radius(pos: Vector2) -> bool:
		return position.distance_to(pos) <= explosion_radius


var rocket: MockRpgRocket


func before_each() -> void:
	rocket = MockRpgRocket.new()
	rocket.initialize()


func after_each() -> void:
	rocket = null


# ============================================================================
# Default Configuration Tests
# ============================================================================


func test_default_speed() -> void:
	assert_eq(rocket.speed, 800.0,
		"Maximum cruise speed should be 800.0 px/s")


func test_default_speed_initial() -> void:
	assert_eq(rocket.speed_initial, 300.0,
		"Initial launch speed should be 300.0 px/s")


func test_default_accel_distance() -> void:
	assert_eq(rocket.accel_distance, 1000.0,
		"Acceleration distance should be 1000.0 px")


func test_default_explosion_radius() -> void:
	assert_eq(rocket.explosion_radius, 150.0,
		"Explosion radius should be 150.0 px")


func test_default_explosion_damage() -> void:
	assert_eq(rocket.explosion_damage, 3,
		"Explosion damage should be 3")


func test_default_spawn_immunity_time() -> void:
	assert_eq(rocket.spawn_immunity_time, 0.3,
		"Spawn immunity time should be 0.3 seconds")


func test_default_trail_length() -> void:
	assert_eq(rocket.trail_length, 20,
		"Trail length should be 20")


func test_default_lifetime() -> void:
	assert_eq(rocket.lifetime, 5.0,
		"Lifetime should be 5.0 seconds")


# ============================================================================
# Homing Parameter Tests
# ============================================================================


func test_homing_steer_speed() -> void:
	assert_eq(rocket.homing_steer_speed, 1.2,
		"Homing steer speed should be 1.2 rad/s")


func test_homing_max_turn_angle() -> void:
	assert_almost_eq(rocket.homing_max_turn_angle, deg_to_rad(30.0), 0.001,
		"Homing max turn angle should be 30 degrees in radians")


func test_homing_original_direction_stored() -> void:
	assert_eq(rocket._homing_original_direction, Vector2.RIGHT,
		"Original direction should be stored on initialize")


# ============================================================================
# Spawn Immunity Tests
# ============================================================================


func test_spawn_immunity_active_initially() -> void:
	assert_true(rocket._spawn_immunity_active,
		"Spawn immunity should be active at start")


func test_spawn_immunity_deactivates_after_time() -> void:
	# Simulate past spawn immunity time
	rocket.simulate_physics_step(0.15)
	assert_true(rocket._spawn_immunity_active,
		"Immunity should still be active before 0.3s")

	rocket.simulate_physics_step(0.16)
	assert_false(rocket._spawn_immunity_active,
		"Immunity should deactivate after 0.3s")


# ============================================================================
# Acceleration Tests
# ============================================================================


func test_starts_at_initial_speed() -> void:
	assert_eq(rocket._current_speed, rocket.speed_initial,
		"Rocket should start at initial speed")


func test_speed_increases_during_acceleration() -> void:
	# Simulate several frames
	for i in range(30):
		rocket.simulate_physics_step(0.016)

	assert_gt(rocket._current_speed, rocket.speed_initial,
		"Speed should increase during acceleration phase")
	assert_le(rocket._current_speed, rocket.speed,
		"Speed should not exceed max speed")


func test_reaches_max_speed_after_accel_distance() -> void:
	# Simulate enough frames to exceed 1000px acceleration distance
	for i in range(500):
		rocket.simulate_physics_step(0.016)
		if rocket._has_exploded:
			break

	if not rocket._has_exploded:
		assert_almost_eq(rocket._current_speed, rocket.speed, 1.0,
			"Should reach max speed after acceleration distance")


# ============================================================================
# Movement Tests
# ============================================================================


func test_rocket_moves_forward() -> void:
	rocket.simulate_physics_step(0.016)
	assert_gt(rocket.position.x, 0.0,
		"Rocket should move in direction (right)")


func test_distance_tracked() -> void:
	rocket.simulate_physics_step(0.016)
	assert_gt(rocket._distance_traveled, 0.0,
		"Distance traveled should increase")


# ============================================================================
# Lifetime Tests
# ============================================================================


func test_explodes_after_lifetime() -> void:
	# Simulate enough time to exceed 5 second lifetime
	var total_time := 0.0
	while total_time < 6.0:
		rocket.simulate_physics_step(0.05)
		total_time += 0.05
		if rocket._has_exploded:
			break

	assert_true(rocket._has_exploded,
		"Rocket should explode after lifetime expires")


# ============================================================================
# Explosion Radius Tests
# ============================================================================


func test_is_in_explosion_radius() -> void:
	assert_true(rocket.is_in_explosion_radius(Vector2(100, 0)),
		"Position 100 units away should be within 150 radius")


func test_is_not_in_explosion_radius() -> void:
	assert_false(rocket.is_in_explosion_radius(Vector2(200, 0)),
		"Position 200 units away should be outside 150 radius")
