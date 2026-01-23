extends GutTest
## Unit tests for effect scripts (blood_decal, bullet_hole, effect_cleanup).
##
## Tests the visual effect configurations including fade behavior,
## auto-fade settings, and cleanup methods.


# ============================================================================
# Mock BloodDecal for Logic Tests
# ============================================================================


class MockBloodDecal:
	## Time in seconds before the decal starts fading.
	var fade_delay: float = 30.0

	## Time in seconds for the fade-out animation.
	var fade_duration: float = 5.0

	## Whether the decal should fade out over time.
	var auto_fade: bool = true

	## Initial alpha value.
	var _initial_alpha: float = 0.85

	## Current modulate alpha.
	var modulate_a: float = 0.85

	## Track if removed.
	var removed: bool = false

	## Track if fade started.
	var fade_started: bool = false

	## Track if quick fade started.
	var quick_fade_started: bool = false

	## Simulate ready.
	func ready() -> void:
		_initial_alpha = modulate_a

		if auto_fade:
			start_fade_timer()

	## Starts the timer for automatic fade-out.
	func start_fade_timer() -> void:
		fade_started = true

	## Immediately removes the decal.
	func remove() -> void:
		removed = true

	## Fades out the decal quickly.
	func fade_out_quick() -> void:
		quick_fade_started = true


# ============================================================================
# Mock BulletHole for Logic Tests
# ============================================================================


class MockBulletHole:
	## Whether the hole should fade out over time.
	var auto_fade: bool = false

	## Time in seconds before the hole starts fading.
	var fade_delay: float = 60.0

	## Time in seconds for the fade-out animation.
	var fade_duration: float = 10.0

	## Initial alpha value.
	var _initial_alpha: float = 0.9

	## Current modulate alpha.
	var modulate_a: float = 0.9

	## Track if removed.
	var removed: bool = false

	## Track if fade started.
	var fade_started: bool = false

	## Track if quick fade started.
	var quick_fade_started: bool = false

	## Simulate ready.
	func ready() -> void:
		_initial_alpha = modulate_a

		if auto_fade:
			start_fade_timer()

	## Starts the timer for automatic fade-out.
	func start_fade_timer() -> void:
		fade_started = true

	## Immediately removes the hole.
	func remove() -> void:
		removed = true

	## Fades out the hole quickly.
	func fade_out_quick() -> void:
		quick_fade_started = true


# ============================================================================
# Mock EffectCleanup for Logic Tests
# ============================================================================


class MockEffectCleanup:
	## Duration in seconds before effect is removed.
	var lifetime: float = 1.0

	## Time alive.
	var _time_alive: float = 0.0

	## Track if queued for removal.
	var queue_freed: bool = false

	## Simulate physics/process update.
	func process(delta: float) -> void:
		_time_alive += delta

		if _time_alive >= lifetime:
			queue_free()

	## Simulate queue_free.
	func queue_free() -> void:
		queue_freed = true


var blood_decal: MockBloodDecal
var bullet_hole: MockBulletHole
var effect_cleanup: MockEffectCleanup


func before_each() -> void:
	blood_decal = MockBloodDecal.new()
	bullet_hole = MockBulletHole.new()
	effect_cleanup = MockEffectCleanup.new()


func after_each() -> void:
	blood_decal = null
	bullet_hole = null
	effect_cleanup = null


# ============================================================================
# BloodDecal Default Configuration Tests
# ============================================================================


func test_blood_decal_default_fade_delay() -> void:
	assert_eq(blood_decal.fade_delay, 30.0,
		"Blood decal default fade delay should be 30 seconds")


func test_blood_decal_default_fade_duration() -> void:
	assert_eq(blood_decal.fade_duration, 5.0,
		"Blood decal default fade duration should be 5 seconds")


func test_blood_decal_default_auto_fade() -> void:
	assert_true(blood_decal.auto_fade,
		"Blood decal should auto fade by default")


func test_blood_decal_default_initial_alpha() -> void:
	assert_eq(blood_decal._initial_alpha, 0.85,
		"Blood decal default initial alpha should be 0.85")


# ============================================================================
# BloodDecal Behavior Tests
# ============================================================================


func test_blood_decal_starts_fade_when_auto_fade_true() -> void:
	blood_decal.ready()

	assert_true(blood_decal.fade_started,
		"Blood decal should start fade timer when auto_fade is true")


func test_blood_decal_no_fade_when_auto_fade_false() -> void:
	blood_decal.auto_fade = false
	blood_decal.ready()

	assert_false(blood_decal.fade_started,
		"Blood decal should not start fade timer when auto_fade is false")


func test_blood_decal_remove() -> void:
	blood_decal.remove()

	assert_true(blood_decal.removed)


func test_blood_decal_quick_fade() -> void:
	blood_decal.fade_out_quick()

	assert_true(blood_decal.quick_fade_started)


func test_blood_decal_initial_alpha_set_from_modulate() -> void:
	blood_decal.modulate_a = 0.7
	blood_decal.ready()

	assert_eq(blood_decal._initial_alpha, 0.7,
		"Initial alpha should be set from current modulate")


# ============================================================================
# BulletHole Default Configuration Tests
# ============================================================================


