extends GutTest
## Unit tests for MuzzleFlashDetectionComponent (Issue #711).
##
## Tests the muzzle flash detection logic for enemy AI suppression fire:
## - Flash detection within FOV
## - Flash detection outside FOV (should not detect)
## - Suppression fire cooldown
## - Line-of-sight requirements
## - Memory decay


var _component: MuzzleFlashDetectionComponent


func before_each() -> void:
	_component = MuzzleFlashDetectionComponent.new()
	_component.debug_logging = false


func after_each() -> void:
	_component = null


## Test that component initializes with correct default values.
func test_initialization() -> void:
	assert_false(_component.detected, "Should not be detected initially")
	assert_eq(_component.flash_position, Vector2.ZERO, "Flash position should be zero")
	assert_eq(_component.estimated_shooter_position, Vector2.ZERO, "Shooter position should be zero")
	assert_true(_component.can_suppress, "Should be able to suppress initially")


## Test flash detection within enemy FOV.
func test_flash_detection_within_fov() -> void:
	var enemy_pos := Vector2(0, 0)
	var enemy_facing := 0.0  # Facing right
	var fov_deg := 100.0
	var fov_enabled := true
	var flash_pos := Vector2(300, 0)  # Directly in front
	var shooter_pos := Vector2(280, 0)

	var detected := _component.check_flash(
		enemy_pos, enemy_facing, fov_deg, fov_enabled,
		flash_pos, shooter_pos, null
	)

	assert_true(detected, "Should detect flash within FOV")
	assert_true(_component.detected, "detected flag should be true")
	assert_eq(_component.flash_position, flash_pos, "Flash position should match")
	assert_eq(_component.estimated_shooter_position, shooter_pos, "Shooter position should match")


## Test flash detection outside enemy FOV.
func test_flash_detection_outside_fov() -> void:
	var enemy_pos := Vector2(0, 0)
	var enemy_facing := 0.0  # Facing right
	var fov_deg := 100.0
	var fov_enabled := true
	var flash_pos := Vector2(-300, 0)  # Behind the enemy
	var shooter_pos := Vector2(-280, 0)

	var detected := _component.check_flash(
		enemy_pos, enemy_facing, fov_deg, fov_enabled,
		flash_pos, shooter_pos, null
	)

	assert_false(detected, "Should not detect flash outside FOV")
	assert_false(_component.detected, "detected flag should be false")


## Test flash detection with FOV disabled (360 degree vision).
func test_flash_detection_fov_disabled() -> void:
	var enemy_pos := Vector2(0, 0)
	var enemy_facing := 0.0  # Facing right
	var fov_deg := 100.0
	var fov_enabled := false  # FOV disabled
	var flash_pos := Vector2(-300, 0)  # Behind the enemy
	var shooter_pos := Vector2(-280, 0)

	var detected := _component.check_flash(
		enemy_pos, enemy_facing, fov_deg, fov_enabled,
		flash_pos, shooter_pos, null
	)

	assert_true(detected, "Should detect flash when FOV is disabled")


## Test flash detection outside max range.
func test_flash_detection_outside_range() -> void:
	var enemy_pos := Vector2(0, 0)
	var enemy_facing := 0.0
	var fov_deg := 100.0
	var fov_enabled := true
	var flash_pos := Vector2(2000, 0)  # Beyond max range
	var shooter_pos := Vector2(1980, 0)

	var detected := _component.check_flash(
		enemy_pos, enemy_facing, fov_deg, fov_enabled,
		flash_pos, shooter_pos, null
	)

	assert_false(detected, "Should not detect flash outside max range")


## Test suppression cooldown.
func test_suppression_cooldown() -> void:
	# Start suppression
	_component.start_suppression()

	assert_false(_component.can_suppress, "Should not be able to suppress after starting")

	# Simulate partial cooldown
	_component.update(1.0)  # 1 second
	assert_false(_component.can_suppress, "Should still be on cooldown after 1 second")

	# Simulate full cooldown
	_component.update(3.0)  # 3 more seconds (total 4, cooldown is 3)
	assert_true(_component.can_suppress, "Should be able to suppress after cooldown")


## Test flash memory decay.
func test_flash_memory_decay() -> void:
	# Detect a flash first
	var enemy_pos := Vector2(0, 0)
	var flash_pos := Vector2(300, 0)
	var shooter_pos := Vector2(280, 0)

	_component.check_flash(enemy_pos, 0.0, 100.0, true, flash_pos, shooter_pos, null)
	assert_true(_component.detected, "Should be detected initially")

	# Simulate partial memory decay
	_component.update(0.3)
	assert_true(_component.detected, "Should still be detected after 0.3 seconds")

	# Simulate full memory decay
	_component.update(0.5)  # Total 0.8 seconds, memory is 0.5
	assert_false(_component.detected, "Should not be detected after memory expires")


