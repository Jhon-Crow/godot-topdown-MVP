extends GutTest
## Unit tests for muzzle_flash.gd muzzle flash visual effect.
##
## Tests flash duration, light start energy, floor-glow sprite fade, and the
## lifecycle behaviour.


# ============================================================================
# Mock MuzzleFlash for Logic Tests
# ============================================================================


class MockMuzzleFlash:
	## Duration of the muzzle flash effect in seconds.
	const FLASH_DURATION: float = 0.3

	## Starting energy of the point light (matches backup branch brightness).
	const LIGHT_START_ENERGY: float = 4.5

	## Starting alpha of the floor glow sprite.
	const FLOOR_GLOW_START_ALPHA: float = 0.9

	## Time tracker.
	var _elapsed_time: float = 0.0

	## Whether the effect is active.
	var _is_active: bool = false

	## Current light energy.
	var _light_energy: float = 0.0

	## Current floor glow alpha.
	var _floor_glow_alpha: float = 0.0

	## Whether cleanup was scheduled.
	var _cleanup_scheduled: bool = false

	## Simulate starting the effect.
	func start_effect() -> void:
		_is_active = true
		_elapsed_time = 0.0
		_light_energy = LIGHT_START_ENERGY
		_floor_glow_alpha = FLOOR_GLOW_START_ALPHA

	## Simulate process update.
	func process(delta: float) -> void:
		if not _is_active:
			return

		_elapsed_time += delta
		var progress := clampf(_elapsed_time / FLASH_DURATION, 0.0, 1.0)

		var fade := 1.0 - progress
		fade = fade * fade
		_light_energy = LIGHT_START_ENERGY * fade
		_floor_glow_alpha = FLOOR_GLOW_START_ALPHA * fade

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


func test_light_start_energy_matches_backup_branch() -> void:
	assert_eq(MockMuzzleFlash.LIGHT_START_ENERGY, 4.5,
		"LIGHT_START_ENERGY should match the backup branch brightness (Issue #1845)")


func test_floor_glow_start_alpha_is_positive() -> void:
	assert_gt(MockMuzzleFlash.FLOOR_GLOW_START_ALPHA, 0.0,
		"Floor glow alpha should be positive so the flash is visible on the floor")
	assert_lte(MockMuzzleFlash.FLOOR_GLOW_START_ALPHA, 1.0,
		"Floor glow alpha should not exceed 1.0")


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

	assert_eq(muzzle._light_energy, MockMuzzleFlash.LIGHT_START_ENERGY,
		"Light energy should be LIGHT_START_ENERGY on start")


func test_initial_floor_glow_alpha_on_start() -> void:
	muzzle.start_effect()

	assert_eq(muzzle._floor_glow_alpha, MockMuzzleFlash.FLOOR_GLOW_START_ALPHA,
		"Floor glow alpha should be FLOOR_GLOW_START_ALPHA on start")


func test_energy_decreases_over_time() -> void:
	muzzle.start_effect()
	muzzle.process(0.15)

	assert_lt(muzzle._light_energy, MockMuzzleFlash.LIGHT_START_ENERGY,
		"Light energy should decrease over time")
	assert_gt(muzzle._light_energy, 0.0,
		"Light energy should still be positive mid-fade")


func test_floor_glow_alpha_decreases_over_time() -> void:
	muzzle.start_effect()
	muzzle.process(0.15)

	assert_lt(muzzle._floor_glow_alpha, MockMuzzleFlash.FLOOR_GLOW_START_ALPHA,
		"Floor glow alpha should decrease over time")
	assert_gt(muzzle._floor_glow_alpha, 0.0,
		"Floor glow alpha should still be positive mid-fade")


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


func test_floor_glow_alpha_zero_after_duration() -> void:
	muzzle.start_effect()
	muzzle.process(0.3)

	assert_almost_eq(muzzle._floor_glow_alpha, 0.0, 0.01,
		"Floor glow alpha should be ~0 after full duration")


func test_ease_out_curve_applied_to_light() -> void:
	muzzle.start_effect()
	muzzle.process(0.15)  # 50% through

	# With ease-out (fade^2): at 50%, fade=0.5, fade^2=0.25
	assert_almost_eq(muzzle._light_energy, MockMuzzleFlash.LIGHT_START_ENERGY * 0.25, 0.01,
		"Ease-out curve should be applied to the point light (fade^2)")


func test_ease_out_curve_applied_to_floor_glow() -> void:
	muzzle.start_effect()
	muzzle.process(0.15)  # 50% through

	# With ease-out (fade^2): at 50%, fade=0.5, fade^2=0.25
	assert_almost_eq(muzzle._floor_glow_alpha, MockMuzzleFlash.FLOOR_GLOW_START_ALPHA * 0.25, 0.01,
		"Ease-out curve should be applied to the floor glow (fade^2)")


func test_no_update_when_inactive() -> void:
	muzzle._light_energy = 3.0
	muzzle._floor_glow_alpha = 0.5
	muzzle.process(0.1)

	assert_eq(muzzle._light_energy, 3.0,
		"Process should not change light energy when inactive")
	assert_eq(muzzle._floor_glow_alpha, 0.5,
		"Process should not change floor glow alpha when inactive")


# ============================================================================
# Floor Visibility Regression Tests (Issue #1845)
# ============================================================================


func test_floor_glow_is_visible_during_first_half_of_effect() -> void:
	## On maps with bright ambient lighting (e.g. Labyrinth Complex), the
	## PointLight2D addition is too small to perceive against the already-lit
	## floor. The additive FloorGlow Sprite2D is responsible for making the
	## flash visible on the floor regardless of the map's ambient lights.
	muzzle.start_effect()
	muzzle.process(0.05)

	assert_gt(muzzle._floor_glow_alpha, 0.3,
		"Floor glow must remain clearly visible during the first third of the flash")
