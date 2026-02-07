extends Node
## FlashbangPlayerEffectsManager - Screen overlay effect when the player is hit by a flashbang.
##
## This autoload singleton manages the player's screen effect when a flashbang
## grenade explodes within range and line of sight (Issue #605).
##
## Effect details:
## - Dark purple tint covers the screen center
## - Bordeaux/burgundy vignette border (like retinal afterimage)
## - Duration: 1-5 seconds based on distance (closer = longer)
## - Intensity: scales with distance (closer = stronger)
## - Walls block the effect (line of sight required, Issue #469)
## - Effect fades out gradually over time

## Minimum effect duration in seconds (at maximum distance).
const MIN_DURATION: float = 1.0

## Maximum effect duration in seconds (at point-blank range).
const MAX_DURATION: float = 5.0

## Duration of the fade-out phase as a ratio of total duration.
## The last 60% of the effect duration is the fade-out.
const FADE_OUT_RATIO: float = 0.6

## The CanvasLayer for screen effects.
var _effects_layer: CanvasLayer = null

## The ColorRect with the flashbang player shader.
var _effect_rect: ColorRect = null

## Whether the flashbang screen effect is currently active.
var _is_effect_active: bool = false

## The time when the effect started (in real time seconds).
var _effect_start_time: float = 0.0

## Total duration of the current effect in seconds.
var _effect_duration: float = 0.0

## Peak intensity of the current effect (0.0-1.0).
var _peak_intensity: float = 0.0

## Tracks the previous scene root to detect scene changes.
var _previous_scene_root: Node = null


func _ready() -> void:
	# Connect to scene tree changes to reset effects on scene reload
	get_tree().tree_changed.connect(_on_tree_changed)

	# Create effects layer (higher than LastChanceEffectsManager at 102)
	_effects_layer = CanvasLayer.new()
	_effects_layer.name = "FlashbangPlayerEffectsLayer"
	_effects_layer.layer = 103
	add_child(_effects_layer)

	# Create effect overlay
	_effect_rect = ColorRect.new()
	_effect_rect.name = "FlashbangPlayerOverlay"
	_effect_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_effect_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Load and apply the flashbang player shader
	var shader := load("res://scripts/shaders/flashbang_player.gdshader") as Shader
	if shader:
		var material := ShaderMaterial.new()
		material.shader = shader
		material.set_shader_parameter("intensity", 0.0)
		_effect_rect.material = material
		_log("Flashbang player shader loaded successfully")
	else:
		push_warning("FlashbangPlayerEffectsManager: Could not load flashbang player shader")
		_log("WARNING: Could not load flashbang player shader!")

	_effect_rect.visible = false
	_effects_layer.add_child(_effect_rect)

	# Perform shader warmup to prevent first-use lag (Issue #343)
	_warmup_shader()

	_log("FlashbangPlayerEffectsManager ready")
	_log("  Duration range: %.1f-%.1f seconds" % [MIN_DURATION, MAX_DURATION])


func _process(_delta: float) -> void:
	if not _is_effect_active:
		return

	var current_time := Time.get_ticks_msec() / 1000.0
	var elapsed := current_time - _effect_start_time

	# Check if effect has expired
	if elapsed >= _effect_duration:
		_end_effect()
		return

	# Calculate current intensity based on elapsed time
	var progress := elapsed / _effect_duration

	# Full intensity for the first portion, then fade out
	var fade_start := 1.0 - FADE_OUT_RATIO
	var current_intensity: float
	if progress < fade_start:
		# Full intensity phase
		current_intensity = _peak_intensity
	else:
		# Fade-out phase: ease-out curve for smooth transition
		var fade_progress := (progress - fade_start) / FADE_OUT_RATIO
		# Use ease-out quadratic for natural-looking fade
		current_intensity = _peak_intensity * (1.0 - fade_progress * fade_progress)

	# Update shader intensity
	var material := _effect_rect.material as ShaderMaterial
	if material:
		material.set_shader_parameter("intensity", current_intensity)


