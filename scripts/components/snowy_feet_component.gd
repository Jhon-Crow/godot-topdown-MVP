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
##
## When the character has bloody feet (BloodyFeetComponent.has_bloody_feet() == true),
## this component spawns red oval SnowBloodFootprint prints for the first
## snow_blood_steps_count steps, then resumes normal white prints (Issue #1627).
class_name SnowyFeetComponent

## Number of steps before the snow impression opacity reaches its minimum.
@export var snow_steps_count: int = 8

## Number of red blood-stained snow prints to spawn after stepping in blood (Issue #1627).
@export var snow_blood_steps_count: int = 2

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

## Preloaded footprint scene (normal white snow print).
var _footprint_scene: PackedScene = null

## Preloaded red blood-stained snow footprint scene (Issue #1627).
var _snow_blood_footprint_scene: PackedScene = null

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

## Cached reference to sibling BloodyFeetComponent (Issue #1627).
## Used to check whether to spawn red or white snow prints.
var _bloody_feet: Node = null

## Whether this component is connected to BloodyFeetComponent.blood_contact.
var _blood_contact_connected: bool = false

## Counter for remaining red blood-snow footprints to spawn (Issue #1627).
## Set when the character first steps in blood; counts down to 0.
var _blood_snow_steps_remaining: int = 0

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

	var snow_blood_path := "res://scenes/effects/SnowBloodFootprint.tscn"
	if ResourceLoader.exists(snow_blood_path):
		_snow_blood_footprint_scene = load(snow_blood_path)
	else:
		push_warning("SnowyFeetComponent: SnowBloodFootprint scene not found at " + snow_blood_path)

	_find_character_model()

	_connect_bloody_feet()

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


## Called immediately when the sibling BloodyFeetComponent detects blood contact.
## Arms the red-print counter right away so _spawn_footprint() can start emitting
## red oval snow prints on the very next step (Issue #1627 race-condition fix).
func _on_blood_contact(blood_color: Color) -> void:
	var steps := snow_blood_steps_count
	if _bloody_feet and _bloody_feet.get("snow_blood_steps_count") != null:
		steps = _bloody_feet.snow_blood_steps_count
	_blood_snow_steps_remaining = steps
	if debug_logging:
		_log_info("Blood contact signal received — arming %d red snow prints (color: %s)" % [
			_blood_snow_steps_remaining, blood_color])


## Fallback for live setup paths where blood was acquired before this component
## connected to BloodyFeetComponent.blood_contact.  The signal remains the primary
## path, but this keeps snow prints red even if node order or deferred setup races.
func _arm_blood_snow_steps_from_bloody_feet_if_needed() -> void:
	if _blood_snow_steps_remaining > 0:
		return
	if _bloody_feet == null:
		_connect_bloody_feet()
	if _bloody_feet == null:
		return
	if _bloody_feet.get("on_snow") == null or not _bloody_feet.on_snow:
		return
	if not _bloody_feet.has_method("has_bloody_feet") or not _bloody_feet.has_bloody_feet():
		return

	var steps := snow_blood_steps_count
	if _bloody_feet.get("snow_blood_steps_count") != null:
		steps = _bloody_feet.snow_blood_steps_count
	if _bloody_feet.has_method("get_blood_level"):
		steps = mini(steps, _bloody_feet.get_blood_level())
	_blood_snow_steps_remaining = max(steps, 0)
	if debug_logging and _blood_snow_steps_remaining > 0:
		_log_info("Armed %d red snow prints from current BloodyFeetComponent state" % _blood_snow_steps_remaining)


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
	if not _blood_contact_connected:
		_connect_bloody_feet()
	_track_movement()


## Connects to the sibling BloodyFeetComponent once it is available.
func _connect_bloody_feet() -> void:
	if _parent_body == null or _blood_contact_connected:
		return
	_bloody_feet = _parent_body.get_node_or_null("BloodyFeetComponent")
	if _bloody_feet and _bloody_feet.has_signal("blood_contact"):
		if not _bloody_feet.blood_contact.is_connected(_on_blood_contact):
			_bloody_feet.blood_contact.connect(_on_blood_contact)
		_blood_contact_connected = true


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
## Spawns red SnowBloodFootprint for snow_blood_steps_count steps after blood contact,
## then resumes normal white SnowFootprint prints (Issue #1627).
func _spawn_footprint() -> void:
	if not _is_on_snow():
		if debug_logging:
			_log_info("Skipping snow footprint — not on snow surface")
		return

	# Primary arming happens in _on_blood_contact(); this fallback covers blood
	# acquired before the signal connection was established.
	_arm_blood_snow_steps_from_bloody_feet_if_needed()

	# Decide which scene to use: red blood print or normal white print.
	var use_blood_print := _blood_snow_steps_remaining > 0
	var active_scene: PackedScene = _snow_blood_footprint_scene if use_blood_print else _footprint_scene
	if active_scene == null:
		# Fallback to whichever scene is available.
		active_scene = _footprint_scene if _footprint_scene != null else _snow_blood_footprint_scene
	if active_scene == null:
		return

	var footprint := active_scene.instantiate() as Node2D
	if footprint == null:
		return

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

	if use_blood_print:
		# Apply blood color and compute alpha decaying over snow_blood_steps_count steps.
		var blood_color := Color(0.545, 0.0, 0.0, 1.0)
		if _bloody_feet and _bloody_feet.get("_blood_color") != null:
			blood_color = _bloody_feet._blood_color
		if footprint.has_method("set_blood_color"):
			footprint.set_blood_color(blood_color)
		else:
			footprint.modulate.r = blood_color.r
			footprint.modulate.g = blood_color.g
			footprint.modulate.b = blood_color.b

		var total := snow_blood_steps_count
		if _bloody_feet and _bloody_feet.get("snow_blood_steps_count") != null:
			total = _bloody_feet.snow_blood_steps_count
		var steps_taken := total - _blood_snow_steps_remaining
		var alpha := initial_alpha - (steps_taken * alpha_decay_rate)
		alpha = maxf(alpha, 0.05)
		if footprint.has_method("set_alpha"):
			footprint.set_alpha(alpha)
		else:
			footprint.modulate.a = alpha

		_blood_snow_steps_remaining -= 1
		if _bloody_feet and _bloody_feet.has_method("consume_snow_blood_step"):
			_bloody_feet.consume_snow_blood_step()
		if debug_logging:
			_log_info("Red snow footprint placed (blood steps remaining: %d, alpha %.2f)" % [
				_blood_snow_steps_remaining, alpha])
	else:
		# Normal white snow print: alpha decreases with each step.
		var alpha := initial_alpha - (_step_index % snow_steps_count) * alpha_decay_rate
		alpha = maxf(alpha, 0.05)
		if footprint.has_method("set_alpha"):
			footprint.set_alpha(alpha)
		else:
			footprint.modulate.a = alpha

		_step_index += 1
		if debug_logging:
			_log_info("Snow footprint placed (step %d, alpha %.2f, facing %.2f)" % [
				_step_index, alpha, facing_direction.angle()])

	# Add to scene root so footprints stay in world space.
	var scene := get_tree().current_scene
	if scene:
		scene.add_child(footprint)
	else:
		_parent_body.get_parent().add_child(footprint)

	# Schedule fade-out so old prints gradually disappear (snow fills them in).
	_schedule_footprint_fade(footprint)


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
