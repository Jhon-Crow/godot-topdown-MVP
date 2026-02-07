extends GutTest
## Unit tests for grenade throw speed calculation (Issue #615).
##
## Verifies that the two-phase friction model correctly calculates
## the initial speed needed for a grenade to travel a given distance.
## The two-phase model was introduced in Issue #435 and the speed
## calculation was fixed in Issue #615.


# ============================================================================
# Two-Phase Friction Speed Calculator (mirrors C# CalculateGrenadeThrowSpeed)
# ============================================================================


class ThrowSpeedCalculator:
	## Calculate required throw speed for a given distance using two-phase friction.
	## This mirrors the C# CalculateGrenadeThrowSpeed method in Player.cs.
	static func calculate_throw_speed(throw_distance: float, ground_friction: float,
			friction_ramp_velocity: float, min_friction_multiplier: float) -> float:
		var phase1_friction := ground_friction * min_friction_multiplier

		var avg_phase2_multiplier := min_friction_multiplier \
			+ 2.0 * (1.0 - min_friction_multiplier) / 3.0
		var avg_phase2_friction := ground_friction * avg_phase2_multiplier

		var phase2_distance := friction_ramp_velocity * friction_ramp_velocity \
			/ (2.0 * avg_phase2_friction)

		if throw_distance <= phase2_distance:
			return sqrt(2.0 * avg_phase2_friction * throw_distance)
		else:
			var phase1_distance := throw_distance - phase2_distance
			return sqrt(friction_ramp_velocity * friction_ramp_velocity \
				+ 2.0 * phase1_friction * phase1_distance)

	## Calculate landing distance for a given speed (inverse of calculate_throw_speed).
	## This mirrors the C# CalculateGrenadeLandingDistance method in Player.cs.
	static func calculate_landing_distance(throw_speed: float, ground_friction: float,
			friction_ramp_velocity: float, min_friction_multiplier: float) -> float:
		var phase1_friction := ground_friction * min_friction_multiplier

		var avg_phase2_multiplier := min_friction_multiplier \
			+ 2.0 * (1.0 - min_friction_multiplier) / 3.0
		var avg_phase2_friction := ground_friction * avg_phase2_multiplier

		var phase2_distance := friction_ramp_velocity * friction_ramp_velocity \
			/ (2.0 * avg_phase2_friction)

		if throw_speed <= friction_ramp_velocity:
			return throw_speed * throw_speed / (2.0 * avg_phase2_friction)
		else:
			var phase1_distance := (throw_speed * throw_speed \
				- friction_ramp_velocity * friction_ramp_velocity) / (2.0 * phase1_friction)
			return phase1_distance + phase2_distance


# ============================================================================
# Physics Simulation (replicates grenade_base.gd _physics_process)
# ============================================================================


class PhysicsSimulator:
	## Simulate grenade travel distance with velocity-dependent friction.
	## Replicates the exact friction model from grenade_base.gd _physics_process.
	static func simulate_distance(initial_speed: float, ground_friction: float = 300.0,
			min_friction_multiplier: float = 0.5,
			friction_ramp_velocity: float = 200.0) -> float:
		var velocity := initial_speed
		var position := 0.0
		var delta := 1.0 / 60.0  # 60 FPS physics

		while velocity > 0.001:
			# Calculate friction multiplier (matches grenade_base.gd lines 192-201)
			var friction_multiplier: float
			if velocity >= friction_ramp_velocity:
				friction_multiplier = min_friction_multiplier
			else:
				var t := velocity / friction_ramp_velocity
				friction_multiplier = min_friction_multiplier \
					+ (1.0 - min_friction_multiplier) * (1.0 - t * t)

			var effective_friction := ground_friction * friction_multiplier
			var friction_force := effective_friction * delta

			if friction_force > velocity:
				velocity = 0.0
			else:
				velocity -= friction_force

			position += velocity * delta

		return position


# ============================================================================
# Constants for testing
# ============================================================================


const FLASHBANG_FRICTION := 300.0
const FRAG_FRICTION := 280.0
const DEFAULT_RAMP_VELOCITY := 200.0
const DEFAULT_MIN_MULT := 0.5
## Tolerance for distance comparison (pixels).
## The analytical formula is approximate; we accept small deviations.
const DISTANCE_TOLERANCE := 10.0
## Relative tolerance (percentage).
const RELATIVE_TOLERANCE := 0.05


# ============================================================================
# Tests: Speed → Distance → Speed round-trip
# ============================================================================


