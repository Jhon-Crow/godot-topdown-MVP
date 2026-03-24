extends GutTest
## Unit tests for TacticalGroupComponent.
##
## Tests GROUP_RADIUS, MIN_GROUP_SIZE, APPROACH_DISTANCE, UPDATE_INTERVAL
## constants, and angle_diff calculation for tactical group movement.


# ============================================================================
# Mock Classes
# ============================================================================


class MockNode2D:
	var global_position: Vector2 = Vector2.ZERO
	var _instance_id: int = 0

	func _init(pos: Vector2 = Vector2.ZERO, id: int = 0) -> void:
		global_position = pos
		_instance_id = id

	func get_instance_id() -> int:
		return _instance_id


class MockTacticalGroupComponent:
	const GROUP_RADIUS: float = 500.0
	const MIN_GROUP_SIZE: int = 2
	const APPROACH_DISTANCE: float = 160.0
	const CLOSE_RANGE: float = 80.0
	const UPDATE_INTERVAL: float = 0.4

	var enemy: MockNode2D = null
	var _assigned_angle: float = NAN
	var _update_timer: float = 0.0

	func _init(enemy_ref: MockNode2D) -> void:
		enemy = enemy_ref

	## Simplified angle_diff matching the source implementation.
	static func angle_diff(a: float, b: float) -> float:
		var d: float = fmod(abs(a - b), TAU)
		return d if d <= PI else TAU - d

	func get_adjusted_target_simple(player_pos: Vector2, assigned_angle: float) -> Vector2:
		_assigned_angle = assigned_angle

		if is_nan(_assigned_angle):
			return player_pos

		var dist: float = enemy.global_position.distance_to(player_pos)
		if dist <= CLOSE_RANGE:
			return player_pos

		var offset_dir: Vector2 = Vector2.from_angle(_assigned_angle)
		var approach_pos: Vector2 = player_pos + offset_dir * APPROACH_DISTANCE

		var blend: float = clampf((dist - CLOSE_RANGE) / APPROACH_DISTANCE, 0.0, 1.0)
		return player_pos.lerp(approach_pos, blend)


var comp: MockTacticalGroupComponent
var enemy_node: MockNode2D


func before_each() -> void:
	enemy_node = MockNode2D.new(Vector2(300, 0), 1)
	comp = MockTacticalGroupComponent.new(enemy_node)


func after_each() -> void:
	comp = null
	enemy_node = null


# ============================================================================
# Constants Tests
# ============================================================================


func test_group_radius() -> void:
	assert_eq(MockTacticalGroupComponent.GROUP_RADIUS, 500.0,
		"GROUP_RADIUS should be 500.0 pixels")


func test_min_group_size() -> void:
	assert_eq(MockTacticalGroupComponent.MIN_GROUP_SIZE, 2,
		"MIN_GROUP_SIZE should be 2")


func test_approach_distance() -> void:
	assert_eq(MockTacticalGroupComponent.APPROACH_DISTANCE, 160.0,
		"APPROACH_DISTANCE should be 160.0 pixels")


func test_close_range() -> void:
	assert_eq(MockTacticalGroupComponent.CLOSE_RANGE, 80.0,
		"CLOSE_RANGE should be 80.0 pixels")


func test_update_interval() -> void:
	assert_eq(MockTacticalGroupComponent.UPDATE_INTERVAL, 0.4,
		"UPDATE_INTERVAL should be 0.4 seconds")


# ============================================================================
# Angle Diff Calculation Tests
# ============================================================================


func test_angle_diff_same_angle() -> void:
	var result := MockTacticalGroupComponent.angle_diff(1.0, 1.0)

	assert_almost_eq(result, 0.0, 0.001,
		"Same angle should have diff of 0")


func test_angle_diff_opposite_angles() -> void:
	var result := MockTacticalGroupComponent.angle_diff(0.0, PI)

	assert_almost_eq(result, PI, 0.001,
		"Opposite angles should have diff of PI")


func test_angle_diff_quarter_turn() -> void:
	var result := MockTacticalGroupComponent.angle_diff(0.0, PI / 2.0)

	assert_almost_eq(result, PI / 2.0, 0.001,
		"Quarter turn should have diff of PI/2")


func test_angle_diff_wraps_around() -> void:
	# 350 degrees and 10 degrees should be 20 degrees apart, not 340
	var a := deg_to_rad(350.0)
	var b := deg_to_rad(10.0)
	var result := MockTacticalGroupComponent.angle_diff(a, b)

	assert_almost_eq(result, deg_to_rad(20.0), 0.01,
		"Angle diff should wrap around the circle (shortest path)")