## Applies the flashbang screen effect to the player.
## Called when a flashbang grenade explodes and the player is in the blast zone.
## @param grenade_position: World position of the flashbang explosion.
## @param player_position: World position of the player.
## @param effect_radius: The flashbang's effect radius.
func apply_flashbang_effect(grenade_position: Vector2, player_position: Vector2, effect_radius: float) -> void:
	# Calculate distance between grenade and player
	var distance := grenade_position.distance_to(player_position)

	# Calculate distance factor (1.0 at center, 0.0 at edge of radius)
	var distance_factor := 1.0 - clampf(distance / effect_radius, 0.0, 1.0)

	# Skip if distance factor is effectively zero (player at very edge of radius)
	if distance_factor < 0.01:
		_log("Player at edge of radius (factor=%.3f), skipping effect" % distance_factor)
		return

	# Calculate duration: 1-5 seconds based on distance
	var duration := MIN_DURATION + (MAX_DURATION - MIN_DURATION) * distance_factor

	# Calculate peak intensity based on distance (closer = more intense)
	var peak_intensity := clampf(distance_factor, 0.0, 1.0)

	_log("Applying flashbang to player: distance=%.0f, factor=%.2f, duration=%.1fs, intensity=%.2f" % [
		distance, distance_factor, duration, peak_intensity
	])

	# If effect is already active, take the stronger one
	if _is_effect_active:
		if peak_intensity > _peak_intensity:
			_log("Stronger flashbang overrides current effect")
		else:
			_log("Current effect is stronger, ignoring new flashbang")
			return

	_start_effect(duration, peak_intensity)


## Starts the screen effect with the given duration and intensity.
func _start_effect(duration: float, peak_intensity: float) -> void:
	_is_effect_active = true
	_effect_duration = duration
	_peak_intensity = peak_intensity
	_effect_start_time = Time.get_ticks_msec() / 1000.0

	# Show the overlay and set initial intensity
	_effect_rect.visible = true
	var material := _effect_rect.material as ShaderMaterial
	if material:
		material.set_shader_parameter("intensity", peak_intensity)

	_log("Flashbang player effect started: duration=%.1fs, intensity=%.2f" % [duration, peak_intensity])


## Ends the screen effect and hides the overlay.
func _end_effect() -> void:
	_is_effect_active = false
	_effect_rect.visible = false

	var material := _effect_rect.material as ShaderMaterial
	if material:
		material.set_shader_parameter("intensity", 0.0)

	_log("Flashbang player effect ended")


## Returns whether the flashbang screen effect is currently active.
func is_effect_active() -> bool:
	return _is_effect_active


## Returns the remaining duration of the current effect in seconds.
func get_remaining_duration() -> float:
	if not _is_effect_active:
		return 0.0

	var current_time := Time.get_ticks_msec() / 1000.0
	var elapsed := current_time - _effect_start_time
	return maxf(_effect_duration - elapsed, 0.0)


## Returns the current peak intensity of the effect.
func get_peak_intensity() -> float:
	return _peak_intensity if _is_effect_active else 0.0


## Resets all effects (useful when restarting the scene).
func reset_effects() -> void:
	_log("Resetting flashbang player effects (scene change)")

	_is_effect_active = false
	_effect_duration = 0.0
	_peak_intensity = 0.0
	_effect_start_time = 0.0

	if _effect_rect:
		_effect_rect.visible = false
		var material := _effect_rect.material as ShaderMaterial
		if material:
			material.set_shader_parameter("intensity", 0.0)


## Called when the scene tree structure changes.
## Used to reset effects when a new scene is loaded.
func _on_tree_changed() -> void:
	var current_scene := get_tree().current_scene
	if current_scene != null and current_scene != _previous_scene_root:
		_previous_scene_root = current_scene
		reset_effects()


## Performs warmup to pre-compile the shader.
## This prevents a shader compilation stutter on first use (Issue #343).
func _warmup_shader() -> void:
	if _effect_rect == null or _effect_rect.material == null:
		return

	_log("Starting shader warmup (Issue #343 fix)...")
	var start_time := Time.get_ticks_msec()

	# Briefly enable the effect rect with zero visual effect
	var material := _effect_rect.material as ShaderMaterial
	if material:
		material.set_shader_parameter("intensity", 0.0)

	_effect_rect.visible = true

	# Wait one frame to ensure GPU processes and compiles the shader
	await get_tree().process_frame

	# Hide the overlay again
	_effect_rect.visible = false

	var elapsed := Time.get_ticks_msec() - start_time
	_log("Shader warmup complete in %d ms" % elapsed)


## Log a message with the FlashbangPlayer prefix.
func _log(message: String) -> void:
	var logger: Node = get_node_or_null("/root/FileLogger")
	if logger and logger.has_method("log_info"):
		logger.log_info("[FlashbangPlayer] " + message)
	else:
		print("[FlashbangPlayer] " + message)
