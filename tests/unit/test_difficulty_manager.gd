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
		HARD,
		POWER_FANTASY,
		BLACK_METAL,  ## Issue #958: 25% less HP, 25% faster, B&W+red visual filter
		GUNSLINGER    ## Issue #1727: 2x less HP, 4x ammo, no laser sights, kill last-chance
	}

	## Night mode reaction delay multiplier (Issue #825)
	const NIGHT_MODE_REACTION_DELAY_MULTIPLIER: float = 1.3

	## Current difficulty level
	var current_difficulty: Difficulty = Difficulty.NORMAL

	## Night mode state for testing (Issue #825)
	var _night_mode_active: bool = false

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

	func is_power_fantasy_mode() -> bool:
		return current_difficulty == Difficulty.POWER_FANTASY

	func is_black_metal_mode() -> bool:
		return current_difficulty == Difficulty.BLACK_METAL

	func is_gunslinger_mode() -> bool:
		return current_difficulty == Difficulty.GUNSLINGER

	func get_difficulty_name() -> String:
		match current_difficulty:
			Difficulty.EASY:
				return "Easy"
			Difficulty.NORMAL:
				return "Normal"
			Difficulty.HARD:
				return "Hard"
			Difficulty.POWER_FANTASY:
				return "Power Fantasy"
			Difficulty.BLACK_METAL:
				return "Black Metal"
			Difficulty.GUNSLINGER:
				return "Gunslinger"
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
			Difficulty.POWER_FANTASY:
				return "Power Fantasy"
			Difficulty.BLACK_METAL:
				return "Black Metal"
			Difficulty.GUNSLINGER:
				return "Gunslinger"
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
			Difficulty.POWER_FANTASY:
				return 270
			Difficulty.BLACK_METAL:
				return 90
			Difficulty.GUNSLINGER:
				return 360  # 4x normal ammo
			_:
				return 90

	func is_distraction_attack_enabled() -> bool:
		return current_difficulty == Difficulty.HARD

	func get_hp_multiplier() -> float:
		if current_difficulty == Difficulty.BLACK_METAL:
			return 0.75
		if current_difficulty == Difficulty.GUNSLINGER:
			return 0.5  # 2x less HP
		return 1.0

	func should_disable_laser_sight() -> bool:
		return current_difficulty == Difficulty.GUNSLINGER

	func is_kill_last_chance_enabled() -> bool:
		return current_difficulty == Difficulty.POWER_FANTASY or current_difficulty == Difficulty.GUNSLINGER

	func is_special_last_chance_disabled() -> bool:
		return current_difficulty == Difficulty.GUNSLINGER

	func should_apply_gunslinger_enemy_glow() -> bool:
		return current_difficulty == Difficulty.GUNSLINGER

	func get_player_speed_multiplier() -> float:
		if current_difficulty == Difficulty.GUNSLINGER:
			return 1.5
		if current_difficulty == Difficulty.BLACK_METAL:
			return 1.25
		return 1.0

	## Simulated settings file existence for is_first_launch() tests (Issue #1734).
	var _settings_file_exists: bool = false

	## Simulate is_first_launch() without touching the filesystem (Issue #1734).
	func is_first_launch() -> bool:
		return not _settings_file_exists

	## Mark the settings file as existing (simulates a previous save) (Issue #1734).
	func simulate_settings_saved() -> void:
		_settings_file_exists = true

	## Reset difficulty to default and clear the simulated settings file (Issue #1734).
	func reset_to_default() -> void:
		current_difficulty = Difficulty.NORMAL
		_settings_file_exists = false

	## Set night mode active state for testing (Issue #825).
	func set_night_mode_active(active: bool) -> void:
		_night_mode_active = active

	## Check if night mode is active (Issue #825).
	func _is_night_mode_active() -> bool:
		return _night_mode_active

	func get_detection_delay() -> float:
		var base_delay: float
		match current_difficulty:
			Difficulty.EASY:
				base_delay = 0.5
			Difficulty.NORMAL:
				base_delay = 0.6
			Difficulty.HARD:
				base_delay = 0.2
			Difficulty.POWER_FANTASY:
				base_delay = 0.8
			Difficulty.BLACK_METAL:
				base_delay = 0.3
			Difficulty.GUNSLINGER:
				base_delay = 0.4
			_:
				base_delay = 0.6
		# Issue #825: In night mode, enemies react 30% slower
		if _is_night_mode_active():
			return base_delay * NIGHT_MODE_REACTION_DELAY_MULTIPLIER
		return base_delay


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
	assert_eq(manager.get_difficulty_name_for(MockDifficultyManager.Difficulty.POWER_FANTASY), "Power Fantasy")
	assert_eq(manager.get_difficulty_name_for(MockDifficultyManager.Difficulty.BLACK_METAL), "Black Metal")


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


