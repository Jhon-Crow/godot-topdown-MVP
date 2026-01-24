extends GutTest
## Unit tests for VisionComponent.
##
## Tests the vision and line-of-sight detection functionality including
## range checking, detection delay, visibility ratio calculation, and
## lead prediction timing.


# ============================================================================
# Mock VisionComponent for Logic Tests
# ============================================================================


class MockVisionComponent:
	## Detection range for spotting targets.
	## Set to 0 or negative for unlimited range (line-of-sight only).
	var detection_range: float = 0.0

	## Delay before reacting to newly visible targets (seconds).
	var detection_delay: float = 0.2

	## Delay before enabling lead prediction on visible targets (seconds).
	var lead_prediction_delay: float = 0.3

	## Minimum visibility ratio required for lead prediction.
	var lead_prediction_visibility_threshold: float = 0.6

	## Parent position (simulated).
	var _parent_position: Vector2 = Vector2.ZERO

	## Target position (simulated).
	var _target_position: Vector2 = Vector2.ZERO

	## Whether the target is currently visible (for testing).
	var _can_see_target: bool = false

	## Detection delay timer.
	var _detection_timer: float = 0.0

	## Whether detection delay has elapsed.
	var _detection_delay_elapsed: bool = false

	## Continuous visibility timer.
	var _continuous_visibility_timer: float = 0.0

	## Current visibility ratio of target (0.0 to 1.0).
	var _target_visibility_ratio: float = 0.0

	## Signals emitted (for testing).
	var visibility_changed_emitted: Array = []
	var target_detected_emitted: int = 0

	## Set parent position for distance calculations.
	func set_parent_position(pos: Vector2) -> void:
		_parent_position = pos

	## Set target position for distance calculations.
	func set_target_position(pos: Vector2) -> void:
		_target_position = pos

	## Simulate setting visibility (would normally come from raycast).
	func set_line_of_sight_clear(value: bool) -> void:
		var was_visible := _can_see_target

		# Check range if set
		if detection_range > 0.0:
			var distance := _parent_position.distance_to(_target_position)
			if distance > detection_range:
				_can_see_target = false
				if was_visible:
					visibility_changed_emitted.append(false)
					_reset_detection_timers()
				return

		_can_see_target = value

		if _can_see_target:
			if not was_visible:
				visibility_changed_emitted.append(true)
		else:
			if was_visible:
				visibility_changed_emitted.append(false)
			_reset_detection_timers()

	## Update detection timer (call from _physics_process).
	func update_detection(delta: float) -> void:
		if _can_see_target:
			_continuous_visibility_timer += delta

			if not _detection_delay_elapsed:
				_detection_timer += delta
				if _detection_timer >= detection_delay:
					_detection_delay_elapsed = true
					target_detected_emitted += 1

	## Reset detection timers.
	func _reset_detection_timers() -> void:
		_detection_timer = 0.0
		_detection_delay_elapsed = false
		_continuous_visibility_timer = 0.0
		_target_visibility_ratio = 0.0

	## Set the visibility ratio (would normally come from multiple raycasts).
	func set_visibility_ratio(ratio: float) -> void:
		_target_visibility_ratio = clampf(ratio, 0.0, 1.0)

	## Check if target is currently visible.
	func can_see_target() -> bool:
		return _can_see_target

	## Check if detection delay has elapsed.
	func is_detection_confirmed() -> bool:
		return _detection_delay_elapsed

	## Check if lead prediction should be enabled.
	func should_enable_lead_prediction() -> bool:
		return _continuous_visibility_timer >= lead_prediction_delay and \
			   _target_visibility_ratio >= lead_prediction_visibility_threshold

	## Get the current visibility ratio.
	func get_visibility_ratio() -> float:
		return _target_visibility_ratio

	## Get the continuous visibility time.
	func get_continuous_visibility_time() -> float:
		return _continuous_visibility_timer


var vision: MockVisionComponent


func before_each() -> void:
	vision = MockVisionComponent.new()


func after_each() -> void:
	vision = null


# ============================================================================
# Default Configuration Tests
# ============================================================================


func test_default_detection_range_is_unlimited() -> void:
	assert_eq(vision.detection_range, 0.0,
		"Default detection range should be 0 (unlimited)")


func test_default_detection_delay() -> void:
	assert_eq(vision.detection_delay, 0.2,
		"Default detection delay should be 0.2 seconds")


func test_default_lead_prediction_delay() -> void:
	assert_eq(vision.lead_prediction_delay, 0.3,
		"Default lead prediction delay should be 0.3 seconds")


func test_default_lead_prediction_threshold() -> void:
	assert_eq(vision.lead_prediction_visibility_threshold, 0.6,
		"Default lead prediction visibility threshold should be 0.6")


# ============================================================================
# Initial State Tests
# ============================================================================


func test_cannot_see_target_initially() -> void:
	assert_false(vision.can_see_target(),
		"Should not see target initially")


