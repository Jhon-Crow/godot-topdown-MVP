extends Node
## Component that tracks when a character steps in blood and spawns footprints.
##
## Attach this component to any CharacterBody2D (Player or Enemy) to enable
## bloody footprint tracking. The component monitors for blood puddle contact
## and spawns footprint decals at regular intervals while moving.
##
## Performance Note (Issue #407 FPS fix):
## - Uses signal-based detection (area_entered/area_exited) instead of polling
## - Fallback distance check is throttled to run every 30 frames (~0.5s at 60fps)
## - Uses distance_squared_to() for faster distance comparisons
class_name BloodyFeetComponent

## Emitted immediately when the character steps in blood (Issue #1627).
## SnowyFeetComponent connects to this to set its red-print counter synchronously,
## avoiding the race condition where _blood_level drains before SnowyFeet checks it.
signal blood_contact(blood_color: Color)

## Number of bloody footprints before the blood runs out.
@export var blood_steps_count: int = 12

## When true, exactly snow_blood_steps_count red oval footprints are spawned on snow
## after stepping in blood, then SnowyFeetComponent resumes normal white prints (Issue #1627).
## Set by the Winter Forest level script.
@export var on_snow: bool = false

## Number of red oval bloody footprints to leave on snow after stepping in blood (Issue #1627).
@export var snow_blood_steps_count: int = 5

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

## Preloaded footprint scene (regular BloodFootprint for non-snow surfaces).
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

## Whether currently overlapping a blood puddle (signal-based detection).
## Performance fix: Use signals instead of polling get_overlapping_areas() every frame.
var _is_overlapping_blood: bool = false

## Area2D used to detect overlap with snow-surface areas (group "snow_area").
## Used when on_snow = true to restrict footprints to snow surfaces only.
var _snow_detector: Area2D = null

## Whether currently overlapping a snow surface (signal-based detection).
var _is_overlapping_snow: bool = false

## Counter for throttled fallback distance check.
## Performance fix: Only check distance every N frames instead of every frame.
var _fallback_check_counter: int = 0

## Interval for fallback distance check (in physics frames).
## At 60fps, 30 frames = ~0.5 seconds between checks.
const FALLBACK_CHECK_INTERVAL: int = 30


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

	# Create Area2D for blood puddle detection (deferred to ensure parent is in tree)
	# Performance fix: Defer setup to ensure Area2D is properly in scene tree
	call_deferred("_setup_blood_detector")

	# Create Area2D for snow-surface detection (used when on_snow = true).
	call_deferred("_setup_snow_detector")

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
## Performance fix: This is called deferred to ensure parent is in scene tree.
func _setup_blood_detector() -> void:
	if _parent_body == null:
		return

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
	# Performance fix: Use signals (area_entered/area_exited) instead of polling
	# get_overlapping_areas() every frame. Signals are more efficient as they're
	# triggered by the physics engine only when overlaps change.
	_blood_detector.area_entered.connect(_on_area_entered)
	_blood_detector.area_exited.connect(_on_area_exited)

	_log_info("Blood detector created and attached to %s" % _parent_body.name)


## Sets up the Area2D for detecting snow-surface areas (used when on_snow = true).
func _setup_snow_detector() -> void:
	if _parent_body == null:
		return

	_snow_detector = Area2D.new()
	_snow_detector.name = "SnowDetectorForBlood"
	_snow_detector.collision_layer = 0
	_snow_detector.collision_mask = 128  # Layer 8 = snow_area layer.
	_snow_detector.monitoring = true
	_snow_detector.monitorable = false

	var collision_shape := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 8.0
	collision_shape.shape = shape
	_snow_detector.add_child(collision_shape)

	_parent_body.add_child(_snow_detector)

	_snow_detector.area_entered.connect(_on_snow_area_entered)
	_snow_detector.area_exited.connect(_on_snow_area_exited)

	_log_info("Snow surface detector created on %s" % _parent_body.name)


## Called when the detector enters a snow-surface area.
func _on_snow_area_entered(area: Area2D) -> void:
	if area.is_in_group("snow_area"):
		_is_overlapping_snow = true


## Called when the detector exits a snow-surface area.
func _on_snow_area_exited(area: Area2D) -> void:
	if area.is_in_group("snow_area"):
		if _snow_detector:
			var still_on_snow := false
			for other in _snow_detector.get_overlapping_areas():
				if other.is_in_group("snow_area"):
					still_on_snow = true
					break
			_is_overlapping_snow = still_on_snow


## Returns true when the character is standing on a snow surface.
func _is_on_snow() -> bool:
	if _is_overlapping_snow:
		return true
	if _snow_detector and _snow_detector.is_inside_tree():
		for area in _snow_detector.get_overlapping_areas():
			if area.is_in_group("snow_area"):
				return true
	return false


