extends GrenadeBase
class_name ChemicalGasGrenade
## Chemical gas grenade thrown by enemies (Issue #1129).
##
## With 50% chance, enemies throw this instead of their default grenade.
## After 4 seconds, releases caustic yellow gas cloud.
## Unlike explosive grenades, this does NOT explode — it hisses and releases gas.
## All enemies in the cloud create illusory copies (2–5 per enemy) for 20 seconds.
## If the player is already under this effect, enemies throw default grenades instead.
##
## Per issue #1129 requirements:
## - с 50% вероятностью враг бросает химическую гранату вместо стандартной
## - выглядит и выделяет газ как газовая граната игрока, но газ едкого жёлтого цвета
## - эффект: все враги создают иллюзорные копии (от 2 до 5), эффект длится 20 секунд
## - иллюзорная копия выглядит и действует как обычный враг, но убивается одним выстрелом
## - все оружия иллюзорной копии наносят 5% от нормального урона
## - иллюзорные копии не останавливают пули или шрапнель
## - все иллюзорные копии врага исчезают, если убит оригинал
## - когда эффект гранаты истекает, все иллюзорные копии исчезают
## - если игрок уже под эффектом такой гранаты, все враги бросают стандартные гранаты

## Effect radius for the gas cloud (same as aggression gas grenade).
@export var effect_radius: float = 300.0

## Duration the gas cloud persists (seconds).
@export var cloud_duration: float = 20.0

## Duration of illusion effect on each enemy (seconds).
@export var illusion_duration: float = 20.0

## Hiss visual pulse timer for gas release countdown.
var _hiss_timer: float = 0.0


func _ready() -> void:
	super._ready()
	# Uses default 4 second fuse from GrenadeBase


## Override blink effect — gas grenade does NOT blink like an explosive.
## Instead it emits a subtle yellowish pulsing hiss effect.
func _update_blink_effect(delta: float) -> void:
	if not _sprite:
		return

	# Gentle yellowish pulse that intensifies as gas release approaches
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

	# Smooth sinusoidal pulse between normal and yellowish tint
	var pulse := (sin(_hiss_timer * pulse_speed * TAU) + 1.0) * 0.5
	var r := lerpf(1.0, 1.0, pulse)
	var g := lerpf(1.0, 1.0, pulse)
	var b := lerpf(1.0, 0.3, pulse)
	_sprite.modulate = Color(r, g, b, 1.0)


## Override to define the gas release effect — NOT an explosion.
func _on_explode() -> void:
	# Spawn the persistent chemical gas cloud
	_spawn_chemical_cloud()
	# No casing scatter — this is a gas release, not an explosion


## Override the base _explode to skip PowerFantasy explosion effect.
## Gas grenade releases gas quietly, it does not produce an explosive shockwave.
func _explode() -> void:
	if _has_exploded:
		return
	_has_exploded = true

	FileLogger.info("[ChemicalGasGrenade] Chemical gas released at %s!" % str(global_position))

	# NO PowerFantasy explosion effect — gas release is not an explosion

	# Play gas release sound (quiet hiss, not explosion)
	_play_explosion_sound()

	# Call gas release effect
	_on_explode()

	# Emit signal
	exploded.emit(global_position, self)

	# Destroy grenade after a short delay for effects
	await get_tree().create_timer(0.1).timeout
	queue_free()


## Override explosion sound — gas release is a quiet hiss, not a boom.
func _play_explosion_sound() -> void:
	# Play gas release sound via AudioManager (reuse aggression gas sound)
	var audio_manager: Node = get_node_or_null("/root/AudioManager")
	if audio_manager and audio_manager.has_method("play_aggression_gas_release"):
		audio_manager.play_aggression_gas_release(global_position)

	# Also emit sound for AI awareness via SoundPropagation (quieter than explosions)
	var sound_propagation: Node = get_node_or_null("/root/SoundPropagation")
	if sound_propagation and sound_propagation.has_method("emit_sound"):
		var viewport := get_viewport()
		var viewport_diagonal := 1469.0  # Default 1280x720 diagonal
		if viewport:
			var size := viewport.get_visible_rect().size
			viewport_diagonal = sqrt(size.x * size.x + size.y * size.y)
		# Gas release is quieter — 1x viewport instead of 2x
		var sound_range := viewport_diagonal * 1.0
		# 1 = EXPLOSION type, 2 = NEUTRAL source
		sound_propagation.emit_sound(1, global_position, 2, self, sound_range)


## Get the effect radius for this grenade type.
func _get_effect_radius() -> float:
	return effect_radius


## Spawn the persistent chemical gas cloud at the gas release position.
func _spawn_chemical_cloud() -> void:
	var cloud := ChemicalCloud.new()
	cloud.name = "ChemicalCloud"
	cloud.global_position = global_position
	cloud.cloud_radius = effect_radius
	cloud.cloud_duration = cloud_duration
	cloud.illusion_effect_duration = illusion_duration

	# Add to current scene (not as child of grenade, since grenade will be freed)
	get_tree().current_scene.add_child(cloud)

	FileLogger.info("[ChemicalGasGrenade] Chemical cloud spawned at %s (radius=%.0f, duration=%.0fs)" % [
		str(global_position), effect_radius, cloud_duration
	])
