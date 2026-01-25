extends Sprite2D
## Persistent blood decal (stain) that remains on the floor.
##
## Blood decals slowly fade over time and can be configured
## to disappear after a set duration.

## Time in seconds before the decal starts fading.
@export var fade_delay: float = 30.0

## Time in seconds for the fade-out animation.
@export var fade_duration: float = 5.0

## Whether the decal should fade out over time.
@export var auto_fade: bool = false

## Initial alpha value.
var _initial_alpha: float = 0.85


func _ready() -> void:
	_initial_alpha = modulate.a

	if auto_fade:
		_start_fade_timer()


## Starts the timer for automatic fade-out.
func _start_fade_timer() -> void:
	# Wait for fade delay
	# Check if we're still valid (scene might change during wait)
	var tree := get_tree()
	if tree == null:
		return
	await tree.create_timer(fade_delay).timeout

	# Check if node is still valid after await (scene might have changed)
	if not is_instance_valid(self) or not is_inside_tree():
		return

	# Gradually fade out
	var tween := create_tween()
	if tween == null:
		queue_free()
		return
	tween.tween_property(self, "modulate:a", 0.0, fade_duration)
	tween.tween_callback(queue_free)


## Immediately removes the decal.
func remove() -> void:
	queue_free()


## Fades out the decal quickly (for cleanup).
func fade_out_quick() -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.5)
	tween.tween_callback(queue_free)
