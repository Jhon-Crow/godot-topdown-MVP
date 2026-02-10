extends GutTest
## Tests for AggressionComponent (Issue #729 fix).
##
## Validates that aggressive enemies navigate toward other enemies
## even when there is no line of sight.

const AggressionComponent := preload("res://scripts/components/aggression_component.gd")


## Mock parent CharacterBody2D for testing
class MockEnemy extends CharacterBody2D:
	var _is_alive: bool = true
	var _shoot_timer: float = 0.0
	var velocity: Vector2 = Vector2.ZERO
	var _move_called: bool = false
	var _move_target: Vector2 = Vector2.ZERO
	var _move_speed: float = 0.0

	func _ready() -> void:
		add_to_group("enemies")

	func _move_to_target_nav(target_pos: Vector2, speed: float) -> bool:
		_move_called = true
		_move_target = target_pos
		_move_speed = speed
		velocity = (target_pos - global_position).normalized() * speed
		return true

	func _force_model_to_face_direction(_dir: Vector2) -> void:
		pass

	func _get_weapon_forward_direction() -> Vector2:
		return Vector2.RIGHT.rotated(rotation)

	func _can_shoot() -> bool:
		return true

	func _shoot() -> void:
		pass

	func _log_to_file(_msg: String) -> void:
		pass


func test_find_nearest_enemy_any_returns_enemy_without_los() -> void:
	# Given: Two enemies where one cannot see the other
	var enemy1 := MockEnemy.new()
	var enemy2 := MockEnemy.new()
	add_child_autofree(enemy1)
	add_child_autofree(enemy2)
	enemy1.global_position = Vector2(0, 0)
	enemy2.global_position = Vector2(500, 500)  # Far away

	# Create aggression component on enemy1
	var comp := AggressionComponent.new()
	enemy1.add_child(comp)

	await wait_frames(2)

	# When: Finding any enemy (regardless of LOS)
	var result := comp._find_nearest_enemy_any()

	# Then: Should find enemy2 even without LOS check
	assert_not_null(result, "Should find an enemy without requiring LOS")
	assert_eq(result, enemy2, "Should return the other enemy")


func test_find_nearest_enemy_any_excludes_self() -> void:
	# Given: A single enemy
	var enemy1 := MockEnemy.new()
	add_child_autofree(enemy1)

	var comp := AggressionComponent.new()
	enemy1.add_child(comp)

	await wait_frames(2)

	# When: Finding any enemy
	var result := comp._find_nearest_enemy_any()

	# Then: Should return null (no other enemies)
	assert_null(result, "Should not target self")


func test_find_nearest_enemy_any_excludes_dead() -> void:
	# Given: Two enemies where one is dead
	var enemy1 := MockEnemy.new()
	var enemy2 := MockEnemy.new()
	add_child_autofree(enemy1)
	add_child_autofree(enemy2)
	enemy2._is_alive = false  # Dead enemy

	var comp := AggressionComponent.new()
	enemy1.add_child(comp)

	await wait_frames(2)

	# When: Finding any enemy
	var result := comp._find_nearest_enemy_any()

	# Then: Should return null (only dead enemy available)
	assert_null(result, "Should not target dead enemies")


func test_process_combat_navigates_when_no_los_target() -> void:
	# Given: An aggressive enemy with a navigation target (no LOS)
	var enemy1 := MockEnemy.new()
	var enemy2 := MockEnemy.new()
	add_child_autofree(enemy1)
	add_child_autofree(enemy2)
	enemy1.global_position = Vector2(0, 0)
	enemy2.global_position = Vector2(500, 500)

	var comp := AggressionComponent.new()
	enemy1.add_child(comp)

	await wait_frames(2)

	# Set aggressive without a visible target (simulating no LOS)
	comp.set_aggressive(true)
	comp._target = null  # No visible target

	# When: Processing combat
	comp.process_combat(0.016, 3.0, 0.5, 200.0)

	# Then: Should have called _move_to_target_nav to navigate toward enemy2
	assert_true(enemy1._move_called, "Should navigate when no visible target but enemies exist")


func test_process_combat_stops_when_no_enemies() -> void:
	# Given: A single aggressive enemy with no other enemies
	var enemy1 := MockEnemy.new()
	add_child_autofree(enemy1)
	enemy1.velocity = Vector2(100, 100)  # Initial velocity

	var comp := AggressionComponent.new()
	enemy1.add_child(comp)

	await wait_frames(2)

	comp.set_aggressive(true)
	comp._target = null

	# When: Processing combat
	comp.process_combat(0.016, 3.0, 0.5, 200.0)

	# Then: Should stop moving (no enemies to navigate toward)
	assert_eq(enemy1.velocity, Vector2.ZERO, "Should stop when no enemies exist")


func test_set_aggressive_clears_nav_target() -> void:
	# Given: An aggression component with a nav target
	var enemy1 := MockEnemy.new()
	add_child_autofree(enemy1)

	var comp := AggressionComponent.new()
	enemy1.add_child(comp)

	await wait_frames(2)

	comp._nav_target = enemy1  # Set a dummy nav target

	# When: Setting aggressive (start or end)
	comp.set_aggressive(true)

	# Then: Nav target should be cleared
	assert_null(comp._nav_target, "Nav target should be cleared when aggression starts")

	# And when ending
	comp._nav_target = enemy1
	comp.set_aggressive(false)
	assert_null(comp._nav_target, "Nav target should be cleared when aggression ends")


func test_find_nearest_enemy_returns_closest() -> void:
	# Given: Three enemies at different distances
	var enemy1 := MockEnemy.new()
	var enemy2 := MockEnemy.new()
	var enemy3 := MockEnemy.new()
	add_child_autofree(enemy1)
	add_child_autofree(enemy2)
	add_child_autofree(enemy3)

	enemy1.global_position = Vector2(0, 0)
	enemy2.global_position = Vector2(100, 0)  # Closest
	enemy3.global_position = Vector2(500, 500)  # Far

	var comp := AggressionComponent.new()
	enemy1.add_child(comp)

	await wait_frames(2)

	# When: Finding nearest enemy
	var result := comp._find_nearest_enemy_any()

	# Then: Should return closest enemy (enemy2)
	assert_eq(result, enemy2, "Should return closest enemy")
