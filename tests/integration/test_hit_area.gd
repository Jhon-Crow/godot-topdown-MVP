extends GutTest
## Integration tests for HitArea behavior.
##
## Tests that HitArea correctly forwards on_hit calls to parent.


const HitAreaScript = preload("res://scripts/objects/hit_area.gd")


var hit_area: Area2D
var parent_node: Node2D


# Mock parent that has on_hit method
class MockParentWithOnHit:
	extends Node2D

	var hit_called: bool = false
	var hit_count: int = 0

	func on_hit() -> void:
		hit_called = true
		hit_count += 1


# Mock parent without on_hit method
class MockParentWithoutOnHit:
	extends Node2D
	pass


# ============================================================================
# Setup
# ============================================================================


func before_each() -> void:
	parent_node = null
	hit_area = null


func after_each() -> void:
	parent_node = null
	hit_area = null


func _create_hit_area_with_parent(parent: Node2D) -> Area2D:
	parent_node = parent
	add_child_autoqfree(parent_node)

	hit_area = Area2D.new()
	hit_area.set_script(HitAreaScript)
	parent_node.add_child(hit_area)

	return hit_area


# ============================================================================
# on_hit Forwarding Tests
# ============================================================================


func test_on_hit_forwards_to_parent() -> void:
	var mock_parent := MockParentWithOnHit.new()
	_create_hit_area_with_parent(mock_parent)

	hit_area.on_hit()

	assert_true(mock_parent.hit_called, "Parent's on_hit should be called")


func test_on_hit_increments_parent_hit_count() -> void:
	var mock_parent := MockParentWithOnHit.new()
	_create_hit_area_with_parent(mock_parent)

	hit_area.on_hit()
	hit_area.on_hit()
	hit_area.on_hit()

	assert_eq(mock_parent.hit_count, 3, "Parent's on_hit should be called 3 times")


func test_on_hit_does_nothing_without_parent_method() -> void:
	var mock_parent := MockParentWithoutOnHit.new()
	_create_hit_area_with_parent(mock_parent)

	# Should not crash when parent doesn't have on_hit
	hit_area.on_hit()

	# Test passes if no error occurred
	pass_test("on_hit should not crash when parent lacks on_hit method")


func test_on_hit_does_nothing_without_parent() -> void:
	# Create hit area without adding to tree (no parent)
	hit_area = Area2D.new()
	hit_area.set_script(HitAreaScript)
	add_child_autoqfree(hit_area)

	# Remove from tree to simulate no parent
	remove_child(hit_area)

	# Should not crash when there's no parent
	# Note: get_parent() returns null when not in tree
	hit_area.on_hit()

	# Re-add to tree for autoqfree cleanup
	add_child(hit_area)

	pass_test("on_hit should not crash when parent is null")


# ============================================================================
# Integration with Different Parent Types
# ============================================================================


class MockEnemy:
	extends CharacterBody2D

	var damage_taken: int = 0
	var is_dead: bool = false

	func on_hit() -> void:
		damage_taken += 1
		if damage_taken >= 3:
			is_dead = true


func test_on_hit_works_with_characterbody2d_parent() -> void:
	var mock_enemy := MockEnemy.new()
	_create_hit_area_with_parent(mock_enemy)

	hit_area.on_hit()
	hit_area.on_hit()

	assert_eq(mock_enemy.damage_taken, 2, "Enemy should take 2 damage")
	assert_false(mock_enemy.is_dead, "Enemy should not be dead yet")


func test_on_hit_can_kill_parent() -> void:
	var mock_enemy := MockEnemy.new()
	_create_hit_area_with_parent(mock_enemy)

	hit_area.on_hit()
	hit_area.on_hit()
	hit_area.on_hit()

	assert_eq(mock_enemy.damage_taken, 3, "Enemy should take 3 damage")
	assert_true(mock_enemy.is_dead, "Enemy should be dead")


# ============================================================================
# Edge Cases
# ============================================================================


class MockParentWithReturnValue:
	extends Node2D

	var last_return: bool = false

	func on_hit() -> bool:
		last_return = true
		return true


func test_on_hit_ignores_parent_return_value() -> void:
	var mock_parent := MockParentWithReturnValue.new()
	_create_hit_area_with_parent(mock_parent)

	# HitArea.on_hit() returns void, so parent's return value is ignored
	hit_area.on_hit()

	assert_true(mock_parent.last_return, "Parent's on_hit was still called")


class MockParentWithArgs:
	extends Node2D

	var received_args: Array = []

	func on_hit(damage: int = 0, _attacker: Node = null) -> void:
		received_args.append(damage)


func test_on_hit_calls_without_args() -> void:
	var mock_parent := MockParentWithArgs.new()
	_create_hit_area_with_parent(mock_parent)

	# HitArea calls on_hit without arguments
	hit_area.on_hit()

	# Parent's on_hit should receive default values
	assert_eq(mock_parent.received_args.size(), 1, "on_hit should be called once")
	assert_eq(mock_parent.received_args[0], 0, "Should use default damage value")


# ============================================================================
# Multiple HitAreas on Same Parent Tests
# ============================================================================


func test_multiple_hit_areas_on_same_parent() -> void:
	var mock_parent := MockParentWithOnHit.new()
	add_child_autoqfree(mock_parent)

	var hit_area1 := Area2D.new()
	hit_area1.set_script(HitAreaScript)
	mock_parent.add_child(hit_area1)

	var hit_area2 := Area2D.new()
	hit_area2.set_script(HitAreaScript)
	mock_parent.add_child(hit_area2)

	hit_area1.on_hit()
	hit_area2.on_hit()
	hit_area1.on_hit()

	assert_eq(mock_parent.hit_count, 3, "Parent should receive all hits from both areas")
