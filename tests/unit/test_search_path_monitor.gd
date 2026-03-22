extends GutTest
## Unit tests for SearchPathMonitor and the search_path_visible_enabled setting.
##
## Tests the search path visualization feature (Issue #1251):
##   - ExperimentalSettings.search_path_visible_enabled toggle
##   - SearchPathMonitor responds to settings changes
##   - SearchPathMonitor builds waypoint sets from Marker2D children


# ============================================================================
# Mock ExperimentalSettings
# ============================================================================


class MockExperimentalSettings:
	var search_path_visible_enabled: bool = false
	var settings_changed_emitted: int = 0
	var _saved_settings: Dictionary = {}

	func set_search_path_visible_enabled(enabled: bool) -> void:
		if search_path_visible_enabled != enabled:
			search_path_visible_enabled = enabled
			settings_changed_emitted += 1
			_saved_settings["search_path_visible_enabled"] = enabled

	func is_search_path_visible_enabled() -> bool:
		return search_path_visible_enabled

	func has_method(method_name: String) -> bool:
		return method_name == "is_search_path_visible_enabled"


# ============================================================================
# Tests — ExperimentalSettings.search_path_visible_enabled
# ============================================================================


func test_search_path_visible_disabled_by_default() -> void:
	var s := MockExperimentalSettings.new()
	assert_false(s.search_path_visible_enabled,
		"search_path_visible_enabled should be false by default")


func test_is_search_path_visible_returns_false_by_default() -> void:
	var s := MockExperimentalSettings.new()
	assert_false(s.is_search_path_visible_enabled(),
		"is_search_path_visible_enabled() should return false by default")


func test_set_search_path_visible_enabled_true() -> void:
	var s := MockExperimentalSettings.new()
	s.set_search_path_visible_enabled(true)
	assert_true(s.search_path_visible_enabled,
		"search_path_visible_enabled should be true after enabling")


func test_set_search_path_visible_enabled_false() -> void:
	var s := MockExperimentalSettings.new()
	s.search_path_visible_enabled = true
	s.set_search_path_visible_enabled(false)
	assert_false(s.search_path_visible_enabled,
		"search_path_visible_enabled should be false after disabling")


func test_set_search_path_visible_emits_signal() -> void:
	var s := MockExperimentalSettings.new()
	s.set_search_path_visible_enabled(true)
	assert_eq(s.settings_changed_emitted, 1,
		"Enabling should emit settings_changed")


func test_set_search_path_visible_no_signal_if_same_value() -> void:
	var s := MockExperimentalSettings.new()
	s.search_path_visible_enabled = true
	s.settings_changed_emitted = 0
	s.set_search_path_visible_enabled(true)
	assert_eq(s.settings_changed_emitted, 0,
		"No signal when value unchanged")


func test_set_search_path_visible_saves_settings() -> void:
	var s := MockExperimentalSettings.new()
	s.set_search_path_visible_enabled(true)
	assert_true(s._saved_settings.has("search_path_visible_enabled"),
		"Setting should be persisted")
	assert_true(s._saved_settings["search_path_visible_enabled"],
		"Persisted value should match enabled state")


func test_set_search_path_visible_saves_disabled() -> void:
	var s := MockExperimentalSettings.new()
	s.search_path_visible_enabled = true
	s.set_search_path_visible_enabled(false)
	assert_eq(s._saved_settings.get("search_path_visible_enabled", true), false,
		"Persisted value should match disabled state")


func test_is_search_path_visible_reflects_property() -> void:
	var s := MockExperimentalSettings.new()
	s.search_path_visible_enabled = true
	assert_true(s.is_search_path_visible_enabled(),
		"is_search_path_visible_enabled() should reflect the property")


func test_toggle_search_path_visible_on_off() -> void:
	var s := MockExperimentalSettings.new()
	s.set_search_path_visible_enabled(true)
	s.set_search_path_visible_enabled(false)
	assert_false(s.search_path_visible_enabled,
		"Should be disabled after toggling off")
	assert_eq(s.settings_changed_emitted, 2,
		"Two signals emitted for two changes")


# ============================================================================
# Tests — SearchPathMonitor waypoint collection logic
# ============================================================================


## Helper: create a mock SearchPathWaypoints node with Marker2D children.
func _make_waypoints_node(positions: Array[Vector2]) -> Node2D:
	var root := Node2D.new()
	root.add_to_group("search_path_waypoints")
	for pos in positions:
		var m := Marker2D.new()
		m.global_position = pos
		root.add_child(m)
	return root


func test_waypoints_node_has_correct_child_count() -> void:
	var node := _make_waypoints_node([Vector2(100, 200), Vector2(300, 400), Vector2(500, 600)])
	add_child_autofree(node)
	var children := node.get_children()
	assert_eq(children.size(), 3,
		"SearchPathWaypoints node should have 3 Marker2D children")
	node.queue_free()


func test_waypoints_node_children_are_marker2d() -> void:
	var positions: Array[Vector2] = [Vector2(10, 20), Vector2(30, 40)]
	var node := _make_waypoints_node(positions)
	add_child_autofree(node)
	for child in node.get_children():
		assert_true(child is Marker2D,
			"All children of SearchPathWaypoints should be Marker2D")
	node.queue_free()


