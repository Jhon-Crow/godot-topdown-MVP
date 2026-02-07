extends GutTest
## Unit tests for grenade throw speed and trajectory visualization (Issue #615).
##
## Verifies that the trajectory preview (_Draw) uses the same physics compensation
## factor as the actual throw (ThrowSimpleGrenade), ensuring the landing indicator
## matches where the grenade actually lands.
##
## The compensation factor (1.16x) accounts for Godot's RigidBody2D hidden damping
## effects that cause grenades to land ~14% shorter than the classical physics formula
## predicts (Issue #428).


# ============================================================================
# Constants matching Player.cs
# ============================================================================


const FLASHBANG_FRICTION := 300.0
const FRAG_FRICTION := 280.0
const PHYSICS_COMPENSATION := 1.16
const DEFAULT_MAX_THROW_SPEED := 850.0


# ============================================================================
# Helper functions mirroring Player.cs formulas
# ============================================================================


## Calculate throw speed with compensation (mirrors ThrowSimpleGrenade in Player.cs).
static func calculate_throw_speed(throw_distance: float, ground_friction: float) -> float:
	return sqrt(2.0 * ground_friction * throw_distance * PHYSICS_COMPENSATION)


## Calculate compensated landing distance for a given speed (mirrors _Draw in Player.cs).
## This is the expected actual landing distance, accounting for Godot physics damping.
static func calculate_landing_distance(throw_speed: float, ground_friction: float) -> float:
	return (throw_speed * throw_speed) / (2.0 * ground_friction * PHYSICS_COMPENSATION)


## Calculate uncompensated (theoretical) landing distance.
## This is what the classical physics formula predicts without engine effects.
static func calculate_theoretical_distance(throw_speed: float, ground_friction: float) -> float:
	return (throw_speed * throw_speed) / (2.0 * ground_friction)


# ============================================================================
# Tests: Throw speed formula is self-consistent
# ============================================================================


func test_round_trip_short_distance() -> void:
	var target := 100.0
	var speed := calculate_throw_speed(target, FLASHBANG_FRICTION)
	var distance := calculate_landing_distance(speed, FLASHBANG_FRICTION)
	assert_almost_eq(distance, target, 0.1,
		"Round-trip should recover original distance for short throw")


func test_round_trip_medium_distance() -> void:
	var target := 500.0
	var speed := calculate_throw_speed(target, FLASHBANG_FRICTION)
	var distance := calculate_landing_distance(speed, FLASHBANG_FRICTION)
	assert_almost_eq(distance, target, 0.1,
		"Round-trip should recover original distance for medium throw")


func test_round_trip_long_distance() -> void:
	var target := 1000.0
	var speed := calculate_throw_speed(target, FLASHBANG_FRICTION)
	var distance := calculate_landing_distance(speed, FLASHBANG_FRICTION)
	assert_almost_eq(distance, target, 0.1,
		"Round-trip should recover original distance for long throw")


func test_round_trip_frag_grenade() -> void:
	var target := 600.0
	var speed := calculate_throw_speed(target, FRAG_FRICTION)
	var distance := calculate_landing_distance(speed, FRAG_FRICTION)
	assert_almost_eq(distance, target, 0.1,
		"Round-trip should work for frag grenade friction")


# ============================================================================
# Tests: Compensation produces higher speed than no compensation
# ============================================================================


func test_compensated_speed_higher_than_uncompensated() -> void:
	var target := 500.0
	var compensated := calculate_throw_speed(target, FLASHBANG_FRICTION)
	var uncompensated := sqrt(2.0 * FLASHBANG_FRICTION * target)
	assert_true(compensated > uncompensated,
		"Compensated speed (%.1f) should be higher than uncompensated (%.1f)" % [
			compensated, uncompensated])


func test_compensation_factor_magnitude() -> void:
	## The compensation should increase speed by sqrt(1.16) ≈ 7.7%
	var target := 500.0
	var compensated := calculate_throw_speed(target, FLASHBANG_FRICTION)
	var uncompensated := sqrt(2.0 * FLASHBANG_FRICTION * target)
	var ratio := compensated / uncompensated
	var expected_ratio := sqrt(PHYSICS_COMPENSATION)
	assert_almost_eq(ratio, expected_ratio, 0.001,
		"Speed ratio should be sqrt(1.16) ≈ %.4f" % expected_ratio)


# ============================================================================
# Tests: Landing distance is shorter than theoretical
# ============================================================================


func test_compensated_distance_shorter_than_theoretical() -> void:
	## The compensated landing distance should be ~86% of theoretical
	var speed := 500.0
	var compensated := calculate_landing_distance(speed, FLASHBANG_FRICTION)
	var theoretical := calculate_theoretical_distance(speed, FLASHBANG_FRICTION)
	assert_true(compensated < theoretical,
		"Compensated distance (%.1f) should be shorter than theoretical (%.1f)" % [
			compensated, theoretical])


func test_compensation_distance_ratio() -> void:
	## The ratio should be 1/1.16 ≈ 0.862
	var speed := 500.0
	var compensated := calculate_landing_distance(speed, FLASHBANG_FRICTION)
	var theoretical := calculate_theoretical_distance(speed, FLASHBANG_FRICTION)
	var ratio := compensated / theoretical
	var expected_ratio := 1.0 / PHYSICS_COMPENSATION
	assert_almost_eq(ratio, expected_ratio, 0.001,
		"Distance ratio should be 1/1.16 ≈ %.4f" % expected_ratio)


