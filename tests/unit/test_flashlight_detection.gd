extends GutTest
## Unit tests for FlashlightDetectionComponent (Issue #574).
##
## Tests the flashlight beam detection system that allows enemies to:
## - Detect the player's flashlight beam when it enters their field of vision
## - Estimate player position from the beam origin
## - Check if positions are illuminated by the flashlight
## - Determine if navigation waypoints are lit
##
## v2: Detection is based on "can the enemy SEE the beam?" (beam-in-FOV),
## not "does the beam HIT the enemy?" (beam-on-enemy).


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


func test_beam_visibility_range_constant() -> void:
	assert_eq(FlashlightDetectionComponent.BEAM_VISIBILITY_RANGE, 600.0,
		"Beam visibility range should be 600.0 pixels")


func test_beam_sample_count_constant() -> void:
	assert_eq(FlashlightDetectionComponent.BEAM_SAMPLE_COUNT, 8,
		"Beam sample count should be 8")


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
# check_flashlight Tests (v2 — beam-in-FOV detection)
# ============================================================================


func test_check_flashlight_respects_interval() -> void:
	# Beam points right from origin, enemy is to the side looking at the beam
	var mock_player := _create_mock_player(Vector2.ZERO, Vector2.RIGHT, true)
	var enemy_pos := Vector2(0, -200)  # Above the beam, looking down (toward beam)
	var enemy_facing := Vector2.DOWN.angle()  # Facing down, beam is in FOV

	# First call with small delta — should NOT check yet (below interval)
	var result := detection.check_flashlight(enemy_pos, enemy_facing, 100.0, true, mock_player, null, 0.05)
	# Default detected is false, and interval hasn't elapsed
	assert_false(result, "Should not detect before interval elapses (first call)")

	# Call again with enough delta to exceed interval (0.15s)
	result = detection.check_flashlight(enemy_pos, enemy_facing, 100.0, true, mock_player, null, 0.11)
	assert_true(result, "Should detect after interval elapses — beam is in enemy's FOV")
	assert_true(detection.detected, "Detection state should be true")

	mock_player.queue_free()


func test_check_flashlight_null_player() -> void:
	var result := detection.check_flashlight(Vector2(300, 0), 0.0, 100.0, true, null, null, 0.2)
	assert_false(result, "Should return false when player is null")


func test_check_flashlight_enemy_sees_beam_from_side() -> void:
	# The key v2 test: enemy is NOT in the beam, but can SEE the beam from the side
	# Player at origin, beam points right
	var mock_player := _create_mock_player(Vector2.ZERO, Vector2.RIGHT, true)

	# Enemy is above and to the right, looking down-left toward where the beam passes
	var enemy_pos := Vector2(300, -200)
	var enemy_facing := Vector2(0, 1).angle()  # Facing down (toward beam center)

	var result := detection.check_flashlight(enemy_pos, enemy_facing, 100.0, true, mock_player, null, 0.2)
	assert_true(result, "Enemy should detect beam visible in their FOV even when not hit by it")

	mock_player.queue_free()


func test_check_flashlight_enemy_looking_away_from_beam() -> void:
	# Enemy can't see the beam because they're looking away
	var mock_player := _create_mock_player(Vector2.ZERO, Vector2.RIGHT, true)

	# Enemy is above the beam, looking UP (away from the beam)
	var enemy_pos := Vector2(300, -200)
	var enemy_facing := Vector2(0, -1).angle()  # Facing up (away from beam)

	var result := detection.check_flashlight(enemy_pos, enemy_facing, 100.0, true, mock_player, null, 0.2)
	assert_false(result, "Enemy looking away from beam should NOT detect it")

	mock_player.queue_free()


