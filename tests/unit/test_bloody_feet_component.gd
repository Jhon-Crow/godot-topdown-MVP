extends GutTest
## Unit tests for BloodyFeetComponent.
##
## Tests the bloody footprints feature where characters stepping in blood
## leave footprint trails that fade with each step.


## Mock CharacterBody2D for testing without full scene.
class MockCharacter extends CharacterBody2D:
	var test_position: Vector2 = Vector2.ZERO

	func _init() -> void:
		collision_layer = 1
		collision_mask = 0


## Mock BloodDecal for testing puddle detection.
class MockBloodPuddle extends Area2D:
	func _init() -> void:
		add_to_group("blood_puddle")
		collision_layer = 64
		collision_mask = 0
		monitorable = true


class MockBloodDecal extends Sprite2D:
	var puddle_area: Area2D = Area2D.new()

	func _init() -> void:
		add_to_group("blood_puddle")
		modulate = Color(1.0, 1.0, 1.0, 0.85)
		var gradient := Gradient.new()
		gradient.colors = PackedColorArray([
			Color(0.5, 0.02, 0.02, 1.0),
			Color(0.5, 0.02, 0.02, 0.5),
			Color(0.5, 0.02, 0.02, 0.0),
		])
		gradient.offsets = PackedFloat32Array([0.0, 0.8, 1.0])
		var gradient_texture := GradientTexture2D.new()
		gradient_texture.gradient = gradient
		texture = gradient_texture
		puddle_area.name = "PuddleArea"
		puddle_area.add_to_group("blood_puddle")
		add_child(puddle_area)


var _component: Node = null
var _character: MockCharacter = null


func before_each() -> void:
	_character = MockCharacter.new()
	_character.global_position = Vector2(100, 100)
	add_child(_character)

	# Load component script and create instance
	var script = load("res://scripts/components/bloody_feet_component.gd")
	_component = script.new()
	_character.add_child(_component)

	# Wait for _ready to complete
	await wait_frames(2)


func after_each() -> void:
	if _character:
		_character.queue_free()
	_character = null
	_component = null
	await wait_frames(2)


## Test that component initializes correctly.
func test_component_initializes() -> void:
	assert_not_null(_component, "Component should be created")
	assert_eq(_component.get_blood_level(), 0, "Initial blood level should be 0")
	assert_false(_component.has_bloody_feet(), "Should not have bloody feet initially")


## Test that blood level can be set manually.
func test_set_blood_level() -> void:
	_component.set_blood_level(4)
	assert_eq(_component.get_blood_level(), 4, "Blood level should be set to 4")
	assert_true(_component.has_bloody_feet(), "Should have bloody feet after setting level")


## Test that blood level is clamped to max.
func test_blood_level_clamped_to_max() -> void:
	_component.set_blood_level(100)  # Way above default max of 12
	assert_eq(_component.get_blood_level(), 12, "Blood level should be clamped to blood_steps_count")


## Test that blood level is clamped to zero.
func test_blood_level_clamped_to_zero() -> void:
	_component.set_blood_level(-5)
	assert_eq(_component.get_blood_level(), 0, "Blood level should be clamped to 0")


## Test that component exports are accessible.
func test_exports_accessible() -> void:
	assert_eq(_component.blood_steps_count, 12, "Default blood_steps_count should be 12")
	assert_eq(_component.step_distance, 30.0, "Default step_distance should be 30.0")
	assert_eq(_component.initial_alpha, 0.8, "Default initial_alpha should be 0.8")
	assert_eq(_component.alpha_decay_rate, 0.06, "Default alpha_decay_rate should be 0.06")


## Test custom configuration of exports.
func test_custom_exports() -> void:
	_component.blood_steps_count = 10
	_component.step_distance = 50.0
	_component.initial_alpha = 0.9
	_component.alpha_decay_rate = 0.08

	assert_eq(_component.blood_steps_count, 10, "blood_steps_count should be configurable")
	assert_eq(_component.step_distance, 50.0, "step_distance should be configurable")
	assert_eq(_component.initial_alpha, 0.9, "initial_alpha should be configurable")
	assert_eq(_component.alpha_decay_rate, 0.08, "alpha_decay_rate should be configurable")


## Test that setting blood level to max sets has_bloody_feet.
func test_has_bloody_feet_true_when_level_positive() -> void:
	_component.set_blood_level(1)
	assert_true(_component.has_bloody_feet(), "has_bloody_feet should be true with level > 0")


## Test that has_bloody_feet returns false when level is zero.
func test_has_bloody_feet_false_when_level_zero() -> void:
	_component.set_blood_level(0)
	assert_false(_component.has_bloody_feet(), "has_bloody_feet should be false with level = 0")


## Test alpha calculation for first footprint.
func test_first_footprint_alpha() -> void:
	# First step should have initial_alpha
	var expected_alpha: float = _component.initial_alpha
	var steps_taken: int = 0
	var calculated_alpha: float = _component.initial_alpha - (steps_taken * _component.alpha_decay_rate)
	assert_almost_eq(calculated_alpha, expected_alpha, 0.001, "First footprint alpha should be initial_alpha")


