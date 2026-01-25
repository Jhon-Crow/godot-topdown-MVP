extends Node
## Autoload singleton for managing impact visual effects.
##
## Spawns particle effects when bullets hit different surfaces:
## - Wall/obstacle hits: Dust particles scatter in different directions
## - Lethal hits on enemies/players: Blood splatter effect
## - Non-lethal hits (armor): Spark particles
##
## Effect intensity scales based on weapon caliber.
## Blood decals persist on the floor for visual feedback.

## Preloaded particle effect scenes.
var _dust_effect_scene: PackedScene = null
var _blood_effect_scene: PackedScene = null
var _sparks_effect_scene: PackedScene = null
var _blood_decal_scene: PackedScene = null
var _bullet_hole_scene: PackedScene = null

## Default effect scale for calibers without explicit setting.
const DEFAULT_EFFECT_SCALE: float = 1.0

## Minimum effect scale (prevents invisible effects).
const MIN_EFFECT_SCALE: float = 0.3

## Maximum effect scale (prevents overwhelming effects).
const MAX_EFFECT_SCALE: float = 2.0

## Maximum number of blood decals before oldest ones are removed.
const MAX_BLOOD_DECALS: int = 100

## Maximum distance to check for walls for blood splatters (in pixels).
const WALL_SPLATTER_CHECK_DISTANCE: float = 100.0

## Collision layer for walls/obstacles (layer 3 = bitmask 4).
## Layer mapping: 1=player, 2=enemies, 3=obstacles, 4=pickups, 5=projectiles, 6=targets
const WALL_COLLISION_LAYER: int = 4

## Maximum number of bullet holes is unlimited (permanent holes as requested).
## Set to 0 to disable cleanup limit.
const MAX_BULLET_HOLES: int = 0

## Active blood decals for cleanup management.
var _blood_decals = []

## Active bullet holes for cleanup management (visual only).
var _bullet_holes = []

## Active penetration collision holes for cleanup management.
var _penetration_holes = []

## Penetration hole scene.
var _penetration_hole_scene: PackedScene = null

## Enable/disable debug logging for effect spawning.
var _debug_effects: bool = false

## Reference to FileLogger for persistent logging.
var _file_logger: Node = null

## Track the last known scene to detect scene changes.
var _last_scene: Node = null


func _ready() -> void:
	# CRITICAL: First line diagnostic - if this doesn't appear, script failed to load
	print("[ImpactEffectsManager] _ready() STARTING - FULL VERSION...")

	# Get FileLogger reference - print diagnostic if it fails
	_file_logger = get_node_or_null("/root/FileLogger")
	if _file_logger == null:
		print("[ImpactEffectsManager] WARNING: FileLogger not found at /root/FileLogger")
	else:
		print("[ImpactEffectsManager] FileLogger found successfully")

	_preload_effect_scenes()

	# Connect to tree_changed to detect scene changes and clear stale references
	get_tree().tree_changed.connect(_on_tree_changed)
	_last_scene = get_tree().current_scene

	_log_info("ImpactEffectsManager ready - FULL VERSION with blood effects enabled")


## Logs to FileLogger and always prints to console for diagnostics.
func _log_info(message: String) -> void:
	var log_message := "[ImpactEffects] " + message
	# Always print to console for debugging exported builds
	print(log_message)
	# Also write to file logger if available
	if _file_logger and _file_logger.has_method("log_info"):
		_file_logger.log_info(log_message)


