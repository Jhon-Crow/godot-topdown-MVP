extends Node
## Component that tracks when a character steps in blood and spawns footprints.
##
## Attach this component to any CharacterBody2D (Player or Enemy) to enable
## bloody footprint tracking. The component monitors for blood puddle contact
## and spawns footprint decals at regular intervals while moving.
class_name BloodyFeetComponent

## Number of bloody footprints before the blood runs out.
@export var blood_steps_count: int = 12

## Distance in pixels between footprint spawns.
@export var step_distance: float = 30.0

## Alpha value for the first footprint (0.0 to 1.0).
@export var initial_alpha: float = 0.8

## Alpha reduction per step. Last footprint will be at (initial_alpha - (blood_steps_count - 1) * alpha_decay_rate).
@export var alpha_decay_rate: float = 0.06

## Footprint scale multiplier.
@export var footprint_scale: float = 1.0

## Enable debug logging.
@export var debug_logging: bool = false

## Preloaded footprint scene.
var _footprint_scene: PackedScene = null

## Current blood level (number of steps remaining).
var _blood_level: int = 0

## Distance traveled since last footprint.
var _distance_since_last_footprint: float = 0.0

## Last recorded position for distance tracking.
var _last_position: Vector2 = Vector2.ZERO

## Direction of last movement for footprint rotation.
var _last_move_direction: Vector2 = Vector2.RIGHT

## Whether component has been initialized.
var _initialized: bool = false

## Reference to parent CharacterBody2D.
var _parent_body: CharacterBody2D = null

## Track which foot to alternate (left/right).
var _is_left_foot: bool = true

## Reference to FileLogger for persistent logging.
var _file_logger: Node = null

## Area2D for detecting blood puddles.
var _blood_detector: Area2D = null

## Reference to the character's model node for facing direction.
## This is PlayerModel for Player or EnemyModel for Enemy.
var _character_model: Node2D = null

## Color of the blood puddle the character stepped in.
## Used to tint footprints to match/be darker than the puddle.
var _blood_color: Color = Color(0.545, 0.0, 0.0, 1.0)  # Default dark red


func _ready() -> void:
	_file_logger = get_node_or_null("/root/FileLogger")
	_log_info("BloodyFeetComponent initializing...")

	# Get parent CharacterBody2D
	_parent_body = get_parent() as CharacterBody2D
	if _parent_body == null:
		push_warning("BloodyFeetComponent: Parent must be a CharacterBody2D")
		return

	_last_position = _parent_body.global_position

	# Preload footprint scene
	var footprint_path := "res://scenes/effects/BloodFootprint.tscn"
	if ResourceLoader.exists(footprint_path):
		_footprint_scene = load(footprint_path)
		_log_info("Footprint scene loaded")
	else:
		push_warning("BloodyFeetComponent: Footprint scene not found at " + footprint_path)

	# Create Area2D for blood puddle detection
	_setup_blood_detector()

	# Find the character's model node for facing direction
	_find_character_model()

	_initialized = true
	_log_info("BloodyFeetComponent ready on %s" % _parent_body.name)


## Finds the character model node (PlayerModel or EnemyModel) for facing direction.
func _find_character_model() -> void:
	if _parent_body == null:
		return

	# Try to find PlayerModel (for Player character)
	_character_model = _parent_body.get_node_or_null("PlayerModel")
	if _character_model:
		_log_info("Found PlayerModel for facing direction")
		return

	# Try to find EnemyModel (for Enemy character)
	_character_model = _parent_body.get_node_or_null("EnemyModel")
	if _character_model:
		_log_info("Found EnemyModel for facing direction")
		return

	# Fallback: no model found, will use movement direction
	_log_info("No character model found, will use movement direction for footprint rotation")


