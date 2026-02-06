extends Node
## PowerFantasyEffectsManager - Manages special effects for Power Fantasy difficulty mode.
##
## This autoload singleton provides:
## 1. "Last chance" effect (300ms) after killing an enemy - penultimate hit effect
## 2. "Special last chance" effect (2000ms) when a grenade explodes - penultimate hit effect
##
## These effects use the penultimate hit system (time slowdown + saturation boost)
## but with shorter durations specific to Power Fantasy mode.

## Duration of the last chance effect when killing an enemy (300ms).
const KILL_EFFECT_DURATION_MS: float = 300.0

## Duration of the special last chance effect when grenade explodes (2000ms).
const GRENADE_EFFECT_DURATION_MS: float = 2000.0

## The slowed down time scale during effects.
const EFFECT_TIME_SCALE: float = 0.1

## Screen saturation multiplier during effect.
const SCREEN_SATURATION_BOOST: float = 2.0

## Screen contrast multiplier during effect.
const SCREEN_CONTRAST_BOOST: float = 1.0

## The CanvasLayer for screen effects.
var _effects_layer: CanvasLayer = null

## The ColorRect with the saturation shader.
var _saturation_rect: ColorRect = null

## Whether the effect is currently active.
var _is_effect_active: bool = false

## Timer for tracking effect duration (uses real time, not game time).
var _effect_start_time: float = 0.0

## Current effect duration in milliseconds.
var _current_effect_duration_ms: float = 0.0

## Tracks the previous scene root to detect scene changes.
var _previous_scene_root: Node = null


func _ready() -> void:
	# Connect to scene tree changes to reset effects on scene reload
	get_tree().tree_changed.connect(_on_tree_changed)

	# Create effects layer (very high layer to render on top of everything)
	_effects_layer = CanvasLayer.new()
	_effects_layer.name = "PowerFantasyEffectsLayer"
	_effects_layer.layer = 103  # Higher than other effects layers
	add_child(_effects_layer)

	# Create saturation overlay
	_saturation_rect = ColorRect.new()
	_saturation_rect.name = "PowerFantasySaturationOverlay"
	_saturation_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_saturation_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Load and apply the saturation shader
	var shader := load("res://scripts/shaders/saturation.gdshader") as Shader
	if shader:
		var material := ShaderMaterial.new()
		material.shader = shader
		material.set_shader_parameter("saturation_boost", 0.0)
		material.set_shader_parameter("contrast_boost", 0.0)
		_saturation_rect.material = material
		_log("Saturation shader loaded successfully")
	else:
		push_warning("PowerFantasyEffectsManager: Could not load saturation shader")
		_log("WARNING: Could not load saturation shader!")

	_saturation_rect.visible = false
	_effects_layer.add_child(_saturation_rect)

	_log("PowerFantasyEffectsManager ready - Configuration:")
	_log("  Kill effect duration: %.0fms" % KILL_EFFECT_DURATION_MS)
	_log("  Grenade effect duration: %.0fms (%.1fs)" % [GRENADE_EFFECT_DURATION_MS, GRENADE_EFFECT_DURATION_MS / 1000.0])


func _process(_delta: float) -> void:
	# Check if effect should end based on real time duration
	if _is_effect_active:
		# Use OS.get_ticks_msec() for real time (not affected by time_scale)
		var current_time := Time.get_ticks_msec() / 1000.0
		var elapsed_real_time := (current_time - _effect_start_time) * 1000.0  # Convert to ms

		if elapsed_real_time >= _current_effect_duration_ms:
			_log("Effect duration expired after %.2f ms" % elapsed_real_time)
			_end_effect()


## Log a message with the PowerFantasy prefix.
func _log(message: String) -> void:
	var logger: Node = get_node_or_null("/root/FileLogger")
	if logger and logger.has_method("log_info"):
		logger.log_info("[PowerFantasy] " + message)
	else:
		print("[PowerFantasy] " + message)


