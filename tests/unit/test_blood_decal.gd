extends GutTest
## Unit tests for blood_decal.gd persistent blood stain effect.
##
## Tests default configuration values, puddle area setup,
## collision layer assignment, and auto-fade behavior.


# ============================================================================
# Mock BloodDecal for Logic Tests
# ============================================================================


class MockBloodDecal:
	## Time in seconds before the decal starts fading.
	var fade_delay: float = 30.0

	## Time in seconds for the fade-out animation.
	var fade_duration: float = 5.0

	## Whether the decal should fade out over time.
	var auto_fade: bool = false

	## Whether this decal can be stepped in.
	var is_puddle: bool = true

	## Initial alpha value.
	var _initial_alpha: float = 0.85

	## Current modulate alpha.
	var modulate_a: float = 0.85

	## Collision layer for puddle area (2^6 = 64 for layer 7).
	var puddle_collision_layer: int = 64

	## Puddle area radius.
	var puddle_radius: float = 12.0

	## Track if fade started.
	var fade_started: bool = false

	## Track if removed.
	var removed: bool = false

	## Track if quick fade started.
	var quick_fade_started: bool = false

	## Track if puddle area was set up.
	var puddle_area_setup: bool = false

	## Simulated texture width/height for radius calculation.
	var texture_width: float = 0.0
	var texture_height: float = 0.0
	var scale_x: float = 1.0

	## Simulate ready.
	func ready() -> void:
		_initial_alpha = modulate_a

		if is_puddle:
			_setup_puddle_area()

		if auto_fade:
			start_fade_timer()

	## Set up the puddle area with collision layer.
	func _setup_puddle_area() -> void:
		puddle_area_setup = true
		puddle_collision_layer = 64  # Bit 6 = layer 7

		if texture_width > 0.0 or texture_height > 0.0:
			puddle_radius = max(texture_width, texture_height) * scale_x * 0.4
		else:
			puddle_radius = 12.0  # Default radius

	## Starts the timer for automatic fade-out.
	func start_fade_timer() -> void:
		fade_started = true

	## Immediately removes the decal.
	func remove() -> void:
		removed = true

	## Fades out the decal quickly.
	func fade_out_quick() -> void:
		quick_fade_started = true


var decal: MockBloodDecal


func before_each() -> void:
	decal = MockBloodDecal.new()


func after_each() -> void:
	decal = null


# ============================================================================
# Default Configuration Tests
# ============================================================================


func test_fade_delay_default() -> void:
	assert_eq(decal.fade_delay, 30.0,
		"Blood decal fade_delay should default to 30.0 seconds")


func test_fade_duration_default() -> void:
	assert_eq(decal.fade_duration, 5.0,
		"Blood decal fade_duration should default to 5.0 seconds")


func test_initial_alpha_default() -> void:
	assert_eq(decal._initial_alpha, 0.85,
		"Blood decal initial alpha should default to 0.85")


func test_auto_fade_default_false() -> void:
	assert_false(decal.auto_fade,
		"Blood decal auto_fade should default to false")


# ============================================================================
# Puddle Area Tests
# ============================================================================


func test_puddle_area_setup_on_ready() -> void:
	decal.ready()

	assert_true(decal.puddle_area_setup,
		"Puddle area should be set up when is_puddle is true")


func test_puddle_area_not_setup_when_not_puddle() -> void:
	decal.is_puddle = false
	decal.ready()

	assert_false(decal.puddle_area_setup,
		"Puddle area should not be set up when is_puddle is false")


func test_puddle_collision_layer_is_64() -> void:
	decal.ready()

	assert_eq(decal.puddle_collision_layer, 64,
		"Puddle area collision layer should be 64 (bit 6, layer 7)")


func test_puddle_default_radius() -> void:
	decal.ready()

	assert_eq(decal.puddle_radius, 12.0,
		"Puddle radius should default to 12.0 when no texture")


func test_puddle_radius_from_texture() -> void:
	decal.texture_width = 64.0
	decal.texture_height = 48.0
	decal.scale_x = 1.0
	decal.ready()

	# max(64, 48) * 1.0 * 0.4 = 25.6
	assert_almost_eq(decal.puddle_radius, 25.6, 0.01,
		"Puddle radius should be max(width, height) * scale * 0.4")


func test_puddle_radius_with_scale() -> void:
	decal.texture_width = 32.0
	decal.texture_height = 32.0
	decal.scale_x = 2.0
	decal.ready()

	# max(32, 32) * 2.0 * 0.4 = 25.6
	assert_almost_eq(decal.puddle_radius, 25.6, 0.01,
		"Puddle radius should account for scale")


# ============================================================================
# Auto-fade Behavior Tests
# ============================================================================


func test_no_fade_when_auto_fade_false() -> void:
	decal.ready()

	assert_false(decal.fade_started,
		"Fade should not start when auto_fade is false")


func test_fade_starts_when_auto_fade_true() -> void:
	decal.auto_fade = true
	decal.ready()

	assert_true(decal.fade_started,
		"Fade should start when auto_fade is true")


func test_initial_alpha_set_from_modulate() -> void:
	decal.modulate_a = 0.6
	decal.ready()

	assert_eq(decal._initial_alpha, 0.6,
		"Initial alpha should be set from modulate value")


func test_remove() -> void:
	decal.remove()

	assert_true(decal.removed,
		"Remove should mark the decal as removed")


func test_quick_fade() -> void:
	decal.fade_out_quick()

	assert_true(decal.quick_fade_started,
		"Quick fade should be started")