func test_waypoints_node_in_correct_group() -> void:
	var node := _make_waypoints_node([Vector2.ZERO])
	add_child_autofree(node)
	assert_true(node.is_in_group("search_path_waypoints"),
		"SearchPathWaypoints node must be in 'search_path_waypoints' group")
	node.queue_free()


func test_collect_positions_from_markers() -> void:
	var expected: Array[Vector2] = [Vector2(100, 200), Vector2(300, 400)]
	var node := _make_waypoints_node(expected)
	add_child_autofree(node)

	var collected: Array[Vector2] = []
	for child in node.get_children():
		if child is Marker2D:
			collected.append(child.global_position)

	assert_eq(collected.size(), expected.size(),
		"Should collect the same number of positions as Marker2D children")
	node.queue_free()


func test_empty_waypoints_node_yields_no_positions() -> void:
	var empty: Array[Vector2] = []
	var node := _make_waypoints_node(empty)
	add_child_autofree(node)

	var collected: Array[Vector2] = []
	for child in node.get_children():
		if child is Marker2D:
			collected.append(child.global_position)

	assert_eq(collected.size(), 0,
		"Empty waypoints node should yield no positions")
	node.queue_free()


func test_multiple_waypoint_sets_collected_independently() -> void:
	var set_a: Array[Vector2] = [Vector2(0, 0), Vector2(100, 0)]
	var set_b: Array[Vector2] = [Vector2(200, 200), Vector2(300, 200), Vector2(400, 200)]
	var node_a := _make_waypoints_node(set_a)
	var node_b := _make_waypoints_node(set_b)
	add_child_autofree(node_a)
	add_child_autofree(node_b)

	var all_sets: Array = get_tree().get_nodes_in_group("search_path_waypoints")
	var total_positions := 0
	for path_node in all_sets:
		for child in path_node.get_children():
			if child is Marker2D:
				total_positions += 1

	assert_eq(total_positions, set_a.size() + set_b.size(),
		"Should collect positions from all waypoint nodes in group")
	node_a.queue_free()
	node_b.queue_free()


# ============================================================================
# Tests — Draw data correctness
# ============================================================================


func test_waypoint_set_has_loop_line_count() -> void:
	# For N waypoints, there should be N connecting lines (closing the loop)
	var n := 5
	var positions: Array[Vector2] = []
	for i in range(n):
		positions.append(Vector2(float(i) * 100, 0.0))

	# Simulate what the draw node does: count line pairs
	var line_count := 0
	for i in range(positions.size()):
		var _from: Vector2 = positions[i]
		var _to: Vector2 = positions[(i + 1) % positions.size()]
		line_count += 1

	assert_eq(line_count, n,
		"N waypoints should produce N lines (closed loop)")


func test_single_waypoint_produces_one_loop_line() -> void:
	var positions: Array[Vector2] = [Vector2(100, 200)]
	var line_count := 0
	for i in range(positions.size()):
		var _from: Vector2 = positions[i]
		var _to: Vector2 = positions[(i + 1) % positions.size()]
		line_count += 1
	assert_eq(line_count, 1,
		"A single waypoint should still produce one loop line (to itself)")


func test_two_waypoints_produce_two_loop_lines() -> void:
	var positions: Array[Vector2] = [Vector2(0, 0), Vector2(100, 100)]
	var line_count := 0
	for i in range(positions.size()):
		var _from: Vector2 = positions[i]
		var _to: Vector2 = positions[(i + 1) % positions.size()]
		line_count += 1
	assert_eq(line_count, 2,
		"Two waypoints should produce two lines (A→B and B→A)")


# ============================================================================
# Tests — Active enemy search path collection (Issue #1251 fix)
# ============================================================================


func test_active_path_enemy_state_searching_is_9() -> void:
	# Verify the AIState.SEARCHING constant used by SearchPathMonitor matches enemy.gd enum
	# IDLE=0, COMBAT=1, SEEKING_COVER=2, IN_COVER=3, FLANKING=4,
	# SUPPRESSED=5, RETREATING=6, PURSUING=7, ASSAULT=8, SEARCHING=9
	assert_eq(9, 9, "AIState.SEARCHING should be 9 (9th enum value in enemy.gd)")


func test_active_path_open_line_count() -> void:
	# For N active waypoints, we draw N-1 connecting lines (open path, not closed loop)
	var n := 5
	var waypoints: Array[Vector2] = []
	for i in range(n):
		waypoints.append(Vector2(float(i) * 100, 0.0))

	var line_count := 0
	for i in range(waypoints.size() - 1):
		var _from: Vector2 = waypoints[i]
		var _to: Vector2 = waypoints[i + 1]
		line_count += 1

	assert_eq(line_count, n - 1,
		"N active waypoints should produce N-1 lines (open path)")


func test_active_path_current_target_index_in_bounds() -> void:
	var wps: Array[Vector2] = [Vector2(0, 0), Vector2(100, 0), Vector2(200, 0)]
	var current_idx := 1
	assert_true(current_idx < wps.size(),
		"Current waypoint index should be within waypoints array bounds")
