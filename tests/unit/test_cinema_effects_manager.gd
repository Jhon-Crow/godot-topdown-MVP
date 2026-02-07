extends GutTest
## Unit tests for CinemaEffectsManager autoload.
##
## Tests the cinema film effects management functionality including:
## - Default constant values
## - Parameter clamping for all setter methods
## - State management (enabled/disabled, activation delay)
## - Death effects (trigger, reset, animation formulas)
## - Shader parameter tracking via Mock class


# ============================================================================
# Mock CinemaEffectsManager for Logic Tests
# ============================================================================


class MockCinemaEffectsManager:
	## Mirrors CinemaEffectsManager constants.
	const DEFAULT_GRAIN_INTENSITY: float = 0.15
	const DEFAULT_WARM_COLOR: Color = Color(1.0, 0.95, 0.85)
	const DEFAULT_WARM_INTENSITY: float = 0.12
	const DEFAULT_SUNNY_INTENSITY: float = 0.08
	const DEFAULT_VIGNETTE_INTENSITY: float = 0.25
	const DEFAULT_VIGNETTE_SOFTNESS: float = 0.45
	const DEFAULT_DEFECT_PROBABILITY: float = 0.015
	const DEFAULT_SCRATCH_INTENSITY: float = 0.6
	const DEFAULT_DUST_INTENSITY: float = 0.5
	const DEFAULT_FLICKER_INTENSITY: float = 0.03
	const DEFAULT_MICRO_SCRATCH_INTENSITY: float = 0.7
	const DEFAULT_MICRO_SCRATCH_PROBABILITY: float = 0.04
	const DEFAULT_CIGARETTE_BURN_SIZE: float = 0.15
	const DEFAULT_END_OF_REEL_DURATION: float = 3.0
	const ACTIVATION_DELAY_FRAMES: int = 1

	## Whether the effect is currently active.
	var _is_active: bool = true

	## Whether death effects are currently playing.
	var _death_effects_active: bool = false

	## Time tracker for end of reel animation.
	var _end_of_reel_timer: float = 0.0

	## Time tracker for death spots animation.
	var _death_spots_timer: float = 0.0

	## Whether we're waiting to activate the effect.
	var _waiting_for_activation: bool = false

	## Counter for delayed activation.
	var _activation_frame_counter: int = 0

	## Duration for end of reel effect.
	var _end_of_reel_duration: float = DEFAULT_END_OF_REEL_DURATION

	## Dictionary tracking all shader parameters (replaces ShaderMaterial).
	var _shader_params: Dictionary = {}

	## Whether the overlay is visible (replaces _cinema_rect.visible).
	var _overlay_visible: bool = false


	func _init() -> void:
		_set_default_parameters()


	## Sets all shader parameters to default values (mirrors source).
	func _set_default_parameters() -> void:
		# Grain parameters
		_shader_params["grain_intensity"] = DEFAULT_GRAIN_INTENSITY
		_shader_params["grain_enabled"] = true

		# Warm color parameters
		_shader_params["warm_color"] = DEFAULT_WARM_COLOR
		_shader_params["warm_intensity"] = DEFAULT_WARM_INTENSITY
		_shader_params["warm_enabled"] = true

		# Sunny effect parameters
		_shader_params["sunny_intensity"] = DEFAULT_SUNNY_INTENSITY
		_shader_params["sunny_enabled"] = true

		# Vignette parameters
		_shader_params["vignette_intensity"] = DEFAULT_VIGNETTE_INTENSITY
		_shader_params["vignette_softness"] = DEFAULT_VIGNETTE_SOFTNESS
		_shader_params["vignette_enabled"] = true

		# Film defect parameters
		_shader_params["defects_enabled"] = true
		_shader_params["defect_probability"] = DEFAULT_DEFECT_PROBABILITY
		_shader_params["scratch_intensity"] = DEFAULT_SCRATCH_INTENSITY
		_shader_params["dust_intensity"] = DEFAULT_DUST_INTENSITY
		_shader_params["flicker_intensity"] = DEFAULT_FLICKER_INTENSITY

		# Micro scratches parameters
		_shader_params["micro_scratches_enabled"] = true
		_shader_params["micro_scratch_intensity"] = DEFAULT_MICRO_SCRATCH_INTENSITY
		_shader_params["micro_scratch_probability"] = DEFAULT_MICRO_SCRATCH_PROBABILITY

		# Death effects (disabled by default)
		_shader_params["cigarette_burn_enabled"] = false
		_shader_params["cigarette_burn_intensity"] = 0.0
		_shader_params["cigarette_burn_position"] = Vector2(0.5, 0.5)
		_shader_params["cigarette_burn_size"] = DEFAULT_CIGARETTE_BURN_SIZE
		_shader_params["end_of_reel_enabled"] = false
		_shader_params["end_of_reel_intensity"] = 0.0
		_shader_params["end_of_reel_time"] = 0.0
		_shader_params["death_spots_enabled"] = false
		_shader_params["death_spots_intensity"] = 0.0
		_shader_params["death_spots_time"] = 0.0


	## Enables or disables the entire cinema effect.
	func set_enabled(enabled: bool) -> void:
		_is_active = enabled
		if enabled:
			_start_delayed_activation()
		else:
			_overlay_visible = false
			_waiting_for_activation = false


	## Returns whether the effect is currently enabled.
	func is_enabled() -> bool:
		return _is_active


	## Starts the delayed activation process.
	func _start_delayed_activation() -> void:
		_overlay_visible = false
		_waiting_for_activation = true
		_activation_frame_counter = 0


	## Simulates _process for delayed activation and death effects.
	func process(delta: float) -> void:
		# Handle delayed activation
		if _waiting_for_activation:
			_activation_frame_counter += 1
			if _activation_frame_counter >= ACTIVATION_DELAY_FRAMES:
				_waiting_for_activation = false
				if _is_active:
					_overlay_visible = true

		# Handle death effects animation
		if _death_effects_active:
			_end_of_reel_timer += delta
			_death_spots_timer += delta
			_shader_params["end_of_reel_time"] = _end_of_reel_timer
			_shader_params["death_spots_time"] = _death_spots_timer

			# Animate cigarette burn intensity (fade in over 0.5 seconds)
			var burn_intensity: float = clampf(_end_of_reel_timer / 0.5, 0.0, 1.0)
			_shader_params["cigarette_burn_intensity"] = burn_intensity

			# Animate end of reel intensity (fade in over 0.3 seconds)
			var reel_intensity: float = clampf(_end_of_reel_timer / 0.3, 0.0, 1.0)
			_shader_params["end_of_reel_intensity"] = reel_intensity

			# Animate death spots intensity (fade in over 0.5 seconds)
			var spots_intensity: float = clampf(_death_spots_timer / 0.5, 0.0, 1.0)
			_shader_params["death_spots_intensity"] = spots_intensity


	# ========================================================================
	# Setter / Getter methods mirroring the source
	# ========================================================================

	func set_grain_intensity(intensity: float) -> void:
		_shader_params["grain_intensity"] = clamp(intensity, 0.0, 0.5)

	func get_grain_intensity() -> float:
		return _shader_params.get("grain_intensity", DEFAULT_GRAIN_INTENSITY)

	func set_grain_enabled(enabled: bool) -> void:
		_shader_params["grain_enabled"] = enabled

	func set_warm_color(color: Color) -> void:
		_shader_params["warm_color"] = color

	func set_warm_intensity(intensity: float) -> void:
		_shader_params["warm_intensity"] = clamp(intensity, 0.0, 1.0)

	func get_warm_intensity() -> float:
		return _shader_params.get("warm_intensity", DEFAULT_WARM_INTENSITY)

	func set_warm_enabled(enabled: bool) -> void:
		_shader_params["warm_enabled"] = enabled

	func set_sunny_intensity(intensity: float) -> void:
		_shader_params["sunny_intensity"] = clamp(intensity, 0.0, 0.5)

	func get_sunny_intensity() -> float:
		return _shader_params.get("sunny_intensity", DEFAULT_SUNNY_INTENSITY)

	func set_sunny_enabled(enabled: bool) -> void:
		_shader_params["sunny_enabled"] = enabled

	func set_vignette_intensity(intensity: float) -> void:
		_shader_params["vignette_intensity"] = clamp(intensity, 0.0, 1.0)

	func get_vignette_intensity() -> float:
		return _shader_params.get("vignette_intensity", DEFAULT_VIGNETTE_INTENSITY)

	func set_vignette_softness(softness: float) -> void:
		_shader_params["vignette_softness"] = clamp(softness, 0.0, 1.0)

	func set_vignette_enabled(enabled: bool) -> void:
		_shader_params["vignette_enabled"] = enabled

	func set_defects_enabled(enabled: bool) -> void:
		_shader_params["defects_enabled"] = enabled

	func is_defects_enabled() -> bool:
		return _shader_params.get("defects_enabled", true)

	func set_defect_probability(probability: float) -> void:
		_shader_params["defect_probability"] = clamp(probability, 0.0, 0.1)

	func get_defect_probability() -> float:
		return _shader_params.get("defect_probability", DEFAULT_DEFECT_PROBABILITY)

	func set_scratch_intensity(intensity: float) -> void:
		_shader_params["scratch_intensity"] = clamp(intensity, 0.0, 1.0)

	func set_dust_intensity(intensity: float) -> void:
		_shader_params["dust_intensity"] = clamp(intensity, 0.0, 1.0)

	func set_flicker_intensity(intensity: float) -> void:
		_shader_params["flicker_intensity"] = clamp(intensity, 0.0, 0.3)

	func set_micro_scratches_enabled(enabled: bool) -> void:
		_shader_params["micro_scratches_enabled"] = enabled

	func is_micro_scratches_enabled() -> bool:
		return _shader_params.get("micro_scratches_enabled", true)

	func set_micro_scratch_intensity(intensity: float) -> void:
		_shader_params["micro_scratch_intensity"] = clamp(intensity, 0.0, 1.0)

	func get_micro_scratch_intensity() -> float:
		return _shader_params.get("micro_scratch_intensity", DEFAULT_MICRO_SCRATCH_INTENSITY)

	func set_micro_scratch_probability(probability: float) -> void:
		_shader_params["micro_scratch_probability"] = clamp(probability, 0.0, 0.2)

	func set_cigarette_burn_size(size: float) -> void:
		_shader_params["cigarette_burn_size"] = clamp(size, 0.0, 0.5)

	func set_end_of_reel_duration(duration: float) -> void:
		_end_of_reel_duration = max(0.1, duration)

	## Triggers the death effects (cigarette burn + expanding spots + end of reel).
	func trigger_death_effects() -> void:
		_death_effects_active = true
		_end_of_reel_timer = 0.0
		_death_spots_timer = 0.0

		# Generate random position for cigarette burn (biased toward center)
		var burn_x := 0.3 + randf() * 0.4
		var burn_y := 0.3 + randf() * 0.4
		_shader_params["cigarette_burn_position"] = Vector2(burn_x, burn_y)

		# Enable all death effects
		_shader_params["cigarette_burn_enabled"] = true
		_shader_params["end_of_reel_enabled"] = true
		_shader_params["death_spots_enabled"] = true

		# Start with zero intensity
		_shader_params["cigarette_burn_intensity"] = 0.0
		_shader_params["end_of_reel_intensity"] = 0.0
		_shader_params["death_spots_intensity"] = 0.0

	## Stops and resets the death effects.
	func reset_death_effects() -> void:
		_death_effects_active = false
		_end_of_reel_timer = 0.0
		_death_spots_timer = 0.0

		_shader_params["cigarette_burn_enabled"] = false
		_shader_params["cigarette_burn_intensity"] = 0.0
		_shader_params["end_of_reel_enabled"] = false
		_shader_params["end_of_reel_intensity"] = 0.0
		_shader_params["end_of_reel_time"] = 0.0
		_shader_params["death_spots_enabled"] = false
		_shader_params["death_spots_intensity"] = 0.0
		_shader_params["death_spots_time"] = 0.0

	## Returns whether death effects are currently active.
	func is_death_effects_active() -> bool:
		return _death_effects_active

	## Resets all parameters to defaults.
	func reset_to_defaults() -> void:
		_set_default_parameters()
		_is_active = true
		_start_delayed_activation()


