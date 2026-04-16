extends GutTest
## Tests for EnemyTeleportComponent (Issue #752).
##
## Validates cooldown timing, distance constraints, nav snap tolerance,
## cooldown timer logic, and ready flag behaviour.

const TeleportComponent := preload("res://scripts/components/enemy_teleport_component.gd")


# =============================================================================
# Constants
# =============================================================================

func test_cooldown_constant() -> void:
	assert_eq(TeleportComponent.COOLDOWN, 5.0,
		"COOLDOWN should be 5.0 seconds")


func test_min_distance_constant() -> void:
	assert_eq(TeleportComponent.MIN_DISTANCE, 10.0,
		"MIN_DISTANCE should be 10.0 px")


func test_nav_snap_tolerance_constant() -> void:
	assert_eq(TeleportComponent.NAV_SNAP_TOLERANCE, 50.0,
		"NAV_SNAP_TOLERANCE should be 50.0 px")


func test_viewport_fraction_constant() -> void:
	assert_eq(TeleportComponent.VIEWPORT_FRACTION, 1.0,
		"VIEWPORT_FRACTION should be 1.0")


func test_default_diagonal_constant() -> void:
	assert_eq(TeleportComponent.DEFAULT_DIAGONAL, 1469.0,
		"DEFAULT_DIAGONAL should be 1469.0")


# =============================================================================
# Initial State
# =============================================================================

func test_initial_cooldown_timer_zero() -> void:
	var comp := TeleportComponent.new()
	add_child_autofree(comp)

	assert_eq(comp._cooldown_timer, 0.0,
		"Cooldown timer should start at 0.0")


func test_ready_flag_set_with_character_parent() -> void:
	var comp := TeleportComponent.new()
	var parent := CharacterBody2D.new()
	parent.add_child(comp)
	add_child_autofree(parent)

	assert_true(comp._ready_flag,
		"Ready flag should be true when parent is a CharacterBody2D")


func test_ready_flag_false_with_non_character_parent() -> void:
	var comp := TeleportComponent.new()
	var parent := Node2D.new()
	parent.add_child(comp)
	add_child_autofree(parent)

	assert_false(comp._ready_flag,
		"Ready flag should be false when parent is not a CharacterBody2D")


# =============================================================================
# is_ready
# =============================================================================

func test_is_ready_when_flag_set_and_cooldown_zero() -> void:
	var comp := TeleportComponent.new()
	var parent := CharacterBody2D.new()
	parent.add_child(comp)
	add_child_autofree(parent)

	assert_true(comp.is_ready(),
		"Should be ready when flag is set and cooldown is zero")


func test_is_not_ready_when_on_cooldown() -> void:
	var comp := TeleportComponent.new()
	var parent := CharacterBody2D.new()
	parent.add_child(comp)
	add_child_autofree(parent)

	comp._cooldown_timer = 3.0
	assert_false(comp.is_ready(),
		"Should not be ready when cooldown timer is positive")


func test_is_not_ready_when_flag_false() -> void:
	var comp := TeleportComponent.new()
	add_child_autofree(comp)

	comp._ready_flag = false
	comp._cooldown_timer = 0.0
	assert_false(comp.is_ready(),
		"Should not be ready when _ready_flag is false")


# =============================================================================
# Cooldown Timer Logic
# =============================================================================

func test_update_decrements_cooldown() -> void:
	var comp := TeleportComponent.new()
	add_child_autofree(comp)

	comp._cooldown_timer = 3.0
	comp.update(1.0)

	assert_almost_eq(comp._cooldown_timer, 2.0, 0.01,
		"Cooldown timer should decrement by delta")


func test_update_cooldown_goes_below_zero() -> void:
	var comp := TeleportComponent.new()
	add_child_autofree(comp)

	comp._cooldown_timer = 0.5
	comp.update(1.0)

	assert_lt(comp._cooldown_timer, 0.0,
		"Cooldown timer can go below zero (is_ready checks <= 0)")


func test_update_does_nothing_when_cooldown_zero() -> void:
	var comp := TeleportComponent.new()
	add_child_autofree(comp)

	comp._cooldown_timer = 0.0
	comp.update(0.5)

	assert_eq(comp._cooldown_timer, 0.0,
		"Cooldown timer should remain 0 when already at 0")


# =============================================================================
# try_teleport Rejection Cases
# =============================================================================

func test_try_teleport_rejects_when_not_ready() -> void:
	var comp := TeleportComponent.new()
	add_child_autofree(comp)

	comp._ready_flag = false
	var result := comp.try_teleport(Vector2(100, 100))
	assert_false(result, "Should reject teleport when not ready")


func test_try_teleport_rejects_zero_target() -> void:
	var comp := TeleportComponent.new()
	var parent := CharacterBody2D.new()
	parent.add_child(comp)
	add_child_autofree(parent)

	var result := comp.try_teleport(Vector2.ZERO)
	assert_false(result, "Should reject teleport to (0,0)")


func test_try_teleport_rejects_too_close() -> void:
	var comp := TeleportComponent.new()
	var parent := CharacterBody2D.new()
	parent.add_child(comp)
	add_child_autofree(parent)

	parent.global_position = Vector2(100, 100)
	var result := comp.try_teleport(Vector2(105, 100))  # 5px away < MIN_DISTANCE
	assert_false(result, "Should reject teleport distance below MIN_DISTANCE")


# =============================================================================
# try_damage_teleport
# =============================================================================

func test_try_damage_teleport_rejects_when_not_ready() -> void:
	var comp := TeleportComponent.new()
	add_child_autofree(comp)

	comp._ready_flag = false
	var result := comp.try_damage_teleport(Vector2(200, 200), Vector2(300, 300))
	assert_false(result, "try_damage_teleport should reject when not ready")


func test_try_damage_teleport_rejects_zero_positions() -> void:
	var comp := TeleportComponent.new()
	var parent := CharacterBody2D.new()
	parent.add_child(comp)
	add_child_autofree(parent)

	var result := comp.try_damage_teleport(Vector2.ZERO, Vector2.ZERO)
	assert_false(result, "try_damage_teleport should reject zero positions")