func test_round_trip_short_distance() -> void:
	var target := 50.0
	var speed := ThrowSpeedCalculator.calculate_throw_speed(
		target, FLASHBANG_FRICTION, DEFAULT_RAMP_VELOCITY, DEFAULT_MIN_MULT)
	var distance := ThrowSpeedCalculator.calculate_landing_distance(
		speed, FLASHBANG_FRICTION, DEFAULT_RAMP_VELOCITY, DEFAULT_MIN_MULT)
	assert_almost_eq(distance, target, 0.1,
		"Round-trip should recover original distance for short throw")


func test_round_trip_medium_distance() -> void:
	var target := 400.0
	var speed := ThrowSpeedCalculator.calculate_throw_speed(
		target, FLASHBANG_FRICTION, DEFAULT_RAMP_VELOCITY, DEFAULT_MIN_MULT)
	var distance := ThrowSpeedCalculator.calculate_landing_distance(
		speed, FLASHBANG_FRICTION, DEFAULT_RAMP_VELOCITY, DEFAULT_MIN_MULT)
	assert_almost_eq(distance, target, 0.1,
		"Round-trip should recover original distance for medium throw")


func test_round_trip_long_distance() -> void:
	var target := 1000.0
	var speed := ThrowSpeedCalculator.calculate_throw_speed(
		target, FLASHBANG_FRICTION, DEFAULT_RAMP_VELOCITY, DEFAULT_MIN_MULT)
	var distance := ThrowSpeedCalculator.calculate_landing_distance(
		speed, FLASHBANG_FRICTION, DEFAULT_RAMP_VELOCITY, DEFAULT_MIN_MULT)
	assert_almost_eq(distance, target, 0.1,
		"Round-trip should recover original distance for long throw")


# ============================================================================
# Tests: Formula matches physics simulation
# ============================================================================


func test_simulation_matches_formula_200px() -> void:
	_verify_simulation_accuracy(200.0, FLASHBANG_FRICTION)


func test_simulation_matches_formula_400px() -> void:
	_verify_simulation_accuracy(400.0, FLASHBANG_FRICTION)


func test_simulation_matches_formula_600px() -> void:
	_verify_simulation_accuracy(600.0, FLASHBANG_FRICTION)


func test_simulation_matches_formula_800px() -> void:
	_verify_simulation_accuracy(800.0, FLASHBANG_FRICTION)


func test_simulation_matches_formula_1000px() -> void:
	_verify_simulation_accuracy(1000.0, FLASHBANG_FRICTION)


func test_simulation_frag_grenade_300px() -> void:
	_verify_simulation_accuracy(300.0, FRAG_FRICTION)


func test_simulation_frag_grenade_600px() -> void:
	_verify_simulation_accuracy(600.0, FRAG_FRICTION)


func test_simulation_frag_grenade_1000px() -> void:
	_verify_simulation_accuracy(1000.0, FRAG_FRICTION)


# ============================================================================
# Tests: Speed increases with distance
# ============================================================================


func test_speed_increases_with_distance() -> void:
	var speed_200 := ThrowSpeedCalculator.calculate_throw_speed(
		200.0, FLASHBANG_FRICTION, DEFAULT_RAMP_VELOCITY, DEFAULT_MIN_MULT)
	var speed_500 := ThrowSpeedCalculator.calculate_throw_speed(
		500.0, FLASHBANG_FRICTION, DEFAULT_RAMP_VELOCITY, DEFAULT_MIN_MULT)
	var speed_1000 := ThrowSpeedCalculator.calculate_throw_speed(
		1000.0, FLASHBANG_FRICTION, DEFAULT_RAMP_VELOCITY, DEFAULT_MIN_MULT)
	assert_true(speed_200 < speed_500,
		"Speed for 200px should be less than 500px")
	assert_true(speed_500 < speed_1000,
		"Speed for 500px should be less than 1000px")


# ============================================================================
# Tests: Phase 2 distance is reasonable
# ============================================================================


func test_phase2_distance_is_positive() -> void:
	var avg_mult := DEFAULT_MIN_MULT + 2.0 * (1.0 - DEFAULT_MIN_MULT) / 3.0
	var avg_friction := FLASHBANG_FRICTION * avg_mult
	var phase2_dist := DEFAULT_RAMP_VELOCITY * DEFAULT_RAMP_VELOCITY / (2.0 * avg_friction)
	assert_true(phase2_dist > 0.0,
		"Phase 2 distance should be positive")
	assert_true(phase2_dist < 200.0,
		"Phase 2 distance should be reasonable (< 200px)")


# ============================================================================
# Tests: Short throw (below ramp velocity)
# ============================================================================


func test_short_throw_speed_is_below_ramp_velocity() -> void:
	var speed := ThrowSpeedCalculator.calculate_throw_speed(
		30.0, FLASHBANG_FRICTION, DEFAULT_RAMP_VELOCITY, DEFAULT_MIN_MULT)
	assert_true(speed < DEFAULT_RAMP_VELOCITY,
		"Short throw speed should be below friction ramp velocity")