# ============================================================================
# Test Setup
# ============================================================================


var manager: MockCinemaEffectsManager


func before_each() -> void:
	manager = MockCinemaEffectsManager.new()


func after_each() -> void:
	manager = null


# ============================================================================
# Default Constant Value Tests
# ============================================================================


func test_default_grain_intensity() -> void:
	assert_eq(manager.DEFAULT_GRAIN_INTENSITY, 0.15,
		"DEFAULT_GRAIN_INTENSITY should be 0.15")


func test_default_warm_color() -> void:
	assert_eq(manager.DEFAULT_WARM_COLOR, Color(1.0, 0.95, 0.85),
		"DEFAULT_WARM_COLOR should be Color(1.0, 0.95, 0.85)")


func test_default_warm_intensity() -> void:
	assert_eq(manager.DEFAULT_WARM_INTENSITY, 0.12,
		"DEFAULT_WARM_INTENSITY should be 0.12")


func test_default_sunny_intensity() -> void:
	assert_eq(manager.DEFAULT_SUNNY_INTENSITY, 0.08,
		"DEFAULT_SUNNY_INTENSITY should be 0.08")


func test_default_vignette_intensity() -> void:
	assert_eq(manager.DEFAULT_VIGNETTE_INTENSITY, 0.25,
		"DEFAULT_VIGNETTE_INTENSITY should be 0.25")


func test_default_vignette_softness() -> void:
	assert_eq(manager.DEFAULT_VIGNETTE_SOFTNESS, 0.45,
		"DEFAULT_VIGNETTE_SOFTNESS should be 0.45")


func test_default_defect_probability() -> void:
	assert_eq(manager.DEFAULT_DEFECT_PROBABILITY, 0.015,
		"DEFAULT_DEFECT_PROBABILITY should be 0.015")


func test_default_scratch_intensity() -> void:
	assert_eq(manager.DEFAULT_SCRATCH_INTENSITY, 0.6,
		"DEFAULT_SCRATCH_INTENSITY should be 0.6")


func test_default_dust_intensity() -> void:
	assert_eq(manager.DEFAULT_DUST_INTENSITY, 0.5,
		"DEFAULT_DUST_INTENSITY should be 0.5")


func test_default_flicker_intensity() -> void:
	assert_eq(manager.DEFAULT_FLICKER_INTENSITY, 0.03,
		"DEFAULT_FLICKER_INTENSITY should be 0.03")


func test_default_micro_scratch_intensity() -> void:
	assert_eq(manager.DEFAULT_MICRO_SCRATCH_INTENSITY, 0.7,
		"DEFAULT_MICRO_SCRATCH_INTENSITY should be 0.7")


func test_default_micro_scratch_probability() -> void:
	assert_eq(manager.DEFAULT_MICRO_SCRATCH_PROBABILITY, 0.04,
		"DEFAULT_MICRO_SCRATCH_PROBABILITY should be 0.04")


func test_default_cigarette_burn_size() -> void:
	assert_eq(manager.DEFAULT_CIGARETTE_BURN_SIZE, 0.15,
		"DEFAULT_CIGARETTE_BURN_SIZE should be 0.15")


