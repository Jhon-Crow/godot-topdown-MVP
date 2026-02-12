extends GutTest
## Unit tests for GroupSearchCoordinator (Issue #650).
##
## Tests the group search coordination system including:
## - Enemy registration and sector assignment
## - Angular sector division
## - Sector waypoint generation
## - Shared visited zones
## - Realistic scan target generation
## - Coordinator lifecycle (creation, cleanup)


# ============================================================================
# Helper: Mock enemy node for testing
# ============================================================================

class MockEnemy extends Node2D:
	var _state: int = 0
	func get_current_state() -> int: return _state


var _mock_enemies: Array[MockEnemy] = []


func before_each() -> void:
	GroupSearchCoordinator.clear_all()
	_mock_enemies.clear()


func after_each() -> void:
	for enemy in _mock_enemies:
		if is_instance_valid(enemy):
			enemy.free()
	_mock_enemies.clear()
	GroupSearchCoordinator.clear_all()


func _create_mock_enemy() -> MockEnemy:
	var enemy := MockEnemy.new()
	add_child(enemy)
	_mock_enemies.append(enemy)
	return enemy


# ============================================================================
# Initialization Tests
# ============================================================================


func test_coordinator_creation() -> void:
	var coord := GroupSearchCoordinator.new(Vector2(100, 200))
	assert_eq(coord.center, Vector2(100, 200), "Center should be set on creation")
	assert_eq(coord.get_enemy_count(), 0, "Should have no enemies initially")


func test_get_or_create_returns_coordinator() -> void:
	var coord := GroupSearchCoordinator.get_or_create(Vector2(100, 100))
	assert_not_null(coord, "Should return a coordinator")
	assert_eq(coord.center, Vector2(100, 100), "Center should match request")


func test_get_or_create_reuses_nearby_coordinator() -> void:
	var coord1 := GroupSearchCoordinator.get_or_create(Vector2(100, 100))
	var coord2 := GroupSearchCoordinator.get_or_create(Vector2(150, 150))
	assert_eq(coord1, coord2, "Should reuse coordinator for nearby center (within 200px)")


func test_get_or_create_creates_separate_for_distant() -> void:
	var coord1 := GroupSearchCoordinator.get_or_create(Vector2(100, 100))
	var coord2 := GroupSearchCoordinator.get_or_create(Vector2(500, 500))
	assert_ne(coord1, coord2, "Should create separate coordinator for distant center (>200px)")


# ============================================================================
# Registration Tests
# ============================================================================


func test_register_single_enemy() -> void:
	var coord := GroupSearchCoordinator.get_or_create(Vector2.ZERO)
	var enemy := _create_mock_enemy()
	var sector := coord.register_enemy(enemy)
	assert_eq(sector, 0, "First enemy should get sector 0")
	assert_eq(coord.get_enemy_count(), 1, "Should have 1 enemy")


func test_register_multiple_enemies() -> void:
	var coord := GroupSearchCoordinator.get_or_create(Vector2.ZERO)
	var e1 := _create_mock_enemy()
	var e2 := _create_mock_enemy()
	var e3 := _create_mock_enemy()
	coord.register_enemy(e1)
	coord.register_enemy(e2)
	coord.register_enemy(e3)
	assert_eq(coord.get_enemy_count(), 3, "Should have 3 enemies")


func test_register_same_enemy_returns_same_sector() -> void:
	var coord := GroupSearchCoordinator.get_or_create(Vector2.ZERO)
	var enemy := _create_mock_enemy()
	var sector1 := coord.register_enemy(enemy)
	var sector2 := coord.register_enemy(enemy)
	assert_eq(sector1, sector2, "Registering same enemy twice should return same sector")
	assert_eq(coord.get_enemy_count(), 1, "Should still have 1 enemy")


func test_unregister_enemy() -> void:
	var coord := GroupSearchCoordinator.get_or_create(Vector2.ZERO)
	var enemy := _create_mock_enemy()
	coord.register_enemy(enemy)
	assert_eq(coord.get_enemy_count(), 1, "Should have 1 enemy before unregister")
	coord.unregister_enemy(enemy)
	assert_eq(coord.get_enemy_count(), 0, "Should have 0 enemies after unregister")


# ============================================================================
# Coordination Tests
# ============================================================================


func test_not_coordinated_with_single_enemy() -> void:
	var coord := GroupSearchCoordinator.get_or_create(Vector2.ZERO)
	var enemy := _create_mock_enemy()
	coord.register_enemy(enemy)
	assert_false(coord.is_coordinated(), "Should not be coordinated with 1 enemy")


