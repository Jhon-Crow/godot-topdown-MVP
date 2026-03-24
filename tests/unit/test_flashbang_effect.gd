extends GutTest
## Unit tests for flashbang_effect.gd flashbang visual effect.
##
## Tests flash duration, light start energy, effect radius default,
## and fade behavior.


# ============================================================================
# Mock FlashbangEffect for Logic Tests
# ============================================================================


class MockFlashbangEffect:
	## Duration of the flashbang effect in seconds.
	const FLASH_DURATION: float = 0.5

	## Starting energy of the point light.
	const LIGHT_START_ENERGY: float = 8.0

	## Effect radius.
	var effect_radius: float = 400.0

	## Time tracker.
	var _elapsed_time: float = 0.0

	## Whether the effect is active.
	var _is_active: bool = false

	## Current light energy.
	var _light_energy: float = 0.0

	## Whether freed.
	var queue_freed: bool = false

	## Simulate starting the effect.
	func start_effect() -> void:
		_is_active = true
		_elapsed_time = 0.0
		_light_energy = LIGHT_START_ENERGY

	## Simulate process update.
	func process(delta: float) -> void:
		if not _is_active:
			return

		_elapsed_time += delta
		var progress := clampf(_elapsed_time / FLASH_DURATION, 0.0, 1.0)

		var fade := 1.0 - progress
		fade = fade * fade
		_light_energy = LIGHT_START_ENERGY * fade

		if progress >= 1.0:
			_is_active = false
			queue_free()

	## Simulate queue_free.
	func queue_free() -> void:
		queue_freed = true


var flashbang: MockFlashbangEffect


func before_each() -> void:
	flashbang = MockFlashbangEffect.new()


func after_each() -> void:
	flashbang = null


# ============================================================================
# Constant Tests
# ============================================================================


func test_flash_duration() -> void:
	assert_eq(MockFlashbangEffect.FLASH_DURATION, 0.5,
		"FLASH_DURATION should be 0.5 seconds")


func test_light_start_energy() -> void:
	assert_eq(MockFlashbangEffect.LIGHT_START_ENERGY, 8.0,
		"LIGHT_START_ENERGY should be 8.0")


func test_effect_radius_default() -> void:
	assert_eq(flashbang.effect_radius, 400.0,
		"Effect radius should default to 400.0 pixels")


# ============================================================================
# Effect Lifecycle Tests
# ============================================================================


func test_not_active_initially() -> void:
	assert_false(flashbang._is_active,
		"Effect should not be active initially")


func test_active_after_start() -> void:
	flashbang.start_effect()

	assert_true(flashbang._is_active,
		"Effect should be active after start")


func test_initial_energy_on_start() -> void:
	flashbang.start_effect()

	assert_eq(flashbang._light_energy, 8.0,
		"Light energy should be LIGHT_START_ENERGY on start")


func test_energy_decreases_over_time() -> void:
	flashbang.start_effect()
	flashbang.process(0.25)

	assert_lt(flashbang._light_energy, 8.0,
		"Light energy should decrease over time")
	assert_gt(flashbang._light_energy, 0.0,
		"Light energy should still be positive mid-fade")


func test_effect_completes_after_duration() -> void:
	flashbang.start_effect()
	flashbang.process(0.5)

	assert_false(flashbang._is_active,
		"Effect should be inactive after FLASH_DURATION")


func test_queue_freed_after_completion() -> void:
	flashbang.start_effect()
	flashbang.process(0.5)

	assert_true(flashbang.queue_freed,
		"Node should be freed after completion")


func test_energy_zero_after_duration() -> void:
	flashbang.start_effect()
	flashbang.process(0.5)

	assert_almost_eq(flashbang._light_energy, 0.0, 0.01,
		"Light energy should be ~0 after full duration")


func test_no_update_when_inactive() -> void:
	flashbang._light_energy = 5.0
	flashbang.process(0.1)

	assert_eq(flashbang._light_energy, 5.0,
		"Process should not change energy when inactive")
