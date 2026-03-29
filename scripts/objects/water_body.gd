extends Area2D
## Realistic water body for the Beach level (Issue #1445, enhanced Issue #1550).
##
## Combines:
##   - A ColorRect (WaterVisual) with the realistic_water.gdshader for visual waves
##     including animated surf-foam streaks marching toward the shore (Issue #1550)
##   - Wave interruption by player/enemies: positions are pushed to the shader each
##     frame so wave amplitude is attenuated around obstacles — same concept as
##     LightOccluder2D blocking light rays (Issue #1550)
##   - Area2D physics detection to spawn WaterSplashEffect when bodies/objects interact
##   - Blood diffusion effect (blood spreads in water instead of leaving footprints)
##   - Reactions to shell casings, grenades, and explosions
##
## WaterVisual and WaterCollision are pre-baked in WaterBody.tscn so they
## always exist regardless of script execution order.

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

## Pre-baked child nodes from WaterBody.tscn (always present, no add_child needed).
@onready var _visual: ColorRect = $WaterVisual
@onready var _collision: CollisionShape2D = $WaterCollision

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

## Maximum number of obstacle positions passed to the shader (must match shader array size).
const MAX_OBSTACLE_SHADER_SLOTS: int = 8

## Throttle: only push obstacle UVs to shader every N frames to save GPU upload cost.
var _obstacle_update_frame: int = 0
const OBSTACLE_UPDATE_INTERVAL: int = 6  # update every 6 frames — bodies rarely need sub-6-frame precision

## True when shader obstacle params need to be re-uploaded (body entered/exited).
var _obstacle_dirty: bool = false

## Whether time is currently stopped (e.g. last chance effect). When true,
## wave animation is paused by setting shader speed parameters to zero.
var _time_stopped: bool = false

## Stored shader speed values to restore after time resumes.
var _saved_wave_speed: float = 0.0
var _saved_ripple_speed: float = 0.0
var _saved_surf_speed: float = 0.0
var _saved_distortion_strength: float = 0.0


func _ready() -> void:
	# Register in group so LastChanceEffectsManager can find this node reliably
	# (script resource_path may be empty in exported builds).
	add_to_group("precipitation_effects")
	# Update pre-baked node dimensions in case water_width/height were overridden in the scene.
	if _visual != null:
		_visual.position = Vector2(-water_width * 0.5, -water_height * 0.5)
		_visual.size = Vector2(water_width, water_height)
	if _collision != null and _collision.shape is RectangleShape2D:
		(_collision.shape as RectangleShape2D).size = Vector2(water_width, water_height)

	# Apply animated water shader to the pre-baked ColorRect
	_apply_shader()

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

	var shader_ok: bool = _visual != null and _visual.material != null
	_log("[WaterBody] Ready — visual=%s shader=%s collision=%s splash=%s blood=%s" % [
		str(_visual != null),
		"OK" if shader_ok else "FALLBACK",
		str(_collision != null),
		"OK" if _splash_script != null else "MISSING",
		"OK" if _blood_diffusion_script != null else "MISSING"
	])


func _process(_delta: float) -> void:
	# Skip all per-body work when no bodies are in water — avoids unnecessary
	# CPU iteration and GPU uploads that caused a stutter on first entry (Issue #1573).
	if not _bodies_in_water.is_empty():
		# Check movement of all bodies currently inside the water.
		for body in _bodies_in_water.keys():
			if not is_instance_valid(body):
				_bodies_in_water.erase(body)
				_obstacle_dirty = true
				continue

			var current_pos: Vector2 = body.global_position
			var last_pos: Vector2 = _bodies_in_water[body]
			if current_pos.distance_to(last_pos) >= splash_interval:
				_spawn_splash(current_pos)
				_bodies_in_water[body] = current_pos

		# Suppress bloody footprints for characters inside water
		_suppress_bloody_footprints()

		# Push obstacle positions to shader for wave interruption (Issue #1550).
		# Only re-upload when dirty (body entered/exited) OR on the throttle interval.
		_obstacle_update_frame += 1
		if _obstacle_dirty or _obstacle_update_frame >= OBSTACLE_UPDATE_INTERVAL:
			_obstacle_update_frame = 0
			_obstacle_dirty = false
			_update_obstacle_shader_params()

	# Clean up stale grenade references — skip when no grenades tracked.
	if not _connected_grenades.is_empty():
		_cleanup_grenades()


