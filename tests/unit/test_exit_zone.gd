extends GutTest
## Unit tests for ExitZone component.
##
## Tests the exit zone functionality including activation, player detection,
## and signal emission for level completion.


# ============================================================================
# Mock ExitZone for Logic Tests
# ============================================================================


class MockExitZone:
	## Whether the exit zone is currently active (all enemies eliminated).
	var _is_active: bool = false

	## Exit zone dimensions.
	var zone_width: float = 80.0
	var zone_height: float = 120.0

	## Exit zone position offset.
	var zone_offset: Vector2 = Vector2.ZERO

	## Signal tracking.
	var player_reached_exit_emitted: int = 0

	## Whether monitoring is enabled.
	var monitoring: bool = false

	## Whether visuals are visible.
	var visible_state: bool = false


	## Check if the exit zone is active.
	func is_active() -> bool:
		return _is_active


	## Activate the exit zone when all enemies are eliminated.
	func activate() -> void:
		_is_active = true
		monitoring = true
		visible_state = true


	## Deactivate the exit zone.
	func deactivate() -> void:
		_is_active = false
		monitoring = false
		visible_state = false


	## Simulate a body entering the zone.
	func simulate_body_entered(body_name: String, is_player: bool) -> void:
		if not _is_active:
			return

		# Check if it's the player
		if body_name == "Player" or is_player:
			player_reached_exit_emitted += 1


# ============================================================================
# Mock Level for Testing Exit Zone Integration
# ============================================================================


class MockLevelWithExit:
	## Reference to the exit zone.
	var exit_zone: MockExitZone = null

	## Whether the level has been cleared.
	var level_cleared: bool = false

	## Whether score screen was shown.
	var score_shown: bool = false

	## Current enemy count.
	var enemy_count: int = 5


	func _init() -> void:
		exit_zone = MockExitZone.new()


	## Called when an enemy dies.
	func on_enemy_died() -> void:
		enemy_count -= 1
		if enemy_count <= 0:
			level_cleared = true
			activate_exit_zone()


	## Activate the exit zone.
	func activate_exit_zone() -> void:
		if exit_zone:
			exit_zone.activate()


	## Called when player reaches exit.
	func on_player_reached_exit() -> void:
		if not level_cleared:
			return
		score_shown = true


var exit_zone: MockExitZone
var mock_level: MockLevelWithExit


func before_each() -> void:
	exit_zone = MockExitZone.new()
	mock_level = MockLevelWithExit.new()


func after_each() -> void:
	exit_zone = null
	mock_level = null


# ============================================================================
# Exit Zone State Tests
# ============================================================================


func test_exit_zone_starts_inactive() -> void:
	assert_false(exit_zone.is_active(),
		"Exit zone should start inactive")


func test_exit_zone_starts_not_monitoring() -> void:
	assert_false(exit_zone.monitoring,
		"Exit zone should not be monitoring initially")


func test_exit_zone_starts_hidden() -> void:
	assert_false(exit_zone.visible_state,
		"Exit zone should be hidden initially")


func test_exit_zone_default_dimensions() -> void:
	assert_eq(exit_zone.zone_width, 80.0,
		"Default zone width should be 80")
	assert_eq(exit_zone.zone_height, 120.0,
		"Default zone height should be 120")


# ============================================================================
# Activation Tests
# ============================================================================


func test_activate_sets_active() -> void:
	exit_zone.activate()

	assert_true(exit_zone.is_active(),
		"Exit zone should be active after activation")


func test_activate_enables_monitoring() -> void:
	exit_zone.activate()

	assert_true(exit_zone.monitoring,
		"Exit zone should be monitoring after activation")


func test_activate_shows_visuals() -> void:
	exit_zone.activate()

	assert_true(exit_zone.visible_state,
		"Exit zone visuals should be visible after activation")


func test_deactivate_sets_inactive() -> void:
	exit_zone.activate()
	exit_zone.deactivate()

	assert_false(exit_zone.is_active(),
		"Exit zone should be inactive after deactivation")


func test_deactivate_disables_monitoring() -> void:
	exit_zone.activate()
	exit_zone.deactivate()

	assert_false(exit_zone.monitoring,
		"Exit zone should not be monitoring after deactivation")


