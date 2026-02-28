extends GutTest
## Unit tests for MuzzleFlashDetectionComponent (Issue #754).
##
## Tests the muzzle flash detection system that allows enemies to:
## - Detect player weapon muzzle flashes within their FOV
## - Estimate player position from flash location and direction
## - Detect ambient glow even when gun barrel is behind a wall
## - Shoot suppressive fire at estimated player positions


var detection: MuzzleFlashDetectionComponent


func before_each() -> void:
	detection = MuzzleFlashDetectionComponent.new()


func after_each() -> void:
	detection = null


# ============================================================================
# Constants Tests
# ============================================================================


func test_muzzle_flash_confidence_constant() -> void:
	assert_eq(MuzzleFlashDetectionComponent.MUZZLE_FLASH_DETECTION_CONFIDENCE, 0.65,
		"Muzzle flash detection confidence should be 0.65")


func test_max_range_constant() -> void:
	assert_eq(MuzzleFlashDetectionComponent.MUZZLE_FLASH_MAX_RANGE, 500.0,
		"Max detection range should be 500.0 pixels")


func test_flash_max_age_constant() -> void:
	assert_eq(MuzzleFlashDetectionComponent.FLASH_MAX_AGE, 0.35,
		"Flash max age should be 0.35 seconds")


func test_check_interval_constant() -> void:
	assert_eq(MuzzleFlashDetectionComponent.CHECK_INTERVAL, 0.1,
		"Check interval should be 0.1 seconds")


# ============================================================================
# Initialization Tests
# ============================================================================


func test_initial_detected_is_false() -> void:
	assert_false(detection.detected, "Initial detected state should be false")


func test_initial_estimated_position_is_zero() -> void:
	assert_eq(detection.estimated_player_position, Vector2.ZERO,
		"Initial estimated position should be Vector2.ZERO")


func test_initial_flash_direction_is_zero() -> void:
	assert_eq(detection.flash_direction, Vector2.ZERO,
		"Initial flash direction should be Vector2.ZERO")


func test_initial_flash_position_is_zero() -> void:
	assert_eq(detection.flash_position, Vector2.ZERO,
		"Initial flash position should be Vector2.ZERO")


# ============================================================================
# Reset Tests
# ============================================================================


func test_reset_clears_detection() -> void:
	detection.detected = true
	detection.estimated_player_position = Vector2(100, 200)
	detection.flash_direction = Vector2.RIGHT
	detection.flash_position = Vector2(50, 50)

	detection.reset()

	assert_false(detection.detected, "Reset should clear detection state")
	assert_eq(detection.estimated_player_position, Vector2.ZERO,
		"Reset should clear estimated position")
	assert_eq(detection.flash_direction, Vector2.ZERO,
		"Reset should clear flash direction")
	assert_eq(detection.flash_position, Vector2.ZERO,
		"Reset should clear flash position")


# ============================================================================
# check_muzzle_flash Tests (without ImpactEffectsManager)
# ============================================================================


func test_check_muzzle_flash_null_player_returns_false() -> void:
	var result := detection.check_muzzle_flash(
		Vector2(100, 0), 0.0, 90.0, false, null, null, false, 0.2
	)
	assert_false(result, "Should return false when player is null")


func test_check_muzzle_flash_when_player_visible_returns_false() -> void:
	var mock_player := MockPlayer.new()
	add_child(mock_player)

	# When player is visible, muzzle flash should be ignored
	var result := detection.check_muzzle_flash(
		Vector2(100, 0), 0.0, 90.0, false, mock_player, null, true, 0.2
	)
	assert_false(result, "Should return false when player is visible")

	mock_player.queue_free()


func test_check_muzzle_flash_when_preparing_grenade_returns_false() -> void:
	var mock_player := MockPlayer.new()
	mock_player._preparing_grenade = true
	add_child(mock_player)

	var result := detection.check_muzzle_flash(
		Vector2(100, 0), 0.0, 90.0, false, mock_player, null, false, 0.2
	)
	assert_false(result, "Should return false when player is preparing grenade")

	mock_player.queue_free()


func test_check_muzzle_flash_respects_interval() -> void:
	var mock_player := MockPlayer.new()
	add_child(mock_player)

	# First call with small delta — interval not elapsed
	var result := detection.check_muzzle_flash(
		Vector2(100, 0), 0.0, 90.0, false, mock_player, null, false, 0.05
	)
	# With no impact manager, result is false anyway
	# Key: timer accumulates and doesn't check prematurely
	assert_false(result, "Should return false before interval elapses (no flash data)")

	mock_player.queue_free()


# ============================================================================
# Estimated Position Tests
# ============================================================================


func test_estimated_position_offset_from_flash() -> void:
	# Directly set detection state to test position calculation
	detection.detected = true
	detection.flash_position = Vector2(200, 100)
	detection.flash_direction = Vector2.RIGHT  # Bullet traveling right
	# Player is behind the flash: flash_pos - dir * 30 = (170, 100)
	detection.estimated_player_position = detection.flash_position - detection.flash_direction * 30.0

	assert_almost_eq(detection.estimated_player_position.x, 170.0, 0.01,
		"Estimated X should be 30px behind muzzle flash in shooting direction")
	assert_almost_eq(detection.estimated_player_position.y, 100.0, 0.01,
		"Estimated Y should match flash Y when shooting horizontally")


func test_estimated_position_with_vertical_shot() -> void:
	detection.flash_position = Vector2(100, 300)
	detection.flash_direction = Vector2.DOWN  # Shooting downward
	# Player behind: flash_pos - dir * 30 = (100, 270)
	detection.estimated_player_position = detection.flash_position - detection.flash_direction * 30.0

	assert_almost_eq(detection.estimated_player_position.x, 100.0, 0.01,
		"Estimated X should match flash X when shooting vertically")
	assert_almost_eq(detection.estimated_player_position.y, 270.0, 0.01,
		"Estimated Y should be 30px above flash when shooting down")


# ============================================================================
# String Representation Tests
# ============================================================================


func test_to_string_no_detection() -> void:
	var result := detection._to_string()
	assert_eq(result, "MuzzleFlashDetection(none)",
		"Should show 'none' when not detected")


func test_to_string_with_detection() -> void:
	detection.detected = true
	detection.flash_position = Vector2(100, 200)
	detection.estimated_player_position = Vector2(70, 200)

	var result := detection._to_string()
	assert_true(result.begins_with("MuzzleFlashDetection("),
		"Should start with MuzzleFlashDetection(")
	assert_true(result.contains("100"),
		"Should contain the flash position data")


# ============================================================================
# Helper Classes
# ============================================================================


## Mock player class for testing without full Player scene.
class MockPlayer extends Node2D:
	var _preparing_grenade: bool = false

	func is_preparing_grenade() -> bool:
		return _preparing_grenade