## Preloads all particle effect scenes for efficient instantiation.
func _preload_effect_scenes() -> void:
	# Load effect scenes if they exist
	var dust_path := "res://scenes/effects/DustEffect.tscn"
	var blood_path := "res://scenes/effects/BloodEffect.tscn"
	var sparks_path := "res://scenes/effects/SparksEffect.tscn"
	var blood_decal_path := "res://scenes/effects/BloodDecal.tscn"

	# Track loaded scenes for logging
	var loaded_scenes = []
	var missing_scenes = []

	if ResourceLoader.exists(dust_path):
		_dust_effect_scene = load(dust_path)
		loaded_scenes.append("DustEffect")
		if _debug_effects:
			print("[ImpactEffectsManager] Loaded DustEffect scene")
	else:
		missing_scenes.append("DustEffect")
		push_warning("ImpactEffectsManager: DustEffect scene not found at " + dust_path)

	if ResourceLoader.exists(blood_path):
		_blood_effect_scene = load(blood_path)
		loaded_scenes.append("BloodEffect")
		if _debug_effects:
			print("[ImpactEffectsManager] Loaded BloodEffect scene")
	else:
		missing_scenes.append("BloodEffect")
		push_warning("ImpactEffectsManager: BloodEffect scene not found at " + blood_path)

	if ResourceLoader.exists(sparks_path):
		_sparks_effect_scene = load(sparks_path)
		loaded_scenes.append("SparksEffect")
		if _debug_effects:
			print("[ImpactEffectsManager] Loaded SparksEffect scene")
	else:
		missing_scenes.append("SparksEffect")
		push_warning("ImpactEffectsManager: SparksEffect scene not found at " + sparks_path)

	if ResourceLoader.exists(blood_decal_path):
		_blood_decal_scene = load(blood_decal_path)
		loaded_scenes.append("BloodDecal")
		if _debug_effects:
			print("[ImpactEffectsManager] Loaded BloodDecal scene")
	else:
		missing_scenes.append("BloodDecal")
		# Blood decals are optional - don't warn, just log in debug mode
		if _debug_effects:
			print("[ImpactEffectsManager] BloodDecal scene not found (optional)")

	# Log summary of loaded scenes
	_log_info("Scenes loaded: %s" % [", ".join(loaded_scenes)])
	if missing_scenes.size() > 0:
		_log_info("Missing scenes: %s" % [", ".join(missing_scenes)])

	var bullet_hole_path := "res://scenes/effects/BulletHole.tscn"
	if ResourceLoader.exists(bullet_hole_path):
		_bullet_hole_scene = load(bullet_hole_path)
		if _debug_effects:
			print("[ImpactEffectsManager] Loaded BulletHole scene")
	else:
		# Bullet holes are optional - don't warn, just log in debug mode
		if _debug_effects:
			print("[ImpactEffectsManager] BulletHole scene not found (optional)")

	var penetration_hole_path := "res://scenes/effects/PenetrationHole.tscn"
	if ResourceLoader.exists(penetration_hole_path):
		_penetration_hole_scene = load(penetration_hole_path)
		if _debug_effects:
			print("[ImpactEffectsManager] Loaded PenetrationHole scene")
	else:
		# Penetration holes are optional
		if _debug_effects:
			print("[ImpactEffectsManager] PenetrationHole scene not found (optional)")


## Spawns a dust effect at the given position when a bullet hits a wall.
## @param position: World position where the bullet hit the wall.
## @param surface_normal: Normal vector of the surface (particles scatter away from it).
## @param caliber_data: Optional caliber data for effect scaling.
func spawn_dust_effect(position: Vector2, surface_normal: Vector2, caliber_data: Resource = null) -> void:
	if _debug_effects:
		print("[ImpactEffectsManager] spawn_dust_effect at ", position, " normal=", surface_normal)

	if _dust_effect_scene == null:
		if _debug_effects:
			print("[ImpactEffectsManager] ERROR: _dust_effect_scene is null")
		return

	var effect: GPUParticles2D = _dust_effect_scene.instantiate() as GPUParticles2D
	if effect == null:
		if _debug_effects:
			print("[ImpactEffectsManager] ERROR: Failed to instantiate dust effect")
		return

	effect.global_position = position

	# Rotate effect to face away from surface (in the direction of the normal)
	effect.rotation = surface_normal.angle()

	# Scale effect based on caliber
	var effect_scale := _get_effect_scale(caliber_data)
	effect.amount_ratio = effect_scale
	# Use smaller visual scale for more realistic dust particles
	effect.scale = Vector2(effect_scale * 0.8, effect_scale * 0.8)

	# Add to scene tree
	_add_effect_to_scene(effect)

	# Start emitting
	effect.emitting = true

	if _debug_effects:
		print("[ImpactEffectsManager] Dust effect spawned successfully")