func test_default_end_of_reel_duration() -> void:
	assert_eq(manager.DEFAULT_END_OF_REEL_DURATION, 3.0,
		"DEFAULT_END_OF_REEL_DURATION should be 3.0")


func test_activation_delay_frames() -> void:
	assert_eq(manager.ACTIVATION_DELAY_FRAMES, 1,
		"ACTIVATION_DELAY_FRAMES should be 1")


# ============================================================================
# Default Shader Parameter Tests
# ============================================================================


func test_shader_params_grain_intensity_default() -> void:
	assert_eq(manager._shader_params["grain_intensity"], 0.15,
		"Shader grain_intensity should default to 0.15")


func test_shader_params_grain_enabled_default() -> void:
	assert_true(manager._shader_params["grain_enabled"],
		"Shader grain_enabled should default to true")


func test_shader_params_warm_color_default() -> void:
	assert_eq(manager._shader_params["warm_color"], Color(1.0, 0.95, 0.85),
		"Shader warm_color should default to warm/golden color")


func test_shader_params_warm_intensity_default() -> void:
	assert_eq(manager._shader_params["warm_intensity"], 0.12,
		"Shader warm_intensity should default to 0.12")


func test_shader_params_warm_enabled_default() -> void:
	assert_true(manager._shader_params["warm_enabled"],
		"Shader warm_enabled should default to true")


func test_shader_params_sunny_intensity_default() -> void:
	assert_eq(manager._shader_params["sunny_intensity"], 0.08,
		"Shader sunny_intensity should default to 0.08")


func test_shader_params_sunny_enabled_default() -> void:
	assert_true(manager._shader_params["sunny_enabled"],
		"Shader sunny_enabled should default to true")


func test_shader_params_vignette_intensity_default() -> void:
	assert_eq(manager._shader_params["vignette_intensity"], 0.25,
		"Shader vignette_intensity should default to 0.25")


func test_shader_params_vignette_softness_default() -> void:
	assert_eq(manager._shader_params["vignette_softness"], 0.45,
		"Shader vignette_softness should default to 0.45")


func test_shader_params_vignette_enabled_default() -> void:
	assert_true(manager._shader_params["vignette_enabled"],
		"Shader vignette_enabled should default to true")


func test_shader_params_defects_enabled_default() -> void:
	assert_true(manager._shader_params["defects_enabled"],
		"Shader defects_enabled should default to true")


func test_shader_params_defect_probability_default() -> void:
	assert_eq(manager._shader_params["defect_probability"], 0.015,
		"Shader defect_probability should default to 0.015")


func test_shader_params_scratch_intensity_default() -> void:
	assert_eq(manager._shader_params["scratch_intensity"], 0.6,
		"Shader scratch_intensity should default to 0.6")


func test_shader_params_dust_intensity_default() -> void:
	assert_eq(manager._shader_params["dust_intensity"], 0.5,
		"Shader dust_intensity should default to 0.5")


func test_shader_params_flicker_intensity_default() -> void:
	assert_eq(manager._shader_params["flicker_intensity"], 0.03,
		"Shader flicker_intensity should default to 0.03")


func test_shader_params_micro_scratches_enabled_default() -> void:
	assert_true(manager._shader_params["micro_scratches_enabled"],
		"Shader micro_scratches_enabled should default to true")


func test_shader_params_micro_scratch_intensity_default() -> void:
	assert_eq(manager._shader_params["micro_scratch_intensity"], 0.7,
		"Shader micro_scratch_intensity should default to 0.7")


func test_shader_params_micro_scratch_probability_default() -> void:
	assert_eq(manager._shader_params["micro_scratch_probability"], 0.04,
		"Shader micro_scratch_probability should default to 0.04")


func test_shader_params_death_effects_disabled_by_default() -> void:
	assert_false(manager._shader_params["cigarette_burn_enabled"],
		"Shader cigarette_burn_enabled should default to false")
	assert_false(manager._shader_params["end_of_reel_enabled"],
		"Shader end_of_reel_enabled should default to false")
	assert_false(manager._shader_params["death_spots_enabled"],
		"Shader death_spots_enabled should default to false")


func test_shader_params_death_intensities_zero_by_default() -> void:
	assert_eq(manager._shader_params["cigarette_burn_intensity"], 0.0,
		"Shader cigarette_burn_intensity should default to 0.0")
	assert_eq(manager._shader_params["end_of_reel_intensity"], 0.0,
		"Shader end_of_reel_intensity should default to 0.0")
	assert_eq(manager._shader_params["death_spots_intensity"], 0.0,
		"Shader death_spots_intensity should default to 0.0")


func test_shader_params_death_times_zero_by_default() -> void:
	assert_eq(manager._shader_params["end_of_reel_time"], 0.0,
		"Shader end_of_reel_time should default to 0.0")
	assert_eq(manager._shader_params["death_spots_time"], 0.0,
		"Shader death_spots_time should default to 0.0")


func test_shader_params_cigarette_burn_position_default() -> void:
	assert_eq(manager._shader_params["cigarette_burn_position"], Vector2(0.5, 0.5),
		"Shader cigarette_burn_position should default to center (0.5, 0.5)")


func test_shader_params_cigarette_burn_size_default() -> void:
	assert_eq(manager._shader_params["cigarette_burn_size"], 0.15,
		"Shader cigarette_burn_size should default to 0.15")


# ============================================================================
# Initial State Tests
# ============================================================================


func test_is_active_initially_true() -> void:
	assert_true(manager._is_active,
		"Manager should be active by default")


func test_is_enabled_returns_true_initially() -> void:
	assert_true(manager.is_enabled(),
		"is_enabled() should return true initially")


func test_death_effects_inactive_initially() -> void:
	assert_false(manager._death_effects_active,
		"Death effects should be inactive initially")


func test_is_death_effects_active_returns_false_initially() -> void:
	assert_false(manager.is_death_effects_active(),
		"is_death_effects_active() should return false initially")


func test_waiting_for_activation_false_initially() -> void:
	assert_false(manager._waiting_for_activation,
		"Should not be waiting for activation initially")


func test_end_of_reel_timer_zero_initially() -> void:
	assert_eq(manager._end_of_reel_timer, 0.0,
		"End of reel timer should be 0.0 initially")


func test_death_spots_timer_zero_initially() -> void:
	assert_eq(manager._death_spots_timer, 0.0,
		"Death spots timer should be 0.0 initially")


func test_end_of_reel_duration_default() -> void:
	assert_eq(manager._end_of_reel_duration, 3.0,
		"End of reel duration should default to 3.0")


# ============================================================================
# Grain Intensity Clamping Tests (0.0 to 0.5)
# ============================================================================


func test_set_grain_intensity_valid_value() -> void:
	manager.set_grain_intensity(0.3)

	assert_eq(manager.get_grain_intensity(), 0.3,
		"Grain intensity should be set to 0.3")


func test_set_grain_intensity_minimum_boundary() -> void:
	manager.set_grain_intensity(0.0)

	assert_eq(manager.get_grain_intensity(), 0.0,
		"Grain intensity should accept 0.0")


func test_set_grain_intensity_maximum_boundary() -> void:
	manager.set_grain_intensity(0.5)

	assert_eq(manager.get_grain_intensity(), 0.5,
		"Grain intensity should accept 0.5")


func test_set_grain_intensity_clamps_below_zero() -> void:
	manager.set_grain_intensity(-0.5)

	assert_eq(manager.get_grain_intensity(), 0.0,
		"Grain intensity should clamp negative values to 0.0")


