extends GutTest
## Integration tests for enemy death and bullet pass-through behavior.
##
## Tests that dead enemies allow bullets to pass through instead of absorbing them.
## This ensures ammunition is not wasted on already-dead enemies.


const HitAreaScript = preload("res://scripts/objects/hit_area.gd")


var enemy: CharacterBody2D
var hit_area: Area2D
var hit_collision_shape: CollisionShape2D


# Mock enemy that simulates the real enemy's death behavior
# This matches the multi-layered approach used in the real enemy.gd
class MockEnemy:
	extends CharacterBody2D

	var _is_alive: bool = true
	var _hit_area: Area2D = null
	var _hit_collision_shape: CollisionShape2D = null
	var _original_hit_area_layer: int = 0
	var _original_hit_area_mask: int = 0
	var hit_count: int = 0
	var current_health: int = 3

	signal died
	signal hit

	func on_hit() -> void:
		if not _is_alive:
			return
		hit_count += 1
		hit.emit()
		current_health -= 1
		if current_health <= 0:
			_on_death()

	func _on_death() -> void:
		_is_alive = false
		died.emit()
		# Multi-layered approach to disable collision (matching real enemy.gd)
		# Approach 1: Disable CollisionShape2D
		if _hit_collision_shape:
			_hit_collision_shape.set_deferred("disabled", true)
		# Approach 2: Move to unused collision layers
		if _hit_area:
			_hit_area.set_deferred("collision_layer", 0)
			_hit_area.set_deferred("collision_mask", 0)
		# Approach 3: Disable monitorable/monitoring
		if _hit_area:
			_hit_area.set_deferred("monitorable", false)
			_hit_area.set_deferred("monitoring", false)

	func _reset() -> void:
		_is_alive = true
		current_health = 3
		hit_count = 0
		# Re-enable CollisionShape2D
		if _hit_collision_shape:
			_hit_collision_shape.disabled = false
		# Restore collision layers
		if _hit_area:
			_hit_area.collision_layer = _original_hit_area_layer
			_hit_area.collision_mask = _original_hit_area_mask
		# Re-enable monitorable/monitoring
		if _hit_area:
			_hit_area.monitorable = true
			_hit_area.monitoring = true

	func is_alive() -> bool:
		return _is_alive


# ============================================================================
# Setup
# ============================================================================


func before_each() -> void:
	enemy = null
	hit_area = null
	hit_collision_shape = null


func after_each() -> void:
	enemy = null
	hit_area = null
	hit_collision_shape = null


func _create_enemy_with_hit_area() -> MockEnemy:
	enemy = MockEnemy.new()
	add_child_autoqfree(enemy)

	hit_area = Area2D.new()
	hit_area.set_script(HitAreaScript)
	hit_area.monitorable = true
	hit_area.monitoring = true
	hit_area.collision_layer = 2  # Match real enemy scene
	hit_area.collision_mask = 16  # Match real enemy scene
	enemy.add_child(hit_area)
	enemy._hit_area = hit_area
	# Store original collision layers
	enemy._original_hit_area_layer = hit_area.collision_layer
	enemy._original_hit_area_mask = hit_area.collision_mask

	# Add collision shape to hit area
	hit_collision_shape = CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 24.0
	hit_collision_shape.shape = shape
	hit_area.add_child(hit_collision_shape)
	enemy._hit_collision_shape = hit_collision_shape

	return enemy


# ============================================================================
# HitArea State Tests
# ============================================================================


func test_hit_area_is_enabled_when_alive() -> void:
	var mock_enemy := _create_enemy_with_hit_area()

	assert_true(mock_enemy.is_alive(), "Enemy should be alive initially")
	assert_true(hit_area.monitorable, "HitArea should be monitorable when enemy is alive")
	assert_true(hit_area.monitoring, "HitArea should be monitoring when enemy is alive")


func test_hit_area_is_disabled_on_death() -> void:
	var mock_enemy := _create_enemy_with_hit_area()

	# Kill the enemy by dealing enough damage
	mock_enemy.on_hit()
	mock_enemy.on_hit()
	mock_enemy.on_hit()  # Health goes to 0

	# Wait for deferred calls to be processed
	await get_tree().process_frame

	assert_false(mock_enemy.is_alive(), "Enemy should be dead")
	assert_false(hit_area.monitorable, "HitArea should not be monitorable when dead")
	assert_false(hit_area.monitoring, "HitArea should not be monitoring when dead")


