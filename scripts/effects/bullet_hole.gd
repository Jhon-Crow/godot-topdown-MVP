extends Sprite2D
## Persistent bullet hole that remains on walls after penetration.
##
## Bullet holes represent the visual damage where a bullet penetrated
## through a wall. They slowly fade over time and can be configured
## to disappear after a set duration.

## Time in seconds before the hole starts fading.
@export var fade_delay: float = 60.0

## Time in seconds for the fade-out animation.
@export var fade_duration: float = 10.0

## Whether the hole should fade out over time.
@export var auto_fade: bool = true

## Initial alpha value.
var _initial_alpha: float = 0.9


func _ready() -> void:
	_initial_alpha = modulate.a

	if auto_fade:
		_start_fade_timer()


## Starts the timer for automatic fade-out.
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
