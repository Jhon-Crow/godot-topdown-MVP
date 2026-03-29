extends Node
## Component that leaves visible footprints in snow as a character walks (Issue #1627).
##
## Attach to any CharacterBody2D (Player or Enemy) inside the Winter Forest level.
## Only leaves footprints when the character is standing on a snow-surface area
## (any Area2D in the "snow_area" group).
##
## Snow footprints use near-white tinting so they appear as subtle impressions in the
## snow rather than dark stains.  Alpha decreases with each step and the prints fade
## after a short delay, simulating snow slowly filling the impressions back in.
class_name SnowyFeetComponent

## Number of steps before the snow impression opacity reaches its minimum.
@export var snow_steps_count: int = 8

## Distance in pixels between consecutive footprint spawns.
@export var step_distance: float = 30.0

## Alpha of the first (freshest) footprint.
@export var initial_alpha: float = 0.55

## Alpha reduction per step.  Last print alpha = initial_alpha - (snow_steps_count - 1) * alpha_decay_rate.
@export var alpha_decay_rate: float = 0.06

## Time in seconds before a snow footprint starts fading out.
@export var footprint_fade_delay: float = 20.0

## Duration of the fade-out tween for each footprint.
@export var footprint_fade_duration: float = 5.0

## Scale applied to the boot-print sprite.
@export var footprint_scale: float = 1.0

## Enable verbose debug logging.
@export var debug_logging: bool = false

## Preloaded footprint scene.
var _footprint_scene: PackedScene = null

## Distance traveled since the last footprint was placed.
var _distance_since_last_footprint: float = 0.0

## Last recorded world position (used to measure travel distance).
var _last_position: Vector2 = Vector2.ZERO

## Direction of the most recent movement (for footprint rotation).
var _last_move_direction: Vector2 = Vector2.RIGHT

## Whether the component has finished its _ready setup.
var _initialized: bool = false

## Reference to the parent CharacterBody2D.
var _parent_body: CharacterBody2D = null

## Whether to alternate left/right foot on each print.
var _is_left_foot: bool = true

## Reference to FileLogger autoload for persistent logging.
var _file_logger: Node = null

## Optional reference to the character's model node (PlayerModel / EnemyModel).
## Used to read the facing direction so prints align with the character's look direction.
var _character_model: Node2D = null

## Running step index, used to compute per-step alpha.
var _step_index: int = 0

## Cached reference to sibling BloodyFeetComponent (found lazily in _ready).
## When the character has active blood, SnowyFeetComponent defers to it so both
## components do not emit footprints simultaneously (Issue #1627).
var _bloody_feet: Node = null

## Area2D used to detect overlap with snow-surface areas (group "snow_area").
var _snow_detector: Area2D = null

## Whether currently overlapping a snow surface (signal-based detection).
var _is_overlapping_snow: bool = false


func _ready() -> void:
	_file_logger = get_node_or_null("/root/FileLogger")

	_parent_body = get_parent() as CharacterBody2D
	if _parent_body == null:
		push_warning("SnowyFeetComponent: Parent must be a CharacterBody2D")
		return

	_last_position = _parent_body.global_position

	var footprint_path := "res://scenes/effects/SnowFootprint.tscn"
	if ResourceLoader.exists(footprint_path):
		_footprint_scene = load(footprint_path)
	else:
		push_warning("SnowyFeetComponent: SnowFootprint scene not found at " + footprint_path)

	_find_character_model()

	# Cache sibling BloodyFeetComponent to avoid double-printing when character has blood.
	_bloody_feet = _parent_body.get_node_or_null("BloodyFeetComponent")

	# Create Area2D detector for snow-surface overlap (deferred so parent is in tree).
	call_deferred("_setup_snow_detector")

	_initialized = true
	_log_info("SnowyFeetComponent ready on %s" % _parent_body.name)


## Creates an Area2D attached to the parent body to detect snow-surface areas.
func _setup_snow_detector() -> void:
	if _parent_body == null:
		return

	_snow_detector = Area2D.new()
	_snow_detector.name = "SnowDetector"
	_snow_detector.collision_layer = 0
	_snow_detector.collision_mask = 32  # Layer 6 = 2^5 = 32 (snow_area layer)
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

	_log_info("Snow detector created on %s" % _parent_body.name)


## Called when the foot detector enters an Area2D.
func _on_snow_area_entered(area: Area2D) -> void:
	if area.is_in_group("snow_area"):
		_is_overlapping_snow = true


