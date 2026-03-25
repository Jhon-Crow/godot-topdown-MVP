extends Area2D
## Realistic water body with spring-based physics simulation (Issues #1445, #1495).
##
## Combines:
##   - Spring-column water surface simulation (WaterSurface) for physically reactive waves
##   - A ColorRect (WaterVisual) with the realistic_water.gdshader for ambient wave animation
##   - Area2D physics detection for bodies/objects entering/exiting water
##   - Dynamic splashes: velocity/mass-based surface deformation
##   - Buoyancy forces for RigidBody2D objects (casings, grenades)
##   - Movement drag for CharacterBody2D objects (player, enemies)
##   - Blood diffusion effect (blood spreads in water instead of leaving footprints)
##   - Reactions to shell casings, grenades, explosions, and bullets
##
## WaterVisual, WaterCollision, and WaterSurface are pre-baked in WaterBody.tscn
## so they always exist regardless of script execution order.

class_name WaterBody

## Size of the water rectangle in pixels.
@export var water_width: float = 2400.0
@export var water_height: float = 356.0

## Minimum distance the tracked body must travel before a new splash is spawned.
@export var splash_interval: float = 36.0

## Buoyancy force applied upward to RigidBody2D objects in water.
@export var buoyancy_force: float = 120.0

## Linear drag factor applied to RigidBody2D objects in water.
@export var water_drag: float = 3.0

## Movement speed multiplier for CharacterBody2D objects in water.
@export var movement_speed_factor: float = 0.65

## Script path for the splash effect (loaded at runtime).
const SPLASH_SCRIPT_PATH: String = "res://scripts/effects/water_splash_effect.gd"

## Shader path.
const WATER_SHADER_PATH: String = "res://scripts/shaders/realistic_water.gdshader"

## Blood diffusion effect path.
const BLOOD_DIFFUSION_SCRIPT_PATH: String = "res://scripts/effects/water_blood_diffusion.gd"

## Water surface simulation script path.
const WATER_SURFACE_SCRIPT_PATH: String = "res://scripts/objects/water_surface.gd"

## Pre-baked child nodes from WaterBody.tscn (always present, no add_child needed).
@onready var _visual: ColorRect = $WaterVisual
@onready var _collision: CollisionShape2D = $WaterCollision

## Spring-column water surface simulation node.
var _surface: Node2D = null

## Tracks bodies currently inside the water.
## key: Node → value: Dictionary { "last_pos": Vector2, "velocity": Vector2 }
var _bodies_in_water: Dictionary = {}

## Tracks RigidBody2D objects in water for buoyancy/drag.
## key: Node → value: Dictionary { "original_gravity_scale": float, "original_linear_damp": float }
var _rigid_bodies_in_water: Dictionary = {}

## Preloaded splash script (loaded once).
var _splash_script: GDScript = null

## Preloaded blood diffusion script (loaded once).
var _blood_diffusion_script: GDScript = null

## Track grenades we've already connected to (avoid duplicate signal connections).
var _connected_grenades: Dictionary = {}

## Track casings already processed (avoid duplicate splashes per casing).
var _processed_casings: Dictionary = {}


func _ready() -> void:
	# Update pre-baked node dimensions in case water_width/height were overridden in the scene.
	if _visual != null:
		_visual.position = Vector2(-water_width * 0.5, -water_height * 0.5)
		_visual.size = Vector2(water_width, water_height)
	if _collision != null and _collision.shape is RectangleShape2D:
		(_collision.shape as RectangleShape2D).size = Vector2(water_width, water_height)

	# Apply animated water shader to the pre-baked ColorRect
	_apply_shader()

	# Initialize the spring-column water surface simulation
	_init_water_surface()

	# Detect physics bodies AND rigid bodies:
	# Layer 1 (1) = player, Layer 2 (2) = enemies,
	# Layer 5 (16) = bullets/projectiles
	# Layer 6 (32) = grenades, Layer 7 (64) = casings/blood puddles
	collision_layer = 0
	collision_mask = 0b01110011  # layers 1, 2, 5, 6, 7 = 1+2+16+32+64 = 115

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

	var shader_ok: bool = _visual != null and _visual.material != null
	var surface_ok: bool = _surface != null
	_log("[WaterBody] Ready — visual=%s shader=%s collision=%s splash=%s blood=%s surface=%s" % [
		str(_visual != null),
		"OK" if shader_ok else "FALLBACK",
		str(_collision != null),
		"OK" if _splash_script != null else "MISSING",
		"OK" if _blood_diffusion_script != null else "MISSING",
		"OK" if surface_ok else "MISSING"
	])


func _physics_process(delta: float) -> void:
	# Apply buoyancy and drag to RigidBody2D objects in water
	_apply_buoyancy_forces(delta)