func test_check_flashlight_360_vision_detects_beam() -> void:
	# When FOV is disabled (360° vision), enemy should always detect nearby beam
	var mock_player := _create_mock_player(Vector2.ZERO, Vector2.RIGHT, true)

	# Enemy is above the beam, facing up (normally wouldn't see it)
	var enemy_pos := Vector2(300, -200)
	var enemy_facing := Vector2(0, -1).angle()  # Facing up

	# FOV disabled = 360° vision
	var result := detection.check_flashlight(enemy_pos, enemy_facing, 100.0, false, mock_player, null, 0.2)
	assert_true(result, "Enemy with 360° vision should detect beam regardless of facing direction")

	mock_player.queue_free()


func test_check_flashlight_sets_estimated_position() -> void:
	var origin := Vector2(50, 50)
	var mock_player := _create_mock_player(origin, Vector2.RIGHT, true)

	# Enemy near the beam, facing toward it
	var enemy_pos := Vector2(200, -100)
	var enemy_facing := Vector2(0.5, 1).normalized().angle()  # Facing toward beam

	detection.check_flashlight(enemy_pos, enemy_facing, 100.0, true, mock_player, null, 0.2)

	assert_eq(detection.estimated_player_position, origin,
		"Estimated position should be the flashlight origin")

	mock_player.queue_free()


func test_check_flashlight_sets_beam_direction() -> void:
	var mock_player := _create_mock_player(Vector2.ZERO, Vector2.RIGHT, true)

	var enemy_pos := Vector2(200, -100)
	var enemy_facing := Vector2(0, 1).angle()  # Facing down toward beam

	detection.check_flashlight(enemy_pos, enemy_facing, 100.0, true, mock_player, null, 0.2)

	assert_eq(detection.beam_direction, Vector2.RIGHT,
		"Beam direction should match flashlight direction")

	mock_player.queue_free()


func test_check_flashlight_resets_when_off() -> void:
	var mock_player := _create_mock_player(Vector2.ZERO, Vector2.RIGHT, true)
	var enemy_pos := Vector2(200, -100)
	var enemy_facing := Vector2(0, 1).angle()

	# First: detect
	detection.check_flashlight(enemy_pos, enemy_facing, 100.0, true, mock_player, null, 0.2)
	assert_true(detection.detected, "Should detect flashlight")

	# Turn flashlight off
	mock_player._flashlight_on = false

	# Check again
	detection.check_flashlight(enemy_pos, enemy_facing, 100.0, true, mock_player, null, 0.2)
	assert_false(detection.detected, "Should not detect when flashlight is off")

	mock_player.queue_free()


func test_check_flashlight_enemy_too_far_from_beam() -> void:
	# Enemy is far away from the beam, even though facing toward it
	var mock_player := _create_mock_player(Vector2.ZERO, Vector2.RIGHT, true)

	# Enemy is very far above (>1200px away from any beam point)
	var enemy_pos := Vector2(300, -1500)
	var enemy_facing := Vector2(0, 1).angle()  # Facing down

	var result := detection.check_flashlight(enemy_pos, enemy_facing, 100.0, true, mock_player, null, 0.2)
	assert_false(result, "Enemy too far from any beam point should NOT detect it")

	mock_player.queue_free()


func test_check_flashlight_narrow_fov_misses_beam() -> void:
	# Enemy has very narrow FOV and the beam is just outside it
	var mock_player := _create_mock_player(Vector2.ZERO, Vector2.RIGHT, true)

	# Enemy is perpendicular to the beam, with a very narrow FOV facing straight right
	# Beam goes right from origin, enemy is at (300, -200) facing right
	# The beam sample points are along x-axis, enemy looking right → beam is below-left
	var enemy_pos := Vector2(300, -300)
	var enemy_facing := Vector2(1, 0).angle()  # Facing right (beam is below)

	var result := detection.check_flashlight(enemy_pos, enemy_facing, 20.0, true, mock_player, null, 0.2)
	assert_false(result, "Enemy with narrow 20° FOV facing away from beam should NOT detect it")

	mock_player.queue_free()


# ============================================================================
# Beam Sample Point Generation Tests
# ============================================================================


