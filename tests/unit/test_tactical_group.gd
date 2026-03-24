extends GutTest
## Unit tests for TacticalGroupComponent (Issue #1287).
##
## Tests group detection, slot assignment, approach-offset calculation, and
## the close-range blend-out logic.  All tests use pure-GDScript mocks — no
## Godot physics or scene tree is needed.


# ============================================================================
# Mock SceneTree / Enemy stubs
# ============================================================================


class MockSceneTree:
	var _enemies: Array = []

	func get_nodes_in_group(_group: String) -> Array:
		return _enemies


class MockEnemy2D:
	var global_position: Vector2 = Vector2.ZERO
	var _tree: MockSceneTree = null
	var _active_state: int = 7  # PURSUING by default

	func get_tree() -> MockSceneTree:
		return _tree

	func get_current_state() -> int:
		return _active_state

	func has_method(method: String) -> bool:
		return method in ["get_current_state"]

	func get_instance_id() -> int:
		# Return a deterministic ID based on position for stable sort in tests.
		return int(global_position.x * 100.0 + global_position.y)

	func get_node_or_null(_path: String) -> Node:
		return null  # No ExperimentalSettings — defaults to enabled


# ============================================================================
# Helpers
# ============================================================================


## Build a TacticalGroupComponent for a mock enemy positioned at (0, 0)
## surrounded by `n_allies` additional mock enemies all within GROUP_RADIUS
## of player_pos.
func _make_group(n_total: int, player_pos: Vector2) -> Array:
	var tree := MockSceneTree.new()
	var members: Array = []

	for i: int in range(n_total):
		var e := MockEnemy2D.new()
		# Spread enemies in a circle around the player so they're all in range.
		var angle: float = TAU * i / n_total
		e.global_position = player_pos + Vector2.from_angle(angle) * 200.0
		e._tree = tree
		members.append(e)

	tree._enemies = members
	return members


# ============================================================================
# Tests: constants sanity
# ============================================================================


func test_group_radius_is_500px() -> void:
	assert_eq(TacticalGroupComponent.GROUP_RADIUS, 500.0,
		"GROUP_RADIUS must be 500 px as specified in issue #1287")


func test_min_group_size_at_least_2() -> void:
	assert_gte(TacticalGroupComponent.MIN_GROUP_SIZE, 2,
		"MIN_GROUP_SIZE must be at least 2 to form a group")


func test_approach_distance_reasonable() -> void:
	assert_gt(TacticalGroupComponent.APPROACH_DISTANCE, 0.0,
		"APPROACH_DISTANCE must be positive")
	assert_lt(TacticalGroupComponent.APPROACH_DISTANCE, TacticalGroupComponent.GROUP_RADIUS,
		"APPROACH_DISTANCE must be less than GROUP_RADIUS")


func test_close_range_less_than_approach_distance() -> void:
	assert_lt(TacticalGroupComponent.CLOSE_RANGE, TacticalGroupComponent.APPROACH_DISTANCE,
		"CLOSE_RANGE should be less than APPROACH_DISTANCE for the blend to work")


func test_update_interval_positive() -> void:
	assert_gt(TacticalGroupComponent.UPDATE_INTERVAL, 0.0,
		"UPDATE_INTERVAL must be positive")


# ============================================================================
# Tests: initial state
# ============================================================================


func test_initial_assigned_angle_is_nan() -> void:
	var comp := TacticalGroupComponent.new(null)
	assert_true(is_nan(comp._assigned_angle),
		"_assigned_angle should be NAN before first group update")


func test_get_adjusted_target_returns_player_pos_when_null_enemy() -> void:
	var comp := TacticalGroupComponent.new(null)
	var player_pos := Vector2(100.0, 200.0)
	var result := comp.get_adjusted_target(player_pos, 0.016)
	assert_eq(result, player_pos,
		"Should return player_pos unchanged when enemy ref is null")


# ============================================================================
# Tests: group detection
# ============================================================================


func test_no_group_formed_with_single_enemy() -> void:
	# Only one enemy in range — group should not form (returns player_pos).
	var members := _make_group(1, Vector2.ZERO)
	var comp := TacticalGroupComponent.new(members[0])
	# Force an update by making the timer negative.
	comp._update_timer = -1.0
	var result := comp.get_adjusted_target(Vector2.ZERO, 0.016)
	assert_eq(result, Vector2.ZERO,
		"Single enemy should not form a group — target unchanged")
	assert_true(is_nan(comp._assigned_angle),
		"_assigned_angle should remain NAN with only one enemy")


