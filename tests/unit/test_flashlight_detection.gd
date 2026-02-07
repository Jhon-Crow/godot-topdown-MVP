extends GutTest
## Unit tests for FlashlightDetectionComponent (Issue #574).
##
## Tests the flashlight beam detection system that allows enemies to:
## - Detect the player's flashlight beam via cone intersection test
## - Estimate player position from the beam origin
## - Check if positions are illuminated by the flashlight
## - Determine if navigation waypoints are lit


var detection: FlashlightDetectionComponent


func before_each() -> void:
	detection = FlashlightDetectionComponent.new()


func after_each() -> void:
	detection = null


# ============================================================================
# Constants Tests
# ============================================================================


func test_flashlight_confidence_constant() -> void:
	assert_eq(FlashlightDetectionComponent.FLASHLIGHT_DETECTION_CONFIDENCE, 0.75,
		"Flashlight detection confidence should be 0.75")


func test_flashlight_max_range_constant() -> void:
	assert_eq(FlashlightDetectionComponent.FLASHLIGHT_MAX_RANGE, 600.0,
		"Max detection range should be 600.0 pixels")


func test_beam_half_angle_constant() -> void:
	assert_eq(FlashlightDetectionComponent.BEAM_HALF_ANGLE_DEG, 12.0,
		"Beam half-angle should be 12.0 degrees")


func test_check_interval_constant() -> void:
	assert_eq(FlashlightDetectionComponent.CHECK_INTERVAL, 0.15,
		"Check interval should be 0.15 seconds")


# ============================================================================
# Initialization Tests
# ============================================================================


func test_initial_detected_is_false() -> void:
	assert_false(detection.detected,
		"Initial detected state should be false")


func test_initial_estimated_position_is_zero() -> void:
	assert_eq(detection.estimated_player_position, Vector2.ZERO,
		"Initial estimated position should be Vector2.ZERO")


func test_initial_beam_direction_is_zero() -> void:
	assert_eq(detection.beam_direction, Vector2.ZERO,
		"Initial beam direction should be Vector2.ZERO")


# ============================================================================
# Reset Tests
# ============================================================================


func test_reset_clears_detection() -> void:
	detection.detected = true
	detection.estimated_player_position = Vector2(100, 200)
	detection.beam_direction = Vector2.RIGHT

	detection.reset()

	assert_false(detection.detected,
		"Reset should clear detection state")
	assert_eq(detection.estimated_player_position, Vector2.ZERO,
		"Reset should clear estimated position")
	assert_eq(detection.beam_direction, Vector2.ZERO,
		"Reset should clear beam direction")


# ============================================================================
# is_position_lit Tests (cone intersection without LOS)
# ============================================================================


func test_is_position_lit_null_player() -> void:
	assert_false(detection.is_position_lit(Vector2(100, 0), null),
		"Should return false when player is null")


func test_is_position_lit_within_beam_cone() -> void:
	# Create a mock player with flashlight on, pointing right
	var mock_player := _create_mock_player(Vector2.ZERO, Vector2.RIGHT, true)

	# Position directly in front of the beam (within 12-degree half-angle)
	var test_pos := Vector2(300, 0)  # Straight ahead
	assert_true(detection.is_position_lit(test_pos, mock_player),
		"Position directly in beam path should be lit")

	mock_player.queue_free()


func test_is_position_lit_slightly_off_axis() -> void:
	var mock_player := _create_mock_player(Vector2.ZERO, Vector2.RIGHT, true)

	# Position slightly off-axis (about 5 degrees) — should still be in beam
	var test_pos := Vector2(300, 26)  # arctan(26/300) ≈ 5°
	assert_true(detection.is_position_lit(test_pos, mock_player),
		"Position slightly off-axis should be lit (within 12° half-angle)")

	mock_player.queue_free()


func test_is_position_lit_outside_beam_cone() -> void:
	var mock_player := _create_mock_player(Vector2.ZERO, Vector2.RIGHT, true)

	# Position far off-axis (about 45 degrees) — outside beam
	var test_pos := Vector2(300, 300)  # arctan(300/300) = 45°
	assert_false(detection.is_position_lit(test_pos, mock_player),
		"Position at 45° off-axis should NOT be lit")

	mock_player.queue_free()


func test_is_position_lit_behind_flashlight() -> void:
	var mock_player := _create_mock_player(Vector2.ZERO, Vector2.RIGHT, true)

	# Position behind the flashlight
	var test_pos := Vector2(-300, 0)
	assert_false(detection.is_position_lit(test_pos, mock_player),
		"Position behind flashlight should NOT be lit")

	mock_player.queue_free()


func test_is_position_lit_beyond_max_range() -> void:
	var mock_player := _create_mock_player(Vector2.ZERO, Vector2.RIGHT, true)

	# Position beyond max range (600px)
	var test_pos := Vector2(700, 0)
	assert_false(detection.is_position_lit(test_pos, mock_player),
		"Position beyond max range should NOT be lit")

	mock_player.queue_free()


func test_is_position_lit_flashlight_off() -> void:
	var mock_player := _create_mock_player(Vector2.ZERO, Vector2.RIGHT, false)

	var test_pos := Vector2(300, 0)
	assert_false(detection.is_position_lit(test_pos, mock_player),
		"Position should NOT be lit when flashlight is off")

	mock_player.queue_free()