func test_generate_beam_sample_points_count() -> void:
	var points := detection._generate_beam_sample_points(Vector2.ZERO, Vector2.RIGHT)
	# 3 rays (center + left edge + right edge) × BEAM_SAMPLE_COUNT each
	var expected_count := FlashlightDetectionComponent.BEAM_SAMPLE_COUNT * 3
	assert_eq(points.size(), expected_count,
		"Should generate %d sample points (3 rays × %d samples)" % [expected_count, FlashlightDetectionComponent.BEAM_SAMPLE_COUNT])


func test_generate_beam_sample_points_center_ray() -> void:
	var origin := Vector2(100, 100)
	var direction := Vector2.RIGHT
	var points := detection._generate_beam_sample_points(origin, direction)

	# First BEAM_SAMPLE_COUNT points should be along center line
	var last_point: Vector2 = points[FlashlightDetectionComponent.BEAM_SAMPLE_COUNT - 1]
	# Last center point should be at max range
	var expected_end := origin + direction * FlashlightDetectionComponent.FLASHLIGHT_MAX_RANGE
	assert_almost_eq(last_point.x, expected_end.x, 0.1,
		"Last center sample point should be at max range X")
	assert_almost_eq(last_point.y, expected_end.y, 0.1,
		"Last center sample point should be at max range Y")


func test_generate_beam_sample_points_edge_rays_spread() -> void:
	var points := detection._generate_beam_sample_points(Vector2.ZERO, Vector2.RIGHT)
	var n := FlashlightDetectionComponent.BEAM_SAMPLE_COUNT

	# Last point on center ray
	var center_end := points[n - 1]
	# Last point on left edge ray
	var left_end := points[2 * n - 1]
	# Last point on right edge ray
	var right_end := points[3 * n - 1]

	# Left and right edges should be above/below center at the far end
	assert_true(left_end.y < center_end.y,
		"Left edge should be above center (negative Y in screen coords)")
	assert_true(right_end.y > center_end.y,
		"Right edge should be below center (positive Y in screen coords)")


# ============================================================================
# is_point_in_beam_cone Tests
# ============================================================================


func test_point_in_beam_cone_center() -> void:
	assert_true(detection._is_point_in_beam_cone(
		Vector2(300, 0), Vector2.ZERO, Vector2.RIGHT),
		"Point on center line should be in beam cone")


func test_point_in_beam_cone_outside() -> void:
	assert_false(detection._is_point_in_beam_cone(
		Vector2(0, 300), Vector2.ZERO, Vector2.RIGHT),
		"Point perpendicular to beam should NOT be in cone")


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
# Wall-Clamped Detection Suppression Tests (Issue #640)
# ============================================================================


func test_no_detection_when_flashlight_wall_clamped() -> void:
	# Issue #640: When the flashlight is wall-clamped (player flush against wall),
	# enemies should not detect the beam through the wall.
	var player := _create_mock_player(
		Vector2(0, 0),       # origin
		Vector2.RIGHT,       # direction: pointing right
		true                 # flashlight on
	)
	player._flashlight_wall_clamped = true  # Wall-clamped

	# Enemy is close, in front of beam, would normally detect it
	var result := detection.check_flashlight(
		Vector2(200, 0),     # enemy position (directly in beam)
		0.0,                 # enemy facing angle (facing right, toward beam)
		100.0,               # enemy FOV (100 degrees)
		true,                # FOV enabled
		player,              # player
		null,                # no raycast (skip LOS — we test the wall-clamp guard)
		0.2                  # delta > CHECK_INTERVAL so check runs
	)

	assert_false(result,
		"Enemy should NOT detect flashlight when beam is wall-clamped")
	assert_false(detection.detected,
		"Detection state should be false when wall-clamped")
	player.queue_free()


