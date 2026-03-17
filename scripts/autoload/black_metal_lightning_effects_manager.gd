extends Node
## BlackMetalLightningEffectsManager - Thunder and lightning effects for Black Metal difficulty.
##
## Issue #1023: Adds dramatic horror-film style lightning bolt effects when the player
## hits an enemy in Black Metal difficulty mode. Each strike draws actual visible
## jagged bolt streaks from the top of the screen downward, with branches, plus
## a brief screen-wide illumination flash — like old horror/black-metal films.
##
## The bolt shader uses hint_screen_texture (same as black_metal.gdshader), with the
## ColorRect kept ALWAYS VISIBLE. This combination avoids both known gl_compatibility bugs:
##   1. visible=false→true transition bug: never occurs because ColorRect is always visible.
##   2. Transparent overlay corrupting higher-layer screen_texture capture: avoided because
##      at intensity=0 the shader outputs the original scene unchanged (pure passthrough),
##      not a transparent black quad.
##
## Why NOT toggling visible:
##   Godot's gl_compatibility renderer has known bugs with hint_screen_texture
##   (GitHub Issues #79914, #66458). When a ColorRect transitions from visible=false
##   to visible=true, the screen capture can return white/empty on the first frame,
##   causing the white blink symptom.
##
## Why NOT the pure overlay approach (transparent ColorRect always visible):
##   A full-screen transparent quad at layer 98 interferes with hint_screen_texture
##   in higher-layer shaders (cinema_film at layer 99), producing a white screen on
##   ALL difficulties — not just Black Metal.
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
## Stays ALWAYS VISIBLE — shader controls appearance via intensity (intensity=0 → passthrough).
## This avoids the gl_compatibility hint_screen_texture white-frame bug that occurs
## when transitioning from visible=false to visible=true.
var _flash_rect: ColorRect = null

## Cached shader material reference.
var _material: ShaderMaterial = null

## Whether the manager is active (Black Metal mode enabled).
var _is_active: bool = false

## Whether a flash animation is currently playing.
var _is_flashing: bool = false

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

	# Keep ColorRect ALWAYS VISIBLE — shader outputs passthrough (original scene) when intensity=0.
	# This avoids the gl_compatibility bug where transitioning visible=false→true
	# on a hint_screen_texture ColorRect can produce a white frame.
	# At intensity=0: COLOR = original scene → no visual effect on any difficulty.
	_flash_rect.visible = true
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

	_log("Starting %s lightning strike" % FlashPattern.keys()[pattern])
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

	# Show the bolt by setting intensity to 1.0.
	# The ColorRect is always visible; shader controls appearance via intensity.
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


## Performs warmup to pre-compile the lightning bolt shader.
## At intensity=0.0, the shader outputs the original scene (pure passthrough).
## This ensures no white blink even during GPU shader compilation.
func _warmup_shader() -> void:
	if _flash_rect == null or _material == null:
		return

	_log("Starting shader warmup (Issue #343 pattern)...")
	var start_time := Time.get_ticks_msec()

	# intensity=0.0 → shader outputs original scene → pure passthrough, no visible effect.
	# Same pattern as black_metal_effects_manager warmup.
	_material.set_shader_parameter("intensity", 0.0)

	# Wait one frame for GPU to compile and process the shader.
	await get_tree().process_frame

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
