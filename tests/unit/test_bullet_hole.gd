extends GutTest
## Unit tests for bullet_hole.gd persistent wall damage effect.
##
## Tests default configuration including auto_fade, fade timing,
## and initial alpha values.


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


var hole: MockBulletHole


func before_each() -> void:
	hole = MockBulletHole.new()


func after_each() -> void:
	hole = null


# ============================================================================
# Default Configuration Tests
# ============================================================================


func test_auto_fade_default_false() -> void:
	assert_false(hole.auto_fade,
		"Bullet hole auto_fade should default to false (permanent)")


func test_fade_delay_default() -> void:
	assert_eq(hole.fade_delay, 60.0,
		"Bullet hole fade_delay should default to 60.0 seconds")


func test_fade_duration_default() -> void:
	assert_eq(hole.fade_duration, 10.0,
		"Bullet hole fade_duration should default to 10.0 seconds")


func test_initial_alpha_default() -> void:
	assert_eq(hole._initial_alpha, 0.9,
		"Bullet hole initial alpha should default to 0.9")


# ============================================================================
# Behavior Tests
# ============================================================================


func test_no_fade_by_default() -> void:
	hole.ready()

	assert_false(hole.fade_started,
		"Bullet hole should not start fade by default (permanent)")


func test_fade_starts_when_auto_fade_enabled() -> void:
	hole.auto_fade = true
	hole.ready()

	assert_true(hole.fade_started,
		"Bullet hole should start fade when auto_fade is enabled")


func test_initial_alpha_set_from_modulate() -> void:
	hole.modulate_a = 0.5
	hole.ready()

	assert_eq(hole._initial_alpha, 0.5,
		"Initial alpha should be set from current modulate value")


func test_remove() -> void:
	hole.remove()

	assert_true(hole.removed,
		"Remove should mark the hole as removed")


func test_quick_fade() -> void:
	hole.fade_out_quick()

	assert_true(hole.quick_fade_started,
		"Quick fade should be started")


# ============================================================================
# Alpha Range Tests
# ============================================================================


func test_alpha_in_valid_range() -> void:
	assert_gte(hole._initial_alpha, 0.0,
		"Initial alpha should be >= 0.0")
	assert_lte(hole._initial_alpha, 1.0,
		"Initial alpha should be <= 1.0")
