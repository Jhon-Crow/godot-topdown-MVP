extends Node
## Autoload singleton for managing cinema film effects.
##
## Provides a screen-wide film effect that simulates a vintage/cinematic look including:
## - Film grain (without ripple/wave artifacts)
## - Warm/sunny color tint
## - Vignette effect
## - Rare film defects (scratches, dust, flicker)
##
## The effect can be enabled/disabled and parameters can be adjusted at runtime.

# ============================================================================
# DEFAULT VALUES
# ============================================================================

## Default grain intensity (0.0 = no grain, 0.5 = maximum)
const DEFAULT_GRAIN_INTENSITY: float = 0.04

## Default warm color tint (slightly warm/golden)
const DEFAULT_WARM_COLOR: Color = Color(1.0, 0.95, 0.85)

## Default warm tint intensity (0.0 = no tint, 1.0 = full tint)
const DEFAULT_WARM_INTENSITY: float = 0.12

## Default brightness
const DEFAULT_BRIGHTNESS: float = 1.05

## Default contrast
const DEFAULT_CONTRAST: float = 1.05

## Default sunny effect intensity
const DEFAULT_SUNNY_INTENSITY: float = 0.08

## Default sunny highlight boost
const DEFAULT_SUNNY_HIGHLIGHT_BOOST: float = 1.15

## Default vignette intensity
const DEFAULT_VIGNETTE_INTENSITY: float = 0.25

## Default vignette softness
const DEFAULT_VIGNETTE_SOFTNESS: float = 0.45

## Default film defect probability (1.5% chance)
const DEFAULT_DEFECT_PROBABILITY: float = 0.015

## Default scratch intensity
const DEFAULT_SCRATCH_INTENSITY: float = 0.6

## Default dust intensity
const DEFAULT_DUST_INTENSITY: float = 0.5

## Default flicker intensity
const DEFAULT_FLICKER_INTENSITY: float = 0.03

## The CanvasLayer for cinema effects.
var _effects_layer: CanvasLayer = null

## The ColorRect with the cinema shader.
var _cinema_rect: ColorRect = null

## Whether the effect is currently active.
var _is_active: bool = true

## Cached shader material reference.
var _material: ShaderMaterial = null


## Number of frames to wait before enabling the effect.
## This ensures the scene has fully rendered before applying the shader.
const ACTIVATION_DELAY_FRAMES: int = 3

## Counter for delayed activation.
var _activation_frame_counter: int = 0

## Whether we're waiting to activate the effect.
var _waiting_for_activation: bool = false


func _ready() -> void:
	_log("CinemaEffectsManager initializing...")

	# Connect to scene tree changes to handle scene reloads
	get_tree().tree_changed.connect(_on_tree_changed)

	# Create effects layer (high layer to render on top of everything)
	_effects_layer = CanvasLayer.new()
	_effects_layer.name = "CinemaEffectsLayer"
	_effects_layer.layer = 99  # Below hit effects (100) but above UI
	add_child(_effects_layer)
	_log("Created effects layer at layer 99")

	# Create full-screen overlay
	_cinema_rect = ColorRect.new()
	_cinema_rect.name = "CinemaOverlay"
	_cinema_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cinema_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Load and apply the cinema shader
	var shader := load("res://scripts/shaders/cinema_film.gdshader") as Shader
	if shader:
		_material = ShaderMaterial.new()
		_material.shader = shader
		_set_default_parameters()
		_cinema_rect.material = _material
		_log("Cinema shader loaded and applied successfully")
	else:
		push_warning("CinemaEffectsManager: Could not load cinema_film shader")
		_log("WARNING: Could not load cinema_film shader!")

	# CRITICAL: Start with overlay HIDDEN to prevent white screen
	# The shader will be enabled after the scene renders
	_cinema_rect.visible = false
	_effects_layer.add_child(_cinema_rect)

	# Perform shader warmup to prevent first-frame stutter (Issue #343 pattern)
	_warmup_shader()

	_log("Cinema film effect initialized - Configuration:")
	_log("  Grain intensity: %.2f" % DEFAULT_GRAIN_INTENSITY)
	_log("  Warm tint: %.2f intensity" % DEFAULT_WARM_INTENSITY)
	_log("  Sunny effect: %.2f intensity" % DEFAULT_SUNNY_INTENSITY)
	_log("  Vignette: %.2f intensity" % DEFAULT_VIGNETTE_INTENSITY)
	_log("  Film defects: %.1f%% probability" % (DEFAULT_DEFECT_PROBABILITY * 100.0))

	# Start delayed activation - wait for scene to render
	_waiting_for_activation = true
	_activation_frame_counter = 0
	_log("Waiting %d frames before enabling effect..." % ACTIVATION_DELAY_FRAMES)


