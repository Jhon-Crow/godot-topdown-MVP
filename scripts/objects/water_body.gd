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
var _captured_water_time: float = 0.0

## Water pigment tint from blood diffusion events. Stored as world-space source
## positions so waves near the cloud can become redder without tinting the whole sea.
const MAX_BLOOD_TINT_SHADER_SLOTS: int = 8
const BLOOD_TINT_DURATION: float = 75.0
const BLOOD_TINT_HOLD_DURATION: float = 62.0
var _blood_tint_sources: Array[Dictionary] = []

## Live tint sources updated each frame during cloud fade (key = position hash).
## Each entry: { "position", "color", "intensity", "current_strength", "settled" }
var _live_tint_sources: Array[Dictionary] = []


func _ready() -> void:
	# Unconditional early log — confirms this script's _ready() is running in the build (Issue #1578).
	_log("[WaterBody] _ready() start — registering groups")
	# Register in group so ImpactEffectsManager can locate this node by group query (Issue #1578).
	add_to_group("water_body")
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
	var mat_type: String = _visual.material.get_class() if shader_ok else "none"
	_log("[WaterBody] Ready — visual=%s shader=%s(%s) collision=%s splash=%s blood=%s group=%s [fix#1608]" % [
		str(_visual != null),
		"OK" if shader_ok else "FALLBACK",
		mat_type,
		str(_collision != null),
		"OK" if _splash_script != null else "MISSING",
		"OK" if _blood_diffusion_script != null else "MISSING",
		str(is_in_group("precipitation_effects"))
	])


func _process(_delta: float) -> void:
	_update_shader_time()

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

	if not _blood_tint_sources.is_empty():
		_update_blood_tint_shader_params()


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


func _update_shader_time() -> void:
	if _time_stopped:
		return
	if _visual == null or not (_visual.material is ShaderMaterial):
		return
	var mat: ShaderMaterial = _visual.material as ShaderMaterial
	_captured_water_time = Time.get_ticks_msec() / 1000.0
	mat.set_shader_parameter("water_time", _captured_water_time)


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
	# Detect blood puddles entering the water zone and create diffusion effect (Issue #1578).
	# This handles any blood decals that were placed in water before this WaterBody could
	# intercept them (e.g. decals placed by an external system without water awareness).
	if area.is_in_group("blood_puddle") or (area.get_parent() and area.get_parent().is_in_group("blood_puddle")):
		# Prefer the Sprite2D decal root; fall back to the area itself for position.
		var blood_node: Node2D
		if area.get_parent() is Sprite2D:
			blood_node = area.get_parent() as Node2D
		else:
			blood_node = area

		var diffusion_pos: Vector2 = blood_node.global_position
		var diffusion_color: Color = blood_node.modulate if blood_node is Sprite2D else Color(0.5, 0.02, 0.02, 0.55)
		_spawn_blood_diffusion(diffusion_pos, diffusion_color)

		# Remove the decal from the scene — blood does not form puddles in water.
		var decal_root: Node2D = blood_node if blood_node is Sprite2D else area.get_parent() as Node2D
		if decal_root != null and is_instance_valid(decal_root) and decal_root.has_method("fade_out_quick"):
			decal_root.fade_out_quick()
		elif decal_root != null and is_instance_valid(decal_root):
			decal_root.queue_free()


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


## Public: check if a world position is within the water area bounds (Issue #1578).
## Called by ImpactEffectsManager._find_water_body_at() to avoid spawning blood decals in water.
func is_point_in_water(world_pos: Vector2) -> bool:
	return _is_point_in_water(world_pos)


## Public: check if a world position is within an expanded water boundary (Issue #1578).
## Margin absorbs puddles that land near the water edge so they don't get clipped.
func is_point_near_water(world_pos: Vector2, margin: float) -> bool:
	var local_pos: Vector2 = world_pos - global_position
	return abs(local_pos.x) <= water_width * 0.5 + margin and abs(local_pos.y) <= water_height * 0.5 + margin


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


## Public entry point for external systems (e.g. ImpactEffectsManager) to trigger
## a blood diffusion effect at a world position inside this water body (Issue #1578).
func spawn_blood_diffusion_at(world_pos: Vector2, blood_color: Color) -> void:
	_spawn_blood_diffusion(world_pos, blood_color)


## Public entry point: register permanent blood pigment tint after a cloud disperses.
## absorbed_hits scales the tint strength (more hits = darker water). Default = 1.
func register_blood_tint_at(world_pos: Vector2, blood_color: Color, absorbed_hits: int = 1) -> void:
	_add_blood_tint_source(world_pos, blood_color, absorbed_hits)


