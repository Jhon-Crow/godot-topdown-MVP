extends Node
## BlackMetalEffectsManager - Manages the visual filter for Black Metal difficulty mode.
##
## Applies a fullscreen dark/desaturating overlay when Black Metal difficulty is active.
## The filter uses an OVERLAY-BASED approach (no hint_screen_texture) following the
## same architecture as CinemaEffectsManager v5.3, which explicitly avoids
## hint_screen_texture due to known white-screen bugs in Godot's gl_compatibility renderer.
##
## The black-and-white + red aesthetic is achieved architecturally:
##   - This CanvasLayer (layer 97) covers the game world with a dark desaturating overlay.
##   - Blood/hit effects and other vivid effects render on higher CanvasLayers (100+)
##     and appear ABOVE this overlay in full color — preserving red and fire tones.
##
## The filter is automatically enabled/disabled when difficulty changes via signal.

## CanvasLayer for the screen-space filter overlay.
var _filter_layer: CanvasLayer = null

## ColorRect carrying the shader material.
var _filter_rect: ColorRect = null

## Whether the filter should be visible (logical state).
var _is_active: bool = false


func _ready() -> void:
	# Create the overlay at layer 97 — below hit/blood effects (layer 100+) but above the game world.
	# This ensures vivid red/fire effects from higher layers show through unfiltered.
	_filter_layer = CanvasLayer.new()
	_filter_layer.name = "BlackMetalFilterLayer"
	_filter_layer.layer = 97
	_filter_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_filter_layer)

	_filter_rect = ColorRect.new()
	_filter_rect.name = "BlackMetalFilter"
	_filter_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_filter_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var shader := load("res://scripts/shaders/black_metal.gdshader") as Shader
	if shader:
		var material := ShaderMaterial.new()
		material.shader = shader
		material.set_shader_parameter("intensity", 1.0)
		material.set_shader_parameter("vignette_intensity", 0.75)
		material.set_shader_parameter("vignette_softness", 0.35)
		material.set_shader_parameter("grain_intensity", 0.12)
		material.set_shader_parameter("desaturation_darkness", 0.55)
		_filter_rect.material = material
		_log("Black Metal shader loaded successfully (overlay approach, no screen_texture)")
	else:
		push_warning("BlackMetalEffectsManager: Could not load black_metal.gdshader")
		_log("WARNING: Could not load black_metal.gdshader")

	_filter_rect.visible = false
	_filter_layer.add_child(_filter_rect)

	# Connect to difficulty changes to enable/disable the filter.
	var difficulty_manager: Node = get_node_or_null("/root/DifficultyManager")
	if difficulty_manager:
		difficulty_manager.difficulty_changed.connect(_on_difficulty_changed)
		# Apply current difficulty state immediately.
		_apply_current_difficulty()
	else:
		_log("WARNING: DifficultyManager not found - filter will not activate automatically")


## Enables the Black Metal visual filter.
## Since this shader does NOT use hint_screen_texture, it is safe to show immediately
## without any activation delay — no white screen risk.
func enable_filter() -> void:
	_is_active = true
	if _filter_rect:
		_filter_rect.visible = true
	_log("Black Metal filter ENABLED")


## Disables the Black Metal visual filter.
func disable_filter() -> void:
	_is_active = false
	if _filter_rect:
		_filter_rect.visible = false
	_log("Black Metal filter DISABLED")


## Returns whether the filter is currently active.
func is_filter_active() -> bool:
	return _is_active


## Called when the global difficulty changes.
func _on_difficulty_changed(_new_difficulty: int) -> void:
	_apply_current_difficulty()


## Reads the current difficulty from DifficultyManager and toggles the filter.
func _apply_current_difficulty() -> void:
	var difficulty_manager: Node = get_node_or_null("/root/DifficultyManager")
	if difficulty_manager and difficulty_manager.has_method("is_black_metal_mode"):
		if difficulty_manager.is_black_metal_mode():
			enable_filter()
		else:
			disable_filter()


## Log a message with the BlackMetal prefix.
func _log(message: String) -> void:
	var file_logger: Node = get_node_or_null("/root/FileLogger")
	if file_logger and file_logger.has_method("log_info"):
		file_logger.log_info("[BlackMetalEffectsManager] " + message)
	else:
		print("[BlackMetalEffectsManager] " + message)