func test_bullet_hole_default_auto_fade() -> void:
	assert_false(bullet_hole.auto_fade,
		"Bullet hole should NOT auto fade by default (permanent)")


func test_bullet_hole_default_fade_delay() -> void:
	assert_eq(bullet_hole.fade_delay, 60.0,
		"Bullet hole default fade delay should be 60 seconds")


func test_bullet_hole_default_fade_duration() -> void:
	assert_eq(bullet_hole.fade_duration, 10.0,
		"Bullet hole default fade duration should be 10 seconds")


func test_bullet_hole_default_initial_alpha() -> void:
	assert_eq(bullet_hole._initial_alpha, 0.9,
		"Bullet hole default initial alpha should be 0.9")


# ============================================================================
# BulletHole Behavior Tests
# ============================================================================


func test_bullet_hole_no_fade_by_default() -> void:
	bullet_hole.ready()

	assert_false(bullet_hole.fade_started,
		"Bullet hole should not start fade by default")


func test_bullet_hole_starts_fade_when_enabled() -> void:
	bullet_hole.auto_fade = true
	bullet_hole.ready()

	assert_true(bullet_hole.fade_started,
		"Bullet hole should start fade when auto_fade is enabled")


func test_bullet_hole_remove() -> void:
	bullet_hole.remove()

	assert_true(bullet_hole.removed)


func test_bullet_hole_quick_fade() -> void:
	bullet_hole.fade_out_quick()

	assert_true(bullet_hole.quick_fade_started)


func test_bullet_hole_initial_alpha_set_from_modulate() -> void:
	bullet_hole.modulate_a = 0.5
	bullet_hole.ready()

	assert_eq(bullet_hole._initial_alpha, 0.5)


# ============================================================================
# EffectCleanup Default Configuration Tests
# ============================================================================


func test_effect_cleanup_default_lifetime() -> void:
	assert_eq(effect_cleanup.lifetime, 1.0,
		"Effect cleanup default lifetime should be 1 second")


# ============================================================================
# EffectCleanup Behavior Tests
# ============================================================================


func test_effect_cleanup_not_freed_before_lifetime() -> void:
	effect_cleanup.process(0.5)

	assert_false(effect_cleanup.queue_freed)


func test_effect_cleanup_freed_after_lifetime() -> void:
	effect_cleanup.process(1.5)

	assert_true(effect_cleanup.queue_freed)


func test_effect_cleanup_freed_at_exact_lifetime() -> void:
	effect_cleanup.process(1.0)

	assert_true(effect_cleanup.queue_freed)


func test_effect_cleanup_custom_lifetime() -> void:
	effect_cleanup.lifetime = 3.0
	effect_cleanup.process(2.0)

	assert_false(effect_cleanup.queue_freed)

	effect_cleanup.process(1.5)

	assert_true(effect_cleanup.queue_freed)


func test_effect_cleanup_time_accumulates() -> void:
	effect_cleanup.process(0.3)
	effect_cleanup.process(0.3)
	effect_cleanup.process(0.3)

	assert_almost_eq(effect_cleanup._time_alive, 0.9, 0.001)
	assert_false(effect_cleanup.queue_freed)

	effect_cleanup.process(0.2)

	assert_true(effect_cleanup.queue_freed)


# ============================================================================
# Cross-Effect Comparison Tests
# ============================================================================


func test_blood_decal_fades_faster_than_bullet_hole() -> void:
	assert_lt(blood_decal.fade_delay, bullet_hole.fade_delay,
		"Blood decal should fade sooner than bullet hole")


func test_blood_decal_fade_duration_shorter_than_bullet_hole() -> void:
	assert_lt(blood_decal.fade_duration, bullet_hole.fade_duration,
		"Blood decal fade should be shorter than bullet hole")


func test_bullet_hole_more_opaque_than_blood_decal() -> void:
	assert_gt(bullet_hole._initial_alpha, blood_decal._initial_alpha,
		"Bullet hole should be more opaque than blood decal")


# ============================================================================
# Edge Cases Tests
# ============================================================================


func test_zero_fade_delay() -> void:
	blood_decal.fade_delay = 0.0
	blood_decal.ready()

	# Should still start fade timer
	assert_true(blood_decal.fade_started)


func test_zero_lifetime_immediate_cleanup() -> void:
	effect_cleanup.lifetime = 0.0
	effect_cleanup.process(0.001)

	assert_true(effect_cleanup.queue_freed)


func test_negative_lifetime_still_works() -> void:
	effect_cleanup.lifetime = -1.0
	effect_cleanup.process(0.001)

	# Any time >= -1.0 should trigger cleanup
	assert_true(effect_cleanup.queue_freed)


func test_very_large_fade_delay() -> void:
	blood_decal.fade_delay = 999999.0
	blood_decal.ready()

	# Should still start fade timer (just with large delay)
	assert_true(blood_decal.fade_started)


func test_alpha_values_in_valid_range() -> void:
	assert_gte(blood_decal._initial_alpha, 0.0)
	assert_lte(blood_decal._initial_alpha, 1.0)
	assert_gte(bullet_hole._initial_alpha, 0.0)
	assert_lte(bullet_hole._initial_alpha, 1.0)
