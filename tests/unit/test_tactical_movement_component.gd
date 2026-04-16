extends GutTest
## Tests for TacticalMovementComponent (Issue #1249).
##
## Validates narrow-passage constants, yield timing, yield state management,
## and reset_yield behaviour.

const TacticalMovementComp := preload("res://scripts/components/tactical_movement_component.gd")


# =============================================================================
# Constants
# =============================================================================

func test_ally_block_detection_range_constant() -> void:
	assert_eq(TacticalMovementComp.ALLY_BLOCK_DETECTION_RANGE, 100.0,
		"ALLY_BLOCK_DETECTION_RANGE should be 100.0 px")


func test_narrow_passage_half_width_constant() -> void:
	assert_eq(TacticalMovementComp.NARROW_PASSAGE_HALF_WIDTH, 64.0,
		"NARROW_PASSAGE_HALF_WIDTH should be 64.0 px")


func test_yield_max_wait_time_constant() -> void:
	assert_eq(TacticalMovementComp.YIELD_MAX_WAIT_TIME, 3.0,
		"YIELD_MAX_WAIT_TIME should be 3.0 seconds")


func test_yield_cooldown_constant() -> void:
	assert_eq(TacticalMovementComp.YIELD_COOLDOWN, 0.5,
		"YIELD_COOLDOWN should be 0.5 seconds")


func test_yield_cover_search_radius_constant() -> void:
	assert_eq(TacticalMovementComp.YIELD_COVER_SEARCH_RADIUS, 150.0,
		"YIELD_COVER_SEARCH_RADIUS should be 150.0 px")


func test_yield_nearby_radius_constant() -> void:
	assert_eq(TacticalMovementComp.YIELD_NEARBY_RADIUS, 200.0,
		"YIELD_NEARBY_RADIUS should be 200.0 px")


# =============================================================================
# Initial State
# =============================================================================

func test_initial_state_not_yielding() -> void:
	var mock_enemy := Node2D.new()
	add_child_autofree(mock_enemy)
	var comp := TacticalMovementComp.new(mock_enemy)

	assert_false(comp.is_yielding, "Should not be yielding initially")
	assert_eq(comp.yield_timer, 0.0, "Yield timer should start at 0.0")
	assert_eq(comp.yield_cooldown_timer, 0.0, "Yield cooldown timer should start at 0.0")
	assert_eq(comp.yield_cover_position, Vector2.ZERO,
		"Yield cover position should be Vector2.ZERO initially")


func test_init_stores_enemy_reference() -> void:
	var mock_enemy := Node2D.new()
	add_child_autofree(mock_enemy)
	var comp := TacticalMovementComp.new(mock_enemy)

	assert_eq(comp.enemy, mock_enemy, "Should store the enemy reference")


# =============================================================================
# Yield State Management
# =============================================================================

func test_reset_yield_clears_state() -> void:
	var mock_enemy := Node2D.new()
	add_child_autofree(mock_enemy)
	var comp := TacticalMovementComp.new(mock_enemy)

	# Simulate yield state
	comp.is_yielding = true
	comp.yield_timer = 2.0
	comp.yield_cover_position = Vector2(100, 200)

	comp.reset_yield()

	assert_false(comp.is_yielding, "Should not be yielding after reset")
	assert_eq(comp.yield_timer, 0.0, "Yield timer should be 0 after reset")
	assert_eq(comp.yield_cover_position, Vector2.ZERO,
		"Yield cover position should be ZERO after reset")
	assert_eq(comp.yield_cooldown_timer, TacticalMovementComp.YIELD_COOLDOWN,
		"Yield cooldown timer should be set to YIELD_COOLDOWN after reset")


func test_get_yield_position_returns_stored_position() -> void:
	var mock_enemy := Node2D.new()
	add_child_autofree(mock_enemy)
	var comp := TacticalMovementComp.new(mock_enemy)

	comp.yield_cover_position = Vector2(50, 75)
	assert_eq(comp.get_yield_position(), Vector2(50, 75),
		"get_yield_position should return the stored cover position")


func test_get_yield_position_returns_zero_by_default() -> void:
	var mock_enemy := Node2D.new()
	add_child_autofree(mock_enemy)
	var comp := TacticalMovementComp.new(mock_enemy)

	assert_eq(comp.get_yield_position(), Vector2.ZERO,
		"get_yield_position should return ZERO when no cover found")


# =============================================================================
# check_and_yield — Edge Cases
# =============================================================================

func test_check_and_yield_returns_false_with_null_enemy() -> void:
	var comp := TacticalMovementComp.new(null)

	var result := comp.check_and_yield(Vector2(100, 100), 200.0, 0.016)
	assert_false(result, "Should return false with null enemy")


func test_check_and_yield_returns_false_with_freed_enemy() -> void:
	var mock_enemy := Node2D.new()
	add_child_autofree(mock_enemy)
	var comp := TacticalMovementComp.new(mock_enemy)

	mock_enemy.queue_free()
	await wait_frames(2)

	var result := comp.check_and_yield(Vector2(100, 100), 200.0, 0.016)
	assert_false(result, "Should return false with freed enemy")


