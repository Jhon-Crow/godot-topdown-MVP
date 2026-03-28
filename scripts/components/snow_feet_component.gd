extends Node
## Component that leaves footprints in snow as characters move (Issue #1627).
##
## Attach to any CharacterBody2D on the Winter Forest map (or any map with snow
## surface). The component spawns SnowFootprint decals at regular step intervals
## while the character is moving — no "stepping in something" required, because
## the whole ground is snow.
##
## Design mirrors BloodyFeetComponent but is simpler:
## - Always active (snow is always underfoot on this map)
## - No blood-level tracking — snow is always stepable
## - Footprints persist for the duration of the level (no fade)
class_name SnowFeetComponent

## Distance in pixels between successive footprint spawns.
@export var step_distance: float = 22.0

## Starting alpha for fresh footprints.
@export var initial_alpha: float = 0.72

## Alpha reduction per step so older prints look shallower (snow fills back in slowly).
@export var alpha_decay_per_step: float = 0.0  # Set to 0 → all prints same depth

## Scale multiplier for the footprint node.
@export var footprint_scale: float = 1.0

## Maximum footprints to keep alive (oldest removed first to save nodes).
@export var max_footprints: int = 80

## Enable debug output.
@export var debug_logging: bool = false

## Preloaded footprint scene.
var _footprint_scene: PackedScene = null

## Parent CharacterBody2D.
var _parent_body: CharacterBody2D = null

## Distance travelled since last footprint.
var _distance_since_last: float = 0.0

## Last recorded world position.
var _last_position: Vector2 = Vector2.ZERO

## Last non-zero movement direction (for footprint rotation).
var _last_direction: Vector2 = Vector2.DOWN

## Alternate left/right foot.
var _is_left_foot: bool = true

## Whether the component has finished setup.
var _initialized: bool = false

## Reference to character model for facing direction (optional).
var _character_model: Node2D = null

## Circular buffer of live footprint nodes (for max_footprints eviction).
var _footprints: Array[Node2D] = []

## Reference to FileLogger autoload.
var _file_logger: Node = null

## Step counter for alpha decay.
var _step_count: int = 0


func _ready() -> void:
	_file_logger = get_node_or_null("/root/FileLogger")

	_parent_body = get_parent() as CharacterBody2D
	if _parent_body == null:
		push_warning("SnowFeetComponent: parent must be CharacterBody2D")
		return

	_last_position = _parent_body.global_position

	var fp_path := "res://scenes/effects/SnowFootprint.tscn"
	if ResourceLoader.exists(fp_path):
		_footprint_scene = load(fp_path)
	else:
		push_warning("SnowFeetComponent: footprint scene not found at " + fp_path)

	_find_character_model()

	_initialized = true
	_log_always("SnowFeetComponent ready on %s" % _parent_body.name)


## Finds the PlayerModel or EnemyModel child for facing direction.
func _find_character_model() -> void:
	if _parent_body == null:
		return
	_character_model = _parent_body.get_node_or_null("PlayerModel")
	if _character_model:
		return
	_character_model = _parent_body.get_node_or_null("EnemyModel")


func _physics_process(_delta: float) -> void:
	if not _initialized or _parent_body == null:
		return
	_track_movement()


## Measures movement and spawns footprints at step_distance intervals.
func _track_movement() -> void:
	var current_pos := _parent_body.global_position
	var movement := current_pos - _last_position
	var dist := movement.length()

	if dist > 0.1:
		_last_direction = movement.normalized()
		_distance_since_last += dist

		if _distance_since_last >= step_distance:
			_spawn_footprint()
			_distance_since_last = 0.0

	_last_position = current_pos


## Returns the character's facing direction from model rotation or movement direction.
func _get_facing_direction() -> Vector2:
	if _character_model:
		var angle := _character_model.global_rotation
		if _character_model.scale.y < 0:
			angle = -angle
		return Vector2.from_angle(angle)
	return _last_direction


## Spawns a SnowFootprint at the current position.
func _spawn_footprint() -> void:
	if _footprint_scene == null:
		return

	var fp := _footprint_scene.instantiate() as Node2D
	if fp == null:
		return

	var facing := _get_facing_direction()
	var alpha := clampf(initial_alpha - _step_count * alpha_decay_per_step, 0.1, 1.0)

	fp.global_position = _parent_body.global_position
	fp.rotation = facing.angle() + PI / 2.0
	fp.scale = Vector2(footprint_scale, footprint_scale)
	# z_index is set in SnowFootprint._ready() — do not override here.

	# Capture foot side before toggling; apply lateral offset.
	var is_left := _is_left_foot
	var perp := facing.rotated(PI / 2.0)
	var offset := 4.5 if is_left else -4.5
	fp.global_position += perp * offset
	_is_left_foot = not _is_left_foot

	# Add to current scene FIRST so _ready() runs and z_index/canvas state is set.
	var scene := get_tree().current_scene
	if scene:
		scene.add_child(fp)
	else:
		_parent_body.get_parent().add_child(fp)

	# Set visual properties AFTER entering tree so queue_redraw() actually schedules a draw.
	if fp.has_method("set_foot"):
		fp.set_foot(is_left)
	if fp.has_method("set_alpha"):
		fp.set_alpha(alpha)
	fp.queue_redraw()

	# Track and evict oldest footprint when cap is reached.
	_footprints.append(fp)
	if _footprints.size() > max_footprints:
		var oldest: Node2D = _footprints.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()

	_step_count += 1

	# Always log first footprint to confirm the system is working.
	if _step_count == 1:
		_log_always("First footprint spawned at %s for %s" % [fp.global_position, _parent_body.name])

	if debug_logging:
		_log("Spawned footprint #%d at %s (alpha=%.2f, facing=%.2f°)" % [
			_step_count, fp.global_position, alpha, rad_to_deg(facing.angle())])


## Logs through FileLogger if available, else prints. Only active when debug_logging=true.
func _log(message: String) -> void:
	if not debug_logging:
		return
	var msg := "[SnowFeet:%s] %s" % [_parent_body.name if _parent_body else "?", message]
	print(msg)
	if _file_logger and _file_logger.has_method("log_info"):
		_file_logger.log_info(msg)


## Always logs through FileLogger (used for important init/error messages regardless of debug flag).
func _log_always(message: String) -> void:
	var msg := "[SnowFeet:%s] %s" % [_parent_body.name if _parent_body else "?", message]
	print(msg)
	if _file_logger and _file_logger.has_method("log_info"):
		_file_logger.log_info(msg)
