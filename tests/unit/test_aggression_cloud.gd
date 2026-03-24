extends GutTest
## Unit tests for aggression_cloud.gd reddish gas cloud effect.
##
## Tests cloud configuration, aggression effect duration,
## tick interval timing, time remaining countdown, and cloud visual fade.


# ============================================================================
# Mock AggressionCloud for Logic Tests
# ============================================================================


class MockAggressionCloud:
	## Radius of the gas cloud in pixels.
	var cloud_radius: float = 300.0

	## How long the cloud persists (seconds).
	var cloud_duration: float = 20.0

	## How long the aggression effect lasts on each enemy (seconds).
	var aggression_effect_duration: float = 10.0

	## Timer for periodic effect application.
	var _effect_tick_timer: float = 0.0
	const EFFECT_TICK_INTERVAL: float = 0.5

	## Time remaining before cloud dissipates.
	var _time_remaining: float = 0.0

	## Track number of effect ticks applied.
	var _effect_ticks_applied: int = 0

	## Track if cloud was freed.
	var queue_freed: bool = false

	## Cloud visual alpha for sprite fallback.
	var cloud_visual_alpha: float = 0.75

	## Whether using particles.
	var _using_particles: bool = false

	## Simulate ready.
	func ready() -> void:
		_time_remaining = cloud_duration

	## Simulate physics process.
	func physics_process(delta: float) -> void:
		_time_remaining -= delta

		_effect_tick_timer += delta
		if _effect_tick_timer >= EFFECT_TICK_INTERVAL:
			_effect_tick_timer = 0.0
			_apply_effect()

		_update_cloud_visual()

		if _time_remaining <= 0.0:
			queue_free()

	## Simulate effect application.
	func _apply_effect() -> void:
		_effect_ticks_applied += 1

	## Update cloud visual based on remaining time.
	func _update_cloud_visual() -> void:
		if not _using_particles:
			if _time_remaining < 5.0:
				var fade_ratio := _time_remaining / 5.0
				cloud_visual_alpha = 0.75 * fade_ratio
			else:
				cloud_visual_alpha = 0.75

	## Simulate queue_free.
	func queue_free() -> void:
		queue_freed = true


var cloud: MockAggressionCloud


func before_each() -> void:
	cloud = MockAggressionCloud.new()


func after_each() -> void:
	cloud = null


# ============================================================================
# Default Configuration Tests
# ============================================================================


func test_cloud_radius_default() -> void:
	assert_eq(cloud.cloud_radius, 300.0,
		"Cloud radius should default to 300.0 pixels")


func test_cloud_duration_default() -> void:
	assert_eq(cloud.cloud_duration, 20.0,
		"Cloud duration should default to 20.0 seconds")


func test_aggression_effect_duration_default() -> void:
	assert_eq(cloud.aggression_effect_duration, 10.0,
		"Aggression effect duration should default to 10.0 seconds")


func test_effect_tick_interval() -> void:
	assert_eq(MockAggressionCloud.EFFECT_TICK_INTERVAL, 0.5,
		"EFFECT_TICK_INTERVAL should be 0.5 seconds")


# ============================================================================
# Time Remaining Countdown Tests
# ============================================================================


func test_time_remaining_initialized_on_ready() -> void:
	cloud.ready()

	assert_eq(cloud._time_remaining, 20.0,
		"Time remaining should be initialized to cloud_duration")


func test_time_remaining_decreases() -> void:
	cloud.ready()
	cloud.physics_process(5.0)

	assert_almost_eq(cloud._time_remaining, 15.0, 0.01,
		"Time remaining should decrease by delta")


func test_cloud_dissipates_at_zero() -> void:
	cloud.ready()
	cloud.physics_process(21.0)

	assert_true(cloud.queue_freed,
		"Cloud should be freed when time remaining reaches zero")


func test_cloud_persists_before_duration() -> void:
	cloud.ready()
	cloud.physics_process(10.0)

	assert_false(cloud.queue_freed,
		"Cloud should persist before duration expires")


# ============================================================================
# Effect Tick Tests
# ============================================================================


func test_no_tick_before_interval() -> void:
	cloud.ready()
	cloud.physics_process(0.3)

	assert_eq(cloud._effect_ticks_applied, 0,
		"No effect tick should occur before EFFECT_TICK_INTERVAL")


func test_tick_at_interval() -> void:
	cloud.ready()
	cloud.physics_process(0.5)

	assert_eq(cloud._effect_ticks_applied, 1,
		"One effect tick should occur at EFFECT_TICK_INTERVAL")


func test_multiple_ticks_over_time() -> void:
	cloud.ready()
	# Process 2.5 seconds in 0.5s increments
	for i in range(5):
		cloud.physics_process(0.5)

	assert_eq(cloud._effect_ticks_applied, 5,
		"Should have 5 ticks after 2.5 seconds at 0.5s interval")


# ============================================================================
# Cloud Visual Fade Tests
# ============================================================================


func test_cloud_visual_full_alpha_above_5_seconds() -> void:
	cloud.ready()
	cloud.physics_process(10.0)

	assert_eq(cloud.cloud_visual_alpha, 0.75,
		"Cloud visual alpha should be 0.75 when time remaining > 5s")


func test_cloud_visual_fading_below_5_seconds() -> void:
	cloud.ready()
	cloud.physics_process(17.5)
	# time_remaining = 2.5, fade_ratio = 2.5/5.0 = 0.5

	assert_almost_eq(cloud.cloud_visual_alpha, 0.75 * 0.5, 0.01,
		"Cloud visual should fade proportionally in last 5 seconds")


func test_cloud_visual_near_zero_at_end() -> void:
	cloud.ready()
	cloud.physics_process(19.5)
	# time_remaining = 0.5, fade_ratio = 0.5/5.0 = 0.1

	assert_almost_eq(cloud.cloud_visual_alpha, 0.75 * 0.1, 0.01,
		"Cloud visual should be nearly invisible near the end")


func test_cloud_visual_at_boundary() -> void:
	cloud.ready()
	cloud.physics_process(15.0)
	# time_remaining = 5.0, should still be full alpha

	assert_eq(cloud.cloud_visual_alpha, 0.75,
		"Cloud visual should be full alpha at exactly 5 seconds remaining")
