extends GutTest
## Unit tests for DroneGrenade (Issues #1667, #1896).
##
## Tests:
## 1. Drift / inertia movement: DRIFT_FACTOR blends input_dir into banked direction.
## 2. Enemy targeting delay: drone is NOT targetable before the delay elapses.
## 3. Enemy targeting: drone IS targetable once delay elapses.
## 4. is_targetable_by_enemies() returns false after explosion.
## 5. Drift constants are sane.
## 6. (Issue #1896) Drone speed is 600 (50% faster).
## 7. (Issue #1896) Throw phase: player control inactive during THROWING.
## 8. (Issue #1896) Throw phase: transitions to PILOTING when target reached.
## 9. (Issue #1896) Throw phase: early collision explodes instead of piloting.


# ============================================================================
# Mock drone grenade for movement, targeting, and throw-phase logic tests
# ============================================================================


class MockDroneGrenade:
	## Mirrors the drift, enemy-targeting, and throw-phase logic from drone_grenade.gd.

	const DRIFT_FACTOR: float = 0.82
	const ENEMY_TARGETING_DELAY: float = 1.5
	const THROW_PHASE_SPEED: float = 900.0

	enum DroneState { IDLE, THROWING, PILOTING, EXPLODED }

	var drone_speed: float = 600.0

	var _drone_launched: bool = false
	var _drone_alive: bool = false
	var _has_exploded: bool = false

	var _current_move_dir: Vector2 = Vector2.ZERO
	var _linear_velocity: Vector2 = Vector2.ZERO
	var _position: Vector2 = Vector2.ZERO

	var _enemy_targeting_timer: float = 0.0
	var _enemy_targeting_active: bool = false

	var _drone_state: DroneState = DroneState.IDLE
	var _throw_target: Vector2 = Vector2.ZERO
	var _aim_point: Vector2 = Vector2.ZERO

	## Set the aim point (world position of mouse cursor at throw time). Issue #1896.
	func set_aim_point(world_pos: Vector2) -> void:
		_aim_point = world_pos

	## Launch the drone (simulates _launch_drone). Issue #1896: enters THROWING if aim point set.
	func launch() -> void:
		if _drone_launched:
			return
		_drone_launched = true
		_drone_alive = true
		_enemy_targeting_timer = ENEMY_TARGETING_DELAY
		_enemy_targeting_active = false

		if _aim_point != Vector2.ZERO:
			_drone_state = DroneState.THROWING
			_throw_target = _aim_point
			var throw_dir := _position.direction_to(_throw_target)
			_linear_velocity = throw_dir * THROW_PHASE_SPEED
		else:
			_start_piloting()

	## Activate PILOTING phase.
	func _start_piloting() -> void:
		_drone_state = DroneState.PILOTING
		_linear_velocity = Vector2.ZERO
		_current_move_dir = Vector2.ZERO

	## Simulate one physics tick (mirrors _physics_process).
	func process(delta: float, input_dir: Vector2) -> void:
		if _has_exploded or not _drone_launched or not _drone_alive:
			return

		# Tick down enemy targeting delay.
		if not _enemy_targeting_active:
			_enemy_targeting_timer -= delta
			if _enemy_targeting_timer <= 0.0:
				_enemy_targeting_active = true

		# THROWING phase: advance position toward target, transition when close.
		if _drone_state == DroneState.THROWING:
			_position += _linear_velocity * delta
			var dist := _position.distance_to(_throw_target)
			if dist <= THROW_PHASE_SPEED * delta * 2.0 or dist <= 16.0:
				_start_piloting()
			return

		# PILOTING phase: apply drift movement from input.
		if _drone_state != DroneState.PILOTING:
			return

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

	## Simulate a collision during the throw (triggers explosion). Issue #1896.
	func on_throw_collision() -> void:
		if not _drone_alive or _has_exploded:
			return
		if _drone_state == DroneState.THROWING:
			explode()

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
		_drone_state = DroneState.EXPLODED


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


func test_drone_speed_is_600() -> void:
	assert_almost_eq(MockDroneGrenade.new().drone_speed, 600.0, 0.001,
		"drone_speed should be 600 (50% faster than original 400) — Issue #1896")


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


# ============================================================================
# Throw Phase Tests (Issue #1896)
# ============================================================================


func test_throw_phase_speed_constant() -> void:
	assert_almost_eq(MockDroneGrenade.THROW_PHASE_SPEED, 900.0, 0.001,
		"THROW_PHASE_SPEED should be 900.0 px/s")


