extends GutTest
## Unit tests for orange_blinking_light.gd (Issue #1436).
##
## Tests blinking logic and rotation constants without requiring
## a Godot scene tree (mock-based).


# ============================================================================
# Mock OrangeBlinkingLight for Logic Tests
# ============================================================================


class MockOrangeBlinkingLight:
	## Rotation speed in radians per second.
	const ROTATION_SPEED: float = PI

	## Blink interval in seconds (50% duty cycle).
	const BLINK_INTERVAL: float = 0.4

	## Light energy when on.
	const LIGHT_ON_ENERGY: float = 4.0

	## Orange color for industrial warning lamps.
	const LIGHT_COLOR: Color = Color(1.0, 0.45, 0.05, 1.0)

	## Current rotation in radians.
	var rotation: float = 0.0

	## Accumulated blink timer.
	var _blink_timer: float = 0.0

	## Simulated energy of LightA.
	var light_a_energy: float = LIGHT_ON_ENERGY

	## Simulated energy of LightB.
	var light_b_energy: float = LIGHT_ON_ENERGY

	## Simulate one _process tick.
	func process(delta: float) -> void:
		rotation += ROTATION_SPEED * delta

		_blink_timer += delta
		var phase: float = fmod(_blink_timer, BLINK_INTERVAL * 2.0)
		var lights_on: bool = phase < BLINK_INTERVAL

		light_a_energy = LIGHT_ON_ENERGY if lights_on else 0.0
		light_b_energy = LIGHT_ON_ENERGY if lights_on else 0.0


# ============================================================================
# Tests
# ============================================================================


func test_rotation_increases_over_time() -> void:
	var light := MockOrangeBlinkingLight.new()
	assert_eq(light.rotation, 0.0, "Initial rotation should be 0")
	light.process(1.0)
	assert_almost_eq(light.rotation, PI, 0.001, "After 1s rotation should be PI rad")


func test_lights_are_on_at_start() -> void:
	var light := MockOrangeBlinkingLight.new()
	# At time 0, phase = 0, which is < BLINK_INTERVAL → on
	light.process(0.0)
	assert_eq(light.light_a_energy, MockOrangeBlinkingLight.LIGHT_ON_ENERGY,
		"LightA should be on at the start of the blink cycle")
	assert_eq(light.light_b_energy, MockOrangeBlinkingLight.LIGHT_ON_ENERGY,
		"LightB should be on at the start of the blink cycle")


func test_lights_turn_off_after_blink_interval() -> void:
	var light := MockOrangeBlinkingLight.new()
	# Advance to just past the ON phase (0.4 s)
	light.process(0.41)
	assert_eq(light.light_a_energy, 0.0, "LightA should be off during OFF phase")
	assert_eq(light.light_b_energy, 0.0, "LightB should be off during OFF phase")


func test_lights_turn_on_again_after_full_cycle() -> void:
	var light := MockOrangeBlinkingLight.new()
	# One full cycle = BLINK_INTERVAL * 2 = 0.8 s → lights should be on again
	light.process(0.81)
	assert_eq(light.light_a_energy, MockOrangeBlinkingLight.LIGHT_ON_ENERGY,
		"LightA should be on again after a full blink cycle")
	assert_eq(light.light_b_energy, MockOrangeBlinkingLight.LIGHT_ON_ENERGY,
		"LightB should be on again after a full blink cycle")


func test_both_lights_blink_in_sync() -> void:
	var light := MockOrangeBlinkingLight.new()
	light.process(0.5)
	assert_eq(light.light_a_energy, light.light_b_energy,
		"LightA and LightB must always be in sync")


func test_light_color_is_orange() -> void:
	var color := MockOrangeBlinkingLight.LIGHT_COLOR
	assert_gt(color.r, 0.9, "Red channel should be near 1.0 for orange")
	assert_gt(color.g, 0.3, "Green channel should be moderate for orange")
	assert_lt(color.g, 0.6, "Green channel should be moderate for orange")
	assert_lt(color.b, 0.2, "Blue channel should be low for orange")


func test_rotation_speed_is_pi_per_second() -> void:
	assert_almost_eq(MockOrangeBlinkingLight.ROTATION_SPEED, PI, 0.001,
		"Rotation speed should be PI rad/s (one full turn per 2 seconds)")


func test_multiple_cycles() -> void:
	var light := MockOrangeBlinkingLight.new()
	# Run for 5 full cycles (4.0 s) and verify lights are on at cycle boundaries
	light.process(4.0)
	assert_eq(light.light_a_energy, MockOrangeBlinkingLight.LIGHT_ON_ENERGY,
		"LightA should be on at the start of a new cycle after 5 complete cycles")