## Called when the foot detector exits an Area2D.
func _on_snow_area_exited(area: Area2D) -> void:
	if area.is_in_group("snow_area"):
		# Still overlapping snow if another snow area is in range.
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
	# Fallback: check overlapping areas directly.
	if _snow_detector and _snow_detector.is_inside_tree():
		for area in _snow_detector.get_overlapping_areas():
			if area.is_in_group("snow_area"):
				return true
	return false


## Finds the character's visual model for facing-direction look-up.
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


## Measures movement and spawns footprints at the configured interval.
func _track_movement() -> void:
	var current_pos := _parent_body.global_position
	var movement := current_pos - _last_position
	var distance := movement.length()

	if distance > 0.1:
		_last_move_direction = movement.normalized()
		_distance_since_last_footprint += distance

		if _distance_since_last_footprint >= step_distance:
			_spawn_footprint()
			_distance_since_last_footprint = 0.0

	_last_position = current_pos


## Returns the character's facing direction from its model, or falls back to movement direction.
func _get_facing_direction() -> Vector2:
	if _character_model:
		var facing_angle := _character_model.global_rotation
		if _character_model.scale.y < 0:
			facing_angle = -facing_angle
		return Vector2.from_angle(facing_angle)
	return _last_move_direction


## Spawns a single snow footprint at the character's current position.
## Only spawns when the character is standing on a snow-surface area.
func _spawn_footprint() -> void:
	if _footprint_scene == null:
		return

	if not _is_on_snow():
		if debug_logging:
			_log_info("Skipping snow footprint — not on snow surface")
		return

	# Skip plain snow prints while the character has bloody feet — BloodyFeetComponent
	# will handle the snow-blood oval prints itself, preventing double footprints.
	if _bloody_feet and _bloody_feet.has_method("has_bloody_feet") and _bloody_feet.has_bloody_feet():
		if debug_logging:
			_log_info("Skipping snow footprint — character has bloody feet (BloodyFeetComponent handles prints)")
		return

	var footprint := _footprint_scene.instantiate() as Node2D
	if footprint == null:
		return

	# Compute alpha: decreases with each step, wraps at snow_steps_count.
	var alpha := initial_alpha - (_step_index % snow_steps_count) * alpha_decay_rate
	alpha = maxf(alpha, 0.05)

	var facing_direction := _get_facing_direction()

	footprint.global_position = _parent_body.global_position
	footprint.rotation = facing_direction.angle() + PI / 2.0
	footprint.scale = Vector2(footprint_scale, footprint_scale)
	footprint.z_index = 0

	if footprint.has_method("set_foot"):
		footprint.set_foot(_is_left_foot)

	# Offset slightly left/right to alternate feet.
	var perpendicular := facing_direction.rotated(PI / 2.0)
	var foot_offset := 4.0 if _is_left_foot else -4.0
	footprint.global_position += perpendicular * foot_offset
	_is_left_foot = not _is_left_foot

	if footprint.has_method("set_alpha"):
		footprint.set_alpha(alpha)
	else:
		footprint.modulate.a = alpha

	# Add to scene root so footprints stay in world space.
	var scene := get_tree().current_scene
	if scene:
		scene.add_child(footprint)
	else:
		_parent_body.get_parent().add_child(footprint)

	_step_index += 1

	# Schedule fade-out so old prints gradually disappear (snow fills them in).
	_schedule_footprint_fade(footprint)

	if debug_logging:
		_log_info("Snow footprint placed (step %d, alpha %.2f, facing %.2f)" % [
			_step_index, alpha, facing_direction.angle()])


## Fades a footprint node out and removes it after footprint_fade_delay seconds.
func _schedule_footprint_fade(footprint: Node2D) -> void:
	var tree := get_tree()
	if tree == null:
		return

	# Capture a weak reference so we don't crash if the scene unloads first.
	var footprint_ref := weakref(footprint)

	# Use an anonymous async function via a lambda-style timer.
	tree.create_timer(footprint_fade_delay).timeout.connect(
		func() -> void:
			var fp: Node2D = footprint_ref.get_ref() as Node2D
			if fp == null or not is_instance_valid(fp) or not fp.is_inside_tree():
				return
			var tween := fp.create_tween()
			if tween == null:
				fp.queue_free()
				return
			tween.tween_property(fp, "modulate:a", 0.0, footprint_fade_duration)
			tween.tween_callback(fp.queue_free),
		CONNECT_ONE_SHOT
	)


## Logs through FileLogger if available, otherwise prints.
func _log_info(message: String) -> void:
	var log_message := "[SnowyFeet:%s] %s" % [
		_parent_body.name if _parent_body else "?", message]
	if debug_logging:
		print(log_message)
	if _file_logger and _file_logger.has_method("log_info"):
		_file_logger.log_info(log_message)