## Sets up the Area2D for detecting blood puddles.
func _setup_blood_detector() -> void:
	_blood_detector = Area2D.new()
	_blood_detector.name = "BloodDetector"

	# Set collision to detect blood puddles (use collision layer 7 for blood)
	# But we primarily use group detection, so this is for future-proofing
	_blood_detector.collision_layer = 0
	_blood_detector.collision_mask = 64  # Layer 7 = 2^6 = 64
	_blood_detector.monitoring = true
	_blood_detector.monitorable = false

	# Create collision shape matching parent's approximate foot area
	var collision_shape := CollisionShape2D.new()
	collision_shape.name = "FootCollision"
	var shape := CircleShape2D.new()
	shape.radius = 8.0  # Small radius for foot detection
	collision_shape.shape = shape

	_blood_detector.add_child(collision_shape)

	# IMPORTANT: Add detector to the parent CharacterBody2D, not to this Node,
	# so that its position follows the character's movement.
	# If we add to this Node (which has no transform), the detector stays at (0, 0).
	_parent_body.add_child(_blood_detector)

	# Connect signals for blood detection
	_blood_detector.area_entered.connect(_on_area_entered)

	_log_info("Blood detector created and attached to %s" % _parent_body.name)


func _physics_process(delta: float) -> void:
	if not _initialized or _parent_body == null:
		return

	# Check for blood puddles via overlapping areas (using group detection)
	_check_blood_puddle_overlap()

	# Track movement for footprint spawning
	if _blood_level > 0:
		_track_movement()


## Debug: Frame counter for periodic overlap logging
var _debug_frame_counter: int = 0

## Checks if we're overlapping with any blood puddle via group detection.
func _check_blood_puddle_overlap() -> void:
	if _blood_detector == null:
		return

	# Get all overlapping areas
	var overlapping_areas := _blood_detector.get_overlapping_areas()

	# Periodic debug logging (every 120 frames = ~2 seconds at 60fps)
	_debug_frame_counter += 1
	if debug_logging and _debug_frame_counter >= 120:
		_debug_frame_counter = 0
		var blood_puddles_in_scene := get_tree().get_nodes_in_group("blood_puddle")
		var parent_pos := _parent_body.global_position if _parent_body else Vector2.ZERO
		var detector_global := _blood_detector.global_position
		var detector_in_tree := _blood_detector.is_inside_tree()
		_log_info("Overlap check: areas=%d, puddles=%d, parent_pos=%s, detector_global=%s, in_tree=%s, layer=%d, mask=%d" % [
			overlapping_areas.size(),
			blood_puddles_in_scene.size(),
			parent_pos,
			detector_global,
			detector_in_tree,
			_blood_detector.collision_layer,
			_blood_detector.collision_mask
		])
		# Log closest blood puddle distance for debugging
		if blood_puddles_in_scene.size() > 0:
			var closest_dist := INF
			var closest_puddle_pos := Vector2.ZERO
			for puddle in blood_puddles_in_scene:
				if puddle is Node2D:
					var dist := parent_pos.distance_to(puddle.global_position)
					if dist < closest_dist:
						closest_dist = dist
						closest_puddle_pos = puddle.global_position
			_log_info("Closest puddle at %s, distance=%.1f" % [closest_puddle_pos, closest_dist])

	for area in overlapping_areas:
		# Check if the area or its parent is a blood puddle
		if area.is_in_group("blood_puddle"):
			_on_blood_puddle_contact(_get_puddle_color(area))
			return  # Early return if found via physics
		elif area.get_parent() and area.get_parent().is_in_group("blood_puddle"):
			_on_blood_puddle_contact(_get_puddle_color(area.get_parent()))
			return  # Early return if found via physics

	# FALLBACK: If physics detection fails, use distance-based detection
	# This handles cases where Area2D physics isn't working correctly
	_check_blood_puddle_by_distance()


## Radius in pixels for distance-based blood detection fallback.
const BLOOD_DETECTION_RADIUS := 20.0