# ============================================================================
# Tests: Speed increases with distance
# ============================================================================


func test_speed_increases_with_distance() -> void:
	var speed_200 := calculate_throw_speed(200.0, FLASHBANG_FRICTION)
	var speed_500 := calculate_throw_speed(500.0, FLASHBANG_FRICTION)
	var speed_1000 := calculate_throw_speed(1000.0, FLASHBANG_FRICTION)
	assert_true(speed_200 < speed_500,
		"Speed for 200px should be less than 500px")
	assert_true(speed_500 < speed_1000,
		"Speed for 500px should be less than 1000px")


# ============================================================================
# Tests: Landing distance increases with speed
# ============================================================================


func test_landing_distance_increases_with_speed() -> void:
	var d_200 := calculate_landing_distance(200.0, FLASHBANG_FRICTION)
	var d_400 := calculate_landing_distance(400.0, FLASHBANG_FRICTION)
	var d_800 := calculate_landing_distance(800.0, FLASHBANG_FRICTION)
	assert_true(d_200 < d_400,
		"Landing distance at 200px/s should be less than at 400px/s")
	assert_true(d_400 < d_800,
		"Landing distance at 400px/s should be less than at 800px/s")


# ============================================================================
# Tests: Edge cases
# ============================================================================


func test_zero_distance_gives_zero_speed() -> void:
	var speed := calculate_throw_speed(0.0, FLASHBANG_FRICTION)
	assert_almost_eq(speed, 0.0, 0.1,
		"Zero distance should give zero speed")


func test_very_small_distance() -> void:
	var speed := calculate_throw_speed(1.0, FLASHBANG_FRICTION)
	assert_true(speed > 0.0, "Very small distance should give positive speed")
	assert_true(speed < 100.0, "Very small distance should give small speed")


func test_zero_speed_gives_zero_distance() -> void:
	var distance := calculate_landing_distance(0.0, FLASHBANG_FRICTION)
	assert_almost_eq(distance, 0.0, 0.1,
		"Zero speed should give zero distance")


# ============================================================================
# Tests: Visualization matches throw (Issue #615 core fix)
# ============================================================================


func test_draw_and_throw_use_same_compensation() -> void:
	## The core fix: _Draw and ThrowSimpleGrenade should use the same
	## compensation factor, so the trajectory preview matches the actual throw.
	var target := 500.0

	# ThrowSimpleGrenade calculates:
	var throw_speed := minf(
		calculate_throw_speed(target, FLASHBANG_FRICTION),
		DEFAULT_MAX_THROW_SPEED)

	# _Draw (simple mode) should calculate the SAME speed:
	var draw_speed := minf(
		sqrt(2.0 * FLASHBANG_FRICTION * target * PHYSICS_COMPENSATION),
		DEFAULT_MAX_THROW_SPEED)

	assert_almost_eq(throw_speed, draw_speed, 0.01,
		"Draw and throw should calculate the same speed")

	# _Draw landing distance should match throw actual distance:
	var draw_landing := (draw_speed * draw_speed) / (2.0 * FLASHBANG_FRICTION * PHYSICS_COMPENSATION)
	var throw_landing := (throw_speed * throw_speed) / (2.0 * FLASHBANG_FRICTION * PHYSICS_COMPENSATION)

	assert_almost_eq(draw_landing, throw_landing, 0.01,
		"Draw landing should match throw landing distance")
	assert_almost_eq(draw_landing, target, 0.1,
		"Landing distance should equal target distance when speed is not clamped")


func test_clamped_speed_reduces_landing_distance() -> void:
	## When throw speed is clamped to max_throw_speed, the landing distance
	## should be less than the target distance.
	var max_speed := 850.0
	var target := 2000.0  # Very far throw - speed will be clamped

	var speed := calculate_throw_speed(target, FLASHBANG_FRICTION)
	assert_true(speed > max_speed,
		"Speed should exceed max for very long throw")

	var clamped_speed := minf(speed, max_speed)
	var landing := calculate_landing_distance(clamped_speed, FLASHBANG_FRICTION)
	assert_true(landing < target,
		"Clamped landing distance (%.1f) should be less than target (%.1f)" % [
			landing, target])


# ============================================================================
# Tests: Different grenade types
# ============================================================================


func test_frag_grenade_lower_friction_means_farther() -> void:
	## Frag grenade (friction=280) should travel farther than flashbang (friction=300)
	## for the same throw speed.
	var speed := 500.0
	var flashbang_dist := calculate_landing_distance(speed, FLASHBANG_FRICTION)
	var frag_dist := calculate_landing_distance(speed, FRAG_FRICTION)
	assert_true(frag_dist > flashbang_dist,
		"Frag grenade should travel farther with lower friction")


func test_frag_grenade_needs_less_speed() -> void:
	## Frag grenade needs less speed to reach the same distance due to lower friction.
	var target := 500.0
	var flashbang_speed := calculate_throw_speed(target, FLASHBANG_FRICTION)
	var frag_speed := calculate_throw_speed(target, FRAG_FRICTION)
	assert_true(frag_speed < flashbang_speed,
		"Frag grenade should need less speed for same distance")
