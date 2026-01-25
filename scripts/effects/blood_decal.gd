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

## Area2D for collision detection (allows characters to detect stepping in blood).
var _puddle_area: Area2D = null


## Reference to FileLogger for persistent logging.
var _file_logger: Node = null


func _ready() -> void:
	_file_logger = get_node_or_null("/root/FileLogger")
	_initial_alpha = modulate.a

	# Add to blood_puddle group for detection
	if is_puddle:
		add_to_group("blood_puddle")
		_setup_puddle_area()
		_log_info("Blood puddle created at %s (added to group)" % global_position)

	if auto_fade:
		_start_fade_timer()


## Creates an Area2D for detecting when characters step in this blood puddle.
func _setup_puddle_area() -> void:
	_puddle_area = Area2D.new()
	_puddle_area.name = "PuddleArea"

	# Set collision layer 7 for blood puddles (2^6 = 64)
	_puddle_area.collision_layer = 64
	_puddle_area.collision_mask = 0
	_puddle_area.monitoring = false
	_puddle_area.monitorable = true

	# Create collision shape based on texture size
	var collision_shape := CollisionShape2D.new()
	collision_shape.name = "PuddleCollision"
	var shape := CircleShape2D.new()
	# Use texture size to determine collision radius, scaled appropriately
	if texture:
		shape.radius = max(texture.get_width(), texture.get_height()) * scale.x * 0.4
	else:
		shape.radius = 12.0  # Default radius if no texture
	collision_shape.shape = shape

	_puddle_area.add_child(collision_shape)
	add_child(_puddle_area)

	# Add the area to blood_puddle group as well for redundant detection
	_puddle_area.add_to_group("blood_puddle")


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
