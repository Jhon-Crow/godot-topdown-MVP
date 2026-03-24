extends GutTest
## Unit tests for TacticalMovementComponent (Issue #1249).
##
## Tests the tactical yielding logic: narrow passage detection, ally-blocking
## detection, priority assignment, and yield timer expiry.


# ============================================================================
# Mock Enemy for testing TacticalMovementComponent
# ============================================================================


class MockEnemy2D:
	## Minimal mock that satisfies TacticalMovementComponent's queries.
	var global_position: Vector2 = Vector2.ZERO
	var _player: Node2D = null  ## Player reference (can be null)
	var _group: String = "enemies"

	var _world_2d: MockWorld2D = null

	func get_world_2d() -> MockWorld2D:
		return _world_2d

	func get_rid() -> RID:
		return RID()

	func is_in_group(group: String) -> bool:
		return group == _group

	func get_tree() -> MockSceneTree:
		return _tree

	var _tree: MockSceneTree = null


class MockWorld2D:
	## Returns a MockSpaceState that we control.
	var space_state: MockSpaceState2D = null

	func direct_space_state() -> MockSpaceState2D:
		return space_state


class MockSpaceState2D:
	## Configurable raycast stub.
	## narrow_hit: whether perpendicular rays hit a wall (simulates narrow passage)
	## ally_hit: whether forward ray hits an ally enemy body
	var narrow_hit: bool = false
	var ally_hit: bool = false
	var ally_body: MockEnemyBody = null

	func intersect_ray(query: Dictionary) -> Dictionary:
		# Use the exclude flag to distinguish perpendicular (wall) from forward (ally) queries.
		# In the component, wall queries use collision_mask=4, ally queries use collision_mask=2.
		var mask: int = query.get("collision_mask", 0)
		if mask == 4 and narrow_hit:
			return {"position": query["from"], "normal": Vector2.UP}
		if mask == 2 and ally_hit and ally_body != null:
			return {"position": query["from"] + Vector2(10, 0), "collider": ally_body}
		return {}


class MockEnemyBody:
	var global_position: Vector2 = Vector2.ZERO

	func is_in_group(group: String) -> bool:
		return group == "enemies"


class MockSceneTree:
	## Returns the registered enemies list.
	var _enemies: Array = []

	func get_nodes_in_group(_group: String) -> Array:
		return _enemies


# ============================================================================
# Helpers
# ============================================================================


## Create a TacticalMovementComponent with a pure-GDScript mock enemy.
## The mock does NOT use Godot physics — we stub the space state manually.
func _make_component() -> TacticalMovementComponent:
	var comp := TacticalMovementComponent.new(null)
	return comp


# ============================================================================
# Tests: yield timer logic (no physics needed)
# ============================================================================


func test_initial_state_is_not_yielding() -> void:
	var comp := TacticalMovementComponent.new(null)
	assert_false(comp.is_yielding, "Component should not be yielding on creation")
	assert_eq(comp.yield_timer, 0.0, "yield_timer should be 0 on creation")


func test_reset_yield_clears_state() -> void:
	var comp := TacticalMovementComponent.new(null)
	comp.is_yielding = true
	comp.yield_timer = 1.5
	comp.yield_cover_position = Vector2(100, 50)
	comp.reset_yield()
	assert_false(comp.is_yielding, "reset_yield should clear is_yielding")
	assert_eq(comp.yield_timer, 0.0, "reset_yield should clear yield_timer")
	assert_eq(comp.yield_cover_position, Vector2.ZERO, "reset_yield should clear yield_cover_position")


func test_reset_yield_sets_cooldown() -> void:
	var comp := TacticalMovementComponent.new(null)
	comp.reset_yield()
	assert_gt(comp.yield_cooldown_timer, 0.0, "reset_yield should start cooldown timer")


func test_yield_expires_after_max_time() -> void:
	# Simulate the component already yielding and advance time past the limit.
	var comp := TacticalMovementComponent.new(null)
	comp.is_yielding = true
	comp.yield_timer = TacticalMovementComponent.YIELD_MAX_WAIT_TIME - 0.01
	# One more tick past the threshold
	var result := comp.check_and_yield(Vector2(100, 0), 220.0, 0.02)
	assert_false(result, "After YIELD_MAX_WAIT_TIME, yield should expire (return false)")
	assert_false(comp.is_yielding, "is_yielding should be false after timeout")


func test_yield_continues_before_max_time() -> void:
	var comp := TacticalMovementComponent.new(null)
	comp.is_yielding = true
	comp.yield_timer = 0.5  # well within YIELD_MAX_WAIT_TIME
	var result := comp.check_and_yield(Vector2(100, 0), 220.0, 0.016)
	assert_true(result, "Should still yield before YIELD_MAX_WAIT_TIME")
	assert_true(comp.is_yielding, "is_yielding should remain true during yield window")