func test_collision_shape_is_disabled_on_death() -> void:
	var mock_enemy := _create_enemy_with_hit_area()

	# Kill the enemy
	mock_enemy.on_hit()
	mock_enemy.on_hit()
	mock_enemy.on_hit()

	# Wait for deferred calls to be processed
	await get_tree().process_frame

	assert_false(mock_enemy.is_alive(), "Enemy should be dead")
	assert_true(hit_collision_shape.disabled, "CollisionShape2D should be disabled when dead")


func test_collision_layers_are_cleared_on_death() -> void:
	var mock_enemy := _create_enemy_with_hit_area()

	# Verify initial layers
	assert_eq(hit_area.collision_layer, 2, "Initial collision_layer should be 2")
	assert_eq(hit_area.collision_mask, 16, "Initial collision_mask should be 16")

	# Kill the enemy
	mock_enemy.on_hit()
	mock_enemy.on_hit()
	mock_enemy.on_hit()

	# Wait for deferred calls to be processed
	await get_tree().process_frame

	assert_eq(hit_area.collision_layer, 0, "collision_layer should be 0 when dead")
	assert_eq(hit_area.collision_mask, 0, "collision_mask should be 0 when dead")


func test_hit_area_is_re_enabled_on_reset() -> void:
	var mock_enemy := _create_enemy_with_hit_area()

	# Kill the enemy
	mock_enemy.on_hit()
	mock_enemy.on_hit()
	mock_enemy.on_hit()

	# Wait for deferred calls
	await get_tree().process_frame

	# Reset the enemy (simulating respawn)
	mock_enemy._reset()

	assert_true(mock_enemy.is_alive(), "Enemy should be alive after reset")
	assert_true(hit_area.monitorable, "HitArea should be monitorable after reset")
	assert_true(hit_area.monitoring, "HitArea should be monitoring after reset")


func test_collision_shape_is_re_enabled_on_reset() -> void:
	var mock_enemy := _create_enemy_with_hit_area()

	# Kill and respawn
	mock_enemy.on_hit()
	mock_enemy.on_hit()
	mock_enemy.on_hit()
	await get_tree().process_frame

	mock_enemy._reset()

	assert_false(hit_collision_shape.disabled, "CollisionShape2D should be enabled after reset")


func test_collision_layers_are_restored_on_reset() -> void:
	var mock_enemy := _create_enemy_with_hit_area()

	# Kill and respawn
	mock_enemy.on_hit()
	mock_enemy.on_hit()
	mock_enemy.on_hit()
	await get_tree().process_frame

	mock_enemy._reset()

	assert_eq(hit_area.collision_layer, 2, "collision_layer should be restored after reset")
	assert_eq(hit_area.collision_mask, 16, "collision_mask should be restored after reset")


# ============================================================================
# Hit Detection Tests
# ============================================================================


func test_alive_enemy_receives_hits() -> void:
	var mock_enemy := _create_enemy_with_hit_area()

	hit_area.on_hit()
	hit_area.on_hit()

	assert_eq(mock_enemy.hit_count, 2, "Enemy should receive hits when alive")
	assert_eq(mock_enemy.current_health, 1, "Enemy health should decrease")


func test_dead_enemy_ignores_hits() -> void:
	var mock_enemy := _create_enemy_with_hit_area()

	# Kill the enemy first
	mock_enemy.on_hit()
	mock_enemy.on_hit()
	mock_enemy.on_hit()  # Dies here, hit_count = 3

	# Try to hit the dead enemy
	mock_enemy.on_hit()  # Should be ignored
	mock_enemy.on_hit()  # Should be ignored

	assert_eq(mock_enemy.hit_count, 3, "Dead enemy should not count additional hits")
	assert_eq(mock_enemy.current_health, 0, "Health should stay at 0")


func test_died_signal_emitted_on_death() -> void:
	var mock_enemy := _create_enemy_with_hit_area()
	var died_signal_received := false

	mock_enemy.died.connect(func(): died_signal_received = true)

	mock_enemy.on_hit()
	mock_enemy.on_hit()
	mock_enemy.on_hit()

	assert_true(died_signal_received, "Died signal should be emitted when enemy dies")


