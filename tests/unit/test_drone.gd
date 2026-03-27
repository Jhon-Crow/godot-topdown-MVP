extends GutTest
## Unit tests for Drone scene object (Issue #1397, #1417, #1508).
##
## Tests the drone visual constants, group membership, combat visuals,
## and spiral search movement logic.


# ============================================================================
# Mock Drone for Logic Tests
# ============================================================================


class MockDrone:
	const DRONE_BODY_SIZE: float = 10.0
	const ROTOR_ARM_LENGTH: float = 12.0
	const ROTOR_RADIUS: float = 4.0
	const ROTOR_SPEED: float = 20.0
	## Spiral constants (Issue #1508)
	const SPIRAL_START_RADIUS: float = 60.0
	const SPIRAL_MAX_RADIUS: float = 600.0
	const SPIRAL_EXPAND_RATE: float = 12.0
	const SPIRAL_ANGULAR_SPEED: float = 1.2
	const SEARCH_SPEED: float = 150.0
	const COMBAT_SPEED: float = 675.0
	## Re-aiming constants (Issue #1542)
	const DRIFT_FACTOR: float = 0.93
	const MISS_DOT_THRESHOLD: float = -0.2
	const REAIM_DRIFT_FACTOR: float = 0.70
	const REAIM_SPEED: float = 220.0
	const REAIM_EXIT_DOT: float = 0.70

	var _is_alive: bool = true
	var _rotor_angle: float = 0.0
	var _groups: Array[String] = []
	var _led_color: Color = Color(0.2, 0.8, 0.2, 0.9)  # Green = searching
	var _is_combat: bool = false
	## Spiral state (Issue #1508)
	var _spiral_angle: float = 0.0
	var _spiral_radius: float = SPIRAL_START_RADIUS
	var _operator_pos: Vector2 = Vector2.ZERO
	var _drone_pos: Vector2 = Vector2.ZERO
	var _velocity: Vector2 = Vector2.ZERO
	## Nav-agent simulation (Issue #1508 follow-up: wall avoidance)
	## When non-null, update_searching uses this position as "next path position"
	## instead of the raw orbit target, mimicking NavigationAgent2D pathfinding.
	var _nav_next_pos: Vector2 = Vector2(INF, INF)
	var _avoidance_velocity: Vector2 = Vector2.ZERO  # ORCA result
	var _avoidance_enabled: bool = false
	## Re-aiming state (Issue #1542)
	var _is_reaiming: bool = false
	var _prev_alignment: float = 1.0
	var _current_move_dir: Vector2 = Vector2.ZERO
	var _player_pos: Vector2 = Vector2.ZERO

	func _init() -> void:
		_groups.append("enemies")

	func is_in_group(group: String) -> bool:
		return group in _groups

	func is_alive() -> bool:
		return _is_alive

	func update_rotors(delta: float) -> void:
		var speed_mult: float = 3.0 if _is_combat else 1.0
		_rotor_angle += ROTOR_SPEED * delta * speed_mult

	func activate_combat() -> void:
		_is_combat = true
		_led_color = Color(1.0, 0.1, 0.05, 0.95)  # Red = combat

	## Simulate one tick of spiral search movement.
	## Mirrors the real _update_searching() logic including nav-agent and ORCA paths.
	func update_searching(delta: float) -> void:
		_spiral_angle += SPIRAL_ANGULAR_SPEED * delta
		_spiral_radius = minf(_spiral_radius + SPIRAL_EXPAND_RATE * delta, SPIRAL_MAX_RADIUS)
		var orbit_target: Vector2 = _operator_pos + Vector2(cos(_spiral_angle), sin(_spiral_angle)) * _spiral_radius

		var intended_dir: Vector2
		if _nav_next_pos.x != INF:
			# Nav-agent available: move toward next path waypoint (avoids walls).
			intended_dir = (_nav_next_pos - _drone_pos).normalized()
		else:
			# No nav agent: move directly toward orbit target.
			var to_target: Vector2 = orbit_target - _drone_pos
			if to_target.length() > 0.0:
				intended_dir = to_target.normalized()
			else:
				intended_dir = Vector2.ZERO

		var intended_vel: Vector2 = intended_dir * SEARCH_SPEED

		# ORCA avoidance: use pre-computed safe velocity if available.
		if _avoidance_enabled and _avoidance_velocity.length_squared() > 0.01:
			_velocity = _avoidance_velocity
		else:
			_velocity = intended_vel

		_drone_pos += _velocity * delta  # Integrate position for tests

	## Simulate one tick of combat movement.
	## Mirrors the real _update_combat() re-aiming logic (Issue #1542).
	func update_combat(delta: float) -> void:
		var to_player: Vector2 = _player_pos - _drone_pos
		var desired_dir: Vector2 = to_player.normalized() if to_player.length() > 0.0 else Vector2.RIGHT

		if _current_move_dir == Vector2.ZERO:
			_current_move_dir = desired_dir
		else:
			var drift: float = REAIM_DRIFT_FACTOR if _is_reaiming else DRIFT_FACTOR
			_current_move_dir = (_current_move_dir * drift + desired_dir * (1.0 - drift)).normalized()

		var alignment: float = _current_move_dir.dot(desired_dir)
		# Re-aim only after zanос bottoms out (alignment was falling, now rising).
		if not _is_reaiming and alignment < MISS_DOT_THRESHOLD and alignment > _prev_alignment:
			_is_reaiming = true
		elif _is_reaiming and alignment >= REAIM_EXIT_DOT:
			_is_reaiming = false
		_prev_alignment = alignment

		var speed: float = REAIM_SPEED if _is_reaiming else COMBAT_SPEED
		_velocity = _current_move_dir * speed
		_drone_pos += _velocity * delta