# ============================================================================
# Tests: Landing distance increases with speed
# ============================================================================


func test_landing_distance_increases_with_speed() -> void:
	var d_200 := ThrowSpeedCalculator.calculate_landing_distance(
		200.0, FLASHBANG_FRICTION, DEFAULT_RAMP_VELOCITY, DEFAULT_MIN_MULT)
	var d_400 := ThrowSpeedCalculator.calculate_landing_distance(
		400.0, FLASHBANG_FRICTION, DEFAULT_RAMP_VELOCITY, DEFAULT_MIN_MULT)
	var d_800 := ThrowSpeedCalculator.calculate_landing_distance(
		800.0, FLASHBANG_FRICTION, DEFAULT_RAMP_VELOCITY, DEFAULT_MIN_MULT)
	assert_true(d_200 < d_400,
		"Landing distance at 200px/s should be less than at 400px/s")
	assert_true(d_400 < d_800,
		"Landing distance at 400px/s should be less than at 800px/s")


# ============================================================================
# Tests: Old formula comparison (Issue #615 regression)
# ============================================================================


func test_old_formula_gives_different_speed() -> void:
	## The old formula v = sqrt(2 * F * d * 1.16) should give a different
	## (typically higher) speed than the correct two-phase formula.
	var target := 500.0
	var old_speed := sqrt(2.0 * FLASHBANG_FRICTION * target * 1.16)
	var new_speed := ThrowSpeedCalculator.calculate_throw_speed(
		target, FLASHBANG_FRICTION, DEFAULT_RAMP_VELOCITY, DEFAULT_MIN_MULT)
	assert_true(abs(old_speed - new_speed) > 50.0,
		"Old and new formulas should give significantly different speeds " +
		"(old=%.1f, new=%.1f)" % [old_speed, new_speed])


func test_new_formula_produces_lower_speed() -> void:
	## With velocity-dependent friction (reduced at high speeds),
	## less initial speed is needed to reach the same distance.
	var target := 500.0
	var old_speed := sqrt(2.0 * FLASHBANG_FRICTION * target * 1.16)
	var new_speed := ThrowSpeedCalculator.calculate_throw_speed(
		target, FLASHBANG_FRICTION, DEFAULT_RAMP_VELOCITY, DEFAULT_MIN_MULT)
	assert_true(new_speed < old_speed,
		"New formula should give lower speed (less friction at high speed) " +
		"(old=%.1f, new=%.1f)" % [old_speed, new_speed])


# ============================================================================
# Tests: Edge cases
# ============================================================================


func test_zero_distance_gives_zero_speed() -> void:
	var speed := ThrowSpeedCalculator.calculate_throw_speed(
		0.0, FLASHBANG_FRICTION, DEFAULT_RAMP_VELOCITY, DEFAULT_MIN_MULT)
	assert_almost_eq(speed, 0.0, 0.1,
		"Zero distance should give zero speed")


func test_very_small_distance() -> void:
	var speed := ThrowSpeedCalculator.calculate_throw_speed(
		1.0, FLASHBANG_FRICTION, DEFAULT_RAMP_VELOCITY, DEFAULT_MIN_MULT)
	assert_true(speed > 0.0, "Very small distance should give positive speed")
	assert_true(speed < 100.0, "Very small distance should give small speed")


func test_zero_speed_gives_zero_distance() -> void:
	var distance := ThrowSpeedCalculator.calculate_landing_distance(
		0.0, FLASHBANG_FRICTION, DEFAULT_RAMP_VELOCITY, DEFAULT_MIN_MULT)
	assert_almost_eq(distance, 0.0, 0.1,
		"Zero speed should give zero distance")


# ============================================================================
# Helper Methods
# ============================================================================


func _verify_simulation_accuracy(target_distance: float, friction: float) -> void:
	## Verify that the calculated speed produces a simulated distance
	## close to the target distance.
	var speed := ThrowSpeedCalculator.calculate_throw_speed(
		target_distance, friction, DEFAULT_RAMP_VELOCITY, DEFAULT_MIN_MULT)
	var simulated := PhysicsSimulator.simulate_distance(
		speed, friction, DEFAULT_MIN_MULT, DEFAULT_RAMP_VELOCITY)

	var error := abs(simulated - target_distance)
	var relative_error := error / target_distance if target_distance > 0 else 0.0

	assert_true(relative_error < RELATIVE_TOLERANCE,
		"Simulated distance (%.1f) should be within %.0f%% of target (%.1f) " % [
			simulated, RELATIVE_TOLERANCE * 100, target_distance] +
		"(error: %.1fpx, %.1f%%). Speed: %.1f" % [error, relative_error * 100, speed])