## Called each frame during cloud fade — grows tint gradually in sync with cloud dispersal.
## fade_t goes 0→1 as the cloud fades out; we track live sources and promote to
## settled (permanent) tint sources once the cloud is fully gone.
func update_blood_tint_fade(world_pos: Vector2, blood_color: Color, absorbed_hits: int, fade_t: float) -> void:
	var max_intensity: float = clampf(float(absorbed_hits) * 0.18, 0.18, 0.72)
	var current_strength: float = max_intensity * fade_t

	# Find or create a live tint entry for this position (within 5px tolerance).
	var found: bool = false
	for entry in _live_tint_sources:
		if entry["position"].distance_to(world_pos) < 5.0:
			entry["current_strength"] = current_strength
			entry["color"] = blood_color
			found = true
			break
	if not found:
		_live_tint_sources.append({
			"position": world_pos,
			"color": blood_color,
			"current_strength": current_strength,
			"max_intensity": max_intensity,
		})
		while _live_tint_sources.size() > MAX_BLOOD_TINT_SHADER_SLOTS:
			_live_tint_sources.pop_front()

	# When cloud is fully dispersed (fade_t >= 1), promote to a permanent tint source.
	if fade_t >= 1.0:
		_add_blood_tint_source(world_pos, blood_color, absorbed_hits)
		# Remove from live sources
		_live_tint_sources = _live_tint_sources.filter(func(e): return e["position"].distance_to(world_pos) >= 5.0)

	_update_live_tint_shader_params()


## Returns the parent that should receive under-water diffusion nodes.
func get_underwater_effect_parent() -> Node:
	if _visual != null:
		return _visual.get_parent()
	return get_parent()


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
	# Tint water gradually as the cloud fades (Issue #1578 feedback).
	var color_ref := blood_color
	diffusion.set("on_tint_update", func(p: Vector2, hits: int, fade_t: float) -> void:
		if is_instance_valid(self):
			update_blood_tint_fade(p, color_ref, hits, fade_t)
	)


func _add_blood_tint_source(world_pos: Vector2, blood_color: Color, absorbed_hits: int = 1) -> void:
	_blood_tint_sources.append({
		"position": world_pos,
		"color": Color(blood_color.r, blood_color.g, blood_color.b, 1.0),
		"start_msec": Time.get_ticks_msec(),
		"intensity": clampf(float(absorbed_hits) * 0.18, 0.18, 0.72),
	})
	while _blood_tint_sources.size() > MAX_BLOOD_TINT_SHADER_SLOTS:
		_blood_tint_sources.pop_front()
	_update_blood_tint_shader_params()


func _update_blood_tint_shader_params() -> void:
	if _visual == null or not (_visual.material is ShaderMaterial):
		return
	var mat: ShaderMaterial = _visual.material as ShaderMaterial
	var now_sec := Time.get_ticks_msec() / 1000.0
	var uvs: Array[Vector2] = []
	var strengths: Array[float] = []
	var kept: Array[Dictionary] = []
	for source in _blood_tint_sources:
		var elapsed: float = now_sec - float(source.get("start_msec", 0)) / 1000.0
		if elapsed >= BLOOD_TINT_DURATION:
			continue
		kept.append(source)
		var world_pos: Vector2 = source.get("position", global_position)
		var local: Vector2 = world_pos - global_position
		uvs.append(Vector2(
			(local.x + water_width * 0.5) / water_width,
			(local.y + water_height * 0.5) / water_height
		).clamp(Vector2.ZERO, Vector2.ONE))
		var fade_t: float = clampf((elapsed - BLOOD_TINT_HOLD_DURATION) / maxf(BLOOD_TINT_DURATION - BLOOD_TINT_HOLD_DURATION, 0.001), 0.0, 1.0)
		var base_strength: float = source.get("intensity", 0.36)
		strengths.append(base_strength * (1.0 - fade_t * fade_t))
		if uvs.size() >= MAX_BLOOD_TINT_SHADER_SLOTS:
			break
	_blood_tint_sources = kept
	while uvs.size() < MAX_BLOOD_TINT_SHADER_SLOTS:
		uvs.append(Vector2(-1.0, -1.0))
		strengths.append(0.0)
	mat.set_shader_parameter("blood_tint_count", mini(kept.size(), MAX_BLOOD_TINT_SHADER_SLOTS))
	mat.set_shader_parameter("blood_tint_uvs", uvs)
	mat.set_shader_parameter("blood_tint_strengths", strengths)