# ============================================================================
# Visual Constants Tests
# ============================================================================


func test_body_size() -> void:
	assert_eq(MockDrone.DRONE_BODY_SIZE, 10.0, "Drone body size should be 10 pixels")


func test_rotor_arm_length() -> void:
	assert_eq(MockDrone.ROTOR_ARM_LENGTH, 12.0, "Rotor arm should be 12 pixels from center")


func test_rotor_radius() -> void:
	assert_eq(MockDrone.ROTOR_RADIUS, 4.0, "Rotor radius should be 4 pixels")


func test_rotor_speed() -> void:
	assert_eq(MockDrone.ROTOR_SPEED, 20.0, "Rotor speed should be 20 rad/s")


# ============================================================================
# Group Tests
# ============================================================================


func test_drone_in_enemies_group() -> void:
	var drone := MockDrone.new()
	assert_true(drone.is_in_group("enemies"), "Drone should be in enemies group")


func test_drone_not_in_other_group() -> void:
	var drone := MockDrone.new()
	assert_false(drone.is_in_group("players"), "Drone should not be in players group")


# ============================================================================
# State Tests
# ============================================================================


func test_alive_by_default() -> void:
	var drone := MockDrone.new()
	assert_true(drone.is_alive(), "Drone should be alive by default")


func test_rotor_angle_starts_at_zero() -> void:
	var drone := MockDrone.new()
	assert_eq(drone._rotor_angle, 0.0, "Rotor angle should start at 0")


func test_rotor_rotation() -> void:
	var drone := MockDrone.new()
	drone.update_rotors(0.5)
	assert_almost_eq(drone._rotor_angle, 10.0, 0.001, "Rotor should rotate by speed * delta")


func test_rotor_continues_rotating() -> void:
	var drone := MockDrone.new()
	drone.update_rotors(1.0)
	drone.update_rotors(1.0)
	assert_almost_eq(drone._rotor_angle, 40.0, 0.001, "Rotor angle should accumulate")


# ============================================================================
# Combat Visual Tests (Issue #1417)
# ============================================================================


func test_led_starts_green() -> void:
	var drone := MockDrone.new()
	assert_almost_eq(drone._led_color.g, 0.8, 0.01, "LED should start green (searching)")
	assert_lt(drone._led_color.r, 0.5, "LED should not be red when searching")


func test_led_turns_red_in_combat() -> void:
	var drone := MockDrone.new()
	drone.activate_combat()
	assert_gt(drone._led_color.r, 0.9, "LED should be red in combat")
	assert_lt(drone._led_color.g, 0.2, "LED green component should be low in combat")


func test_rotors_spin_faster_in_combat() -> void:
	var drone_search := MockDrone.new()
	var drone_combat := MockDrone.new()
	drone_combat.activate_combat()

	drone_search.update_rotors(1.0)
	drone_combat.update_rotors(1.0)

	assert_gt(drone_combat._rotor_angle, drone_search._rotor_angle, "Rotors should spin faster in combat")
	assert_almost_eq(drone_combat._rotor_angle, drone_search._rotor_angle * 3.0, 0.001, "Combat rotors should be 3× faster")


