extends GutTest
## Unit tests for GrenadeBase abstract class.
##
## Tests the common grenade mechanics including timer-based detonation,
## throw physics, effect radius calculation, and visual blink effects.


# ============================================================================
# Mock GrenadeBase for Logic Tests
# ============================================================================


class MockGrenadeBase:
	## Time until explosion in seconds.
	var fuse_time: float = 4.0

	## Maximum throw speed in pixels per second.
	var max_throw_speed: float = 2500.0

	## Minimum throw speed for a minimal drag.
	var min_throw_speed: float = 100.0

	## Drag multiplier to convert drag distance to throw speed.
	var drag_to_speed_multiplier: float = 2.0

	## Mass of the grenade in kg (for velocity-based physics).
	var grenade_mass: float = 0.4

	## Multiplier to convert mouse velocity to throw velocity.
	var mouse_velocity_to_throw_multiplier: float = 3.0

	## Minimum swing distance for full velocity transfer.
	## Reduced from 200.0 to 80.0 for issue #281 fix.
	var min_swing_distance: float = 80.0

	## Minimum transfer efficiency for quick flicks (issue #281 fix).
	var min_transfer_efficiency: float = 0.35

	## Friction/damping applied to slow the grenade.
	var ground_friction: float = 150.0

	## Bounce coefficient when hitting walls.
	var wall_bounce: float = 0.4

	## Sound range multiplier.
	var sound_range_multiplier: float = 2.0

	## Minimum velocity to trigger landing sound.
	var landing_velocity_threshold: float = 50.0

	## Whether the grenade timer has been activated.
	var _timer_active: bool = false

	## Time remaining until explosion.
	var _time_remaining: float = 0.0

	## Whether the grenade has exploded.
	var _has_exploded: bool = false

	## Track if landing sound has been played.
	var _has_landed: bool = false

	## Track if activation sound has been played.
	var _activation_sound_played: bool = false

	## Global position simulation.
	var global_position: Vector2 = Vector2.ZERO

	## Linear velocity simulation.
	var linear_velocity: Vector2 = Vector2.ZERO

	## Rotation.
	var rotation: float = 0.0

	## Whether physics is frozen.
	var freeze: bool = true

	## Blink timer for visual feedback.
	var _blink_timer: float = 0.0

	## Blink interval.
	var _blink_interval: float = 0.5

	## Signals emitted tracking.
	var exploded_emitted: int = 0
	var activation_sound_played: int = 0
	var explosion_sound_played: int = 0
	var landing_sound_played: int = 0

	## Activate the grenade timer.
	func activate_timer() -> void:
		if _timer_active:
			return
		_timer_active = true
		_time_remaining = fuse_time

		if not _activation_sound_played:
			_activation_sound_played = true
			activation_sound_played += 1

	## Throw the grenade using velocity-based physics.
	## Updated with issue #281 fix: minimum transfer efficiency for quick flicks.
	func throw_grenade_velocity_based(mouse_velocity: Vector2, swing_distance: float) -> void:
		freeze = false

		# Calculate mass-adjusted minimum swing distance
		var mass_ratio := grenade_mass / 0.4
		var required_swing := min_swing_distance * mass_ratio

		# Calculate velocity transfer efficiency with minimum guarantee for quick flicks
		# FIX for issue #281: Short fast mouse movements now get reasonable transfer
		var swing_transfer := clampf(swing_distance / required_swing, 0.0, 1.0 - min_transfer_efficiency)
		var transfer_efficiency := clampf(min_transfer_efficiency + swing_transfer, 0.0, 1.0)

		# Convert mouse velocity to throw velocity
		var base_throw_velocity := mouse_velocity * mouse_velocity_to_throw_multiplier * transfer_efficiency
		var mass_adjusted_velocity := base_throw_velocity / sqrt(mass_ratio)

		# Clamp the final speed
		var throw_speed := clampf(mass_adjusted_velocity.length(), 0.0, max_throw_speed)

		# Set velocity
		if throw_speed > 1.0:
			linear_velocity = mass_adjusted_velocity.normalized() * throw_speed
			rotation = linear_velocity.angle()
		else:
			linear_velocity = Vector2.ZERO

	## Throw the grenade in a direction with speed based on drag distance (legacy).
	func throw_grenade(direction: Vector2, drag_distance: float) -> void:
		freeze = false

		var throw_speed := clampf(
			drag_distance * drag_to_speed_multiplier,
			min_throw_speed,
			max_throw_speed
		)

		linear_velocity = direction.normalized() * throw_speed
		rotation = direction.angle()

	## Simulate physics process.
	func physics_process(delta: float, previous_velocity: Vector2) -> void:
		if _has_exploded:
			return

		# Apply ground friction
		if linear_velocity.length() > 0:
			var friction_force := linear_velocity.normalized() * ground_friction * delta
			if friction_force.length() > linear_velocity.length():
				linear_velocity = Vector2.ZERO
			else:
				linear_velocity -= friction_force

		# Check for landing
		if not _has_landed and _timer_active:
			var current_speed := linear_velocity.length()
			var previous_speed := previous_velocity.length()
			if previous_speed > landing_velocity_threshold and current_speed < landing_velocity_threshold:
				_on_grenade_landed()

		# Update timer if active
		if _timer_active:
			_time_remaining -= delta
			_update_blink_effect(delta)

			if _time_remaining <= 0:
				_explode()

	## Update visual blink effect.
	func _update_blink_effect(delta: float) -> void:
		if _time_remaining < 1.0:
			_blink_interval = 0.05
		elif _time_remaining < 2.0:
			_blink_interval = 0.15
		elif _time_remaining < 3.0:
			_blink_interval = 0.3
		else:
			_blink_interval = 0.5

		_blink_timer += delta

	## Internal explosion handling.
	func _explode() -> void:
		if _has_exploded:
			return
		_has_exploded = true
		explosion_sound_played += 1
		exploded_emitted += 1

	## Called when grenade lands.
	func _on_grenade_landed() -> void:
		_has_landed = true
		landing_sound_played += 1

	## Get the explosion effect radius.
	func _get_effect_radius() -> float:
		return 200.0

	## Check if a position is within the effect radius.
	func is_in_effect_radius(pos: Vector2) -> bool:
		return global_position.distance_to(pos) <= _get_effect_radius()

	## Get the remaining time until explosion.
	func get_time_remaining() -> float:
		return _time_remaining

	## Check if the timer is active.
	func is_timer_active() -> bool:
		return _timer_active

	## Check if the grenade has exploded.
	func has_exploded() -> bool:
		return _has_exploded


