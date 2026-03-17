extends Sprite2D
## Persistent blood decal (stain) that remains on the floor.
##
## Blood decals slowly fade over time and can be configured
## to disappear after a set duration. Characters that step
## on blood decals will leave bloody footprints.
class_name BloodDecal

## Time in seconds before the decal starts fading.
@export var fade_delay: float = 30.0

## Time in seconds for the fade-out animation.
@export var fade_duration: float = 5.0

## Whether the decal should fade out over time.
@export var auto_fade: bool = false

## Whether this decal can be stepped in (creates bloody footprints).
@export var is_puddle: bool = true

## Initial alpha value.
var _initial_alpha: float = 0.85

## Reference to FileLogger for persistent logging.
var _file_logger: Node = null


func _ready() -> void:
	_file_logger = get_node_or_null("/root/FileLogger")
	_initial_alpha = modulate.a

	# Add to blood_puddle group for distance-based detection by BloodyFeetComponent.
	# Issue #1027 Fix 24: No longer creates a per-puddle Area2D here.
	# Previously each puddle spawned an Area2D + CollisionShape2D for physics-based
	# signal detection, creating 150+ physics collision shapes with 20 enemies = 3000+
	# broadphase pair checks per frame causing 6fps drops during heavy combat.
	# BloodyFeetComponent uses its own Area2D detector with a distance fallback (every
	# 30 frames) which is sufficient for detecting blood contact without per-puddle physics.
	if is_puddle:
		add_to_group("blood_puddle")
		_log_info("Blood puddle created at %s (added to group)" % global_position)

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


## Logs to FileLogger.
func _log_info(message: String) -> void:
	var log_message := "[BloodDecal] %s" % message
	if _file_logger and _file_logger.has_method("log_info"):
		_file_logger.log_info(log_message)