func test_check_and_yield_returns_false_with_zero_target() -> void:
	var mock_enemy := CharacterBody2D.new()
	add_child_autofree(mock_enemy)
	var comp := TacticalMovementComp.new(mock_enemy)

	var result := comp.check_and_yield(Vector2.ZERO, 200.0, 0.016)
	assert_false(result, "Should return false with zero target position")


func test_check_and_yield_returns_false_during_cooldown() -> void:
	var mock_enemy := CharacterBody2D.new()
	add_child_autofree(mock_enemy)
	var comp := TacticalMovementComp.new(mock_enemy)

	comp.yield_cooldown_timer = 0.3
	var result := comp.check_and_yield(Vector2(500, 500), 200.0, 0.016)
	assert_false(result, "Should return false during cooldown")


# =============================================================================
# Yield Timer — Timeout Forces Through
# =============================================================================

func test_yielding_continues_until_timeout() -> void:
	var mock_enemy := CharacterBody2D.new()
	add_child_autofree(mock_enemy)
	var comp := TacticalMovementComp.new(mock_enemy)

	comp.is_yielding = true
	comp.yield_timer = 1.0

	var result := comp.check_and_yield(Vector2(100, 100), 200.0, 0.5)
	assert_true(result, "Should keep yielding before timeout")
	assert_almost_eq(comp.yield_timer, 1.5, 0.01,
		"Yield timer should increment by delta")


func test_yielding_timeout_stops_yield() -> void:
	var mock_enemy := CharacterBody2D.new()
	add_child_autofree(mock_enemy)
	var comp := TacticalMovementComp.new(mock_enemy)

	comp.is_yielding = true
	comp.yield_timer = 2.8

	var result := comp.check_and_yield(Vector2(100, 100), 200.0, 0.5)
	assert_false(result, "Should stop yielding after timeout")
	assert_false(comp.is_yielding, "is_yielding should be false after timeout")
	assert_eq(comp.yield_cooldown_timer, TacticalMovementComp.YIELD_COOLDOWN,
		"Cooldown should be set after timeout")


# =============================================================================
# Cooldown Timer Decrement
# =============================================================================

func test_cooldown_timer_decrements_during_check() -> void:
	var mock_enemy := CharacterBody2D.new()
	add_child_autofree(mock_enemy)
	var comp := TacticalMovementComp.new(mock_enemy)

	comp.yield_cooldown_timer = 0.4
	comp.check_and_yield(Vector2(100, 100), 200.0, 0.2)

	assert_almost_eq(comp.yield_cooldown_timer, 0.2, 0.01,
		"Cooldown timer should decrement by delta during check_and_yield")


func test_cooldown_timer_clamps_at_zero() -> void:
	var mock_enemy := CharacterBody2D.new()
	add_child_autofree(mock_enemy)
	var comp := TacticalMovementComp.new(mock_enemy)

	comp.yield_cooldown_timer = 0.1
	comp.check_and_yield(Vector2(100, 100), 200.0, 0.5)

	assert_eq(comp.yield_cooldown_timer, 0.0,
		"Cooldown timer should clamp to 0.0")


# =============================================================================
# Debug Info
# =============================================================================

func test_debug_info_empty_when_not_yielding() -> void:
	var mock_enemy := Node2D.new()
	add_child_autofree(mock_enemy)
	var comp := TacticalMovementComp.new(mock_enemy)

	assert_eq(comp.get_debug_info(), "",
		"Debug info should be empty when not yielding")


func test_debug_info_shows_yielding_state() -> void:
	var mock_enemy := Node2D.new()
	add_child_autofree(mock_enemy)
	var comp := TacticalMovementComp.new(mock_enemy)

	comp.is_yielding = true
	comp.yield_timer = 1.5

	var info := comp.get_debug_info()
	assert_true(info.begins_with("YIELDING"),
		"Debug info should show YIELDING state")


# =============================================================================
# Ally Blocking Lane Filter
# =============================================================================

func test_ally_blocking_path_rejects_side_lane_hits() -> void:
	var enemy := CharacterBody2D.new()
	add_child_autofree(enemy)
	enemy.global_position = Vector2.ZERO

	var ally := CharacterBody2D.new()
	add_child_autofree(ally)
	ally.global_position = Vector2(40, TacticalMovementComp.NARROW_PASSAGE_HALF_WIDTH)
	ally.add_to_group("enemies")

	var comp := TacticalMovementComp.new(enemy)
	assert_false(comp._is_ally_blocking_path(Vector2.RIGHT),
		"Ally far to the side should not count as blocking the same corridor lane")


func test_ally_blocking_path_accepts_forward_lane_hits() -> void:
	var enemy := CharacterBody2D.new()
	add_child_autofree(enemy)
	enemy.global_position = Vector2.ZERO

	var ally := CharacterBody2D.new()
	add_child_autofree(ally)
	ally.global_position = Vector2(40, 8)
	ally.add_to_group("enemies")

	var comp := TacticalMovementComp.new(enemy)
	assert_true(comp._is_ally_blocking_path(Vector2.RIGHT),
		"Ally ahead in the same lane should count as blocking")
