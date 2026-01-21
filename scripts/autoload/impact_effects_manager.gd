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
##
## Fully procedural blood system (inspired by First Cut: Samurai Duel):
## - All blood particles use physics-based collision detection
## - No GPU particles for blood - everything collides with walls
## - Blood travels in bullet direction realistically
## - Varied particle counts and patterns based on hit context
## - Blood spawns decals/puddles where it lands

## Preloaded particle effect scenes.
var _dust_effect_scene: PackedScene = null
var _sparks_effect_scene: PackedScene = null
var _blood_decal_scene: PackedScene = null
var _blood_particle_scene: PackedScene = null

## Default effect scale for calibers without explicit setting.
const DEFAULT_EFFECT_SCALE: float = 1.0

## Minimum effect scale (prevents invisible effects).
const MIN_EFFECT_SCALE: float = 0.3

## Maximum effect scale (prevents overwhelming effects).
const MAX_EFFECT_SCALE: float = 2.0

## Maximum number of blood decals before oldest ones are removed.
const MAX_BLOOD_DECALS: int = 200

## Number of blood particles to spawn per hit (base count for non-lethal).
const BASE_BLOOD_PARTICLE_COUNT: int = 5

## Number of blood particles for lethal hits.
const LETHAL_BLOOD_PARTICLE_COUNT: int = 12

## Maximum blood particles per hit.
const MAX_BLOOD_PARTICLE_COUNT: int = 18

## Spread angle for blood particles (radians).
## Tight spread for realistic directional blood spray.
const BLOOD_SPREAD_ANGLE: float = 0.35

## Active blood decals for cleanup management.
var _blood_decals: Array[Node2D] = []

## Enable/disable debug logging for effect spawning.
var _debug_effects: bool = false


func _ready() -> void:
	_preload_effect_scenes()


## Preloads all particle effect scenes for efficient instantiation.
func _preload_effect_scenes() -> void:
	# Load effect scenes if they exist
	var dust_path := "res://scenes/effects/DustEffect.tscn"
	var sparks_path := "res://scenes/effects/SparksEffect.tscn"
	var blood_decal_path := "res://scenes/effects/BloodDecal.tscn"
	var blood_particle_path := "res://scenes/effects/BloodParticle.tscn"

	if ResourceLoader.exists(dust_path):
		_dust_effect_scene = load(dust_path)
		if _debug_effects:
			print("[ImpactEffectsManager] Loaded DustEffect scene")
	else:
		push_warning("ImpactEffectsManager: DustEffect scene not found at " + dust_path)

	if ResourceLoader.exists(sparks_path):
		_sparks_effect_scene = load(sparks_path)
		if _debug_effects:
			print("[ImpactEffectsManager] Loaded SparksEffect scene")
	else:
		push_warning("ImpactEffectsManager: SparksEffect scene not found at " + sparks_path)

	if ResourceLoader.exists(blood_decal_path):
		_blood_decal_scene = load(blood_decal_path)
		if _debug_effects:
			print("[ImpactEffectsManager] Loaded BloodDecal scene")
	else:
		if _debug_effects:
			print("[ImpactEffectsManager] BloodDecal scene not found (optional)")

	if ResourceLoader.exists(blood_particle_path):
		_blood_particle_scene = load(blood_particle_path)
		if _debug_effects:
			print("[ImpactEffectsManager] Loaded BloodParticle scene")
	else:
		push_warning("ImpactEffectsManager: BloodParticle scene not found - blood effects disabled")


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

	var effect := _dust_effect_scene.instantiate() as GPUParticles2D
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


## Spawns a fully procedural blood splatter effect at the given position.
## All particles use physics-based collision detection - no GPU particles.
## @param position: World position where the hit occurred.
## @param hit_direction: Direction the bullet was traveling (blood splatters in this direction).
## @param caliber_data: Optional caliber data for effect scaling.
## @param is_lethal: Whether the hit was lethal (affects intensity and particle count).
## @param target_velocity: Optional velocity of the target when hit.
## @param distance: Optional distance from shooter to target.
## @param impact_angle: Optional angle of impact relative to target surface.
func spawn_blood_effect(
	position: Vector2,
	hit_direction: Vector2,
	caliber_data: Resource = null,
	is_lethal: bool = true,
	target_velocity: Vector2 = Vector2.ZERO,
	distance: float = 0.0,
	impact_angle: float = 0.0
) -> void:
	if _debug_effects:
		print("[ImpactEffectsManager] spawn_blood_effect at ", position, " dir=", hit_direction, " lethal=", is_lethal)

	# Get effect scale from caliber data
	var effect_scale := _get_effect_scale(caliber_data)

	# Calculate intensity based on lethality
	var intensity := effect_scale
	if is_lethal:
		intensity *= 1.5

	# Spawn physics-based blood particles (the only blood particle type now)
	_spawn_blood_particles(position, hit_direction, intensity, is_lethal, target_velocity, distance, impact_angle)

	# Spawn immediate decal at hit location (main impact point)
	if is_lethal:
		_spawn_blood_decal(position, hit_direction, intensity * 0.7)

	if _debug_effects:
		print("[ImpactEffectsManager] Blood effect spawned (procedural system)")


