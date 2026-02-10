extends GutTest
## Unit tests for Issue #723: Enemies should lose player after teleportation or invisibility.
##
## Tests that enemies:
## 1. Lose track of player when player becomes invisible
## 2. Lose track of player when player teleports
## 3. Enter SEARCHING mode at the last known position


# ============================================================================
# Mock Enemy for Testing Memory Reset
# ============================================================================


class MockEnemy:
	## AI States
	enum AIState {
		IDLE,
		COMBAT,
		SEARCHING
	}

	## Current AI state
	var _current_state: AIState = AIState.IDLE

	## Whether enemy can see player
	var _can_see_player: bool = false

	## Last known player position
	var _last_known_player_position: Vector2 = Vector2.ZERO

	## Memory object
	var _memory: MockMemory = null

	## Confusion timer after memory reset
	var _memory_reset_confusion_timer: float = 0.0
	const MEMORY_RESET_CONFUSION_DURATION: float = 0.5

	## Tracking for test verification
	var reset_memory_called: bool = false
	var transition_to_searching_called: bool = false
	var searching_position: Vector2 = Vector2.ZERO

	func _init() -> void:
		_memory = MockMemory.new()

	## Reset enemy memory (Issue #318, #723)
	func reset_memory() -> void:
		reset_memory_called = true
		var old_position := _memory.suspected_position if _memory.has_target() else Vector2.ZERO
		var had_target := old_position != Vector2.ZERO

		# Reset visibility and detection states
		_can_see_player = false
		_memory_reset_confusion_timer = MEMORY_RESET_CONFUSION_DURATION

		if had_target:
			# Set LOW confidence (0.35) - puts enemy in search mode at old position
			_memory.suspected_position = old_position
			_memory.confidence = 0.35
			_last_known_player_position = old_position
			_transition_to_searching(old_position)
		else:
			_memory.reset()
			_last_known_player_position = Vector2.ZERO

	## Transition to SEARCHING state
	func _transition_to_searching(center_position: Vector2) -> void:
		transition_to_searching_called = true
		searching_position = center_position
		_current_state = AIState.SEARCHING

	## Get current state
	func get_current_state() -> AIState:
		return _current_state


class MockMemory:
	var suspected_position: Vector2 = Vector2.ZERO
	var confidence: float = 0.0
	var last_updated: int = 0

	func has_target() -> bool:
		return suspected_position != Vector2.ZERO and confidence > 0.0

	func reset() -> void:
		suspected_position = Vector2.ZERO
		confidence = 0.0
		last_updated = 0


# ============================================================================
# Mock Player for Testing
# ============================================================================


class MockPlayer:
	var _invisibility_suit: MockInvisibilitySuit = null
	var _invisibility_suit_equipped: bool = false

	## Signals
	signal invisibility_changed(active: bool, charges_remaining: int, max_charges: int)

	func equip_invisibility_suit() -> void:
		_invisibility_suit = MockInvisibilitySuit.new()
		_invisibility_suit_equipped = true

	func activate_invisibility() -> bool:
		if _invisibility_suit_equipped and _invisibility_suit:
			return _invisibility_suit.activate()
		return false

	func is_invisible() -> bool:
		if not _invisibility_suit_equipped or _invisibility_suit == null:
			return false
		return _invisibility_suit.is_invisible()


class MockInvisibilitySuit:
	const MAX_CHARGES: int = 2
	const EFFECT_DURATION: float = 4.0

	var charges: int = MAX_CHARGES
	var is_active: bool = false
	var _effect_timer: float = 0.0

	signal invisibility_activated(charges_remaining: int)
	signal invisibility_deactivated(charges_remaining: int)

	func activate() -> bool:
		if is_active or charges <= 0:
			return false

		charges -= 1
		is_active = true
		_effect_timer = EFFECT_DURATION
		invisibility_activated.emit(charges)
		return true

	func is_invisible() -> bool:
		return is_active


