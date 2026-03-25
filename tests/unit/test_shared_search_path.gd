extends GutTest
## Unit tests for SharedSearchPath slot limiter (Issue #1458).
##
## Tests the search slot manager that limits simultaneous SEARCHING enemies
## to MAX_SEARCHERS, preventing excessive NavigationServer2D load.


func _make_ssp() -> Node:
	var ssp := preload("res://scripts/autoload/shared_search_path.gd").new()
	add_child_autofree(ssp)
	return ssp


# ============================================================================
# Tests — Slot Acquisition
# ============================================================================


func test_max_searchers_constant_is_2() -> void:
	var ssp := _make_ssp()
	assert_eq(ssp.MAX_SEARCHERS, 2, "MAX_SEARCHERS should be 2")


func test_first_enemy_gets_slot() -> void:
	var ssp := _make_ssp()
	assert_true(ssp.try_acquire(1001), "First enemy should get a slot")


func test_second_enemy_gets_slot() -> void:
	var ssp := _make_ssp()
	ssp.try_acquire(1001)
	assert_true(ssp.try_acquire(1002), "Second enemy should get a slot")


func test_third_enemy_denied_slot() -> void:
	var ssp := _make_ssp()
	ssp.try_acquire(1001)
	ssp.try_acquire(1002)
	assert_false(ssp.try_acquire(1003), "Third enemy should be denied (slots full)")


func test_same_enemy_reacquires_slot() -> void:
	var ssp := _make_ssp()
	ssp.try_acquire(2001)
	assert_true(ssp.try_acquire(2001), "Same enemy re-acquiring should return true")


# ============================================================================
# Tests — Slot Release
# ============================================================================


func test_release_frees_slot() -> void:
	var ssp := _make_ssp()
	ssp.try_acquire(3001)
	ssp.try_acquire(3002)
	ssp.release(3001)
	assert_true(ssp.try_acquire(3003), "After release, third enemy should get slot")


func test_release_nonexistent_is_safe() -> void:
	var ssp := _make_ssp()
	ssp.release(9999)  # Should not crash
	assert_true(true, "Releasing non-existent ID should not crash")


func test_active_count_updates() -> void:
	var ssp := _make_ssp()
	assert_eq(ssp.get_active_count(), 0, "Initial count should be 0")
	ssp.try_acquire(4001)
	assert_eq(ssp.get_active_count(), 1, "Count should be 1 after one acquire")
	ssp.try_acquire(4002)
	assert_eq(ssp.get_active_count(), 2, "Count should be 2 after two acquires")
	ssp.release(4001)
	assert_eq(ssp.get_active_count(), 1, "Count should be 1 after one release")


# ============================================================================
# Tests — is_active Query
# ============================================================================


func test_is_active_true_after_acquire() -> void:
	var ssp := _make_ssp()
	ssp.try_acquire(5001)
	assert_true(ssp.is_active(5001), "Enemy should be active after acquiring slot")


func test_is_active_false_before_acquire() -> void:
	var ssp := _make_ssp()
	assert_false(ssp.is_active(5001), "Enemy should not be active before acquiring")


func test_is_active_false_after_release() -> void:
	var ssp := _make_ssp()
	ssp.try_acquire(6001)
	ssp.release(6001)
	assert_false(ssp.is_active(6001), "Enemy should not be active after release")


# ============================================================================
# Tests — Edge Cases
# ============================================================================


func test_denied_enemy_not_counted() -> void:
	var ssp := _make_ssp()
	ssp.try_acquire(7001)
	ssp.try_acquire(7002)
	ssp.try_acquire(7003)  # denied
	assert_eq(ssp.get_active_count(), 2, "Denied enemy should not increase count")


func test_full_then_release_then_acquire_cycle() -> void:
	var ssp := _make_ssp()
	ssp.try_acquire(8001)
	ssp.try_acquire(8002)
	assert_false(ssp.try_acquire(8003), "Should be full")
	ssp.release(8001)
	assert_true(ssp.try_acquire(8003), "Should get slot after release")