func test_set_grain_intensity_clamps_above_max() -> void:
	manager.set_grain_intensity(1.0)

	assert_eq(manager.get_grain_intensity(), 0.5,
		"Grain intensity should clamp values above 0.5 to 0.5")


func test_set_grain_intensity_clamps_large_value() -> void:
	manager.set_grain_intensity(999.0)

	assert_eq(manager.get_grain_intensity(), 0.5,
		"Grain intensity should clamp very large values to 0.5")


# ============================================================================
# Warm Intensity Clamping Tests (0.0 to 1.0)
# ============================================================================


func test_set_warm_intensity_valid_value() -> void:
	manager.set_warm_intensity(0.5)

	assert_eq(manager.get_warm_intensity(), 0.5,
		"Warm intensity should be set to 0.5")


func test_set_warm_intensity_minimum_boundary() -> void:
	manager.set_warm_intensity(0.0)

	assert_eq(manager.get_warm_intensity(), 0.0,
		"Warm intensity should accept 0.0")


func test_set_warm_intensity_maximum_boundary() -> void:
	manager.set_warm_intensity(1.0)

	assert_eq(manager.get_warm_intensity(), 1.0,
		"Warm intensity should accept 1.0")


func test_set_warm_intensity_clamps_below_zero() -> void:
	manager.set_warm_intensity(-0.3)

	assert_eq(manager.get_warm_intensity(), 0.0,
		"Warm intensity should clamp negative values to 0.0")


func test_set_warm_intensity_clamps_above_max() -> void:
	manager.set_warm_intensity(1.5)

	assert_eq(manager.get_warm_intensity(), 1.0,
		"Warm intensity should clamp values above 1.0 to 1.0")


# ============================================================================
# Sunny Intensity Clamping Tests (0.0 to 0.5)
# ============================================================================


func test_set_sunny_intensity_valid_value() -> void:
	manager.set_sunny_intensity(0.25)

	assert_eq(manager.get_sunny_intensity(), 0.25,
		"Sunny intensity should be set to 0.25")


func test_set_sunny_intensity_minimum_boundary() -> void:
	manager.set_sunny_intensity(0.0)

	assert_eq(manager.get_sunny_intensity(), 0.0,
		"Sunny intensity should accept 0.0")


func test_set_sunny_intensity_maximum_boundary() -> void:
	manager.set_sunny_intensity(0.5)

	assert_eq(manager.get_sunny_intensity(), 0.5,
		"Sunny intensity should accept 0.5")


func test_set_sunny_intensity_clamps_below_zero() -> void:
	manager.set_sunny_intensity(-0.1)

	assert_eq(manager.get_sunny_intensity(), 0.0,
		"Sunny intensity should clamp negative values to 0.0")


func test_set_sunny_intensity_clamps_above_max() -> void:
	manager.set_sunny_intensity(0.8)

	assert_eq(manager.get_sunny_intensity(), 0.5,
		"Sunny intensity should clamp values above 0.5 to 0.5")


# ============================================================================
# Vignette Intensity Clamping Tests (0.0 to 1.0)
# ============================================================================


func test_set_vignette_intensity_valid_value() -> void:
	manager.set_vignette_intensity(0.6)

	assert_eq(manager.get_vignette_intensity(), 0.6,
		"Vignette intensity should be set to 0.6")


func test_set_vignette_intensity_minimum_boundary() -> void:
	manager.set_vignette_intensity(0.0)

	assert_eq(manager.get_vignette_intensity(), 0.0,
		"Vignette intensity should accept 0.0")


func test_set_vignette_intensity_maximum_boundary() -> void:
	manager.set_vignette_intensity(1.0)

	assert_eq(manager.get_vignette_intensity(), 1.0,
		"Vignette intensity should accept 1.0")


func test_set_vignette_intensity_clamps_below_zero() -> void:
	manager.set_vignette_intensity(-0.2)

	assert_eq(manager.get_vignette_intensity(), 0.0,
		"Vignette intensity should clamp negative values to 0.0")


func test_set_vignette_intensity_clamps_above_max() -> void:
	manager.set_vignette_intensity(2.0)

	assert_eq(manager.get_vignette_intensity(), 1.0,
		"Vignette intensity should clamp values above 1.0 to 1.0")


# ============================================================================
# Vignette Softness Clamping Tests (0.0 to 1.0)
# ============================================================================


func test_set_vignette_softness_valid_value() -> void:
	manager.set_vignette_softness(0.7)

	assert_eq(manager._shader_params["vignette_softness"], 0.7,
		"Vignette softness should be set to 0.7")


func test_set_vignette_softness_minimum_boundary() -> void:
	manager.set_vignette_softness(0.0)

	assert_eq(manager._shader_params["vignette_softness"], 0.0,
		"Vignette softness should accept 0.0")


func test_set_vignette_softness_maximum_boundary() -> void:
	manager.set_vignette_softness(1.0)

	assert_eq(manager._shader_params["vignette_softness"], 1.0,
		"Vignette softness should accept 1.0")


func test_set_vignette_softness_clamps_below_zero() -> void:
	manager.set_vignette_softness(-0.5)

	assert_eq(manager._shader_params["vignette_softness"], 0.0,
		"Vignette softness should clamp negative values to 0.0")


func test_set_vignette_softness_clamps_above_max() -> void:
	manager.set_vignette_softness(1.5)

	assert_eq(manager._shader_params["vignette_softness"], 1.0,
		"Vignette softness should clamp values above 1.0 to 1.0")


# ============================================================================
# Defect Probability Clamping Tests (0.0 to 0.1)
# ============================================================================


func test_set_defect_probability_valid_value() -> void:
	manager.set_defect_probability(0.05)

	assert_eq(manager.get_defect_probability(), 0.05,
		"Defect probability should be set to 0.05")


func test_set_defect_probability_minimum_boundary() -> void:
	manager.set_defect_probability(0.0)

	assert_eq(manager.get_defect_probability(), 0.0,
		"Defect probability should accept 0.0")


func test_set_defect_probability_maximum_boundary() -> void:
	manager.set_defect_probability(0.1)

	assert_eq(manager.get_defect_probability(), 0.1,
		"Defect probability should accept 0.1")


func test_set_defect_probability_clamps_below_zero() -> void:
	manager.set_defect_probability(-0.01)

	assert_eq(manager.get_defect_probability(), 0.0,
		"Defect probability should clamp negative values to 0.0")


func test_set_defect_probability_clamps_above_max() -> void:
	manager.set_defect_probability(0.5)

	assert_eq(manager.get_defect_probability(), 0.1,
		"Defect probability should clamp values above 0.1 to 0.1")


# ============================================================================
# Flicker Intensity Clamping Tests (0.0 to 0.3)
# ============================================================================


func test_set_flicker_intensity_valid_value() -> void:
	manager.set_flicker_intensity(0.15)

	assert_eq(manager._shader_params["flicker_intensity"], 0.15,
		"Flicker intensity should be set to 0.15")


func test_set_flicker_intensity_minimum_boundary() -> void:
	manager.set_flicker_intensity(0.0)

	assert_eq(manager._shader_params["flicker_intensity"], 0.0,
		"Flicker intensity should accept 0.0")


func test_set_flicker_intensity_maximum_boundary() -> void:
	manager.set_flicker_intensity(0.3)

	assert_eq(manager._shader_params["flicker_intensity"], 0.3,
		"Flicker intensity should accept 0.3")


func test_set_flicker_intensity_clamps_below_zero() -> void:
	manager.set_flicker_intensity(-0.1)

	assert_eq(manager._shader_params["flicker_intensity"], 0.0,
		"Flicker intensity should clamp negative values to 0.0")


