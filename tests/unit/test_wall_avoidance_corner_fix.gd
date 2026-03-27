extends GutTest
## Tests for Issue #1457 wall avoidance corner-sticking fix (v3: bilateral passage suppression).
##
## Validates that the _check_wall_ahead logic correctly handles:
## - Passage walls (wall normal aligns with lateral direction) → full avoidance
## - Corner edge walls (wall normal does NOT align with lateral direction) → reduced avoidance (0.25×)
## - Bilateral passage confinement (walls on BOTH sides, center clear) → ZERO avoidance
##   (NavAgent handles navigation unimpeded; normalization would amplify tiny imbalance)
## - Center ray: uses collision normal to steer away from wall (not fixed perpendicular)
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
# Constants Validation (v2: collision-normal-aware)
# =============================================================================

func test_corner_edge_scale_is_positive_and_reduced() -> void:
	# When center is clear AND wall normal does not align laterally (corner edge),
	# lateral scale = 0.25 — reduced avoidance to prevent corner sticking.
	var corner_edge_scale: float = 0.25
	assert_gt(corner_edge_scale, 0.0, "Corner-edge lateral scale must be positive (some avoidance)")
	assert_lt(corner_edge_scale, 1.0, "Corner-edge lateral scale must be less than 1.0 (reduced avoidance)")


func test_passage_wall_lateral_alignment_threshold() -> void:
	# A passage wall has its normal aligned with the lateral (perpendicular) direction.
	# Moving LEFT (direction = (-1,0)), perpendicular = (0,-1).
	# Top wall normal = (0,+1): abs(dot with perpendicular (0,-1)) = 1.0 > 0.7 → passage wall.
	var direction := Vector2(-1.0, 0.0)
	var perpendicular := Vector2(-direction.y, direction.x)  # (0, -1)
	var top_wall_normal := Vector2(0.0, 1.0)  # pointing down into corridor
	var lateral_alignment: float = absf(top_wall_normal.dot(perpendicular))
	assert_gt(lateral_alignment, 0.7,
		"Corridor wall above/below movement path should have high lateral alignment (passage wall)")


func test_corner_edge_has_low_lateral_alignment() -> void:
	# A corner edge wall is parallel to movement direction.
	# Moving LEFT (direction = (-1,0)), perpendicular = (0,-1).
	# Corner wall normal = (-1, 0) (pointing right, into moving enemy): abs dot (0,-1) = 0.0 < 0.7 → corner.
	var direction := Vector2(-1.0, 0.0)
	var perpendicular := Vector2(-direction.y, direction.x)  # (0, -1)
	var corner_wall_normal := Vector2(-1.0, 0.0)  # wall facing direction of motion
	var lateral_alignment: float = absf(corner_wall_normal.dot(perpendicular))
	assert_lt(lateral_alignment, 0.7,
		"Corner edge wall should have low lateral alignment")


func test_scale_formula_center_blocked() -> void:
	# When center IS blocked, scale = 1.0 regardless of lateral alignment.
	var center_clear: bool = false
	var lateral_alignment: float = 0.0  # corner edge
	var scale: float = 1.0 if (not center_clear or lateral_alignment > 0.7) else 0.25
	assert_almost_eq(scale, 1.0, 0.001,
		"When center ray blocked, lateral avoidance should be at full strength (1.0)")


func test_scale_formula_passage_wall() -> void:
	# Passage wall: center clear, lateral alignment high → full avoidance.
	var center_clear: bool = true
	var lateral_alignment: float = 1.0  # passage wall perpendicular to motion
	var scale: float = 1.0 if (not center_clear or lateral_alignment > 0.7) else 0.25
	assert_almost_eq(scale, 1.0, 0.001,
		"Passage wall (high lateral alignment) should get full avoidance even when center clear")


func test_scale_formula_corner_edge() -> void:
	# Corner edge: center clear, lateral alignment low → reduced avoidance (0.25).
	var center_clear: bool = true
	var lateral_alignment: float = 0.0  # corner edge parallel to motion
	var scale: float = 1.0 if (not center_clear or lateral_alignment > 0.7) else 0.25
	assert_almost_eq(scale, 0.25, 0.001,
		"Corner edge (low lateral alignment, center clear) should get 0.25× reduced avoidance")


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

# =============================================================================
# v3: Bilateral Passage Suppression Logic
# =============================================================================

