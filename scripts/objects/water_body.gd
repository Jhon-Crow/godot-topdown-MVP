extends Area2D
## Realistic water body for the Beach level (Issue #1445).
##
## Combines:
##   - A ColorRect with the realistic_water.gdshader for visual waves
##   - Area2D physics detection to spawn WaterSplashEffect when bodies/objects interact
##   - Blood diffusion effect (blood spreads in water instead of leaving footprints)
##   - Reactions to shell casings, grenades, and explosions
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

## Blood diffusion effect path.
const BLOOD_DIFFUSION_SCRIPT_PATH: String = "res://scripts/effects/water_blood_diffusion.gd"

## Internal nodes created in _ready.
var _visual: ColorRect = null
var _collision: CollisionShape2D = null

## Tracks bodies currently inside the water.
## key: Node → value: last_position (Vector2)
var _bodies_in_water: Dictionary = {}

## Preloaded splash script (loaded once).
var _splash_script: GDScript = null

## Preloaded blood diffusion script (loaded once).
var _blood_diffusion_script: GDScript = null

## Track grenades we've already connected to (avoid duplicate signal connections).
var _connected_grenades: Dictionary = {}

## Track casings already processed (avoid duplicate splashes per casing).
var _processed_casings: Dictionary = {}


func _ready() -> void:
	_create_visual()
	_create_collision()

	# Detect physics bodies AND rigid bodies:
	# Layer 1 (1) = player, Layer 2 (2) = enemies,
	# Layer 6 (32) = grenades, Layer 7 (64) = casings/blood puddles
	collision_layer = 0
	collision_mask = 0b01100011  # layers 1, 2, 6, 7 = 1+2+32+64 = 99

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	area_entered.connect(_on_area_entered)

	# Preload splash script
	if ResourceLoader.exists(SPLASH_SCRIPT_PATH):
		_splash_script = load(SPLASH_SCRIPT_PATH)
	else:
		push_warning("[WaterBody] Splash script not found at %s" % SPLASH_SCRIPT_PATH)

	# Preload blood diffusion script
	if ResourceLoader.exists(BLOOD_DIFFUSION_SCRIPT_PATH):
		_blood_diffusion_script = load(BLOOD_DIFFUSION_SCRIPT_PATH)


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

	# Suppress bloody footprints for characters inside water
	_suppress_bloody_footprints()

	# Clean up stale grenade references
	_cleanup_grenades()


func _create_visual() -> void:
	_visual = ColorRect.new()
	_visual.name = "WaterVisual"
	_visual.offset_left   = -water_width  * 0.5
	_visual.offset_top    = -water_height * 0.5
	_visual.offset_right  =  water_width  * 0.5
	_visual.offset_bottom =  water_height * 0.5
	# Set base color to transparent — shader fully controls the visual
	_visual.color = Color(0.0, 0.0, 0.0, 0.0)
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
		_visual.color = Color(0.15, 0.55, 0.85, 0.88)

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

	# Check if this is a grenade (RigidBody2D on layer 6)
	if body.is_in_group("grenades") or body.get("collision_layer") == 32:
		_on_grenade_entered(body)
		return

	# Check if this is a casing (RigidBody2D on layer 7)
	if body.is_in_group("casings") or (body is RigidBody2D and body.get("collision_layer") == 64):
		_on_casing_entered(body)
		return

	# Regular body (player/enemy)
	_bodies_in_water[body] = body.global_position
	_spawn_splash(body.global_position)

	# Suppress bloody footprints immediately when entering water
	_suppress_footprints_on_body(body)


func _on_body_exited(body: Node2D) -> void:
	_bodies_in_water.erase(body)


func _on_area_entered(area: Area2D) -> void:
	# Detect blood puddles entering the water zone and create diffusion effect
	if area.is_in_group("blood_puddle") or (area.get_parent() and area.get_parent().is_in_group("blood_puddle")):
		var blood_node: Node2D = area if area is Sprite2D else area.get_parent() as Node2D
		if blood_node and blood_node is Sprite2D:
			_spawn_blood_diffusion(blood_node.global_position, blood_node.modulate)