## Spawns a blood splatter effect at the given position for lethal hits.
## @param position: World position where the lethal hit occurred.
## @param hit_direction: Direction the bullet was traveling (blood splatters opposite).
## @param caliber_data: Optional caliber data for effect scaling.
## @param is_lethal: Whether the hit was lethal (affects intensity and decal spawning).
func spawn_blood_effect(position: Vector2, hit_direction: Vector2, caliber_data: Resource = null, is_lethal: bool = true) -> void:
	_log_info("spawn_blood_effect called at %s, dir=%s, lethal=%s" % [position, hit_direction, is_lethal])

	if _debug_effects:
		print("[ImpactEffectsManager] spawn_blood_effect at ", position, " dir=", hit_direction, " lethal=", is_lethal)

	if _blood_effect_scene == null:
		_log_info("ERROR: _blood_effect_scene is null - cannot spawn blood effect")
		print("[ImpactEffectsManager] ERROR: _blood_effect_scene is null - blood effect NOT spawned")
		return

	var effect: GPUParticles2D = _blood_effect_scene.instantiate() as GPUParticles2D
	if effect == null:
		_log_info("ERROR: Failed to instantiate blood effect from scene")
		print("[ImpactEffectsManager] ERROR: Failed to instantiate blood effect - casting failed")
		return

	_log_info("Blood particle effect instantiated successfully")

	effect.global_position = position

	# Blood splatters in the direction the bullet was traveling
	effect.rotation = hit_direction.angle()

	# Scale effect based on caliber (larger calibers = more blood)
	var effect_scale := _get_effect_scale(caliber_data)
	# Lethal hits produce more blood
	if is_lethal:
		effect_scale *= 1.5
	effect.amount_ratio = clampf(effect_scale, MIN_EFFECT_SCALE, MAX_EFFECT_SCALE)
	effect.scale = Vector2(effect_scale, effect_scale)

	# Add to scene tree
	_add_effect_to_scene(effect)

	# Start emitting
	effect.emitting = true

	# Spawn many small blood decals that simulate where particles land
	# Number of decals based on hit intensity and lethality
	var num_decals := 8 if is_lethal else 4
	_spawn_blood_decals_at_particle_landing(position, hit_direction, effect, num_decals)

	# Check for nearby walls and spawn wall splatters
	_spawn_wall_blood_splatter(position, hit_direction, effect_scale, is_lethal)

	_log_info("Blood effect spawned at %s (scale=%s)" % [position, effect_scale])
	if _debug_effects:
		print("[ImpactEffectsManager] Blood effect spawned successfully")


## Spawns a spark effect at the given position for non-lethal (armor) hits.
## @param position: World position where the non-lethal hit occurred.
## @param hit_direction: Direction the bullet was traveling.
## @param caliber_data: Optional caliber data for effect scaling.
func spawn_sparks_effect(position: Vector2, hit_direction: Vector2, caliber_data: Resource = null) -> void:
	if _debug_effects:
		print("[ImpactEffectsManager] spawn_sparks_effect at ", position, " dir=", hit_direction)

	if _sparks_effect_scene == null:
		if _debug_effects:
			print("[ImpactEffectsManager] ERROR: _sparks_effect_scene is null")
		return

	var effect: GPUParticles2D = _sparks_effect_scene.instantiate() as GPUParticles2D
	if effect == null:
		if _debug_effects:
			print("[ImpactEffectsManager] ERROR: Failed to instantiate sparks effect")
		return

	effect.global_position = position

	# Sparks scatter in direction opposite to bullet travel (reflection)
	effect.rotation = (-hit_direction).angle()

	# Scale effect based on caliber
	var effect_scale := _get_effect_scale(caliber_data)
	# Sparks are generally smaller, so reduce scale slightly
	effect_scale *= 0.7
	effect.amount_ratio = effect_scale
	effect.scale = Vector2(effect_scale, effect_scale)

	# Add to scene tree
	_add_effect_to_scene(effect)

	# Start emitting
	effect.emitting = true

	if _debug_effects:
		print("[ImpactEffectsManager] Sparks effect spawned successfully")


