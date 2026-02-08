extends GrenadeBase
class_name AggressionGasGrenade
## Aggression gas grenade that releases a cloud making enemies fight each other.
##
## After 4 seconds, releases a gas cloud (slightly larger than frag grenade radius).
## Enemies inside the cloud become aggressive toward other enemies for 10 seconds.
## The aggression effect refreshes if enemies touch the gas again.
## The gas cloud dissipates after 20 seconds.
##
## Per issue #675 requirements:
## - через 4 секунды после активации выпускает облако газа
## - чуть больше радиуса поражения наступательной гранаты (>225px)
## - враги начинают воспринимать других врагов как врагов - атакуют их
## - атакованные враги воспринимают агрессоров как врагов и тоже отстреливаются
## - эффект длится 10 секунд и обновляется при повторном контакте
## - газ рассеивается через 20 секунд

## Effect radius for the gas cloud (slightly larger than frag grenade's 225px).
@export var effect_radius: float = 300.0

## Duration the gas cloud persists (seconds).
@export var cloud_duration: float = 20.0

## Duration of aggression effect on each enemy (seconds).
@export var aggression_duration: float = 10.0


func _ready() -> void:
	super._ready()
	# Uses default 4 second fuse from GrenadeBase


## Override to define the explosion effect - spawn gas cloud.
func _on_explode() -> void:
	# Spawn the persistent aggression gas cloud
	_spawn_aggression_cloud()

	# Scatter shell casings lightly (non-lethal grenade)
	_scatter_casings(effect_radius * 0.3)


## Override explosion sound - gas release is quieter than explosive grenades.
func _play_explosion_sound() -> void:
	# Play gas release sound via AudioManager
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
		# Gas release is quieter - 1x viewport instead of 2x
		var sound_range := viewport_diagonal * 1.0
		# 1 = EXPLOSION type, 2 = NEUTRAL source
		sound_propagation.emit_sound(1, global_position, 2, self, sound_range)


## Get the effect radius for this grenade type.
func _get_effect_radius() -> float:
	return effect_radius


## Spawn the persistent aggression gas cloud at the explosion position.
func _spawn_aggression_cloud() -> void:
	var cloud := AggressionCloud.new()
	cloud.name = "AggressionCloud"
	cloud.global_position = global_position
	cloud.cloud_radius = effect_radius
	cloud.cloud_duration = cloud_duration
	cloud.aggression_effect_duration = aggression_duration

	# Add to current scene (not as child of grenade, since grenade will be freed)
	get_tree().current_scene.add_child(cloud)

	FileLogger.info("[AggressionGasGrenade] Gas cloud spawned at %s (radius=%.0f, duration=%.0fs)" % [
		str(global_position), effect_radius, cloud_duration
	])


## Spawn visual gas release effect at explosion position.
func _spawn_gas_release_effect() -> void:
	var impact_manager: Node = get_node_or_null("/root/ImpactEffectsManager")

	if impact_manager and impact_manager.has_method("spawn_gas_effect"):
		impact_manager.spawn_gas_effect(global_position, effect_radius)
	else:
		# The AggressionCloud handles its own visual, so no fallback needed here
		pass
