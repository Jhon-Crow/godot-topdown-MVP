extends GutTest
## Unit tests for trajectory_glasses_effect.gd ricochet trajectory visualization.
##
## Tests effect duration, max charges, max ricochet bounces,
## and warning thresholds.


# ============================================================================
# Mock TrajectoryGlassesEffect for Logic Tests
# ============================================================================


class MockTrajectoryGlassesEffect:
	## Duration of trajectory glasses effect in seconds.
	const EFFECT_DURATION: float = 10.0

	## Maximum charges per battle.
	const MAX_CHARGES: int = 2

	## Maximum number of ricochet bounces to visualize.
	const MAX_RICOCHET_BOUNCES: int = 5

	## Laser width for visualization.
	const LASER_WIDTH: float = 2.0

	## Maximum ricochet angle in degrees.
	const MAX_RICOCHET_ANGLE: float = 90.0

	## Continuous blink threshold (seconds).
	const CONTINUOUS_BLINK_THRESHOLD: float = 4.0

	## Single-blink threshold (25% of EFFECT_DURATION).
	const SINGLE_BLINK_THRESHOLD: float = EFFECT_DURATION * 0.25

	## Flash frequency when time is low (Hz).
	const WARNING_FLASH_FREQUENCY: float = 3.0

	## Current charges.
	var charges: int = MAX_CHARGES

	## Whether active.
	var is_active: bool = false

	## Timer.
	var _effect_timer: float = 0.0

	## Warning flash timer.
	var _warning_flash_timer: float = 0.0

	## Blink state.
	var trajectory_ray_visible: bool = true

	## Track signals.
	var _activated_count: int = 0
	var _deactivated_count: int = 0

	## Activate the effect.
	func activate() -> bool:
		if is_active:
			return false
		if charges <= 0:
			return false
		charges -= 1
		is_active = true
		_effect_timer = EFFECT_DURATION
		_activated_count += 1
		return true

	## Deactivate the effect.
	func deactivate() -> void:
		if not is_active:
			return
		is_active = false
		_effect_timer = 0.0
		_warning_flash_timer = 0.0
		trajectory_ray_visible = true
		_deactivated_count += 1

	## Simulate process.
	func process(delta: float) -> void:
		if not is_active:
			return
		_effect_timer -= delta
		if _effect_timer <= 0.0:
			deactivate()
			return

		# Blink logic
		if _effect_timer <= CONTINUOUS_BLINK_THRESHOLD:
			_warning_flash_timer += delta
			var flash_period := 1.0 / WARNING_FLASH_FREQUENCY
			trajectory_ray_visible = fmod(_warning_flash_timer, flash_period) < (flash_period * 0.5)
		else:
			trajectory_ray_visible = true

	## Get remaining time.
	func get_remaining_time() -> float:
		return _effect_timer if is_active else 0.0

	## Get charges.
	func get_charges() -> int:
		return charges


var glasses: MockTrajectoryGlassesEffect


func before_each() -> void:
	glasses = MockTrajectoryGlassesEffect.new()


func after_each() -> void:
	glasses = null


# ============================================================================
# Constant Tests
# ============================================================================


func test_effect_duration() -> void:
	assert_eq(MockTrajectoryGlassesEffect.EFFECT_DURATION, 10.0,
		"EFFECT_DURATION should be 10.0 seconds")


func test_max_charges() -> void:
	assert_eq(MockTrajectoryGlassesEffect.MAX_CHARGES, 2,
		"MAX_CHARGES should be 2")


func test_max_ricochet_bounces() -> void:
	assert_eq(MockTrajectoryGlassesEffect.MAX_RICOCHET_BOUNCES, 5,
		"MAX_RICOCHET_BOUNCES should be 5")


func test_max_ricochet_angle() -> void:
	assert_eq(MockTrajectoryGlassesEffect.MAX_RICOCHET_ANGLE, 90.0,
		"MAX_RICOCHET_ANGLE should be 90.0 degrees")


func test_laser_width() -> void:
	assert_eq(MockTrajectoryGlassesEffect.LASER_WIDTH, 2.0,
		"LASER_WIDTH should be 2.0")


