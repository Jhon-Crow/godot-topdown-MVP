extends Node
## BlackMetalEffectsManager - Manages the visual filter for Black Metal difficulty mode.
##
## Applies a fullscreen B&W+red post-processing filter when Black Metal difficulty is active.
## The filter uses hint_screen_texture to read the rendered scene and apply per-pixel color
## transformation (same approach as ghost_replay.gdshader used in Ghost replay mode).
##
## WHITE SCREEN PREVENTION:
##   In Godot's gl_compatibility renderer, hint_screen_texture can return an empty/white texture
##   if the overlay is shown before the scene has rendered. This is avoided by:
##   1. Warmup: The shader runs for 1 frame with intensity=0.0 (invisible pass-through).
##      Even if screen_texture returns white during warmup, the output equals original.rgb
##      (mix(original, result, 0.0) = original), so no white flash is visible.
##   2. Delayed activation: On scene transitions, the overlay is deferred by
##      ACTIVATION_DELAY_FRAMES frames to let the framebuffer populate first.
##   This is the same pattern used by HitEffectsManager and LastChanceEffectsManager.
##
## The filter is automatically enabled/disabled when difficulty changes via signal.

## Number of frames to wait after a scene transition before showing the filter.
## 3 frames ensures the framebuffer is fully populated in gl_compatibility renderer.
const ACTIVATION_DELAY_FRAMES: int = 3

## CanvasLayer for the screen-space filter.
var _filter_layer: CanvasLayer = null

## ColorRect carrying the shader material.
var _filter_rect: ColorRect = null

## Cached shader material reference.
var _material: ShaderMaterial = null

## Whether the filter should be visible (logical state).
var _is_active: bool = false

## Whether we're waiting for delayed activation after a scene change.
var _waiting_for_activation: bool = false

## Frame counter for delayed activation.
var _activation_frame_counter: int = 0

## Track the previous scene to detect scene transitions.
var _previous_scene_root: Node = null


func _ready() -> void:
	_log("BlackMetalEffectsManager initializing...")

	# Connect to scene tree changes to handle scene reloads.
	get_tree().tree_changed.connect(_on_tree_changed)

	# Create the filter at layer 97 — below hit/blood effects (layer 100+) but above world.
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
		_material = ShaderMaterial.new()
		_material.shader = shader
		_material.set_shader_parameter("intensity", 1.0)
		_material.set_shader_parameter("red_threshold", 0.15)
		_material.set_shader_parameter("red_boost", 1.8)
		_material.set_shader_parameter("fire_threshold", 0.25)
		_material.set_shader_parameter("bright_flash_threshold", 0.85)  # Issue #985: preserve weapon flashes
		_material.set_shader_parameter("contrast", 1.5)
		_filter_rect.material = _material
		_log("Black Metal shader loaded (B&W+red, hint_screen_texture approach)")
	else:
		push_warning("BlackMetalEffectsManager: Could not load black_metal.gdshader")
		_log("WARNING: Could not load black_metal.gdshader")

	_filter_rect.visible = false
	_filter_layer.add_child(_filter_rect)

	# Perform shader warmup to pre-compile the shader.
	# Warmup runs at intensity=0.0 so even if screen_texture returns white (gl_compatibility
	# renderer behavior before scene renders), the output is a pure pass-through of original.rgb.
	_warmup_shader()

	# Connect to difficulty changes to enable/disable the filter.
	var difficulty_manager: Node = get_node_or_null("/root/DifficultyManager")
	if difficulty_manager:
		difficulty_manager.difficulty_changed.connect(_on_difficulty_changed)
		# Apply current difficulty state immediately.
		_apply_current_difficulty()
	else:
		_log("WARNING: DifficultyManager not found - filter will not activate automatically")


## Process function handles delayed activation after scene transitions.
func _process(_delta: float) -> void:
	if _waiting_for_activation:
		_activation_frame_counter += 1
		if _activation_frame_counter >= ACTIVATION_DELAY_FRAMES:
			_waiting_for_activation = false
			if _is_active and _filter_rect:
				if _material:
					_material.set_shader_parameter("intensity", 1.0)
				_filter_rect.visible = true
				_log("Black Metal filter now visible (after %d frames delay)" % ACTIVATION_DELAY_FRAMES)


## Enables the Black Metal visual filter.
## Uses delayed activation to ensure the framebuffer is populated before hint_screen_texture reads.
func enable_filter() -> void:
	_is_active = true
	_log("Black Metal filter ENABLED (will show after %d frames)" % ACTIVATION_DELAY_FRAMES)
	_start_delayed_activation()


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
## Re-triggers delayed activation on scene transitions to prevent white screen.
func _on_tree_changed() -> void:
	var current_scene := get_tree().current_scene
	if current_scene != null and current_scene != _previous_scene_root:
		_previous_scene_root = current_scene
		_log("Scene changed to: %s" % current_scene.name)
		# Re-trigger delayed activation on scene changes.
		# The framebuffer needs to repopulate after a scene transition.
		if _is_active:
			_start_delayed_activation()


## Hides the overlay and starts the frame counter for delayed activation.
func _start_delayed_activation() -> void:
	if _filter_rect:
		_filter_rect.visible = false
	_waiting_for_activation = true
	_activation_frame_counter = 0


## Performs warmup to pre-compile the Black Metal shader.
## Warmup uses intensity=0.0 so the output is original.rgb (pass-through).
## Even if hint_screen_texture returns white during warmup, there is no visible white flash.
func _warmup_shader() -> void:
	if _filter_rect == null or _material == null:
		return

	_log("Starting shader warmup (Issue #343 pattern)...")
	var start_time := Time.get_ticks_msec()

	# Set intensity to 0 so the shader outputs original.rgb — no visible effect during warmup.
	_material.set_shader_parameter("intensity", 0.0)
	_filter_rect.visible = true

	# Wait one frame for GPU to compile and process the shader.
	await get_tree().process_frame

	# CRITICAL: Hide after warmup. intensity will be set back to 1.0 on activation.
	_filter_rect.visible = false
	_material.set_shader_parameter("intensity", 1.0)

	var elapsed := Time.get_ticks_msec() - start_time
	_log("Shader warmup complete in %d ms" % elapsed)


## Log a message with the BlackMetal prefix.
## Issue #1293: print() fallback gated to debug builds to avoid FPS drops.
func _log(message: String) -> void:
	var file_logger: Node = get_node_or_null("/root/FileLogger")
	if file_logger and file_logger.has_method("log_info"):
		file_logger.log_info("[BlackMetalEffectsManager] " + message)
	elif OS.is_debug_build():
		print("[BlackMetalEffectsManager] " + message)
