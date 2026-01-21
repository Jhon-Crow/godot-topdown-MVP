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

## Default effect scale for calibers without explicit setting.
const DEFAULT_EFFECT_SCALE: float = 1.0

## Minimum effect scale (prevents invisible effects).
const MIN_EFFECT_SCALE: float = 0.3

## Maximum effect scale (prevents overwhelming effects).
const MAX_EFFECT_SCALE: float = 2.0

## Maximum number of blood decals before oldest ones are removed.
const MAX_BLOOD_DECALS: int = 100

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
	var blood_path := "res://scenes/effects/BloodEffect.tscn"
	var sparks_path := "res://scenes/effects/SparksEffect.tscn"
	var blood_decal_path := "res://scenes/effects/BloodDecal.tscn"

	if ResourceLoader.exists(dust_path):
		_dust_effect_scene = load(dust_path)
		if _debug_effects:
			print("[ImpactEffectsManager] Loaded DustEffect scene")
	else:
		push_warning("ImpactEffectsManager: DustEffect scene not found at " + dust_path)

	if ResourceLoader.exists(blood_path):
		_blood_effect_scene = load(blood_path)
		if _debug_effects:
			print("[ImpactEffectsManager] Loaded BloodEffect scene")
	else:
		push_warning("ImpactEffectsManager: BloodEffect scene not found at " + blood_path)

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
		# Blood decals are optional - don't warn, just log in debug mode
		if _debug_effects:
			print("[ImpactEffectsManager] BloodDecal scene not found (optional)")


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


## Spawns a blood splatter effect at the given position for lethal hits.
## @param position: World position where the lethal hit occurred.
## @param hit_direction: Direction the bullet was traveling (blood splatters opposite).
## @param caliber_data: Optional caliber data for effect scaling.
## @param is_lethal: Whether the hit was lethal (affects intensity and decal spawning).
func spawn_blood_effect(position: Vector2, hit_direction: Vector2, caliber_data: Resource = null, is_lethal: bool = true) -> void:
	if _debug_effects:
		print("[ImpactEffectsManager] spawn_blood_effect at ", position, " dir=", hit_direction, " lethal=", is_lethal)

	if _blood_effect_scene == null:
		if _debug_effects:
			print("[ImpactEffectsManager] ERROR: _blood_effect_scene is null")
		return

	var effect := _blood_effect_scene.instantiate() as GPUParticles2D
	if effect == null:
		if _debug_effects:
			print("[ImpactEffectsManager] ERROR: Failed to instantiate blood effect")
		return

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

	# Spawn blood decal on floor (persistent stain)
	if is_lethal:
		_spawn_blood_decal(position, hit_direction, effect_scale)

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
## @param hit_direction: Direction the blood was traveling (affects rotation).
## @param intensity: Scale multiplier for decal size.
func _spawn_blood_decal(position: Vector2, hit_direction: Vector2, intensity: float = 1.0) -> void:
	if _blood_decal_scene == null:
		return

	var decal := _blood_decal_scene.instantiate() as Node2D
	if decal == null:
		return

	# Position slightly offset in hit direction (blood travels before landing)
	decal.global_position = position + hit_direction.normalized() * randf_range(10.0, 30.0)

	# Random rotation for variety
	decal.rotation = randf() * TAU

	# Scale based on intensity with randomization
	var decal_scale := intensity * randf_range(0.5, 1.2)
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
		print("[ImpactEffectsManager] Blood decal spawned, total: ", _blood_decals.size())


## Clears all blood decals from the scene.
## Call this on scene transitions or when cleaning up.
func clear_blood_decals() -> void:
	for decal in _blood_decals:
		if decal and is_instance_valid(decal):
			decal.queue_free()
	_blood_decals.clear()
	if _debug_effects:
		print("[ImpactEffectsManager] All blood decals cleared")