## Gets the effect scale from caliber data, or returns default if not available.
## @param caliber_data: Caliber resource that may contain effect_scale property.
## @return: Effect scale factor clamped between MIN and MAX values.
func _get_effect_scale(caliber_data: Resource) -> float:
	var effect_scale := DEFAULT_EFFECT_SCALE

	if caliber_data and "effect_scale" in caliber_data:
		effect_scale = caliber_data.effect_scale

	return clampf(effect_scale, MIN_EFFECT_SCALE, MAX_EFFECT_SCALE)


## Adds an effect node to the current scene tree.
## Effect will be added as a child of the current scene.
func _add_effect_to_scene(effect: Node2D) -> void:
	var scene := get_tree().current_scene
	if scene:
		scene.add_child(effect)
		if _debug_effects:
			print("[ImpactEffectsManager] Effect added to scene: ", scene.name)
	else:
		# Fallback: add to self (autoload node)
		add_child(effect)
		if _debug_effects:
			print("[ImpactEffectsManager] WARNING: No current scene, effect added to autoload")


## Spawns multiple small blood decals at positions simulating where blood particles would land.
## @param origin: World position where the blood spray starts.
## @param hit_direction: Direction the bullet was traveling (blood sprays in this direction).
## @param effect: The GPUParticles2D effect to get physics parameters from.
## @param count: Number of decals to spawn.
func _spawn_blood_decals_at_particle_landing(origin: Vector2, hit_direction: Vector2, effect: GPUParticles2D, count: int) -> void:
	if _blood_decal_scene == null:
		_log_info("Blood decal scene is null - skipping floor decals")
		return

	# Get particle physics parameters from the effect's process material
	var process_mat: ParticleProcessMaterial = effect.process_material as ParticleProcessMaterial
	if process_mat == null:
		_log_info("Blood effect has no process material - using defaults")
		# Use default parameters matching BloodEffect.tscn
		var initial_velocity_min: float = 150.0
		var initial_velocity_max: float = 350.0
		var gravity: Vector2 = Vector2(0, 450)
		var spread_angle: float = deg_to_rad(55.0)
		var lifetime: float = effect.lifetime
		_spawn_decals_with_params(origin, hit_direction, initial_velocity_min, initial_velocity_max, gravity, spread_angle, lifetime, count)
		return

	var initial_velocity_min: float = process_mat.initial_velocity_min
	var initial_velocity_max: float = process_mat.initial_velocity_max
	# ParticleProcessMaterial uses Vector3 for gravity, convert to Vector2
	var gravity_3d: Vector3 = process_mat.gravity
	var gravity: Vector2 = Vector2(gravity_3d.x, gravity_3d.y)
	var spread_angle: float = deg_to_rad(process_mat.spread)
	var lifetime: float = effect.lifetime

	_spawn_decals_with_params(origin, hit_direction, initial_velocity_min, initial_velocity_max, gravity, spread_angle, lifetime, count)


## Internal helper to spawn decals with given physics parameters.
## Checks for wall collisions to prevent decals from appearing through walls.
## Decals are spawned with a delay matching when particles would "land".
func _spawn_decals_with_params(origin: Vector2, hit_direction: Vector2, initial_velocity_min: float, initial_velocity_max: float, gravity: Vector2, spread_angle: float, lifetime: float, count: int) -> void:
	# Base direction (effect rotation is in the hit direction)
	var base_angle: float = hit_direction.angle()

	var decals_scheduled := 0
	for i in range(count):
		# Simulate a random particle trajectory
		# Random angle within spread range
		var angle_offset: float = randf_range(-spread_angle / 2.0, spread_angle / 2.0)
		var particle_angle: float = base_angle + angle_offset

		# Random initial velocity within range
		var initial_speed: float = randf_range(initial_velocity_min, initial_velocity_max)
		var velocity: Vector2 = Vector2.RIGHT.rotated(particle_angle) * initial_speed

		# Simulate particle landing time (random portion of lifetime)
		var land_time: float = randf_range(lifetime * 0.3, lifetime * 0.9)

		# Calculate landing position using physics: pos = origin + v*t + 0.5*g*t^2
		var landing_pos: Vector2 = origin + velocity * land_time + 0.5 * gravity * land_time * land_time

		# Random rotation and scale for variety
		var decal_rotation: float = randf() * TAU
		var decal_scale: float = randf_range(0.8, 1.5)

		# Schedule decal to spawn after land_time (when particle would land)
		_schedule_delayed_decal(origin, landing_pos, decal_rotation, decal_scale, land_time)
		decals_scheduled += 1

	_log_info("Blood decals scheduled: %d to spawn at particle landing times" % [decals_scheduled])
	if _debug_effects:
		print("[ImpactEffectsManager] Blood decals scheduled: ", decals_scheduled)