# ============================================================================
# Power Fantasy Mode Tests (Issue #492)
# ============================================================================


func test_set_difficulty_to_power_fantasy() -> void:
	manager.set_difficulty(MockDifficultyManager.Difficulty.POWER_FANTASY)

	assert_eq(manager.current_difficulty, MockDifficultyManager.Difficulty.POWER_FANTASY,
		"Difficulty should be POWER_FANTASY after setting")
	assert_true(manager.is_power_fantasy_mode(), "is_power_fantasy_mode() should return true")
	assert_false(manager.is_normal_mode(), "is_normal_mode() should return false")
	assert_false(manager.is_easy_mode(), "is_easy_mode() should return false")
	assert_false(manager.is_hard_mode(), "is_hard_mode() should return false")


func test_get_difficulty_name_power_fantasy() -> void:
	manager.set_difficulty(MockDifficultyManager.Difficulty.POWER_FANTASY)

	assert_eq(manager.get_difficulty_name(), "Power Fantasy",
		"Power Fantasy difficulty name should be 'Power Fantasy'")


func test_max_ammo_power_fantasy_mode() -> void:
	manager.set_difficulty(MockDifficultyManager.Difficulty.POWER_FANTASY)

	assert_eq(manager.get_max_ammo(), 270,
		"Power Fantasy mode should have 270 max ammo (3x normal)")


func test_distraction_attack_disabled_in_power_fantasy_mode() -> void:
	manager.set_difficulty(MockDifficultyManager.Difficulty.POWER_FANTASY)

	assert_false(manager.is_distraction_attack_enabled(),
		"Distraction attack should be disabled in Power Fantasy mode")


func test_detection_delay_power_fantasy_mode() -> void:
	manager.set_difficulty(MockDifficultyManager.Difficulty.POWER_FANTASY)

	assert_eq(manager.get_detection_delay(), 0.8,
		"Power Fantasy mode should have 0.8s detection delay (slowest reaction)")


# ============================================================================
# Night Mode Detection Delay Tests (Issue #825)
# ============================================================================


func test_detection_delay_night_mode_easy() -> void:
	manager.set_difficulty(MockDifficultyManager.Difficulty.EASY)
	manager.set_night_mode_active(true)

	var expected := 0.5 * MockDifficultyManager.NIGHT_MODE_REACTION_DELAY_MULTIPLIER
	assert_almost_eq(manager.get_detection_delay(), expected, 0.001,
		"Night mode easy should have 30%% longer detection delay")


func test_detection_delay_night_mode_normal() -> void:
	# Default is NORMAL
	manager.set_night_mode_active(true)

	var expected := 0.6 * MockDifficultyManager.NIGHT_MODE_REACTION_DELAY_MULTIPLIER
	assert_almost_eq(manager.get_detection_delay(), expected, 0.001,
		"Night mode normal should have 30%% longer detection delay")