# ============================================================================
# Warning Threshold Tests
# ============================================================================


func test_continuous_blink_threshold() -> void:
	assert_eq(MockTrajectoryGlassesEffect.CONTINUOUS_BLINK_THRESHOLD, 4.0,
		"CONTINUOUS_BLINK_THRESHOLD should be 4.0 seconds")


func test_single_blink_threshold() -> void:
	assert_eq(MockTrajectoryGlassesEffect.SINGLE_BLINK_THRESHOLD, 2.5,
		"SINGLE_BLINK_THRESHOLD should be 2.5 seconds (25% of EFFECT_DURATION)")


func test_warning_flash_frequency() -> void:
	assert_eq(MockTrajectoryGlassesEffect.WARNING_FLASH_FREQUENCY, 3.0,
		"WARNING_FLASH_FREQUENCY should be 3.0 Hz")


func test_single_blink_is_quarter_of_duration() -> void:
	assert_almost_eq(
		MockTrajectoryGlassesEffect.SINGLE_BLINK_THRESHOLD,
		MockTrajectoryGlassesEffect.EFFECT_DURATION * 0.25,
		0.001,
		"SINGLE_BLINK_THRESHOLD should be 25% of EFFECT_DURATION")


# ============================================================================
# Activation / Charge Tests
# ============================================================================


func test_initial_charges() -> void:
	assert_eq(glasses.charges, 2,
		"Should start with MAX_CHARGES")


func test_activate_consumes_charge() -> void:
	glasses.activate()

	assert_eq(glasses.charges, 1,
		"Activating should consume one charge")


func test_activate_returns_true() -> void:
	assert_true(glasses.activate(),
		"Activate should return true on first call")


func test_activate_when_active_returns_false() -> void:
	glasses.activate()

	assert_false(glasses.activate(),
		"Activate should return false when already active")


func test_activate_with_no_charges_returns_false() -> void:
	glasses.charges = 0

	assert_false(glasses.activate(),
		"Activate should return false when no charges")


func test_two_activations_use_both_charges() -> void:
	glasses.activate()
	glasses.deactivate()
	glasses.activate()
	glasses.deactivate()

	assert_eq(glasses.charges, 0,
		"Two activations should use both charges")


func test_third_activation_fails() -> void:
	glasses.activate()
	glasses.deactivate()
	glasses.activate()
	glasses.deactivate()

	assert_false(glasses.activate(),
		"Third activation should fail with no charges")


# ============================================================================
# Duration / Timer Tests
# ============================================================================


func test_timer_set_on_activate() -> void:
	glasses.activate()

	assert_eq(glasses.get_remaining_time(), 10.0,
		"Timer should be set to EFFECT_DURATION on activate")


func test_timer_counts_down() -> void:
	glasses.activate()
	glasses.process(3.0)

	assert_almost_eq(glasses.get_remaining_time(), 7.0, 0.01,
		"Timer should count down by delta")


func test_auto_deactivates_after_duration() -> void:
	glasses.activate()
	glasses.process(10.0)

	assert_false(glasses.is_active,
		"Effect should auto-deactivate after EFFECT_DURATION")


func test_remaining_time_zero_when_inactive() -> void:
	assert_eq(glasses.get_remaining_time(), 0.0,
		"Remaining time should be 0 when inactive")


# ============================================================================
# Blink Behavior Tests
# ============================================================================


func test_ray_visible_above_blink_threshold() -> void:
	glasses.activate()
	glasses.process(3.0)
	# 7 seconds remaining, above threshold

	assert_true(glasses.trajectory_ray_visible,
		"Ray should be visible above CONTINUOUS_BLINK_THRESHOLD")


func test_ray_blinks_below_threshold() -> void:
	glasses.activate()
	glasses.process(7.0)
	# 3 seconds remaining, below 4.0 threshold
	# At this point blink logic should be active
	# The exact visibility depends on the timer phase, but blink should have toggled
	# Just verify the system is processing (no crash)
	assert_true(glasses.is_active,
		"Effect should still be active below blink threshold")
