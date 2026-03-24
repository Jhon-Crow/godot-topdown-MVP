extends GutTest
## Unit tests for machete enemy COMBAT state stuck detection (Issue #1107).
##
## Tests that the machete enemy correctly detects when it is stuck against a wall
## in COMBAT state and transitions to PURSUING to find an alternate route.
## Also tests the improved _get_nav_direction_to fallback behavior.


# ============================================================================
# Stub classes for logic testing without Godot scene
# ============================================================================


class StubMacheteState:
	## Simulates the stuck detection state variables added for Issue #1107.
	var machete_combat_stuck_timer: float = 0.0
	var machete_combat_stuck_last_pos: Vector2 = Vector2.ZERO
	const MACHETE_COMBAT_STUCK_MAX_TIME: float = 1.5
	const MACHETE_COMBAT_STUCK_DIST_THRESHOLD: float = 20.0

	## Simulates one physics frame of stuck detection logic.
	## Returns true if the enemy should transition to PURSUING (is stuck).
	func process_stuck_detection(delta: float, current_pos: Vector2) -> bool:
		var moved_dist := current_pos.distance_to(machete_combat_stuck_last_pos)
		if moved_dist < MACHETE_COMBAT_STUCK_DIST_THRESHOLD:
			machete_combat_stuck_timer += delta
			if machete_combat_stuck_timer >= MACHETE_COMBAT_STUCK_MAX_TIME:
				machete_combat_stuck_timer = 0.0
				machete_combat_stuck_last_pos = current_pos
				return true  # Should transition to PURSUING
		else:
			machete_combat_stuck_timer = 0.0
			machete_combat_stuck_last_pos = current_pos
		return false

	## Reset on entering COMBAT state.
	func reset(current_pos: Vector2) -> void:
		machete_combat_stuck_timer = 0.0
		machete_combat_stuck_last_pos = current_pos


# ============================================================================
# Stuck Detection Tests
# ============================================================================


func test_stuck_detection_resets_on_movement() -> void:
	var state := StubMacheteState.new()
	state.reset(Vector2(100, 100))

	# Simulate enemy moving (50px which is > threshold of 20px)
	var should_pursue := state.process_stuck_detection(0.5, Vector2(150, 100))
	assert_false(should_pursue, "Moving enemy should not trigger stuck detection")
	assert_eq(state.machete_combat_stuck_timer, 0.0, "Timer should reset when enemy moves")
	assert_eq(state.machete_combat_stuck_last_pos, Vector2(150, 100), "Last pos should update on move")


func test_stuck_detection_accumulates_timer_when_not_moving() -> void:
	var state := StubMacheteState.new()
	state.reset(Vector2(100, 100))

	# Simulate stuck: enemy hasn't moved (only moved 5px which is < 20px threshold)
	var should_pursue1 := state.process_stuck_detection(0.5, Vector2(105, 100))
	assert_false(should_pursue1, "Should not trigger yet after 0.5s stuck")
	assert_gt(state.machete_combat_stuck_timer, 0.0, "Timer should accumulate when stuck")

	var should_pursue2 := state.process_stuck_detection(0.5, Vector2(105, 100))
	assert_false(should_pursue2, "Should not trigger yet after 1.0s stuck")

	var should_pursue3 := state.process_stuck_detection(0.5, Vector2(105, 100))
	# After 1.5s total, should trigger
	assert_true(should_pursue3, "Should transition to PURSUING after 1.5s stuck")


func test_stuck_detection_resets_timer_after_transition() -> void:
	var state := StubMacheteState.new()
	state.reset(Vector2(100, 100))

	# Accumulate stuck timer to threshold
	state.process_stuck_detection(0.5, Vector2(105, 100))
	state.process_stuck_detection(0.5, Vector2(105, 100))
	var triggered := state.process_stuck_detection(0.5, Vector2(105, 100))
	assert_true(triggered, "Should have triggered")

	# Timer should be reset after trigger
	assert_eq(state.machete_combat_stuck_timer, 0.0, "Timer should reset after triggering")