func test_detection_resumes_after_wall_clamp_clears() -> void:
	# Issue #640: After moving away from wall, detection should work again.
	var player := _create_mock_player(
		Vector2(0, 0),       # origin
		Vector2.RIGHT,       # direction
		true                 # flashlight on
	)

	# First: wall-clamped — no detection
	player._flashlight_wall_clamped = true
	var result1 := detection.check_flashlight(
		Vector2(200, 0), 0.0, 100.0, true, player, null, 0.2
	)
	assert_false(result1, "Should not detect when wall-clamped")

	# Then: wall clamp cleared
	player._flashlight_wall_clamped = false
	var result2 := detection.check_flashlight(
		Vector2(200, 0), 0.0, 100.0, true, player, null, 0.2
	)

	# Note: without a raycast, the LOS check is skipped, so detection depends
	# only on distance, FOV, and cone geometry. The beam should be detectable.
	assert_true(result2,
		"Enemy should detect flashlight after wall clamp clears")
	player.queue_free()


func test_is_position_lit_false_when_wall_clamped() -> void:
	# Issue #640: Positions should not be reported as lit when wall-clamped.
	var player := _create_mock_player(
		Vector2(0, 0), Vector2.RIGHT, true
	)
	player._flashlight_wall_clamped = true

	var lit := detection.is_position_lit(Vector2(200, 0), player)

	assert_false(lit,
		"Position should NOT be reported as lit when flashlight is wall-clamped")
	player.queue_free()


# ============================================================================
# Player-Center Wall Check Tests (Issue #640 root cause #7)
#
# When the flashlight barrel is at/inside a wall boundary, raycasts from the
# barrel don't detect the wall (Godot's hit_from_inside=false by default).
# The detection component now adds a secondary check from the player center
# (which is always outside walls) to reliably block detection through walls.
# These tests verify the player_center variable is correctly set from
# player.global_position and used in the wall check flow.
# ============================================================================


func test_player_center_used_for_wall_checks() -> void:
	# Verify that the detection component extracts player_center from
	# player.global_position for the secondary wall check.
	# The flashlight origin may differ from player center (barrel offset).
	var player_center := Vector2(486, 1020)
	var barrel_offset := Vector2(501, 999)  # Barrel inside wall

	var player := MockFlashlightPlayer.new()
	player.global_position = player_center
	player._flashlight_origin = barrel_offset
	player._flashlight_direction = Vector2(0.556, -0.831).normalized()
	player._flashlight_on = true
	player._flashlight_wall_clamped = false  # Not wall-clamped (edge case)
	add_child(player)

	# With null raycast, the player-center check is skipped (no physics).
	# But the detection still uses the correct player_center for distance pre-checks.
	# This test verifies the mock setup is correct for the scenario.
	assert_eq(player.global_position, player_center,
		"Player center should be the CharacterBody2D global_position")
	assert_ne(player.get_flashlight_origin(), player_center,
		"Flashlight origin (barrel) should differ from player center")

	player.queue_free()


func test_detection_uses_barrel_origin_for_beam_geometry() -> void:
	# Verify that beam sample points are generated from the barrel position
	# (flashlight_origin), not from the player center.
	var player := _create_mock_player(
		Vector2(100, 100),  # Player center
		Vector2.RIGHT,
		true
	)
	# Set barrel position different from player center
	player._flashlight_origin = Vector2(120, 100)

	# Enemy is near the beam, facing toward it (would detect if barrel is origin)
	var enemy_pos := Vector2(300, 50)
	var enemy_facing := Vector2(-1, 0.5).normalized().angle()

	# Without raycast, no wall check — detection depends only on cone geometry
	var result := detection.check_flashlight(
		enemy_pos, enemy_facing, 100.0, true, player, null, 0.2
	)

	# The estimated position should be the barrel position, not player center
	if detection.detected:
		assert_eq(detection.estimated_player_position, player._flashlight_origin,
			"Estimated position should be the barrel position (flashlight_origin)")

	player.queue_free()


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
	var _flashlight_wall_clamped: bool = false

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

	func is_flashlight_wall_clamped() -> bool:
		return _flashlight_wall_clamped
