extends GutTest
## Unit tests for DifficultyManager autoload.
##
## Tests the difficulty settings, mode checking, and game parameters
## that change based on difficulty level.


# Mock class that mirrors DifficultyManager's testable functionality
# without depending on autoload or file system
class MockDifficultyManager:
	## Difficulty levels enumeration (mirrors the actual enum)
	enum Difficulty {
		EASY,
		NORMAL,
		HARD
	}

	## Current difficulty level
	var current_difficulty: Difficulty = Difficulty.NORMAL

	## Signal for difficulty changes
	signal difficulty_changed(new_difficulty: Difficulty)

	func set_difficulty(difficulty: Difficulty) -> void:
		if current_difficulty != difficulty:
			current_difficulty = difficulty
			difficulty_changed.emit(difficulty)

	func get_difficulty() -> Difficulty:
		return current_difficulty

	func is_hard_mode() -> bool:
		return current_difficulty == Difficulty.HARD

	func is_normal_mode() -> bool:
		return current_difficulty == Difficulty.NORMAL

	func is_easy_mode() -> bool:
		return current_difficulty == Difficulty.EASY

	func get_difficulty_name() -> String:
		match current_difficulty:
			Difficulty.EASY:
				return "Easy"
			Difficulty.NORMAL:
				return "Normal"
			Difficulty.HARD:
				return "Hard"
			_:
				return "Unknown"

	func get_difficulty_name_for(difficulty: Difficulty) -> String:
		match difficulty:
			Difficulty.EASY:
				return "Easy"
			Difficulty.NORMAL:
				return "Normal"
			Difficulty.HARD:
				return "Hard"
			_:
				return "Unknown"

	func get_max_ammo() -> int:
		match current_difficulty:
			Difficulty.EASY:
				return 90
			Difficulty.NORMAL:
				return 90
			Difficulty.HARD:
				return 60
			_:
				return 90

	func is_distraction_attack_enabled() -> bool:
		return current_difficulty == Difficulty.HARD

	func get_detection_delay() -> float:
		match current_difficulty:
			Difficulty.EASY:
				return 0.5
			Difficulty.NORMAL:
				return 0.6
			Difficulty.HARD:
				return 0.2
			_:
				return 0.6


var manager: MockDifficultyManager


func before_each() -> void:
	manager = MockDifficultyManager.new()


func after_each() -> void:
	manager = null


# ============================================================================
# Initial State Tests
# ============================================================================


func test_initial_difficulty_is_normal() -> void:
	assert_eq(manager.current_difficulty, MockDifficultyManager.Difficulty.NORMAL,
		"Initial difficulty should be NORMAL")


func test_initial_is_normal_mode_true() -> void:
	assert_true(manager.is_normal_mode(), "is_normal_mode() should return true initially")


func test_initial_is_hard_mode_false() -> void:
	assert_false(manager.is_hard_mode(), "is_hard_mode() should return false initially")


func test_initial_is_easy_mode_false() -> void:
	assert_false(manager.is_easy_mode(), "is_easy_mode() should return false initially")


# ============================================================================
# Difficulty Change Tests
# ============================================================================


func test_set_difficulty_to_easy() -> void:
	manager.set_difficulty(MockDifficultyManager.Difficulty.EASY)

	assert_eq(manager.current_difficulty, MockDifficultyManager.Difficulty.EASY,
		"Difficulty should be EASY after setting")
	assert_true(manager.is_easy_mode(), "is_easy_mode() should return true")
	assert_false(manager.is_normal_mode(), "is_normal_mode() should return false")
	assert_false(manager.is_hard_mode(), "is_hard_mode() should return false")


func test_set_difficulty_to_hard() -> void:
	manager.set_difficulty(MockDifficultyManager.Difficulty.HARD)

	assert_eq(manager.current_difficulty, MockDifficultyManager.Difficulty.HARD,
		"Difficulty should be HARD after setting")
	assert_true(manager.is_hard_mode(), "is_hard_mode() should return true")
	assert_false(manager.is_normal_mode(), "is_normal_mode() should return false")
	assert_false(manager.is_easy_mode(), "is_easy_mode() should return false")


func test_set_same_difficulty_does_not_emit_signal() -> void:
	var signal_emitted := false
	manager.difficulty_changed.connect(func(_d): signal_emitted = true)

	# Set to same difficulty (NORMAL)
	manager.set_difficulty(MockDifficultyManager.Difficulty.NORMAL)

	assert_false(signal_emitted, "Signal should not be emitted when setting same difficulty")


func test_set_different_difficulty_emits_signal() -> void:
	var signal_emitted := false
	var received_difficulty: int = -1
	manager.difficulty_changed.connect(func(d):
		signal_emitted = true
		received_difficulty = d
	)

	manager.set_difficulty(MockDifficultyManager.Difficulty.HARD)

	assert_true(signal_emitted, "Signal should be emitted when changing difficulty")
	assert_eq(received_difficulty, MockDifficultyManager.Difficulty.HARD,
		"Signal should pass new difficulty value")