func test_no_aim_point_enters_piloting_immediately() -> void:
	var drone := MockDroneGrenade.new()
	# No set_aim_point — legacy behavior.
	drone.launch()
	assert_eq(drone._drone_state, MockDroneGrenade.DroneState.PILOTING,
		"Without aim point, drone should enter PILOTING immediately")


func test_with_aim_point_enters_throwing_phase() -> void:
	var drone := MockDroneGrenade.new()
	drone.set_aim_point(Vector2(200.0, 0.0))
	drone.launch()
	assert_eq(drone._drone_state, MockDroneGrenade.DroneState.THROWING,
		"With aim point set, drone should start in THROWING phase (Issue #1896)")


func test_throw_phase_velocity_toward_target() -> void:
	var drone := MockDroneGrenade.new()
	drone.set_aim_point(Vector2(500.0, 0.0))
	drone.launch()
	# Linear velocity should point right toward the target.
	assert_gt(drone._linear_velocity.x, 0.0,
		"Throw velocity X should be positive toward rightward target")
	assert_almost_eq(drone._linear_velocity.y, 0.0, 1.0,
		"Throw velocity Y should be near zero for rightward target")
	assert_almost_eq(drone._linear_velocity.length(), MockDroneGrenade.THROW_PHASE_SPEED, 1.0,
		"Throw velocity magnitude should equal THROW_PHASE_SPEED")


func test_throw_phase_no_player_input_active() -> void:
	var drone := MockDroneGrenade.new()
	drone.set_aim_point(Vector2(200.0, 0.0))
	drone.launch()
	# Simulate a few frames; state should remain THROWING (far from target).
	for _i in range(3):
		drone.process(0.016, Vector2.RIGHT)  # player pushes keys but drone ignores them
	assert_eq(drone._drone_state, MockDroneGrenade.DroneState.THROWING,
		"Player input must not affect state while drone is in THROWING phase")
	# Velocity should still reflect ballistic throw (not drone_speed).
	assert_almost_eq(drone._linear_velocity.length(), MockDroneGrenade.THROW_PHASE_SPEED, 1.0,
		"Velocity during THROWING should be throw speed, not pilot speed")


func test_throw_phase_transitions_to_piloting_on_arrival() -> void:
	var drone := MockDroneGrenade.new()
	# Place target very close so it is reached quickly.
	drone.set_aim_point(Vector2(8.0, 0.0))
	drone.launch()
	# One tick should be enough to reach the target (8px away, tolerance 16px).
	drone.process(0.016, Vector2.ZERO)
	assert_eq(drone._drone_state, MockDroneGrenade.DroneState.PILOTING,
		"Drone should transition from THROWING to PILOTING after reaching the target (Issue #1896)")


func test_throw_phase_piloting_uses_drone_speed() -> void:
	var drone := MockDroneGrenade.new()
	drone.set_aim_point(Vector2(8.0, 0.0))
	drone.launch()
	# Arrive at target.
	drone.process(0.016, Vector2.ZERO)
	assert_eq(drone._drone_state, MockDroneGrenade.DroneState.PILOTING,
		"Pre-condition: should be in PILOTING")
	# Now apply input and check speed.
	drone.process(0.016, Vector2.RIGHT)
	assert_almost_eq(drone._linear_velocity.length(), drone.drone_speed, 0.5,
		"After transition to PILOTING, velocity magnitude should equal drone_speed")


func test_throw_phase_collision_explodes_drone() -> void:
	var drone := MockDroneGrenade.new()
	drone.set_aim_point(Vector2(500.0, 0.0))
	drone.launch()
	assert_eq(drone._drone_state, MockDroneGrenade.DroneState.THROWING,
		"Pre-condition: drone is THROWING")
	# Simulate hitting a wall during the throw.
	drone.on_throw_collision()
	assert_true(drone._has_exploded,
		"Collision during THROWING phase must explode the drone (Issue #1896)")
	assert_false(drone._drone_alive,
		"Drone must not be alive after throw-phase collision explosion")
	assert_eq(drone._drone_state, MockDroneGrenade.DroneState.EXPLODED,
		"State must be EXPLODED after throw-phase collision")