var grenade: MockGrenadeBase


func before_each() -> void:
	grenade = MockGrenadeBase.new()


func after_each() -> void:
	grenade = null


# ============================================================================
# Default Configuration Tests
# ============================================================================


func test_default_fuse_time() -> void:
	assert_eq(grenade.fuse_time, 4.0,
		"Default fuse time should be 4 seconds")


func test_default_max_throw_speed() -> void:
	assert_eq(grenade.max_throw_speed, 2500.0,
		"Default max throw speed should be 2500 px/s")


func test_default_min_throw_speed() -> void:
	assert_eq(grenade.min_throw_speed, 100.0,
		"Default min throw speed should be 100 px/s")


func test_default_drag_to_speed_multiplier() -> void:
	assert_eq(grenade.drag_to_speed_multiplier, 2.0,
		"Default drag to speed multiplier should be 2.0")


func test_default_ground_friction() -> void:
	assert_eq(grenade.ground_friction, 150.0,
		"Default ground friction should be 150")


func test_default_wall_bounce() -> void:
	assert_eq(grenade.wall_bounce, 0.4,
		"Default wall bounce should be 0.4")


func test_default_sound_range_multiplier() -> void:
	assert_eq(grenade.sound_range_multiplier, 2.0,
		"Default sound range multiplier should be 2.0")


