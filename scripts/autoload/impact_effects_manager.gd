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
## Set to 0 for unlimited decals (puddles should never disappear per issue #293).
const MAX_BLOOD_DECALS: int = 0

## Minimum distance between decals before they start merging (in pixels).
const DECAL_MERGE_DISTANCE: float = 12.0

## Maximum number of merged decals (splatters) to create from nearby drops.
const MAX_MERGED_SPLATTERS: int = 10

## Probability of spawning satellite drops near main drops (0.0 to 1.0).
const SATELLITE_DROP_PROBABILITY: float = 0.4

## Maximum distance for satellite drops from their parent drop (in pixels).
const SATELLITE_DROP_MAX_DISTANCE: float = 8.0

## Minimum distance for satellite drops from their parent drop (in pixels).
const SATELLITE_DROP_MIN_DISTANCE: float = 3.0

## Scale range for satellite drops (smaller than main drops).
const SATELLITE_DROP_SCALE_MIN: float = 0.15
const SATELLITE_DROP_SCALE_MAX: float = 0.35

## Number of satellite drops to spawn per main outermost drop.
const SATELLITE_DROPS_PER_MAIN: int = 3

## Distance threshold to consider a drop as "outermost" (percentile from center).
const OUTERMOST_DROP_PERCENTILE: float = 0.7

## Minimum distance between satellite drops and existing drops to prevent overlap.
const SATELLITE_MIN_SEPARATION: float = 4.0

## Edge drop scaling: drops at the edge are scaled down by this factor.
## Drops at center = 1.0, drops at edge = this value.
const EDGE_DROP_SCALE_MIN: float = 0.4

## Probability of spawning crown/blossom spines around larger drops.
const CROWN_EFFECT_PROBABILITY: float = 0.25

## Number of spines in a crown/blossom effect.
const CROWN_SPINE_COUNT: int = 5

## Scale range for crown spines (thin elongated drops).
const CROWN_SPINE_SCALE_WIDTH: float = 0.12
const CROWN_SPINE_SCALE_LENGTH_MIN: float = 0.4
const CROWN_SPINE_SCALE_LENGTH_MAX: float = 0.7