func test_detection_delay_night_mode_hard() -> void:
	manager.set_difficulty(MockDifficultyManager.Difficulty.HARD)
	manager.set_night_mode_active(true)

	var expected := 0.2 * MockDifficultyManager.NIGHT_MODE_REACTION_DELAY_MULTIPLIER
	assert_almost_eq(manager.get_detection_delay(), expected, 0.001,
		"Night mode hard should have 30%% longer detection delay")


func test_detection_delay_night_mode_power_fantasy() -> void:
	manager.set_difficulty(MockDifficultyManager.Difficulty.POWER_FANTASY)
	manager.set_night_mode_active(true)

	var expected := 0.8 * MockDifficultyManager.NIGHT_MODE_REACTION_DELAY_MULTIPLIER
	assert_almost_eq(manager.get_detection_delay(), expected, 0.001,
		"Night mode power fantasy should have 30%% longer detection delay")


func test_detection_delay_night_mode_disabled_returns_base_delay() -> void:
	# Default is NORMAL, night mode off
	assert_eq(manager.get_detection_delay(), 0.6,
		"Without night mode, normal detection delay should be unchanged")


func test_detection_delay_night_mode_multiplier_is_1_point_3() -> void:
	assert_almost_eq(MockDifficultyManager.NIGHT_MODE_REACTION_DELAY_MULTIPLIER, 1.3, 0.001,
		"Night mode multiplier should be 1.3 (30%% increase)")


func test_night_mode_normal_delay_is_30_percent_longer() -> void:
	manager.set_night_mode_active(false)
	var base_delay := manager.get_detection_delay()

	manager.set_night_mode_active(true)
	var night_delay := manager.get_detection_delay()

	assert_almost_eq(night_delay / base_delay, 1.3, 0.001,
		"Night mode delay should be exactly 30%% longer than base delay")


# ============================================================================
# Black Metal Mode Tests (Issue #958)
# ============================================================================


func test_set_difficulty_to_black_metal() -> void:
	manager.set_difficulty(MockDifficultyManager.Difficulty.BLACK_METAL)

	assert_eq(manager.current_difficulty, MockDifficultyManager.Difficulty.BLACK_METAL,
		"Difficulty should be BLACK_METAL after setting")
	assert_true(manager.is_black_metal_mode(), "is_black_metal_mode() should return true")
	assert_false(manager.is_normal_mode(), "is_normal_mode() should return false")
	assert_false(manager.is_easy_mode(), "is_easy_mode() should return false")
	assert_false(manager.is_hard_mode(), "is_hard_mode() should return false")
	assert_false(manager.is_power_fantasy_mode(), "is_power_fantasy_mode() should return false")


func test_get_difficulty_name_black_metal() -> void:
	manager.set_difficulty(MockDifficultyManager.Difficulty.BLACK_METAL)

	assert_eq(manager.get_difficulty_name(), "Black Metal",
		"Black Metal difficulty name should be 'Black Metal'")


func test_max_ammo_black_metal_mode() -> void:
	manager.set_difficulty(MockDifficultyManager.Difficulty.BLACK_METAL)

	assert_eq(manager.get_max_ammo(), 90,
		"Black Metal mode should have 90 max ammo (same as normal)")


func test_distraction_attack_disabled_in_black_metal_mode() -> void:
	manager.set_difficulty(MockDifficultyManager.Difficulty.BLACK_METAL)

	assert_false(manager.is_distraction_attack_enabled(),
		"Distraction attack should be disabled in Black Metal mode")


func test_detection_delay_black_metal_mode() -> void:
	manager.set_difficulty(MockDifficultyManager.Difficulty.BLACK_METAL)

	assert_eq(manager.get_detection_delay(), 0.3,
		"Black Metal mode should have 0.3s detection delay (faster than normal)")


func test_hp_multiplier_normal_mode_is_one() -> void:
	# Default is NORMAL
	assert_almost_eq(manager.get_hp_multiplier(), 1.0, 0.001,
		"Normal mode HP multiplier should be 1.0 (no change)")