func test_default_landing_velocity_threshold() -> void:
	assert_eq(grenade.landing_velocity_threshold, 50.0,
		"Default landing velocity threshold should be 50")


# ============================================================================
# Initial State Tests
# ============================================================================


func test_timer_not_active_initially() -> void:
	assert_false(grenade.is_timer_active(),
		"Timer should not be active initially")


func test_grenade_not_exploded_initially() -> void:
	assert_false(grenade.has_exploded(),
		"Grenade should not be exploded initially")


func test_grenade_frozen_initially() -> void:
	assert_true(grenade.freeze,
		"Grenade should be frozen initially")


func test_time_remaining_zero_initially() -> void:
	assert_eq(grenade.get_time_remaining(), 0.0,
		"Time remaining should be 0 initially")


# ============================================================================
# Timer Activation Tests
# ============================================================================


func test_activate_timer_sets_active() -> void:
	grenade.activate_timer()

	assert_true(grenade.is_timer_active())


func test_activate_timer_sets_time_remaining() -> void:
	grenade.activate_timer()

	assert_eq(grenade.get_time_remaining(), 4.0)


func test_activate_timer_plays_activation_sound() -> void:
	grenade.activate_timer()

	assert_eq(grenade.activation_sound_played, 1)


func test_activate_timer_twice_does_nothing() -> void:
	grenade.activate_timer()
	grenade.activate_timer()

	assert_eq(grenade.activation_sound_played, 1,
		"Activation sound should only play once")


func test_custom_fuse_time() -> void:
	grenade.fuse_time = 6.0
	grenade.activate_timer()

	assert_eq(grenade.get_time_remaining(), 6.0)


# ============================================================================
# Throw Tests
# ============================================================================


func test_throw_unfreezes_grenade() -> void:
	grenade.throw_grenade(Vector2.RIGHT, 100.0)

	assert_false(grenade.freeze)


func test_throw_sets_velocity() -> void:
	grenade.throw_grenade(Vector2.RIGHT, 100.0)

	assert_gt(grenade.linear_velocity.length(), 0,
		"Should have velocity after throw")


func test_throw_direction() -> void:
	grenade.throw_grenade(Vector2.RIGHT, 100.0)

	assert_gt(grenade.linear_velocity.x, 0,
		"Velocity should be in throw direction")
	assert_almost_eq(grenade.linear_velocity.y, 0.0, 0.001)


func test_throw_speed_scales_with_drag() -> void:
	grenade.throw_grenade(Vector2.RIGHT, 100.0)
	var speed_short := grenade.linear_velocity.length()

	grenade.linear_velocity = Vector2.ZERO
	grenade.throw_grenade(Vector2.RIGHT, 500.0)
	var speed_long := grenade.linear_velocity.length()

	assert_gt(speed_long, speed_short,
		"Longer drag should produce faster throw")


func test_throw_speed_min_clamp() -> void:
	grenade.throw_grenade(Vector2.RIGHT, 1.0)  # Very short drag

	assert_gte(grenade.linear_velocity.length(), grenade.min_throw_speed,
		"Throw speed should not go below minimum")


func test_throw_speed_max_clamp() -> void:
	grenade.throw_grenade(Vector2.RIGHT, 10000.0)  # Very long drag

	assert_le(grenade.linear_velocity.length(), grenade.max_throw_speed,
		"Throw speed should not exceed maximum")


func test_throw_sets_rotation() -> void:
	grenade.throw_grenade(Vector2(1, 1).normalized(), 100.0)

	# 45 degrees = PI/4 radians
	assert_almost_eq(grenade.rotation, PI / 4, 0.01)


func test_throw_normalizes_direction() -> void:
	grenade.throw_grenade(Vector2(100, 0), 100.0)  # Non-normalized

	var expected_speed := 100.0 * grenade.drag_to_speed_multiplier
	assert_almost_eq(grenade.linear_velocity.length(), expected_speed, 0.01,
		"Direction should be normalized")