func test_died_signal_only_emitted_once() -> void:
	var mock_enemy := _create_enemy_with_hit_area()
	var died_signal_count := 0

	mock_enemy.died.connect(func(): died_signal_count += 1)

	# Kill and continue hitting
	for i in range(5):
		mock_enemy.on_hit()

	assert_eq(died_signal_count, 1, "Died signal should only be emitted once")


# ============================================================================
# Respawn Behavior Tests
# ============================================================================


func test_respawned_enemy_can_be_hit_again() -> void:
	var mock_enemy := _create_enemy_with_hit_area()

	# Kill the enemy
	mock_enemy.on_hit()
	mock_enemy.on_hit()
	mock_enemy.on_hit()

	# Wait for deferred calls
	await get_tree().process_frame

	# Reset (respawn)
	mock_enemy._reset()

	# Hit the respawned enemy
	mock_enemy.on_hit()
	mock_enemy.on_hit()

	assert_eq(mock_enemy.hit_count, 2, "Respawned enemy should receive hits")
	assert_eq(mock_enemy.current_health, 1, "Respawned enemy health should decrease from max")


func test_multiple_death_respawn_cycles() -> void:
	var mock_enemy := _create_enemy_with_hit_area()

	# First cycle
	mock_enemy.on_hit()
	mock_enemy.on_hit()
	mock_enemy.on_hit()
	await get_tree().process_frame
	assert_false(mock_enemy.is_alive(), "Should be dead after first cycle")

	mock_enemy._reset()
	assert_true(mock_enemy.is_alive(), "Should be alive after first reset")

	# Second cycle
	mock_enemy.on_hit()
	mock_enemy.on_hit()
	mock_enemy.on_hit()
	await get_tree().process_frame
	assert_false(mock_enemy.is_alive(), "Should be dead after second cycle")

	mock_enemy._reset()
	assert_true(mock_enemy.is_alive(), "Should be alive after second reset")
	assert_true(hit_area.monitorable, "HitArea should be monitorable after second reset")


# ============================================================================
# Edge Cases
# ============================================================================


func test_enemy_without_hit_area_does_not_crash_on_death() -> void:
	# Create enemy without hit area
	var standalone_enemy := MockEnemy.new()
	standalone_enemy._hit_area = null
	add_child_autoqfree(standalone_enemy)

	# Should not crash when dying without hit area
	standalone_enemy.on_hit()
	standalone_enemy.on_hit()
	standalone_enemy.on_hit()

	await get_tree().process_frame

	assert_false(standalone_enemy.is_alive(), "Enemy should be dead")
	pass_test("No crash when enemy dies without hit area reference")


func test_enemy_without_hit_area_does_not_crash_on_reset() -> void:
	# Create enemy without hit area
	var standalone_enemy := MockEnemy.new()
	standalone_enemy._hit_area = null
	add_child_autoqfree(standalone_enemy)

	# Kill and reset without hit area
	standalone_enemy.on_hit()
	standalone_enemy.on_hit()
	standalone_enemy.on_hit()
	await get_tree().process_frame

	standalone_enemy._reset()

	assert_true(standalone_enemy.is_alive(), "Enemy should be alive after reset")
	pass_test("No crash when enemy resets without hit area reference")


# ============================================================================
# Bullet CharacterBody2D Collision Tests
# ============================================================================


func test_is_alive_returns_true_when_alive() -> void:
	var mock_enemy := _create_enemy_with_hit_area()

	assert_true(mock_enemy.is_alive(), "is_alive() should return true for alive enemy")
	assert_true(mock_enemy.has_method("is_alive"), "Enemy should have is_alive method")


func test_is_alive_returns_false_when_dead() -> void:
	var mock_enemy := _create_enemy_with_hit_area()

	# Kill the enemy
	mock_enemy.on_hit()
	mock_enemy.on_hit()
	mock_enemy.on_hit()

	assert_false(mock_enemy.is_alive(), "is_alive() should return false for dead enemy")


func test_is_alive_is_set_immediately_on_death() -> void:
	var mock_enemy := _create_enemy_with_hit_area()

	# Note: is_alive should be set to false SYNCHRONOUSLY in _on_death(),
	# not deferred. This allows bullets to check the alive state immediately.
	mock_enemy.on_hit()
	mock_enemy.on_hit()
	mock_enemy.on_hit()  # This triggers _on_death() which sets _is_alive = false

	# Check immediately without waiting for next frame
	assert_false(mock_enemy.is_alive(), "is_alive should be false immediately after death")
