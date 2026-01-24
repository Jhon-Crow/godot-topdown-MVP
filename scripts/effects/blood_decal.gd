extends Sprite2D
## Persistent blood decal (stain) that remains on the floor.
##
## Blood decals slowly fade over time and can be configured
## to disappear after a set duration. Blood also gradually darkens
## to simulate drying/oxidation (fresh red to dried brown).

## Time in seconds before the decal starts fading.
@export var fade_delay: float = 30.0

## Time in seconds for the fade-out animation.
@export var fade_duration: float = 5.0

## Whether the decal should fade out over time.
## Disabled by default per issue #293 - puddles should never disappear.
@export var auto_fade: bool = false

## Whether blood should gradually darken over time (drying effect).
## Enabled by default for realistic blood aging.
@export var color_aging: bool = true

## Time in seconds for blood to fully transition from fresh to dried color.
@export var aging_duration: float = 60.0

## Fresh blood color tint (applied via modulate).
## Default is slightly bright red to match fresh blood appearance.
const FRESH_BLOOD_TINT := Color(1.0, 0.9, 0.9, 0.9)

## Dried blood color tint (darker, more brown).
## Blood oxidizes over time, turning from bright red to dark brown.
const DRIED_BLOOD_TINT := Color(0.6, 0.35, 0.3, 0.85)

## Initial alpha value.
var _initial_alpha: float = 0.85


func _ready() -> void:
	_initial_alpha = modulate.a

	# Start with fresh blood color
	if color_aging:
		modulate = FRESH_BLOOD_TINT
		_start_color_aging()

	if auto_fade:
		_start_fade_timer()


## Starts gradual color transition from fresh to dried blood.
func _start_color_aging() -> void:
	var tree := get_tree()
	if tree == null:
		return

	var tween := create_tween()
	if tween == null:
		return

	# Gradual transition from fresh red to dried brown over aging_duration
	tween.tween_property(self, "modulate", DRIED_BLOOD_TINT, aging_duration)


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