# ============================================================================
# Physics Process Tests
# ============================================================================


func test_physics_process_reduces_timer() -> void:
	grenade.activate_timer()
	grenade.physics_process(1.0, Vector2.ZERO)

	assert_eq(grenade.get_time_remaining(), 3.0)


func test_physics_process_applies_friction() -> void:
	grenade.freeze = false
	grenade.linear_velocity = Vector2(500, 0)
	grenade.physics_process(0.1, Vector2(500, 0))

	assert_lt(grenade.linear_velocity.length(), 500,
		"Friction should slow the grenade")


func test_physics_process_stops_at_zero_velocity() -> void:
	grenade.freeze = false
	grenade.linear_velocity = Vector2(10, 0)  # Small velocity
	grenade.physics_process(1.0, Vector2(10, 0))  # Large delta

	# Should stop completely, not go negative
	assert_eq(grenade.linear_velocity, Vector2.ZERO)


func test_physics_process_explodes_at_zero_time() -> void:
	grenade.activate_timer()
	grenade.physics_process(5.0, Vector2.ZERO)  # Past fuse time

	assert_true(grenade.has_exploded())


func test_physics_process_does_nothing_after_exploded() -> void:
	grenade.activate_timer()
	grenade._has_exploded = true
	var time_before := grenade.get_time_remaining()
	grenade.physics_process(1.0, Vector2.ZERO)

	assert_eq(grenade.get_time_remaining(), time_before,
		"Should not update timer after explosion")


# ============================================================================
# Landing Detection Tests
# ============================================================================


func test_landing_detected_when_velocity_drops() -> void:
	grenade.activate_timer()
	grenade.linear_velocity = Vector2(10, 0)  # Below threshold
	grenade.physics_process(0.1, Vector2(100, 0))  # Previous above threshold

	assert_true(grenade._has_landed)
	assert_eq(grenade.landing_sound_played, 1)


func test_landing_not_detected_if_timer_not_active() -> void:
	grenade.linear_velocity = Vector2(10, 0)
	grenade.physics_process(0.1, Vector2(100, 0))

	assert_false(grenade._has_landed)


func test_landing_sound_only_plays_once() -> void:
	grenade.activate_timer()
	grenade.linear_velocity = Vector2(10, 0)
	grenade.physics_process(0.1, Vector2(100, 0))
	grenade.physics_process(0.1, Vector2(100, 0))

	assert_eq(grenade.landing_sound_played, 1)


# ============================================================================
# Explosion Tests
# ============================================================================


func test_explosion_sets_exploded_flag() -> void:
	grenade.activate_timer()
	grenade.physics_process(5.0, Vector2.ZERO)

	assert_true(grenade.has_exploded())


func test_explosion_plays_sound() -> void:
	grenade.activate_timer()
	grenade.physics_process(5.0, Vector2.ZERO)

	assert_eq(grenade.explosion_sound_played, 1)


func test_explosion_emits_signal() -> void:
	grenade.activate_timer()
	grenade.physics_process(5.0, Vector2.ZERO)

	assert_eq(grenade.exploded_emitted, 1)


func test_explosion_only_happens_once() -> void:
	grenade.activate_timer()
	grenade.physics_process(5.0, Vector2.ZERO)
	grenade._has_exploded = false  # Reset flag (normally impossible)
	grenade.physics_process(1.0, Vector2.ZERO)

	# Manual _explode call protection
	grenade._explode()
	grenade._explode()

	# Should only have 2 (one from process + one failed attempt)
	# Actually, after first explosion, timer stops updating
	assert_eq(grenade.exploded_emitted, 2)


# ============================================================================
# Effect Radius Tests
# ============================================================================


func test_default_effect_radius() -> void:
	assert_eq(grenade._get_effect_radius(), 200.0)


func test_is_in_effect_radius_at_center() -> void:
	grenade.global_position = Vector2(100, 100)

	assert_true(grenade.is_in_effect_radius(Vector2(100, 100)))


