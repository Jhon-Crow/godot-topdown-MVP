extends GutTest
## Unit tests for MuzzleFlashDetectionComponent.
##
## Tests MUZZLE_FLASH_DETECTION_CONFIDENCE, MUZZLE_FLASH_MAX_RANGE,
## FLASH_MAX_AGE, CHECK_INTERVAL constants, and detection state management.


# ============================================================================
# Mock MuzzleFlashDetectionComponent for Logic Tests
# ============================================================================


class MockMuzzleFlashDetectionComponent:
	const MUZZLE_FLASH_DETECTION_CONFIDENCE: float = 0.65
	const MUZZLE_FLASH_MAX_RANGE: float = 500.0
	const FLASH_MAX_AGE: float = 0.35
	const CHECK_INTERVAL: float = 0.1

	var _check_timer: float = 0.0
	var detected: bool = false
	var estimated_player_position: Vector2 = Vector2.ZERO
	var flash_direction: Vector2 = Vector2.ZERO
	var flash_position: Vector2 = Vector2.ZERO

	func reset() -> void:
		detected = false
		estimated_player_position = Vector2.ZERO
		flash_direction = Vector2.ZERO
		flash_position = Vector2.ZERO
		_check_timer = 0.0

	func simulate_check_timer(delta: float) -> bool:
		_check_timer += delta
		if _check_timer < CHECK_INTERVAL:
			return false
		_check_timer = 0.0
		return true

	## Simulate detection of a muzzle flash.
	func simulate_detection(
			enemy_pos: Vector2,
			enemy_facing_dir: Vector2,
			enemy_fov_deg: float,
			enemy_fov_enabled: bool,
			f_pos: Vector2,
			f_dir: Vector2,
			f_age: float,
			can_see_player: bool,
			has_los: bool) -> bool:
		detected = false
		estimated_player_position = Vector2.ZERO
		flash_direction = Vector2.ZERO
		flash_position = Vector2.ZERO

		# Only detect when player is NOT visible
		if can_see_player:
			return false

		# Age check
		if f_age > FLASH_MAX_AGE:
			return false

		# Distance check
		var dist := enemy_pos.distance_to(f_pos)
		if dist > MUZZLE_FLASH_MAX_RANGE:
			return false

		# FOV check
		if enemy_fov_enabled and enemy_fov_deg > 0.0:
			var fov_half_angle_rad := deg_to_rad(enemy_fov_deg / 2.0)
			var dir_to_flash := (f_pos - enemy_pos).normalized()
			if enemy_facing_dir.dot(dir_to_flash) < cos(fov_half_angle_rad):
				return false

		# LOS check
		if not has_los:
			return false

		# Detection confirmed
		detected = true
		flash_position = f_pos
		flash_direction = f_dir
		estimated_player_position = f_pos - f_dir * 30.0
		return true


var comp: MockMuzzleFlashDetectionComponent


func before_each() -> void:
	comp = MockMuzzleFlashDetectionComponent.new()


func after_each() -> void:
	comp = null


# ============================================================================
# Constants Tests
# ============================================================================


func test_muzzle_flash_detection_confidence() -> void:
	assert_eq(MockMuzzleFlashDetectionComponent.MUZZLE_FLASH_DETECTION_CONFIDENCE, 0.65,
		"MUZZLE_FLASH_DETECTION_CONFIDENCE should be 0.65")


func test_muzzle_flash_max_range() -> void:
	assert_eq(MockMuzzleFlashDetectionComponent.MUZZLE_FLASH_MAX_RANGE, 500.0,
		"MUZZLE_FLASH_MAX_RANGE should be 500.0")


func test_flash_max_age() -> void:
	assert_eq(MockMuzzleFlashDetectionComponent.FLASH_MAX_AGE, 0.35,
		"FLASH_MAX_AGE should be 0.35")


func test_check_interval() -> void:
	assert_eq(MockMuzzleFlashDetectionComponent.CHECK_INTERVAL, 0.1,
		"CHECK_INTERVAL should be 0.1")


# ============================================================================
# Detection State Tests
# ============================================================================


func test_default_not_detected() -> void:
	assert_false(comp.detected,
		"Should not be detected by default")


func test_default_estimated_position_zero() -> void:
	assert_eq(comp.estimated_player_position, Vector2.ZERO)


func test_default_flash_direction_zero() -> void:
	assert_eq(comp.flash_direction, Vector2.ZERO)


func test_default_flash_position_zero() -> void:
	assert_eq(comp.flash_position, Vector2.ZERO)


func test_reset_clears_all_state() -> void:
	comp.detected = true
	comp.estimated_player_position = Vector2(100, 200)
	comp.flash_direction = Vector2.RIGHT
	comp.flash_position = Vector2(50, 50)
	comp._check_timer = 0.08

	comp.reset()

	assert_false(comp.detected)
	assert_eq(comp.estimated_player_position, Vector2.ZERO)
	assert_eq(comp.flash_direction, Vector2.ZERO)
	assert_eq(comp.flash_position, Vector2.ZERO)
	assert_eq(comp._check_timer, 0.0)