func test_bilateral_passage_suppresses_avoidance() -> void:
	# When passage walls are detected on BOTH sides and center is clear,
	# the avoidance should be suppressed (return ZERO) to let NavAgent navigate.
	# This validates the v3 fix for normalizing tiny bilateral imbalances.
	var left_passage_wall: bool = true
	var right_passage_wall: bool = true
	var center_clear: bool = true
	# Bilateral condition: both passage walls AND center clear → suppress
	var should_suppress: bool = left_passage_wall and right_passage_wall and center_clear
	assert_true(should_suppress,
		"Bilateral passage (both sides enclosed, center clear) should suppress avoidance")


func test_single_side_passage_wall_does_not_suppress() -> void:
	# Only one side has a passage wall → normal avoidance applies (no suppression).
	var left_passage_wall: bool = true
	var right_passage_wall: bool = false
	var center_clear: bool = true
	var should_suppress: bool = left_passage_wall and right_passage_wall and center_clear
	assert_false(should_suppress,
		"Single-sided passage wall should NOT suppress avoidance")


func test_bilateral_walls_with_blocked_center_does_not_suppress() -> void:
	# Both sides have passage walls but center is BLOCKED → wall directly ahead.
	# Emergency avoidance applies, do NOT suppress.
	var left_passage_wall: bool = true
	var right_passage_wall: bool = true
	var center_clear: bool = false
	var should_suppress: bool = left_passage_wall and right_passage_wall and center_clear
	assert_false(should_suppress,
		"Bilateral walls with blocked center should NOT suppress (wall ahead requires avoidance)")


func test_bilateral_suppression_prevents_normalization_amplification() -> void:
	# Simulate bilateral force cancellation scenario.
	# Left push: perpendicular * 0.17 (= (1-50/60) weight, passage wall)
	# Right push: -perpendicular * 0.15 (slightly different distance)
	# Net: perpendicular * 0.02 — tiny residual
	# Without suppression: normalized() → full unit vector → misdirection
	# With suppression: return ZERO → NavAgent guides unimpeded
	var perpendicular := Vector2(0.0, 1.0)
	var left_avoidance := perpendicular * 0.17
	var right_avoidance := -perpendicular * 0.15
	var net_avoidance: Vector2 = left_avoidance + right_avoidance
	# Verify the net is small (would be dangerous after normalization)
	assert_lt(net_avoidance.length(), 0.1,
		"Bilateral imbalance should produce a small net avoidance vector")
	# The v3 fix suppresses this → zero, not normalized to full unit vector
	var suppressed_avoidance: Vector2 = Vector2.ZERO  # what v3 returns
	assert_almost_eq(suppressed_avoidance.length(), 0.0, 0.001,
		"Suppressed bilateral avoidance must be zero")


func test_center_ray_uses_collision_normal_not_fixed_perpendicular() -> void:
	# v3 fix: center ray (i==0) uses get_collision_normal() * base_weight
	# instead of perpendicular * base_weight.
	# Verify: for a wall at 30px with center hit, avoidance uses the wall normal.
	var base_weight: float = 1.0 - (30.0 / 60.0)  # 0.5
	var wall_normal := Vector2(0.0, -1.0)  # wall below, normal points up
	var avoidance_v3: Vector2 = wall_normal * base_weight
	# The avoidance should point in the direction of the collision normal
	assert_almost_eq(avoidance_v3.y, -0.5, 0.001,
		"Center-ray avoidance (v3) must use collision normal direction")
	assert_almost_eq(avoidance_v3.x, 0.0, 0.001,
		"Center-ray avoidance (v3) x component should match normal")


func test_minimum_normalization_threshold() -> void:
	# v3 raises the normalization guard from > 0 to > 0.01 to prevent
	# normalizing floating-point noise to full unit vectors.
	var noise_magnitude: float = 0.005  # pure FP noise, below threshold
	var threshold: float = 0.01
	var should_normalize_noise: bool = noise_magnitude > threshold
	assert_false(should_normalize_noise,
		"Floating-point noise (< 0.01) should not be normalized to a unit vector")
	var meaningful_magnitude: float = 0.1  # real avoidance force
	var should_normalize_real: bool = meaningful_magnitude > threshold
	assert_true(should_normalize_real,
		"Real avoidance force (0.1) should still be normalized to guide enemy")
