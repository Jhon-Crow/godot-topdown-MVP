extends GutTest
## Unit tests for the Trajectory Glasses active item (Issue #744).
##
## Tests the trajectory glasses effect including:
## - Charge management (2 charges per battle)
## - Effect duration (10 seconds per activation)
## - Activation/deactivation logic
## - Ricochet angle calculation
## - Signal emissions


# ============================================================================
# Mock Classes
# ============================================================================


class MockTrajectoryGlassesEffect:
	## Duration of trajectory glasses effect in seconds.
	const EFFECT_DURATION: float = 10.0

	## Maximum charges per battle.
	const MAX_CHARGES: int = 2

	## Maximum ricochet angle in degrees.
	const MAX_RICOCHET_ANGLE: float = 90.0

	## Current number of charges remaining.
	var charges: int = MAX_CHARGES

	## Whether the effect is currently active.
	var is_active: bool = false

	## Timer tracking remaining effect duration.
	var _effect_timer: float = 0.0

	## Signal tracking.
	var activation_count: int = 0
	var deactivation_count: int = 0
	var charges_changed_count: int = 0

	## Attempt to activate the trajectory glasses effect.
	func activate() -> bool:
		if is_active:
			return false
		if charges <= 0:
			return false

		charges -= 1
		is_active = true
		_effect_timer = EFFECT_DURATION
		activation_count += 1
		charges_changed_count += 1
		return true

	## Deactivate the trajectory glasses effect.
	func deactivate() -> void:
		if not is_active:
			return
		is_active = false
		_effect_timer = 0.0
		deactivation_count += 1

	## Simulate time passing.
	func update(delta: float) -> void:
		if not is_active:
			return
		_effect_timer -= delta
		if _effect_timer <= 0.0:
			deactivate()

	## Get remaining effect time.
	func get_remaining_time() -> float:
		return _effect_timer if is_active else 0.0

	## Get current charges.
	func get_charges() -> int:
		return charges

	## Calculate the grazing/impact angle in degrees.
	func calculate_impact_angle(direction: Vector2, surface_normal: Vector2) -> float:
		var dot := absf(direction.normalized().dot(surface_normal.normalized()))
		dot = clampf(dot, 0.0, 1.0)
		return rad_to_deg(asin(dot))

	## Check if ricochet is valid at the given angle.
	func is_valid_ricochet_angle(angle_deg: float) -> bool:
		return angle_deg <= MAX_RICOCHET_ANGLE


var effect: MockTrajectoryGlassesEffect


func before_each() -> void:
	effect = MockTrajectoryGlassesEffect.new()


func after_each() -> void:
	effect = null


# ============================================================================
# Charge Tests
# ============================================================================


func test_initial_charges_is_max() -> void:
	assert_eq(effect.charges, effect.MAX_CHARGES,
		"Initial charges should be MAX_CHARGES (2)")


func test_max_charges_is_two() -> void:
	assert_eq(effect.MAX_CHARGES, 2,
		"MAX_CHARGES should be 2 as per issue specification")


func test_activation_consumes_charge() -> void:
	var initial_charges := effect.charges
	effect.activate()
	assert_eq(effect.charges, initial_charges - 1,
		"Activation should consume one charge")


func test_cannot_activate_with_zero_charges() -> void:
	# Use up all charges
	effect.activate()
	effect.deactivate()
	effect.activate()
	effect.deactivate()

	# Should have 0 charges now
	assert_eq(effect.charges, 0, "Should have 0 charges after 2 activations")

	# Third activation should fail
	var result := effect.activate()
	assert_false(result, "Should not activate with 0 charges")


func test_charges_do_not_regenerate() -> void:
	effect.activate()
	effect.deactivate()
	assert_eq(effect.charges, 1,
		"Charges should remain at 1 after deactivation (no regeneration)")


# ============================================================================
# Duration Tests
# ============================================================================


func test_effect_duration_is_ten_seconds() -> void:
	assert_eq(effect.EFFECT_DURATION, 10.0,
		"EFFECT_DURATION should be 10 seconds as per issue specification")


func test_remaining_time_after_activation() -> void:
	effect.activate()
	assert_eq(effect.get_remaining_time(), effect.EFFECT_DURATION,
		"Remaining time should be EFFECT_DURATION right after activation")


func test_remaining_time_decreases() -> void:
	effect.activate()
	effect.update(3.0)  # 3 seconds pass
	assert_almost_eq(effect.get_remaining_time(), 7.0, 0.01,
		"Remaining time should decrease by delta")


func test_effect_deactivates_after_duration() -> void:
	effect.activate()
	effect.update(10.5)  # More than 10 seconds
	assert_false(effect.is_active,
		"Effect should automatically deactivate after duration expires")


func test_remaining_time_is_zero_when_inactive() -> void:
	assert_eq(effect.get_remaining_time(), 0.0,
		"Remaining time should be 0 when inactive")


# ============================================================================
# Activation State Tests
# ============================================================================


