extends Area2D
## Target that reacts when hit by a bullet.
##
## When hit, the target shows a visual reaction (color change)
## and can optionally be destroyed after a delay.

## Color to change to when hit.
@export var hit_color: Color = Color(0.2, 0.8, 0.2, 1.0)

## Original color before being hit.
@export var normal_color: Color = Color(0.9, 0.2, 0.2, 1.0)

## Whether to destroy the target after being hit.
@export var destroy_on_hit: bool = false

## Delay before respawning or destroying (in seconds).
@export var respawn_delay: float = 2.0

## Reference to the sprite for color changes.
@onready var sprite: Sprite2D = $Sprite2D

## Whether the target has been hit and is in hit state.
var _is_hit: bool = false


func _ready() -> void:
	# Ensure the sprite has the normal color
	if sprite:
		sprite.modulate = normal_color


func on_hit() -> void:
	if _is_hit:
		return

	_is_hit = true

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
	if sprite:
		sprite.modulate = normal_color