## Schedules a single blood decal to spawn after a delay, checking for wall collisions at spawn time.
func _schedule_delayed_decal(origin: Vector2, landing_pos: Vector2, decal_rotation: float, decal_scale: float, delay: float) -> void:
	# Use a timer to delay the spawn
	var tree := get_tree()
	if tree == null:
		return

	await tree.create_timer(delay).timeout

	# Check if we're still valid after await (scene might have changed)
	if not is_instance_valid(self):
		return

	if _blood_decal_scene == null:
		return

	# Get the current scene for raycasting at spawn time
	var scene := get_tree().current_scene
	if scene == null:
		return

	var space_state: PhysicsDirectSpaceState2D = scene.get_world_2d().direct_space_state
	if space_state == null:
		return

	# Check if there's a wall between origin and landing position
	var query := PhysicsRayQueryParameters2D.create(origin, landing_pos, WALL_COLLISION_LAYER)
	query.collide_with_bodies = true
	query.collide_with_areas = false
	var result: Dictionary = space_state.intersect_ray(query)
	if not result.is_empty():
		# Wall detected between origin and landing - skip this decal
		return

	# Create the decal
	var decal := _blood_decal_scene.instantiate() as Node2D
	if decal == null:
		return

	decal.global_position = landing_pos
	decal.rotation = decal_rotation
	decal.scale = Vector2(decal_scale, decal_scale)

	# Add to scene
	_add_effect_to_scene(decal)

	# Track decal for cleanup
	_blood_decals.append(decal)

	# Remove oldest decals if limit exceeded
	while _blood_decals.size() > MAX_BLOOD_DECALS:
		var oldest := _blood_decals.pop_front() as Node2D
		if oldest and is_instance_valid(oldest):
			oldest.queue_free()

	if _debug_effects:
		print("[ImpactEffectsManager] Delayed blood decal spawned at ", landing_pos)


## Clears all blood decals from the scene.
## Call this on scene transitions or when cleaning up.
func clear_blood_decals() -> void:
	for decal in _blood_decals:
		if decal and is_instance_valid(decal):
			decal.queue_free()
	_blood_decals.clear()
	if _debug_effects:
		print("[ImpactEffectsManager] All blood decals cleared")


