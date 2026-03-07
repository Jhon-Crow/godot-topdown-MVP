extends Node
## BlackMetalEffectsManager - Manages the visual filter for Black Metal difficulty mode.
##
## Applies a fullscreen black-and-white + red shader when Black Metal difficulty is active.
## Red pixels (blood) and warm/fiery pixels (explosions, bullets, muzzle flashes) are
## preserved in color; everything else is rendered in high-contrast grayscale.
##
## The filter is automatically enabled/disabled when difficulty changes.

## CanvasLayer for the screen-space filter overlay.
var _filter_layer: CanvasLayer = null

## ColorRect carrying the shader material.
var _filter_rect: ColorRect = null

## Whether the filter is currently visible.
var _is_active: bool = false


func _ready() -> void:
	# Create the overlay at a high layer (below replay UI at 100, above most effects).
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
		material.set_shader_parameter("red_threshold", 0.15)
		material.set_shader_parameter("red_boost", 1.8)
		material.set_shader_parameter("fire_threshold", 0.25)
		material.set_shader_parameter("contrast", 1.5)
		_filter_rect.material = material
		_log("Black Metal shader loaded successfully")
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
func enable_filter() -> void:
	if _filter_rect:
		_filter_rect.visible = true
	_is_active = true
	_log("Black Metal filter ENABLED")


## Disables the Black Metal visual filter.
func disable_filter() -> void:
	if _filter_rect:
		_filter_rect.visible = false
	_is_active = false
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
