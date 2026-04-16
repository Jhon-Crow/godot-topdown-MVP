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
var _muzzle_flash_scene: PackedScene = null
var _flashbang_effect_scene: PackedScene = null
var _explosion_scorch_mark_scene: PackedScene = null

## Default effect scale for calibers without explicit setting.
const DEFAULT_EFFECT_SCALE: float = 1.0

## Minimum effect scale (prevents invisible effects).
## Note: Silenced weapons may use scales as low as 0.2 for very subtle muzzle flash.
const MIN_EFFECT_SCALE: float = 0.2

## Maximum effect scale (prevents overwhelming effects).
const MAX_EFFECT_SCALE: float = 2.0

## Maximum number of blood decals before oldest ones are removed.
## Issue #1747: Set to 0 (unlimited) per owner request — blood puddles must never be deleted.
## The previous cap of 200 (Issue #1693) caused visible puddles to disappear during combat.
## Owner confirmed that accumulation is acceptable and puddles should persist indefinitely.
## 0 = unlimited, no cleanup performed.
const MAX_BLOOD_DECALS: int = 0

## Maximum distance to check for walls for blood splatters (in pixels).
const WALL_SPLATTER_CHECK_DISTANCE: float = 100.0

## Collision layer for walls/obstacles (layer 3 = bitmask 4).
## Layer mapping: 1=player, 2=enemies, 3=obstacles, 4=pickups, 5=projectiles, 6=targets
const WALL_COLLISION_LAYER: int = 4

## Maximum number of bullet holes is unlimited (permanent holes as requested).
## Set to 0 to disable cleanup limit.
const MAX_BULLET_HOLES: int = 0

## Number of blood decals spawned per lethal hit.
## Issue #1090 Round 2: Increased to 30 (50% above the Feb 16 backup value of 20)
## per owner request for more visible blood on floor.
## Note: Issue #1027 removed per-puddle Area2D physics, eliminating the main FPS bottleneck.
## 30 Sprite2D decals are trivially cheap to render.
const BLOOD_DECALS_PER_LETHAL_HIT: int = 30

## Number of blood decals spawned per non-lethal hit.
## Issue #1090 Round 2: Increased to 15 (50% above the Feb 16 backup value of 10)
## per owner request for more visible blood on floor.
const BLOOD_DECALS_PER_NONLETHAL_HIT: int = 15

## Active blood decals for cleanup management.
var _blood_decals = []

## Cached light texture for explosion effects (Issue #724 optimization).
## Creating GradientTexture2D is expensive, so we cache and reuse it.
var _cached_explosion_light_texture: GradientTexture2D = null

## Pool of reusable PointLight2D objects for explosion effects (Issue #724 optimization).
## Creating/destroying many PointLight2D objects causes FPS drops even without shadows.
## This pool allows reusing lights instead of creating new ones each explosion.
var _explosion_light_pool: Array[PointLight2D] = []

## Active explosion lights currently animating (for tracking and recycling).
var _active_explosion_lights: Array[PointLight2D] = []

## Maximum number of concurrent explosion lights allowed.
## Beyond this limit, new explosions won't create lights to prevent FPS drops.
## Based on testing: 5-10 simultaneous PointLight2D cause noticeable performance impact.
const MAX_CONCURRENT_EXPLOSION_LIGHTS: int = 8

## Initial pool size for explosion lights (pre-created at startup).
const EXPLOSION_LIGHT_POOL_SIZE: int = 12

## Pool of reusable GPUParticles2D nodes for dust effects (Issue #1145 optimization).
## Instantiating a new GPUParticles2D per wall-hit causes first-emit stutter (Godot issue
## #103308) and CPU allocation overhead, leading to FPS drops at high fire rates.
## Pre-creating nodes and reusing them by resetting position/rotation/emitting eliminates
## this overhead. Pooled nodes are hidden (invisible) when idle.
var _dust_effect_pool: Array[GPUParticles2D] = []

## Count of dust effect nodes currently checked out (active / emitting).
var _dust_effects_active: int = 0

## Maximum number of concurrent dust effects allowed.
## Mini UZI fires ~15 rounds/sec; DustEffect lifetime = 2.5s → up to 37 active at once
## without limiting. Cap at 16 to bound GPU particle work while keeping visuals dense.
const MAX_CONCURRENT_DUST_EFFECTS: int = 16

## Initial pool size for dust effects (pre-created at startup).
const DUST_EFFECT_POOL_SIZE: int = 16

## Active bullet holes for cleanup management (visual only).
var _bullet_holes = []

## Active penetration collision holes for cleanup management.
var _penetration_holes = []

## Active muzzle flash data for enemy detection (Issue #910).
## Each entry contains position, direction, and timestamp.
var _active_muzzle_flashes: Array = []

## Maximum number of tracked muzzle flashes to prevent memory growth.
const MAX_TRACKED_FLASHES: int = 10

## Maximum age before flash is removed from tracking (seconds).
const FLASH_TRACKING_MAX_AGE: float = 0.5

## Penetration hole scene.
var _penetration_hole_scene: PackedScene = null

## Enable/disable debug logging for effect spawning.
var _debug_effects: bool = false

## Reference to FileLogger for persistent logging.
var _file_logger: Node = null

## Track the last known scene to detect scene changes.
var _last_scene: Node = null

## Whether the shader warmup has been completed.
## Warmup pre-compiles GPU shaders to prevent first-shot lag (Issue #343).
var _warmup_completed: bool = false


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

	# Initialize explosion light pool (Issue #724 optimization)
	_init_explosion_light_pool()

	# Initialize dust effect pool (Issue #1145 optimization)
	_init_dust_effect_pool()

	# Perform shader warmup to prevent first-shot lag (Issue #343)
	# This pre-compiles GPU shaders for particle effects during loading
	_warmup_particle_shaders()