func test_group_formed_with_two_enemies() -> void:
	var player_pos := Vector2(500.0, 0.0)
	var members := _make_group(2, player_pos)
	var comp := TacticalGroupComponent.new(members[0])
	comp._update_timer = -1.0
	# Force update by calling with delta large enough to trigger.
	var result := comp.get_adjusted_target(player_pos, 0.5)
	# With 2 enemies in range, a group should form → angle assigned.
	assert_false(is_nan(comp._assigned_angle),
		"_assigned_angle should be set when 2 enemies are within GROUP_RADIUS")


func test_group_formed_with_three_enemies() -> void:
	var player_pos := Vector2(300.0, 300.0)
	var members := _make_group(3, player_pos)
	var comp := TacticalGroupComponent.new(members[0])
	comp._update_timer = -1.0
	comp.get_adjusted_target(player_pos, 0.5)
	assert_false(is_nan(comp._assigned_angle),
		"_assigned_angle should be set when 3 enemies are within GROUP_RADIUS")


# ============================================================================
# Tests: slot uniqueness
# ============================================================================


func test_slot_angles_unique_for_three_members() -> void:
	# Each member should get a distinct slot when 3 enemies form a group.
	var player_pos := Vector2(0.0, 0.0)
	var members := _make_group(3, player_pos)
	var angles: Array[float] = []
	for m: MockEnemy2D in members:
		var comp := TacticalGroupComponent.new(m)
		comp._update_timer = -1.0
		comp.get_adjusted_target(player_pos, 0.5)
		if not is_nan(comp._assigned_angle):
			angles.append(comp._assigned_angle)
	assert_eq(angles.size(), 3, "All 3 members should receive a slot angle")
	# Check all angles are distinct.
	for i: int in range(angles.size()):
		for j: int in range(i + 1, angles.size()):
			assert_ne(angles[i], angles[j],
				"Slot angles must be unique across group members")


# ============================================================================
# Tests: close-range blend-out
# ============================================================================


func test_returns_player_pos_when_within_close_range() -> void:
	var player_pos := Vector2(0.0, 0.0)
	var members := _make_group(2, player_pos)
	# Move member[0] right next to the player (inside CLOSE_RANGE).
	members[0].global_position = Vector2(TacticalGroupComponent.CLOSE_RANGE * 0.5, 0.0)
	var comp := TacticalGroupComponent.new(members[0])
	comp._update_timer = -1.0
	var result := comp.get_adjusted_target(player_pos, 0.5)
	assert_eq(result, player_pos,
		"Within CLOSE_RANGE the target should equal player_pos (no offset)")


func test_offset_applied_outside_close_range() -> void:
	var player_pos := Vector2(0.0, 0.0)
	var members := _make_group(2, player_pos)
	# Move member[0] far enough away that offset should be non-zero.
	members[0].global_position = Vector2(TacticalGroupComponent.APPROACH_DISTANCE * 2.0, 0.0)
	var comp := TacticalGroupComponent.new(members[0])
	comp._update_timer = -1.0
	var result := comp.get_adjusted_target(player_pos, 0.5)
	# Result should differ from player_pos because an offset is applied.
	var changed: bool = result.distance_to(player_pos) > 1.0
	assert_true(changed,
		"Target should be offset from player_pos when outside CLOSE_RANGE")


# ============================================================================
# Tests: angle_diff helper
# ============================================================================


func test_angle_diff_zero_for_equal_angles() -> void:
	var diff := TacticalGroupComponent._angle_diff(0.5, 0.5)
	assert_eq(diff, 0.0, "_angle_diff of equal angles should be 0")


func test_angle_diff_pi_for_opposite_angles() -> void:
	var diff := TacticalGroupComponent._angle_diff(0.0, PI)
	assert_almost_eq(diff, PI, 0.001, "_angle_diff of opposite angles should be PI")


func test_angle_diff_symmetric() -> void:
	var d1 := TacticalGroupComponent._angle_diff(0.1, 0.5)
	var d2 := TacticalGroupComponent._angle_diff(0.5, 0.1)
	assert_almost_eq(d1, d2, 0.001, "_angle_diff should be symmetric")


# ============================================================================
# Tests: debug info
# ============================================================================


func test_debug_info_empty_when_no_group() -> void:
	var comp := TacticalGroupComponent.new(null)
	assert_eq(comp.get_debug_info(), "",
		"debug info should be empty when no group is active")


func test_debug_info_contains_slot_when_group_active() -> void:
	var player_pos := Vector2(0.0, 0.0)
	var members := _make_group(3, player_pos)
	members[0].global_position = Vector2(200.0, 0.0)
	var comp := TacticalGroupComponent.new(members[0])
	comp._update_timer = -1.0
	comp.get_adjusted_target(player_pos, 0.5)
	if not is_nan(comp._assigned_angle):
		var info := comp.get_debug_info()
		assert_true(info.contains("GRP"),
			"debug info should contain 'GRP' when a slot is assigned")