func test_throw_phase_collision_never_enters_piloting() -> void:
	var drone := MockDroneGrenade.new()
	drone.set_aim_point(Vector2(500.0, 0.0))
	drone.launch()
	drone.on_throw_collision()
	# Simulate further ticks — state must stay EXPLODED.
	for _i in range(5):
		drone.process(0.016, Vector2.ZERO)
	assert_eq(drone._drone_state, MockDroneGrenade.DroneState.EXPLODED,
		"After throw-phase explosion the drone must never transition to PILOTING")


# ============================================================================
# C# Player Interop Regression Tests (Issue #1896)
# ============================================================================


func _read_csharp_player_grenade_source() -> String:
	var file := FileAccess.open("res://Scripts/Characters/Player.Grenade.cs", FileAccess.READ)
	assert_not_null(file, "Player.Grenade.cs must be readable for C# interop regression tests")
	if file == null:
		return ""
	return file.get_as_text()


func _extract_csharp_method(source: String, signature: String) -> String:
	var method_start := source.find(signature)
	assert_gt(method_start, -1, "Expected C# method signature to exist: %s" % signature)
	if method_start == -1:
		return ""

	var brace_start := source.find("{", method_start)
	assert_gt(brace_start, -1, "Expected method body to start after signature: %s" % signature)
	if brace_start == -1:
		return ""

	var depth := 0
	for i in range(brace_start, source.length()):
		var ch := source.substr(i, 1)
		if ch == "{":
			depth += 1
		elif ch == "}":
			depth -= 1
			if depth == 0:
				return source.substr(brace_start, i - brace_start + 1)

	fail_test("Expected method body to close for signature: %s" % signature)
	return ""


func test_csharp_simple_throw_sets_drone_aim_before_unfreeze() -> void:
	var source := _read_csharp_player_grenade_source()
	var method := _extract_csharp_method(source, "private void ThrowSimpleGrenade()")

	var aim_idx := method.find("PassDroneThrowAimPoint(targetPos);")
	var unfreeze_idx := method.find("_activeGrenade.Freeze = false;")
	var throw_call_idx := method.find("_activeGrenade.Call(\"throw_grenade_simple\"")

	assert_gt(aim_idx, -1,
		"C# simple throw must pass the cursor target to DroneGrenade.set_aim_point before launch")
	assert_gt(unfreeze_idx, -1, "C# simple throw must still unfreeze the grenade")
	assert_gt(throw_call_idx, -1, "C# simple throw must still call the GDScript throw hook")
	assert_lt(aim_idx, unfreeze_idx,
		"C# simple throw must set the drone aim point before unfreezing to avoid fallback launch")
	assert_lt(aim_idx, throw_call_idx,
		"C# simple throw must set the drone aim point before calling throw_grenade_simple")


func test_csharp_velocity_throw_sets_drone_aim_before_unfreeze() -> void:
	var source := _read_csharp_player_grenade_source()
	var method := _extract_csharp_method(source, "private void ThrowGrenade(Vector2 dragEnd)")

	var aim_idx := method.find("PassDroneThrowAimPoint(dragEnd);")
	var unfreeze_idx := method.find("_activeGrenade.Freeze = false;")
	var throw_call_idx := method.find("_activeGrenade.Call(\"throw_grenade_with_direction\"")

	assert_gt(aim_idx, -1,
		"C# velocity throw must pass dragEnd to DroneGrenade.set_aim_point before launch")
	assert_gt(unfreeze_idx, -1, "C# velocity throw must still unfreeze the grenade")
	assert_gt(throw_call_idx, -1, "C# velocity throw must still call the GDScript throw hook")
	assert_lt(aim_idx, unfreeze_idx,
		"C# velocity throw must set the drone aim point before unfreezing to avoid fallback launch")
	assert_lt(aim_idx, throw_call_idx,
		"C# velocity throw must set the drone aim point before calling throw_grenade_with_direction")


func test_csharp_drone_aim_helper_calls_snake_case_gdscript_method() -> void:
	var source := _read_csharp_player_grenade_source()
	var method := _extract_csharp_method(source, "private void PassDroneThrowAimPoint(Vector2 aimPoint)")

	assert_true(method.contains("_activeGrenade.HasMethod(\"set_aim_point\")"),
		"C# interop must look for DroneGrenade's snake_case GDScript method")
	assert_true(method.contains("_activeGrenade.Call(\"set_aim_point\", aimPoint)"),
		"C# interop must call DroneGrenade.set_aim_point with the world-space aim point")