func test_detection_not_confirmed_initially() -> void:
	assert_false(vision.is_detection_confirmed(),
		"Detection should not be confirmed initially")


func test_visibility_ratio_zero_initially() -> void:
	assert_eq(vision.get_visibility_ratio(), 0.0,
		"Visibility ratio should be 0 initially")


func test_continuous_visibility_time_zero_initially() -> void:
	assert_eq(vision.get_continuous_visibility_time(), 0.0,
		"Continuous visibility time should be 0 initially")


# ============================================================================
# Visibility Tests
# ============================================================================


func test_can_see_target_when_line_of_sight_clear() -> void:
	vision.set_line_of_sight_clear(true)

	assert_true(vision.can_see_target())


func test_cannot_see_target_when_line_of_sight_blocked() -> void:
	vision.set_line_of_sight_clear(true)
	vision.set_line_of_sight_clear(false)

	assert_false(vision.can_see_target())


func test_visibility_change_emits_signal_when_becoming_visible() -> void:
	vision.set_line_of_sight_clear(true)

	assert_eq(vision.visibility_changed_emitted.size(), 1)
	assert_true(vision.visibility_changed_emitted[0])


func test_visibility_change_emits_signal_when_losing_visibility() -> void:
	vision.set_line_of_sight_clear(true)
	vision.set_line_of_sight_clear(false)

	assert_eq(vision.visibility_changed_emitted.size(), 2)
	assert_false(vision.visibility_changed_emitted[1])


func test_no_signal_when_visibility_unchanged() -> void:
	vision.set_line_of_sight_clear(true)
	vision.set_line_of_sight_clear(true)

	assert_eq(vision.visibility_changed_emitted.size(), 1,
		"Should not emit signal when visibility unchanged")


# ============================================================================
# Range Tests
# ============================================================================


func test_target_visible_within_range() -> void:
	vision.detection_range = 100.0
	vision.set_parent_position(Vector2.ZERO)
	vision.set_target_position(Vector2(50, 0))
	vision.set_line_of_sight_clear(true)

	assert_true(vision.can_see_target())


func test_target_not_visible_outside_range() -> void:
	vision.detection_range = 100.0
	vision.set_parent_position(Vector2.ZERO)
	vision.set_target_position(Vector2(150, 0))
	vision.set_line_of_sight_clear(true)

	assert_false(vision.can_see_target())


func test_target_visible_at_exact_range() -> void:
	vision.detection_range = 100.0
	vision.set_parent_position(Vector2.ZERO)
	vision.set_target_position(Vector2(100, 0))
	vision.set_line_of_sight_clear(true)

	assert_true(vision.can_see_target())


func test_unlimited_range_when_zero() -> void:
	vision.detection_range = 0.0
	vision.set_parent_position(Vector2.ZERO)
	vision.set_target_position(Vector2(99999, 0))
	vision.set_line_of_sight_clear(true)

	assert_true(vision.can_see_target(),
		"Should see target at any distance with unlimited range")


func test_unlimited_range_when_negative() -> void:
	vision.detection_range = -1.0
	vision.set_parent_position(Vector2.ZERO)
	vision.set_target_position(Vector2(99999, 0))

	# With negative range, the check > 0 fails, so range is ignored
	vision.set_line_of_sight_clear(true)

	assert_true(vision.can_see_target(),
		"Negative range should also mean unlimited")


# ============================================================================
# Detection Delay Tests
# ============================================================================


func test_detection_not_confirmed_before_delay() -> void:
	vision.set_line_of_sight_clear(true)
	vision.update_detection(0.1)  # Less than 0.2

	assert_false(vision.is_detection_confirmed())


func test_detection_confirmed_after_delay() -> void:
	vision.set_line_of_sight_clear(true)
	vision.update_detection(0.25)

	assert_true(vision.is_detection_confirmed())


func test_detection_confirmed_emits_signal() -> void:
	vision.set_line_of_sight_clear(true)
	vision.update_detection(0.25)

	assert_eq(vision.target_detected_emitted, 1)


func test_detection_signal_emitted_only_once() -> void:
	vision.set_line_of_sight_clear(true)
	vision.update_detection(0.25)
	vision.update_detection(0.5)

	assert_eq(vision.target_detected_emitted, 1,
		"Detection signal should only emit once")


func test_detection_timer_accumulates() -> void:
	vision.set_line_of_sight_clear(true)
	vision.update_detection(0.05)
	vision.update_detection(0.05)
	vision.update_detection(0.05)
	vision.update_detection(0.05)  # Total: 0.2

	assert_true(vision.is_detection_confirmed())


func test_detection_timer_resets_when_losing_visibility() -> void:
	vision.set_line_of_sight_clear(true)
	vision.update_detection(0.15)  # Almost there
	vision.set_line_of_sight_clear(false)
	vision.set_line_of_sight_clear(true)
	vision.update_detection(0.1)

	assert_false(vision.is_detection_confirmed(),
		"Detection timer should reset after losing visibility")