## Fallback distance-based detection when Area2D physics fails.
func _check_blood_puddle_by_distance() -> void:
	if _parent_body == null:
		return

	var parent_pos := _parent_body.global_position
	var blood_puddles := get_tree().get_nodes_in_group("blood_puddle")

	for puddle in blood_puddles:
		if puddle is Node2D:
			var dist := parent_pos.distance_to(puddle.global_position)
			if dist <= BLOOD_DETECTION_RADIUS:
				if debug_logging:
					_log_info("FALLBACK: Blood detected at distance %.1f (pos: %s)" % [dist, puddle.global_position])
				_on_blood_puddle_contact(_get_puddle_color(puddle))
				return


## Extracts the color from a blood puddle node.
## Returns the modulate color of the puddle, or default red if not available.
func _get_puddle_color(puddle_node: Node) -> Color:
	if puddle_node == null:
		return Color(0.545, 0.0, 0.0, 1.0)  # Default dark red

	# If it's a CanvasItem (Sprite2D, etc.), get its modulate color
	if puddle_node is CanvasItem:
		var color := (puddle_node as CanvasItem).modulate
		if debug_logging:
			_log_info("Puddle color: %s (R=%.2f, G=%.2f, B=%.2f)" % [color, color.r, color.g, color.b])
		return color

	return Color(0.545, 0.0, 0.0, 1.0)  # Default dark red


## Called when the character contacts a blood puddle.
## puddle_color: The color of the blood puddle stepped in.
func _on_blood_puddle_contact(puddle_color: Color = Color(0.545, 0.0, 0.0, 1.0)) -> void:
	# Reset blood level to maximum
	var previous_level := _blood_level
	_blood_level = blood_steps_count

	# Store the blood color for footprints
	_blood_color = puddle_color

	if previous_level == 0:
		_log_info("Stepped in blood! %d footprints to spawn, color: %s" % [_blood_level, puddle_color])
		# Reset distance counter when first stepping in blood
		_distance_since_last_footprint = 0.0


## Called when an area enters the blood detector.
func _on_area_entered(area: Area2D) -> void:
	if area.is_in_group("blood_puddle"):
		_on_blood_puddle_contact(_get_puddle_color(area))
	elif area.get_parent() and area.get_parent().is_in_group("blood_puddle"):
		_on_blood_puddle_contact(_get_puddle_color(area.get_parent()))


## Tracks movement and spawns footprints at regular intervals.
func _track_movement() -> void:
	var current_pos := _parent_body.global_position
	var movement := current_pos - _last_position
	var distance := movement.length()

	if distance > 0.1:  # Minimum movement threshold
		_last_move_direction = movement.normalized()
		_distance_since_last_footprint += distance

		# Check if we should spawn a footprint
		if _distance_since_last_footprint >= step_distance:
			_spawn_footprint()
			_distance_since_last_footprint = 0.0

	_last_position = current_pos


## Gets the character's facing direction based on model rotation.
## Falls back to movement direction if no model is found.
func _get_facing_direction() -> Vector2:
	if _character_model:
		# Use the model's global rotation for facing direction
		# The model rotates to face the aim/look direction
		var facing_angle := _character_model.global_rotation

		# Handle flipped sprites (when aiming left, scale.y is negative)
		# In this case, the rotation was negated in the character script,
		# so we need to negate it back to get the actual facing direction
		if _character_model.scale.y < 0:
			facing_angle = -facing_angle

		return Vector2.from_angle(facing_angle)
	else:
		# Fallback to movement direction
		return _last_move_direction


## Checks if the character is currently standing on a blood puddle.
## Uses both Area2D overlap detection and distance-based fallback.
func _is_on_blood_puddle() -> bool:
	# Check via Area2D overlap
	if _blood_detector:
		var overlapping_areas := _blood_detector.get_overlapping_areas()
		for area in overlapping_areas:
			if area.is_in_group("blood_puddle") or (area.get_parent() and area.get_parent().is_in_group("blood_puddle")):
				return true

	# Fallback: distance-based detection
	if _parent_body:
		var parent_pos := _parent_body.global_position
		var blood_puddles := get_tree().get_nodes_in_group("blood_puddle")
		for puddle in blood_puddles:
			if puddle is Node2D:
				var dist := parent_pos.distance_to(puddle.global_position)
				if dist <= BLOOD_DETECTION_RADIUS:
					return true

	return false