## Distance from center for crown spine placement.
const CROWN_SPINE_DISTANCE: float = 4.0

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
		if _dust_effect_scene != null:
			loaded_scenes.append("DustEffect")
			if _debug_effects:
				print("[ImpactEffectsManager] Loaded DustEffect scene")
		else:
			missing_scenes.append("DustEffect (load failed)")
			push_warning("ImpactEffectsManager: DustEffect scene exists but failed to load from " + dust_path)
	else:
		missing_scenes.append("DustEffect")
		push_warning("ImpactEffectsManager: DustEffect scene not found at " + dust_path)

	if ResourceLoader.exists(blood_path):
		_blood_effect_scene = load(blood_path)
		if _blood_effect_scene != null:
			loaded_scenes.append("BloodEffect")
			if _debug_effects:
				print("[ImpactEffectsManager] Loaded BloodEffect scene")
		else:
			missing_scenes.append("BloodEffect (load failed)")
			push_warning("ImpactEffectsManager: BloodEffect scene exists but failed to load from " + blood_path)
	else:
		missing_scenes.append("BloodEffect")
		push_warning("ImpactEffectsManager: BloodEffect scene not found at " + blood_path)

	if ResourceLoader.exists(sparks_path):
		_sparks_effect_scene = load(sparks_path)
		if _sparks_effect_scene != null:
			loaded_scenes.append("SparksEffect")
			if _debug_effects:
				print("[ImpactEffectsManager] Loaded SparksEffect scene")
		else:
			missing_scenes.append("SparksEffect (load failed)")
			push_warning("ImpactEffectsManager: SparksEffect scene exists but failed to load from " + sparks_path)
	else:
		missing_scenes.append("SparksEffect")
		push_warning("ImpactEffectsManager: SparksEffect scene not found at " + sparks_path)

	if ResourceLoader.exists(blood_decal_path):
		_blood_decal_scene = load(blood_decal_path)
		if _blood_decal_scene != null:
			loaded_scenes.append("BloodDecal")
			if _debug_effects:
				print("[ImpactEffectsManager] Loaded BloodDecal scene")
		else:
			# Scene file exists but failed to load - this is a problem
			missing_scenes.append("BloodDecal (load failed)")
			push_warning("ImpactEffectsManager: BloodDecal scene exists but failed to load from " + blood_decal_path)
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

	# Spawn blood decals matching the particle count from the effect
	# This creates as many floor drops as visible particles in the spray
	var num_decals := effect.amount if is_lethal else int(effect.amount * 0.5)
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
		_log_info("Blood decal scene is null - attempting to reload")
		# Try to reload the scene (it may have been unloaded or failed initially)
		var blood_decal_path := "res://scenes/effects/BloodDecal.tscn"
		if ResourceLoader.exists(blood_decal_path):
			_blood_decal_scene = load(blood_decal_path)
			if _blood_decal_scene != null:
				_log_info("Blood decal scene reloaded successfully")
			else:
				_log_info("Blood decal scene reload FAILED - skipping floor decals")
				return
		else:
			_log_info("Blood decal scene file not found - skipping floor decals")
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
## Nearby drops are merged into unified splatters, and drops are elongated based on velocity.
## Edge drops (farther from center) are scaled smaller for realistic blood pattern.
func _spawn_decals_with_params(origin: Vector2, hit_direction: Vector2, initial_velocity_min: float, initial_velocity_max: float, gravity: Vector2, spread_angle: float, lifetime: float, count: int) -> void:
	# Base direction (effect rotation is in the hit direction)
	var base_angle: float = hit_direction.angle()

	# First pass: collect all particle landing data for clustering
	var particle_data: Array = []
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

		particle_data.append({
			"position": landing_pos,
			"velocity": velocity,
			"land_time": land_time,
			"merged": false
		})

	# Calculate spread metrics for edge-based scaling
	# Drops closer to edge should be smaller (per issue #293 feedback)
	var max_distance_from_origin: float = 0.0
	for particle in particle_data:
		var dist: float = origin.distance_to(particle["position"])
		if dist > max_distance_from_origin:
			max_distance_from_origin = dist

	# Second pass: cluster nearby drops into merged splatters
	var merged_splatters: Array = _cluster_drops_into_splatters(particle_data)

	# Track all spawned positions for satellite overlap checking
	var spawned_positions: Array = []

	# Third pass: spawn individual drops with directional elongation and merged splatters
	var decals_scheduled := 0

	# Spawn merged splatters (complex blobs from multiple overlapping decals)
	# When drops merge, they create irregular blob shapes, not perfect circles.
	# We achieve this by spawning multiple overlapping decals with slight offsets.
	for splatter in merged_splatters:
		var center_pos: Vector2 = splatter["center"]
		var avg_velocity: Vector2 = splatter["avg_velocity"]
		var drop_count: int = splatter["count"]
		var earliest_land_time: float = splatter["earliest_land_time"]

		# Calculate distance-based edge scaling
		# Merged splatters near center are larger, near edge are smaller
		var dist_from_origin: float = origin.distance_to(center_pos)
		var edge_factor: float = 1.0
		if max_distance_from_origin > 0.0:
			edge_factor = 1.0 - ((dist_from_origin / max_distance_from_origin) * (1.0 - EDGE_DROP_SCALE_MIN))

		# Calculate directional elongation based on velocity
		var speed: float = avg_velocity.length()
		# Elongation factor: faster drops are more elongated (splashed)
		var elongation: float = clampf(1.0 + speed / 300.0, 1.0, 3.0)

		# Rotation aligned with velocity direction for splash effect
		var base_rotation: float = avg_velocity.angle() if speed > 10.0 else randf() * TAU

		# Scale based on number of merged drops (more drops = larger splatter)
		# Apply edge factor: drops at edge are smaller
		var base_scale: float = (0.8 + (drop_count * 0.12)) * edge_factor

		# For merged puddles with 3+ drops, create complex blob by spawning multiple overlapping decals
		# This creates the "unified blob with gradient contour" effect requested
		var num_overlapping_decals := 1
		if drop_count >= 3:
			num_overlapping_decals = mini(drop_count - 1, 4)  # 2-4 overlapping decals for complex shape

		for k in range(num_overlapping_decals):
			var offset := Vector2.ZERO
			var rotation_offset: float = 0.0
			var scale_variation: float = 1.0

			if k > 0:
				# Offset subsequent decals slightly for irregular blob shape
				var offset_angle: float = randf() * TAU
				var offset_dist: float = randf_range(2.0, 5.0)
				offset = Vector2.RIGHT.rotated(offset_angle) * offset_dist

				# Vary rotation slightly for more organic shape
				rotation_offset = randf_range(-0.3, 0.3)

				# Vary scale slightly
				scale_variation = randf_range(0.85, 1.15)

			var decal_pos: Vector2 = center_pos + offset
			var decal_rotation: float = base_rotation + rotation_offset
			var decal_scale_x: float = base_scale * elongation * scale_variation
			var decal_scale_y: float = base_scale * scale_variation

			# Stagger timing slightly for overlapping decals
			var time_offset: float = k * 0.01

			_schedule_delayed_decal_directional(origin, decal_pos, decal_rotation, decal_scale_x, decal_scale_y, earliest_land_time + time_offset)
			spawned_positions.append(decal_pos)
			decals_scheduled += 1

	# Spawn remaining individual drops with directional elongation
	for particle in particle_data:
		if particle["merged"]:
			continue  # Already part of a merged splatter

		var landing_pos: Vector2 = particle["position"]
		var velocity: Vector2 = particle["velocity"]
		var land_time: float = particle["land_time"]

		# Calculate distance-based edge scaling
		# Drops closer to edge are smaller (per issue #293 feedback)
		var dist_from_origin: float = origin.distance_to(landing_pos)
		var edge_factor: float = 1.0
		if max_distance_from_origin > 0.0:
			edge_factor = 1.0 - ((dist_from_origin / max_distance_from_origin) * (1.0 - EDGE_DROP_SCALE_MIN))

		# Calculate directional elongation based on velocity
		var speed: float = velocity.length()
		# Elongation factor: faster drops are more elongated (splashed)
		var elongation: float = clampf(1.0 + speed / 400.0, 1.0, 2.5)

		# Rotation aligned with velocity direction for splash effect
		var decal_rotation: float = velocity.angle() if speed > 10.0 else randf() * TAU

		# Random scale with elongation applied, multiplied by edge factor
		var base_scale: float = randf_range(0.6, 1.2) * edge_factor
		var decal_scale_x: float = base_scale * elongation
		var decal_scale_y: float = base_scale

		_schedule_delayed_decal_directional(origin, landing_pos, decal_rotation, decal_scale_x, decal_scale_y, land_time)
		spawned_positions.append(landing_pos)
		decals_scheduled += 1

		# Crown/blossom effect: larger drops may have radiating spines
		# This occurs when blood impacts at nearly 90 degrees and creates a crown-like splash
		if base_scale > 0.9 and randf() < CROWN_EFFECT_PROBABILITY:
			var crown_count := _spawn_crown_effect(origin, landing_pos, decal_rotation, base_scale, land_time)
			decals_scheduled += crown_count

	# Fourth pass: spawn satellite drops near outermost drops for realistic secondary spatter
	# Pass spawned_positions to avoid overlap with existing drops
	var satellite_count := _spawn_satellite_drops(origin, particle_data, merged_splatters, spawned_positions)
	decals_scheduled += satellite_count

	_log_info("Blood decals scheduled: %d (%d merged splatters, %d satellite drops)" % [decals_scheduled, merged_splatters.size(), satellite_count])
	if _debug_effects:
		print("[ImpactEffectsManager] Blood decals scheduled: ", decals_scheduled, " (", merged_splatters.size(), " merged, ", satellite_count, " satellites)")