## Spawns physics-based blood particles that collide with walls.
## @param position: Starting position for particles.
## @param hit_direction: Main direction for particle travel.
## @param intensity: Intensity multiplier.
## @param is_lethal: Whether the hit was lethal.
## @param target_velocity: Velocity of the target when hit.
## @param distance: Distance from shooter to target.
## @param impact_angle: Angle of impact.
func _spawn_blood_particles(
	position: Vector2,
	hit_direction: Vector2,
	intensity: float,
	is_lethal: bool,
	target_velocity: Vector2 = Vector2.ZERO,
	distance: float = 0.0,
	impact_angle: float = 0.0
) -> void:
	if _blood_particle_scene == null:
		# Fallback: spawn decals directly without physics particles
		_spawn_fallback_decals(position, hit_direction, intensity, is_lethal)
		return

	# Calculate particle count based on lethality and intensity
	var base_count := LETHAL_BLOOD_PARTICLE_COUNT if is_lethal else BASE_BLOOD_PARTICLE_COUNT

	# Apply intensity and add randomization
	var particle_count := int(base_count * intensity * randf_range(0.85, 1.15))
	particle_count = clampi(particle_count, 2, MAX_BLOOD_PARTICLE_COUNT)

	if _debug_effects:
		print("[ImpactEffectsManager] Spawning ", particle_count, " blood particles")

	# Normalize hit direction for consistent behavior
	var normalized_direction := hit_direction.normalized()
	if normalized_direction.length() < 0.1:
		normalized_direction = Vector2.RIGHT  # Fallback direction

	# Spawn particles with varied parameters
	for i in range(particle_count):
		var particle := _blood_particle_scene.instantiate() as Node2D
		if particle == null:
			continue

		# Offset spawn position slightly in the hit direction to avoid spawning inside walls
		var spawn_offset := normalized_direction * randf_range(2.0, 6.0)
		particle.global_position = position + spawn_offset

		# Initialize particle with contextual parameters
		# Vary intensity per particle for natural look
		var particle_intensity := intensity * randf_range(0.6, 1.4)
		var spread := BLOOD_SPREAD_ANGLE * randf_range(0.8, 1.2)

		if particle.has_method("initialize"):
			particle.initialize(
				normalized_direction,
				particle_intensity,
				spread,
				target_velocity,
				distance,
				impact_angle
			)

		# Add to scene
		_add_effect_to_scene(particle)


## Fallback decal spawning when blood particle scene is not available.
## @param position: Origin position for decals.
## @param hit_direction: Direction for decal spread.
## @param intensity: Intensity multiplier.
## @param is_lethal: Whether the hit was lethal.
func _spawn_fallback_decals(position: Vector2, hit_direction: Vector2, intensity: float, is_lethal: bool) -> void:
	if _blood_decal_scene == null:
		return

	# Calculate number of decals to spawn
	var decal_count := 2 if not is_lethal else int(4 * intensity)
	decal_count = clampi(decal_count, 1, 6)

	for i in range(decal_count):
		# Vary position in the hit direction with tight spread
		var spread_angle := randf_range(-0.4, 0.4)
		var spread_direction := hit_direction.rotated(spread_angle)
		var dist := randf_range(10.0, 40.0) * intensity

		var decal_position := position + spread_direction * dist
		_spawn_blood_decal(decal_position, hit_direction, intensity * randf_range(0.4, 0.9))


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

	var effect := _sparks_effect_scene.instantiate() as GPUParticles2D
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


## Spawns a persistent blood decal (stain) on the floor.
## @param position: World position for the decal.
## @param hit_direction: Direction the blood was traveling (affects elongation).
## @param intensity: Scale multiplier for decal size.
func _spawn_blood_decal(position: Vector2, hit_direction: Vector2, intensity: float = 1.0) -> void:
	if _blood_decal_scene == null:
		return

	var decal := _blood_decal_scene.instantiate() as Node2D
	if decal == null:
		return

	decal.global_position = position

	# Random rotation with slight bias toward hit direction for elongated splatter effect
	var base_rotation := hit_direction.angle() if randf() > 0.3 else randf() * TAU
	decal.rotation = base_rotation + randf_range(-0.3, 0.3)

	# Scale based on intensity with randomization for variety
	var decal_scale := intensity * randf_range(0.4, 1.3)
	decal_scale = clampf(decal_scale, 0.3, 2.5)
	decal.scale = Vector2(decal_scale, decal_scale * randf_range(0.8, 1.2))

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
		print("[ImpactEffectsManager] Blood decal spawned, total: ", _blood_decals.size())


## Spawns a blood decal at a specific position (called by blood particles).
## @param position: World position for the decal.
## @param size_multiplier: Scale multiplier for the decal.
func spawn_blood_decal_at(position: Vector2, size_multiplier: float = 1.0) -> void:
	_spawn_blood_decal(position, Vector2.RIGHT, size_multiplier)


## Clears all blood decals from the scene.
## Call this on scene transitions or when cleaning up.
func clear_blood_decals() -> void:
	for decal in _blood_decals:
		if decal and is_instance_valid(decal):
			decal.queue_free()
	_blood_decals.clear()
	if _debug_effects:
		print("[ImpactEffectsManager] All blood decals cleared")