## Logs to FileLogger and prints to console in debug builds only.
## Issue #1293: print() in release builds causes variable FPS drops.
func _log_info(message: String) -> void:
	var log_message := "[ImpactEffects] " + message
	# Only print to console in debug builds to avoid FPS drops (Issue #1293).
	if OS.is_debug_build():
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

	var muzzle_flash_path := "res://scenes/effects/MuzzleFlash.tscn"
	if ResourceLoader.exists(muzzle_flash_path):
		_muzzle_flash_scene = load(muzzle_flash_path)
		loaded_scenes.append("MuzzleFlash")
		if _debug_effects:
			print("[ImpactEffectsManager] Loaded MuzzleFlash scene")
	else:
		# Muzzle flash is optional - don't warn, just log in debug mode
		if _debug_effects:
			print("[ImpactEffectsManager] MuzzleFlash scene not found (optional)")

	var flashbang_effect_path := "res://scenes/effects/FlashbangEffect.tscn"
	if ResourceLoader.exists(flashbang_effect_path):
		_flashbang_effect_scene = load(flashbang_effect_path)
		loaded_scenes.append("FlashbangEffect")
		if _debug_effects:
			print("[ImpactEffectsManager] Loaded FlashbangEffect scene")
	else:
		# Flashbang effect is optional - don't warn, just log in debug mode
		if _debug_effects:
			print("[ImpactEffectsManager] FlashbangEffect scene not found (optional)")

	# Issue #1005: Load explosion scorch mark scene
	var scorch_mark_path := "res://scenes/effects/ExplosionScorchMark.tscn"
	if ResourceLoader.exists(scorch_mark_path):
		_explosion_scorch_mark_scene = load(scorch_mark_path)
		loaded_scenes.append("ExplosionScorchMark")
		if _debug_effects:
			print("[ImpactEffectsManager] Loaded ExplosionScorchMark scene")
	else:
		# Scorch mark is optional - don't warn, just log in debug mode
		if _debug_effects:
			print("[ImpactEffectsManager] ExplosionScorchMark scene not found (optional)")


## Spawns a dust effect at the given position when a bullet hits a wall.
## Issue #1145: Uses a pre-allocated pool to avoid GPUParticles2D first-emit stutter
## (Godot issue #103308) and CPU allocation overhead at high fire rates.
## @param position: World position where the bullet hit the wall.
## @param surface_normal: Normal vector of the surface (particles scatter away from it).
## @param caliber_data: Optional caliber data for effect scaling.
func spawn_dust_effect(position: Vector2, surface_normal: Vector2, caliber_data: Resource = null) -> void:
	# Issue #1145: Respect the wall hit particles optimization setting.
	var gameplay_settings: Node = get_node_or_null("/root/GameplaySettings")
	if gameplay_settings and not gameplay_settings.is_wall_hit_particles_enabled():
		return
	# Issue #1186: performance toggle
	var perf_settings: Node = get_node_or_null("/root/PerformanceSettings")
	if perf_settings and not perf_settings.is_particles_enabled():
		return

	if _debug_effects:
		print("[ImpactEffectsManager] spawn_dust_effect at ", position, " normal=", surface_normal)

	# Issue #1145: Get a pooled effect node instead of instantiating a new one.
	var effect := _get_dust_effect_from_pool()
	if effect == null:
		if _debug_effects:
			print("[ImpactEffectsManager] Dust effect skipped - pool exhausted (concurrent limit reached)")
		return

	# GPUParticles2D must be in the scene tree (under a CanvasItem/Viewport) to render.
	# Pooled nodes are parked as children of this autoload (a plain Node with no canvas
	# context) while idle. Move the node to the current game scene before emitting so
	# that Godot assigns it a proper canvas layer and it is actually drawn on screen.
	var scene := get_tree().current_scene
	if scene:
		effect.reparent(scene, false)
	# If there is no current scene (unlikely), leave parented to self — effect may not
	# be visible but at least it won't crash.

	effect.global_position = position

	# Rotate effect to face away from surface (in the direction of the normal)
	effect.rotation = surface_normal.angle()

	# Scale effect based on caliber
	var effect_scale := _get_effect_scale(caliber_data)
	effect.amount_ratio = effect_scale
	# Use smaller visual scale for more realistic dust particles
	effect.scale = Vector2(effect_scale * 0.8, effect_scale * 0.8)

	effect.visible = true

	# Use restart() to re-trigger a pooled one-shot effect.
	# Toggling emitting=false/true is unreliable: Godot bug #58778 causes emissions to be
	# silently dropped when the GPU-side inactive_time window has not yet expired after the
	# previous one-shot cycle. restart() bypasses that window and always starts a fresh cycle.
	effect.restart()

	if _debug_effects:
		print("[ImpactEffectsManager] Dust effect spawned from pool successfully")

	# Schedule return to pool after lifetime + cleanup_delay.
	# Matches DustEffect.tscn: lifetime=2.5, cleanup_delay=1.0 → 3.5s total.
	var return_delay := effect.lifetime + 1.0
	get_tree().create_timer(return_delay).timeout.connect(
		func() -> void: _return_dust_effect_to_pool(effect)
	)