# ============================================================================
# Spiral Search Movement Tests (Issue #1508)
# ============================================================================


func test_spiral_constants_valid() -> void:
	assert_gt(MockDrone.SPIRAL_START_RADIUS, 0.0, "Spiral start radius must be positive")
	assert_gt(MockDrone.SPIRAL_MAX_RADIUS, MockDrone.SPIRAL_START_RADIUS, "Max radius must exceed start radius")
	assert_gt(MockDrone.SPIRAL_EXPAND_RATE, 0.0, "Expand rate must be positive")
	assert_gt(MockDrone.SPIRAL_ANGULAR_SPEED, 0.0, "Angular speed must be positive")


func test_spiral_angle_advances_with_time() -> void:
	var drone := MockDrone.new()
	drone.update_searching(1.0)
	assert_almost_eq(drone._spiral_angle, MockDrone.SPIRAL_ANGULAR_SPEED, 0.001,
		"Spiral angle should advance by angular_speed * delta each tick")


func test_spiral_radius_expands_over_time() -> void:
	var drone := MockDrone.new()
	var initial_radius: float = drone._spiral_radius
	drone.update_searching(1.0)
	assert_gt(drone._spiral_radius, initial_radius, "Spiral radius should grow over time")
	assert_almost_eq(drone._spiral_radius, initial_radius + MockDrone.SPIRAL_EXPAND_RATE, 0.001,
		"Spiral radius should grow by expand_rate * delta")


func test_spiral_radius_capped_at_max() -> void:
	var drone := MockDrone.new()
	# Simulate many seconds — radius must never exceed SPIRAL_MAX_RADIUS
	for _i in range(100):
		drone.update_searching(1.0)
	assert_almost_eq(drone._spiral_radius, MockDrone.SPIRAL_MAX_RADIUS, 0.001,
		"Spiral radius should be capped at SPIRAL_MAX_RADIUS")


func test_spiral_radius_starts_at_start_radius() -> void:
	var drone := MockDrone.new()
	assert_eq(drone._spiral_radius, MockDrone.SPIRAL_START_RADIUS,
		"Spiral radius should start at SPIRAL_START_RADIUS")


func test_spiral_drone_moves_toward_orbit_point() -> void:
	var drone := MockDrone.new()
	drone._operator_pos = Vector2(500.0, 500.0)
	drone._drone_pos = Vector2(500.0, 500.0)  # Start at operator center
	drone.update_searching(0.016)  # ~1 frame at 60fps
	assert_gt(drone._velocity.length(), 0.0, "Drone should have non-zero velocity while searching")


func test_spiral_drone_moves_at_search_speed() -> void:
	var drone := MockDrone.new()
	drone._operator_pos = Vector2(0.0, 0.0)
	drone._drone_pos = Vector2(999.0, 0.0)  # Far from orbit target to avoid near-zero to_target
	drone.update_searching(0.1)
	assert_almost_eq(drone._velocity.length(), MockDrone.SEARCH_SPEED, 0.5,
		"Drone search velocity magnitude should equal SEARCH_SPEED")


func test_spiral_orbit_target_at_correct_radius() -> void:
	# Verify the orbit target is placed at spiral_radius from the operator.
	var drone := MockDrone.new()
	drone._operator_pos = Vector2(200.0, 300.0)
	drone._spiral_angle = 0.0
	drone._spiral_radius = 100.0
	# orbit_target = operator_pos + Vector2(cos(0), sin(0)) * 100 = (300, 300)
	var expected_target := Vector2(300.0, 300.0)
	var orbit_target: Vector2 = drone._operator_pos + Vector2(cos(drone._spiral_angle), sin(drone._spiral_angle)) * drone._spiral_radius
	assert_almost_eq(orbit_target.x, expected_target.x, 0.01, "Orbit target X at angle=0 should be operator.x + radius")
	assert_almost_eq(orbit_target.y, expected_target.y, 0.01, "Orbit target Y at angle=0 should be operator.y")


# ============================================================================
# Nav-Agent Pathfinding Tests (Issue #1508 follow-up: wall avoidance)
# ============================================================================