func test_get_difficulty_returns_current() -> void:
	manager.set_difficulty(MockDifficultyManager.Difficulty.EASY)

	assert_eq(manager.get_difficulty(), MockDifficultyManager.Difficulty.EASY,
		"get_difficulty() should return current difficulty")


# ============================================================================
# Difficulty Name Tests
# ============================================================================


func test_get_difficulty_name_easy() -> void:
	manager.set_difficulty(MockDifficultyManager.Difficulty.EASY)

	assert_eq(manager.get_difficulty_name(), "Easy", "Easy difficulty name should be 'Easy'")


func test_get_difficulty_name_normal() -> void:
	# Default is NORMAL
	assert_eq(manager.get_difficulty_name(), "Normal", "Normal difficulty name should be 'Normal'")


func test_get_difficulty_name_hard() -> void:
	manager.set_difficulty(MockDifficultyManager.Difficulty.HARD)

	assert_eq(manager.get_difficulty_name(), "Hard", "Hard difficulty name should be 'Hard'")


func test_get_difficulty_name_for_specific_difficulty() -> void:
	assert_eq(manager.get_difficulty_name_for(MockDifficultyManager.Difficulty.EASY), "Easy")
	assert_eq(manager.get_difficulty_name_for(MockDifficultyManager.Difficulty.NORMAL), "Normal")
	assert_eq(manager.get_difficulty_name_for(MockDifficultyManager.Difficulty.HARD), "Hard")


# ============================================================================
# Max Ammo Tests
# ============================================================================


func test_max_ammo_easy_mode() -> void:
	manager.set_difficulty(MockDifficultyManager.Difficulty.EASY)

	assert_eq(manager.get_max_ammo(), 90, "Easy mode should have 90 max ammo (3 magazines)")


func test_max_ammo_normal_mode() -> void:
	# Default is NORMAL
	assert_eq(manager.get_max_ammo(), 90, "Normal mode should have 90 max ammo (3 magazines)")


func test_max_ammo_hard_mode() -> void:
	manager.set_difficulty(MockDifficultyManager.Difficulty.HARD)

	assert_eq(manager.get_max_ammo(), 60, "Hard mode should have 60 max ammo (2 magazines)")


# ============================================================================
# Distraction Attack Tests
# ============================================================================


func test_distraction_attack_disabled_in_easy_mode() -> void:
	manager.set_difficulty(MockDifficultyManager.Difficulty.EASY)

	assert_false(manager.is_distraction_attack_enabled(),
		"Distraction attack should be disabled in easy mode")


func test_distraction_attack_disabled_in_normal_mode() -> void:
	# Default is NORMAL
	assert_false(manager.is_distraction_attack_enabled(),
		"Distraction attack should be disabled in normal mode")


func test_distraction_attack_enabled_in_hard_mode() -> void:
	manager.set_difficulty(MockDifficultyManager.Difficulty.HARD)

	assert_true(manager.is_distraction_attack_enabled(),
		"Distraction attack should be enabled in hard mode")


# ============================================================================
# Detection Delay Tests
# ============================================================================


func test_detection_delay_easy_mode() -> void:
	manager.set_difficulty(MockDifficultyManager.Difficulty.EASY)

	assert_eq(manager.get_detection_delay(), 0.5,
		"Easy mode should have 0.5s detection delay")


func test_detection_delay_normal_mode() -> void:
	# Default is NORMAL
	assert_eq(manager.get_detection_delay(), 0.6,
		"Normal mode should have 0.6s detection delay")


func test_detection_delay_hard_mode() -> void:
	manager.set_difficulty(MockDifficultyManager.Difficulty.HARD)

	assert_eq(manager.get_detection_delay(), 0.2,
		"Hard mode should have 0.2s detection delay (fastest reaction)")


# ============================================================================
# Difficulty Cycling Tests
# ============================================================================


func test_cycle_through_all_difficulties() -> void:
	# Start at NORMAL (default)
	assert_true(manager.is_normal_mode())

	# Go to EASY
	manager.set_difficulty(MockDifficultyManager.Difficulty.EASY)
	assert_true(manager.is_easy_mode())
	assert_eq(manager.get_max_ammo(), 90)
	assert_eq(manager.get_detection_delay(), 0.5)

	# Go to HARD
	manager.set_difficulty(MockDifficultyManager.Difficulty.HARD)
	assert_true(manager.is_hard_mode())
	assert_eq(manager.get_max_ammo(), 60)
	assert_true(manager.is_distraction_attack_enabled())

	# Go back to NORMAL
	manager.set_difficulty(MockDifficultyManager.Difficulty.NORMAL)
	assert_true(manager.is_normal_mode())
	assert_eq(manager.get_max_ammo(), 90)
	assert_false(manager.is_distraction_attack_enabled())