## Spawns a blood splatter effect at the given position for lethal hits.
## @param position: World position where the lethal hit occurred.
## @param hit_direction: Direction the bullet was traveling (blood splatters opposite).
## @param caliber_data: Optional caliber data for effect scaling.
## @param is_lethal: Whether the hit was lethal (affects intensity and decal spawning).
func spawn_blood_effect(position: Vector2, hit_direction: Vector2, caliber_data: Resource = null, is_lethal: bool = true) -> void:
	# Issue #1186: performance toggle for particles
	var perf_settings: Node = get_node_or_null("/root/PerformanceSettings")
	var _particles_on: bool = perf_settings == null or perf_settings.is_particles_enabled()
	var _decals_on: bool = perf_settings == null or perf_settings.is_blood_decals_enabled()

	if not _particles_on and not _decals_on:
		return

	# Issue #969: gate per-hit logging behind debug flag to prevent file write spam at high fire rates
	if _debug_effects:
		_log_info("spawn_blood_effect called at %s, dir=%s, lethal=%s" % [position, hit_direction, is_lethal])
		print("[ImpactEffectsManager] spawn_blood_effect at ", position, " dir=", hit_direction, " lethal=", is_lethal)

	# Calculate effect scale once - used for both particles and decals
	var effect_scale := _get_effect_scale(caliber_data)
	if is_lethal:
		effect_scale *= 1.5

	# Spawn GPU particle effect only when particles are enabled (Issue #1186)
	var effect: GPUParticles2D = null
	if _particles_on:
		if _blood_effect_scene == null:
			_log_info("ERROR: _blood_effect_scene is null - cannot spawn blood effect")
			print("[ImpactEffectsManager] ERROR: _blood_effect_scene is null - blood effect NOT spawned")
		else:
			effect = _blood_effect_scene.instantiate() as GPUParticles2D
			if effect == null:
				_log_info("ERROR: Failed to instantiate blood effect from scene")
				print("[ImpactEffectsManager] ERROR: Failed to instantiate blood effect - casting failed")
			else:
				if _debug_effects:
					_log_info("Blood particle effect instantiated successfully")

				effect.global_position = position

				# Blood splatters in the direction the bullet was traveling
				effect.rotation = hit_direction.angle()

				# Scale effect based on caliber (larger calibers = more blood)
				effect.amount_ratio = clampf(effect_scale, MIN_EFFECT_SCALE, MAX_EFFECT_SCALE)
				effect.scale = Vector2(effect_scale, effect_scale)

				# Add to scene tree
				_add_effect_to_scene(effect)

				# Start emitting
				effect.emitting = true

	# Spawn blood decals only when decals are enabled (Issue #1186)
	if _decals_on:
		# Spawn small blood decals that simulate where particles land
		# Issue #969: reduced decal count to limit tree_changed signal spam at high fire rates
		# Issue #1090: scale by GameplaySettings blood_amount multiplier
		var base_decals := BLOOD_DECALS_PER_LETHAL_HIT if is_lethal else BLOOD_DECALS_PER_NONLETHAL_HIT
		var gameplay_settings: Node = get_node_or_null("/root/GameplaySettings")
		var blood_multiplier: float = gameplay_settings.get_blood_amount() if gameplay_settings else 1.0
		var num_decals := maxi(0, roundi(base_decals * blood_multiplier))
		_spawn_blood_decals_at_particle_landing(position, hit_direction, effect, num_decals)

		# Check for nearby walls and spawn wall splatters
		_spawn_wall_blood_splatter(position, hit_direction, effect_scale, is_lethal)

	# Issue #969: gate per-hit log behind debug flag
	if _debug_effects:
		_log_info("Blood effect spawned at %s (scale=%s)" % [position, effect_scale])
		print("[ImpactEffectsManager] Blood effect spawned successfully")


## Spawns a spark effect at the given position for non-lethal (armor) hits.
## @param position: World position where the non-lethal hit occurred.
## @param hit_direction: Direction the bullet was traveling.
## @param caliber_data: Optional caliber data for effect scaling.
func spawn_sparks_effect(position: Vector2, hit_direction: Vector2, caliber_data: Resource = null) -> void:
	# Issue #1186: performance toggle
	var perf_settings: Node = get_node_or_null("/root/PerformanceSettings")
	if perf_settings and not perf_settings.is_particles_enabled():
		return

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


## Spawns a muzzle flash effect at the given position when a weapon is fired.
## Creates a brief flash of particles and dynamic light that illuminates nearby walls.
## @param position: World position of the gun muzzle (where bullet exits barrel).
## @param direction: Direction the gun is pointing (flash emits in this direction).
## @param caliber_data: Optional caliber data for effect scaling.
## @param scale_override: Optional explicit scale override (ignores caliber_data if > 0).
##                        Use this for silenced weapons that need very small flash (e.g., 0.2 for ~100x100 pixels).
func spawn_muzzle_flash(position: Vector2, direction: Vector2, caliber_data: Resource = null, scale_override: float = 0.0) -> void:
	# Issue #1186: performance toggle
	var perf_settings: Node = get_node_or_null("/root/PerformanceSettings")
	if perf_settings and not perf_settings.is_particles_enabled():
		return

	if _debug_effects:
		print("[ImpactEffectsManager] spawn_muzzle_flash at ", position, " dir=", direction, " scale_override=", scale_override)

	if _muzzle_flash_scene == null:
		if _debug_effects:
			print("[ImpactEffectsManager] ERROR: _muzzle_flash_scene is null")
		return

	var effect: Node2D = _muzzle_flash_scene.instantiate() as Node2D
	if effect == null:
		if _debug_effects:
			print("[ImpactEffectsManager] ERROR: Failed to instantiate muzzle flash")
		return

	effect.global_position = position

	# Rotate effect to face the shooting direction
	effect.rotation = direction.angle()

	# Scale effect: use explicit override if provided, otherwise use caliber data
	var effect_scale: float
	if scale_override > 0.0:
		effect_scale = clampf(scale_override, MIN_EFFECT_SCALE, MAX_EFFECT_SCALE)
	else:
		effect_scale = _get_effect_scale(caliber_data)
	effect.scale = Vector2(effect_scale, effect_scale)

	# Add to scene tree
	_add_effect_to_scene(effect)

	# Track flash for enemy detection (Issue #910)
	_track_muzzle_flash(position, direction)

	if _debug_effects:
		print("[ImpactEffectsManager] Muzzle flash spawned at ", position, " with scale=", effect_scale)


