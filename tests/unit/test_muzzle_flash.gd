extends GutTest
## Unit tests for muzzle_flash.gd muzzle flash visual effect.
##
## Tests flash duration, light start energy, and fade behavior.


# ============================================================================
# Mock MuzzleFlash for Logic Tests
# ============================================================================


class MockMuzzleFlash:
	## Duration of the muzzle flash effect in seconds.
	const FLASH_DURATION: float = 0.3

	## Starting energy of the point light.
	const LIGHT_START_ENERGY: float = 4.5

	## Initial alpha of the floor-visible flash sprite.
	const SPRITE_START_ALPHA: float = 0.8

	## Final sprite scale multiplier.
	const SPRITE_END_SCALE_MULTIPLIER: float = 0.55

	## Time tracker.
	var _elapsed_time: float = 0.0

	## Whether the effect is active.
	var _is_active: bool = false

	## Current light energy.
	var _light_energy: float = 0.0

	## Whether cleanup was scheduled.
	var _cleanup_scheduled: bool = false

	## Current alpha of the floor-visible flash sprite.
	var _sprite_alpha: float = 0.0

	## Current scale multiplier of the floor-visible flash sprite.
	var _sprite_scale: float = 1.0

	## Simulate starting the effect.
	func start_effect() -> void:
		_is_active = true
		_elapsed_time = 0.0
		_light_energy = LIGHT_START_ENERGY
		_sprite_alpha = SPRITE_START_ALPHA
		_sprite_scale = 1.0

	## Simulate process update.
	func process(delta: float) -> void:
		if not _is_active:
			return

		_elapsed_time += delta
		var progress := clampf(_elapsed_time / FLASH_DURATION, 0.0, 1.0)

		var fade := 1.0 - progress
		fade = fade * fade
		_light_energy = LIGHT_START_ENERGY * fade
		_sprite_alpha = SPRITE_START_ALPHA * fade
		_sprite_scale = lerpf(1.0, SPRITE_END_SCALE_MULTIPLIER, progress)

		if progress >= 1.0:
			_is_active = false
			_cleanup_scheduled = true


var muzzle: MockMuzzleFlash


func before_each() -> void:
	muzzle = MockMuzzleFlash.new()


func after_each() -> void:
	muzzle = null


# ============================================================================
# Constant Tests
# ============================================================================


func test_flash_duration() -> void:
	assert_eq(MockMuzzleFlash.FLASH_DURATION, 0.3,
		"FLASH_DURATION should be 0.3 seconds")


func test_light_start_energy() -> void:
	assert_eq(MockMuzzleFlash.LIGHT_START_ENERGY, 4.5,
		"LIGHT_START_ENERGY should be 4.5")


func test_sprite_start_alpha() -> void:
	assert_eq(MockMuzzleFlash.SPRITE_START_ALPHA, 0.8,
		"SPRITE_START_ALPHA should be 0.8")


# ============================================================================
# Effect Lifecycle Tests
# ============================================================================


func test_not_active_initially() -> void:
	assert_false(muzzle._is_active,
		"Effect should not be active initially")


func test_active_after_start() -> void:
	muzzle.start_effect()

	assert_true(muzzle._is_active,
		"Effect should be active after start")


func test_initial_energy_on_start() -> void:
	muzzle.start_effect()

	assert_eq(muzzle._light_energy, 4.5,
		"Light energy should be LIGHT_START_ENERGY on start")


func test_sprite_alpha_initialized_on_start() -> void:
	muzzle.start_effect()

	assert_eq(muzzle._sprite_alpha, MockMuzzleFlash.SPRITE_START_ALPHA,
		"Flash sprite should start visible so the flash reads on dark floors")


func test_energy_decreases_over_time() -> void:
	muzzle.start_effect()
	muzzle.process(0.15)

	assert_lt(muzzle._light_energy, 4.5,
		"Light energy should decrease over time")
	assert_gt(muzzle._light_energy, 0.0,
		"Light energy should still be positive mid-fade")


func test_effect_completes_after_duration() -> void:
	muzzle.start_effect()
	muzzle.process(0.3)

	assert_false(muzzle._is_active,
		"Effect should be inactive after FLASH_DURATION")


func test_cleanup_scheduled_after_completion() -> void:
	muzzle.start_effect()
	muzzle.process(0.3)

	assert_true(muzzle._cleanup_scheduled,
		"Cleanup should be scheduled after completion")


func test_energy_zero_after_duration() -> void:
	muzzle.start_effect()
	muzzle.process(0.3)

	assert_almost_eq(muzzle._light_energy, 0.0, 0.01,
		"Light energy should be ~0 after full duration")


func test_ease_out_curve_applied() -> void:
	muzzle.start_effect()
	muzzle.process(0.15)  # 50% through

	# With ease-out (fade^2): at 50%, fade=0.5, fade^2=0.25
	# energy = 4.5 * 0.25 = 1.125
	assert_almost_eq(muzzle._light_energy, 4.5 * 0.25, 0.01,
		"Ease-out curve should be applied (fade^2)")


func test_sprite_fades_with_same_curve() -> void:
	muzzle.start_effect()
	muzzle.process(0.15)  # 50% through

	assert_almost_eq(muzzle._sprite_alpha, MockMuzzleFlash.SPRITE_START_ALPHA * 0.25, 0.01,
		"Flash sprite alpha should fade with the same ease-out curve as the light")


func test_sprite_shrinks_over_time() -> void:
	muzzle.start_effect()
	muzzle.process(0.15)

	assert_lt(muzzle._sprite_scale, 1.0,
		"Flash sprite should shrink slightly as it fades")
	assert_gt(muzzle._sprite_scale, MockMuzzleFlash.SPRITE_END_SCALE_MULTIPLIER,
		"Mid-flash sprite scale should remain above its final scale")


func test_sprite_alpha_zero_after_duration() -> void:
	muzzle.start_effect()
	muzzle.process(0.3)

	assert_almost_eq(muzzle._sprite_alpha, 0.0, 0.01,
		"Flash sprite alpha should be ~0 after full duration")


func test_no_update_when_inactive() -> void:
	muzzle._light_energy = 3.0
	muzzle.process(0.1)

	assert_eq(muzzle._light_energy, 3.0,
		"Process should not change energy when inactive")