## Test suppression range check.
func test_suppression_range_check() -> void:
	var enemy_pos := Vector2(0, 0)

	# Detect a close flash
	var close_flash := Vector2(300, 0)  # Within suppression range
	_component.check_flash(enemy_pos, 0.0, 100.0, true, close_flash, close_flash, null)
	assert_true(_component.is_in_suppression_range(enemy_pos), "Should be in suppression range for close flash")

	# Reset and detect a far flash
	_component.reset()
	var far_flash := Vector2(800, 0)  # Outside suppression range
	_component.check_flash(enemy_pos, 0.0, 100.0, true, far_flash, far_flash, null)
	assert_false(_component.is_in_suppression_range(enemy_pos), "Should not be in suppression range for far flash")


## Test should_suppress conditions.
func test_should_suppress_conditions() -> void:
	var enemy_pos := Vector2(0, 0)
	var flash_pos := Vector2(300, 0)

	# Initially should not suppress (no detection)
	assert_false(_component.should_suppress(), "Should not suppress without detection")

	# Detect a flash
	_component.check_flash(enemy_pos, 0.0, 100.0, true, flash_pos, flash_pos, null)
	assert_true(_component.should_suppress(), "Should suppress after detection")

	# Start suppression (puts on cooldown)
	_component.start_suppression()
	assert_false(_component.should_suppress(), "Should not suppress during cooldown")


## Test reset functionality.
func test_reset() -> void:
	# Set up some state
	var enemy_pos := Vector2(0, 0)
	var flash_pos := Vector2(300, 0)
	_component.check_flash(enemy_pos, 0.0, 100.0, true, flash_pos, flash_pos, null)

	assert_true(_component.detected, "Should be detected before reset")

	# Reset
	_component.reset()

	assert_false(_component.detected, "Should not be detected after reset")
	assert_eq(_component.flash_position, Vector2.ZERO, "Flash position should be zero after reset")
	assert_eq(_component.estimated_shooter_position, Vector2.ZERO, "Shooter position should be zero after reset")


## Test burst count is within expected range.
func test_suppression_burst_count() -> void:
	var burst_count := _component.get_suppression_burst_count()
	assert_gte(burst_count, MuzzleFlashDetectionComponent.SUPPRESSION_BURST_COUNT_MIN, "Burst count should be >= min")
	assert_lte(burst_count, MuzzleFlashDetectionComponent.SUPPRESSION_BURST_COUNT_MAX, "Burst count should be <= max")


## Test suppression inaccuracy value.
func test_suppression_inaccuracy() -> void:
	var inaccuracy := _component.get_suppression_inaccuracy()
	assert_eq(inaccuracy, MuzzleFlashDetectionComponent.SUPPRESSION_INACCURACY, "Should return correct inaccuracy value")


## Test detection confidence constant.
func test_detection_confidence() -> void:
	assert_almost_eq(
		MuzzleFlashDetectionComponent.MUZZLE_FLASH_DETECTION_CONFIDENCE,
		0.72, 0.01,
		"Detection confidence should be 0.72"
	)


## Test flash detection at FOV boundary.
func test_flash_detection_at_fov_boundary() -> void:
	var enemy_pos := Vector2(0, 0)
	var enemy_facing := 0.0  # Facing right
	var fov_deg := 100.0  # 50 degrees each side
	var fov_enabled := true

	# Flash at exactly 50 degrees (should be detected - at boundary)
	var angle_rad := deg_to_rad(45.0)  # Slightly inside FOV
	var flash_pos := Vector2(cos(angle_rad) * 300, sin(angle_rad) * 300)

	var detected := _component.check_flash(
		enemy_pos, enemy_facing, fov_deg, fov_enabled,
		flash_pos, flash_pos, null
	)

	assert_true(detected, "Should detect flash at FOV boundary")

	# Reset and test just outside FOV
	_component.reset()
	angle_rad = deg_to_rad(55.0)  # Just outside FOV
	flash_pos = Vector2(cos(angle_rad) * 300, sin(angle_rad) * 300)

	detected = _component.check_flash(
		enemy_pos, enemy_facing, fov_deg, fov_enabled,
		flash_pos, flash_pos, null
	)

	assert_false(detected, "Should not detect flash just outside FOV")