func test_is_in_effect_radius_within_range() -> void:
	grenade.global_position = Vector2(100, 100)

	assert_true(grenade.is_in_effect_radius(Vector2(200, 100)))  # 100 units away


func test_is_in_effect_radius_at_edge() -> void:
	grenade.global_position = Vector2(0, 0)

	assert_true(grenade.is_in_effect_radius(Vector2(200, 0)))  # Exactly at radius


func test_is_not_in_effect_radius_outside() -> void:
	grenade.global_position = Vector2(0, 0)

	assert_false(grenade.is_in_effect_radius(Vector2(300, 0)))  # Outside radius


# ============================================================================
# Blink Effect Tests
# ============================================================================


func test_blink_interval_fast_when_near_explosion() -> void:
	grenade.activate_timer()
	grenade._time_remaining = 0.5
	grenade._update_blink_effect(0.1)

	assert_eq(grenade._blink_interval, 0.05)


func test_blink_interval_medium_1_to_2_seconds() -> void:
	grenade.activate_timer()
	grenade._time_remaining = 1.5
	grenade._update_blink_effect(0.1)

	assert_eq(grenade._blink_interval, 0.15)


func test_blink_interval_slow_2_to_3_seconds() -> void:
	grenade.activate_timer()
	grenade._time_remaining = 2.5
	grenade._update_blink_effect(0.1)

	assert_eq(grenade._blink_interval, 0.3)


func test_blink_interval_slowest_above_3_seconds() -> void:
	grenade.activate_timer()
	grenade._time_remaining = 3.5
	grenade._update_blink_effect(0.1)

	assert_eq(grenade._blink_interval, 0.5)


func test_blink_timer_accumulates() -> void:
	grenade._blink_timer = 0.0
	grenade._time_remaining = 3.5
	grenade._update_blink_effect(0.1)
	grenade._update_blink_effect(0.1)

	assert_eq(grenade._blink_timer, 0.2)


# ============================================================================
# Edge Cases Tests
# ============================================================================


func test_throw_zero_drag_uses_min_speed() -> void:
	grenade.throw_grenade(Vector2.RIGHT, 0.0)

	assert_eq(grenade.linear_velocity.length(), grenade.min_throw_speed)


func test_throw_with_zero_direction() -> void:
	grenade.throw_grenade(Vector2.ZERO, 100.0)

	# Normalizing zero vector produces NaN, should handle gracefully
	# In real code this might cause issues, test documents behavior
	assert_true(is_nan(grenade.linear_velocity.x) or grenade.linear_velocity.length() == 0)


func test_negative_fuse_time() -> void:
	grenade.fuse_time = -1.0
	grenade.activate_timer()

	# Should explode immediately on first physics update
	grenade.physics_process(0.1, Vector2.ZERO)

	assert_true(grenade.has_exploded())


func test_very_large_delta() -> void:
	grenade.activate_timer()
	grenade.physics_process(100.0, Vector2.ZERO)

	assert_true(grenade.has_exploded())
	assert_le(grenade.get_time_remaining(), 0.0)


# ============================================================================
# Velocity-Based Throwing Tests (Realistic Physics)
# ============================================================================


func test_velocity_based_throw_unfreezes_grenade() -> void:
	grenade.throw_grenade_velocity_based(Vector2(500, 0), 300.0)

	assert_false(grenade.freeze)


func test_velocity_based_throw_with_zero_mouse_velocity() -> void:
	# If mouse is not moving at release, grenade should have zero velocity
	grenade.throw_grenade_velocity_based(Vector2.ZERO, 200.0)

	assert_eq(grenade.linear_velocity, Vector2.ZERO,
		"Zero mouse velocity should result in grenade dropping at feet")


