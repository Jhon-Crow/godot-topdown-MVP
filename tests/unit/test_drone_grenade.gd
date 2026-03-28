extends GutTest
## Unit tests for DroneGrenade (Issue #1667).
##
## Tests:
## 1. Drift / inertia movement: DRIFT_FACTOR blends input_dir into banked direction.
## 2. Enemy targeting delay: drone is NOT targetable before the delay elapses.
## 3. Enemy targeting: drone IS targetable once delay elapses.
## 4. is_targetable_by_enemies() returns false after explosion.
## 5. Drift constants are sane.


# ============================================================================
# Mock drone grenade for movement and targeting logic tests
# ============================================================================


class MockDroneGrenade:
	## Mirrors the drift and enemy-targeting logic from drone_grenade.gd.

	const DRIFT_FACTOR: float = 0.82
	const ENEMY_TARGETING_DELAY: float = 1.5

	var drone_speed: float = 400.0

	var _drone_launched: bool = false
	var _drone_alive: bool = false
	var _has_exploded: bool = false

	var _current_move_dir: Vector2 = Vector2.ZERO
	var _linear_velocity: Vector2 = Vector2.ZERO

	var _enemy_targeting_timer: float = 0.0
	var _enemy_targeting_active: bool = false

	## Launch the drone (simulates _launch_drone).
	func launch() -> void:
		if _drone_launched:
			return
		_drone_launched = true
		_drone_alive = true
		_enemy_targeting_timer = ENEMY_TARGETING_DELAY
		_enemy_targeting_active = false

	## Simulate one physics tick (mirrors _physics_process).
	func process(delta: float, input_dir: Vector2) -> void:
		if _has_exploded or not _drone_launched or not _drone_alive:
			return

		# Tick down enemy targeting delay.
		if not _enemy_targeting_active:
			_enemy_targeting_timer -= delta
			if _enemy_targeting_timer <= 0.0:
				_enemy_targeting_active = true

		# Drift / inertia movement.
		if input_dir != Vector2.ZERO:
			if _current_move_dir == Vector2.ZERO:
				_current_move_dir = input_dir
			else:
				_current_move_dir = (_current_move_dir * DRIFT_FACTOR + input_dir * (1.0 - DRIFT_FACTOR)).normalized()
			_linear_velocity = _current_move_dir * drone_speed
		else:
			_current_move_dir = _current_move_dir * DRIFT_FACTOR
			if _current_move_dir.length_squared() < 0.01:
				_current_move_dir = Vector2.ZERO
			_linear_velocity = _current_move_dir * drone_speed

	## Returns true when enemies should aim at this drone.
	func is_targetable_by_enemies() -> bool:
		return _drone_alive and not _has_exploded and _enemy_targeting_active

	## Simulate explosion (on_hit).
	func explode() -> void:
		if not _drone_alive or _has_exploded:
			return
		_drone_alive = false
		_has_exploded = true
		_enemy_targeting_active = false


# ============================================================================
# Drift / Inertia Movement Tests (Issue #1667)
# ============================================================================


func test_drift_factor_constant_value() -> void:
	assert_almost_eq(MockDroneGrenade.DRIFT_FACTOR, 0.82, 0.001,
		"DRIFT_FACTOR should be 0.82 — matching the enemy Drone banking feel")


func test_drift_factor_range() -> void:
	assert_gt(MockDroneGrenade.DRIFT_FACTOR, 0.0,
		"DRIFT_FACTOR must be > 0")
	assert_lt(MockDroneGrenade.DRIFT_FACTOR, 1.0,
		"DRIFT_FACTOR must be < 1 (otherwise no change ever occurs)")


func test_first_input_sets_direction_directly() -> void:
	var drone := MockDroneGrenade.new()
	drone.launch()
	drone.process(0.016, Vector2.RIGHT)
	assert_almost_eq(drone._current_move_dir.x, 1.0, 0.001,
		"First input should set move direction directly (no drift blending yet)")
	assert_almost_eq(drone._current_move_dir.y, 0.0, 0.001,
		"First input: no Y component when input is pure RIGHT")


func test_drift_resists_instant_direction_change() -> void:
	var drone := MockDroneGrenade.new()
	drone.launch()
	# Establish rightward movement.
	drone.process(0.016, Vector2.RIGHT)
	# Now request upward movement — drift should resist full change.
	drone.process(0.016, Vector2.UP)
	# After one frame of up input, the banked dir should still have positive X (rightward momentum).
	assert_gt(drone._current_move_dir.x, 0.0,
		"Drift should carry rightward momentum through a 90° input change")
	# And should have started turning upward (negative Y = up in Godot).
	assert_lt(drone._current_move_dir.y, 0.0,
		"Drift should have started turning toward the up input")