## Log a message with the CinemaEffects prefix.
func _log(message: String) -> void:
	var logger: Node = get_node_or_null("/root/FileLogger")
	if logger and logger.has_method("log_info"):
		logger.log_info("[CinemaEffects] " + message)
	else:
		print("[CinemaEffects] " + message)


## Process function for delayed activation.
func _process(_delta: float) -> void:
	# Handle delayed activation to ensure scene has rendered before enabling effect
	if _waiting_for_activation:
		_activation_frame_counter += 1
		if _activation_frame_counter >= ACTIVATION_DELAY_FRAMES:
			_waiting_for_activation = false
			if _is_active:
				_cinema_rect.visible = true
				_log("Cinema effect now enabled (after %d frames delay)" % ACTIVATION_DELAY_FRAMES)


## Sets all shader parameters to default values.
func _set_default_parameters() -> void:
	if _material:
		# Grain parameters
		_material.set_shader_parameter("grain_intensity", DEFAULT_GRAIN_INTENSITY)
		_material.set_shader_parameter("grain_enabled", true)

		# Warm color parameters
		_material.set_shader_parameter("warm_color", DEFAULT_WARM_COLOR)
		_material.set_shader_parameter("warm_intensity", DEFAULT_WARM_INTENSITY)
		_material.set_shader_parameter("warm_enabled", true)

		# Sunny/bright effect parameters
		_material.set_shader_parameter("sunny_intensity", DEFAULT_SUNNY_INTENSITY)
		_material.set_shader_parameter("sunny_highlight_boost", DEFAULT_SUNNY_HIGHLIGHT_BOOST)
		_material.set_shader_parameter("sunny_enabled", true)

		# Vignette parameters
		_material.set_shader_parameter("vignette_intensity", DEFAULT_VIGNETTE_INTENSITY)
		_material.set_shader_parameter("vignette_softness", DEFAULT_VIGNETTE_SOFTNESS)
		_material.set_shader_parameter("vignette_enabled", true)

		# Brightness and contrast
		_material.set_shader_parameter("brightness", DEFAULT_BRIGHTNESS)
		_material.set_shader_parameter("contrast", DEFAULT_CONTRAST)

		# Film defect parameters
		_material.set_shader_parameter("defects_enabled", true)
		_material.set_shader_parameter("defect_probability", DEFAULT_DEFECT_PROBABILITY)
		_material.set_shader_parameter("scratch_intensity", DEFAULT_SCRATCH_INTENSITY)
		_material.set_shader_parameter("dust_intensity", DEFAULT_DUST_INTENSITY)
		_material.set_shader_parameter("flicker_intensity", DEFAULT_FLICKER_INTENSITY)


## Enables or disables the entire cinema effect.
func set_enabled(enabled: bool) -> void:
	_is_active = enabled
	if enabled:
		# Use delayed activation when enabling to prevent white screen
		_start_delayed_activation()
	else:
		# Disable immediately
		_cinema_rect.visible = false
		_waiting_for_activation = false


## Returns whether the effect is currently enabled.
func is_enabled() -> bool:
	return _is_active


## Sets the film grain intensity.
## @param intensity: Value from 0.0 (no grain) to 0.5 (maximum grain)
func set_grain_intensity(intensity: float) -> void:
	if _material:
		_material.set_shader_parameter("grain_intensity", clamp(intensity, 0.0, 0.5))


