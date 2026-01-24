extends Sprite2D
## Persistent bullet hole that remains on walls after penetration.
##
## Bullet holes represent the visual damage where a bullet penetrated
## through a wall. Holes are permanent and do not fade over time.
## Similar to Red Faction Guerrilla or Teardown visual destruction.

## Whether the hole should fade out over time.
## Default is false for permanent holes as requested.
@export var auto_fade: bool = false

## Time in seconds before the hole starts fading (only if auto_fade is true).
@export var fade_delay: float = 60.0

## Time in seconds for the fade-out animation (only if auto_fade is true).
@export var fade_duration: float = 10.0

## Initial alpha value.
var _initial_alpha: float = 0.9


func _ready() -> void:
	_initial_alpha = modulate.a

	if auto_fade:
		_start_fade_timer()


## Starts the timer for automatic fade-out.
## Only called if auto_fade is true.
func _start_fade_timer() -> void:
	# Wait for fade delay
	await get_tree().create_timer(fade_delay).timeout

	# Gradually fade out
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, fade_duration)
	tween.tween_callback(queue_free)


## Immediately removes the hole.
func remove() -> void:
	queue_free()


## Fades out the hole quickly (for cleanup).
func fade_out_quick() -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.5)
	tween.tween_callback(queue_free)
