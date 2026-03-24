extends GutTest
## Unit tests for explosion_flash.gd explosion visual effect.
##
## Tests flash duration, light energy constants for different
## explosion types, and the ExplosionType enum.


# ============================================================================
# Mock ExplosionFlash for Logic Tests
# ============================================================================


class MockExplosionFlash:
	## Explosion type enum.
	enum ExplosionType {
		FLASHBANG,
		FRAG
	}

	## Duration of the explosion flash effect.
	const FLASH_DURATION: float = 0.4

	## Starting energy for flashbang light.
	const FLASHBANG_LIGHT_ENERGY: float = 8.0

	## Starting energy for frag light.
	const FRAG_LIGHT_ENERGY: float = 6.0

	## The type of explosion.
	var explosion_type: int = ExplosionType.FLASHBANG

	## Effect radius.
	var effect_radius: float = 400.0

	## Time tracker.
	var _elapsed_time: float = 0.0

	## Whether the effect is active.
	var _is_active: bool = false

	## Current light energy.
	var _light_energy: float = 0.0

	## Whether cleanup was scheduled.
	var _cleanup_scheduled: bool = false

	## Simulate starting the effect.
	func start_effect() -> void:
		_is_active = true
		_elapsed_time = 0.0

		if explosion_type == ExplosionType.FLASHBANG:
			_light_energy = FLASHBANG_LIGHT_ENERGY
		else:
			_light_energy = FRAG_LIGHT_ENERGY

	## Simulate process update.
	func process(delta: float) -> void:
		if not _is_active:
			return

		_elapsed_time += delta
		var progress := clampf(_elapsed_time / FLASH_DURATION, 0.0, 1.0)

		var fade := 1.0 - progress
		fade = fade * fade  # Ease-out curve

		var start_energy: float
		if explosion_type == ExplosionType.FLASHBANG:
			start_energy = FLASHBANG_LIGHT_ENERGY
		else:
			start_energy = FRAG_LIGHT_ENERGY
		_light_energy = start_energy * fade

		if progress >= 1.0:
			_is_active = false
			_cleanup_scheduled = true


var flash: MockExplosionFlash


func before_each() -> void:
	flash = MockExplosionFlash.new()


func after_each() -> void:
	flash = null


# ============================================================================
# Constant Tests
# ============================================================================


func test_flash_duration() -> void:
	assert_eq(MockExplosionFlash.FLASH_DURATION, 0.4,
		"FLASH_DURATION should be 0.4 seconds")


func test_flashbang_light_energy() -> void:
	assert_eq(MockExplosionFlash.FLASHBANG_LIGHT_ENERGY, 8.0,
		"FLASHBANG_LIGHT_ENERGY should be 8.0")


func test_frag_light_energy() -> void:
	assert_eq(MockExplosionFlash.FRAG_LIGHT_ENERGY, 6.0,
		"FRAG_LIGHT_ENERGY should be 6.0")


# ============================================================================
# ExplosionType Enum Tests
# ============================================================================


func test_explosion_type_flashbang_value() -> void:
	assert_eq(MockExplosionFlash.ExplosionType.FLASHBANG, 0,
		"FLASHBANG enum value should be 0")


func test_explosion_type_frag_value() -> void:
	assert_eq(MockExplosionFlash.ExplosionType.FRAG, 1,
		"FRAG enum value should be 1")


func test_default_explosion_type_is_flashbang() -> void:
	assert_eq(flash.explosion_type, MockExplosionFlash.ExplosionType.FLASHBANG,
		"Default explosion type should be FLASHBANG")


# ============================================================================
# Flashbang Effect Tests
# ============================================================================


func test_flashbang_initial_energy() -> void:
	flash.explosion_type = MockExplosionFlash.ExplosionType.FLASHBANG
	flash.start_effect()

	assert_eq(flash._light_energy, 8.0,
		"Flashbang should start with FLASHBANG_LIGHT_ENERGY")


func test_flashbang_fades_over_time() -> void:
	flash.explosion_type = MockExplosionFlash.ExplosionType.FLASHBANG
	flash.start_effect()
	flash.process(0.2)  # 50% through

	assert_lt(flash._light_energy, 8.0,
		"Flashbang energy should decrease over time")
	assert_gt(flash._light_energy, 0.0,
		"Flashbang energy should still be positive mid-fade")


func test_flashbang_completes() -> void:
	flash.explosion_type = MockExplosionFlash.ExplosionType.FLASHBANG
	flash.start_effect()
	flash.process(0.4)

	assert_false(flash._is_active,
		"Flash should complete after FLASH_DURATION")
	assert_true(flash._cleanup_scheduled,
		"Cleanup should be scheduled after completion")


# ============================================================================
# Frag Effect Tests
# ============================================================================


func test_frag_initial_energy() -> void:
	flash.explosion_type = MockExplosionFlash.ExplosionType.FRAG
	flash.start_effect()

	assert_eq(flash._light_energy, 6.0,
		"Frag should start with FRAG_LIGHT_ENERGY")


func test_frag_lower_energy_than_flashbang() -> void:
	assert_lt(MockExplosionFlash.FRAG_LIGHT_ENERGY, MockExplosionFlash.FLASHBANG_LIGHT_ENERGY,
		"Frag light energy should be lower than flashbang")


func test_frag_completes() -> void:
	flash.explosion_type = MockExplosionFlash.ExplosionType.FRAG
	flash.start_effect()
	flash.process(0.5)

	assert_false(flash._is_active,
		"Frag flash should complete after FLASH_DURATION")


# ============================================================================
# Fade Behavior Tests
# ============================================================================


func test_energy_at_zero_after_duration() -> void:
	flash.start_effect()
	flash.process(0.4)

	assert_almost_eq(flash._light_energy, 0.0, 0.01,
		"Light energy should be ~0 after full duration")


func test_energy_clamped_past_duration() -> void:
	flash.start_effect()
	flash.process(1.0)

	assert_almost_eq(flash._light_energy, 0.0, 0.01,
		"Light energy should not go negative past duration")
