extends Node
## BlackMetalLightningEffectsManager - Thunder and lightning effects for Black Metal difficulty.
##
## Issue #1023: Adds dramatic horror-film style lightning bolt effects when the player
## hits an enemy in Black Metal difficulty mode. Each strike draws actual visible
## jagged bolt streaks from the top of the screen downward, with branches, plus
## a brief screen-wide illumination flash — like old horror/black-metal films.
##
## APPROACH (v8): hint_screen_texture, rect hidden between flashes
##
## Key design: visible=false is the normal off-state (unlike v6/v7 where it was always visible).
##   _ready():         visible=true + intensity=0 for warmup frame, then visible=false
##   between flashes:  visible=false — rect not in rendering pipeline, no sampling
##   scene changes:    detected via tree_changed; any in-progress flash is aborted
##   "on" state:       visible=true, intensity = 1.0 → 0.0 (bolt visible, fades out)
##   after flash:      visible=false again
##
## Why scene-transition delay is required (v7 failure):
##   v7 set visible=true permanently after warmup. When PersistManager navigates
##   to the last played level immediately on startup (within 600ms), a new scene
##   loads and the GL framebuffer resets. On the FIRST frame of the new scene,
##   hint_screen_texture returns white/empty. With visible=true + intensity=0,
##   the passthrough outputs COLOR = white → white blink visible to the user.
##   (Confirmed in game_log_20260317_054351.txt: warmup at 05:43:52, scene change
##    to CityLevel at 05:43:52, white blink at startup.)
##
## Why NOT the pure overlay approach (no screen_texture, transparent output):
##   A full-screen transparent ColorRect at layer 98 causes visual corruption on ALL
##   difficulties — not just Black Metal. (Tested in v5, game_log_20260317_032119.txt)
##
## Features:
## - Procedural jagged lightning bolt drawn across the screen
## - Branches splitting off the main bolt
## - Screen-wide illumination pulse at the moment of impact
## - Visual diversity: randomized bolt origin, path, number of bolts, branches
## - Single, double, or triple-bolt sequences for varied intensity
## - Respects the existing B&W+red filter (renders at layer 98, above it)


## Flash pattern types for visual diversity.
enum FlashPattern {
	SINGLE,   ## One bolt strike
	DOUBLE,   ## Two quick strikes
	TRIPLE    ## Three rapid strikes
}

## Minimum flash duration in seconds (how long one bolt stays visible).
const MIN_FLASH_DURATION: float = 0.12

## Maximum flash duration in seconds.
const MAX_FLASH_DURATION: float = 0.22

## Gap between strikes in multi-strike patterns (seconds).
const MULTI_FLASH_GAP: float = 0.05

## Probability of double flash pattern.
const DOUBLE_FLASH_CHANCE: float = 0.35

## Probability of triple flash pattern.
const TRIPLE_FLASH_CHANCE: float = 0.15

## CanvasLayer for the lightning bolt overlay.
var _flash_layer: CanvasLayer = null

## ColorRect carrying the bolt shader material.
## Hidden between flashes — only visible=true for the duration of a bolt strike.
## This is the key fix for v8: the rect is NOT a persistent overlay (unlike v6/v7),
## so hint_screen_texture is only sampled during active flashes, never at scene changes.
var _flash_rect: ColorRect = null

## Cached shader material reference.
var _material: ShaderMaterial = null

## Whether the manager is active (Black Metal mode enabled).
var _is_active: bool = false

## Whether a flash animation is currently playing.
var _is_flashing: bool = false

## Track the previous scene to detect scene transitions (for flash-abort on scene change).
var _previous_scene_root: Node = null

## Current flash state for animation.
var _flash_timer: float = 0.0
var _flash_duration: float = 0.0
var _flashes_remaining: int = 0
var _in_gap: bool = false
var _gap_timer: float = 0.0

## Seed used for the current bolt (randomized per flash).
var _current_seed: float = 0.0

## Whether the current bolt should be a double-bolt (2 streaks at once).
var _use_double_bolt: bool = false


