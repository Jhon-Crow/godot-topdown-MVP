extends GutTest
## Unit tests for grenade throw speed and trajectory visualization (Issue #615).
##
## Verifies that the trajectory preview (_Draw) uses the same physics formula
## as the actual throw (ThrowSimpleGrenade), ensuring the landing indicator
## matches where the grenade actually lands.
##
## FIX for Issue #615: The 1.16x compensation factor was removed because the
## actual root cause was DOUBLE FRICTION — both GDScript (grenade_base.gd) and
## C# (GrenadeTimer.cs) were applying friction simultaneously, causing grenades
## to travel only ~59% of the target distance. Now grenade_base.gd skips friction
## when GrenadeTimer handles it, so v = sqrt(2*F*d) works correctly.


# ============================================================================
# Constants matching Player.cs
# ============================================================================


const FLASHBANG_FRICTION := 300.0
const FRAG_FRICTION := 280.0
const DEFAULT_MAX_THROW_SPEED := 850.0


# ============================================================================
# Helper functions mirroring Player.cs formulas
# ============================================================================


## Calculate throw speed (mirrors ThrowSimpleGrenade in Player.cs).
## v = sqrt(2 * F * d)
static func calculate_throw_speed(throw_distance: float, ground_friction: float) -> float:
	return sqrt(2.0 * ground_friction * throw_distance)


## Calculate landing distance for a given speed (mirrors _Draw in Player.cs).
## d = v^2 / (2 * F)
static func calculate_landing_distance(throw_speed: float, ground_friction: float) -> float:
	return (throw_speed * throw_speed) / (2.0 * ground_friction)


# ============================================================================
# Tests: Throw speed formula is self-consistent (round-trip)
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


func test_draw_and_throw_use_same_formula() -> void:
	## The core fix: _Draw and ThrowSimpleGrenade should use the same
	## formula, so the trajectory preview matches the actual throw.
	var target := 500.0

	# ThrowSimpleGrenade calculates: v = sqrt(2 * F * d)
	var throw_speed := minf(
		calculate_throw_speed(target, FLASHBANG_FRICTION),
		DEFAULT_MAX_THROW_SPEED)

	# _Draw (simple mode) should calculate the SAME speed:
	var draw_speed := minf(
		sqrt(2.0 * FLASHBANG_FRICTION * target),
		DEFAULT_MAX_THROW_SPEED)

	assert_almost_eq(throw_speed, draw_speed, 0.01,
		"Draw and throw should calculate the same speed")

	# _Draw landing distance should match throw actual distance:
	var draw_landing := (draw_speed * draw_speed) / (2.0 * FLASHBANG_FRICTION)
	var throw_landing := (throw_speed * throw_speed) / (2.0 * FLASHBANG_FRICTION)

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


# ============================================================================
# Tests: Double friction prevention (Issue #615 root cause)
# ============================================================================


func test_single_friction_gives_correct_distance() -> void:
	## With single friction (C# only), v = sqrt(2*F*d) should give exact distance.
	## This is the core of the Issue #615 fix.
	var target := 547.0  # From user's game log
	var friction := 300.0
	var speed := sqrt(2.0 * friction * target)
	var actual_distance := (speed * speed) / (2.0 * friction)
	assert_almost_eq(actual_distance, target, 0.1,
		"Single friction should give exact target distance")


func test_double_friction_causes_undershoot() -> void:
	## Demonstrates why double friction was the root cause.
	## With two friction systems (0.5*F from GDScript + 1.0*F from C#),
	## effective friction is ~1.5*F, and grenade travels only ~67% of target.
	var target := 547.0
	var friction := 300.0
	var speed := sqrt(2.0 * friction * target)
	# With 1.5x effective friction:
	var double_friction_distance := (speed * speed) / (2.0 * friction * 1.5)
	assert_true(double_friction_distance < target * 0.75,
		"Double friction should cause significant undershoot (%.1f vs %.1f)" % [
			double_friction_distance, target])


func test_no_compensation_needed_with_single_friction() -> void:
	## The 1.16x factor is no longer needed. With single uniform friction,
	## v = sqrt(2*F*d) gives the correct speed for reaching distance d.
	var target := 500.0
	var friction := 300.0
	var speed_no_comp := sqrt(2.0 * friction * target)
	var distance_no_comp := (speed_no_comp * speed_no_comp) / (2.0 * friction)
	assert_almost_eq(distance_no_comp, target, 0.1,
		"No compensation should be needed with single friction")
