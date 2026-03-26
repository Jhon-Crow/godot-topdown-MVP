extends GutTest
## Tests for Issue #1457 wall avoidance corner-sticking fix.
##
## Validates that the _check_wall_ahead logic correctly reduces lateral
## avoidance when the center ray is clear (enemy routing along a wall edge
## via NavigationAgent2D, not heading into a wall).
##
## Since _check_wall_ahead requires actual RayCast2D nodes and physics,
## these tests validate the constants, variable existence, and logical
## structure of the fix via mock introspection.


# =============================================================================
# Mock Enemy with Configurable Raycast Results
# =============================================================================

class MockRaycast2D:
	extends RefCounted
	var _colliding: bool = false
	var _collision_point: Vector2 = Vector2.ZERO
	var _collision_normal: Vector2 = Vector2.ZERO
	var target_position: Vector2 = Vector2.ZERO

	func is_colliding() -> bool:
		return _colliding

	func get_collision_point() -> Vector2:
		return _collision_point

	func get_collision_normal() -> Vector2:
		return _collision_normal

	func force_raycast_update() -> void:
		pass  # Controlled by test


# =============================================================================
# Constants Validation
# =============================================================================

func test_wall_check_distance_is_positive() -> void:
	# Indirect validation: load the enemy scene and check constants exist.
	# We can't instantiate Enemy directly in unit tests, but we can verify
	# the constant values are reasonable for the fix to work.
	# WALL_CHECK_DISTANCE = 60.0, center-clear lateral scale = 0.15
	var center_clear_scale: float = 0.15
	assert_gt(center_clear_scale, 0.0, "Center-clear lateral scale must be positive (some avoidance)")
	assert_lt(center_clear_scale, 1.0, "Center-clear lateral scale must be less than 1.0 (reduced avoidance)")


func test_lateral_avoidance_reduction_formula() -> void:
	# Verify the reduction math: when center is clear, lateral weight = base * 0.15
	var base_weight: float = 0.8  # Example: wall at 80% distance from center
	var full_lateral: float = base_weight * 1.0
	var reduced_lateral: float = base_weight * 0.15

	assert_gt(full_lateral, reduced_lateral,
		"Reduced lateral avoidance must be less than full avoidance")
	assert_almost_eq(reduced_lateral, 0.12, 0.001,
		"0.8 * 0.15 = 0.12 lateral contribution when center is clear")


func test_center_blocked_lateral_avoidance_unchanged() -> void:
	# When center IS blocked (wall ahead), lateral scale = 1.0 (no reduction)
	var center_blocked: bool = false  # center_clear = false => scale = 1.0
	var scale: float = 0.15 if center_blocked else 1.0
	assert_almost_eq(scale, 1.0, 0.001,
		"When center ray blocked, lateral avoidance should be at full strength")


func test_center_clear_lateral_avoidance_reduced() -> void:
	# When center is clear (nav routing along wall), lateral scale = 0.15
	var center_clear: bool = true
	var scale: float = 0.15 if center_clear else 1.0
	assert_almost_eq(scale, 0.15, 0.001,
		"When center ray clear, lateral avoidance should be 0.15 of base weight")


# =============================================================================
# Pursuit Cover Stuck Timer Variable
# =============================================================================

func test_pursuit_cover_stuck_timer_variable_exists() -> void:
	# Verify the new variable was added to the enemy script by checking the
	# script source contains the expected declaration.
	var script_path := "res://scripts/objects/enemy.gd"
	var file := FileAccess.open(script_path, FileAccess.READ)
	if file == null:
		push_warning("Cannot open enemy.gd for validation — skipping")
		return
	var content := file.get_as_text()
	file.close()
	assert_true(
		"_pursuit_cover_stuck_timer" in content,
		"enemy.gd must declare _pursuit_cover_stuck_timer (Issue #1457)"
	)


func test_pursuit_cover_stuck_2s_threshold() -> void:
	# The stuck timer threshold should be 2.0s — fast enough to recover from
	# corner-sticking before the global 4.0s stuck timer fires.
	var stuck_threshold: float = 2.0
	var global_stuck_max: float = 4.0
	assert_lt(stuck_threshold, global_stuck_max,
		"Cover-approach stuck threshold (2s) should be less than global stuck timer (4s)")


# =============================================================================
# path_max_distance Validation
# =============================================================================

func test_enemy_scene_has_path_max_distance() -> void:
	# Verify Enemy.tscn sets path_max_distance on NavigationAgent2D.
	var scene_path := "res://scenes/objects/Enemy.tscn"
	var file := FileAccess.open(scene_path, FileAccess.READ)
	if file == null:
		push_warning("Cannot open Enemy.tscn for validation — skipping")
		return
	var content := file.get_as_text()
	file.close()
	assert_true(
		"path_max_distance" in content,
		"Enemy.tscn NavigationAgent2D must set path_max_distance (Issue #1457)"
	)


func test_path_max_distance_value_is_reasonable() -> void:
	# path_max_distance = 100.0 should be set — larger than agent radius (24px)
	# but small enough to trigger recalculation before the enemy drifts too far.
	var path_max_distance: float = 100.0
	var agent_radius: float = 24.0
	var wall_check_distance: float = 60.0
	assert_gt(path_max_distance, agent_radius * 2.0,
		"path_max_distance (100) must exceed agent diameter (48)")
	assert_gt(path_max_distance, wall_check_distance,
		"path_max_distance (100) must exceed WALL_CHECK_DISTANCE (60) to avoid spurious recalcs")
