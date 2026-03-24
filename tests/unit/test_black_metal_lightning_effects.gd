extends GutTest
## Unit tests for BlackMetalLightningEffectsManager autoload.
##
## Tests FlashPattern enum values, flash timing constants,
## and pattern probability thresholds.


# ============================================================================
# Mock BlackMetalLightningEffectsManager
# ============================================================================


class MockLightningEffectsManager:
	## Flash pattern types for visual diversity.
	enum FlashPattern {
		SINGLE,
		DOUBLE,
		TRIPLE
	}

	## Timing constants.
	const MIN_FLASH_DURATION: float = 0.12
	const MAX_FLASH_DURATION: float = 0.22
	const MULTI_FLASH_GAP: float = 0.05

	## Pattern probability thresholds.
	const DOUBLE_FLASH_CHANCE: float = 0.35
	const TRIPLE_FLASH_CHANCE: float = 0.15

	var _is_active: bool = false
	var _is_flashing: bool = false
	var _flashes_remaining: int = 0

	func set_active(active: bool) -> void:
		_is_active = active

	func is_active() -> bool:
		return _is_active

	## Chooses a flash pattern based on a given roll value (deterministic for testing).
	func choose_flash_pattern_for_roll(roll: float) -> FlashPattern:
		if roll < TRIPLE_FLASH_CHANCE:
			return FlashPattern.TRIPLE
		elif roll < TRIPLE_FLASH_CHANCE + DOUBLE_FLASH_CHANCE:
			return FlashPattern.DOUBLE
		else:
			return FlashPattern.SINGLE

	## Returns the number of flashes for a given pattern.
	func get_flash_count(pattern: FlashPattern) -> int:
		match pattern:
			FlashPattern.SINGLE:
				return 1
			FlashPattern.DOUBLE:
				return 2
			FlashPattern.TRIPLE:
				return 3
		return 0

	## Triggers lightning if active.
	func trigger_lightning() -> bool:
		if not _is_active:
			return false
		if _is_flashing:
			return false
		_is_flashing = true
		return true

	## Ends the flash sequence.
	func end_flash() -> void:
		_is_flashing = false


var manager: MockLightningEffectsManager


func before_each() -> void:
	manager = MockLightningEffectsManager.new()


func after_each() -> void:
	manager = null


# ============================================================================
# FlashPattern Enum Value Tests
# ============================================================================


func test_flash_pattern_single_is_0() -> void:
	assert_eq(MockLightningEffectsManager.FlashPattern.SINGLE, 0,
		"FlashPattern.SINGLE should be 0")


func test_flash_pattern_double_is_1() -> void:
	assert_eq(MockLightningEffectsManager.FlashPattern.DOUBLE, 1,
		"FlashPattern.DOUBLE should be 1")


func test_flash_pattern_triple_is_2() -> void:
	assert_eq(MockLightningEffectsManager.FlashPattern.TRIPLE, 2,
		"FlashPattern.TRIPLE should be 2")


# ============================================================================
# Flash Timing Constant Tests
# ============================================================================


func test_min_flash_duration() -> void:
	assert_almost_eq(MockLightningEffectsManager.MIN_FLASH_DURATION, 0.12, 0.001,
		"MIN_FLASH_DURATION should be 0.12 seconds")


func test_max_flash_duration() -> void:
	assert_almost_eq(MockLightningEffectsManager.MAX_FLASH_DURATION, 0.22, 0.001,
		"MAX_FLASH_DURATION should be 0.22 seconds")


func test_multi_flash_gap() -> void:
	assert_almost_eq(MockLightningEffectsManager.MULTI_FLASH_GAP, 0.05, 0.001,
		"MULTI_FLASH_GAP should be 0.05 seconds")


func test_min_less_than_max_duration() -> void:
	assert_lt(MockLightningEffectsManager.MIN_FLASH_DURATION,
		MockLightningEffectsManager.MAX_FLASH_DURATION,
		"MIN_FLASH_DURATION should be less than MAX_FLASH_DURATION")


# ============================================================================
# Pattern Probability Threshold Tests
# ============================================================================


