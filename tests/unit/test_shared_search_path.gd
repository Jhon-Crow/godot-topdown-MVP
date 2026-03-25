extends GutTest
## Unit tests for SharedSearchPath autoload (Issue #1458).
##
## Tests the shared search path system that generates ONE set of waypoints
## for all searching enemies, reducing nav queries from 20/frame to ~1-2/frame.


# ============================================================================
# Tests — Registration and Waypoint Assignment
# ============================================================================


func test_register_searcher_returns_valid_index() -> void:
	var ssp := preload("res://scripts/autoload/shared_search_path.gd").new()
	add_child_autofree(ssp)
	# Cannot fully test without nav mesh, but verify the method exists and returns int
	var result: int = ssp.register_searcher(1001, Vector2(500, 500))
	# Result is -1 or >= 0 depending on nav mesh availability
	assert_true(result >= -1, "register_searcher should return an int >= -1")
	ssp.queue_free()


func test_unregister_cleans_up_searcher() -> void:
	var ssp := preload("res://scripts/autoload/shared_search_path.gd").new()
	add_child_autofree(ssp)
	ssp.register_searcher(2001, Vector2(100, 100))
	ssp.unregister_searcher(2001)
	# After unregistering, the claims should be empty for this enemy
	var claims := ssp.get_claims()
	for wp_idx in claims:
		assert_ne(claims[wp_idx], 2001, "Claims should not contain unregistered enemy")
	ssp.queue_free()


func test_unregister_nonexistent_is_safe() -> void:
	var ssp := preload("res://scripts/autoload/shared_search_path.gd").new()
	add_child_autofree(ssp)
	# Should not crash
	ssp.unregister_searcher(9999)
	assert_true(true, "Unregistering non-existent searcher should not crash")
	ssp.queue_free()


func test_is_active_after_registration() -> void:
	var ssp := preload("res://scripts/autoload/shared_search_path.gd").new()
	add_child_autofree(ssp)
	assert_false(ssp.is_active(), "Should not be active before any registration")
	ssp.register_searcher(3001, Vector2(200, 200))
	assert_true(ssp.is_active(), "Should be active after registration")
	ssp.queue_free()


func test_deactivates_when_all_unregistered() -> void:
	var ssp := preload("res://scripts/autoload/shared_search_path.gd").new()
	add_child_autofree(ssp)
	ssp.register_searcher(4001, Vector2(300, 300))
	ssp.register_searcher(4002, Vector2(300, 300))
	ssp.unregister_searcher(4001)
	assert_true(ssp.is_active(), "Should still be active with one searcher")
	ssp.unregister_searcher(4002)
	assert_false(ssp.is_active(), "Should deactivate when all searchers unregistered")
	ssp.queue_free()


# ============================================================================
# Tests — Nav Update Stagger
# ============================================================================


func test_nav_update_interval_is_6() -> void:
	var ssp := preload("res://scripts/autoload/shared_search_path.gd").new()
	assert_eq(ssp.NAV_UPDATE_INTERVAL, 6,
		"NAV_UPDATE_INTERVAL should be 6 for shared path (increased from per-enemy 3)")
	ssp.queue_free()


func test_is_nav_update_frame_distributes_across_enemies() -> void:
	var ssp := preload("res://scripts/autoload/shared_search_path.gd").new()
	add_child_autofree(ssp)
	# Register enemies with different IDs to get different offsets
	ssp.register_searcher(100, Vector2.ZERO)
	ssp.register_searcher(101, Vector2.ZERO)
	ssp.register_searcher(102, Vector2.ZERO)
	# At frame 0, only enemies whose offset == 0 should fire
	# enemy 100: offset = 100 % 6 = 4 -> not frame 0
	# enemy 101: offset = 101 % 6 = 5 -> not frame 0
	# enemy 102: offset = 102 % 6 = 0 -> IS frame 0
	assert_false(ssp.is_nav_update_frame(100), "Enemy 100 (offset 4) should not fire at frame 0")
	assert_false(ssp.is_nav_update_frame(101), "Enemy 101 (offset 5) should not fire at frame 0")
	assert_true(ssp.is_nav_update_frame(102), "Enemy 102 (offset 0) should fire at frame 0")
	ssp.queue_free()


# ============================================================================
# Tests — Zone Key Hashing
# ============================================================================


func test_zone_key_is_integer() -> void:
	var ssp := preload("res://scripts/autoload/shared_search_path.gd").new()
	var key: int = ssp._get_zone_key(Vector2(150.0, 250.0))
	assert_true(key is int, "Zone key should be an integer (no string allocation)")
	ssp.queue_free()


func test_zone_key_different_positions() -> void:
	var ssp := preload("res://scripts/autoload/shared_search_path.gd").new()
	var k1: int = ssp._get_zone_key(Vector2(0, 0))
	var k2: int = ssp._get_zone_key(Vector2(100, 0))
	var k3: int = ssp._get_zone_key(Vector2(0, 100))
	assert_ne(k1, k2, "Different X positions should produce different keys")
	assert_ne(k1, k3, "Different Y positions should produce different keys")
	assert_ne(k2, k3, "Different positions should produce different keys")
	ssp.queue_free()


func test_zone_key_same_zone_same_key() -> void:
	var ssp := preload("res://scripts/autoload/shared_search_path.gd").new()
	# Positions within the same 50px zone should produce the same key
	var k1: int = ssp._get_zone_key(Vector2(10, 10))
	var k2: int = ssp._get_zone_key(Vector2(40, 40))
	assert_eq(k1, k2, "Positions in the same 50px zone should have the same key")
	ssp.queue_free()


# ============================================================================
# Tests — Get Waypoint
# ============================================================================


func test_get_waypoint_invalid_index_returns_zero() -> void:
	var ssp := preload("res://scripts/autoload/shared_search_path.gd").new()
	assert_eq(ssp.get_waypoint(-1), Vector2.ZERO, "Invalid index should return Vector2.ZERO")
	assert_eq(ssp.get_waypoint(999), Vector2.ZERO, "Out of bounds index should return Vector2.ZERO")
	ssp.queue_free()


func test_get_center_returns_search_center() -> void:
	var ssp := preload("res://scripts/autoload/shared_search_path.gd").new()
	add_child_autofree(ssp)
	ssp.register_searcher(5001, Vector2(400, 600))
	assert_eq(ssp.get_center(), Vector2(400, 600), "Center should match registration position")
	ssp.queue_free()


# ============================================================================
# Tests — Constants
# ============================================================================


func test_constants_match_expected_values() -> void:
	var ssp := preload("res://scripts/autoload/shared_search_path.gd").new()
	assert_eq(ssp.ZONE_SNAP, 50.0, "ZONE_SNAP should be 50.0")
	assert_eq(ssp.WAYPOINT_SPACING, 75.0, "WAYPOINT_SPACING should be 75.0")
	assert_eq(ssp.INITIAL_RADIUS, 100.0, "INITIAL_RADIUS should be 100.0")
	assert_eq(ssp.MAX_RADIUS, 2000.0, "MAX_RADIUS should be 2000.0")
	assert_eq(ssp.WAYPOINTS_PER_RING, 20, "WAYPOINTS_PER_RING should be 20")
	ssp.queue_free()


func test_get_all_waypoints_returns_array() -> void:
	var ssp := preload("res://scripts/autoload/shared_search_path.gd").new()
	var wps: Array[Vector2] = ssp.get_all_waypoints()
	assert_eq(wps.size(), 0, "Should return empty array when no search active")
	ssp.queue_free()