func test_coordinated_with_two_enemies() -> void:
	var coord := GroupSearchCoordinator.get_or_create(Vector2.ZERO)
	var e1 := _create_mock_enemy()
	var e2 := _create_mock_enemy()
	coord.register_enemy(e1)
	coord.register_enemy(e2)
	assert_true(coord.is_coordinated(), "Should be coordinated with 2+ enemies")


# ============================================================================
# Sector Angle Tests
# ============================================================================


func test_single_enemy_gets_full_circle() -> void:
	var coord := GroupSearchCoordinator.get_or_create(Vector2.ZERO)
	var enemy := _create_mock_enemy()
	coord.register_enemy(enemy)
	var sector := coord.get_sector_angles(enemy)
	assert_almost_eq(sector["end"] - sector["start"], TAU, 0.01,
		"Single enemy should get full 360 degree sector")


func test_two_enemies_get_half_circles() -> void:
	var coord := GroupSearchCoordinator.get_or_create(Vector2.ZERO)
	var e1 := _create_mock_enemy()
	var e2 := _create_mock_enemy()
	coord.register_enemy(e1)
	coord.register_enemy(e2)
	var s1 := coord.get_sector_angles(e1)
	var s2 := coord.get_sector_angles(e2)
	assert_almost_eq(s1["end"] - s1["start"], PI, 0.01,
		"Each of 2 enemies should get 180 degree sector")
	assert_almost_eq(s2["end"] - s2["start"], PI, 0.01,
		"Each of 2 enemies should get 180 degree sector")


func test_three_enemies_get_thirds() -> void:
	var coord := GroupSearchCoordinator.get_or_create(Vector2.ZERO)
	var e1 := _create_mock_enemy()
	var e2 := _create_mock_enemy()
	var e3 := _create_mock_enemy()
	coord.register_enemy(e1)
	coord.register_enemy(e2)
	coord.register_enemy(e3)
	for enemy in [e1, e2, e3]:
		var s := coord.get_sector_angles(enemy)
		assert_almost_eq(s["end"] - s["start"], TAU / 3.0, 0.01,
			"Each of 3 enemies should get 120 degree sector")


func test_sectors_dont_overlap() -> void:
	var coord := GroupSearchCoordinator.get_or_create(Vector2.ZERO)
	var e1 := _create_mock_enemy()
	var e2 := _create_mock_enemy()
	coord.register_enemy(e1)
	coord.register_enemy(e2)
	var s1 := coord.get_sector_angles(e1)
	var s2 := coord.get_sector_angles(e2)
	# s1 should end where s2 starts
	assert_almost_eq(s1["end"], s2["start"], 0.01,
		"Sectors should be adjacent (no gap, no overlap)")


func test_unregistered_enemy_gets_full_circle() -> void:
	var coord := GroupSearchCoordinator.get_or_create(Vector2.ZERO)
	var enemy := _create_mock_enemy()
	# Don't register
	var sector := coord.get_sector_angles(enemy)
	assert_almost_eq(sector["end"] - sector["start"], TAU, 0.01,
		"Unregistered enemy should get full circle as fallback")


# ============================================================================
# Sector Waypoint Generation Tests
# ============================================================================


func test_generate_sector_waypoints_returns_array() -> void:
	var coord := GroupSearchCoordinator.get_or_create(Vector2.ZERO)
	var enemy := _create_mock_enemy()
	coord.register_enemy(enemy)
	var waypoints := coord.generate_sector_waypoints(enemy, 300.0)
	assert_true(waypoints.size() > 0, "Should generate at least one waypoint")


func test_sector_waypoints_within_radius() -> void:
	var coord := GroupSearchCoordinator.get_or_create(Vector2.ZERO)
	var enemy := _create_mock_enemy()
	coord.register_enemy(enemy)
	var waypoints := coord.generate_sector_waypoints(enemy, 300.0)
	for wp in waypoints:
		var dist := wp.distance_to(Vector2.ZERO)
		assert_true(dist <= 300.0 + 1.0,
			"All waypoints should be within radius (got %.1f)" % dist)


func test_two_enemies_get_different_waypoints() -> void:
	var coord := GroupSearchCoordinator.get_or_create(Vector2.ZERO)
	var e1 := _create_mock_enemy()
	var e2 := _create_mock_enemy()
	coord.register_enemy(e1)
	coord.register_enemy(e2)
	var wp1 := coord.generate_sector_waypoints(e1, 300.0)
	var wp2 := coord.generate_sector_waypoints(e2, 300.0)
	# Check that waypoints don't overlap
	var overlap_count := 0
	for w1 in wp1:
		for w2 in wp2:
			if w1.distance_to(w2) < 10.0:
				overlap_count += 1
	assert_eq(overlap_count, 0, "Different sectors should produce non-overlapping waypoints")