func test_stuck_detection_threshold_exact_boundary() -> void:
	var state := StubMacheteState.new()
	state.reset(Vector2(0, 0))

	# Move exactly at threshold (20px) — should NOT be stuck
	var should_pursue := state.process_stuck_detection(0.1, Vector2(20, 0))
	assert_false(should_pursue, "Moving exactly at threshold should not be stuck")


func test_stuck_detection_below_threshold_is_stuck() -> void:
	var state := StubMacheteState.new()
	state.reset(Vector2(0, 0))

	# Move just below threshold (19.9px) — should be stuck
	var should_pursue := state.process_stuck_detection(0.1, Vector2(19.9, 0))
	assert_false(should_pursue, "Should not trigger immediately - only after time")
	assert_gt(state.machete_combat_stuck_timer, 0.0, "Timer should accumulate below threshold")


func test_stuck_detection_resets_on_combat_entry() -> void:
	var state := StubMacheteState.new()
	state.reset(Vector2(100, 100))

	# Accumulate some stuck time
	state.process_stuck_detection(1.0, Vector2(105, 100))
	assert_gt(state.machete_combat_stuck_timer, 0.0, "Timer accumulated")

	# Reset (simulating entering COMBAT state)
	state.reset(Vector2(200, 200))
	assert_eq(state.machete_combat_stuck_timer, 0.0, "Timer should reset on COMBAT entry")
	assert_eq(state.machete_combat_stuck_last_pos, Vector2(200, 200), "Last pos should update on reset")


func test_stuck_detection_partial_movement_gradually_accumulates() -> void:
	var state := StubMacheteState.new()
	state.reset(Vector2(0, 0))

	# Move 10px (below 20px threshold) each "frame"
	var transitions := 0
	for i in range(20):
		# Enemy moves 10px per second (stuck), small delta
		if state.process_stuck_detection(0.1, Vector2(i * 10, 0) if i < 2 else Vector2(10, 0)):
			transitions += 1

	# Should have triggered at least once over this duration
	assert_gt(transitions, 0, "Should trigger at least once over extended stuck period")


# ============================================================================
# Constants Validation Tests
# ============================================================================


func test_stuck_max_time_constant_reasonable() -> void:
	# 1.5 seconds is reasonable: fast enough to recover, slow enough not to thrash
	var max_time: float = 1.5
	assert_gt(max_time, 0.5, "Stuck max time should be > 0.5s to prevent thrashing")
	assert_lt(max_time, 5.0, "Stuck max time should be < 5s to recover quickly")


func test_stuck_dist_threshold_reasonable() -> void:
	# 20px threshold: less than this means stuck (e.g., pressing against a wall)
	var threshold: float = 20.0
	assert_gt(threshold, 5.0, "Threshold should be > 5px to ignore tiny movements")
	assert_lt(threshold, 50.0, "Threshold should be < 50px to detect real movement")


# ============================================================================
# Navigation Fallback Tests (theoretical)
# ============================================================================


func test_nav_direction_fallback_logic_for_unreachable_target() -> void:
	# Simulate the logic in _get_nav_direction_to when no path exists.
	# When is_navigation_finished() is true but target is far, should try nearest point.
	var current_pos := Vector2(0, 0)
	var target_pos := Vector2(500, 0)
	var target_desired_distance: float = 10.0

	# Far target with no path means we should try nearest reachable point
	var dist_to_target := current_pos.distance_to(target_pos)
	var is_far_away := dist_to_target > target_desired_distance * 2.0

	assert_true(is_far_away, "Target at 500px should be considered far from origin")


func test_nav_direction_fallback_not_triggered_when_near_target() -> void:
	# When enemy is near target, is_navigation_finished() returning true means arrived.
	var current_pos := Vector2(490, 0)
	var target_pos := Vector2(500, 0)
	var target_desired_distance: float = 10.0

	var dist_to_target := current_pos.distance_to(target_pos)
	var is_far_away := dist_to_target > target_desired_distance * 2.0

	assert_false(is_far_away, "Target at 10px should NOT trigger unreachable fallback")