## Track a muzzle flash for enemy detection (Issue #910).
func _track_muzzle_flash(position: Vector2, direction: Vector2) -> void:
	var flash_data := {
		"position": position,
		"direction": direction.normalized(),
		"timestamp": Time.get_ticks_msec() / 1000.0
	}
	_active_muzzle_flashes.append(flash_data)
	while _active_muzzle_flashes.size() > MAX_TRACKED_FLASHES:
		_active_muzzle_flashes.pop_front()


## Get active muzzle flashes for enemy detection (Issue #910).
## Returns array of dictionaries with: position, direction, age (seconds).
func get_active_muzzle_flashes() -> Array:
	var current_time := Time.get_ticks_msec() / 1000.0
	_active_muzzle_flashes = _active_muzzle_flashes.filter(
		func(f): return current_time - f.timestamp < FLASH_TRACKING_MAX_AGE
	)
	var result: Array = []
	for flash in _active_muzzle_flashes:
		result.append({
			"position": flash.position,
			"direction": flash.direction,
			"age": current_time - flash.timestamp
		})
	return result


## Spawns a flashbang visual effect at the given position.
## Creates a bright flash of light that illuminates the area but respects walls.
## Uses shadow_enabled PointLight2D so light doesn't pass through walls (Issue #469).
## @param position: World position where the flashbang exploded.
## @param radius: Effect radius for scaling the light coverage.
func spawn_flashbang_effect(position: Vector2, radius: float = 400.0) -> void:
	if _debug_effects:
		print("[ImpactEffectsManager] spawn_flashbang_effect at ", position, " radius=", radius)

	if _flashbang_effect_scene == null:
		if _debug_effects:
			print("[ImpactEffectsManager] ERROR: _flashbang_effect_scene is null")
		return

	var effect: Node2D = _flashbang_effect_scene.instantiate() as Node2D
	if effect == null:
		if _debug_effects:
			print("[ImpactEffectsManager] ERROR: Failed to instantiate flashbang effect")
		return

	effect.global_position = position

	# Set effect radius to scale the light properly
	if effect.has_method("set_effect_radius"):
		effect.set_effect_radius(radius)

	# Add to scene tree
	_add_effect_to_scene(effect)

	_log_info("Flashbang effect spawned at %s (radius=%d)" % [position, radius])
	if _debug_effects:
		print("[ImpactEffectsManager] Flashbang effect spawned at ", position)


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

	# Log scheduled count unconditionally (matches Feb 16 backup behavior, enables log verification)
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

	# Remove oldest off-screen decals if limit exceeded (0 = unlimited, no cleanup).
	# Issue #1747: prefer culling decals outside the player's viewport first.
	if MAX_BLOOD_DECALS > 0:
		while _blood_decals.size() > MAX_BLOOD_DECALS:
			_remove_oldest_offscreen_decal()

	if _debug_effects:
		print("[ImpactEffectsManager] Delayed blood decal spawned at ", landing_pos)


## Removes one blood decal that is outside the player's viewport.
## Issue #1747: Prefer culling off-screen decals so that decals visible to the
## player are never removed first.  Only falls back to removing the oldest
## on-screen decal when every tracked decal is currently inside a viewport
## (e.g. very small map with camera covering the whole level).
## Returns true if a decal was removed, false if the list is now empty.
func _remove_oldest_offscreen_decal() -> bool:
	# Build the visible world-space rectangle from the active Camera2D.
	var viewport_rects: Array[Rect2] = []
	var camera: Camera2D = null
	var current_scene := get_tree().current_scene if get_tree() else null
	if current_scene:
		# Try the "camera" group first (fast path used by PlayerCamera and others).
		var cameras := get_tree().get_nodes_in_group("camera") if get_tree() else []
		if cameras.is_empty():
			# Fallback: walk the scene tree to find any Camera2D.
			cameras = []
			_collect_cameras(current_scene, cameras)
		for cam in cameras:
			if cam is Camera2D and cam.enabled and is_instance_valid(cam):
				camera = cam as Camera2D
				break

	if camera:
		var viewport_size: Vector2 = camera.get_viewport_rect().size
		var cam_center: Vector2 = camera.get_screen_center_position()
		var half: Vector2 = viewport_size * 0.5
		viewport_rects.append(Rect2(cam_center - half, viewport_size))

	# Walk front-to-back to find the oldest off-screen decal.
	for i in range(_blood_decals.size()):
		var decal: Node2D = _blood_decals[i] as Node2D
		if decal == null or not is_instance_valid(decal):
			_blood_decals.remove_at(i)
			return true
		var on_screen := false
		if viewport_rects.is_empty():
			on_screen = false  # no camera info → treat as off-screen (safe to remove)
		else:
			for rect in viewport_rects:
				if rect.has_point(decal.global_position):
					on_screen = true
					break
		if not on_screen:
			_blood_decals.remove_at(i)
			decal.queue_free()
			return true

	# All decals are on-screen — fall back to removing the oldest one to honour the cap.
	if _blood_decals.size() > 0:
		var oldest := _blood_decals.pop_front() as Node2D
		if oldest and is_instance_valid(oldest):
			oldest.queue_free()
		return true

	return false