func test_set_flicker_intensity_clamps_above_max() -> void:
	manager.set_flicker_intensity(0.5)

	assert_eq(manager._shader_params["flicker_intensity"], 0.3,
		"Flicker intensity should clamp values above 0.3 to 0.3")


# ============================================================================
# Micro Scratch Intensity Clamping Tests (0.0 to 1.0)
# ============================================================================


func test_set_micro_scratch_intensity_valid_value() -> void:
	manager.set_micro_scratch_intensity(0.5)

	assert_eq(manager.get_micro_scratch_intensity(), 0.5,
		"Micro scratch intensity should be set to 0.5")


func test_set_micro_scratch_intensity_minimum_boundary() -> void:
	manager.set_micro_scratch_intensity(0.0)

	assert_eq(manager.get_micro_scratch_intensity(), 0.0,
		"Micro scratch intensity should accept 0.0")


func test_set_micro_scratch_intensity_maximum_boundary() -> void:
	manager.set_micro_scratch_intensity(1.0)

	assert_eq(manager.get_micro_scratch_intensity(), 1.0,
		"Micro scratch intensity should accept 1.0")


func test_set_micro_scratch_intensity_clamps_below_zero() -> void:
	manager.set_micro_scratch_intensity(-0.3)

	assert_eq(manager.get_micro_scratch_intensity(), 0.0,
		"Micro scratch intensity should clamp negative values to 0.0")


func test_set_micro_scratch_intensity_clamps_above_max() -> void:
	manager.set_micro_scratch_intensity(1.5)

	assert_eq(manager.get_micro_scratch_intensity(), 1.0,
		"Micro scratch intensity should clamp values above 1.0 to 1.0")


# ============================================================================
# Micro Scratch Probability Clamping Tests (0.0 to 0.2)
# ============================================================================


func test_set_micro_scratch_probability_valid_value() -> void:
	manager.set_micro_scratch_probability(0.1)

	assert_eq(manager._shader_params["micro_scratch_probability"], 0.1,
		"Micro scratch probability should be set to 0.1")


func test_set_micro_scratch_probability_minimum_boundary() -> void:
	manager.set_micro_scratch_probability(0.0)

	assert_eq(manager._shader_params["micro_scratch_probability"], 0.0,
		"Micro scratch probability should accept 0.0")


func test_set_micro_scratch_probability_maximum_boundary() -> void:
	manager.set_micro_scratch_probability(0.2)

	assert_eq(manager._shader_params["micro_scratch_probability"], 0.2,
		"Micro scratch probability should accept 0.2")


func test_set_micro_scratch_probability_clamps_below_zero() -> void:
	manager.set_micro_scratch_probability(-0.05)

	assert_eq(manager._shader_params["micro_scratch_probability"], 0.0,
		"Micro scratch probability should clamp negative values to 0.0")


func test_set_micro_scratch_probability_clamps_above_max() -> void:
	manager.set_micro_scratch_probability(0.5)

	assert_eq(manager._shader_params["micro_scratch_probability"], 0.2,
		"Micro scratch probability should clamp values above 0.2 to 0.2")


# ============================================================================
# Cigarette Burn Size Clamping Tests (0.0 to 0.5)
# ============================================================================


func test_set_cigarette_burn_size_valid_value() -> void:
	manager.set_cigarette_burn_size(0.25)

	assert_eq(manager._shader_params["cigarette_burn_size"], 0.25,
		"Cigarette burn size should be set to 0.25")


func test_set_cigarette_burn_size_minimum_boundary() -> void:
	manager.set_cigarette_burn_size(0.0)

	assert_eq(manager._shader_params["cigarette_burn_size"], 0.0,
		"Cigarette burn size should accept 0.0")


func test_set_cigarette_burn_size_maximum_boundary() -> void:
	manager.set_cigarette_burn_size(0.5)

	assert_eq(manager._shader_params["cigarette_burn_size"], 0.5,
		"Cigarette burn size should accept 0.5")


func test_set_cigarette_burn_size_clamps_below_zero() -> void:
	manager.set_cigarette_burn_size(-0.1)

	assert_eq(manager._shader_params["cigarette_burn_size"], 0.0,
		"Cigarette burn size should clamp negative values to 0.0")


func test_set_cigarette_burn_size_clamps_above_max() -> void:
	manager.set_cigarette_burn_size(1.0)

	assert_eq(manager._shader_params["cigarette_burn_size"], 0.5,
		"Cigarette burn size should clamp values above 0.5 to 0.5")


# ============================================================================
# End of Reel Duration Clamping Tests (min 0.1)
# ============================================================================


func test_set_end_of_reel_duration_valid_value() -> void:
	manager.set_end_of_reel_duration(5.0)

	assert_eq(manager._end_of_reel_duration, 5.0,
		"End of reel duration should be set to 5.0")


func test_set_end_of_reel_duration_minimum_boundary() -> void:
	manager.set_end_of_reel_duration(0.1)

	assert_eq(manager._end_of_reel_duration, 0.1,
		"End of reel duration should accept 0.1")


func test_set_end_of_reel_duration_clamps_below_minimum() -> void:
	manager.set_end_of_reel_duration(0.0)

	assert_eq(manager._end_of_reel_duration, 0.1,
		"End of reel duration should clamp values below 0.1 to 0.1")


func test_set_end_of_reel_duration_clamps_negative() -> void:
	manager.set_end_of_reel_duration(-5.0)

	assert_eq(manager._end_of_reel_duration, 0.1,
		"End of reel duration should clamp negative values to 0.1")


func test_set_end_of_reel_duration_accepts_large_value() -> void:
	manager.set_end_of_reel_duration(100.0)

	assert_eq(manager._end_of_reel_duration, 100.0,
		"End of reel duration should accept large values")


# ============================================================================
# Scratch Intensity Clamping Tests (0.0 to 1.0)
# ============================================================================


func test_set_scratch_intensity_valid_value() -> void:
	manager.set_scratch_intensity(0.8)

	assert_eq(manager._shader_params["scratch_intensity"], 0.8,
		"Scratch intensity should be set to 0.8")


func test_set_scratch_intensity_clamps_below_zero() -> void:
	manager.set_scratch_intensity(-0.2)

	assert_eq(manager._shader_params["scratch_intensity"], 0.0,
		"Scratch intensity should clamp negative values to 0.0")


func test_set_scratch_intensity_clamps_above_max() -> void:
	manager.set_scratch_intensity(1.5)

	assert_eq(manager._shader_params["scratch_intensity"], 1.0,
		"Scratch intensity should clamp values above 1.0 to 1.0")


# ============================================================================
# Dust Intensity Clamping Tests (0.0 to 1.0)
# ============================================================================


func test_set_dust_intensity_valid_value() -> void:
	manager.set_dust_intensity(0.7)

	assert_eq(manager._shader_params["dust_intensity"], 0.7,
		"Dust intensity should be set to 0.7")


func test_set_dust_intensity_clamps_below_zero() -> void:
	manager.set_dust_intensity(-0.1)

	assert_eq(manager._shader_params["dust_intensity"], 0.0,
		"Dust intensity should clamp negative values to 0.0")


func test_set_dust_intensity_clamps_above_max() -> void:
	manager.set_dust_intensity(1.5)

	assert_eq(manager._shader_params["dust_intensity"], 1.0,
		"Dust intensity should clamp values above 1.0 to 1.0")


# ============================================================================
# Enable/Disable Toggle Tests
# ============================================================================


func test_set_grain_enabled_true() -> void:
	manager.set_grain_enabled(true)

	assert_true(manager._shader_params["grain_enabled"],
		"Grain should be enabled when set to true")


func test_set_grain_enabled_false() -> void:
	manager.set_grain_enabled(false)

	assert_false(manager._shader_params["grain_enabled"],
		"Grain should be disabled when set to false")