func test_hp_multiplier_black_metal_is_0_75() -> void:
	manager.set_difficulty(MockDifficultyManager.Difficulty.BLACK_METAL)

	assert_almost_eq(manager.get_hp_multiplier(), 0.75, 0.001,
		"Black Metal mode HP multiplier should be 0.75 (25%% less HP)")


func test_hp_multiplier_power_fantasy_mode_is_one() -> void:
	manager.set_difficulty(MockDifficultyManager.Difficulty.POWER_FANTASY)

	assert_almost_eq(manager.get_hp_multiplier(), 1.0, 0.001,
		"Power Fantasy mode HP multiplier should be 1.0 (health handled separately)")


func test_player_speed_multiplier_normal_mode_is_one() -> void:
	# Default is NORMAL
	assert_almost_eq(manager.get_player_speed_multiplier(), 1.0, 0.001,
		"Normal mode speed multiplier should be 1.0 (no change)")


func test_player_speed_multiplier_black_metal_is_1_25() -> void:
	manager.set_difficulty(MockDifficultyManager.Difficulty.BLACK_METAL)

	assert_almost_eq(manager.get_player_speed_multiplier(), 1.25, 0.001,
		"Black Metal mode speed multiplier should be 1.25 (25%% faster)")


func test_player_speed_multiplier_gunslinger_is_1_5() -> void:
	manager.set_difficulty(MockDifficultyManager.Difficulty.GUNSLINGER)

	assert_almost_eq(manager.get_player_speed_multiplier(), 1.5, 0.001,
		"Gunslinger mode speed multiplier should be 1.5 (50%% faster — Issue #1732)")


func test_black_metal_hp_reduction_calculation() -> void:
	manager.set_difficulty(MockDifficultyManager.Difficulty.BLACK_METAL)
	var hp_mult := manager.get_hp_multiplier()

	# Verify 25% less HP: base 4 HP -> floor(4 * 0.75) = 3
	var base_hp := 4
	var expected_hp := maxi(1, int(base_hp * hp_mult))
	assert_eq(expected_hp, 3,
		"With 4 base HP and 0.75 multiplier, expected 3 HP in Black Metal mode")


func test_black_metal_hp_never_below_one() -> void:
	manager.set_difficulty(MockDifficultyManager.Difficulty.BLACK_METAL)
	var hp_mult := manager.get_hp_multiplier()

	# Even if base HP is 1, result should be at least 1
	var base_hp := 1
	var result_hp := maxi(1, int(base_hp * hp_mult))
	assert_ge(result_hp, 1, "HP should never go below 1 in Black Metal mode")


func test_black_metal_is_not_active_in_normal_mode() -> void:
	# Default is NORMAL
	assert_false(manager.is_black_metal_mode(),
		"is_black_metal_mode() should return false in Normal mode")


func test_black_metal_mode_detection_delay_with_night_mode() -> void:
	manager.set_difficulty(MockDifficultyManager.Difficulty.BLACK_METAL)
	manager.set_night_mode_active(true)

	var expected := 0.3 * MockDifficultyManager.NIGHT_MODE_REACTION_DELAY_MULTIPLIER
	assert_almost_eq(manager.get_detection_delay(), expected, 0.001,
		"Night mode black metal should have 30%% longer detection delay")


# ============================================================================
# Gunslinger Mode Tests (Issue #1727)
# ============================================================================


func test_set_difficulty_to_gunslinger() -> void:
	manager.set_difficulty(MockDifficultyManager.Difficulty.GUNSLINGER)

	assert_eq(manager.current_difficulty, MockDifficultyManager.Difficulty.GUNSLINGER,
		"Difficulty should be GUNSLINGER after setting")
	assert_true(manager.is_gunslinger_mode(), "is_gunslinger_mode() should return true")
	assert_false(manager.is_normal_mode(), "is_normal_mode() should return false")
	assert_false(manager.is_hard_mode(), "is_hard_mode() should return false")
	assert_false(manager.is_power_fantasy_mode(), "is_power_fantasy_mode() should return false")
	assert_false(manager.is_black_metal_mode(), "is_black_metal_mode() should return false")