## Gets the current grain intensity.
func get_grain_intensity() -> float:
	if _material:
		return _material.get_shader_parameter("grain_intensity")
	return DEFAULT_GRAIN_INTENSITY


## Enables or disables just the grain effect.
func set_grain_enabled(enabled: bool) -> void:
	if _material:
		_material.set_shader_parameter("grain_enabled", enabled)


## Sets the warm color tint.
## @param color: The target warm color (default is a subtle warm/sepia)
func set_warm_color(color: Color) -> void:
	if _material:
		_material.set_shader_parameter("warm_color", color)


## Sets the warm tint intensity.
## @param intensity: Value from 0.0 (no tint) to 1.0 (full tint)
func set_warm_intensity(intensity: float) -> void:
	if _material:
		_material.set_shader_parameter("warm_intensity", clamp(intensity, 0.0, 1.0))


## Gets the current warm intensity.
func get_warm_intensity() -> float:
	if _material:
		return _material.get_shader_parameter("warm_intensity")
	return DEFAULT_WARM_INTENSITY


## Enables or disables just the warm tint effect.
func set_warm_enabled(enabled: bool) -> void:
	if _material:
		_material.set_shader_parameter("warm_enabled", enabled)


## Sets the overall brightness.
## @param value: 1.0 = normal, <1.0 = darker, >1.0 = brighter
func set_brightness(value: float) -> void:
	if _material:
		_material.set_shader_parameter("brightness", clamp(value, 0.5, 1.5))


## Gets the current brightness value.
func get_brightness() -> float:
	if _material:
		return _material.get_shader_parameter("brightness")
	return DEFAULT_BRIGHTNESS


## Sets the contrast level.
## @param value: 1.0 = normal, <1.0 = lower contrast, >1.0 = higher contrast
func set_contrast(value: float) -> void:
	if _material:
		_material.set_shader_parameter("contrast", clamp(value, 0.5, 2.0))


## Gets the current contrast value.
func get_contrast() -> float:
	if _material:
		return _material.get_shader_parameter("contrast")
	return DEFAULT_CONTRAST


# ============================================================================
# SUNNY EFFECT CONTROLS
# ============================================================================

## Sets the sunny/golden highlight effect intensity.
## @param intensity: Value from 0.0 (no sunny effect) to 0.5 (maximum)
func set_sunny_intensity(intensity: float) -> void:
	if _material:
		_material.set_shader_parameter("sunny_intensity", clamp(intensity, 0.0, 0.5))


## Gets the current sunny effect intensity.
func get_sunny_intensity() -> float:
	if _material:
		return _material.get_shader_parameter("sunny_intensity")
	return DEFAULT_SUNNY_INTENSITY


## Sets the highlight boost for bright areas in sunny effect.
## @param boost: Value from 1.0 (no boost) to 2.0 (double brightness)
func set_sunny_highlight_boost(boost: float) -> void:
	if _material:
		_material.set_shader_parameter("sunny_highlight_boost", clamp(boost, 1.0, 2.0))


## Enables or disables the sunny/golden highlight effect.
func set_sunny_enabled(enabled: bool) -> void:
	if _material:
		_material.set_shader_parameter("sunny_enabled", enabled)


# ============================================================================
# VIGNETTE CONTROLS
# ============================================================================

## Sets the vignette (edge darkening) intensity.
## @param intensity: Value from 0.0 (no vignette) to 1.0 (strong vignette)
func set_vignette_intensity(intensity: float) -> void:
	if _material:
		_material.set_shader_parameter("vignette_intensity", clamp(intensity, 0.0, 1.0))


## Gets the current vignette intensity.
func get_vignette_intensity() -> float:
	if _material:
		return _material.get_shader_parameter("vignette_intensity")
	return DEFAULT_VIGNETTE_INTENSITY