func _ready() -> void:
	_log("BlackMetalLightningEffectsManager initializing...")

	# Connect to scene tree changes to handle scene reloads.
	# Mirrors black_metal_effects_manager._on_tree_changed pattern.
	get_tree().tree_changed.connect(_on_tree_changed)

	# Create the flash layer at layer 98 — above the Black Metal filter (97) but below hit effects (100).
	_flash_layer = CanvasLayer.new()
	_flash_layer.name = "BlackMetalLightningLayer"
	_flash_layer.layer = 98
	_flash_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_flash_layer)

	_flash_rect = ColorRect.new()
	_flash_rect.name = "LightningFlash"
	_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var shader := load("res://scripts/shaders/lightning_flash.gdshader") as Shader
	if shader:
		_material = ShaderMaterial.new()
		_material.shader = shader
		_material.set_shader_parameter("intensity", 0.0)
		_material.set_shader_parameter("progress", 0.0)
		_material.set_shader_parameter("seed", 0.0)
		_material.set_shader_parameter("bolt_count", 1.0)
		_flash_rect.material = _material
		_log("Lightning bolt shader loaded")
	else:
		push_warning("BlackMetalLightningEffectsManager: Could not load lightning_flash.gdshader")
		_log("WARNING: Could not load lightning_flash.gdshader")

	_flash_rect.visible = false
	_flash_layer.add_child(_flash_rect)

	# Perform shader warmup to pre-compile the shader.
	_warmup_shader()

	# Connect to difficulty changes to enable/disable the effects.
	var difficulty_manager: Node = get_node_or_null("/root/DifficultyManager")
	if difficulty_manager:
		difficulty_manager.difficulty_changed.connect(_on_difficulty_changed)
		# Apply current difficulty state immediately.
		_apply_current_difficulty()
	else:
		_log("WARNING: DifficultyManager not found - effects will not activate automatically")


func _process(delta: float) -> void:
	# Process ongoing flash animation.
	if _is_flashing:
		_process_flash(delta)


## Triggers a lightning bolt strike. Called when player hits an enemy in Black Metal mode.
func trigger_lightning() -> void:
	if not _is_active:
		return

	# Don't interrupt an ongoing flash sequence — let it complete naturally.
	if _is_flashing:
		return

	# Determine flash pattern for visual diversity.
	var pattern := _choose_flash_pattern()

	# Start the flash sequence.
	_start_flash_sequence(pattern)


## Chooses a random flash pattern based on configured probabilities.
func _choose_flash_pattern() -> FlashPattern:
	var roll := randf()
	if roll < TRIPLE_FLASH_CHANCE:
		return FlashPattern.TRIPLE
	elif roll < TRIPLE_FLASH_CHANCE + DOUBLE_FLASH_CHANCE:
		return FlashPattern.DOUBLE
	else:
		return FlashPattern.SINGLE


## Starts a flash sequence with the given pattern.
func _start_flash_sequence(pattern: FlashPattern) -> void:
	match pattern:
		FlashPattern.SINGLE:
			_flashes_remaining = 1
		FlashPattern.DOUBLE:
			_flashes_remaining = 2
		FlashPattern.TRIPLE:
			_flashes_remaining = 3

	_log("%s lightning strike (%d flash(es))" % [FlashPattern.keys()[pattern], _flashes_remaining])
	_start_single_flash()


## Starts a single bolt strike within a sequence.
func _start_single_flash() -> void:
	_is_flashing = true
	_in_gap = false

	# Randomize duration for natural variation.
	_flash_duration = randf_range(MIN_FLASH_DURATION, MAX_FLASH_DURATION)
	_flash_timer = 0.0

	# New random seed → new bolt path each strike.
	_current_seed = randf() * 100.0
	# Occasionally fire two simultaneous bolt streaks for dramatic effect.
	_use_double_bolt = randf() < 0.3

	# Make the ColorRect visible and set intensity to 1.0 to show the bolt.
	if _flash_rect:
		_flash_rect.visible = true
	if _material:
		_material.set_shader_parameter("seed", _current_seed)
		_material.set_shader_parameter("bolt_count", 2.0 if _use_double_bolt else 1.0)
		_material.set_shader_parameter("progress", 0.0)
		_material.set_shader_parameter("intensity", 1.0)