func test_get_difficulty_name_gunslinger() -> void:
	manager.set_difficulty(MockDifficultyManager.Difficulty.GUNSLINGER)

	assert_eq(manager.get_difficulty_name(), "Gunslinger",
		"Gunslinger difficulty name should be 'Gunslinger'")


func test_max_ammo_gunslinger_mode_is_4x_normal() -> void:
	manager.set_difficulty(MockDifficultyManager.Difficulty.GUNSLINGER)

	assert_eq(manager.get_max_ammo(), 360,
		"Gunslinger mode should have 360 max ammo (4x normal 90)")


func test_hp_multiplier_gunslinger_is_0_5() -> void:
	manager.set_difficulty(MockDifficultyManager.Difficulty.GUNSLINGER)

	assert_almost_eq(manager.get_hp_multiplier(), 0.5, 0.001,
		"Gunslinger mode HP multiplier should be 0.5 (2x less HP)")


func test_gunslinger_hp_reduction_calculation() -> void:
	manager.set_difficulty(MockDifficultyManager.Difficulty.GUNSLINGER)
	var hp_mult := manager.get_hp_multiplier()

	# Verify 2x less HP: base 4 HP -> floor(4 * 0.5) = 2
	var base_hp := 4
	var expected_hp := maxi(1, int(base_hp * hp_mult))
	assert_eq(expected_hp, 2,
		"With 4 base HP and 0.5 multiplier, expected 2 HP in Gunslinger mode")


func test_gunslinger_hp_never_below_one() -> void:
	manager.set_difficulty(MockDifficultyManager.Difficulty.GUNSLINGER)
	var hp_mult := manager.get_hp_multiplier()

	var base_hp := 1
	var result_hp := maxi(1, int(base_hp * hp_mult))
	assert_ge(result_hp, 1, "HP should never go below 1 in Gunslinger mode")


func test_gunslinger_disables_laser_sight() -> void:
	manager.set_difficulty(MockDifficultyManager.Difficulty.GUNSLINGER)

	assert_true(manager.should_disable_laser_sight(),
		"Gunslinger mode should disable laser sights on all weapons")


func test_normal_mode_does_not_disable_laser_sight() -> void:
	# Default is NORMAL
	assert_false(manager.should_disable_laser_sight(),
		"Normal mode should not disable laser sights")


func test_power_fantasy_does_not_disable_laser_sight() -> void:
	manager.set_difficulty(MockDifficultyManager.Difficulty.POWER_FANTASY)

	assert_false(manager.should_disable_laser_sight(),
		"Power Fantasy mode should not disable laser sights (has blue lasers)")


func test_gunslinger_enables_kill_last_chance() -> void:
	manager.set_difficulty(MockDifficultyManager.Difficulty.GUNSLINGER)

	assert_true(manager.is_kill_last_chance_enabled(),
		"Gunslinger mode should enable kill-triggered last chance effect")


func test_power_fantasy_enables_kill_last_chance() -> void:
	manager.set_difficulty(MockDifficultyManager.Difficulty.POWER_FANTASY)

	assert_true(manager.is_kill_last_chance_enabled(),
		"Power Fantasy mode should enable kill-triggered last chance effect")


func test_normal_mode_kill_last_chance_disabled() -> void:
	# Default is NORMAL
	assert_false(manager.is_kill_last_chance_enabled(),
		"Normal mode should not have kill-triggered last chance effect")


func test_gunslinger_disables_special_last_chance() -> void:
	manager.set_difficulty(MockDifficultyManager.Difficulty.GUNSLINGER)

	assert_true(manager.is_special_last_chance_disabled(),
		"Gunslinger mode should disable the special time-stop last chance effect")