## Called when an enemy is killed by the player in Power Fantasy mode.
## Triggers the 300ms last chance effect.
func on_enemy_killed() -> void:
	var difficulty_manager: Node = get_node_or_null("/root/DifficultyManager")
	if difficulty_manager == null or not difficulty_manager.is_power_fantasy_mode():
		return

	# Issue #505: Skip kill effect if LastChanceEffectsManager is already providing a stronger
	# time-freeze (e.g., from grenade explosion). The kill effect uses Engine.time_scale which
	# conflicts with the node-based freeze: when the kill effect ends after 300ms, it resets
	# Engine.time_scale to 1.0 while the grenade freeze is still active.
	var last_chance_manager: Node = get_node_or_null("/root/LastChanceEffectsManager")
	if last_chance_manager and last_chance_manager.has_method("is_effect_active"):
		if last_chance_manager.is_effect_active():
			_log("Enemy killed - skipping 300ms effect (LastChance time-freeze already active)")
			return

	_log("Enemy killed - triggering 300ms last chance effect")
	_start_effect(KILL_EFFECT_DURATION_MS)


## Called when a grenade explodes in Power Fantasy mode.
## Triggers the full last chance time-freeze effect (like Hard mode) for 2000ms.
func on_grenade_exploded() -> void:
	var difficulty_manager: Node = get_node_or_null("/root/DifficultyManager")
	if difficulty_manager == null or not difficulty_manager.is_power_fantasy_mode():
		return

	_log("Grenade exploded - triggering last chance time-freeze effect for %.0fms" % GRENADE_EFFECT_DURATION_MS)

	# Use LastChanceEffectsManager for the full time-freeze effect (like Hard mode)
	var last_chance_manager: Node = get_node_or_null("/root/LastChanceEffectsManager")
	if last_chance_manager and last_chance_manager.has_method("trigger_grenade_last_chance"):
		last_chance_manager.trigger_grenade_last_chance(GRENADE_EFFECT_DURATION_MS / 1000.0)
	else:
		# Fallback: use simple time-scale effect if LastChanceEffectsManager not available
		_log("WARNING: LastChanceEffectsManager not available, using simple slowdown fallback")
		_start_effect(GRENADE_EFFECT_DURATION_MS)


## Starts the power fantasy effect with the specified duration.
func _start_effect(duration_ms: float) -> void:
	# If effect is already active, reset the timer
	if _is_effect_active:
		_effect_start_time = Time.get_ticks_msec() / 1000.0
		_current_effect_duration_ms = duration_ms
		_log("Effect timer reset to %.0fms" % duration_ms)
		return

	_is_effect_active = true
	_effect_start_time = Time.get_ticks_msec() / 1000.0
	_current_effect_duration_ms = duration_ms

	_log("Starting power fantasy effect:")
	_log("  - Time scale: %.2f" % EFFECT_TIME_SCALE)
	_log("  - Duration: %.0fms" % duration_ms)

	# Slow down time
	Engine.time_scale = EFFECT_TIME_SCALE

	# Apply screen saturation and contrast
	_saturation_rect.visible = true
	var material := _saturation_rect.material as ShaderMaterial
	if material:
		material.set_shader_parameter("saturation_boost", SCREEN_SATURATION_BOOST)
		material.set_shader_parameter("contrast_boost", SCREEN_CONTRAST_BOOST)


## Ends the power fantasy effect.
func _end_effect() -> void:
	if not _is_effect_active:
		return

	_is_effect_active = false
	_log("Ending power fantasy effect")

	# Restore normal time
	Engine.time_scale = 1.0

	# Remove screen saturation and contrast
	_saturation_rect.visible = false
	var material := _saturation_rect.material as ShaderMaterial
	if material:
		material.set_shader_parameter("saturation_boost", 0.0)
		material.set_shader_parameter("contrast_boost", 0.0)


## Resets all effects (useful when restarting the scene).
func reset_effects() -> void:
	_log("Resetting all effects (scene change detected)")

	if _is_effect_active:
		_is_effect_active = false
		# Restore normal time immediately
		Engine.time_scale = 1.0

	# Remove screen saturation and contrast
	_saturation_rect.visible = false
	var material := _saturation_rect.material as ShaderMaterial
	if material:
		material.set_shader_parameter("saturation_boost", 0.0)
		material.set_shader_parameter("contrast_boost", 0.0)


## Called when the scene tree structure changes.
## Used to reset effects when a new scene is loaded.
func _on_tree_changed() -> void:
	var current_scene := get_tree().current_scene
	if current_scene != null and current_scene != _previous_scene_root:
		_previous_scene_root = current_scene
		reset_effects()


## Returns whether the power fantasy effect is currently active.
func is_effect_active() -> bool:
	return _is_effect_active