## Recursively collects all Camera2D nodes under a parent node.
func _collect_cameras(parent: Node, result: Array) -> void:
	for child in parent.get_children():
		if child is Camera2D:
			result.append(child)
		if child.get_child_count() > 0:
			_collect_cameras(child, result)


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

	# Issue #969: gate per-hit log behind debug flag
	if _debug_effects:
		_log_info("Wall found for blood splatter at %s (dist=%d px)" % [wall_hit_pos, hit_position.distance_to(wall_hit_pos)])
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

	# Remove oldest off-screen decals if limit exceeded (0 = unlimited, no cleanup).
	# Issue #1747: prefer culling decals outside the player's viewport first.
	if MAX_BLOOD_DECALS > 0:
		while _blood_decals.size() > MAX_BLOOD_DECALS:
			_remove_oldest_offscreen_decal()

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


## Clears all persistent effects (blood decals, bullet holes, penetration holes, and scorch marks).
## Call this on scene transitions.
func clear_all_persistent_effects() -> void:
	clear_blood_decals()
	clear_bullet_holes()
	clear_penetration_holes()
	clear_scorch_marks()


## Called when the scene tree changes. Detects scene transitions and clears stale references.
func _on_tree_changed() -> void:
	var current_scene := get_tree().current_scene
	if current_scene != _last_scene:
		_log_info("Scene changed - clearing all stale effect references")
		# Clear arrays of stale references (nodes are already freed by scene change)
		_blood_decals.clear()
		_bullet_holes.clear()
		_penetration_holes.clear()
		_scorch_marks.clear()
		_last_scene = current_scene


## Performs warmup to pre-compile all particle effect shaders.
## This prevents the noticeable freeze on first shot when hitting enemies (Issue #343).
##
## The freeze occurs because GPUParticles2D shaders are compiled just-in-time by the GPU
## driver the first time they're used. This warmup ensures all shaders are compiled during
## level loading, before gameplay begins.
##
## IMPORTANT: Shader compilation only happens when particles are ACTUALLY RENDERED on screen.
## Simply setting emitting=true with off-screen positions (-10000, -10000) doesn't work because
## the GPU may cull particles outside the viewport frustum before compiling shaders.
##
## Solution: We position particles at the camera center (within viewport) but make them
## nearly invisible using modulate alpha. This forces the GPU to compile shaders while
## keeping the warmup visually imperceptible to players.
##
## References:
## - https://github.com/godotengine/godot/issues/34627
## - https://github.com/godotengine/godot/issues/87891
## - https://github.com/godotengine/godot/issues/76241
## - https://forum.godotengine.org/t/particles-huge-lag-spike-on-first-instance/45839
## - https://forum.godotengine.org/t/gpuparticles2d-is-hanginging-the-first-time-emitting-is-set-true/84587
func _warmup_particle_shaders() -> void:
	if _warmup_completed:
		return

	_log_info("Starting particle shader warmup (Issue #343 fix)...")
	var start_time := Time.get_ticks_msec()

	# Track how many effects we warmed up
	var warmed_up_count := 0
	var warmup_nodes: Array[Node] = []

	# Get viewport center for positioning (particles must be on-screen to compile shaders)
	# Default to reasonable center position if viewport not available yet
	var warmup_pos := Vector2(400, 300)
	var viewport := get_viewport()
	if viewport:
		var viewport_size := viewport.get_visible_rect().size
		warmup_pos = viewport_size / 2.0

	# Get scene root for adding effects
	var scene_root := get_tree().current_scene

	# --- PART 1: Warmup GPU particle effects ---
	# Warmup each effect type by instantiating, emitting, and letting GPU compile shaders
	var particle_effects_to_warmup: Array[PackedScene] = [
		_dust_effect_scene,
		_blood_effect_scene,
		_sparks_effect_scene
	]

	var particle_effect_names: Array[String] = ["DustEffect", "BloodEffect", "SparksEffect"]

	for i in range(particle_effects_to_warmup.size()):
		var scene := particle_effects_to_warmup[i]
		var effect_name := particle_effect_names[i]

		if scene == null:
			if _debug_effects:
				print("[ImpactEffectsManager] Warmup: %s scene is null, skipping" % effect_name)
			continue

		var effect: GPUParticles2D = scene.instantiate() as GPUParticles2D
		if effect == null:
			if _debug_effects:
				print("[ImpactEffectsManager] Warmup: Failed to instantiate %s" % effect_name)
			continue

		# Position within viewport (on-screen) so GPU actually compiles shaders
		# Particles outside the frustum may be culled before shader compilation
		effect.global_position = warmup_pos

		# Make particles nearly invisible but still rendered (alpha must be > 0)
		# This forces GPU to compile shaders while keeping warmup imperceptible
		effect.modulate = Color(1, 1, 1, 0.01)

		# Ensure the effect is rendered at the lowest z-index (behind everything)
		effect.z_index = -100

		# Add to the current scene so it's rendered in the proper context
		# (Adding to autoload may have different rendering behavior)
		if scene_root:
			scene_root.add_child(effect)
		else:
			# Fallback to autoload if no scene loaded yet
			add_child(effect)

		# Start emitting to trigger shader compilation
		effect.emitting = true

		if _debug_effects:
			print("[ImpactEffectsManager] Warmup: %s emitting at %s (alpha=0.01)" % [effect_name, warmup_pos])

		warmed_up_count += 1
		warmup_nodes.append(effect)

	# --- PART 2: Warmup blood decal (Sprite2D with GradientTexture2D) ---
	# Blood decals also use GradientTexture2D which may trigger shader compilation
	if _blood_decal_scene:
		var decal: Node2D = _blood_decal_scene.instantiate() as Node2D
		if decal:
			decal.global_position = warmup_pos
			# Make nearly invisible but still rendered
			decal.modulate = Color(1, 1, 1, 0.01)
			decal.z_index = -100

			if scene_root:
				scene_root.add_child(decal)
			else:
				add_child(decal)

			if _debug_effects:
				print("[ImpactEffectsManager] Warmup: BloodDecal at %s (alpha=0.01)" % warmup_pos)

			warmed_up_count += 1
			warmup_nodes.append(decal)

	# --- PART 3: Warmup bullet hole if available ---
	if _bullet_hole_scene:
		var hole: Node2D = _bullet_hole_scene.instantiate() as Node2D
		if hole:
			hole.global_position = warmup_pos
			hole.modulate = Color(1, 1, 1, 0.01)
			hole.z_index = -100

			if scene_root:
				scene_root.add_child(hole)
			else:
				add_child(hole)

			if _debug_effects:
				print("[ImpactEffectsManager] Warmup: BulletHole at %s (alpha=0.01)" % warmup_pos)

			warmed_up_count += 1
			warmup_nodes.append(hole)

	# --- PART 4: Warmup muzzle flash if available ---
	# Muzzle flash uses both GPUParticles2D and PointLight2D
	if _muzzle_flash_scene:
		var flash: Node2D = _muzzle_flash_scene.instantiate() as Node2D
		if flash:
			flash.global_position = warmup_pos
			flash.modulate = Color(1, 1, 1, 0.01)
			flash.z_index = -100

			if scene_root:
				scene_root.add_child(flash)
			else:
				add_child(flash)

			if _debug_effects:
				print("[ImpactEffectsManager] Warmup: MuzzleFlash at %s (alpha=0.01)" % warmup_pos)

			warmed_up_count += 1
			warmup_nodes.append(flash)

	# --- PART 5: Warmup flashbang effect if available ---
	# Flashbang effect uses PointLight2D with shadow_enabled (Issue #469)
	if _flashbang_effect_scene:
		var flashbang: Node2D = _flashbang_effect_scene.instantiate() as Node2D
		if flashbang:
			flashbang.global_position = warmup_pos
			flashbang.modulate = Color(1, 1, 1, 0.01)
			flashbang.z_index = -100

			if scene_root:
				scene_root.add_child(flashbang)
			else:
				add_child(flashbang)

			if _debug_effects:
				print("[ImpactEffectsManager] Warmup: FlashbangEffect at %s (alpha=0.01)" % warmup_pos)

			warmed_up_count += 1
			warmup_nodes.append(flashbang)

	# Wait multiple frames to ensure GPU fully processes and compiles all shaders
	# One frame may not be enough for complex particle systems
	if warmed_up_count > 0:
		# Wait 3 frames to ensure shader compilation completes
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().process_frame

		# Clean up all warmup effects
		for node in warmup_nodes:
			if is_instance_valid(node):
				node.queue_free()

	var elapsed := Time.get_ticks_msec() - start_time
	_warmup_completed = true
	_log_info("Particle shader warmup complete: %d effects warmed up in %d ms" % [warmed_up_count, elapsed])


