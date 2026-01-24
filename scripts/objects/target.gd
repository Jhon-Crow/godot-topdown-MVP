extends Area2D
## Target that reacts when hit by a bullet or affected by grenades.
##
## When hit, the target shows a visual reaction (color change)
## and can optionally be destroyed after a delay.
## Also supports receiving flashbang status effects (blindness/stun).

## Signal emitted when the target is hit.
signal target_hit

## Signal emitted when the target receives a status effect from grenade.
signal status_effect_received(effect_type: String, duration: float)

## Color to change to when hit.
@export var hit_color: Color = Color(0.2, 0.8, 0.2, 1.0)

## Original color before being hit.
@export var normal_color: Color = Color(0.9, 0.2, 0.2, 1.0)

## Color when blinded by flashbang.
@export var blind_color: Color = Color(1.0, 1.0, 0.5, 1.0)  # Yellow tint

## Color when stunned by flashbang.
@export var stun_color: Color = Color(0.5, 0.5, 1.0, 1.0)  # Blue tint

## Whether to destroy the target after being hit.
@export var destroy_on_hit: bool = false

## Delay before respawning or destroying (in seconds).
@export var respawn_delay: float = 2.0

## Reference to the sprite for color changes.
@onready var sprite: Sprite2D = $Sprite2D

## Whether the target has been hit and is in hit state.
var _is_hit: bool = false

## Whether the target is blinded.
var _is_blinded: bool = false

## Whether the target is stunned.
var _is_stunned: bool = false


func _ready() -> void:
	# Add to enemies group for grenade targeting
	add_to_group("enemies")

	# Ensure the sprite has the normal color
	if sprite:
		sprite.modulate = normal_color


func on_hit() -> void:
	if _is_hit:
		return

	_is_hit = true

	# Emit signal for tutorial tracking
	target_hit.emit()

	# Change color to show hit
	if sprite:
		sprite.modulate = hit_color

	# Handle destruction or respawn
	if destroy_on_hit:
		# Wait before destroying
		await get_tree().create_timer(respawn_delay).timeout
		queue_free()
	else:
		# Wait before resetting
		await get_tree().create_timer(respawn_delay).timeout
		_reset()


func _reset() -> void:
	_is_hit = false
	if sprite and not _is_blinded and not _is_stunned:
		sprite.modulate = normal_color


## Apply blindness effect from flashbang grenade.
## Targets show yellow tint when blinded.
func apply_blindness(duration: float) -> void:
	if _is_blinded:
		return

	_is_blinded = true
	status_effect_received.emit("blindness", duration)
	FileLogger.info("[Target] %s blinded for %.1f seconds" % [name, duration])

	# Show yellow tint
	if sprite:
		sprite.modulate = blind_color

	# Reset after duration
	await get_tree().create_timer(duration).timeout
	_is_blinded = false
	_update_visual_state()


## Apply stun effect from flashbang grenade.
## Targets show blue tint when stunned.
func apply_stun(duration: float) -> void:
	if _is_stunned:
		return

	_is_stunned = true
	status_effect_received.emit("stun", duration)
	FileLogger.info("[Target] %s stunned for %.1f seconds" % [name, duration])

	# Show blue tint (overrides blind color if both active)
	if sprite:
		sprite.modulate = stun_color

	# Reset after duration
	await get_tree().create_timer(duration).timeout
	_is_stunned = false
	_update_visual_state()


## Update visual state based on current status effects.
func _update_visual_state() -> void:
	if not sprite:
		return

	if _is_stunned:
		sprite.modulate = stun_color
	elif _is_blinded:
		sprite.modulate = blind_color
	elif _is_hit:
		sprite.modulate = hit_color
	else:
		sprite.modulate = normal_color