func test_angle_diff_negative_angles() -> void:
	var result := MockTacticalGroupComponent.angle_diff(-PI / 4.0, PI / 4.0)

	assert_almost_eq(result, PI / 2.0, 0.001,
		"Should handle negative angles correctly")


func test_angle_diff_symmetric() -> void:
	var diff1 := MockTacticalGroupComponent.angle_diff(0.5, 1.5)
	var diff2 := MockTacticalGroupComponent.angle_diff(1.5, 0.5)

	assert_almost_eq(diff1, diff2, 0.001,
		"Angle diff should be symmetric (a,b) == (b,a)")


func test_angle_diff_full_circle() -> void:
	var result := MockTacticalGroupComponent.angle_diff(0.0, TAU)

	assert_almost_eq(result, 0.0, 0.001,
		"Full circle diff should be 0")


func test_angle_diff_always_positive() -> void:
	var result := MockTacticalGroupComponent.angle_diff(2.0, 1.0)

	assert_true(result >= 0.0,
		"Angle diff should always be non-negative")


func test_angle_diff_max_is_pi() -> void:
	# No angle diff should exceed PI
	for _i in range(20):
		var a := randf() * TAU * 2.0 - TAU
		var b := randf() * TAU * 2.0 - TAU
		var result := MockTacticalGroupComponent.angle_diff(a, b)
		assert_true(result <= PI + 0.001,
			"Angle diff should never exceed PI")


# ============================================================================
# Target Adjustment Tests
# ============================================================================


func test_no_adjustment_when_no_group() -> void:
	var player_pos := Vector2(0, 0)
	var result := comp.get_adjusted_target_simple(player_pos, NAN)

	assert_eq(result, player_pos,
		"Should return player_pos unchanged when no group (NAN angle)")


func test_no_adjustment_in_close_range() -> void:
	enemy_node.global_position = Vector2(50, 0)  # Within CLOSE_RANGE (80)
	var player_pos := Vector2(0, 0)

	var result := comp.get_adjusted_target_simple(player_pos, 0.0)

	assert_eq(result, player_pos,
		"Should return player_pos when within CLOSE_RANGE")


func test_full_offset_at_approach_distance() -> void:
	# Place enemy at CLOSE_RANGE + APPROACH_DISTANCE from player
	var dist := MockTacticalGroupComponent.CLOSE_RANGE + MockTacticalGroupComponent.APPROACH_DISTANCE
	enemy_node.global_position = Vector2(dist, 0)
	var player_pos := Vector2(0, 0)
	var assigned_angle := 0.0  # Offset toward positive X

	var result := comp.get_adjusted_target_simple(player_pos, assigned_angle)

	# At full blend, result should be player_pos + offset_dir * APPROACH_DISTANCE
	var expected := Vector2(MockTacticalGroupComponent.APPROACH_DISTANCE, 0.0)
	assert_almost_eq(result.x, expected.x, 1.0,
		"At full blend distance, offset should be fully applied (x)")
	assert_almost_eq(result.y, expected.y, 1.0,
		"At full blend distance, offset should be fully applied (y)")


func test_partial_blend_in_transition_zone() -> void:
	# Place enemy between CLOSE_RANGE and CLOSE_RANGE + APPROACH_DISTANCE
	var mid_dist := MockTacticalGroupComponent.CLOSE_RANGE + MockTacticalGroupComponent.APPROACH_DISTANCE / 2.0
	enemy_node.global_position = Vector2(mid_dist, 0)
	var player_pos := Vector2(0, 0)

	var result := comp.get_adjusted_target_simple(player_pos, 0.0)

	# blend = (dist - CLOSE_RANGE) / APPROACH_DISTANCE = 0.5
	# result = player_pos.lerp(approach_pos, 0.5)
	var approach_pos := Vector2(MockTacticalGroupComponent.APPROACH_DISTANCE, 0.0)
	var expected := player_pos.lerp(approach_pos, 0.5)
	assert_almost_eq(result.x, expected.x, 1.0,
		"Should partially blend offset in transition zone")


func test_offset_direction_pi_over_2() -> void:
	enemy_node.global_position = Vector2(0, 500)  # Far enough for full blend
	var player_pos := Vector2(0, 0)
	var assigned_angle := PI / 2.0  # Offset toward positive Y

	var result := comp.get_adjusted_target_simple(player_pos, assigned_angle)

	assert_true(result.y > 0.0,
		"With PI/2 angle, offset should be in positive Y direction")


func test_offset_direction_pi() -> void:
	enemy_node.global_position = Vector2(-500, 0)  # Far enough
	var player_pos := Vector2(0, 0)
	var assigned_angle := PI  # Offset toward negative X

	var result := comp.get_adjusted_target_simple(player_pos, assigned_angle)

	assert_true(result.x < 0.0,
		"With PI angle, offset should be in negative X direction")