func test_drift_majority_of_old_direction_preserved() -> void:
	var drone := MockDroneGrenade.new()
	drone.launch()
	# Rightward, then request up.
	drone.process(0.016, Vector2.RIGHT)
	drone.process(0.016, Vector2.UP)
	# With DRIFT_FACTOR=0.82 the rightward component dominates over the 0.18 upward blend.
	assert_gt(abs(drone._current_move_dir.x), abs(drone._current_move_dir.y),
		"After one frame of 90° change, old direction should still dominate")


func test_drift_velocity_equals_drone_speed_when_moving() -> void:
	var drone := MockDroneGrenade.new()
	drone.launch()
	drone.process(0.016, Vector2.RIGHT)
	assert_almost_eq(drone._linear_velocity.length(), drone.drone_speed, 0.5,
		"Velocity magnitude should equal drone_speed while input is held")


func test_drift_gradually_follows_new_direction() -> void:
	var drone := MockDroneGrenade.new()
	drone.launch()
	drone.process(0.016, Vector2.RIGHT)
	# Apply upward input for many frames.
	for _i in range(60):
		drone.process(0.016, Vector2.UP)
	# After 60 frames, the direction should have substantially turned upward.
	assert_lt(drone._current_move_dir.y, -0.8,
		"After many frames of up input, move direction should mostly face up")


func test_no_input_bleeds_velocity() -> void:
	var drone := MockDroneGrenade.new()
	drone.launch()
	# Build up rightward momentum.
	drone.process(0.016, Vector2.RIGHT)
	var initial_speed := drone._linear_velocity.length()
	# Release input — velocity should bleed off.
	drone.process(0.016, Vector2.ZERO)
	assert_lt(drone._linear_velocity.length(), initial_speed,
		"No input should bleed off velocity (coasting)")


func test_no_input_from_zero_stays_zero() -> void:
	var drone := MockDroneGrenade.new()
	drone.launch()
	# With zero initial momentum and zero input, velocity should stay zero.
	drone.process(0.016, Vector2.ZERO)
	assert_almost_eq(drone._linear_velocity.length(), 0.0, 0.01,
		"Zero input from rest should produce zero velocity")


# ============================================================================
# Enemy Targeting Delay Tests (Issue #1667)
# ============================================================================


func test_targeting_delay_constant() -> void:
	assert_almost_eq(MockDroneGrenade.ENEMY_TARGETING_DELAY, 1.5, 0.001,
		"Enemy targeting delay should be 1.5 seconds")


func test_not_targetable_immediately_after_launch() -> void:
	var drone := MockDroneGrenade.new()
	drone.launch()
	assert_false(drone.is_targetable_by_enemies(),
		"Drone must NOT be targetable immediately after launch (targeting delay not elapsed)")


func test_not_targetable_before_delay_elapses() -> void:
	var drone := MockDroneGrenade.new()
	drone.launch()
	# Tick just under the delay.
	drone.process(1.4, Vector2.ZERO)
	assert_false(drone.is_targetable_by_enemies(),
		"Drone must NOT be targetable while targeting delay is still counting down")


func test_targetable_after_delay_elapses() -> void:
	var drone := MockDroneGrenade.new()
	drone.launch()
	# Tick past the delay.
	drone.process(2.0, Vector2.ZERO)
	assert_true(drone.is_targetable_by_enemies(),
		"Drone must be targetable once the enemy targeting delay has elapsed")


func test_not_targetable_before_launch() -> void:
	var drone := MockDroneGrenade.new()
	# No launch() called.
	assert_false(drone.is_targetable_by_enemies(),
		"Drone must not be targetable before it is launched")


func test_not_targetable_after_explosion() -> void:
	var drone := MockDroneGrenade.new()
	drone.launch()
	# Let delay elapse.
	drone.process(2.0, Vector2.ZERO)
	assert_true(drone.is_targetable_by_enemies(), "Pre-condition: should be targetable")
	# Explode the drone.
	drone.explode()
	assert_false(drone.is_targetable_by_enemies(),
		"Drone must NOT be targetable after it has exploded")


func test_explode_sets_drone_alive_false() -> void:
	var drone := MockDroneGrenade.new()
	drone.launch()
	drone.explode()
	assert_false(drone._drone_alive,
		"_drone_alive must be false after explosion")


func test_explode_sets_has_exploded_true() -> void:
	var drone := MockDroneGrenade.new()
	drone.launch()
	drone.explode()
	assert_true(drone._has_exploded,
		"_has_exploded must be true after explosion")


func test_double_explode_is_idempotent() -> void:
	var drone := MockDroneGrenade.new()
	drone.launch()
	drone.explode()
	drone.explode()
	# Should not crash; drone remains dead.
	assert_false(drone.is_targetable_by_enemies(),
		"Double explode must not re-enable targeting")


func test_targeting_timer_not_active_after_explode() -> void:
	var drone := MockDroneGrenade.new()
	drone.launch()
	drone.process(2.0, Vector2.ZERO)
	drone.explode()
	assert_false(drone._enemy_targeting_active,
		"_enemy_targeting_active must be cleared when drone explodes")