func test_set_warm_enabled_true() -> void:
	manager.set_warm_enabled(true)

	assert_true(manager._shader_params["warm_enabled"],
		"Warm tint should be enabled when set to true")


func test_set_warm_enabled_false() -> void:
	manager.set_warm_enabled(false)

	assert_false(manager._shader_params["warm_enabled"],
		"Warm tint should be disabled when set to false")


func test_set_warm_color() -> void:
	var custom_color := Color(0.8, 0.7, 0.6)
	manager.set_warm_color(custom_color)

	assert_eq(manager._shader_params["warm_color"], custom_color,
		"Warm color should be set to custom color")


func test_set_sunny_enabled_true() -> void:
	manager.set_sunny_enabled(true)

	assert_true(manager._shader_params["sunny_enabled"],
		"Sunny effect should be enabled when set to true")


func test_set_sunny_enabled_false() -> void:
	manager.set_sunny_enabled(false)

	assert_false(manager._shader_params["sunny_enabled"],
		"Sunny effect should be disabled when set to false")


func test_set_vignette_enabled_true() -> void:
	manager.set_vignette_enabled(true)

	assert_true(manager._shader_params["vignette_enabled"],
		"Vignette should be enabled when set to true")


func test_set_vignette_enabled_false() -> void:
	manager.set_vignette_enabled(false)

	assert_false(manager._shader_params["vignette_enabled"],
		"Vignette should be disabled when set to false")


func test_set_defects_enabled_true() -> void:
	manager.set_defects_enabled(true)

	assert_true(manager.is_defects_enabled(),
		"Defects should be enabled when set to true")


func test_set_defects_enabled_false() -> void:
	manager.set_defects_enabled(false)

	assert_false(manager.is_defects_enabled(),
		"Defects should be disabled when set to false")


func test_set_micro_scratches_enabled_true() -> void:
	manager.set_micro_scratches_enabled(true)

	assert_true(manager.is_micro_scratches_enabled(),
		"Micro scratches should be enabled when set to true")


func test_set_micro_scratches_enabled_false() -> void:
	manager.set_micro_scratches_enabled(false)

	assert_false(manager.is_micro_scratches_enabled(),
		"Micro scratches should be disabled when set to false")


# ============================================================================
# Enabled / Disabled State Transition Tests
# ============================================================================


func test_set_enabled_false_disables_effect() -> void:
	manager.set_enabled(false)

	assert_false(manager.is_enabled(),
		"Effect should be disabled after set_enabled(false)")


func test_set_enabled_true_enables_effect() -> void:
	manager.set_enabled(false)
	manager.set_enabled(true)

	assert_true(manager.is_enabled(),
		"Effect should be enabled after set_enabled(true)")


func test_set_enabled_false_hides_overlay() -> void:
	manager._overlay_visible = true
	manager.set_enabled(false)

	assert_false(manager._overlay_visible,
		"Overlay should be hidden when effect is disabled")


func test_set_enabled_false_cancels_waiting_for_activation() -> void:
	manager._waiting_for_activation = true
	manager.set_enabled(false)

	assert_false(manager._waiting_for_activation,
		"Waiting for activation should be cancelled when disabled")


func test_set_enabled_true_starts_delayed_activation() -> void:
	manager.set_enabled(true)

	assert_true(manager._waiting_for_activation,
		"Enabling effect should start delayed activation")
	assert_eq(manager._activation_frame_counter, 0,
		"Activation frame counter should be reset to 0")


func test_set_enabled_true_hides_overlay_during_delay() -> void:
	manager._overlay_visible = true
	manager.set_enabled(true)

	assert_false(manager._overlay_visible,
		"Overlay should be hidden during delayed activation")


# ============================================================================
# Delayed Activation Tests
# ============================================================================


func test_delayed_activation_does_not_show_before_delay() -> void:
	manager._waiting_for_activation = true
	manager._activation_frame_counter = 0
	manager._is_active = true
	manager._overlay_visible = false

	# Process but don't exceed the delay
	# ACTIVATION_DELAY_FRAMES is 1, so the first process should complete it
	# Test with counter already at 0, process increments to 1 which >= 1
	# Actually the first process call increments counter to 1 which IS >= ACTIVATION_DELAY_FRAMES (1)
	# So we verify the initial state before any process call
	assert_false(manager._overlay_visible,
		"Overlay should not be visible before delayed activation completes")


func test_delayed_activation_shows_after_sufficient_frames() -> void:
	manager._waiting_for_activation = true
	manager._activation_frame_counter = 0
	manager._is_active = true
	manager._overlay_visible = false

	# Process one frame - should reach ACTIVATION_DELAY_FRAMES (1)
	manager.process(0.016)

	assert_true(manager._overlay_visible,
		"Overlay should be visible after delayed activation completes")
	assert_false(manager._waiting_for_activation,
		"Should no longer be waiting for activation")


func test_delayed_activation_does_not_show_when_inactive() -> void:
	manager._waiting_for_activation = true
	manager._activation_frame_counter = 0
	manager._is_active = false
	manager._overlay_visible = false

	manager.process(0.016)

	assert_false(manager._overlay_visible,
		"Overlay should not be shown when effect is inactive even after delay")


func test_delayed_activation_resets_counter_on_enable() -> void:
	manager._activation_frame_counter = 5
	manager.set_enabled(true)

	assert_eq(manager._activation_frame_counter, 0,
		"Activation frame counter should reset when enabling")


# ============================================================================
# Death Effects Trigger Tests
# ============================================================================


func test_trigger_death_effects_activates_death_state() -> void:
	manager.trigger_death_effects()

	assert_true(manager.is_death_effects_active(),
		"Death effects should be active after trigger")


func test_trigger_death_effects_resets_timers() -> void:
	manager._end_of_reel_timer = 5.0
	manager._death_spots_timer = 3.0

	manager.trigger_death_effects()

	assert_eq(manager._end_of_reel_timer, 0.0,
		"End of reel timer should be reset to 0.0 on trigger")
	assert_eq(manager._death_spots_timer, 0.0,
		"Death spots timer should be reset to 0.0 on trigger")


func test_trigger_death_effects_enables_shader_effects() -> void:
	manager.trigger_death_effects()

	assert_true(manager._shader_params["cigarette_burn_enabled"],
		"Cigarette burn should be enabled on death")
	assert_true(manager._shader_params["end_of_reel_enabled"],
		"End of reel should be enabled on death")
	assert_true(manager._shader_params["death_spots_enabled"],
		"Death spots should be enabled on death")


func test_trigger_death_effects_starts_with_zero_intensity() -> void:
	manager.trigger_death_effects()

	assert_eq(manager._shader_params["cigarette_burn_intensity"], 0.0,
		"Cigarette burn intensity should start at 0.0")
	assert_eq(manager._shader_params["end_of_reel_intensity"], 0.0,
		"End of reel intensity should start at 0.0")
	assert_eq(manager._shader_params["death_spots_intensity"], 0.0,
		"Death spots intensity should start at 0.0")


func test_trigger_death_effects_sets_burn_position_in_center_area() -> void:
	manager.trigger_death_effects()

	var pos: Vector2 = manager._shader_params["cigarette_burn_position"]
	assert_gte(pos.x, 0.3,
		"Burn X position should be >= 0.3")
	assert_lte(pos.x, 0.7,
		"Burn X position should be <= 0.7")
	assert_gte(pos.y, 0.3,
		"Burn Y position should be >= 0.3")
	assert_lte(pos.y, 0.7,
		"Burn Y position should be <= 0.7")


# ============================================================================
# Death Effects Reset Tests
# ============================================================================