## Processes the bolt animation each frame.
func _process_flash(delta: float) -> void:
	if _in_gap:
		# We're in the gap between strikes.
		_gap_timer += delta
		if _gap_timer >= MULTI_FLASH_GAP:
			_in_gap = false
			if _flashes_remaining > 0:
				_start_single_flash()
			else:
				_end_flash_sequence()
		return

	_flash_timer += delta
	var progress := _flash_timer / _flash_duration

	if progress >= 1.0:
		# This strike is complete.
		_flashes_remaining -= 1

		if _flashes_remaining > 0:
			# Enter gap before next strike — hide bolt by setting intensity=0.
			_in_gap = true
			_gap_timer = 0.0
			if _material:
				_material.set_shader_parameter("intensity", 0.0)
		else:
			_end_flash_sequence()
	else:
		# Fade out the bolt: instant full brightness at start, rapid fade.
		# Lightning: blazing start, fast decay. Use quadratic ease-out.
		var fade := 1.0 - progress
		fade = fade * fade  # ease-out
		if _material:
			_material.set_shader_parameter("progress", progress)
			_material.set_shader_parameter("intensity", fade)


## Ends the entire flash sequence.
func _end_flash_sequence() -> void:
	_is_flashing = false
	_flashes_remaining = 0
	if _material:
		_material.set_shader_parameter("intensity", 0.0)
	if _flash_rect:
		_flash_rect.visible = false


## Called when the global difficulty changes.
func _on_difficulty_changed(_new_difficulty: int) -> void:
	_apply_current_difficulty()


## Reads the current difficulty from DifficultyManager and toggles activation.
func _apply_current_difficulty() -> void:
	var difficulty_manager: Node = get_node_or_null("/root/DifficultyManager")
	if difficulty_manager and difficulty_manager.has_method("is_black_metal_mode"):
		var was_active := _is_active
		_is_active = difficulty_manager.is_black_metal_mode()
		if _is_active and not was_active:
			_log("Lightning effects ENABLED (Black Metal mode)")
		elif not _is_active and was_active:
			_log("Lightning effects DISABLED")
			_end_flash_sequence()
			if _flash_rect:
				_flash_rect.visible = false


## Called when the scene tree structure changes.
## Aborts any in-progress flash and hides the overlay immediately.
## The new scene's framebuffer is not populated yet — we must not sample hint_screen_texture.
## Since visible=false is the normal "off" state between flashes, no delayed re-show is needed.
func _on_tree_changed() -> void:
	var current_scene := get_tree().current_scene
	if current_scene != null and current_scene != _previous_scene_root:
		_previous_scene_root = current_scene
		_log("Scene changed to: %s" % current_scene.name)
		# Abort any in-progress flash and hide the overlay.
		_is_flashing = false
		_flashes_remaining = 0
		if _material:
			_material.set_shader_parameter("intensity", 0.0)
		if _flash_rect:
			_flash_rect.visible = false


## Performs warmup to pre-compile the lightning bolt shader.
##
## WARMUP SEQUENCE (mirrors black_metal_effects_manager):
##   1. visible=true + intensity=0.0: wait 1 frame (GPU compiles shader; even if
##      hint_screen_texture returns white, intensity=0 outputs passthrough so no blink).
##   2. After the frame: visible=false (rect hidden, no rendering, no sampling).
##      The rect stays hidden until trigger_lightning() fires a bolt.
func _warmup_shader() -> void:
	if _flash_rect == null or _material == null:
		return

	_log("Starting shader warmup (Issue #343 pattern)...")
	var start_time := Time.get_ticks_msec()

	# intensity=0.0 → even if hint_screen_texture returns white, output is passthrough.
	_material.set_shader_parameter("intensity", 0.0)
	_flash_rect.visible = true

	# Wait one frame for GPU to compile and process the shader.
	await get_tree().process_frame

	# Hide after warmup — same as black_metal_effects_manager.
	# The overlay only becomes visible when trigger_lightning() fires a bolt.
	_flash_rect.visible = false

	var elapsed := Time.get_ticks_msec() - start_time
	_log("Shader warmup complete in %d ms" % elapsed)


## Returns whether lightning effects are currently active.
func is_active() -> bool:
	return _is_active


## Log a message with the Lightning prefix.
func _log(message: String) -> void:
	var file_logger: Node = get_node_or_null("/root/FileLogger")
	if file_logger and file_logger.has_method("log_info"):
		file_logger.log_info("[BlackMetalLightningEffectsManager] " + message)
	else:
		print("[BlackMetalLightningEffectsManager] " + message)