## Spawns a flashbang visual effect at the given position with wall occlusion.
## The visual effect is only displayed if the player has line of sight to the explosion.
## This prevents the flash from being visible through walls (Issue #470).
## @param position: World position where the flashbang exploded.
## @param radius: Effect radius for the visual flash size.
func spawn_flashbang_effect_with_occlusion(position: Vector2, radius: float) -> void:
	_spawn_grenade_visual_effect(position, radius, Color(1.0, 1.0, 1.0, 0.9), "flashbang")


## Spawns an explosion visual effect at the given position with wall occlusion.
## The visual effect is only displayed if the player has line of sight to the explosion.
## This prevents the explosion flash from being visible through walls (Issue #470).
## @param position: World position where the grenade exploded.
## @param radius: Effect radius for the visual explosion size.
func spawn_explosion_effect(position: Vector2, radius: float) -> void:
	_spawn_grenade_visual_effect(position, radius, Color(1.0, 0.6, 0.2, 0.9), "explosion")


## Internal helper to spawn grenade visual effects with automatic wall occlusion.
## FIX for Issue #470 (Final): Uses ONLY PointLight2D.
## FIX for Issue #724 (Performance): Pools and limits concurrent lights.
##
## Performance optimization (Issue #724):
## - PointLight2D objects are pooled and reused instead of created/destroyed
## - Maximum concurrent lights is limited (beyond limit, effects are skipped)
## - Lights stay pooled even though shadows are enabled, so brief flashes can respect occluders
##
## @param position: World position of the explosion.
## @param radius: Effect radius for visual size.
## @param flash_color: Color of the flash effect.
## @param effect_type: Type name for logging ("flashbang" or "explosion").
func _spawn_grenade_visual_effect(position: Vector2, radius: float, flash_color: Color, effect_type: String) -> void:
	# Issue #1186: performance toggle for explosion lights
	var perf_settings: Node = get_node_or_null("/root/PerformanceSettings")
	if perf_settings and not perf_settings.is_explosion_lights_enabled():
		return

	# Check if we've hit the concurrent light limit (Issue #724 optimization)
	if _active_explosion_lights.size() >= MAX_CONCURRENT_EXPLOSION_LIGHTS:
		if _debug_effects:
			print("[ImpactEffectsManager] Skipping %s light at %s - concurrent limit (%d) reached" % [
				effect_type, position, MAX_CONCURRENT_EXPLOSION_LIGHTS])
		return

	# Use pooled light with limit check
	_create_grenade_light_with_occlusion(position, radius, flash_color, effect_type)