## Clusters nearby drops into merged splatters.
## Returns an array of splatter data: {center, avg_velocity, count, earliest_land_time}
func _cluster_drops_into_splatters(particle_data: Array) -> Array:
	var splatters: Array = []

	for i in range(particle_data.size()):
		if particle_data[i]["merged"]:
			continue

		var cluster_positions: Array = [particle_data[i]["position"]]
		var cluster_velocities: Array = [particle_data[i]["velocity"]]
		var cluster_land_times: Array = [particle_data[i]["land_time"]]
		particle_data[i]["merged"] = true

		# Find all nearby drops within merge distance
		for j in range(i + 1, particle_data.size()):
			if particle_data[j]["merged"]:
				continue

			var dist: float = particle_data[i]["position"].distance_to(particle_data[j]["position"])
			if dist < DECAL_MERGE_DISTANCE:
				cluster_positions.append(particle_data[j]["position"])
				cluster_velocities.append(particle_data[j]["velocity"])
				cluster_land_times.append(particle_data[j]["land_time"])
				particle_data[j]["merged"] = true

		# Only create merged splatter if we have multiple drops
		if cluster_positions.size() >= 2:
			# Calculate center position (average of all clustered drops)
			var center := Vector2.ZERO
			for pos in cluster_positions:
				center += pos
			center /= cluster_positions.size()

			# Calculate average velocity for directional elongation
			var avg_velocity := Vector2.ZERO
			for vel in cluster_velocities:
				avg_velocity += vel
			avg_velocity /= cluster_velocities.size()

			# Use earliest land time for the merged splatter
			var earliest_time: float = cluster_land_times[0]
			for t in cluster_land_times:
				if t < earliest_time:
					earliest_time = t

			splatters.append({
				"center": center,
				"avg_velocity": avg_velocity,
				"count": cluster_positions.size(),
				"earliest_land_time": earliest_time
			})

			# Limit number of merged splatters
			if splatters.size() >= MAX_MERGED_SPLATTERS:
				break
		else:
			# Single drop, mark as not merged so it spawns individually
			particle_data[i]["merged"] = false

	return splatters