## Push current body positions inside water to the shader as UV-space coordinates.
## This implements wave interruption by obstacles — the shader attenuates wave
## amplitude within a radius around each UV position, mirroring the way
## LightOccluder2D nodes block light rays (Issue #1550).
func _update_obstacle_shader_params() -> void:
	if _visual == null or not (_visual.material is ShaderMaterial):
		return
	var mat: ShaderMaterial = _visual.material as ShaderMaterial

	# Collect valid body positions (up to MAX_OBSTACLE_SHADER_SLOTS)
	var uvs: Array[Vector2] = []
	for body in _bodies_in_water.keys():
		if not is_instance_valid(body):
			continue
		# Skip grenades and casings — only player/enemy bodies cast "wave shadows"
		if body.is_in_group("grenades") or body.is_in_group("casings"):
			continue
		var world_pos: Vector2 = body.global_position
		# Convert world position → UV space [0..1] within the water rectangle.
		# The water rectangle: centre = global_position, size = water_width × water_height
		var local: Vector2 = world_pos - global_position
		var uv: Vector2 = Vector2(
			(local.x + water_width * 0.5) / water_width,
			(local.y + water_height * 0.5) / water_height
		)
		# Clamp to valid UV range
		uv = uv.clamp(Vector2.ZERO, Vector2.ONE)
		uvs.append(uv)
		if uvs.size() >= MAX_OBSTACLE_SHADER_SLOTS:
			break

	# The shader expects exactly MAX_OBSTACLE_SHADER_SLOTS entries in the array.
	# Pad with out-of-range UVs (e.g. (-1,-1)) so unused slots don't affect rendering.
	while uvs.size() < MAX_OBSTACLE_SHADER_SLOTS:
		uvs.append(Vector2(-1.0, -1.0))

	mat.set_shader_parameter("obstacle_count", mini(uvs.size(), MAX_OBSTACLE_SHADER_SLOTS))
	mat.set_shader_parameter("obstacle_uvs", uvs)


## Apply the animated water shader to the WaterVisual ColorRect.
## If a ShaderMaterial is already pre-assigned in the scene (WaterBody.tscn),
## it is used as-is — no dynamic load needed.  The dynamic path is kept as a
## fallback for editor-only use and to satisfy re-instantiation edge cases.
func _apply_shader() -> void:
	if _visual == null:
		_log("[WaterBody] ERROR: WaterVisual node not found — water will show as plain blue")
		return

	# Fast path: shader material was pre-baked into the scene — just use it.
	if _visual.material is ShaderMaterial:
		_log("[WaterBody] Shader pre-assigned in scene — using existing ShaderMaterial")
		return

	# Fallback: try to load the shader at runtime (editor / non-exported builds).
	if ResourceLoader.exists(WATER_SHADER_PATH):
		var shader: Shader = load(WATER_SHADER_PATH)
		if shader != null:
			var mat := ShaderMaterial.new()
			mat.shader = shader
			_visual.material = mat
			_log("[WaterBody] Shader loaded at runtime from: " + WATER_SHADER_PATH)
		else:
			_log("[WaterBody] ERROR: Shader resource null at runtime — using plain colour fallback")
	else:
		_log("[WaterBody] ERROR: Shader file not found at runtime (%s) — using plain colour fallback" % WATER_SHADER_PATH)


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
	_obstacle_dirty = true
	_spawn_splash(body.global_position)

	# Suppress bloody footprints immediately when entering water
	_suppress_footprints_on_body(body)


func _on_body_exited(body: Node2D) -> void:
	_bodies_in_water.erase(body)
	_obstacle_dirty = true


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


## Pauses or resumes wave animation for time-stop effects (e.g. last chance).
## When paused is true, all three shader speed parameters are set to zero so the
## water surface appears frozen. When paused is false, the original speed values
## are restored. The splash/physics detection is not affected.
func set_time_stopped(paused: bool) -> void:
	if _time_stopped == paused:
		return
	_time_stopped = paused
	if _visual == null or not (_visual.material is ShaderMaterial):
		return
	var mat: ShaderMaterial = _visual.material as ShaderMaterial
	if paused:
		# Save current speed values then set to zero.
		_saved_wave_speed = mat.get_shader_parameter("wave_speed")
		_saved_ripple_speed = mat.get_shader_parameter("ripple_speed")
		_saved_surf_speed = mat.get_shader_parameter("surf_speed")
		_saved_distortion_strength = mat.get_shader_parameter("distortion_strength")
		mat.set_shader_parameter("wave_speed", 0.0)
		mat.set_shader_parameter("ripple_speed", 0.0)
		mat.set_shader_parameter("surf_speed", 0.0)
		mat.set_shader_parameter("distortion_strength", 0.0)
		_log("[WaterBody] Wave animation paused (time stopped)")
	else:
		# Restore saved speed values.
		mat.set_shader_parameter("wave_speed", _saved_wave_speed)
		mat.set_shader_parameter("ripple_speed", _saved_ripple_speed)
		mat.set_shader_parameter("surf_speed", _saved_surf_speed)
		mat.set_shader_parameter("distortion_strength", _saved_distortion_strength)
		_log("[WaterBody] Wave animation resumed (time resumed)")


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
