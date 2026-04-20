extends GrenadeBase
class_name ChemicalGasGrenade
## Chemical gas grenade that releases a cloud creating illusion copies (Issue #1353).
##
## Explodes on contact/landing (Issue #1367), releasing a yellow-green chemical gas cloud.
## The cloud creates visual-only illusion copies of nearby enemies.
## Unlike explosive grenades, this does NOT explode — it hisses and releases gas.
##
## Uses visual effects instead of spawning real enemy clones for performance.

## Effect radius for the gas cloud (Issue #1367: 2x bigger cloud).
@export var effect_radius: float = 600.0

## Duration the gas cloud persists (seconds).
@export var cloud_duration: float = 20.0

## Duration of each illusion copy (seconds).
@export var illusion_duration: float = 20.0

## Preloaded scene for reliable instantiation — avoids GDScript class registry failures
## (Godot bug #94150) that prevent ChemicalCloud._ready() from being called when using .new().
const ChemicalCloudScene := preload("res://scenes/effects/ChemicalCloud.tscn")

## Preloaded script used as a belt-and-suspenders fallback: after `instantiate()`
## we verify the cloud has the script attached, and re-attach via set_script()
## if the PackedScene deserialization dropped it (observed in some exported builds
## as a consequence of Godot bug #94150).
const ChemicalCloudScript := preload("res://scripts/effects/chemical_cloud.gd")

## Hiss visual pulse timer.
var _hiss_timer: float = 0.0


func _ready() -> void:
	super._ready()


## Override blink — chemical grenade pulses yellow-green instead of red.
func _update_blink_effect(delta: float) -> void:
	if not _sprite:
		return

	_hiss_timer += delta
	var pulse_speed: float
	if _time_remaining < 1.0:
		pulse_speed = 8.0
	elif _time_remaining < 2.0:
		pulse_speed = 4.0
	elif _time_remaining < 3.0:
		pulse_speed = 2.0
	else:
		pulse_speed = 1.0

	var pulse := (sin(_hiss_timer * pulse_speed * TAU) + 1.0) * 0.5
	var r := lerpf(1.0, 0.7, pulse)
	var g := lerpf(1.0, 0.9, pulse)
	var b := lerpf(1.0, 0.3, pulse)
	_sprite.modulate = Color(r, g, b, 1.0)


## Override to spawn chemical cloud instead of explosion.
func _on_explode() -> void:
	_spawn_chemical_cloud()


## Issue #1367: Explode on landing (grenade comes to rest) instead of waiting for fuse timer.
func _on_grenade_landed() -> void:
	super._on_grenade_landed()
	FileLogger.info("[ChemicalGasGrenade] Landed at %s — detonating on contact" % str(global_position))
	_explode()


## Issue #1367: Also explode on collision with walls/obstacles for immediate detonation.
func _on_body_entered(body: Node) -> void:
	super._on_body_entered(body)
	if _has_exploded:
		return
	# Only detonate on wall/obstacle collision, not on enemies
	if body is StaticBody2D or body is TileMap:
		FileLogger.info("[ChemicalGasGrenade] Hit obstacle '%s' — detonating on contact" % body.name)
		_explode()


## Override base _explode to skip explosive effects.
## Issue #1688: Visual effect starts spreading gradually when the sound starts playing.
func _explode() -> void:
	if _has_exploded:
		return
	_has_exploded = true

	FileLogger.info("[ChemicalGasGrenade] Gas released at %s!" % str(global_position))

	# Play the hiss sound first.
	_play_explosion_sound()

	# Issue #1688: Spawn cloud immediately when sound starts, with gradual grow-in
	# matching the sound duration so gas spreads progressively as the hiss plays.
	var sound_length := _get_gas_sound_length()
	FileLogger.info("[ChemicalGasGrenade] Spawning cloud with %.2fs grow-in matching sound" % sound_length)
	_spawn_chemical_cloud_with_grow_in(sound_length)

	exploded.emit(global_position, self)

	await get_tree().create_timer(0.1).timeout
	queue_free()


## Issue #1688: Get the duration of the gas release sound.
## Returns 0.0 if the stream cannot be loaded (cloud spawns immediately as fallback).
func _get_gas_sound_length() -> float:
	var stream := load("res://assets/audio/взрыв газовой гранаты.mp3") as AudioStream
	if stream:
		return stream.get_length()
	return 0.0


## Override explosion sound — quiet hiss.
func _play_explosion_sound() -> void:
	var audio_manager: Node = get_node_or_null("/root/AudioManager")
	if audio_manager and audio_manager.has_method("play_aggression_gas_release"):
		audio_manager.play_aggression_gas_release(global_position)

	var sound_propagation: Node = get_node_or_null("/root/SoundPropagation")
	if sound_propagation and sound_propagation.has_method("emit_sound"):
		var viewport := get_viewport()
		var viewport_diagonal := 1469.0
		if viewport:
			var size := viewport.get_visible_rect().size
			viewport_diagonal = sqrt(size.x * size.x + size.y * size.y)
		var sound_range := viewport_diagonal * 1.0
		sound_propagation.emit_sound(1, global_position, 2, self, sound_range)


## Get the effect radius.
func _get_effect_radius() -> float:
	return effect_radius


## Spawn the chemical gas cloud at the release position.
func _spawn_chemical_cloud() -> void:
	_spawn_chemical_cloud_with_grow_in(0.0)


## Issue #1688: Spawn the cloud immediately, growing in gradually over grow_duration seconds.
## This makes the gas start spreading when the sound starts, not after it ends.
func _spawn_chemical_cloud_with_grow_in(grow_duration: float) -> void:
	var cloud: Node2D = ChemicalCloudScene.instantiate() as Node2D
	if cloud == null:
		FileLogger.error("[ChemicalGasGrenade] ChemicalCloudScene.instantiate() returned null — aborting cloud spawn")
		return

	# Belt-and-suspenders: guarantee the ChemicalCloud script is attached.
	# Exported builds have been observed to deserialize the PackedScene without
	# the script attached (Godot bug #94150 side-effect), causing _ready() to
	# never run and the cloud to behave as a bare Node2D.
	if cloud.get_script() != ChemicalCloudScript:
		FileLogger.warning("[ChemicalGasGrenade] Instantiated cloud is missing ChemicalCloud script — attaching via set_script()")
		cloud.set_script(ChemicalCloudScript)

	cloud.name = "ChemicalCloud"
	cloud.cloud_radius = effect_radius
	cloud.cloud_duration = cloud_duration
	cloud.illusion_duration = illusion_duration
	if grow_duration > 0.0:
		cloud.grow_in_duration = grow_duration

	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		FileLogger.error("[ChemicalGasGrenade] current_scene is null — cannot attach cloud")
		cloud.queue_free()
		return
	scene_root.add_child(cloud)
	cloud.global_position = global_position

	var has_script: bool = cloud.get_script() == ChemicalCloudScript
	FileLogger.info("[ChemicalGasGrenade] Chemical cloud spawned at %s (radius=%.0f, duration=%.0fs, grow_in=%.2fs, script_attached=%s, parent=%s)" % [
		str(global_position), effect_radius, cloud_duration, grow_duration,
		str(has_script), scene_root.name
	])