## Spawns satellite drops near outermost main drops for realistic secondary spatter effect.
## Satellite drops are small secondary drops that form when blood impacts a surface.
## Based on forensic blood spatter analysis: "satellite spatter" forms as blood separates
## from the rim of the main drop during impact, creating small splashes around the main stain.
## @param origin: The origin point of the blood spray.
## @param particle_data: Array of particle landing data.
## @param merged_splatters: Array of merged splatter data.
## @param existing_positions: Array of already spawned drop positions to avoid overlap.
## @return: Number of satellite drops spawned.
func _spawn_satellite_drops(origin: Vector2, particle_data: Array, merged_splatters: Array, existing_positions: Array = []) -> int:
	if _blood_decal_scene == null:
		return 0

	var satellite_count := 0

	# Calculate center of all drops to determine "outermost" drops
	var center := Vector2.ZERO
	var valid_drops: Array = []

	for particle in particle_data:
		if not particle["merged"]:
			valid_drops.append(particle)
			center += particle["position"]

	for splatter in merged_splatters:
		valid_drops.append({"position": splatter["center"], "velocity": splatter["avg_velocity"], "land_time": splatter["earliest_land_time"]})
		center += splatter["center"]

	if valid_drops.size() == 0:
		return 0

	center /= valid_drops.size()

	# Calculate distances from center for each drop
	var distances: Array = []
	for drop in valid_drops:
		distances.append(drop["position"].distance_to(center))

	# Sort distances to find the threshold for "outermost" drops
	var sorted_distances := distances.duplicate()
	sorted_distances.sort()
	var threshold_index := int(sorted_distances.size() * OUTERMOST_DROP_PERCENTILE)
	var distance_threshold: float = sorted_distances[threshold_index] if threshold_index < sorted_distances.size() else 0.0

	# Track all positions (existing + newly spawned satellites) for overlap checking
	var all_positions: Array = existing_positions.duplicate()

	# Spawn satellite drops near outermost drops
	for i in range(valid_drops.size()):
		if distances[i] < distance_threshold:
			continue  # Skip non-outermost drops

		var drop = valid_drops[i]
		var drop_pos: Vector2 = drop["position"]
		var drop_velocity: Vector2 = drop["velocity"]
		var drop_land_time: float = drop["land_time"]

		# Probability check for spawning satellites
		if randf() > SATELLITE_DROP_PROBABILITY:
			continue

		# Spawn multiple small satellite drops around this main drop
		for _j in range(SATELLITE_DROPS_PER_MAIN):
			# Try multiple times to find a non-overlapping position
			var satellite_pos: Vector2 = Vector2.ZERO
			var found_valid_position := false

			for _attempt in range(5):  # Try up to 5 times to find valid position
				# Random angle, biased toward the direction of velocity (splash direction)
				var velocity_angle: float = drop_velocity.angle() if drop_velocity.length() > 10.0 else randf() * TAU
				var angle_spread: float = PI * 0.8  # Allow satellites in a wide arc
				var satellite_angle: float = velocity_angle + randf_range(-angle_spread, angle_spread)

				# Random distance from parent drop
				var satellite_dist: float = randf_range(SATELLITE_DROP_MIN_DISTANCE, SATELLITE_DROP_MAX_DISTANCE)

				# Calculate satellite position
				satellite_pos = drop_pos + Vector2.RIGHT.rotated(satellite_angle) * satellite_dist

				# Check if position overlaps with any existing drop
				var has_overlap := false
				for existing_pos in all_positions:
					if satellite_pos.distance_to(existing_pos) < SATELLITE_MIN_SEPARATION:
						has_overlap = true
						break

				if not has_overlap:
					found_valid_position = true
					break

			# Skip this satellite if we couldn't find a valid position
			if not found_valid_position:
				continue

			# Random small scale for satellite drops
			var satellite_scale: float = randf_range(SATELLITE_DROP_SCALE_MIN, SATELLITE_DROP_SCALE_MAX)

			# Satellites land slightly after main drop
			var satellite_delay: float = drop_land_time + randf_range(0.02, 0.08)

			# Random rotation for variety
			var satellite_rotation: float = randf() * TAU

			# Schedule the satellite decal
			_schedule_delayed_decal_directional(origin, satellite_pos, satellite_rotation, satellite_scale, satellite_scale, satellite_delay)

			# Track this position to avoid future overlaps
			all_positions.append(satellite_pos)
			satellite_count += 1

	return satellite_count