## Spawns a footprint at the current position.
## Footprints are only spawned on floor without blood.
func _spawn_footprint() -> void:
	if _footprint_scene == null or _blood_level <= 0:
		return

	# Don't spawn footprint if currently standing on blood
	# Footprints should only appear on floor without blood
	if _is_on_blood_puddle():
		if debug_logging:
			_log_info("Skipping footprint - currently on blood puddle")
		return

	var footprint := _footprint_scene.instantiate() as Node2D
	if footprint == null:
		return

	# Calculate alpha based on remaining steps
	# First step has highest alpha, last step has lowest
	var steps_taken := blood_steps_count - _blood_level
	var alpha := initial_alpha - (steps_taken * alpha_decay_rate)
	alpha = maxf(alpha, 0.05)  # Minimum visible alpha

	# Get the facing direction (from model rotation, not movement)
	var facing_direction := _get_facing_direction()

	# Set footprint properties
	footprint.global_position = _parent_body.global_position
	# Use facing direction for rotation (the direction character is looking)
	# Add PI/2 (90 degrees clockwise) to align boot texture with facing direction
	footprint.rotation = facing_direction.angle() + PI / 2.0
	footprint.scale = Vector2(footprint_scale, footprint_scale)
	# Ensure footprint renders above floor (z_index 0) but below characters
	footprint.z_index = 1

	# Set which foot this is (left or right boot texture)
	if footprint.has_method("set_foot"):
		footprint.set_foot(_is_left_foot)

	# Alternate left/right foot by slightly offsetting perpendicular to facing direction
	var perpendicular := facing_direction.rotated(PI / 2.0)
	var foot_offset := 4.0 if _is_left_foot else -4.0
	footprint.global_position += perpendicular * foot_offset
	_is_left_foot = not _is_left_foot

	# Set the blood color (same or darker than puddle)
	if footprint.has_method("set_blood_color"):
		footprint.set_blood_color(_blood_color)
	else:
		# Fallback: apply color directly to modulate
		footprint.modulate.r = _blood_color.r
		footprint.modulate.g = _blood_color.g
		footprint.modulate.b = _blood_color.b

	# Set alpha using the footprint's method (after color to preserve alpha)
	if footprint.has_method("set_alpha"):
		footprint.set_alpha(alpha)
	else:
		footprint.modulate.a = alpha

	# Add to scene tree
	var scene := get_tree().current_scene
	if scene:
		scene.add_child(footprint)
	else:
		_parent_body.get_parent().add_child(footprint)

	# Decrease blood level
	_blood_level -= 1

	if debug_logging:
		_log_info("Footprint spawned (steps remaining: %d, alpha: %.2f, facing: %.2f, color: %s)" % [_blood_level, alpha, facing_direction.angle(), _blood_color])

	if _blood_level <= 0:
		_log_info("Blood ran out - no more footprints")


## Manually set blood level (for testing or external triggers).
func set_blood_level(level: int) -> void:
	_blood_level = clampi(level, 0, blood_steps_count)
	_distance_since_last_footprint = 0.0
	_log_info("Blood level set to %d" % _blood_level)


## Get current blood level.
func get_blood_level() -> int:
	return _blood_level


## Check if currently has bloody feet.
func has_bloody_feet() -> bool:
	return _blood_level > 0


## Logs to FileLogger and prints to console in debug mode.
func _log_info(message: String) -> void:
	var log_message := "[BloodyFeet:%s] %s" % [_parent_body.name if _parent_body else "?", message]
	if debug_logging:
		print(log_message)
	if _file_logger and _file_logger.has_method("log_info"):
		_file_logger.log_info(log_message)