## Checks for nearby walls in the bullet direction and spawns blood splatters on them.
## @param hit_position: World position where the hit occurred.
## @param hit_direction: Direction the bullet was traveling.
## @param intensity: Scale multiplier for splatter size.
## @param is_lethal: Whether the hit was lethal (affects splatter size).
func _spawn_wall_blood_splatter(hit_position: Vector2, hit_direction: Vector2, intensity: float, is_lethal: bool) -> void:
	if _blood_decal_scene == null:
		return

	# Get the current scene for raycasting
	var scene := get_tree().current_scene
	if scene == null:
		return

	# Get the physics space for raycasting
	var space_state: PhysicsDirectSpaceState2D = scene.get_world_2d().direct_space_state
	if space_state == null:
		return

	# Cast a ray in the bullet direction to find nearby walls
	var ray_end := hit_position + hit_direction.normalized() * WALL_SPLATTER_CHECK_DISTANCE
	var query := PhysicsRayQueryParameters2D.create(hit_position, ray_end, WALL_COLLISION_LAYER)
	query.collide_with_bodies = true
	query.collide_with_areas = false

	var result: Dictionary = space_state.intersect_ray(query)

	if result.is_empty():
		if _debug_effects:
			print("[ImpactEffectsManager] No wall found for blood splatter")
		return

	# Wall found! Spawn blood splatter at the impact point
	var wall_hit_pos: Vector2 = result.position
	var wall_normal: Vector2 = result.normal

	_log_info("Wall found for blood splatter at %s (dist=%d px)" % [wall_hit_pos, hit_position.distance_to(wall_hit_pos)])
	if _debug_effects:
		print("[ImpactEffectsManager] Wall found at ", wall_hit_pos, " normal=", wall_normal)

	# Create blood splatter decal on the wall
	var splatter := _blood_decal_scene.instantiate() as Node2D
	if splatter == null:
		return

	# Position at wall impact point, slightly offset along normal to prevent z-fighting
	splatter.global_position = wall_hit_pos + wall_normal * 1.0

	# Rotate to align with wall (facing outward)
	splatter.rotation = wall_normal.angle() + PI / 2.0

	# Scale based on distance (closer = more blood), intensity, and lethality
	# Wall splatters should be small drips (8x8 texture, scale 0.8-1.5 = 6-12 pixels)
	var distance := hit_position.distance_to(wall_hit_pos)
	var distance_factor := 1.0 - (distance / WALL_SPLATTER_CHECK_DISTANCE)
	# Base scale for wall splatters - small drips
	var splatter_scale := distance_factor * randf_range(0.8, 1.5)
	if is_lethal:
		splatter_scale *= 1.2  # Lethal hits produce slightly more blood
	else:
		splatter_scale *= 0.7  # Non-lethal hits produce less blood

	# Elongated shape for dripping effect (taller than wide)
	splatter.scale = Vector2(splatter_scale, splatter_scale * randf_range(1.5, 2.5))

	# Wall splatters need to be visible on walls but below characters
	# Note: Floor decals use z_index = -1 (below characters), wall splatters use 0
	if splatter is CanvasItem:
		splatter.z_index = 0  # Wall splatters: above floor but below characters

	# Add to scene
	_add_effect_to_scene(splatter)

	# Track as blood decal for cleanup
	_blood_decals.append(splatter)

	# Remove oldest decals if limit exceeded
	while _blood_decals.size() > MAX_BLOOD_DECALS:
		var oldest := _blood_decals.pop_front() as Node2D
		if oldest and is_instance_valid(oldest):
			oldest.queue_free()

	if _debug_effects:
		print("[ImpactEffectsManager] Wall blood splatter spawned at ", wall_hit_pos)


## Spawns a bullet hole at the given position when a bullet penetrates a wall.
## @param position: World position where the bullet entered/exited the wall.
## @param surface_normal: Normal vector of the surface (hole faces this direction).
## @param caliber_data: Optional caliber data for effect scaling.
## @param is_entry: True for entry hole (darker), false for exit hole (lighter).
func spawn_penetration_hole(position: Vector2, surface_normal: Vector2, caliber_data: Resource = null, is_entry: bool = true) -> void:
	if _debug_effects:
		print("[ImpactEffectsManager] spawn_penetration_hole at ", position, " is_entry=", is_entry)

	if _bullet_hole_scene == null:
		if _debug_effects:
			print("[ImpactEffectsManager] BulletHole scene not loaded, skipping hole effect")
		return

	var hole := _bullet_hole_scene.instantiate() as Node2D
	if hole == null:
		if _debug_effects:
			print("[ImpactEffectsManager] ERROR: Failed to instantiate bullet hole")
		return

	hole.global_position = position

	# Rotate hole to face the surface normal direction
	hole.rotation = surface_normal.angle()

	# Scale based on caliber
	var effect_scale := _get_effect_scale(caliber_data)

	# Entry holes are slightly smaller and darker
	# Exit holes are slightly larger due to bullet expansion
	if is_entry:
		effect_scale *= 0.8
		# Make entry holes darker
		if hole is Sprite2D:
			hole.modulate = Color(0.8, 0.8, 0.8, 0.95)
	else:
		effect_scale *= 1.2
		# Exit holes are slightly lighter (spalling effect)
		if hole is Sprite2D:
			hole.modulate = Color(1.0, 1.0, 1.0, 0.9)

	hole.scale = Vector2(effect_scale, effect_scale)

	# Add to scene
	_add_effect_to_scene(hole)

	# Track hole for cleanup (unlimited holes, no cleanup limit)
	_bullet_holes.append(hole)

	# Only remove oldest holes if limit is set (MAX_BULLET_HOLES > 0)
	if MAX_BULLET_HOLES > 0:
		while _bullet_holes.size() > MAX_BULLET_HOLES:
			var oldest := _bullet_holes.pop_front() as Node2D
			if oldest and is_instance_valid(oldest):
				oldest.queue_free()

	# Also spawn dust effect at the hole location
	spawn_dust_effect(position, surface_normal, caliber_data)

	if _debug_effects:
		print("[ImpactEffectsManager] Bullet hole spawned, total: ", _bullet_holes.size())