## Sets the vignette softness (how gradual the edge darkening is).
## @param softness: Value from 0.0 (sharp edges) to 1.0 (soft gradient)
func set_vignette_softness(softness: float) -> void:
	if _material:
		_material.set_shader_parameter("vignette_softness", clamp(softness, 0.0, 1.0))


## Enables or disables the vignette effect.
func set_vignette_enabled(enabled: bool) -> void:
	if _material:
		_material.set_shader_parameter("vignette_enabled", enabled)


# ============================================================================
# FILM DEFECTS CONTROLS (scratches, dust, flicker)
# ============================================================================

## Enables or disables all film defect effects (scratches, dust, flicker).
func set_defects_enabled(enabled: bool) -> void:
	if _material:
		_material.set_shader_parameter("defects_enabled", enabled)


## Returns whether film defects are enabled.
func is_defects_enabled() -> bool:
	if _material:
		return _material.get_shader_parameter("defects_enabled")
	return true


## Sets the probability of film defects appearing.
## @param probability: Value from 0.0 (never) to 0.1 (10% chance per frame)
func set_defect_probability(probability: float) -> void:
	if _material:
		_material.set_shader_parameter("defect_probability", clamp(probability, 0.0, 0.1))


## Gets the current defect probability.
func get_defect_probability() -> float:
	if _material:
		return _material.get_shader_parameter("defect_probability")
	return DEFAULT_DEFECT_PROBABILITY


## Sets the intensity of vertical scratch lines.
## @param intensity: Value from 0.0 (invisible) to 1.0 (fully visible)
func set_scratch_intensity(intensity: float) -> void:
	if _material:
		_material.set_shader_parameter("scratch_intensity", clamp(intensity, 0.0, 1.0))


## Sets the intensity of dust particles.
## @param intensity: Value from 0.0 (no dust) to 1.0 (dark dust)
func set_dust_intensity(intensity: float) -> void:
	if _material:
		_material.set_shader_parameter("dust_intensity", clamp(intensity, 0.0, 1.0))


## Sets the intensity of projector flicker effect.
## @param intensity: Value from 0.0 (no flicker) to 0.3 (strong flicker)
func set_flicker_intensity(intensity: float) -> void:
	if _material:
		_material.set_shader_parameter("flicker_intensity", clamp(intensity, 0.0, 0.3))


## Resets all parameters to defaults.
func reset_to_defaults() -> void:
	_set_default_parameters()
	_is_active = true
	# Trigger delayed activation instead of immediate enable
	_start_delayed_activation()


## Tracks the previous scene root to detect scene changes.
var _previous_scene_root: Node = null


## Called when the scene tree structure changes.
## Used to ensure effect persists across scene loads.
func _on_tree_changed() -> void:
	var current_scene := get_tree().current_scene
	if current_scene != null and current_scene != _previous_scene_root:
		_previous_scene_root = current_scene
		_log("Scene changed to: %s" % current_scene.name)
		# Re-trigger delayed activation on scene changes
		# This ensures the new scene has rendered before enabling the effect
		if _is_active:
			_start_delayed_activation()


## Starts the delayed activation process.
## Hides the overlay and waits for the scene to render before showing it.
func _start_delayed_activation() -> void:
	_cinema_rect.visible = false
	_waiting_for_activation = true
	_activation_frame_counter = 0


## Performs warmup to pre-compile the cinema shader.
## This prevents a shader compilation stutter on first frame (Issue #343 pattern).
func _warmup_shader() -> void:
	if _cinema_rect == null or _cinema_rect.material == null:
		return

	_log("Starting cinema shader warmup (Issue #343 fix)...")
	var start_time := Time.get_ticks_msec()

	# Ensure shader is visible briefly to trigger compilation
	_cinema_rect.visible = true

	# Wait one frame to ensure GPU processes and compiles the shader
	await get_tree().process_frame

	# CRITICAL: Hide the overlay after warmup
	# It will be re-enabled by delayed activation
	_cinema_rect.visible = false

	var elapsed := Time.get_ticks_msec() - start_time
	_log("Cinema shader warmup complete in %d ms" % elapsed)