## Update shader with live (still-fading) tint sources that are growing gradually.
func _update_live_tint_shader_params() -> void:
	if _visual == null or not (_visual.material is ShaderMaterial):
		return
	if _live_tint_sources.is_empty():
		return
	# Merge live sources with settled sources for shader upload.
	# Live sources fill any remaining shader slots after settled sources.
	var mat: ShaderMaterial = _visual.material as ShaderMaterial
	var now_sec := Time.get_ticks_msec() / 1000.0
	var uvs: Array[Vector2] = []
	var strengths: Array[float] = []
	# Settled (permanent) sources first
	for source in _blood_tint_sources:
		if uvs.size() >= MAX_BLOOD_TINT_SHADER_SLOTS:
			break
		var elapsed: float = now_sec - float(source.get("start_msec", 0)) / 1000.0
		if elapsed >= BLOOD_TINT_DURATION:
			continue
		var world_pos: Vector2 = source.get("position", global_position)
		var local: Vector2 = world_pos - global_position
		uvs.append(Vector2(
			(local.x + water_width * 0.5) / water_width,
			(local.y + water_height * 0.5) / water_height
		).clamp(Vector2.ZERO, Vector2.ONE))
		var fade_t: float = clampf((elapsed - BLOOD_TINT_HOLD_DURATION) / maxf(BLOOD_TINT_DURATION - BLOOD_TINT_HOLD_DURATION, 0.001), 0.0, 1.0)
		strengths.append(source.get("intensity", 0.36) * (1.0 - fade_t * fade_t))
	# Live sources fill remaining slots
	for entry in _live_tint_sources:
		if uvs.size() >= MAX_BLOOD_TINT_SHADER_SLOTS:
			break
		var world_pos: Vector2 = entry["position"]
		var local: Vector2 = world_pos - global_position
		uvs.append(Vector2(
			(local.x + water_width * 0.5) / water_width,
			(local.y + water_height * 0.5) / water_height
		).clamp(Vector2.ZERO, Vector2.ONE))
		strengths.append(entry.get("current_strength", 0.0))
	var count: int = uvs.size()
	while uvs.size() < MAX_BLOOD_TINT_SHADER_SLOTS:
		uvs.append(Vector2(-1.0, -1.0))
		strengths.append(0.0)
	mat.set_shader_parameter("blood_tint_count", count)
	mat.set_shader_parameter("blood_tint_uvs", uvs)
	mat.set_shader_parameter("blood_tint_strengths", strengths)


## Pauses or resumes wave animation for time-stop effects (e.g. last chance).
## Mirrors the RainEffect/SnowEffect pattern (Issue #1608):
##   - Shader speed uniforms are zeroed so all TIME-dependent animation stops.
##   - WaterVisual process mode is disabled so the canvas item stops updating,
##     matching the PROCESS_MODE_DISABLED approach used for particle nodes in
##     RainEffect._streaks and SnowEffect._flakes_large/_flakes_small.
## When paused is false, both are restored.
## The splash/physics detection is not affected.
func set_time_stopped(paused: bool) -> void:
	if _time_stopped == paused:
		return
	_time_stopped = paused
	if paused:
		# Disable WaterVisual processing — mirrors PROCESS_MODE_DISABLED used on
		# particle nodes in RainEffect and SnowEffect (Issue #1608).
		if _visual != null:
			_visual.process_mode = Node.PROCESS_MODE_DISABLED
		# Zero all shader speed uniforms so TIME-based animation freezes.
		if _visual != null and _visual.material is ShaderMaterial:
			var mat: ShaderMaterial = _visual.material as ShaderMaterial
			_update_shader_time()
			_saved_wave_speed = mat.get_shader_parameter("wave_speed")
			_saved_ripple_speed = mat.get_shader_parameter("ripple_speed")
			_saved_surf_speed = mat.get_shader_parameter("surf_speed")
			mat.set_shader_parameter("time_stopped", true)
			mat.set_shader_parameter("water_time", _captured_water_time)
			mat.set_shader_parameter("wave_speed", 0.0)
			mat.set_shader_parameter("ripple_speed", 0.0)
			mat.set_shader_parameter("surf_speed", 0.0)
			_log("[WaterBody] Wave animation paused: water_time=%s, wave_speed=%s→0, ripple_speed=%s→0, surf_speed=%s→0" % [
				str(_captured_water_time), str(_saved_wave_speed), str(_saved_ripple_speed), str(_saved_surf_speed)])
		else:
			_log("[WaterBody] Wave animation paused (no shader material — visual=%s mat_type=%s)" % [
				str(_visual != null),
				str(_visual.material.get_class() if _visual != null and _visual.material != null else "null")])
	else:
		# Restore WaterVisual processing — mirrors PROCESS_MODE_INHERIT restore in
		# RainEffect and SnowEffect (Issue #1608).
		if _visual != null:
			_visual.process_mode = Node.PROCESS_MODE_INHERIT
		# Restore shader speed uniforms.
		if _visual != null and _visual.material is ShaderMaterial:
			var mat: ShaderMaterial = _visual.material as ShaderMaterial
			mat.set_shader_parameter("wave_speed", _saved_wave_speed)
			mat.set_shader_parameter("ripple_speed", _saved_ripple_speed)
			mat.set_shader_parameter("surf_speed", _saved_surf_speed)
			mat.set_shader_parameter("time_stopped", false)
			_log("[WaterBody] Wave animation resumed: wave_speed=%s, ripple_speed=%s, surf_speed=%s" % [
				str(_saved_wave_speed), str(_saved_ripple_speed), str(_saved_surf_speed)])
		else:
			_log("[WaterBody] Wave animation resumed (no shader material)")


## Log a message via the FileLogger autoload (mirrors SnowEffect/RainEffect pattern).
## Uses Engine.get_singleton() as primary lookup so it works in exported builds.
func _log(message: String) -> void:
	var file_logger: Node = Engine.get_singleton("FileLogger") if Engine.has_singleton("FileLogger") else null
	if file_logger == null:
		file_logger = get_node_or_null("/root/FileLogger")
	if file_logger and file_logger.has_method("log_info"):
		file_logger.log_info(message)
	else:
		print(message)


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