func _process(_delta: float) -> void:
	# Check movement of all bodies currently inside the water.
	for body in _bodies_in_water.keys():
		if not is_instance_valid(body):
			_bodies_in_water.erase(body)
			continue

		var current_pos: Vector2 = body.global_position
		var body_data: Dictionary = _bodies_in_water[body]
		var last_pos: Vector2 = body_data["last_pos"]
		var velocity: Vector2 = current_pos - last_pos

		# Update stored velocity for splash calculations
		body_data["velocity"] = velocity
		_bodies_in_water[body] = body_data

		if current_pos.distance_to(last_pos) >= splash_interval:
			_spawn_splash(current_pos)
			# Disturb the water surface where the body is moving
			if _surface != null and _surface.has_method("splash_from_body"):
				_surface.splash_from_body(current_pos.x, velocity * 3.0, 1.0, 24.0)
			body_data["last_pos"] = current_pos
			_bodies_in_water[body] = body_data
		elif velocity.length() > 1.0 and _surface != null and _surface.has_method("disturb"):
			# Continuous surface disturbance for moving bodies
			_surface.disturb(current_pos.x, velocity.length() * 0.3)

	# Suppress bloody footprints for characters inside water
	_suppress_bloody_footprints()

	# Clean up stale grenade references
	_cleanup_grenades()


## Initialize the spring-column water surface simulation.
func _init_water_surface() -> void:
	if not ResourceLoader.exists(WATER_SURFACE_SCRIPT_PATH):
		push_warning("[WaterBody] WaterSurface script not found — spring physics disabled")
		return

	var surface_script: GDScript = load(WATER_SURFACE_SCRIPT_PATH)
	if surface_script == null:
		push_warning("[WaterBody] Failed to load WaterSurface script")
		return

	_surface = Node2D.new()
	_surface.set_script(surface_script)
	_surface.name = "WaterSurface"
	# Position at the top edge of the water body (surface line)
	_surface.set("surface_width", water_width)
	_surface.set("surface_depth", water_height * 0.5)
	add_child(_surface)
	# Position relative to WaterBody center — surface sits at the top edge
	_surface.position = Vector2(0, -water_height * 0.5)
	_surface.z_index = 2  # Above WaterVisual (z=1) so deformed surface is visible


## Apply the animated water shader to the WaterVisual ColorRect.
func _apply_shader() -> void:
	if _visual == null:
		push_warning("[WaterBody] WaterVisual node not found — water will show as plain blue")
		return

	if ResourceLoader.exists(WATER_SHADER_PATH):
		var shader: Shader = load(WATER_SHADER_PATH)
		if shader != null:
			var mat := ShaderMaterial.new()
			mat.shader = shader
			_visual.material = mat
		else:
			push_warning("[WaterBody] Shader resource null — using plain colour fallback")
	else:
		push_warning("[WaterBody] Water shader not found — using plain colour fallback")


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
	_bodies_in_water[body] = { "last_pos": body.global_position, "velocity": Vector2.ZERO }
	_spawn_splash(body.global_position)

	# Create entry splash on water surface based on body velocity
	if _surface != null and _surface.has_method("splash_from_body"):
		var entry_velocity: Vector2 = Vector2.ZERO
		if body is CharacterBody2D:
			entry_velocity = body.velocity
		elif body is RigidBody2D:
			entry_velocity = body.linear_velocity
		if entry_velocity.length() < 50.0:
			entry_velocity = Vector2(0, 80.0)  # Minimum entry splash
		_surface.splash_from_body(body.global_position.x, entry_velocity, 1.0, 30.0)

	# Suppress bloody footprints immediately when entering water
	_suppress_footprints_on_body(body)


func _on_body_exited(body: Node2D) -> void:
	# Create exit splash on the water surface
	if _surface != null and _surface.has_method("splash_from_body"):
		var exit_velocity: Vector2 = Vector2.ZERO
		if body is CharacterBody2D:
			exit_velocity = body.velocity
		elif body is RigidBody2D:
			exit_velocity = body.linear_velocity
		if exit_velocity.length() > 20.0:
			_surface.splash_from_body(body.global_position.x, exit_velocity * 0.5, 1.0, 20.0)

	_bodies_in_water.erase(body)

	# Restore RigidBody2D physics if it was tracked
	if body in _rigid_bodies_in_water:
		_restore_rigid_body(body)


func _on_area_entered(area: Area2D) -> void:
	# Detect blood puddles entering the water zone and create diffusion effect
	if area.is_in_group("blood_puddle") or (area.get_parent() and area.get_parent().is_in_group("blood_puddle")):
		var blood_node: Node2D = area if area is Sprite2D else area.get_parent() as Node2D
		if blood_node and blood_node is Sprite2D:
			_spawn_blood_diffusion(blood_node.global_position, blood_node.modulate)

	# Detect bullets (Area2D on layer 5) entering water
	if area.is_in_group("bullets") or area.get("collision_layer") == 16:
		_on_bullet_entered(area)


## Handle bullet entering water — small splash + surface disturbance.
func _on_bullet_entered(bullet: Area2D) -> void:
	var bullet_pos: Vector2 = bullet.global_position
	_spawn_splash_small(bullet_pos)

	# Disturb surface at bullet impact point
	if _surface != null and _surface.has_method("splash"):
		var speed: float = 100.0  # Default bullet splash force
		# Try to get bullet velocity for more accurate splash
		if bullet.get("velocity") != null:
			speed = bullet.get("velocity").length() * 0.05
		elif bullet.get("speed") != null:
			speed = float(bullet.get("speed")) * 0.03
		_surface.splash(bullet_pos.x, clampf(speed, 30.0, 80.0), 0.5)