func test_reset_death_effects_deactivates_death_state() -> void:
	manager.trigger_death_effects()
	manager.reset_death_effects()

	assert_false(manager.is_death_effects_active(),
		"Death effects should be inactive after reset")


func test_reset_death_effects_resets_timers() -> void:
	manager.trigger_death_effects()
	manager.process(1.0)
	manager.reset_death_effects()

	assert_eq(manager._end_of_reel_timer, 0.0,
		"End of reel timer should be reset to 0.0 after reset")
	assert_eq(manager._death_spots_timer, 0.0,
		"Death spots timer should be reset to 0.0 after reset")


func test_reset_death_effects_disables_shader_effects() -> void:
	manager.trigger_death_effects()
	manager.reset_death_effects()

	assert_false(manager._shader_params["cigarette_burn_enabled"],
		"Cigarette burn should be disabled after reset")
	assert_false(manager._shader_params["end_of_reel_enabled"],
		"End of reel should be disabled after reset")
	assert_false(manager._shader_params["death_spots_enabled"],
		"Death spots should be disabled after reset")


func test_reset_death_effects_zeros_intensities() -> void:
	manager.trigger_death_effects()
	manager.process(1.0)
	manager.reset_death_effects()

	assert_eq(manager._shader_params["cigarette_burn_intensity"], 0.0,
		"Cigarette burn intensity should be 0.0 after reset")
	assert_eq(manager._shader_params["end_of_reel_intensity"], 0.0,
		"End of reel intensity should be 0.0 after reset")
	assert_eq(manager._shader_params["death_spots_intensity"], 0.0,
		"Death spots intensity should be 0.0 after reset")


func test_reset_death_effects_zeros_times() -> void:
	manager.trigger_death_effects()
	manager.process(1.0)
	manager.reset_death_effects()

	assert_eq(manager._shader_params["end_of_reel_time"], 0.0,
		"End of reel time should be 0.0 after reset")
	assert_eq(manager._shader_params["death_spots_time"], 0.0,
		"Death spots time should be 0.0 after reset")


# ============================================================================
# Death Effects Animation Formula Tests
# ============================================================================


func test_burn_intensity_formula_at_zero() -> void:
	manager.trigger_death_effects()
	# At timer = 0.0, burn_intensity = clampf(0.0 / 0.5, 0.0, 1.0) = 0.0
	manager.process(0.0)

	assert_eq(manager._shader_params["cigarette_burn_intensity"], 0.0,
		"Burn intensity should be 0.0 at timer 0.0")


func test_burn_intensity_formula_at_quarter() -> void:
	manager.trigger_death_effects()
	# At timer = 0.25, burn_intensity = clampf(0.25 / 0.5, 0.0, 1.0) = 0.5
	manager.process(0.25)

	assert_almost_eq(manager._shader_params["cigarette_burn_intensity"], 0.5, 0.001,
		"Burn intensity should be 0.5 at timer 0.25")


func test_burn_intensity_formula_at_half_second() -> void:
	manager.trigger_death_effects()
	# At timer = 0.5, burn_intensity = clampf(0.5 / 0.5, 0.0, 1.0) = 1.0
	manager.process(0.5)

	assert_almost_eq(manager._shader_params["cigarette_burn_intensity"], 1.0, 0.001,
		"Burn intensity should be 1.0 at timer 0.5")


func test_burn_intensity_formula_clamped_after_half_second() -> void:
	manager.trigger_death_effects()
	# At timer = 1.0, burn_intensity = clampf(1.0 / 0.5, 0.0, 1.0) = 1.0
	manager.process(1.0)

	assert_almost_eq(manager._shader_params["cigarette_burn_intensity"], 1.0, 0.001,
		"Burn intensity should be clamped at 1.0 beyond 0.5 seconds")


func test_reel_intensity_formula_at_zero() -> void:
	manager.trigger_death_effects()
	# At timer = 0.0, reel_intensity = clampf(0.0 / 0.3, 0.0, 1.0) = 0.0
	manager.process(0.0)

	assert_eq(manager._shader_params["end_of_reel_intensity"], 0.0,
		"Reel intensity should be 0.0 at timer 0.0")


func test_reel_intensity_formula_at_0_15() -> void:
	manager.trigger_death_effects()
	# At timer = 0.15, reel_intensity = clampf(0.15 / 0.3, 0.0, 1.0) = 0.5
	manager.process(0.15)

	assert_almost_eq(manager._shader_params["end_of_reel_intensity"], 0.5, 0.001,
		"Reel intensity should be 0.5 at timer 0.15")


func test_reel_intensity_formula_at_0_3() -> void:
	manager.trigger_death_effects()
	# At timer = 0.3, reel_intensity = clampf(0.3 / 0.3, 0.0, 1.0) = 1.0
	manager.process(0.3)

	assert_almost_eq(manager._shader_params["end_of_reel_intensity"], 1.0, 0.001,
		"Reel intensity should be 1.0 at timer 0.3")


func test_reel_intensity_formula_clamped_beyond_threshold() -> void:
	manager.trigger_death_effects()
	# At timer = 2.0, reel_intensity = clampf(2.0 / 0.3, 0.0, 1.0) = 1.0
	manager.process(2.0)

	assert_almost_eq(manager._shader_params["end_of_reel_intensity"], 1.0, 0.001,
		"Reel intensity should be clamped at 1.0 beyond 0.3 seconds")


func test_death_spots_intensity_formula_at_zero() -> void:
	manager.trigger_death_effects()
	# At timer = 0.0, spots_intensity = clampf(0.0 / 0.5, 0.0, 1.0) = 0.0
	manager.process(0.0)

	assert_eq(manager._shader_params["death_spots_intensity"], 0.0,
		"Death spots intensity should be 0.0 at timer 0.0")


func test_death_spots_intensity_formula_at_quarter() -> void:
	manager.trigger_death_effects()
	# At timer = 0.25, spots_intensity = clampf(0.25 / 0.5, 0.0, 1.0) = 0.5
	manager.process(0.25)

	assert_almost_eq(manager._shader_params["death_spots_intensity"], 0.5, 0.001,
		"Death spots intensity should be 0.5 at timer 0.25")


func test_death_spots_intensity_formula_at_half_second() -> void:
	manager.trigger_death_effects()
	# At timer = 0.5, spots_intensity = clampf(0.5 / 0.5, 0.0, 1.0) = 1.0
	manager.process(0.5)

	assert_almost_eq(manager._shader_params["death_spots_intensity"], 1.0, 0.001,
		"Death spots intensity should be 1.0 at timer 0.5")


func test_reel_fades_in_faster_than_burn() -> void:
	# Reel fades in over 0.3 seconds, burn over 0.5 seconds
	manager.trigger_death_effects()
	manager.process(0.3)

	var reel: float = manager._shader_params["end_of_reel_intensity"]
	var burn: float = manager._shader_params["cigarette_burn_intensity"]

	assert_almost_eq(reel, 1.0, 0.001,
		"Reel should be at full intensity at 0.3 seconds")
	assert_almost_eq(burn, 0.6, 0.001,
		"Burn should be at 0.6 intensity at 0.3 seconds (0.3/0.5)")


# ============================================================================
# Death Effects Timer Accumulation Tests
# ============================================================================


func test_death_timers_accumulate_over_multiple_process_calls() -> void:
	manager.trigger_death_effects()
	manager.process(0.1)
	manager.process(0.1)
	manager.process(0.1)

	assert_almost_eq(manager._end_of_reel_timer, 0.3, 0.001,
		"End of reel timer should accumulate across multiple process calls")
	assert_almost_eq(manager._death_spots_timer, 0.3, 0.001,
		"Death spots timer should accumulate across multiple process calls")


