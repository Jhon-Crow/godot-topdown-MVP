extends Area2D
## Realistic water body for the Beach level (Issue #1445).
##
## Combines:
##   - A ColorRect with the realistic_water.gdshader for visual waves + refraction
##   - Area2D physics detection to spawn WaterSplashEffect when bodies move through it
##
## Exported properties allow tuning width/height from the scene editor or
## from beach_level.gd at runtime.

class_name WaterBody

## Size of the water rectangle in pixels.
@export var water_width: float = 2400.0
@export var water_height: float = 356.0

## Minimum distance the tracked body must travel before a new splash is spawned.
@export var splash_interval: float = 36.0

## Script path for the splash effect (loaded at runtime).
const SPLASH_SCRIPT_PATH: String = "res://scripts/effects/water_splash_effect.gd"

## Shader path.
const WATER_SHADER_PATH: String = "res://scripts/shaders/realistic_water.gdshader"

## Internal nodes created in _ready.
var _visual: ColorRect = null
var _collision: CollisionShape2D = null

## Tracks bodies currently inside the water.
## key: Node → value: last_position (Vector2)
var _bodies_in_water: Dictionary = {}

## Preloaded splash script (loaded once).
var _splash_script: GDScript = null


func _ready() -> void:
	_create_visual()
	_create_collision()

	# Detect all physics bodies (players, enemies, …)
	collision_layer = 0
	collision_mask = 0b0011  # layers 1 (player) and 2 (enemy)

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	# Preload splash script
	if ResourceLoader.exists(SPLASH_SCRIPT_PATH):
		_splash_script = load(SPLASH_SCRIPT_PATH)
	else:
		push_warning("[WaterBody] Splash script not found at %s" % SPLASH_SCRIPT_PATH)


func _process(_delta: float) -> void:
	# Check movement of all bodies currently inside the water.
	for body in _bodies_in_water.keys():
		if not is_instance_valid(body):
			_bodies_in_water.erase(body)
			continue

		var current_pos: Vector2 = body.global_position
		var last_pos: Vector2 = _bodies_in_water[body]
		if current_pos.distance_to(last_pos) >= splash_interval:
			_spawn_splash(current_pos)
			_bodies_in_water[body] = current_pos


func _create_visual() -> void:
	_visual = ColorRect.new()
	_visual.name = "WaterVisual"
	_visual.offset_left   = -water_width  * 0.5
	_visual.offset_top    = -water_height * 0.5
	_visual.offset_right  =  water_width  * 0.5
	_visual.offset_bottom =  water_height * 0.5
	_visual.z_index = 1

	# Apply water shader if available
	if ResourceLoader.exists(WATER_SHADER_PATH):
		var shader: Shader = load(WATER_SHADER_PATH)
		var mat := ShaderMaterial.new()
		mat.shader = shader
		_visual.material = mat
	else:
		# Fallback: simple semi-transparent blue rectangle
		push_warning("[WaterBody] Water shader not found — using plain colour fallback")
		_visual.color = Color(0.18, 0.58, 0.90, 0.78)

	add_child(_visual)


func _create_collision() -> void:
	_collision = CollisionShape2D.new()
	_collision.name = "WaterCollision"
	var rect := RectangleShape2D.new()
	rect.size = Vector2(water_width, water_height)
	_collision.shape = rect
	add_child(_collision)


func _on_body_entered(body: Node2D) -> void:
	if body == null:
		return
	_bodies_in_water[body] = body.global_position
	_spawn_splash(body.global_position)


func _on_body_exited(body: Node2D) -> void:
	_bodies_in_water.erase(body)


func _spawn_splash(world_pos: Vector2) -> void:
	if _splash_script == null:
		return
	var splash: Node2D = Node2D.new()
	splash.set_script(_splash_script)
	# Position relative to this node's parent so global_position works
	get_parent().add_child(splash)
	splash.global_position = world_pos
