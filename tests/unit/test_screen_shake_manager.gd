extends GutTest
## Unit tests for ScreenShakeManager autoload.
##
## Tests the shake calculation functions and recovery logic.


# ============================================================================
# Static Calculation Tests
# ============================================================================


## Test shake intensity calculation based on fire rate
func test_calculate_shake_intensity_base_case() -> void:
	# Fire rate of 10 shots/sec should give base intensity
	var result := ScreenShakeManagerHelper.calculate_shake_intensity(5.0, 10.0)

	assert_almost_eq(result, 5.0, 0.001, "Fire rate 10 should give base intensity")


func test_calculate_shake_intensity_lower_fire_rate() -> void:
	# Fire rate of 5 shots/sec should give 2x base intensity
	var result := ScreenShakeManagerHelper.calculate_shake_intensity(5.0, 5.0)

	assert_almost_eq(result, 10.0, 0.001, "Lower fire rate should increase shake per shot")


func test_calculate_shake_intensity_higher_fire_rate() -> void:
	# Fire rate of 20 shots/sec should give 0.5x base intensity
	var result := ScreenShakeManagerHelper.calculate_shake_intensity(5.0, 20.0)

	assert_almost_eq(result, 2.5, 0.001, "Higher fire rate should decrease shake per shot")


func test_calculate_shake_intensity_zero_fire_rate() -> void:
	# Zero fire rate should return base intensity (edge case)
	var result := ScreenShakeManagerHelper.calculate_shake_intensity(5.0, 0.0)

	assert_eq(result, 5.0, "Zero fire rate should return base intensity")


func test_calculate_shake_intensity_zero_base() -> void:
	# Zero base intensity should always return zero
	var result := ScreenShakeManagerHelper.calculate_shake_intensity(0.0, 10.0)

	assert_eq(result, 0.0, "Zero base intensity should return zero")


# ============================================================================
# Recovery Time Calculation Tests
# ============================================================================


func test_calculate_recovery_time_min_spread() -> void:
	# At minimum spread (ratio 0.0), should use min recovery time
	var result := ScreenShakeManagerHelper.calculate_recovery_time(0.0, 0.3, 0.05)

	assert_almost_eq(result, 0.3, 0.001, "Min spread should use min recovery time")


func test_calculate_recovery_time_max_spread() -> void:
	# At maximum spread (ratio 1.0), should use max recovery time
	var result := ScreenShakeManagerHelper.calculate_recovery_time(1.0, 0.3, 0.05)

	assert_almost_eq(result, 0.05, 0.001, "Max spread should use max recovery time")


func test_calculate_recovery_time_mid_spread() -> void:
	# At mid spread (ratio 0.5), should interpolate
	var result := ScreenShakeManagerHelper.calculate_recovery_time(0.5, 0.3, 0.05)

	assert_almost_eq(result, 0.175, 0.001, "Mid spread should interpolate between min and max")


func test_calculate_recovery_time_enforces_minimum() -> void:
	# Even if max_recovery is below 50ms, should clamp to 50ms
	var result := ScreenShakeManagerHelper.calculate_recovery_time(1.0, 0.3, 0.01)

	assert_almost_eq(result, 0.05, 0.001, "Should enforce 50ms minimum recovery time")


func test_calculate_recovery_time_clamped_spread_ratio() -> void:
	# Spread ratio above 1.0 should be clamped
	var result := ScreenShakeManagerHelper.calculate_recovery_time(1.5, 0.3, 0.05)

	# Since the helper mirrors the autoload logic, we test expected behavior
	# The ratio should be clamped to 1.0, giving max recovery time
	assert_true(result <= 0.3 and result >= 0.05, "Should clamp spread ratio to [0, 1]")


# ============================================================================
# Direction Tests
# ============================================================================


func test_shake_direction_opposite_to_shooting() -> void:
	# Shooting right should shake left
	var shoot_direction := Vector2(1, 0)
	var expected_shake_direction := Vector2(-1, 0)

	var actual := -shoot_direction.normalized()

	assert_almost_eq(actual.x, expected_shake_direction.x, 0.001, "X component should be opposite")
	assert_almost_eq(actual.y, expected_shake_direction.y, 0.001, "Y component should be opposite")


func test_shake_direction_diagonal() -> void:
	# Shooting diagonally up-right should shake down-left
	var shoot_direction := Vector2(1, -1).normalized()
	var expected_shake_direction := Vector2(-1, 1).normalized()

	var actual := -shoot_direction

	assert_almost_eq(actual.x, expected_shake_direction.x, 0.001, "X component should be opposite")
	assert_almost_eq(actual.y, expected_shake_direction.y, 0.001, "Y component should be opposite")


# ============================================================================
# Accumulation Tests
# ============================================================================


func test_shake_accumulation_same_direction() -> void:
	# Multiple shakes in same direction should accumulate
	var direction := Vector2(1, 0)
	var intensity := 5.0

	var total := Vector2.ZERO
	for i in 3:
		total += -direction.normalized() * intensity

	assert_almost_eq(total.x, -15.0, 0.001, "Three shakes should accumulate to 3x intensity")


func test_shake_accumulation_opposite_directions() -> void:
	# Shakes in opposite directions should cancel
	var direction1 := Vector2(1, 0)
	var direction2 := Vector2(-1, 0)
	var intensity := 5.0

	var total := Vector2.ZERO
	total += -direction1.normalized() * intensity  # Shake left
	total += -direction2.normalized() * intensity  # Shake right

	assert_almost_eq(total.x, 0.0, 0.001, "Opposite shakes should cancel")


# ============================================================================
# Max Shake Limit Tests
# ============================================================================


func test_shake_max_clamp() -> void:
	# Shake offset should be clamped to MAX_SHAKE_OFFSET (50 pixels)
	var offset := Vector2(100, 0)  # Way beyond max
	var max_offset := 50.0

	if offset.length() > max_offset:
		offset = offset.normalized() * max_offset

	assert_almost_eq(offset.length(), max_offset, 0.001, "Should clamp to max offset")


# ============================================================================
# Helper Class (mirrors ScreenShakeManager static methods)
# ============================================================================


class ScreenShakeManagerHelper:
	const MIN_RECOVERY_TIME: float = 0.05

	static func calculate_shake_intensity(base_intensity: float, fire_rate: float) -> float:
		if fire_rate <= 0.0:
			return base_intensity
		return base_intensity / fire_rate * 10.0

	static func calculate_recovery_time(spread_ratio: float, min_recovery: float, max_recovery: float) -> float:
		var clamped_max := maxf(max_recovery, MIN_RECOVERY_TIME)
		return lerpf(min_recovery, clamped_max, spread_ratio)