func test_normal_mode_special_last_chance_not_disabled() -> void:
	# Default is NORMAL
	assert_false(manager.is_special_last_chance_disabled(),
		"Normal mode should not have special last chance disabled")


func test_hard_mode_special_last_chance_not_disabled() -> void:
	manager.set_difficulty(MockDifficultyManager.Difficulty.HARD)

	assert_false(manager.is_special_last_chance_disabled(),
		"Hard mode should not have special last chance disabled (it uses the effect normally)")


func test_gunslinger_enemy_glow_enabled() -> void:
	manager.set_difficulty(MockDifficultyManager.Difficulty.GUNSLINGER)

	assert_true(manager.should_apply_gunslinger_enemy_glow(),
		"Gunslinger mode should apply enemy glow effect")


func test_normal_mode_enemy_glow_disabled() -> void:
	# Default is NORMAL
	assert_false(manager.should_apply_gunslinger_enemy_glow(),
		"Normal mode should not apply Gunslinger enemy glow")


func test_distraction_attack_disabled_in_gunslinger_mode() -> void:
	manager.set_difficulty(MockDifficultyManager.Difficulty.GUNSLINGER)

	assert_false(manager.is_distraction_attack_enabled(),
		"Distraction attack should be disabled in Gunslinger mode")


func test_detection_delay_gunslinger_mode() -> void:
	manager.set_difficulty(MockDifficultyManager.Difficulty.GUNSLINGER)

	assert_almost_eq(manager.get_detection_delay(), 0.4, 0.001,
		"Gunslinger mode should have 0.4s detection delay (slightly faster than normal)")


func test_gunslinger_is_not_active_in_normal_mode() -> void:
	# Default is NORMAL
	assert_false(manager.is_gunslinger_mode(),
		"is_gunslinger_mode() should return false in Normal mode")


func test_get_difficulty_name_for_gunslinger() -> void:
	assert_eq(manager.get_difficulty_name_for(MockDifficultyManager.Difficulty.GUNSLINGER),
		"Gunslinger", "get_difficulty_name_for(GUNSLINGER) should return 'Gunslinger'")


# ============================================================================
# First Launch Tests (Issue #1734)
# ============================================================================


func test_is_first_launch_true_when_no_settings_file() -> void:
	# Settings file does not exist by default in the mock
	assert_true(manager.is_first_launch(),
		"is_first_launch() should return true when no settings file exists")


func test_is_first_launch_false_after_settings_saved() -> void:
	manager.simulate_settings_saved()

	assert_false(manager.is_first_launch(),
		"is_first_launch() should return false once a settings file exists")


func test_first_launch_is_true_before_any_difficulty_set() -> void:
	# A fresh manager with no persisted file is always a first launch
	assert_true(manager.is_first_launch(),
		"New manager with no saved file should report first launch")


func test_first_launch_is_false_after_saving_any_difficulty() -> void:
	manager.set_difficulty(MockDifficultyManager.Difficulty.EASY)
	manager.simulate_settings_saved()

	assert_false(manager.is_first_launch(),
		"After saving a difficulty choice is_first_launch() should be false")


func test_reset_to_default_restores_first_launch_state() -> void:
	## After clear_all_saves(), reset_to_default() must delete the settings file so
	## is_first_launch() returns true again on the next startup (Issue #1734).
	manager.set_difficulty(MockDifficultyManager.Difficulty.POWER_FANTASY)
	manager.simulate_settings_saved()
	assert_false(manager.is_first_launch(), "Precondition: not a first launch")

	manager.reset_to_default()

	assert_true(manager.is_first_launch(),
		"is_first_launch() must return true after reset_to_default() (Issue #1734)")
	assert_eq(manager.current_difficulty, MockDifficultyManager.Difficulty.NORMAL,
		"Difficulty must be reset to NORMAL after reset_to_default()")