## Test alpha calculation for subsequent footprints.
func test_alpha_decreases_per_step() -> void:
	var initial: float = _component.initial_alpha
	var decay: float = _component.alpha_decay_rate

	# Alpha for step 1 (second footprint)
	var alpha_1: float = initial - (1 * decay)
	# Alpha for step 2 (third footprint)
	var alpha_2: float = initial - (2 * decay)
	# Alpha for step 3 (fourth footprint)
	var alpha_3: float = initial - (3 * decay)

	assert_true(alpha_1 < initial, "Alpha should decrease after step 1")
	assert_true(alpha_2 < alpha_1, "Alpha should decrease after step 2")
	assert_true(alpha_3 < alpha_2, "Alpha should decrease after step 3")


## Test alpha calculation for last footprint.
func test_last_footprint_alpha() -> void:
	var steps: int = _component.blood_steps_count
	var last_step_index: int = steps - 1
	var expected_alpha: float = _component.initial_alpha - (last_step_index * _component.alpha_decay_rate)
	assert_true(expected_alpha > 0, "Last footprint should still have positive alpha")


## Test that component requires CharacterBody2D parent.
func test_requires_characterbody2d_parent() -> void:
	# Create component on non-CharacterBody2D parent
	var bad_parent := Node2D.new()
	add_child(bad_parent)

	var script: GDScript = load("res://scripts/components/bloody_feet_component.gd")
	var bad_component: Node = script.new()
	bad_parent.add_child(bad_component)

	await wait_frames(2)

	# Component should handle gracefully (not crash)
	assert_false(bad_component.has_bloody_feet(), "Component should handle non-CharacterBody2D parent gracefully")

	bad_parent.queue_free()
	await wait_frames(2)


## Test blood detection area is created.
func test_blood_detector_created() -> void:
	var blood_detector := _character.get_node_or_null("BloodDetector")
	assert_not_null(blood_detector, "BloodDetector Area2D should be created")
	assert_true(blood_detector is Area2D, "BloodDetector should be an Area2D")


## Test blood detector has collision shape.
func test_blood_detector_has_collision() -> void:
	var blood_detector := _character.get_node_or_null("BloodDetector")
	if blood_detector:
		var collision := blood_detector.get_node_or_null("FootCollision")
		assert_not_null(collision, "BloodDetector should have FootCollision shape")


## Test component debug logging can be enabled.
func test_debug_logging_toggle() -> void:
	_component.debug_logging = true
	assert_true(_component.debug_logging, "Debug logging should be toggleable to true")

	_component.debug_logging = false
	assert_false(_component.debug_logging, "Debug logging should be toggleable to false")


## Test that on_snow flag defaults to false.
func test_on_snow_defaults_false() -> void:
	assert_false(_component.on_snow,
		"on_snow should default to false (non-snow levels are not affected)")


## Test that on_snow flag can be enabled.
func test_on_snow_can_be_enabled() -> void:
	_component.on_snow = true
	assert_true(_component.on_snow,
		"on_snow should be settable to true by the level script")


## Test that snow_blood_steps_count defaults to 5.
func test_snow_blood_steps_count_defaults_to_5() -> void:
	assert_eq(_component.snow_blood_steps_count, 5,
		"snow_blood_steps_count should default to 5 for a longer fading red trail")


## Test that on snow, blood contact sets blood level to snow_blood_steps_count not halved 12 (Issue #1627).
func test_on_snow_blood_contact_uses_snow_blood_steps_count() -> void:
	_component.on_snow = true
	_component.snow_blood_steps_count = 5
	_component.blood_steps_count = 12
	# Simulate stepping in blood via the internal method
	_component._on_blood_puddle_contact(Color(0.545, 0.0, 0.0, 1.0))
	assert_eq(_component.get_blood_level(), 5,
		"On snow, blood_level should be set to snow_blood_steps_count")


## Test that snow surface detector is created when component initializes.
func test_snow_detector_created() -> void:
	# The detector is named "SnowDetectorForBlood" and attached to the parent body.
	await wait_frames(3)
	var snow_detector := _character.get_node_or_null("SnowDetectorForBlood")
	assert_not_null(snow_detector,
		"SnowDetectorForBlood Area2D should be created on the parent body")
	assert_true(snow_detector is Area2D,
		"SnowDetectorForBlood should be an Area2D")


## Test that on snow, blood level is exposed for SnowyFeetComponent to read (Issue #1627).
## SnowyFeetComponent handles all snow footprint rendering; BloodyFeetComponent only
## tracks blood level and exposes it via has_bloody_feet() and get_blood_level().
func test_on_snow_blood_level_exposed_for_snowy_feet() -> void:
	_component.on_snow = true
	_component.snow_blood_steps_count = 5
	_component._on_blood_puddle_contact(Color(0.545, 0.0, 0.0, 1.0))
	assert_true(_component.has_bloody_feet(),
		"has_bloody_feet() must return true so SnowyFeetComponent can detect blood and spawn red prints")
	assert_eq(_component.get_blood_level(), 5,
		"Blood level should be snow_blood_steps_count for SnowyFeetComponent to count down")