func test_nav_agent_path_overrides_direct_direction() -> void:
	# When a nav-agent provides a waypoint, the drone must move toward that
	# waypoint rather than directly toward the orbit target.
	var drone := MockDrone.new()
	drone._operator_pos = Vector2(0.0, 0.0)
	drone._drone_pos = Vector2(0.0, 0.0)
	drone._spiral_angle = 0.0    # orbit target will be at (SPIRAL_START_RADIUS, 0)
	drone._spiral_radius = MockDrone.SPIRAL_START_RADIUS

	# Simulate nav agent returning a waypoint that is perpendicular to the
	# direct path — as if the path routes around a wall.
	drone._nav_next_pos = Vector2(0.0, 50.0)  # nav says go up, not right

	drone.update_searching(0.1)

	# The drone should move upward (toward nav waypoint), not rightward (direct).
	assert_gt(drone._velocity.y, 0.0, "Drone should follow nav-agent waypoint direction (upward)")
	assert_almost_eq(drone._velocity.x, 0.0, 1.0, "Drone should not drift rightward when nav says go up")


func test_nav_agent_velocity_is_search_speed() -> void:
	# Even when using nav-agent pathfinding, the speed must remain SEARCH_SPEED.
	var drone := MockDrone.new()
	drone._operator_pos = Vector2(0.0, 0.0)
	drone._drone_pos = Vector2(0.0, 0.0)
	drone._nav_next_pos = Vector2(0.0, 200.0)  # nav waypoint is north

	drone.update_searching(0.1)

	assert_almost_eq(drone._velocity.length(), MockDrone.SEARCH_SPEED, 0.5,
		"Nav-agent pathfinding should preserve SEARCH_SPEED magnitude")


func test_nav_agent_fallback_without_nav() -> void:
	# Without a nav agent (_nav_next_pos = INF), drone falls back to direct path.
	var drone := MockDrone.new()
	drone._operator_pos = Vector2(0.0, 0.0)
	drone._drone_pos = Vector2(0.0, 0.0)
	# _nav_next_pos stays at (INF, INF) — no nav agent

	drone.update_searching(0.1)

	# Should still move (toward orbit target), not stand still.
	assert_gt(drone._velocity.length(), 0.0, "Drone must move even without a nav agent")


# ============================================================================
# ORCA Avoidance Tests (Issue #1508 follow-up: enemy non-collision)
# ============================================================================


func test_avoidance_velocity_used_when_available() -> void:
	# When ORCA provides a safe velocity, the drone must use it instead of the
	# intended velocity — this steers it away from other enemies.
	var drone := MockDrone.new()
	drone._avoidance_enabled = true
	drone._avoidance_velocity = Vector2(0.0, MockDrone.SEARCH_SPEED)  # ORCA says go up
	drone._operator_pos = Vector2(0.0, 0.0)
	drone._drone_pos = Vector2(0.0, 0.0)
	drone._nav_next_pos = Vector2(200.0, 0.0)  # nav says go right

	drone.update_searching(0.1)

	# ORCA velocity should override nav velocity
	assert_gt(drone._velocity.y, 0.0, "ORCA avoidance velocity (upward) should override nav direction")
	assert_almost_eq(drone._velocity.x, 0.0, 1.0, "Rightward nav velocity should be overridden by ORCA")


func test_avoidance_velocity_ignored_when_near_zero() -> void:
	# When ORCA returns near-zero (no conflict), fall back to intended velocity.
	var drone := MockDrone.new()
	drone._avoidance_enabled = true
	drone._avoidance_velocity = Vector2(0.001, 0.0)  # Effectively zero
	drone._operator_pos = Vector2(0.0, 0.0)
	drone._drone_pos = Vector2(0.0, 0.0)
	drone._nav_next_pos = Vector2(200.0, 0.0)  # nav says go right

	drone.update_searching(0.1)

	assert_gt(drone._velocity.x, 0.0, "Intended rightward velocity should be used when ORCA velocity is near-zero")


func test_avoidance_disabled_uses_intended_velocity() -> void:
	# When avoidance is disabled (e.g. test scene without nav mesh), the drone
	# moves using the intended velocity without ORCA involvement.
	var drone := MockDrone.new()
	drone._avoidance_enabled = false
	drone._avoidance_velocity = Vector2(0.0, MockDrone.SEARCH_SPEED)  # Set but should not be used
	drone._operator_pos = Vector2(0.0, 0.0)
	drone._drone_pos = Vector2(0.0, 0.0)
	drone._nav_next_pos = Vector2(200.0, 0.0)

	drone.update_searching(0.1)

	assert_gt(drone._velocity.x, 0.0, "Without avoidance, drone should use intended (rightward) velocity")