func _physics_process(delta: float) -> void:
	if not _initialized or _parent_body == null:
		return

	# Performance fix: Signal-based detection handles most cases efficiently.
	# Only run throttled fallback check periodically for edge cases.
	_fallback_check_counter += 1
	if _fallback_check_counter >= FALLBACK_CHECK_INTERVAL:
		_fallback_check_counter = 0
		_check_blood_puddle_throttled()

	# Track movement for footprint spawning
	if _blood_level > 0:
		_track_movement()


## Debug: Frame counter for periodic overlap logging
var _debug_frame_counter: int = 0

## Throttled blood puddle check - runs periodically as a fallback.
## Performance fix: This replaces the previous every-frame check with a throttled version.
func _check_blood_puddle_throttled() -> void:
	if _blood_detector == null or _parent_body == null:
		return

	# Debug logging (only when debug_logging is enabled)
	if debug_logging:
		_debug_frame_counter += 1
		if _debug_frame_counter >= 4:  # Every 4 throttled checks = ~2 seconds
			_debug_frame_counter = 0
			var overlapping_areas := _blood_detector.get_overlapping_areas()
			var blood_puddles_in_scene := get_tree().get_nodes_in_group("blood_puddle")
			var parent_pos := _parent_body.global_position
			var detector_global := _blood_detector.global_position if _blood_detector.is_inside_tree() else Vector2.ZERO
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

	# Signal-based detection should handle most cases.
	# Only run distance fallback if we're not already overlapping via signals.
	if not _is_overlapping_blood:
		_check_blood_puddle_by_distance()


## Radius in pixels for distance-based blood detection fallback.
const BLOOD_DETECTION_RADIUS := 20.0

## Fallback blood color used when a puddle has no readable visual color.
const DEFAULT_BLOOD_COLOR := Color(0.545, 0.0, 0.0, 1.0)

## Squared radius for faster distance comparisons (avoids sqrt).
const BLOOD_DETECTION_RADIUS_SQUARED := BLOOD_DETECTION_RADIUS * BLOOD_DETECTION_RADIUS

## Maximum number of puddles to check in fallback (performance limit).
## This prevents massive slowdowns when there are hundreds of puddles.
const MAX_PUDDLES_TO_CHECK := 50

## Fallback distance-based detection when Area2D physics fails.
## Performance fix: Uses distance_squared_to() and limits puddle count.
func _check_blood_puddle_by_distance() -> void:
	if _parent_body == null:
		return

	var parent_pos := _parent_body.global_position
	var blood_puddles := get_tree().get_nodes_in_group("blood_puddle")

	# Performance fix: Limit the number of puddles we check to prevent
	# O(n) explosion when there are hundreds of puddles.
	var check_count := 0
	for puddle in blood_puddles:
		if check_count >= MAX_PUDDLES_TO_CHECK:
			break
		check_count += 1

		if puddle is Node2D:
			# Performance fix: Use distance_squared_to() instead of distance_to()
			# to avoid expensive square root operation.
			var dist_sq := parent_pos.distance_squared_to(puddle.global_position)
			if dist_sq <= BLOOD_DETECTION_RADIUS_SQUARED:
				if debug_logging:
					_log_info("FALLBACK: Blood detected at distance %.1f (pos: %s)" % [sqrt(dist_sq), puddle.global_position])
				_on_blood_puddle_contact(_get_puddle_color(puddle))
				return


## Extracts the color from a blood puddle node.
## Returns the modulate color of the puddle, or default red if not available.
func _get_puddle_color(puddle_node: Node) -> Color:
	if puddle_node == null:
		return DEFAULT_BLOOD_COLOR

	var parent := puddle_node.get_parent()
	if puddle_node is Area2D and parent != null and parent.is_in_group("blood_puddle"):
		return _get_puddle_color(parent)

	if puddle_node is CanvasItem:
		var color := (puddle_node as CanvasItem).modulate
		if debug_logging:
			_log_info("Puddle color: %s (R=%.2f, G=%.2f, B=%.2f)" % [color, color.r, color.g, color.b])
		return color

	return DEFAULT_BLOOD_COLOR


## Called when the character contacts a blood puddle.
## puddle_color: The color of the blood puddle stepped in.
func _on_blood_puddle_contact(puddle_color: Color = Color(0.545, 0.0, 0.0, 1.0)) -> void:
	# Reset blood level: on snow use snow_blood_steps_count (default 2) oval red prints,
	# then SnowyFeetComponent resumes normal white snow prints (Issue #1627).
	var target_level := snow_blood_steps_count if on_snow else blood_steps_count
	_apply_blood_contact(target_level, puddle_color)