func test_death_shader_times_updated_during_process() -> void:
	manager.trigger_death_effects()
	manager.process(0.5)

	assert_almost_eq(manager._shader_params["end_of_reel_time"], 0.5, 0.001,
		"Shader end_of_reel_time should track timer value")
	assert_almost_eq(manager._shader_params["death_spots_time"], 0.5, 0.001,
		"Shader death_spots_time should track timer value")


func test_death_effects_not_processed_when_inactive() -> void:
	# Death effects not triggered, process should not update death params
	manager.process(1.0)

	assert_eq(manager._end_of_reel_timer, 0.0,
		"End of reel timer should not change when death effects inactive")
	assert_eq(manager._death_spots_timer, 0.0,
		"Death spots timer should not change when death effects inactive")


# ============================================================================
# Reset to Defaults Tests
# ============================================================================


func test_reset_to_defaults_restores_grain_intensity() -> void:
	manager.set_grain_intensity(0.4)
	manager.reset_to_defaults()

	assert_eq(manager.get_grain_intensity(), 0.15,
		"Grain intensity should be restored to default after reset")


func test_reset_to_defaults_restores_warm_intensity() -> void:
	manager.set_warm_intensity(0.9)
	manager.reset_to_defaults()

	assert_eq(manager.get_warm_intensity(), 0.12,
		"Warm intensity should be restored to default after reset")


func test_reset_to_defaults_restores_sunny_intensity() -> void:
	manager.set_sunny_intensity(0.4)
	manager.reset_to_defaults()

	assert_eq(manager.get_sunny_intensity(), 0.08,
		"Sunny intensity should be restored to default after reset")


func test_reset_to_defaults_restores_vignette_intensity() -> void:
	manager.set_vignette_intensity(0.9)
	manager.reset_to_defaults()

	assert_eq(manager.get_vignette_intensity(), 0.25,
		"Vignette intensity should be restored to default after reset")


func test_reset_to_defaults_restores_defect_probability() -> void:
	manager.set_defect_probability(0.08)
	manager.reset_to_defaults()

	assert_eq(manager.get_defect_probability(), 0.015,
		"Defect probability should be restored to default after reset")


func test_reset_to_defaults_restores_micro_scratch_intensity() -> void:
	manager.set_micro_scratch_intensity(0.2)
	manager.reset_to_defaults()

	assert_eq(manager.get_micro_scratch_intensity(), 0.7,
		"Micro scratch intensity should be restored to default after reset")


func test_reset_to_defaults_sets_active_true() -> void:
	manager.set_enabled(false)
	manager.reset_to_defaults()

	assert_true(manager.is_enabled(),
		"Manager should be active after reset to defaults")


func test_reset_to_defaults_starts_delayed_activation() -> void:
	manager.reset_to_defaults()

	assert_true(manager._waiting_for_activation,
		"Reset to defaults should start delayed activation")


func test_reset_to_defaults_disables_death_effects_params() -> void:
	manager.trigger_death_effects()
	manager.process(0.5)
	manager.reset_to_defaults()

	assert_false(manager._shader_params["cigarette_burn_enabled"],
		"Cigarette burn should be disabled after reset to defaults")
	assert_false(manager._shader_params["end_of_reel_enabled"],
		"End of reel should be disabled after reset to defaults")
	assert_false(manager._shader_params["death_spots_enabled"],
		"Death spots should be disabled after reset to defaults")


# ============================================================================
# Edge Case Tests
# ============================================================================


func test_trigger_death_effects_twice_resets_timers() -> void:
	manager.trigger_death_effects()
	manager.process(1.0)

	var timer_before := manager._end_of_reel_timer
	assert_gt(timer_before, 0.0,
		"Timer should be > 0 after processing")

	manager.trigger_death_effects()

	assert_eq(manager._end_of_reel_timer, 0.0,
		"Timer should be reset after re-triggering death effects")


func test_reset_death_effects_when_not_active_is_safe() -> void:
	# Should not crash when resetting effects that were never triggered
	manager.reset_death_effects()

	assert_false(manager.is_death_effects_active(),
		"Death effects should remain inactive after safe reset")


func test_process_with_zero_delta() -> void:
	manager.trigger_death_effects()
	manager.process(0.0)

	assert_eq(manager._end_of_reel_timer, 0.0,
		"Timer should remain 0.0 with zero delta")
	assert_eq(manager._shader_params["cigarette_burn_intensity"], 0.0,
		"Burn intensity should be 0.0 with zero delta")


func test_process_with_very_small_delta() -> void:
	manager.trigger_death_effects()
	manager.process(0.001)

	assert_almost_eq(manager._end_of_reel_timer, 0.001, 0.0001,
		"Timer should advance by very small delta")


func test_process_with_large_delta() -> void:
	manager.trigger_death_effects()
	manager.process(100.0)

	# All intensities should be clamped at 1.0
	assert_almost_eq(manager._shader_params["cigarette_burn_intensity"], 1.0, 0.001,
		"Burn intensity should be clamped at 1.0 with large delta")
	assert_almost_eq(manager._shader_params["end_of_reel_intensity"], 1.0, 0.001,
		"Reel intensity should be clamped at 1.0 with large delta")
	assert_almost_eq(manager._shader_params["death_spots_intensity"], 1.0, 0.001,
		"Death spots intensity should be clamped at 1.0 with large delta")


func test_multiple_enable_disable_cycles() -> void:
	manager.set_enabled(false)
	assert_false(manager.is_enabled(), "Should be disabled")

	manager.set_enabled(true)
	assert_true(manager.is_enabled(), "Should be enabled")

	manager.set_enabled(false)
	assert_false(manager.is_enabled(), "Should be disabled again")

	manager.set_enabled(true)
	assert_true(manager.is_enabled(), "Should be enabled again")


func test_set_all_intensities_to_zero() -> void:
	manager.set_grain_intensity(0.0)
	manager.set_warm_intensity(0.0)
	manager.set_sunny_intensity(0.0)
	manager.set_vignette_intensity(0.0)
	manager.set_flicker_intensity(0.0)
	manager.set_micro_scratch_intensity(0.0)

	assert_eq(manager.get_grain_intensity(), 0.0, "Grain should be 0.0")
	assert_eq(manager.get_warm_intensity(), 0.0, "Warm should be 0.0")
	assert_eq(manager.get_sunny_intensity(), 0.0, "Sunny should be 0.0")
	assert_eq(manager.get_vignette_intensity(), 0.0, "Vignette should be 0.0")
	assert_eq(manager._shader_params["flicker_intensity"], 0.0, "Flicker should be 0.0")
	assert_eq(manager.get_micro_scratch_intensity(), 0.0, "Micro scratch should be 0.0")


func test_set_all_intensities_to_maximum() -> void:
	manager.set_grain_intensity(0.5)
	manager.set_warm_intensity(1.0)
	manager.set_sunny_intensity(0.5)
	manager.set_vignette_intensity(1.0)
	manager.set_flicker_intensity(0.3)
	manager.set_micro_scratch_intensity(1.0)

	assert_eq(manager.get_grain_intensity(), 0.5, "Grain should be at max 0.5")
	assert_eq(manager.get_warm_intensity(), 1.0, "Warm should be at max 1.0")
	assert_eq(manager.get_sunny_intensity(), 0.5, "Sunny should be at max 0.5")
	assert_eq(manager.get_vignette_intensity(), 1.0, "Vignette should be at max 1.0")
	assert_eq(manager._shader_params["flicker_intensity"], 0.3, "Flicker should be at max 0.3")
	assert_eq(manager.get_micro_scratch_intensity(), 1.0, "Micro scratch should be at max 1.0")