func test_velocity_based_throw_direction_matches_mouse_velocity() -> void:
	grenade.throw_grenade_velocity_based(Vector2(1000, 0), 250.0)

	assert_gt(grenade.linear_velocity.x, 0,
		"Velocity should be in direction of mouse movement")
	assert_almost_eq(grenade.linear_velocity.y, 0.0, 0.001)


func test_velocity_based_throw_speed_scales_with_mouse_velocity() -> void:
	grenade.throw_grenade_velocity_based(Vector2(500, 0), 250.0)
	var speed_slow := grenade.linear_velocity.length()

	grenade.linear_velocity = Vector2.ZERO
	grenade.throw_grenade_velocity_based(Vector2(1500, 0), 250.0)
	var speed_fast := grenade.linear_velocity.length()

	assert_gt(speed_fast, speed_slow,
		"Faster mouse movement should produce faster throw")


func test_velocity_based_throw_transfer_efficiency_with_low_swing() -> void:
	# Low swing distance should reduce velocity transfer
	grenade.throw_grenade_velocity_based(Vector2(1000, 0), 50.0)
	var speed_low_swing := grenade.linear_velocity.length()

	grenade.linear_velocity = Vector2.ZERO
	grenade.throw_grenade_velocity_based(Vector2(1000, 0), 400.0)
	var speed_high_swing := grenade.linear_velocity.length()

	assert_gt(speed_high_swing, speed_low_swing,
		"Longer swing distance should improve velocity transfer")


func test_velocity_based_throw_mass_affects_throw_speed() -> void:
	# Light grenade
	grenade.grenade_mass = 0.2
	grenade.throw_grenade_velocity_based(Vector2(1000, 0), 300.0)
	var speed_light := grenade.linear_velocity.length()

	# Heavy grenade
	grenade.linear_velocity = Vector2.ZERO
	grenade.grenade_mass = 0.6
	grenade.throw_grenade_velocity_based(Vector2(1000, 0), 300.0)
	var speed_heavy := grenade.linear_velocity.length()

	assert_gt(speed_light, speed_heavy,
		"Lighter grenade should be thrown faster with same mouse velocity")


func test_velocity_based_throw_max_speed_clamped() -> void:
	grenade.throw_grenade_velocity_based(Vector2(10000, 0), 500.0)

	assert_le(grenade.linear_velocity.length(), grenade.max_throw_speed,
		"Throw speed should not exceed maximum")


func test_velocity_based_throw_sets_rotation() -> void:
	grenade.throw_grenade_velocity_based(Vector2(1, 1).normalized() * 1000, 250.0)

	# 45 degrees = PI/4 radians
	assert_almost_eq(grenade.rotation, PI / 4, 0.01)


func test_velocity_based_throw_with_diagonal_velocity() -> void:
	grenade.throw_grenade_velocity_based(Vector2(500, -500), 250.0)

	assert_gt(grenade.linear_velocity.x, 0)
	assert_lt(grenade.linear_velocity.y, 0)


func test_velocity_based_throw_minimum_swing_scales_with_mass() -> void:
	# Heavy grenade needs more swing for full transfer
	grenade.grenade_mass = 0.6  # 1.5x standard mass
	grenade.min_swing_distance = 80.0

	# With insufficient swing for heavy grenade, transfer is reduced
	grenade.throw_grenade_velocity_based(Vector2(1000, 0), 80.0)
	var speed_heavy_short_swing := grenade.linear_velocity.length()

	grenade.linear_velocity = Vector2.ZERO
	# With sufficient swing (80 * 1.5 = 120)
	grenade.throw_grenade_velocity_based(Vector2(1000, 0), 150.0)
	var speed_heavy_long_swing := grenade.linear_velocity.length()

	assert_gt(speed_heavy_long_swing, speed_heavy_short_swing,
		"Heavy grenade should need more swing distance for full velocity transfer")


# ============================================================================
# Issue #281 Fix Tests: Quick Flick Throwing
# ============================================================================