# ============================================================================
# Tests for Enemy Losing Player on Invisibility
# ============================================================================


func test_enemy_cannot_see_invisible_player() -> void:
	var player := MockPlayer.new()
	player.equip_invisibility_suit()

	# Player is initially visible
	assert_false(player.is_invisible(), "Player should not be invisible initially")

	# Activate invisibility
	var activated := player.activate_invisibility()
	assert_true(activated, "Invisibility should activate successfully")
	assert_true(player.is_invisible(), "Player should be invisible after activation")


func test_invisibility_activation_should_reset_enemy_memory() -> void:
	var enemy := MockEnemy.new()

	# Set up enemy tracking player
	enemy._can_see_player = true
	enemy._current_state = MockEnemy.AIState.COMBAT
	enemy._memory.suspected_position = Vector2(100, 100)
	enemy._memory.confidence = 0.9

	# Simulate invisibility activation triggering reset_memory
	enemy.reset_memory()

	# Verify memory was reset
	assert_true(enemy.reset_memory_called, "reset_memory should be called")
	assert_false(enemy._can_see_player, "Enemy should lose sight of player")
	assert_gt(enemy._memory_reset_confusion_timer, 0.0, "Confusion timer should be set")


func test_enemy_enters_searching_mode_when_player_goes_invisible() -> void:
	var enemy := MockEnemy.new()

	# Enemy is tracking player at position (200, 150)
	var player_pos := Vector2(200, 150)
	enemy._can_see_player = true
	enemy._current_state = MockEnemy.AIState.COMBAT
	enemy._memory.suspected_position = player_pos
	enemy._memory.confidence = 0.9

	# Player goes invisible - enemy should reset memory and search at last known position
	enemy.reset_memory()

	assert_true(enemy.transition_to_searching_called, "Enemy should transition to SEARCHING")
	assert_eq(enemy.searching_position, player_pos, "Enemy should search at last known position")
	assert_eq(enemy.get_current_state(), MockEnemy.AIState.SEARCHING, "Enemy state should be SEARCHING")


func test_enemy_without_target_does_not_search_on_invisibility() -> void:
	var enemy := MockEnemy.new()

	# Enemy has no memory of player
	enemy._memory.reset()
	enemy._can_see_player = false

	# Reset memory when player goes invisible
	enemy.reset_memory()

	assert_false(enemy.transition_to_searching_called, "Enemy with no target should not search")


# ============================================================================
# Tests for Enemy Losing Player on Teleportation
# ============================================================================


func test_teleport_should_reset_enemy_memory() -> void:
	var enemy := MockEnemy.new()

	# Enemy is tracking player
	enemy._can_see_player = true
	enemy._current_state = MockEnemy.AIState.COMBAT
	enemy._memory.suspected_position = Vector2(300, 200)
	enemy._memory.confidence = 0.95

	# Simulate teleport triggering reset_memory
	enemy.reset_memory()

	assert_true(enemy.reset_memory_called, "reset_memory should be called on teleport")
	assert_false(enemy._can_see_player, "Enemy should lose sight after teleport")


func test_enemy_searches_old_position_after_teleport() -> void:
	var enemy := MockEnemy.new()

	# Enemy saw player at position (500, 400) before teleport
	var old_player_pos := Vector2(500, 400)
	enemy._can_see_player = true
	enemy._current_state = MockEnemy.AIState.COMBAT
	enemy._memory.suspected_position = old_player_pos
	enemy._memory.confidence = 0.8

	# Player teleports - enemy should search at OLD position
	enemy.reset_memory()

	assert_true(enemy.transition_to_searching_called, "Enemy should search after teleport")
	assert_eq(enemy.searching_position, old_player_pos, "Enemy should search at OLD position (before teleport)")
	assert_eq(enemy._memory.confidence, 0.35, "Memory confidence should be LOW (0.35) for searching")