## Spawns crown/blossom effect spines around a main blood drop.
## When blood drops land at nearly 90 degrees, they create a crown-like splash pattern
## with thin spines radiating outward from the main drop. This is a well-documented
## forensic blood pattern phenomenon.
## @param origin: The origin point of the blood spray (for wall collision checks).
## @param drop_pos: Position of the main blood drop.
## @param drop_rotation: Rotation of the main drop.
## @param drop_scale: Scale of the main drop.
## @param land_time: When the main drop lands.
## @return: Number of crown spines spawned.
func _spawn_crown_effect(origin: Vector2, drop_pos: Vector2, drop_rotation: float, drop_scale: float, land_time: float) -> int:
	if _blood_decal_scene == null:
		return 0

	var spine_count := 0

	# Spines radiate evenly around the drop
	var angle_step: float = TAU / CROWN_SPINE_COUNT

	for i in range(CROWN_SPINE_COUNT):
		# Calculate spine angle (evenly distributed with slight randomization)
		var spine_angle: float = i * angle_step + randf_range(-0.2, 0.2)

		# Calculate spine position (at edge of main drop)
		var spine_distance: float = CROWN_SPINE_DISTANCE * drop_scale
		var spine_pos: Vector2 = drop_pos + Vector2.RIGHT.rotated(spine_angle) * spine_distance

		# Spine is elongated and thin, pointing outward from the center
		var spine_length: float = randf_range(CROWN_SPINE_SCALE_LENGTH_MIN, CROWN_SPINE_SCALE_LENGTH_MAX)
		var spine_width: float = CROWN_SPINE_SCALE_WIDTH

		# Rotation points outward from center
		var spine_rotation: float = spine_angle

		# Spines appear slightly after the main drop lands
		var spine_delay: float = land_time + randf_range(0.01, 0.03)

		_schedule_delayed_decal_directional(origin, spine_pos, spine_rotation, spine_length, spine_width, spine_delay)
		spine_count += 1

	return spine_count


## Schedules a single blood decal with directional scaling (elongation) to spawn after a delay.
func _schedule_delayed_decal_directional(origin: Vector2, landing_pos: Vector2, decal_rotation: float, scale_x: float, scale_y: float, delay: float) -> void:
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
	# Apply directional scaling (elongation based on velocity direction)
	decal.scale = Vector2(scale_x, scale_y)

	# Add to scene
	_add_effect_to_scene(decal)

	# Track decal for cleanup (only if limit is enabled)
	_blood_decals.append(decal)

	# Remove oldest decals if limit exceeded (0 = unlimited, no cleanup)
	if MAX_BLOOD_DECALS > 0:
		while _blood_decals.size() > MAX_BLOOD_DECALS:
			var oldest := _blood_decals.pop_front() as Node2D
			if oldest and is_instance_valid(oldest):
				oldest.queue_free()

	if _debug_effects:
		print("[ImpactEffectsManager] Directional blood decal spawned at ", landing_pos, " scale=", Vector2(scale_x, scale_y))


## Schedules a single blood decal to spawn after a delay, checking for wall collisions at spawn time.
## @deprecated Use _schedule_delayed_decal_directional for new code.
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

	# Track decal for cleanup (only if limit is enabled)
	_blood_decals.append(decal)

	# Remove oldest decals if limit exceeded (0 = unlimited, no cleanup)
	if MAX_BLOOD_DECALS > 0:
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

	# Wall splatters at same z-index as floor decals (both above floor ColorRect)
	if splatter is CanvasItem:
		splatter.z_index = 1  # Same as floor decals (above floor)

	# Add to scene
	_add_effect_to_scene(splatter)

	# Track as blood decal for cleanup (only if limit is enabled)
	_blood_decals.append(splatter)

	# Remove oldest decals if limit exceeded (0 = unlimited, no cleanup)
	if MAX_BLOOD_DECALS > 0:
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