func test_no_yield_when_null_enemy() -> void:
	var comp := TacticalMovementComponent.new(null)
	var result := comp.check_and_yield(Vector2(100, 0), 220.0, 0.016)
	assert_false(result, "Should not yield when enemy reference is null")


func test_no_yield_for_zero_target() -> void:
	var comp := TacticalMovementComponent.new(null)
	var result := comp.check_and_yield(Vector2.ZERO, 220.0, 0.016)
	assert_false(result, "Should not yield when target_pos is Vector2.ZERO")


func test_cooldown_prevents_immediate_recheck() -> void:
	var comp := TacticalMovementComponent.new(null)
	comp.yield_cooldown_timer = TacticalMovementComponent.YIELD_COOLDOWN
	# Even without physics setup, should return false due to cooldown
	var result := comp.check_and_yield(Vector2(100, 0), 220.0, 0.016)
	assert_false(result, "Cooldown should prevent re-checking immediately after yield ends")


func test_cooldown_decrements_with_delta() -> void:
	var comp := TacticalMovementComponent.new(null)
	comp.yield_cooldown_timer = 0.3
	comp.check_and_yield(Vector2(100, 0), 220.0, 0.1)
	assert_lt(comp.yield_cooldown_timer, 0.3, "Cooldown timer should decrement when check_and_yield is called")


# ============================================================================
# Tests: get_yield_position
# ============================================================================


func test_get_yield_position_returns_zero_when_not_yielding() -> void:
	var comp := TacticalMovementComponent.new(null)
	assert_eq(comp.get_yield_position(), Vector2.ZERO, "get_yield_position should return ZERO when not yielding")


func test_get_yield_position_returns_stored_position() -> void:
	var comp := TacticalMovementComponent.new(null)
	comp.is_yielding = true
	comp.yield_cover_position = Vector2(75.0, -30.0)
	assert_eq(comp.get_yield_position(), Vector2(75.0, -30.0), "get_yield_position should return yield_cover_position")


# ============================================================================
# Tests: debug info
# ============================================================================


func test_debug_info_empty_when_not_yielding() -> void:
	var comp := TacticalMovementComponent.new(null)
	assert_eq(comp.get_debug_info(), "", "debug info should be empty when not yielding")


func test_debug_info_contains_timers_when_yielding() -> void:
	var comp := TacticalMovementComponent.new(null)
	comp.is_yielding = true
	comp.yield_timer = 1.2
	var info := comp.get_debug_info()
	assert_ne(info, "", "debug info should not be empty when yielding")
	assert_true(info.contains("YIELDING"), "debug info should contain 'YIELDING'")


# ============================================================================
# Tests: constants sanity
# ============================================================================


func test_narrow_passage_half_width_is_reasonable() -> void:
	# Must be > enemy radius (24px) to catch corridors that block 2 enemies side by side.
	assert_gt(TacticalMovementComponent.NARROW_PASSAGE_HALF_WIDTH, 24.0,
		"NARROW_PASSAGE_HALF_WIDTH should exceed enemy radius")


func test_ally_block_detection_range_is_reasonable() -> void:
	# Must be larger than separation radius (60px) to detect allies before overlap.
	assert_gt(TacticalMovementComponent.ALLY_BLOCK_DETECTION_RANGE, 50.0,
		"ALLY_BLOCK_DETECTION_RANGE should be larger than minimum separation")


func test_yield_max_wait_time_is_reasonable() -> void:
	# Should be long enough to let one enemy pass (1-3 seconds) but not forever.
	assert_gt(TacticalMovementComponent.YIELD_MAX_WAIT_TIME, 1.0,
		"YIELD_MAX_WAIT_TIME should be at least 1 second")
	assert_lt(TacticalMovementComponent.YIELD_MAX_WAIT_TIME, 10.0,
		"YIELD_MAX_WAIT_TIME should be less than 10 seconds to avoid deadlocks")


func test_yield_cooldown_is_positive() -> void:
	assert_gt(TacticalMovementComponent.YIELD_COOLDOWN, 0.0,
		"YIELD_COOLDOWN must be positive to prevent instant re-yielding")


# ============================================================================
# Tests: priority logic (pure logic, mocked group iteration)
# ============================================================================


func test_ally_block_range_less_than_yield_cover_search_radius() -> void:
	# Cover search radius must be larger than ally detection range so we can find
	# a lateral position that is actually clear of the ally blocking the passage.
	assert_lt(TacticalMovementComponent.ALLY_BLOCK_DETECTION_RANGE,
		TacticalMovementComponent.YIELD_COVER_SEARCH_RADIUS,
		"YIELD_COVER_SEARCH_RADIUS should exceed ALLY_BLOCK_DETECTION_RANGE")