func test_sector_waypoints_max_count() -> void:
	var coord := GroupSearchCoordinator.get_or_create(Vector2.ZERO)
	var enemy := _create_mock_enemy()
	coord.register_enemy(enemy)
	var waypoints := coord.generate_sector_waypoints(enemy, 5000.0)
	assert_true(waypoints.size() <= 20, "Should generate at most 20 waypoints (got %d)" % waypoints.size())


# ============================================================================
# Shared Visited Zone Tests
# ============================================================================


func test_mark_zone_visited() -> void:
	var coord := GroupSearchCoordinator.get_or_create(Vector2.ZERO)
	coord.mark_zone_visited(Vector2(100, 100))
	assert_true(coord.is_zone_visited(Vector2(100, 100)), "Zone should be marked as visited")


func test_unvisited_zone() -> void:
	var coord := GroupSearchCoordinator.get_or_create(Vector2.ZERO)
	assert_false(coord.is_zone_visited(Vector2(100, 100)), "Zone should not be visited initially")


func test_shared_zones_between_enemies() -> void:
	var coord := GroupSearchCoordinator.get_or_create(Vector2.ZERO)
	var e1 := _create_mock_enemy()
	var e2 := _create_mock_enemy()
	coord.register_enemy(e1)
	coord.register_enemy(e2)
	# Enemy 1 visits a zone
	coord.mark_zone_visited(Vector2(100, 100))
	# Enemy 2 should see it as visited
	assert_true(coord.is_zone_visited(Vector2(100, 100)),
		"Zone visited by one enemy should be visible to all coordinated enemies")


func test_clear_visited_zones() -> void:
	var coord := GroupSearchCoordinator.get_or_create(Vector2.ZERO)
	coord.mark_zone_visited(Vector2(100, 100))
	coord.clear_visited_zones()
	assert_false(coord.is_zone_visited(Vector2(100, 100)),
		"Clear should remove all visited zones")


func test_visited_zone_snapping() -> void:
	var coord := GroupSearchCoordinator.get_or_create(Vector2.ZERO)
	coord.mark_zone_visited(Vector2(110, 110))
	# Nearby position (within 50px snap) should also be considered visited
	assert_true(coord.is_zone_visited(Vector2(115, 115)),
		"Nearby position within snap grid should be considered same zone")


# ============================================================================
# Scan Target Generation Tests
# ============================================================================


func test_generate_scan_targets_returns_array() -> void:
	var coord := GroupSearchCoordinator.get_or_create(Vector2.ZERO)
	var enemy := _create_mock_enemy()
	coord.register_enemy(enemy)
	var targets := coord.generate_scan_targets(enemy, 0.0)
	assert_eq(targets.size(), GroupSearchCoordinator.SCAN_TARGETS_PER_STOP,
		"Should generate expected number of scan targets")


func test_scan_targets_have_angle_and_pause() -> void:
	var coord := GroupSearchCoordinator.get_or_create(Vector2.ZERO)
	var enemy := _create_mock_enemy()
	coord.register_enemy(enemy)
	var targets := coord.generate_scan_targets(enemy, 0.0)
	for target in targets:
		assert_true(target.has("angle"), "Scan target should have 'angle' key")
		assert_true(target.has("pause"), "Scan target should have 'pause' key")
		assert_true(target["pause"] >= GroupSearchCoordinator.SCAN_PAUSE_MIN,
			"Pause should be at least SCAN_PAUSE_MIN")


func test_solo_scan_targets_returns_array() -> void:
	var targets := GroupSearchCoordinator.generate_solo_scan_targets(0.0, Vector2.RIGHT)
	assert_eq(targets.size(), 3, "Solo scan should generate 3 targets")
	for target in targets:
		assert_true(target.has("angle"), "Target should have 'angle' key")
		assert_true(target.has("pause"), "Target should have 'pause' key")


func test_scan_targets_angle_in_valid_range() -> void:
	var coord := GroupSearchCoordinator.get_or_create(Vector2.ZERO)
	var enemy := _create_mock_enemy()
	coord.register_enemy(enemy)
	var targets := coord.generate_scan_targets(enemy, 0.0)
	for target in targets:
		assert_true(target["angle"] >= -PI and target["angle"] <= PI,
			"Scan angle should be wrapped to [-PI, PI]")


# ============================================================================
# Lifecycle Tests
# ============================================================================