# ============================================================================
# Check Interval Tests
# ============================================================================


func test_check_timer_below_interval() -> void:
	assert_false(comp.simulate_check_timer(0.05),
		"Should not trigger check before interval")


func test_check_timer_at_interval() -> void:
	assert_true(comp.simulate_check_timer(0.1),
		"Should trigger check at interval")


func test_check_timer_accumulates() -> void:
	comp.simulate_check_timer(0.03)
	comp.simulate_check_timer(0.03)
	var result := comp.simulate_check_timer(0.04)

	assert_true(result,
		"Timer should accumulate to trigger check")


func test_check_timer_resets_after_trigger() -> void:
	comp.simulate_check_timer(0.1)

	assert_eq(comp._check_timer, 0.0,
		"Timer should reset after triggering")


# ============================================================================
# Detection Logic Tests
# ============================================================================


func test_detect_flash_in_range_and_fov() -> void:
	var result := comp.simulate_detection(
		Vector2(0, 0),       # enemy_pos
		Vector2.RIGHT,       # enemy_facing_dir
		100.0,               # enemy_fov_deg
		true,                # fov_enabled
		Vector2(200, 0),     # flash_pos
		Vector2.RIGHT,       # flash_dir
		0.1,                 # flash_age
		false,               # can_see_player
		true                 # has_los
	)

	assert_true(result, "Should detect flash in range, FOV, and LOS")
	assert_true(comp.detected)


func test_no_detect_when_player_visible() -> void:
	var result := comp.simulate_detection(
		Vector2(0, 0), Vector2.RIGHT, 100.0, true,
		Vector2(200, 0), Vector2.RIGHT, 0.1,
		true,  # can_see_player
		true
	)

	assert_false(result,
		"Should not detect flash when player is directly visible")


func test_no_detect_when_flash_too_old() -> void:
	var result := comp.simulate_detection(
		Vector2(0, 0), Vector2.RIGHT, 100.0, true,
		Vector2(200, 0), Vector2.RIGHT, 0.5,  # > FLASH_MAX_AGE
		false, true
	)

	assert_false(result,
		"Should not detect flash older than FLASH_MAX_AGE")


func test_no_detect_when_out_of_range() -> void:
	var result := comp.simulate_detection(
		Vector2(0, 0), Vector2.RIGHT, 100.0, true,
		Vector2(600, 0), Vector2.RIGHT, 0.1,  # > MUZZLE_FLASH_MAX_RANGE
		false, true
	)

	assert_false(result,
		"Should not detect flash beyond MUZZLE_FLASH_MAX_RANGE")


func test_no_detect_when_outside_fov() -> void:
	var result := comp.simulate_detection(
		Vector2(0, 0),
		Vector2.RIGHT,       # facing right
		60.0,                # narrow 60-degree FOV
		true,
		Vector2(-200, 0),    # flash behind enemy
		Vector2.LEFT, 0.1,
		false, true
	)

	assert_false(result,
		"Should not detect flash outside enemy FOV")


func test_no_detect_when_no_los() -> void:
	var result := comp.simulate_detection(
		Vector2(0, 0), Vector2.RIGHT, 100.0, true,
		Vector2(200, 0), Vector2.RIGHT, 0.1,
		false,
		false  # no LOS
	)

	assert_false(result,
		"Should not detect flash without line of sight")


func test_estimated_position_offset_from_flash() -> void:
	comp.simulate_detection(
		Vector2(0, 0), Vector2.RIGHT, 100.0, true,
		Vector2(200, 0), Vector2.RIGHT, 0.1,
		false, true
	)

	# estimated_player_position = flash_pos - flash_dir * 30
	assert_eq(comp.estimated_player_position, Vector2(170, 0),
		"Estimated position should be 30px behind flash in opposite of flash direction")


func test_detect_with_fov_disabled() -> void:
	var result := comp.simulate_detection(
		Vector2(0, 0),
		Vector2.RIGHT,
		100.0,
		false,               # FOV disabled — 360 vision
		Vector2(-200, 0),    # flash behind enemy
		Vector2.LEFT, 0.1,
		false, true
	)

	assert_true(result,
		"Should detect flash from any direction when FOV is disabled")


func test_detect_at_max_age_boundary() -> void:
	var result := comp.simulate_detection(
		Vector2(0, 0), Vector2.RIGHT, 100.0, true,
		Vector2(200, 0), Vector2.RIGHT, 0.35,  # exactly FLASH_MAX_AGE
		false, true
	)

	assert_true(result,
		"Should detect flash at exactly FLASH_MAX_AGE")