## Handle grenade entering water — splash on entry, connect for explosion.
func _on_grenade_entered(grenade: Node2D) -> void:
	_spawn_splash(grenade.global_position)

	# Connect to explosion signal if available and not already connected
	var grenade_id := grenade.get_instance_id()
	if grenade_id not in _connected_grenades:
		if grenade.has_signal("exploded"):
			grenade.exploded.connect(_on_grenade_exploded)
			_connected_grenades[grenade_id] = grenade


## Handle grenade explosion in water.
func _on_grenade_exploded(explosion_pos: Vector2, _grenade: Node2D) -> void:
	# Check if explosion is within our water area
	if _is_point_in_water(explosion_pos):
		_spawn_splash_large(explosion_pos)


## Handle casing falling into water.
func _on_casing_entered(casing: Node2D) -> void:
	var casing_id := casing.get_instance_id()
	if casing_id in _processed_casings:
		return
	_processed_casings[casing_id] = true
	_spawn_splash_small(casing.global_position)


## Check if a world position is within the water area bounds.
func _is_point_in_water(world_pos: Vector2) -> bool:
	var local_pos: Vector2 = world_pos - global_position
	var half_w: float = water_width * 0.5
	var half_h: float = water_height * 0.5
	return abs(local_pos.x) <= half_w and abs(local_pos.y) <= half_h


## Suppress bloody footprints for all characters currently in water.
func _suppress_bloody_footprints() -> void:
	for body in _bodies_in_water.keys():
		if not is_instance_valid(body):
			continue
		_suppress_footprints_on_body(body)


## Suppress bloody footprints on a specific body by resetting blood level.
func _suppress_footprints_on_body(body: Node2D) -> void:
	# Find BloodyFeetComponent on this body
	var bloody_feet: Node = body.get_node_or_null("BloodyFeetComponent")
	if bloody_feet and bloody_feet.has_method("has_bloody_feet"):
		if bloody_feet.has_bloody_feet():
			# Spawn blood diffusion in water instead of footprints
			var blood_col: Color = bloody_feet.get("_blood_color") if bloody_feet.get("_blood_color") != null else Color(0.545, 0.0, 0.0, 1.0)
			_spawn_blood_diffusion(body.global_position, blood_col)
			# Reset blood level so no footprints are spawned
			if bloody_feet.has_method("set_blood_level"):
				bloody_feet.set_blood_level(0)


## Spawn a standard splash at a world position.
func _spawn_splash(world_pos: Vector2) -> void:
	if _splash_script == null:
		return
	var splash: Node2D = Node2D.new()
	splash.set_script(_splash_script)
	# Position relative to this node's parent so global_position works
	get_parent().add_child(splash)
	splash.global_position = world_pos


## Spawn a small splash (for casings and small objects).
func _spawn_splash_small(world_pos: Vector2) -> void:
	if _splash_script == null:
		return
	var splash: Node2D = Node2D.new()
	splash.set_script(_splash_script)
	get_parent().add_child(splash)
	splash.global_position = world_pos
	# Configure for small splash after adding to tree
	if splash.has_method("configure_small"):
		splash.configure_small()


## Spawn a large splash (for grenade explosions).
func _spawn_splash_large(world_pos: Vector2) -> void:
	if _splash_script == null:
		return
	var splash: Node2D = Node2D.new()
	splash.set_script(_splash_script)
	get_parent().add_child(splash)
	splash.global_position = world_pos
	# Configure for large splash after adding to tree
	if splash.has_method("configure_large"):
		splash.configure_large()


## Spawn blood diffusion effect in water at a position.
func _spawn_blood_diffusion(world_pos: Vector2, blood_color: Color) -> void:
	if _blood_diffusion_script == null:
		return
	var diffusion: Node2D = Node2D.new()
	diffusion.set_script(_blood_diffusion_script)
	get_parent().add_child(diffusion)
	diffusion.global_position = world_pos
	if diffusion.has_method("set_blood_color"):
		diffusion.set_blood_color(blood_color)


## Clean up references to freed grenades.
func _cleanup_grenades() -> void:
	var to_remove: Array = []
	for grenade_id in _connected_grenades.keys():
		var grenade = _connected_grenades[grenade_id]
		if not is_instance_valid(grenade):
			to_remove.append(grenade_id)
	for grenade_id in to_remove:
		_connected_grenades.erase(grenade_id)

	# Also clean up processed casings periodically
	if _processed_casings.size() > 200:
		var keys := _processed_casings.keys()
		for i in range(100):
			_processed_casings.erase(keys[i])