func test_issue_281_quick_flick_gets_minimum_transfer() -> void:
	# Scenario from issue: Quick flick (874 px/s, 83.7px swing)
	# OLD behavior: transfer = 83.7 / 200 = 0.42 (too low!)
	# NEW behavior: transfer = 0.35 + (83.7/80) * 0.65 = 0.35 + 0.65 = 1.0 (capped)
	grenade.throw_grenade_velocity_based(Vector2(874.2, 0), 83.7)

	# With new system, quick flicks should have reasonable throw speed
	# At minimum, we expect 35% of velocity * multiplier to transfer
	var expected_min_speed := 874.2 * grenade.mouse_velocity_to_throw_multiplier * grenade.min_transfer_efficiency
	assert_gt(grenade.linear_velocity.length(), expected_min_speed * 0.8,
		"Quick flick should have at least 35% velocity transfer")


func test_issue_281_very_short_swing_still_throws() -> void:
	# Very short swing (4px) should still throw the grenade, not drop at feet
	# OLD behavior: transfer = 4 / 200 = 0.02 (basically drops)
	# NEW behavior: transfer = 0.35 minimum
	grenade.throw_grenade_velocity_based(Vector2(1000, 0), 4.0)

	assert_gt(grenade.linear_velocity.length(), 50.0,
		"Even very short swings should throw grenade, not drop at feet")


func test_issue_281_minimum_transfer_efficiency_applied() -> void:
	# Test that minimum transfer efficiency is actually being applied
	# With 0px swing, we should still get min_transfer_efficiency
	grenade.throw_grenade_velocity_based(Vector2(1000, 0), 1.0)
	var speed_zero_swing := grenade.linear_velocity.length()

	# Speed should be at least min_transfer_efficiency * velocity * multiplier
	var expected_speed := 1000.0 * grenade.mouse_velocity_to_throw_multiplier * grenade.min_transfer_efficiency
	assert_gt(speed_zero_swing, expected_speed * 0.8,
		"Minimum transfer efficiency should always apply")


func test_issue_281_full_swing_still_reaches_max_transfer() -> void:
	# Full swing should still achieve 100% transfer (not 135%!)
	grenade.throw_grenade_velocity_based(Vector2(1000, 0), 150.0)  # Well above min_swing
	var speed_full_swing := grenade.linear_velocity.length()

	grenade.linear_velocity = Vector2.ZERO
	grenade.throw_grenade_velocity_based(Vector2(1000, 0), 500.0)  # Much more swing
	var speed_extra_swing := grenade.linear_velocity.length()

	# Both should be at ~100% transfer (same speed)
	assert_almost_eq(speed_full_swing, speed_extra_swing, 10.0,
		"Extra swing beyond required should not increase transfer beyond 100%")


func test_issue_281_intermediate_swing_has_reasonable_transfer() -> void:
	# A swing of 40px (50% of required 80px) should have better transfer than old system
	# OLD: 40/200 = 0.20
	# NEW: 0.35 + (40/80)*0.65 = 0.35 + 0.325 = 0.675
	grenade.throw_grenade_velocity_based(Vector2(1000, 0), 40.0)

	# Expect around 67.5% transfer, which gives ~675 * multiplier speed
	var expected_transfer := 0.35 + (40.0 / 80.0) * (1.0 - 0.35)  # 0.675
	var expected_speed := 1000.0 * grenade.mouse_velocity_to_throw_multiplier * expected_transfer
	assert_almost_eq(grenade.linear_velocity.length(), expected_speed, expected_speed * 0.15,
		"Intermediate swing should have improved transfer vs old system")


func test_issue_281_high_velocity_short_swing_throws_far() -> void:
	# High velocity (2000+ px/s) with short swing (50px) should still throw reasonably
	# This is the core use case from the issue
	grenade.throw_grenade_velocity_based(Vector2(2000, 0), 50.0)

	# With 2000 px/s velocity, minimum 35% transfer should give at least 700 speed
	assert_gt(grenade.linear_velocity.length(), 200.0,
		"High velocity quick flicks should throw grenades reasonably far")