func test_double_flash_chance() -> void:
	assert_almost_eq(MockLightningEffectsManager.DOUBLE_FLASH_CHANCE, 0.35, 0.001,
		"DOUBLE_FLASH_CHANCE should be 0.35")


func test_triple_flash_chance() -> void:
	assert_almost_eq(MockLightningEffectsManager.TRIPLE_FLASH_CHANCE, 0.15, 0.001,
		"TRIPLE_FLASH_CHANCE should be 0.15")


func test_combined_chances_less_than_one() -> void:
	var combined := MockLightningEffectsManager.TRIPLE_FLASH_CHANCE + MockLightningEffectsManager.DOUBLE_FLASH_CHANCE
	assert_lt(combined, 1.0,
		"Combined TRIPLE + DOUBLE chance (%.2f) should be less than 1.0" % combined)


func test_pattern_triple_for_low_roll() -> void:
	var pattern := manager.choose_flash_pattern_for_roll(0.10)

	assert_eq(pattern, MockLightningEffectsManager.FlashPattern.TRIPLE,
		"Roll below TRIPLE_FLASH_CHANCE should give TRIPLE")


func test_pattern_double_for_mid_roll() -> void:
	var pattern := manager.choose_flash_pattern_for_roll(0.30)

	assert_eq(pattern, MockLightningEffectsManager.FlashPattern.DOUBLE,
		"Roll between TRIPLE and TRIPLE+DOUBLE thresholds should give DOUBLE")


func test_pattern_single_for_high_roll() -> void:
	var pattern := manager.choose_flash_pattern_for_roll(0.60)

	assert_eq(pattern, MockLightningEffectsManager.FlashPattern.SINGLE,
		"Roll above TRIPLE+DOUBLE threshold should give SINGLE")


func test_pattern_at_triple_boundary() -> void:
	var pattern := manager.choose_flash_pattern_for_roll(0.149)

	assert_eq(pattern, MockLightningEffectsManager.FlashPattern.TRIPLE,
		"Roll just under TRIPLE_FLASH_CHANCE should give TRIPLE")


func test_pattern_at_double_boundary() -> void:
	var pattern := manager.choose_flash_pattern_for_roll(0.15)

	assert_eq(pattern, MockLightningEffectsManager.FlashPattern.DOUBLE,
		"Roll exactly at TRIPLE_FLASH_CHANCE should give DOUBLE")


func test_pattern_at_single_boundary() -> void:
	var pattern := manager.choose_flash_pattern_for_roll(0.50)

	assert_eq(pattern, MockLightningEffectsManager.FlashPattern.SINGLE,
		"Roll at TRIPLE+DOUBLE threshold should give SINGLE")


# ============================================================================
# Flash Count Tests
# ============================================================================


func test_single_pattern_gives_1_flash() -> void:
	assert_eq(manager.get_flash_count(MockLightningEffectsManager.FlashPattern.SINGLE), 1,
		"SINGLE pattern should give 1 flash")


func test_double_pattern_gives_2_flashes() -> void:
	assert_eq(manager.get_flash_count(MockLightningEffectsManager.FlashPattern.DOUBLE), 2,
		"DOUBLE pattern should give 2 flashes")


func test_triple_pattern_gives_3_flashes() -> void:
	assert_eq(manager.get_flash_count(MockLightningEffectsManager.FlashPattern.TRIPLE), 3,
		"TRIPLE pattern should give 3 flashes")


# ============================================================================
# Trigger Logic Tests
# ============================================================================


func test_trigger_fails_when_inactive() -> void:
	assert_false(manager.trigger_lightning(),
		"trigger_lightning() should fail when inactive")


func test_trigger_succeeds_when_active() -> void:
	manager.set_active(true)

	assert_true(manager.trigger_lightning(),
		"trigger_lightning() should succeed when active")


func test_trigger_fails_when_already_flashing() -> void:
	manager.set_active(true)
	manager.trigger_lightning()

	assert_false(manager.trigger_lightning(),
		"trigger_lightning() should fail when already flashing")


func test_trigger_succeeds_after_flash_ends() -> void:
	manager.set_active(true)
	manager.trigger_lightning()
	manager.end_flash()

	assert_true(manager.trigger_lightning(),
		"trigger_lightning() should succeed after flash ends")