## Test that blood_contact signal is emitted on blood puddle contact (Issue #1627 race-condition fix).
## SnowyFeetComponent connects to this signal to arm its red-print counter immediately,
## before BloodyFeetComponent's _blood_level can drain to zero.
func test_blood_contact_signal_emitted_on_puddle_contact() -> void:
	watch_signals(_component)

	var puddle_color := Color(0.6, 0.0, 0.0, 1.0)
	_component._on_blood_puddle_contact(puddle_color)
	await wait_frames(1)

	assert_signal_emitted(_component, "blood_contact",
		"blood_contact signal must be emitted when _on_blood_puddle_contact is called")
	assert_signal_emitted_with_parameters(_component, "blood_contact", [puddle_color])


## Test that manual blood-level changes also emit blood_contact on snow.
## This covers scene/setup paths that grant blood without an area_entered signal.
func test_set_blood_level_on_snow_emits_blood_contact_signal() -> void:
	_component.on_snow = true
	_component.snow_blood_steps_count = 5
	watch_signals(_component)

	_component.set_blood_level(5)
	await wait_frames(1)

	assert_signal_emitted(_component, "blood_contact",
		"set_blood_level() with blood on snow must emit blood_contact so SnowyFeetComponent arms red prints")
	assert_eq(_component.get_blood_level(), 5,
		"Blood level should be set to the requested snow blood count")


## Test that on snow, manual blood level is clamped to snow_blood_steps_count.
func test_set_blood_level_on_snow_clamps_to_snow_blood_steps_count() -> void:
	_component.on_snow = true
	_component.snow_blood_steps_count = 5
	_component.set_blood_level(12)

	assert_eq(_component.get_blood_level(), 5,
		"Snow blood level should clamp to snow_blood_steps_count, not regular blood_steps_count")


func test_get_puddle_color_uses_parent_decal_color_for_child_area() -> void:
	var decal := MockBloodDecal.new()
	add_child(decal)
	await wait_frames(1)

	var color: Color = _component._get_puddle_color(decal.puddle_area)

	assert_almost_eq(color.r, 1.0, 0.01,
		"Child PuddleArea contact should use the parent BloodDecal modulate color")
	assert_almost_eq(color.g, 1.0, 0.01,
		"Child PuddleArea contact should use the parent BloodDecal modulate color")
	assert_almost_eq(color.b, 1.0, 0.01,
		"Child PuddleArea contact should use the parent BloodDecal modulate color")

	decal.queue_free()
	await wait_frames(1)


func test_get_puddle_color_returns_decal_modulate_color() -> void:
	var decal_scene: PackedScene = load("res://scenes/effects/BloodDecal.tscn")
	assert_not_null(decal_scene, "BloodDecal scene must load for the regression test")
	if decal_scene == null:
		return

	var decal := decal_scene.instantiate() as Sprite2D
	assert_not_null(decal, "BloodDecal scene should instantiate as Sprite2D")
	if decal == null:
		return
	add_child(decal)
	await wait_frames(2)

	var puddle_area := decal.get_node_or_null("PuddleArea")
	assert_not_null(puddle_area, "BloodDecal should create a child PuddleArea for contact detection")
	if puddle_area == null:
		decal.queue_free()
		await wait_frames(1)
		return

	var color: Color = _component._get_puddle_color(puddle_area)

	assert_almost_eq(color.r, decal.modulate.r, 0.01,
		"Puddle color should match parent BloodDecal modulate red channel")
	assert_almost_eq(color.g, decal.modulate.g, 0.01,
		"Puddle color should match parent BloodDecal modulate green channel")
	assert_almost_eq(color.b, decal.modulate.b, 0.01,
		"Puddle color should match parent BloodDecal modulate blue channel")

	decal.queue_free()
	await wait_frames(1)


func test_on_snow_spawn_footprint_does_not_drain_before_snowy_feet_renders() -> void:
	_component.on_snow = true
	_component.snow_blood_steps_count = 5
	_component.set_blood_level(5)

	_component._spawn_footprint()

	assert_eq(_component.get_blood_level(), 5,
		"BloodyFeetComponent must not drain snow blood before SnowyFeetComponent renders red oval prints")


func test_consume_snow_blood_step_drains_after_snowy_feet_render() -> void:
	_component.on_snow = true
	_component.snow_blood_steps_count = 5
	_component.set_blood_level(5)

	_component.consume_snow_blood_step()

	assert_eq(_component.get_blood_level(), 4,
		"SnowyFeetComponent should explicitly consume one blood step after rendering a red snow print")