## Handle grenade entering water — splash on entry, connect for explosion.
func _on_grenade_entered(grenade: Node2D) -> void:
	_spawn_splash(grenade.global_position)

	# Create surface splash from grenade velocity
	if _surface != null and grenade is RigidBody2D:
		var vel: Vector2 = (grenade as RigidBody2D).linear_velocity
		if _surface.has_method("splash_from_body"):
			_surface.splash_from_body(grenade.global_position.x, vel, 2.0, 15.0)

	# Apply buoyancy to grenade
	if grenade is RigidBody2D:
		_apply_water_physics_to_rigid_body(grenade as RigidBody2D)

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
		# Create large explosion wave on the spring surface
		if _surface != null and _surface.has_method("explosion_splash"):
			_surface.explosion_splash(explosion_pos.x, 120.0, 300.0)


## Handle casing falling into water.
func _on_casing_entered(casing: Node2D) -> void:
	var casing_id := casing.get_instance_id()
	if casing_id in _processed_casings:
		return
	_processed_casings[casing_id] = true
	_spawn_splash_small(casing.global_position)

	# Disturb surface at casing impact point
	if _surface != null and casing is RigidBody2D:
		var vel: Vector2 = (casing as RigidBody2D).linear_velocity
		if _surface.has_method("splash_from_body"):
			_surface.splash_from_body(casing.global_position.x, vel, 0.3, 5.0)

	# Apply water physics to casing (slow it down and make it float)
	if casing is RigidBody2D:
		_apply_water_physics_to_rigid_body(casing as RigidBody2D)


## Apply water physics (reduced gravity + drag) to a RigidBody2D.
func _apply_water_physics_to_rigid_body(body: RigidBody2D) -> void:
	if body in _rigid_bodies_in_water:
		return  # Already tracked

	_rigid_bodies_in_water[body] = {
		"original_gravity_scale": body.gravity_scale,
		"original_linear_damp": body.linear_damp
	}
	# Reduce gravity and increase drag in water
	body.gravity_scale = body.gravity_scale * 0.1
	body.linear_damp = water_drag


## Restore a RigidBody2D to its original physics when leaving water.
func _restore_rigid_body(body: Node2D) -> void:
	if body not in _rigid_bodies_in_water:
		return
	var data: Dictionary = _rigid_bodies_in_water[body]
	if body is RigidBody2D:
		(body as RigidBody2D).gravity_scale = data["original_gravity_scale"]
		(body as RigidBody2D).linear_damp = data["original_linear_damp"]
	_rigid_bodies_in_water.erase(body)


## Apply buoyancy forces to all RigidBody2D objects currently in water.
func _apply_buoyancy_forces(delta: float) -> void:
	var to_remove: Array = []
	for body in _rigid_bodies_in_water.keys():
		if not is_instance_valid(body):
			to_remove.append(body)
			continue
		if body is RigidBody2D:
			var rb: RigidBody2D = body as RigidBody2D
			# Apply upward buoyancy force
			rb.apply_central_force(Vector2(0, -buoyancy_force * delta * 60.0))

			# Continuously disturb surface while the rigid body is moving
			if _surface != null and _surface.has_method("disturb"):
				var speed: float = rb.linear_velocity.length()
				if speed > 5.0:
					_surface.disturb(rb.global_position.x, speed * 0.05)

	for body in to_remove:
		_rigid_bodies_in_water.erase(body)


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
	var splash_node: Node2D = Node2D.new()
	splash_node.set_script(_splash_script)
	# Position relative to this node's parent so global_position works
	get_parent().add_child(splash_node)
	splash_node.global_position = world_pos


## Spawn a small splash (for casings, bullets, and small objects).
func _spawn_splash_small(world_pos: Vector2) -> void:
	if _splash_script == null:
		return
	var splash_node: Node2D = Node2D.new()
	splash_node.set_script(_splash_script)
	get_parent().add_child(splash_node)
	splash_node.global_position = world_pos
	# Configure for small splash after adding to tree
	if splash_node.has_method("configure_small"):
		splash_node.configure_small()


## Spawn a large splash (for grenade explosions).
func _spawn_splash_large(world_pos: Vector2) -> void:
	if _splash_script == null:
		return
	var splash_node: Node2D = Node2D.new()
	splash_node.set_script(_splash_script)
	get_parent().add_child(splash_node)
	splash_node.global_position = world_pos
	# Configure for large splash after adding to tree
	if splash_node.has_method("configure_large"):
		splash_node.configure_large()


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


## Log a message via the FileLogger autoload (mirrors beach_level.gd pattern).
func _log(message: String) -> void:
	print(message)
	var file_logger: Node = get_node_or_null("/root/FileLogger")
	if file_logger and file_logger.has_method("log_info"):
		file_logger.log_info(message)


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