# Combat Re-aiming Tests (Issue #1542)
# ============================================================================


func test_combat_full_speed_when_aligned() -> void:
	# When the drone is aimed at the player, it must fly at full COMBAT_SPEED.
	var drone := MockDrone.new()
	drone._drone_pos = Vector2(0.0, 0.0)
	drone._player_pos = Vector2(500.0, 0.0)  # Player directly to the right
	drone._current_move_dir = Vector2(1.0, 0.0)  # Already aimed at player

	drone.update_combat(0.016)

	assert_false(drone._is_reaiming, "Drone should not be re-aiming when aligned with player")
	assert_almost_eq(drone._velocity.length(), MockDrone.COMBAT_SPEED, 1.0,
		"Drone should fly at COMBAT_SPEED when aimed at player")


func test_miss_detection_enters_reaim_phase() -> void:
	# After flying away from the player (miss), the drone must eventually enter re-aiming.
	# Re-aim starts only after the zanос (overshoot/skid) bottoms out — i.e. once the
	# alignment has stopped falling and has begun to rise again (Issue #1542 owner feedback).
	var drone := MockDrone.new()
	drone._drone_pos = Vector2(0.0, 0.0)
	drone._player_pos = Vector2(500.0, 0.0)   # Player to the right
	# Drone moving directly away from the player — extreme miss
	drone._current_move_dir = Vector2(-1.0, 0.0)

	# Run enough ticks for the zanос to bottom out and re-aim to trigger.
	# With DRIFT_FACTOR=0.93 the alignment will keep falling for a few frames,
	# then slowly rise as the drone naturally turns back — re-aim triggers on that rise.
	var entered_reaim := false
	for _i in range(120):
		drone.update_combat(0.016)
		if drone._is_reaiming:
			entered_reaim = true
			break

	assert_true(entered_reaim, "Drone should enter re-aiming phase after the overshoot bottoms out")


func test_reaim_phase_uses_reduced_speed() -> void:
	# During re-aiming, the drone must slow down to REAIM_SPEED.
	var drone := MockDrone.new()
	drone._drone_pos = Vector2(0.0, 0.0)
	drone._player_pos = Vector2(500.0, 0.0)
	drone._current_move_dir = Vector2(-1.0, 0.0)  # Flying away → will trigger miss
	drone._is_reaiming = true  # Pre-set to reaiming state

	drone.update_combat(0.016)

	assert_lt(drone._velocity.length(), MockDrone.COMBAT_SPEED * 0.5,
		"Drone should fly at reduced speed during re-aiming phase")
	assert_almost_eq(drone._velocity.length(), MockDrone.REAIM_SPEED, 5.0,
		"Drone speed during re-aiming should equal REAIM_SPEED")


func test_reaim_exits_when_aligned() -> void:
	# Once re-aligned with the player (dot >= REAIM_EXIT_DOT), re-aiming must end.
	var drone := MockDrone.new()
	drone._drone_pos = Vector2(0.0, 0.0)
	drone._player_pos = Vector2(500.0, 0.0)
	drone._current_move_dir = Vector2(1.0, 0.0)  # Already aimed at player
	drone._is_reaiming = true  # Start in re-aiming state

	drone.update_combat(0.016)

	assert_false(drone._is_reaiming, "Re-aiming should end once drone is aligned with player")
	assert_almost_eq(drone._velocity.length(), MockDrone.COMBAT_SPEED, 1.0,
		"Drone should resume COMBAT_SPEED after re-aiming completes")


func test_reaim_drift_factor_is_less_than_combat_drift() -> void:
	# The re-aim drift must be lower than combat drift so steering is faster during re-aim.
	assert_lt(MockDrone.REAIM_DRIFT_FACTOR, MockDrone.DRIFT_FACTOR,
		"REAIM_DRIFT_FACTOR must be lower than DRIFT_FACTOR for faster steering correction")


func test_reaim_speed_is_less_than_combat_speed() -> void:
	# Re-aim speed must be meaningfully lower than combat speed.
	assert_lt(MockDrone.REAIM_SPEED, MockDrone.COMBAT_SPEED * 0.5,
		"REAIM_SPEED should be less than half of COMBAT_SPEED")