func test_multiple_enemies_all_reset_on_teleport() -> void:
	var enemies: Array[MockEnemy] = []

	# Create 3 enemies tracking player
	for i in range(3):
		var enemy := MockEnemy.new()
		enemy._can_see_player = true
		enemy._memory.suspected_position = Vector2(100 + i * 50, 100)
		enemy._memory.confidence = 0.7
		enemies.append(enemy)

	# Simulate teleport resetting all enemies
	for enemy in enemies:
		enemy.reset_memory()

	# Verify all enemies reset
	for i in range(3):
		assert_true(enemies[i].reset_memory_called, "Enemy %d should have memory reset" % i)
		assert_false(enemies[i]._can_see_player, "Enemy %d should lose sight" % i)
		assert_true(enemies[i].transition_to_searching_called, "Enemy %d should search" % i)


# ============================================================================
# Tests for Search Mode Behavior
# ============================================================================


func test_searching_mode_sets_low_confidence() -> void:
	var enemy := MockEnemy.new()

	# Enemy has high confidence before reset
	enemy._memory.suspected_position = Vector2(250, 300)
	enemy._memory.confidence = 0.95

	# Reset memory
	enemy.reset_memory()

	# Confidence should drop to 0.35 (search mode)
	assert_eq(enemy._memory.confidence, 0.35, "Search mode should have LOW confidence (0.35)")


func test_confusion_timer_blocks_immediate_redetection() -> void:
	var enemy := MockEnemy.new()

	# Reset memory
	enemy.reset_memory()

	# Confusion timer should be set to block vision/sound detection temporarily
	assert_eq(enemy._memory_reset_confusion_timer, MockEnemy.MEMORY_RESET_CONFUSION_DURATION,
		"Confusion timer should be set to block immediate redetection")


# ============================================================================
# Integration Scenario Tests
# ============================================================================


func test_full_scenario_combat_to_invisible_to_searching() -> void:
	var enemy := MockEnemy.new()
	var player := MockPlayer.new()
	player.equip_invisibility_suit()

	# Step 1: Enemy is in COMBAT, tracking player at (400, 300)
	var combat_pos := Vector2(400, 300)
	enemy._current_state = MockEnemy.AIState.COMBAT
	enemy._can_see_player = true
	enemy._memory.suspected_position = combat_pos
	enemy._memory.confidence = 0.9

	# Step 2: Player activates invisibility
	player.activate_invisibility()
	assert_true(player.is_invisible(), "Player should be invisible")

	# Step 3: Enemy memory is reset (would be called by player's _on_invisibility_activated)
	enemy.reset_memory()

	# Step 4: Verify enemy state
	assert_false(enemy._can_see_player, "Enemy cannot see invisible player")
	assert_eq(enemy.get_current_state(), MockEnemy.AIState.SEARCHING, "Enemy should be SEARCHING")
	assert_eq(enemy.searching_position, combat_pos, "Enemy searches at last seen position")
	assert_gt(enemy._memory_reset_confusion_timer, 0.0, "Confusion prevents immediate redetection")


func test_full_scenario_combat_to_teleport_to_searching() -> void:
	var enemy := MockEnemy.new()

	# Step 1: Enemy tracking player at (600, 500)
	var pre_teleport_pos := Vector2(600, 500)
	enemy._current_state = MockEnemy.AIState.COMBAT
	enemy._can_see_player = true
	enemy._memory.suspected_position = pre_teleport_pos
	enemy._memory.confidence = 0.85

	# Step 2: Player teleports to (100, 100) - but enemy doesn't know new position
	# Enemy memory reset is triggered
	enemy.reset_memory()

	# Step 3: Verify enemy behavior
	assert_false(enemy._can_see_player, "Enemy loses sight after teleport")
	assert_eq(enemy.get_current_state(), MockEnemy.AIState.SEARCHING, "Enemy should SEARCH")
	assert_eq(enemy.searching_position, pre_teleport_pos, "Enemy searches OLD position")
	assert_eq(enemy._last_known_player_position, pre_teleport_pos, "Last known pos is OLD position")
