extends GutTest
## Unit tests for GameManager functionality.
##
## Tests the game statistics tracking and calculation logic.
## Note: These tests focus on the pure calculation methods that can be tested
## without requiring the full Godot scene tree.


# We test the GameManager logic by creating a mock instance
# that doesn't depend on autoload


class MockGameManager:
	## Mock class that mirrors GameManager's testable functionality
	var kills: int = 0
	var shots_fired: int = 0
	var hits_landed: int = 0
	var player_alive: bool = true
	var debug_mode_enabled: bool = false

	func register_shot() -> void:
		shots_fired += 1

	func register_hit() -> void:
		hits_landed += 1

	func register_kill() -> void:
		kills += 1

	func get_accuracy() -> float:
		if shots_fired == 0:
			return 0.0
		return (float(hits_landed) / float(shots_fired)) * 100.0

	func toggle_debug_mode() -> void:
		debug_mode_enabled = not debug_mode_enabled

	func is_debug_mode_enabled() -> bool:
		return debug_mode_enabled

	func _reset_stats() -> void:
		kills = 0
		shots_fired = 0
		hits_landed = 0
		player_alive = true


var manager: MockGameManager


func before_each() -> void:
	manager = MockGameManager.new()


func after_each() -> void:
	manager = null


# ============================================================================
# Statistics Tracking Tests
# ============================================================================


func test_initial_stats_are_zero() -> void:
	assert_eq(manager.kills, 0, "Initial kills should be 0")
	assert_eq(manager.shots_fired, 0, "Initial shots_fired should be 0")
	assert_eq(manager.hits_landed, 0, "Initial hits_landed should be 0")
	assert_true(manager.player_alive, "Player should be alive initially")


func test_register_shot_increments_counter() -> void:
	manager.register_shot()

	assert_eq(manager.shots_fired, 1, "Shots fired should be 1 after one shot")


func test_register_multiple_shots() -> void:
	manager.register_shot()
	manager.register_shot()
	manager.register_shot()

	assert_eq(manager.shots_fired, 3, "Shots fired should be 3 after three shots")


func test_register_hit_increments_counter() -> void:
	manager.register_hit()

	assert_eq(manager.hits_landed, 1, "Hits landed should be 1 after one hit")


func test_register_multiple_hits() -> void:
	manager.register_hit()
	manager.register_hit()

	assert_eq(manager.hits_landed, 2, "Hits landed should be 2 after two hits")


func test_register_kill_increments_counter() -> void:
	manager.register_kill()

	assert_eq(manager.kills, 1, "Kills should be 1 after one kill")


func test_register_multiple_kills() -> void:
	manager.register_kill()
	manager.register_kill()
	manager.register_kill()

	assert_eq(manager.kills, 3, "Kills should be 3 after three kills")


# ============================================================================
# Accuracy Calculation Tests
# ============================================================================


func test_accuracy_is_zero_with_no_shots() -> void:
	var accuracy := manager.get_accuracy()

	assert_eq(accuracy, 0.0, "Accuracy should be 0 when no shots fired")


func test_accuracy_is_100_with_all_hits() -> void:
	manager.shots_fired = 10
	manager.hits_landed = 10

	var accuracy := manager.get_accuracy()

	assert_eq(accuracy, 100.0, "Accuracy should be 100% when all shots hit")


func test_accuracy_is_50_with_half_hits() -> void:
	manager.shots_fired = 10
	manager.hits_landed = 5

	var accuracy := manager.get_accuracy()

	assert_eq(accuracy, 50.0, "Accuracy should be 50% when half shots hit")


func test_accuracy_is_0_with_no_hits() -> void:
	manager.shots_fired = 10
	manager.hits_landed = 0

	var accuracy := manager.get_accuracy()

	assert_eq(accuracy, 0.0, "Accuracy should be 0% when no shots hit")


func test_accuracy_with_fractional_result() -> void:
	manager.shots_fired = 3
	manager.hits_landed = 1

	var accuracy := manager.get_accuracy()

	assert_almost_eq(accuracy, 33.33, 0.01, "Accuracy should be ~33.33% for 1/3 hits")


func test_accuracy_calculation_formula() -> void:
	manager.shots_fired = 20
	manager.hits_landed = 15

	var accuracy := manager.get_accuracy()

	# 15/20 = 0.75 * 100 = 75%
	assert_eq(accuracy, 75.0, "Accuracy should follow (hits/shots) * 100 formula")


# ============================================================================
# Debug Mode Tests
# ============================================================================


func test_debug_mode_initially_disabled() -> void:
	assert_false(manager.debug_mode_enabled, "Debug mode should be disabled initially")


func test_toggle_debug_mode_enables() -> void:
	manager.toggle_debug_mode()

	assert_true(manager.is_debug_mode_enabled(), "Debug mode should be enabled after toggle")


func test_toggle_debug_mode_disables() -> void:
	manager.debug_mode_enabled = true

	manager.toggle_debug_mode()

	assert_false(manager.is_debug_mode_enabled(), "Debug mode should be disabled after toggle")


func test_toggle_debug_mode_multiple_times() -> void:
	manager.toggle_debug_mode()  # Enable
	assert_true(manager.is_debug_mode_enabled(), "Should be enabled")

	manager.toggle_debug_mode()  # Disable
	assert_false(manager.is_debug_mode_enabled(), "Should be disabled")

	manager.toggle_debug_mode()  # Enable again
	assert_true(manager.is_debug_mode_enabled(), "Should be enabled again")


# ============================================================================
# Reset Stats Tests
# ============================================================================


func test_reset_stats_clears_all_counters() -> void:
	manager.kills = 5
	manager.shots_fired = 100
	manager.hits_landed = 50
	manager.player_alive = false

	manager._reset_stats()

	assert_eq(manager.kills, 0, "Kills should be reset to 0")
	assert_eq(manager.shots_fired, 0, "Shots fired should be reset to 0")
	assert_eq(manager.hits_landed, 0, "Hits landed should be reset to 0")
	assert_true(manager.player_alive, "Player alive should be reset to true")


# ============================================================================
# Combined Scenario Tests
# ============================================================================


func test_full_combat_scenario() -> void:
	# Simulate a combat scenario
	# Player fires 5 shots, lands 3, gets 2 kills

	manager.register_shot()  # 1
	manager.register_shot()  # 2
	manager.register_hit()   # Hit 1
	manager.register_kill()  # Kill 1
	manager.register_shot()  # 3
	manager.register_hit()   # Hit 2
	manager.register_shot()  # 4
	manager.register_shot()  # 5
	manager.register_hit()   # Hit 3
	manager.register_kill()  # Kill 2

	assert_eq(manager.shots_fired, 5, "Should have 5 shots")
	assert_eq(manager.hits_landed, 3, "Should have 3 hits")
	assert_eq(manager.kills, 2, "Should have 2 kills")
	assert_eq(manager.get_accuracy(), 60.0, "Accuracy should be 60% (3/5)")


func test_perfect_accuracy_scenario() -> void:
	# Every shot is a hit
	for i in range(10):
		manager.register_shot()
		manager.register_hit()

	assert_eq(manager.get_accuracy(), 100.0, "Perfect accuracy")


func test_terrible_accuracy_scenario() -> void:
	# No hits at all
	for i in range(10):
		manager.register_shot()

	assert_eq(manager.get_accuracy(), 0.0, "Zero accuracy")