func _apply_blood_contact(target_level: int, puddle_color: Color) -> void:
	var previous_level := _blood_level
	_blood_level = target_level
	_blood_color = puddle_color
	if previous_level == 0:
		_log_info("Stepped in blood! %d footprints to spawn, color: %s" % [_blood_level, puddle_color])
		# Reset distance counter when first stepping in blood
		_distance_since_last_footprint = 0.0

	# Notify SnowyFeetComponent immediately so it can arm its red-print counter
	# before any _blood_level decrements happen (Issue #1627 race-condition fix).
	blood_contact.emit(puddle_color)


## Called when an area enters the blood detector.
## Performance fix: Signal-based detection is more efficient than polling.
func _on_area_entered(area: Area2D) -> void:
	if area.is_in_group("blood_puddle"):
		_is_overlapping_blood = true
		_on_blood_puddle_contact(_get_puddle_color(area))
	elif area.get_parent() and area.get_parent().is_in_group("blood_puddle"):
		_is_overlapping_blood = true
		_on_blood_puddle_contact(_get_puddle_color(area.get_parent()))


## Called when an area exits the blood detector.
## Performance fix: Track overlap state via signals instead of polling every frame.
func _on_area_exited(area: Area2D) -> void:
	if area.is_in_group("blood_puddle") or (area.get_parent() and area.get_parent().is_in_group("blood_puddle")):
		# Check if we're still overlapping any other blood puddles
		if _blood_detector:
			var still_overlapping := false
			for other_area in _blood_detector.get_overlapping_areas():
				if other_area.is_in_group("blood_puddle") or (other_area.get_parent() and other_area.get_parent().is_in_group("blood_puddle")):
					still_overlapping = true
					break
			_is_overlapping_blood = still_overlapping


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
## Performance fix: Uses cached overlap state and limited distance check.
func _is_on_blood_puddle() -> bool:
	# Fast path: Use cached signal-based overlap state
	if _is_overlapping_blood:
		return true

	# Check via Area2D overlap (only if detector is valid)
	if _blood_detector and _blood_detector.is_inside_tree():
		var overlapping_areas := _blood_detector.get_overlapping_areas()
		for area in overlapping_areas:
			if area.is_in_group("blood_puddle") or (area.get_parent() and area.get_parent().is_in_group("blood_puddle")):
				return true

	# Fallback: Limited distance-based detection
	# Performance fix: Only check a limited number of nearby puddles
	if _parent_body:
		var parent_pos := _parent_body.global_position
		var blood_puddles := get_tree().get_nodes_in_group("blood_puddle")
		var check_count := 0
		for puddle in blood_puddles:
			if check_count >= MAX_PUDDLES_TO_CHECK:
				break
			check_count += 1
			if puddle is Node2D:
				# Performance fix: Use distance_squared_to() to avoid sqrt
				var dist_sq := parent_pos.distance_squared_to(puddle.global_position)
				if dist_sq <= BLOOD_DETECTION_RADIUS_SQUARED:
					return true

	return false


## Spawns a footprint at the current position.
## Footprints are only spawned on floors without blood.
## On snow levels (on_snow = true), SnowyFeetComponent handles all snow prints
## (both normal and bloody), so this component only spawns boot-print footprints
## on non-snow surfaces (Issue #1627).
func _spawn_footprint() -> void:
	if _blood_level <= 0:
		return

	# On snow levels, SnowyFeetComponent handles all footprint rendering (both normal
	# white and red blood-snow prints). This component only tracks the blood level so
	# SnowyFeetComponent can read it via has_bloody_feet() and _blood_color (Issue #1627).
	if on_snow:
		if debug_logging:
			_log_info("On snow — SnowyFeetComponent handles prints (blood steps remaining: %d)" % _blood_level)
		return

	# Non-snow level: use regular boot-print BloodFootprint scene.
	if _footprint_scene == null:
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

	# Calculate alpha based on remaining steps.
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
	# Ensure footprint renders below characters (body z_index = 1)
	footprint.z_index = 0

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
	var max_level := snow_blood_steps_count if on_snow else blood_steps_count
	var clamped_level := clampi(level, 0, max_level)
	if clamped_level > 0:
		_apply_blood_contact(clamped_level, _blood_color)
	else:
		_blood_level = 0
		_distance_since_last_footprint = 0.0
	_log_info("Blood level set to %d" % _blood_level)


## Get current blood level.
func get_blood_level() -> int:
	return _blood_level


## Called by SnowyFeetComponent after it renders one red snow footprint.
## Keeps blood-state ownership synchronized without letting this component drain
## the counter before SnowyFeetComponent has rendered the visible red oval print.
func consume_snow_blood_step() -> void:
	if _blood_level <= 0:
		return
	_blood_level -= 1
	if debug_logging:
		_log_info("Snow blood step consumed (blood steps remaining: %d)" % _blood_level)
	if _blood_level <= 0:
		_log_info("Blood ran out on snow")


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
