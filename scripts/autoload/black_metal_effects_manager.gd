extends Node
## BlackMetalEffectsManager - Manages the visual filter for Black Metal difficulty mode.
##
## Applies a fullscreen black-and-white + red shader when Black Metal difficulty is active.
## Red pixels (blood) and warm/fiery pixels (explosions, bullets, muzzle flashes) are
## preserved in color; everything else is rendered in high-contrast grayscale.
##
## The filter is automatically enabled/disabled when difficulty changes.
##
## IMPORTANT: hint_screen_texture requires at least one rendered frame before it is valid.
## Showing the overlay on frame 0 produces a white screen in Godot's gl_compatibility
## renderer. We therefore defer the first show by one frame (same fix used in
## CinemaEffectsManager v5.3).

## Number of frames to wait after enable_filter() before making the overlay visible.
const ACTIVATION_DELAY_FRAMES: int = 1

## CanvasLayer for the screen-space filter overlay.
var _filter_layer: CanvasLayer = null

## ColorRect carrying the shader material.
var _filter_rect: ColorRect = null

## Whether the filter should be visible (logical state).
var _is_active: bool = false

## Whether we are currently waiting to show the overlay after a delay.
var _waiting_for_activation: bool = false

## Frame counter used for the activation delay.
var _activation_frame_counter: int = 0

## Tracks the previous scene root to re-trigger activation on scene changes.
var _previous_scene_root: Node = null


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

	# Connect to scene changes so the filter re-activates properly after level loads.
	get_tree().tree_changed.connect(_on_tree_changed)

	# Connect to difficulty changes to enable/disable the filter.
	var difficulty_manager: Node = get_node_or_null("/root/DifficultyManager")
	if difficulty_manager:
		difficulty_manager.difficulty_changed.connect(_on_difficulty_changed)
		# Apply current difficulty state immediately.
		_apply_current_difficulty()
	else:
		_log("WARNING: DifficultyManager not found - filter will not activate automatically")


## Called every frame to handle the activation delay.
func _process(_delta: float) -> void:
	if not _waiting_for_activation:
		return
	_activation_frame_counter += 1
	if _activation_frame_counter >= ACTIVATION_DELAY_FRAMES:
		_waiting_for_activation = false
		if _is_active and _filter_rect:
			_filter_rect.visible = true
			_log("Black Metal filter now visible (after %d frame delay)" % ACTIVATION_DELAY_FRAMES)


## Enables the Black Metal visual filter (with a one-frame delay to avoid white screen).
func enable_filter() -> void:
	_is_active = true
	_start_delayed_activation()
	_log("Black Metal filter ENABLED (activation deferred by %d frame(s))" % ACTIVATION_DELAY_FRAMES)


## Starts the delayed-activation sequence.
## Hides the overlay and waits for the scene to render before showing it.
func _start_delayed_activation() -> void:
	if _filter_rect:
		_filter_rect.visible = false
	_waiting_for_activation = true
	_activation_frame_counter = 0


## Disables the Black Metal visual filter.
func disable_filter() -> void:
	_is_active = false
	_waiting_for_activation = false
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


## Called when the scene tree structure changes.
## Re-triggers activation on scene load so the filter appears in the new level.
func _on_tree_changed() -> void:
	var current_scene := get_tree().current_scene
	if current_scene != null and current_scene != _previous_scene_root:
		_previous_scene_root = current_scene
		_log("Scene changed to: %s" % current_scene.name)
		if _is_active:
			_start_delayed_activation()


## Log a message with the BlackMetal prefix.
func _log(message: String) -> void:
	var file_logger: Node = get_node_or_null("/root/FileLogger")
	if file_logger and file_logger.has_method("log_info"):
		file_logger.log_info("[BlackMetalEffectsManager] " + message)
	else:
		print("[BlackMetalEffectsManager] " + message)
