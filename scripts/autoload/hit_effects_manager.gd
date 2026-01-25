extends Node
## Autoload singleton for managing hit feedback effects.
##
## When the player hits an enemy:
## - Game speed slows to 0.8 (subtle slowdown) for 3 seconds
## - Screen saturation increases for 3 seconds

## The slowed down time scale when hit effect is active.
const SLOW_TIME_SCALE: float = 0.8

## Duration of the time slowdown effect in seconds.
const SLOW_DURATION: float = 3.0

## Duration of the saturation boost effect in seconds.
const SATURATION_DURATION: float = 3.0

## How much extra saturation to add (0.0 = normal, 1.0 = double saturation).
const SATURATION_BOOST: float = 0.4

## The CanvasLayer for screen effects.
var _effects_layer: CanvasLayer = null

## The ColorRect with the saturation shader.
var _saturation_rect: ColorRect = null

## Timer for time slowdown effect.
var _slow_timer: float = 0.0

## Timer for saturation boost effect.
var _saturation_timer: float = 0.0

## Whether the time slowdown effect is currently active.
var _is_slow_active: bool = false

## Whether the saturation boost effect is currently active.
var _is_saturation_active: bool = false


func _ready() -> void:
	# Connect to scene tree changes to reset effects on scene reload
	get_tree().tree_changed.connect(_on_tree_changed)

	# Create effects layer (high layer to render on top)
	_effects_layer = CanvasLayer.new()
	_effects_layer.name = "HitEffectsLayer"
	_effects_layer.layer = 100
	add_child(_effects_layer)

	# Create saturation overlay
	_saturation_rect = ColorRect.new()
	_saturation_rect.name = "SaturationOverlay"
	_saturation_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_saturation_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Load and apply the saturation shader
	var shader := load("res://scripts/shaders/saturation.gdshader") as Shader
	if shader:
		var material := ShaderMaterial.new()
		material.shader = shader
		material.set_shader_parameter("saturation_boost", 0.0)
		_saturation_rect.material = material
	else:
		push_warning("HitEffectsManager: Could not load saturation shader")

	_saturation_rect.visible = false
	_effects_layer.add_child(_saturation_rect)

	# Perform shader warmup to prevent first-shot lag (Issue #343)
	# This pre-compiles the saturation shader during loading
	_warmup_saturation_shader()


func _process(delta: float) -> void:
	# Use unscaled delta for timers so they run correctly regardless of time_scale
	# When time_scale is 0.9, we want 3 real seconds, not 3 scaled seconds
	var unscaled_delta := delta / Engine.time_scale if Engine.time_scale > 0 else delta

	# Process time slowdown effect
	if _is_slow_active:
		_slow_timer -= unscaled_delta
		if _slow_timer <= 0.0:
			_end_slow_effect()

	# Process saturation boost effect
	if _is_saturation_active:
		_saturation_timer -= unscaled_delta
		if _saturation_timer <= 0.0:
			_end_saturation_effect()


## Called when the player successfully hits an enemy.
## Triggers both the time slowdown and saturation boost effects.
func on_player_hit_enemy() -> void:
	_start_slow_effect()
	_start_saturation_effect()


## Starts or resets the time slowdown effect.
func _start_slow_effect() -> void:
	_slow_timer = SLOW_DURATION
	if not _is_slow_active:
		_is_slow_active = true
		Engine.time_scale = SLOW_TIME_SCALE


## Ends the time slowdown effect.
func _end_slow_effect() -> void:
	_is_slow_active = false
	Engine.time_scale = 1.0


## Starts or resets the saturation boost effect.
func _start_saturation_effect() -> void:
	_saturation_timer = SATURATION_DURATION
	if not _is_saturation_active:
		_is_saturation_active = true
		_saturation_rect.visible = true
		var material := _saturation_rect.material as ShaderMaterial
		if material:
			material.set_shader_parameter("saturation_boost", SATURATION_BOOST)


## Ends the saturation boost effect.
func _end_saturation_effect() -> void:
	_is_saturation_active = false
	_saturation_rect.visible = false
	var material := _saturation_rect.material as ShaderMaterial
	if material:
		material.set_shader_parameter("saturation_boost", 0.0)


## Resets all effects (useful when restarting the scene).
func reset_effects() -> void:
	_end_slow_effect()
	_end_saturation_effect()
	_slow_timer = 0.0
	_saturation_timer = 0.0


## Tracks the previous scene root to detect scene changes.
var _previous_scene_root: Node = null


## Called when the scene tree structure changes.
## Used to reset effects when a new scene is loaded.
func _on_tree_changed() -> void:
	var current_scene := get_tree().current_scene
	if current_scene != null and current_scene != _previous_scene_root:
		_previous_scene_root = current_scene
		reset_effects()


## Performs warmup to pre-compile the saturation shader.
## This prevents a shader compilation stutter on first hit (Issue #343).
##
## The saturation shader uses hint_screen_texture which requires specific
## framebuffer setup. By briefly enabling and rendering the shader during
## loading, we force the GPU to compile it before gameplay begins.
func _warmup_saturation_shader() -> void:
	if _saturation_rect == null or _saturation_rect.material == null:
		return

	print("[HitEffectsManager] Starting saturation shader warmup (Issue #343 fix)...")
	var start_time := Time.get_ticks_msec()

	# Briefly enable the saturation rect with zero boost (invisible effect)
	# This forces the GPU to compile the shader
	var material := _saturation_rect.material as ShaderMaterial
	if material:
		# Set boost to 0 so there's no visible effect during warmup
		material.set_shader_parameter("saturation_boost", 0.0)

	_saturation_rect.visible = true

	# Wait one frame to ensure GPU processes and compiles the shader
	await get_tree().process_frame

	# Hide the overlay again
	_saturation_rect.visible = false

	var elapsed := Time.get_ticks_msec() - start_time
	print("[HitEffectsManager] Saturation shader warmup complete in %d ms" % elapsed)
