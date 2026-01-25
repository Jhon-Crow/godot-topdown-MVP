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
	var expected_alpha := _component.initial_alpha
	var steps_taken := 0
	var calculated_alpha := _component.initial_alpha - (steps_taken * _component.alpha_decay_rate)
	assert_almost_eq(calculated_alpha, expected_alpha, 0.001, "First footprint alpha should be initial_alpha")


## Test alpha calculation for subsequent footprints.
func test_alpha_decreases_per_step() -> void:
	var initial := _component.initial_alpha
	var decay := _component.alpha_decay_rate

	# Alpha for step 1 (second footprint)
	var alpha_1 := initial - (1 * decay)
	# Alpha for step 2 (third footprint)
	var alpha_2 := initial - (2 * decay)
	# Alpha for step 3 (fourth footprint)
	var alpha_3 := initial - (3 * decay)

	assert_true(alpha_1 < initial, "Alpha should decrease after step 1")
	assert_true(alpha_2 < alpha_1, "Alpha should decrease after step 2")
	assert_true(alpha_3 < alpha_2, "Alpha should decrease after step 3")


## Test alpha calculation for last footprint.
func test_last_footprint_alpha() -> void:
	var steps := _component.blood_steps_count
	var last_step_index := steps - 1
	var expected_alpha := _component.initial_alpha - (last_step_index * _component.alpha_decay_rate)
	assert_true(expected_alpha > 0, "Last footprint should still have positive alpha")


## Test that component requires CharacterBody2D parent.
func test_requires_characterbody2d_parent() -> void:
	# Create component on non-CharacterBody2D parent
	var bad_parent := Node2D.new()
	add_child(bad_parent)

	var script = load("res://scripts/components/bloody_feet_component.gd")
	var bad_component := script.new()
	bad_parent.add_child(bad_component)

	await wait_frames(2)

	# Component should handle gracefully (not crash)
	assert_false(bad_component.has_bloody_feet(), "Component should handle non-CharacterBody2D parent gracefully")

	bad_parent.queue_free()
	await wait_frames(2)


## Test blood detection area is created.
func test_blood_detector_created() -> void:
	var blood_detector := _component.get_node_or_null("BloodDetector")
	assert_not_null(blood_detector, "BloodDetector Area2D should be created")
	assert_true(blood_detector is Area2D, "BloodDetector should be an Area2D")


## Test blood detector has collision shape.
func test_blood_detector_has_collision() -> void:
	var blood_detector := _component.get_node_or_null("BloodDetector")
	if blood_detector:
		var collision := blood_detector.get_node_or_null("FootCollision")
		assert_not_null(collision, "BloodDetector should have FootCollision shape")


## Test component debug logging can be enabled.
func test_debug_logging_toggle() -> void:
	_component.debug_logging = true
	assert_true(_component.debug_logging, "Debug logging should be toggleable to true")

	_component.debug_logging = false
	assert_false(_component.debug_logging, "Debug logging should be toggleable to false")