func test_deactivate_hides_visuals() -> void:
	exit_zone.activate()
	exit_zone.deactivate()

	assert_false(exit_zone.visible_state,
		"Exit zone visuals should be hidden after deactivation")


# ============================================================================
# Player Detection Tests
# ============================================================================


func test_player_detection_when_active() -> void:
	exit_zone.activate()
	exit_zone.simulate_body_entered("Player", true)

	assert_eq(exit_zone.player_reached_exit_emitted, 1,
		"Should emit player reached exit signal when active")


func test_player_detection_by_name() -> void:
	exit_zone.activate()
	exit_zone.simulate_body_entered("Player", false)

	assert_eq(exit_zone.player_reached_exit_emitted, 1,
		"Should detect player by name")


func test_player_detection_by_group() -> void:
	exit_zone.activate()
	exit_zone.simulate_body_entered("SomeNode", true)

	assert_eq(exit_zone.player_reached_exit_emitted, 1,
		"Should detect player by group membership")


func test_no_detection_when_inactive() -> void:
	# Don't activate
	exit_zone.simulate_body_entered("Player", true)

	assert_eq(exit_zone.player_reached_exit_emitted, 0,
		"Should not detect player when inactive")


func test_non_player_not_detected() -> void:
	exit_zone.activate()
	exit_zone.simulate_body_entered("Enemy", false)

	assert_eq(exit_zone.player_reached_exit_emitted, 0,
		"Should not detect non-player bodies")


# ============================================================================
# Level Integration Tests
# ============================================================================


func test_level_starts_with_enemies() -> void:
	assert_eq(mock_level.enemy_count, 5,
		"Level should start with 5 enemies")


func test_level_not_cleared_initially() -> void:
	assert_false(mock_level.level_cleared,
		"Level should not be cleared initially")


func test_exit_inactive_with_enemies() -> void:
	assert_false(mock_level.exit_zone.is_active(),
		"Exit zone should be inactive while enemies remain")


func test_killing_enemy_decrements_count() -> void:
	mock_level.on_enemy_died()

	assert_eq(mock_level.enemy_count, 4,
		"Enemy count should decrease when enemy dies")


func test_partial_clear_does_not_activate_exit() -> void:
	mock_level.on_enemy_died()
	mock_level.on_enemy_died()

	assert_false(mock_level.exit_zone.is_active(),
		"Exit should not activate with enemies remaining")


func test_full_clear_activates_exit() -> void:
	# Kill all 5 enemies
	for i in range(5):
		mock_level.on_enemy_died()

	assert_true(mock_level.exit_zone.is_active(),
		"Exit should activate when all enemies eliminated")


func test_full_clear_sets_level_cleared() -> void:
	for i in range(5):
		mock_level.on_enemy_died()

	assert_true(mock_level.level_cleared,
		"Level should be marked as cleared")


func test_score_not_shown_before_reaching_exit() -> void:
	for i in range(5):
		mock_level.on_enemy_died()

	assert_false(mock_level.score_shown,
		"Score should not show until player reaches exit")


func test_score_shown_after_reaching_exit() -> void:
	# Clear level
	for i in range(5):
		mock_level.on_enemy_died()

	# Player reaches exit
	mock_level.on_player_reached_exit()

	assert_true(mock_level.score_shown,
		"Score should show after player reaches exit")


func test_reaching_exit_before_clear_does_nothing() -> void:
	# Kill some but not all enemies
	mock_level.on_enemy_died()
	mock_level.on_enemy_died()

	# Try to trigger exit
	mock_level.on_player_reached_exit()

	assert_false(mock_level.score_shown,
		"Score should not show if level not cleared")


# ============================================================================
# Configuration Tests
# ============================================================================


func test_custom_dimensions() -> void:
	exit_zone.zone_width = 100.0
	exit_zone.zone_height = 200.0

	assert_eq(exit_zone.zone_width, 100.0,
		"Custom width should be applied")
	assert_eq(exit_zone.zone_height, 200.0,
		"Custom height should be applied")


func test_custom_offset() -> void:
	exit_zone.zone_offset = Vector2(50, 100)

	assert_eq(exit_zone.zone_offset, Vector2(50, 100),
		"Custom offset should be applied")