## Clears all bullet holes from the scene.
## Call this on scene transitions or when cleaning up.
func clear_bullet_holes() -> void:
	for hole in _bullet_holes:
		if hole and is_instance_valid(hole):
			hole.queue_free()
	_bullet_holes.clear()
	if _debug_effects:
		print("[ImpactEffectsManager] All bullet holes cleared")


## Spawns a collision hole (Area2D) that creates an actual gap in wall collision.
## This allows bullets and vision to pass through the hole.
## @param entry_point: Where the bullet entered the wall.
## @param exit_point: Where the bullet exited the wall.
## @param bullet_direction: Direction the bullet was traveling.
## @param caliber_data: Optional caliber data for hole width.
func spawn_collision_hole(entry_point: Vector2, exit_point: Vector2, bullet_direction: Vector2, caliber_data: Resource = null) -> void:
	if _debug_effects:
		print("[ImpactEffectsManager] spawn_collision_hole from ", entry_point, " to ", exit_point)

	if _penetration_hole_scene == null:
		if _debug_effects:
			print("[ImpactEffectsManager] PenetrationHole scene not loaded, skipping collision hole")
		return

	var hole := _penetration_hole_scene.instantiate()
	if hole == null:
		if _debug_effects:
			print("[ImpactEffectsManager] ERROR: Failed to instantiate penetration hole")
		return

	# Calculate hole width based on caliber (default 4 pixels for 5.45mm)
	var hole_width := 4.0
	if caliber_data and "diameter_mm" in caliber_data:
		# Scale from mm to pixels (roughly 0.8 pixels per mm for visual effect)
		hole_width = caliber_data.diameter_mm * 0.8

	# Configure the hole with entry/exit points
	if hole.has_method("set_from_entry_exit"):
		hole.trail_width = hole_width
		hole.set_from_entry_exit(entry_point, exit_point)
	else:
		# Fallback: manually position at center
		hole.global_position = (entry_point + exit_point) / 2.0
		if hole.has_method("configure"):
			var path := exit_point - entry_point
			hole.configure(bullet_direction, hole_width, path.length())

	# Add to scene
	_add_effect_to_scene(hole)

	# Track hole (unlimited, no cleanup)
	_penetration_holes.append(hole)

	if _debug_effects:
		print("[ImpactEffectsManager] Collision hole spawned, total: ", _penetration_holes.size())


## Clears all penetration collision holes from the scene.
## Call this on scene transitions or when cleaning up.
func clear_penetration_holes() -> void:
	for hole in _penetration_holes:
		if hole and is_instance_valid(hole):
			hole.queue_free()
	_penetration_holes.clear()
	if _debug_effects:
		print("[ImpactEffectsManager] All penetration holes cleared")


## Clears all persistent effects (blood decals, bullet holes, and penetration holes).
## Call this on scene transitions.
func clear_all_persistent_effects() -> void:
	clear_blood_decals()
	clear_bullet_holes()
	clear_penetration_holes()


## Called when the scene tree changes. Detects scene transitions and clears stale references.
func _on_tree_changed() -> void:
	var current_scene := get_tree().current_scene
	if current_scene != _last_scene:
		_log_info("Scene changed - clearing all stale effect references")
		# Clear arrays of stale references (nodes are already freed by scene change)
		_blood_decals.clear()
		_bullet_holes.clear()
		_penetration_holes.clear()
		_last_scene = current_scene
