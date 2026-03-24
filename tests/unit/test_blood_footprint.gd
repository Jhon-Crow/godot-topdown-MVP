extends GutTest
## Unit tests for blood_footprint.gd bloody boot print decal.
##
## Tests initial alpha, foot texture selection logic,
## and alpha setting behavior.


# ============================================================================
# Mock Texture for Foot Selection Tests
# ============================================================================


class MockTexture:
	var name: String = ""

	func _init(n: String) -> void:
		name = n


# ============================================================================
# Mock BloodFootprint for Logic Tests
# ============================================================================


class MockBloodFootprint:
	## Initial alpha value (set by spawner based on step count).
	var _initial_alpha: float = 0.8

	## Current modulate alpha.
	var modulate_a: float = 1.0

	## Current modulate color.
	var modulate_r: float = 1.0
	var modulate_g: float = 1.0
	var modulate_b: float = 1.0

	## Current texture.
	var texture = null

	## Simulated loaded textures.
	var _left_texture = null
	var _right_texture = null
	var _textures_loaded: bool = false

	## Blood color.
	var _blood_color: Color = Color(0.545, 0.0, 0.0, 1.0)

	## Load mock textures.
	func load_textures() -> void:
		if _textures_loaded:
			return
		_left_texture = MockTexture.new("left")
		_right_texture = MockTexture.new("right")
		_textures_loaded = true

	## Set the footprint alpha.
	func set_alpha(alpha: float) -> void:
		_initial_alpha = alpha
		modulate_a = alpha

	## Set which foot this print is for.
	func set_foot(is_left: bool) -> void:
		load_textures()

		if is_left and _left_texture:
			texture = _left_texture
		elif not is_left and _right_texture:
			texture = _right_texture
		else:
			if _left_texture:
				texture = _left_texture
			elif _right_texture:
				texture = _right_texture

	## Set the blood color.
	func set_blood_color(puddle_color: Color) -> void:
		_blood_color = puddle_color
		modulate_r = puddle_color.r
		modulate_g = puddle_color.g
		modulate_b = puddle_color.b


var footprint: MockBloodFootprint


func before_each() -> void:
	footprint = MockBloodFootprint.new()


func after_each() -> void:
	footprint = null


# ============================================================================
# Default Configuration Tests
# ============================================================================


func test_initial_alpha_default() -> void:
	assert_eq(footprint._initial_alpha, 0.8,
		"Blood footprint initial alpha should default to 0.8")


func test_default_blood_color() -> void:
	assert_almost_eq(footprint._blood_color.r, 0.545, 0.001,
		"Default blood color red channel should be 0.545")
	assert_eq(footprint._blood_color.g, 0.0,
		"Default blood color green channel should be 0.0")
	assert_eq(footprint._blood_color.b, 0.0,
		"Default blood color blue channel should be 0.0")


# ============================================================================
# Foot Texture Selection Tests
# ============================================================================


func test_left_foot_texture() -> void:
	footprint.set_foot(true)

	assert_not_null(footprint.texture,
		"Texture should be set for left foot")
	assert_eq((footprint.texture as MockTexture).name, "left",
		"Left foot should use left texture")


func test_right_foot_texture() -> void:
	footprint.set_foot(false)

	assert_not_null(footprint.texture,
		"Texture should be set for right foot")
	assert_eq((footprint.texture as MockTexture).name, "right",
		"Right foot should use right texture")


func test_left_foot_fallback_when_no_left_texture() -> void:
	footprint.load_textures()
	footprint._left_texture = null
	footprint.set_foot(true)

	assert_not_null(footprint.texture,
		"Should fall back to right texture when left is unavailable")
	assert_eq((footprint.texture as MockTexture).name, "right",
		"Should use right texture as fallback")


func test_right_foot_fallback_when_no_right_texture() -> void:
	footprint.load_textures()
	footprint._right_texture = null
	footprint.set_foot(false)

	assert_not_null(footprint.texture,
		"Should fall back to left texture when right is unavailable")
	assert_eq((footprint.texture as MockTexture).name, "left",
		"Should use left texture as fallback")


# ============================================================================
# Alpha Setting Tests
# ============================================================================


func test_set_alpha_updates_initial_alpha() -> void:
	footprint.set_alpha(0.5)

	assert_eq(footprint._initial_alpha, 0.5,
		"set_alpha should update _initial_alpha")


func test_set_alpha_updates_modulate() -> void:
	footprint.set_alpha(0.3)

	assert_eq(footprint.modulate_a, 0.3,
		"set_alpha should update modulate alpha")


func test_set_alpha_zero() -> void:
	footprint.set_alpha(0.0)

	assert_eq(footprint._initial_alpha, 0.0)
	assert_eq(footprint.modulate_a, 0.0)


func test_set_alpha_full() -> void:
	footprint.set_alpha(1.0)

	assert_eq(footprint._initial_alpha, 1.0)
	assert_eq(footprint.modulate_a, 1.0)


# ============================================================================
# Blood Color Tests
# ============================================================================


func test_set_blood_color() -> void:
	var color := Color(0.8, 0.1, 0.05, 1.0)
	footprint.set_blood_color(color)

	assert_eq(footprint._blood_color, color,
		"Blood color should be updated")
	assert_almost_eq(footprint.modulate_r, 0.8, 0.001,
		"Modulate red should match blood color")
	assert_almost_eq(footprint.modulate_g, 0.1, 0.001,
		"Modulate green should match blood color")
	assert_almost_eq(footprint.modulate_b, 0.05, 0.001,
		"Modulate blue should match blood color")