func test_starts_inactive() -> void:
	assert_false(effect.is_active, "Effect should start inactive")


func test_activate_returns_true_on_success() -> void:
	var result := effect.activate()
	assert_true(result, "activate() should return true on success")


func test_is_active_after_activation() -> void:
	effect.activate()
	assert_true(effect.is_active, "Effect should be active after activation")


func test_cannot_double_activate() -> void:
	effect.activate()
	var result := effect.activate()
	assert_false(result, "Should not be able to activate while already active")


func test_is_inactive_after_deactivation() -> void:
	effect.activate()
	effect.deactivate()
	assert_false(effect.is_active, "Effect should be inactive after deactivation")


func test_can_reactivate_after_deactivation() -> void:
	effect.activate()
	effect.deactivate()
	var result := effect.activate()
	assert_true(result, "Should be able to reactivate after deactivation")


# ============================================================================
# Signal Tracking Tests
# ============================================================================


func test_activation_increments_count() -> void:
	effect.activate()
	assert_eq(effect.activation_count, 1, "Activation should increment count")


func test_deactivation_increments_count() -> void:
	effect.activate()
	effect.deactivate()
	assert_eq(effect.deactivation_count, 1, "Deactivation should increment count")


func test_charges_changed_on_activation() -> void:
	effect.activate()
	assert_eq(effect.charges_changed_count, 1,
		"Charges changed should be emitted on activation")


func test_auto_deactivation_increments_deactivation_count() -> void:
	effect.activate()
	effect.update(15.0)  # Force auto-deactivation
	assert_eq(effect.deactivation_count, 1,
		"Auto-deactivation should increment deactivation count")


# ============================================================================
# Ricochet Angle Calculation Tests
# ============================================================================


func test_parallel_shot_has_zero_impact_angle() -> void:
	# Bullet traveling parallel to surface (grazing)
	var direction := Vector2.RIGHT
	var normal := Vector2.UP  # Perpendicular to bullet direction
	var angle := effect.calculate_impact_angle(direction, normal)
	assert_almost_eq(angle, 0.0, 0.1,
		"Parallel/grazing shot should have ~0 degree impact angle")


func test_perpendicular_shot_has_90_degree_impact_angle() -> void:
	# Bullet traveling directly into surface (head-on)
	var direction := Vector2.UP
	var normal := Vector2.DOWN  # Opposite to bullet direction
	var angle := effect.calculate_impact_angle(direction, normal)
	assert_almost_eq(angle, 90.0, 0.1,
		"Perpendicular/head-on shot should have ~90 degree impact angle")


func test_45_degree_shot() -> void:
	# Bullet traveling at 45 degrees to surface
	var direction := Vector2(1, 1).normalized()
	var normal := Vector2.UP
	var angle := effect.calculate_impact_angle(direction, normal)
	assert_almost_eq(angle, 45.0, 0.1,
		"45-degree shot should have ~45 degree impact angle")


func test_shallow_angle_is_valid_ricochet() -> void:
	# 15 degrees - shallow angle, should ricochet
	assert_true(effect.is_valid_ricochet_angle(15.0),
		"15 degree angle should be valid for ricochet")


func test_moderate_angle_is_valid_ricochet() -> void:
	# 45 degrees - moderate angle, still valid
	assert_true(effect.is_valid_ricochet_angle(45.0),
		"45 degree angle should be valid for ricochet")


func test_steep_angle_is_valid_at_max() -> void:
	# 90 degrees - exactly at max angle
	assert_true(effect.is_valid_ricochet_angle(90.0),
		"90 degree angle should be valid (at max threshold)")


func test_beyond_max_angle_is_invalid() -> void:
	# 91 degrees - beyond max angle
	assert_false(effect.is_valid_ricochet_angle(91.0),
		"91 degree angle should be invalid for ricochet")


# ============================================================================
# Integration Tests
# ============================================================================


func test_full_usage_cycle() -> void:
	# First activation
	assert_true(effect.activate(), "First activation should succeed")
	assert_eq(effect.charges, 1, "Should have 1 charge left")
	assert_true(effect.is_active, "Should be active")

	# Wait for duration
	effect.update(10.0)
	assert_false(effect.is_active, "Should be inactive after duration")

	# Second activation
	assert_true(effect.activate(), "Second activation should succeed")
	assert_eq(effect.charges, 0, "Should have 0 charges left")
	assert_true(effect.is_active, "Should be active")

	# Wait for duration
	effect.update(10.0)
	assert_false(effect.is_active, "Should be inactive after duration")

	# Third activation should fail
	assert_false(effect.activate(), "Third activation should fail (no charges)")
	assert_eq(effect.charges, 0, "Should still have 0 charges")


func test_manual_deactivation_preserves_charges() -> void:
	effect.activate()
	effect.update(3.0)  # 3 seconds used
	effect.deactivate()  # Manually deactivate early

	assert_eq(effect.charges, 1, "Manual deactivation should preserve remaining charge")
	assert_false(effect.is_active, "Should be inactive after manual deactivation")