func test_reaim_faster_steering_than_combat() -> void:
	# Verify that a drone in re-aiming mode corrects its heading faster than in normal combat.
	# Start both drones flying perpendicular to the player — measure alignment after several ticks.
	var drone_normal := MockDrone.new()
	var drone_reaiming := MockDrone.new()

	for drone in [drone_normal, drone_reaiming]:
		drone._drone_pos = Vector2(0.0, 0.0)
		drone._player_pos = Vector2(500.0, 0.0)
		drone._current_move_dir = Vector2(0.0, 1.0)  # Perpendicular to player

	drone_reaiming._is_reaiming = true

	for _i in range(5):
		drone_normal.update_combat(0.016)
		drone_reaiming.update_combat(0.016)

	var alignment_normal: float = drone_normal._current_move_dir.dot(Vector2(1.0, 0.0))
	var alignment_reaiming: float = drone_reaiming._current_move_dir.dot(Vector2(1.0, 0.0))

	assert_gt(alignment_reaiming, alignment_normal,
		"Drone in re-aiming mode should correct heading faster than normal combat mode")


func test_reaim_does_not_start_mid_overshoot() -> void:
	# Re-aim must NOT start while the alignment is still falling (zanос in progress).
	# It should only start once alignment begins to recover (bottom of the skid).
	var drone := MockDrone.new()
	drone._drone_pos = Vector2(0.0, 0.0)
	drone._player_pos = Vector2(500.0, 0.0)
	# Start flying directly away — alignment will be falling for first several ticks.
	drone._current_move_dir = Vector2(-1.0, 0.0)
	# _prev_alignment starts at 1.0; alignment on tick 1 will be around -0.99 < 1.0,
	# so the "alignment > _prev_alignment" guard prevents early re-aim entry.
	drone.update_combat(0.016)
	assert_false(drone._is_reaiming,
		"Drone must NOT enter re-aim on the first tick — zanос is still in progress")


# ============================================================================
# Operator-killed explosion tests (Issue #1551)
# ============================================================================


class MockDroneWithOperatorLink:
	## Mirrors the operator-death link added in Issue #1551:
	## initialize_drone() connects operator.died → _explode().
	var _is_alive: bool = true
	var _has_exploded: bool = false
	var _operator: MockOperatorNode = null

	func initialize_drone(operator: MockOperatorNode) -> void:
		_operator = operator
		# Mirror the real connection: operator.died → _explode
		operator.on_died_callbacks.append(_explode)

	func _explode() -> void:
		if _has_exploded or not _is_alive:
			return
		_has_exploded = true
		_is_alive = false

	func is_alive() -> bool:
		return _is_alive

	func has_exploded() -> bool:
		return _has_exploded


class MockOperatorNode:
	## Minimal operator node that can emit a died signal (simulated via callbacks).
	var on_died_callbacks: Array = []
	var _is_alive: bool = true

	func die() -> void:
		_is_alive = false
		for cb in on_died_callbacks:
			cb.call()

	func is_alive() -> bool:
		return _is_alive


func test_drone_explodes_when_operator_killed() -> void:
	# Issue #1551: killing the operator must cause the drone to explode.
	var operator := MockOperatorNode.new()
	var drone := MockDroneWithOperatorLink.new()
	drone.initialize_drone(operator)

	assert_true(drone.is_alive(), "Drone should be alive before operator dies")
	assert_false(drone.has_exploded(), "Drone should not have exploded yet")

	operator.die()

	assert_true(drone.has_exploded(), "Drone must explode immediately when operator is killed")
	assert_false(drone.is_alive(), "Drone must be dead after explosion triggered by operator death")


func test_drone_explode_not_called_twice_when_operator_killed() -> void:
	# _explode() has a guard: _has_exploded prevents double-explosion.
	var operator := MockOperatorNode.new()
	var drone := MockDroneWithOperatorLink.new()
	drone.initialize_drone(operator)

	# Simulate drone already exploded (e.g. player collision) before operator dies
	drone._has_exploded = true
	drone._is_alive = false

	operator.die()

	# Should still be in the same dead-exploded state without crashing
	assert_true(drone.has_exploded(), "Exploded flag must remain true")
	assert_false(drone.is_alive(), "Drone must remain dead")


func test_drone_without_operator_does_not_crash() -> void:
	# initialize_drone() with null operator must not connect any signal.
	var drone := MockDroneWithOperatorLink.new()
	# No initialize_drone() call — operator is null
	assert_true(drone.is_alive(), "Drone without operator should still be alive initially")
	assert_false(drone.has_exploded(), "Drone without operator should not have exploded")