## Creates a PointLight2D-based flash effect for grenade explosions.
##
## ISSUE #724 OPTIMIZATION (Phase 2): PointLight2D pooling.
##
## Performance issues with multiple simultaneous lights:
## - Creating 12+ PointLight2D objects at once causes FPS drops
## - This happens even with shadows disabled
## - Each PointLight2D adds GPU draw calls regardless of shadow state
##
## Solution: Pool and reuse PointLight2D objects.
## - Lights are retrieved from pool instead of created
## - After fade-out, lights return to pool instead of being freed
## - Maximum concurrent lights is enforced to prevent overload
##
## @param position: World position of the explosion.
## @param radius: Effect radius for light size.
## @param light_color: Color of the flash.
## @param effect_type: Type name for logging ("flashbang" or "explosion").
func _create_grenade_light_with_occlusion(position: Vector2, radius: float, light_color: Color, effect_type: String) -> void:
	# Get a light from the pool (or create new if pool empty)
	var light: PointLight2D = _get_explosion_light_from_pool()
	if light == null:
		if _debug_effects:
			print("[ImpactEffectsManager] Failed to get explosion light from pool")
		return

	# Configure the light
	light.global_position = position
	light.z_index = 10  # Draw above floor but not too high
	light.color = Color(light_color.r, light_color.g, light_color.b, 1.0)
	light.visible = true

	# Use high energy for visible flash - much brighter than muzzle flash
	# Flashbang: 8.0 energy (blinding white flash)
	# Frag: 6.0 energy (orange explosion)
	if effect_type == "flashbang":
		light.energy = 8.0
		light.texture_scale = radius / 100.0
	else:
		light.energy = 6.0
		light.texture_scale = radius / 80.0

	# Track as active
	_active_explosion_lights.append(light)

	# Animate the light: fade out over 0.4s with ease-out curve
	var fade_duration := 0.4 if effect_type == "flashbang" else 0.3
	var tween := light.create_tween()
	tween.tween_property(light, "energy", 0.0, fade_duration).set_ease(Tween.EASE_OUT)
	# Return to pool instead of freeing
	tween.tween_callback(_return_explosion_light_to_pool.bind(light))


## Returns the cached light texture for explosion effects.
## Issue #724 optimization: Creating GradientTexture2D every explosion is expensive
## because it causes GPU texture uploads. We cache and reuse the texture instead.
func _get_cached_light_texture() -> GradientTexture2D:
	if _cached_explosion_light_texture == null:
		_cached_explosion_light_texture = _create_light_texture()
	return _cached_explosion_light_texture


## Creates a simple white radial gradient texture for the light.
## Note: This is called once and cached via _get_cached_light_texture().
func _create_light_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0)])
	gradient.offsets = PackedFloat32Array([0.0, 1.0])

	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 256
	texture.height = 256

	return texture


# =============================================================================
# Dust Effect Pool Management (Issue #1145 Optimization)
# =============================================================================


## Initializes the dust effect pool with pre-created GPUParticles2D nodes.
## Called once during _ready() so all allocations happen at load time, not during gameplay.
func _init_dust_effect_pool() -> void:
	if _dust_effect_scene == null:
		_log_info("Dust effect pool: scene not loaded, skipping pool init")
		return

	for i in range(DUST_EFFECT_POOL_SIZE):
		var effect := _create_pooled_dust_effect()
		if effect != null:
			_dust_effect_pool.append(effect)

	_log_info("Dust effect pool initialized: %d effects pre-created" % _dust_effect_pool.size())


## Creates a single pooled GPUParticles2D dust node, parented to the autoload so it persists
## across scene changes. The node is hidden and not emitting while idle.
func _create_pooled_dust_effect() -> GPUParticles2D:
	if _dust_effect_scene == null:
		return null

	var effect: GPUParticles2D = _dust_effect_scene.instantiate() as GPUParticles2D
	if effect == null:
		return null

	# Remove auto-cleanup script to prevent queue_free — the pool manages lifetime.
	# The effect_cleanup.gd script calls queue_free() after lifetime+delay which would
	# destroy our pooled node. We use a Timer-based return-to-pool instead.
	if effect.get_script() != null:
		effect.set_script(null)

	effect.visible = false
	effect.emitting = false

	# Add to autoload so it persists across scene changes
	add_child(effect)

	return effect


## Returns a dust effect node from the pool, or null if the pool is exhausted
## and the concurrent cap is reached (oldest active node is recycled in that case).
func _get_dust_effect_from_pool() -> GPUParticles2D:
	# Enforce concurrent limit to prevent FPS drops at high fire rates.
	if _dust_effects_active >= MAX_CONCURRENT_DUST_EFFECTS:
		if _debug_effects:
			print("[ImpactEffectsManager] Dust pool: concurrent limit %d reached, skipping" % MAX_CONCURRENT_DUST_EFFECTS)
		return null

	var effect: GPUParticles2D = null
	if _dust_effect_pool.size() > 0:
		effect = _dust_effect_pool.pop_back()
	else:
		# Pool empty but under cap — create a new node on-demand.
		effect = _create_pooled_dust_effect()
		if _debug_effects and effect != null:
			print("[ImpactEffectsManager] Dust pool empty, created new node")

	if effect != null:
		_dust_effects_active += 1

	return effect


## Returns a dust effect node to the pool after it finishes emitting.
## Reparents the node back to the autoload so it persists across scene changes.
func _return_dust_effect_to_pool(effect: GPUParticles2D) -> void:
	_dust_effects_active = maxi(0, _dust_effects_active - 1)

	if not is_instance_valid(effect):
		return

	effect.emitting = false
	effect.visible = false

	# Move back to the autoload so it survives scene transitions.
	# get_parent() may be null if the scene was freed while the effect was active.
	if effect.get_parent() != self:
		effect.reparent(self, false)

	_dust_effect_pool.append(effect)

	if _debug_effects:
		print("[ImpactEffectsManager] Dust effect returned to pool (pool: %d, active: %d)" % [
			_dust_effect_pool.size(), _dust_effects_active])


# =============================================================================
# Explosion Light Pool Management (Issue #724 Optimization)
# =============================================================================