func test_custom_detection_delay() -> void:
	vision.detection_delay = 1.0
	vision.set_line_of_sight_clear(true)
	vision.update_detection(0.5)

	assert_false(vision.is_detection_confirmed())

	vision.update_detection(0.6)

	assert_true(vision.is_detection_confirmed())


# ============================================================================
# Continuous Visibility Timer Tests
# ============================================================================


func test_continuous_visibility_timer_increases() -> void:
	vision.set_line_of_sight_clear(true)
	vision.update_detection(0.5)

	assert_eq(vision.get_continuous_visibility_time(), 0.5)


func test_continuous_visibility_timer_resets_on_visibility_loss() -> void:
	vision.set_line_of_sight_clear(true)
	vision.update_detection(0.5)
	vision.set_line_of_sight_clear(false)

	assert_eq(vision.get_continuous_visibility_time(), 0.0)


func test_continuous_visibility_timer_not_updated_when_not_visible() -> void:
	vision.update_detection(0.5)

	assert_eq(vision.get_continuous_visibility_time(), 0.0,
		"Timer should not increase when target not visible")


# ============================================================================
# Lead Prediction Tests
# ============================================================================


func test_lead_prediction_disabled_initially() -> void:
	assert_false(vision.should_enable_lead_prediction())


func test_lead_prediction_disabled_without_enough_time() -> void:
	vision.set_line_of_sight_clear(true)
	vision.set_visibility_ratio(0.8)
	vision.update_detection(0.2)  # Less than 0.3

	assert_false(vision.should_enable_lead_prediction())


func test_lead_prediction_disabled_without_enough_visibility() -> void:
	vision.set_line_of_sight_clear(true)
	vision.set_visibility_ratio(0.4)  # Less than 0.6
	vision.update_detection(0.5)

	assert_false(vision.should_enable_lead_prediction())


func test_lead_prediction_enabled_with_enough_time_and_visibility() -> void:
	vision.set_line_of_sight_clear(true)
	vision.set_visibility_ratio(0.8)
	vision.update_detection(0.5)

	assert_true(vision.should_enable_lead_prediction())


func test_lead_prediction_at_exact_thresholds() -> void:
	vision.set_line_of_sight_clear(true)
	vision.set_visibility_ratio(0.6)
	vision.update_detection(0.3)

	assert_true(vision.should_enable_lead_prediction(),
		"Should enable at exactly the threshold values")


func test_custom_lead_prediction_thresholds() -> void:
	vision.lead_prediction_delay = 1.0
	vision.lead_prediction_visibility_threshold = 0.9
	vision.set_line_of_sight_clear(true)
	vision.set_visibility_ratio(0.85)
	vision.update_detection(0.8)

	assert_false(vision.should_enable_lead_prediction())

	vision.set_visibility_ratio(0.95)
	vision.update_detection(0.3)  # Total: 1.1

	assert_true(vision.should_enable_lead_prediction())


# ============================================================================
# Visibility Ratio Tests
# ============================================================================


func test_visibility_ratio_clamped_to_max() -> void:
	vision.set_visibility_ratio(1.5)

	assert_eq(vision.get_visibility_ratio(), 1.0)


func test_visibility_ratio_clamped_to_min() -> void:
	vision.set_visibility_ratio(-0.5)

	assert_eq(vision.get_visibility_ratio(), 0.0)


func test_visibility_ratio_set_correctly() -> void:
	vision.set_visibility_ratio(0.75)

	assert_eq(vision.get_visibility_ratio(), 0.75)


func test_visibility_ratio_resets_on_visibility_loss() -> void:
	vision.set_line_of_sight_clear(true)
	vision.set_visibility_ratio(0.8)
	vision.set_line_of_sight_clear(false)

	assert_eq(vision.get_visibility_ratio(), 0.0)


# ============================================================================
# Edge Cases Tests
# ============================================================================


func test_zero_delta_update() -> void:
	vision.set_line_of_sight_clear(true)
	vision.update_detection(0.0)

	assert_eq(vision.get_continuous_visibility_time(), 0.0)
	assert_false(vision.is_detection_confirmed())


func test_very_large_delta_update() -> void:
	vision.set_line_of_sight_clear(true)
	vision.update_detection(100.0)

	assert_true(vision.is_detection_confirmed())
	assert_true(vision.get_continuous_visibility_time() >= 100.0)


func test_rapid_visibility_toggling() -> void:
	for _i in range(10):
		vision.set_line_of_sight_clear(true)
		vision.update_detection(0.05)
		vision.set_line_of_sight_clear(false)

	assert_false(vision.is_detection_confirmed(),
		"Rapid toggling should reset timers each time")


func test_parent_and_target_at_same_position() -> void:
	vision.detection_range = 100.0
	vision.set_parent_position(Vector2(50, 50))
	vision.set_target_position(Vector2(50, 50))
	vision.set_line_of_sight_clear(true)

	assert_true(vision.can_see_target(),
		"Should see target at same position (distance 0)")