func test_clear_all_removes_coordinators() -> void:
	GroupSearchCoordinator.get_or_create(Vector2(100, 100))
	GroupSearchCoordinator.get_or_create(Vector2(500, 500))
	GroupSearchCoordinator.clear_all()
	# After clear, creating should not find old coordinators
	var coord := GroupSearchCoordinator.get_or_create(Vector2(100, 100))
	assert_eq(coord.get_enemy_count(), 0, "After clear_all, new coordinator should have 0 enemies")


func test_coordinator_removed_when_all_enemies_unregister() -> void:
	var coord := GroupSearchCoordinator.get_or_create(Vector2.ZERO)
	var enemy := _create_mock_enemy()
	coord.register_enemy(enemy)
	coord.unregister_enemy(enemy)
	# Coordinator should self-remove, so getting one at same pos should create new
	var coord2 := GroupSearchCoordinator.get_or_create(Vector2.ZERO)
	assert_eq(coord2.get_enemy_count(), 0, "New coordinator should have 0 enemies after old one cleaned up")


# ============================================================================
# Edge Case Tests
# ============================================================================


func test_sector_reassignment_after_unregister() -> void:
	var coord := GroupSearchCoordinator.get_or_create(Vector2.ZERO)
	var e1 := _create_mock_enemy()
	var e2 := _create_mock_enemy()
	var e3 := _create_mock_enemy()
	coord.register_enemy(e1)
	coord.register_enemy(e2)
	coord.register_enemy(e3)
	# Remove middle enemy
	coord.unregister_enemy(e2)
	# Remaining enemies should be reassigned sectors
	assert_eq(coord.get_enemy_count(), 2, "Should have 2 enemies after unregister")
	var s1 := coord.get_sector_angles(e1)
	var s3 := coord.get_sector_angles(e3)
	assert_almost_eq(s1["end"] - s1["start"], PI, 0.01,
		"After removal, each remaining enemy gets 180 degrees")
	assert_almost_eq(s3["end"] - s3["start"], PI, 0.01,
		"After removal, each remaining enemy gets 180 degrees")


func test_get_sector_angles_empty_coordinator() -> void:
	var coord := GroupSearchCoordinator.get_or_create(Vector2.ZERO)
	var enemy := _create_mock_enemy()
	# Don't register - coordinator is empty
	var sector := coord.get_sector_angles(enemy)
	assert_almost_eq(sector["start"], 0.0, 0.01, "Empty coordinator should return start=0")
	assert_almost_eq(sector["end"], TAU, 0.01, "Empty coordinator should return end=TAU")


func test_unregister_nonexistent_enemy_no_crash() -> void:
	var coord := GroupSearchCoordinator.get_or_create(Vector2.ZERO)
	var enemy := _create_mock_enemy()
	# Unregistering an enemy that was never registered should not crash
	coord.unregister_enemy(enemy)
	assert_eq(coord.get_enemy_count(), 0, "Should still have 0 enemies")


func test_double_unregister_no_crash() -> void:
	var coord := GroupSearchCoordinator.get_or_create(Vector2.ZERO)
	var enemy := _create_mock_enemy()
	coord.register_enemy(enemy)
	coord.unregister_enemy(enemy)
	coord.unregister_enemy(enemy)  # Double unregister should be safe
	assert_eq(coord.get_enemy_count(), 0, "Should still have 0 enemies after double unregister")


func test_waypoints_with_nav_callback() -> void:
	var coord := GroupSearchCoordinator.get_or_create(Vector2.ZERO)
	var enemy := _create_mock_enemy()
	coord.register_enemy(enemy)
	# Callback that rejects all positions
	var reject_all := func(_pos: Vector2) -> bool: return false
	var waypoints := coord.generate_sector_waypoints(enemy, 300.0, reject_all)
	# Should still include center if not visited
	assert_true(waypoints.size() <= 1,
		"With all positions rejected, should have at most center waypoint")


func test_waypoints_skip_visited_zones() -> void:
	var coord := GroupSearchCoordinator.get_or_create(Vector2.ZERO)
	var enemy := _create_mock_enemy()
	coord.register_enemy(enemy)
	# Generate waypoints first
	var wp_before := coord.generate_sector_waypoints(enemy, 300.0)
	# Mark all as visited
	for wp in wp_before:
		coord.mark_zone_visited(wp)
	# Generate again — should be fewer
	var wp_after := coord.generate_sector_waypoints(enemy, 300.0)
	assert_true(wp_after.size() < wp_before.size(),
		"Should generate fewer waypoints when zones are already visited")
