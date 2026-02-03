extends Node
## Autoload singleton for managing cinema film effects.
##
## Provides a screen-wide film grain and warm color tint effect
## that simulates a vintage/cinematic look.
##
## The effect can be enabled/disabled and parameters can be adjusted at runtime.

## Default grain intensity (0.0 = no grain, 0.5 = maximum)
const DEFAULT_GRAIN_INTENSITY: float = 0.05

## Default grain animation speed
const DEFAULT_GRAIN_SPEED: float = 15.0

## Default warm color tint (slightly warm/sepia)
const DEFAULT_WARM_COLOR: Color = Color(1.0, 0.9, 0.7)

## Default warm tint intensity (0.0 = no tint, 1.0 = full tint)
const DEFAULT_WARM_INTENSITY: float = 0.15

## Default brightness
const DEFAULT_BRIGHTNESS: float = 1.0

## The CanvasLayer for cinema effects.
var _effects_layer: CanvasLayer = null

## The ColorRect with the cinema shader.
var _cinema_rect: ColorRect = null

## Whether the effect is currently active.
var _is_active: bool = true

## Cached shader material reference.
var _material: ShaderMaterial = null


func _ready() -> void:
	# Connect to scene tree changes to handle scene reloads
	get_tree().tree_changed.connect(_on_tree_changed)

	# Create effects layer (high layer to render on top of everything)
	_effects_layer = CanvasLayer.new()
	_effects_layer.name = "CinemaEffectsLayer"
	_effects_layer.layer = 99  # Below hit effects (100) but above UI
	add_child(_effects_layer)

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
	else:
		push_warning("CinemaEffectsManager: Could not load cinema_film shader")

	_effects_layer.add_child(_cinema_rect)

	# Perform shader warmup to prevent first-frame stutter (Issue #343 pattern)
	_warmup_shader()

	print("[CinemaEffectsManager] Cinema film effect initialized")


## Sets all shader parameters to default values.
func _set_default_parameters() -> void:
	if _material:
		_material.set_shader_parameter("grain_intensity", DEFAULT_GRAIN_INTENSITY)
		_material.set_shader_parameter("grain_speed", DEFAULT_GRAIN_SPEED)
		_material.set_shader_parameter("warm_color", DEFAULT_WARM_COLOR)
		_material.set_shader_parameter("warm_intensity", DEFAULT_WARM_INTENSITY)
		_material.set_shader_parameter("brightness", DEFAULT_BRIGHTNESS)
		_material.set_shader_parameter("grain_enabled", true)
		_material.set_shader_parameter("warm_enabled", true)


## Enables or disables the entire cinema effect.
func set_enabled(enabled: bool) -> void:
	_is_active = enabled
	_cinema_rect.visible = enabled


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


## Sets the grain animation speed.
## @param speed: Higher values = faster grain animation
func set_grain_speed(speed: float) -> void:
	if _material:
		_material.set_shader_parameter("grain_speed", max(speed, 0.0))


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


## Resets all parameters to defaults.
func reset_to_defaults() -> void:
	_set_default_parameters()
	_is_active = true
	_cinema_rect.visible = true


## Tracks the previous scene root to detect scene changes.
var _previous_scene_root: Node = null


## Called when the scene tree structure changes.
## Used to ensure effect persists across scene loads.
func _on_tree_changed() -> void:
	var current_scene := get_tree().current_scene
	if current_scene != null and current_scene != _previous_scene_root:
		_previous_scene_root = current_scene
		# Keep the effect active across scene changes
		# The effect settings persist as this is an autoload


## Performs warmup to pre-compile the cinema shader.
## This prevents a shader compilation stutter on first frame (Issue #343 pattern).
func _warmup_shader() -> void:
	if _cinema_rect == null or _cinema_rect.material == null:
		return

	print("[CinemaEffectsManager] Starting cinema shader warmup...")
	var start_time := Time.get_ticks_msec()

	# Ensure shader is visible briefly to trigger compilation
	_cinema_rect.visible = true

	# Wait one frame to ensure GPU processes and compiles the shader
	await get_tree().process_frame

	var elapsed := Time.get_ticks_msec() - start_time
	print("[CinemaEffectsManager] Cinema shader warmup complete in %d ms" % elapsed)