func test_is_position_lit_at_beam_edge() -> void:
	var mock_player := _create_mock_player(Vector2.ZERO, Vector2.RIGHT, true)

	# Position at approximately 11 degrees — just within 12° half-angle
	var angle_rad := deg_to_rad(11.0)
	var test_pos := Vector2(300 * cos(angle_rad), 300 * sin(angle_rad))
	assert_true(detection.is_position_lit(test_pos, mock_player),
		"Position at 11° (just within 12° half-angle) should be lit")

	mock_player.queue_free()


func test_is_position_lit_just_outside_beam_edge() -> void:
	var mock_player := _create_mock_player(Vector2.ZERO, Vector2.RIGHT, true)

	# Position at approximately 15 degrees — outside 12° half-angle
	var angle_rad := deg_to_rad(15.0)
	var test_pos := Vector2(300 * cos(angle_rad), 300 * sin(angle_rad))
	assert_false(detection.is_position_lit(test_pos, mock_player),
		"Position at 15° (outside 12° half-angle) should NOT be lit")

	mock_player.queue_free()


# ============================================================================
# check_flashlight Tests (with interval timing)
# ============================================================================


func test_check_flashlight_respects_interval() -> void:
	var mock_player := _create_mock_player(Vector2.ZERO, Vector2.RIGHT, true)
	var enemy_pos := Vector2(300, 0)

	# First call with small delta — should NOT check yet (below interval)
	var result := detection.check_flashlight(enemy_pos, mock_player, null, 0.05)
	# Default detected is false, and interval hasn't elapsed
	assert_false(result, "Should not detect before interval elapses (first call)")

	# Call again with enough delta to exceed interval (0.15s)
	result = detection.check_flashlight(enemy_pos, mock_player, null, 0.11)
	assert_true(result, "Should detect after interval elapses")
	assert_true(detection.detected, "Detection state should be true")

	mock_player.queue_free()


func test_check_flashlight_null_player() -> void:
	var result := detection.check_flashlight(Vector2(300, 0), null, null, 0.2)
	assert_false(result, "Should return false when player is null")


func test_check_flashlight_sets_estimated_position() -> void:
	var origin := Vector2(50, 50)
	var mock_player := _create_mock_player(origin, Vector2.RIGHT, true)

	detection.check_flashlight(Vector2(350, 50), mock_player, null, 0.2)

	assert_eq(detection.estimated_player_position, origin,
		"Estimated position should be the flashlight origin")

	mock_player.queue_free()


func test_check_flashlight_sets_beam_direction() -> void:
	var mock_player := _create_mock_player(Vector2.ZERO, Vector2.RIGHT, true)

	detection.check_flashlight(Vector2(300, 0), mock_player, null, 0.2)

	assert_eq(detection.beam_direction, Vector2.RIGHT,
		"Beam direction should match flashlight direction")

	mock_player.queue_free()


func test_check_flashlight_resets_when_off() -> void:
	var mock_player := _create_mock_player(Vector2.ZERO, Vector2.RIGHT, true)

	# First: detect
	detection.check_flashlight(Vector2(300, 0), mock_player, null, 0.2)
	assert_true(detection.detected, "Should detect flashlight")

	# Turn flashlight off
	mock_player._flashlight_on = false

	# Check again
	detection.check_flashlight(Vector2(300, 0), mock_player, null, 0.2)
	assert_false(detection.detected, "Should not detect when flashlight is off")

	mock_player.queue_free()


# ============================================================================
# String Representation Tests
# ============================================================================


func test_to_string_no_detection() -> void:
	var result := detection._to_string()
	assert_eq(result, "FlashlightDetection(none)",
		"Should show 'none' when not detected")


func test_to_string_with_detection() -> void:
	detection.detected = true
	detection.estimated_player_position = Vector2(100, 200)
	detection.beam_direction = Vector2.RIGHT

	var result := detection._to_string()
	assert_true(result.begins_with("FlashlightDetection("),
		"Should start with FlashlightDetection(")
	assert_true(result.contains("100"),
		"Should contain the position data")


# ============================================================================
# Helper Methods
# ============================================================================


## Create a mock player node with flashlight methods for testing.
func _create_mock_player(origin: Vector2, direction: Vector2, flashlight_on: bool) -> Node2D:
	var player := MockFlashlightPlayer.new()
	player.global_position = origin
	player._flashlight_origin = origin
	player._flashlight_direction = direction
	player._flashlight_on = flashlight_on
	add_child(player)
	return player


## Mock player class that implements the flashlight API without needing the full Player scene.
class MockFlashlightPlayer extends Node2D:
	var _flashlight_on: bool = false
	var _flashlight_direction: Vector2 = Vector2.RIGHT
	var _flashlight_origin: Vector2 = Vector2.ZERO

	func is_flashlight_on() -> bool:
		return _flashlight_on

	func get_flashlight_direction() -> Vector2:
		if not _flashlight_on:
			return Vector2.ZERO
		return _flashlight_direction

	func get_flashlight_origin() -> Vector2:
		if not _flashlight_on:
			return global_position
		return _flashlight_origin