## Initializes the explosion light pool with pre-created PointLight2D objects.
## This is called once during _ready() to avoid runtime allocation.
func _init_explosion_light_pool() -> void:
	# Pre-cache the texture first
	_get_cached_light_texture()

	# Create the pool of PointLight2D objects
	for i in range(EXPLOSION_LIGHT_POOL_SIZE):
		var light := _create_pooled_explosion_light()
		_explosion_light_pool.append(light)

	_log_info("Explosion light pool initialized: %d lights pre-created" % EXPLOSION_LIGHT_POOL_SIZE)


## Creates a single PointLight2D configured for explosion effects.
## The light is initially hidden and added to the scene tree.
func _create_pooled_explosion_light() -> PointLight2D:
	var light := PointLight2D.new()
	light.visible = false
	light.z_index = 10
	# Issue #1825: flash and explosion lights must respect LightOccluder2D blockers in the level.
	# Keep the nodes pooled to limit the runtime cost of enabling shadows.
	light.shadow_enabled = true
	light.texture = _get_cached_light_texture()

	# Add to scene tree (as child of autoload so it persists)
	add_child(light)

	return light


## Gets an explosion light from the pool.
## Returns a ready-to-use PointLight2D, or null if pool is exhausted and limit reached.
func _get_explosion_light_from_pool() -> PointLight2D:
	# Try to get from pool first
	if _explosion_light_pool.size() > 0:
		var light: PointLight2D = _explosion_light_pool.pop_back()
		if _debug_effects:
			print("[ImpactEffectsManager] Light retrieved from pool (pool: %d, active: %d)" % [
				_explosion_light_pool.size(), _active_explosion_lights.size()])
		return light

	# Pool empty - check if we can create a new one
	if _active_explosion_lights.size() < MAX_CONCURRENT_EXPLOSION_LIGHTS:
		var light := _create_pooled_explosion_light()
		if _debug_effects:
			print("[ImpactEffectsManager] Created new light (pool empty, active: %d)" % _active_explosion_lights.size())
		return light

	# Pool empty and at limit - try to recycle the oldest active light
	if _active_explosion_lights.size() > 0:
		var oldest: PointLight2D = _active_explosion_lights.pop_front()
		# Stop any existing tween
		var tweens := oldest.get_tree().get_processed_tweens()
		for tween in tweens:
			if tween.is_valid():
				# Can't check tween target, so just reset the light
				pass
		oldest.visible = false
		oldest.energy = 0.0
		if _debug_effects:
			print("[ImpactEffectsManager] Recycled oldest active light")
		return oldest

	return null


## Returns an explosion light to the pool after it finishes animating.
func _return_explosion_light_to_pool(light: PointLight2D) -> void:
	if not is_instance_valid(light):
		return

	# Remove from active tracking
	var idx := _active_explosion_lights.find(light)
	if idx >= 0:
		_active_explosion_lights.remove_at(idx)

	# Reset and hide
	light.visible = false
	light.energy = 0.0

	# Return to pool
	_explosion_light_pool.append(light)

	if _debug_effects:
		print("[ImpactEffectsManager] Light returned to pool (pool: %d, active: %d)" % [
			_explosion_light_pool.size(), _active_explosion_lights.size()])


## Creates a radial gradient texture for grenade flash effects.
## @param radius: The radius of the effect in pixels.
## @return: A radial gradient texture.
func _create_radial_gradient_texture(radius: int) -> GradientTexture2D:
	var gradient := Gradient.new()
	# Center is bright, fades to transparent at edges
	gradient.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0.5), Color(1, 1, 1, 0)])
	gradient.offsets = PackedFloat32Array([0.0, 0.3, 1.0])

	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = radius * 2
	texture.height = radius * 2

	return texture


# =============================================================================
# Explosion Scorch Marks (Issue #1005)
# =============================================================================


## Active scorch marks for cleanup management.
var _scorch_marks: Array = []


## Spawns an explosion scorch mark on the floor at the given position.
## Scorch marks persist as visual evidence of grenade explosions.
## @param position: World position where the grenade exploded.
## @param scorch_radius: Radius of the scorch mark in pixels.
## @param scorch_alpha: Opacity of the scorch mark (0.0 to 1.0).
## @param grenade_type: Type of grenade for logging ("flashbang", "frag", "defensive").
func spawn_explosion_scorch_mark(position: Vector2, scorch_radius: float, scorch_alpha: float, grenade_type: String) -> void:
	if _debug_effects:
		print("[ImpactEffectsManager] spawn_explosion_scorch_mark at ", position, " radius=", scorch_radius, " alpha=", scorch_alpha, " type=", grenade_type)

	if _explosion_scorch_mark_scene == null:
		if _debug_effects:
			print("[ImpactEffectsManager] ExplosionScorchMark scene not loaded, skipping")
		return

	var scorch_mark: Node = _explosion_scorch_mark_scene.instantiate()
	if scorch_mark == null:
		if _debug_effects:
			print("[ImpactEffectsManager] ERROR: Failed to instantiate scorch mark")
		return

	# Configure scorch mark properties
	scorch_mark.global_position = position
	scorch_mark.scorch_radius = scorch_radius
	scorch_mark.scorch_alpha = scorch_alpha
	scorch_mark.grenade_type = grenade_type

	# Add to scene
	_add_effect_to_scene(scorch_mark)

	# Track for cleanup management
	_scorch_marks.append(scorch_mark)

	_log_info("Spawned %s scorch mark at %s (radius: %.1f, alpha: %.2f)" % [
		grenade_type, str(position), scorch_radius, scorch_alpha])


## Clears all scorch marks from the scene.
## Call this on scene transitions or when cleaning up.
func clear_scorch_marks() -> void:
	for mark in _scorch_marks:
		if mark and is_instance_valid(mark):
			mark.queue_free()
	_scorch_marks.clear()
	if _debug_effects:
		print("[ImpactEffectsManager] All scorch marks cleared")

