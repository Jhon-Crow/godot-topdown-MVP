class_name DeathAnimationComponent
extends Node2D
## Death animation component that handles death animations with ragdoll physics.
##
## Provides angle-based death animations for 2D top-down characters.
## Includes pre-made fall animations that transition to ragdoll physics for variety.
## Supports 24 unique death directions (every 15 degrees).

## Signal emitted when death animation starts.
signal death_animation_started

## Signal emitted when death animation enters ragdoll phase.
signal ragdoll_activated

## Signal emitted when death animation completes (body at rest).
signal death_animation_completed

## Duration of the pre-made fall animation in seconds.
@export var fall_animation_duration: float = 0.8

## Point at which ragdoll activates (0.0-1.0, where 1.0 = end of fall animation).
## Set to 0.6 as per requirements (60% of fall time).
@export var ragdoll_activation_point: float = 0.6

## Whether to enable ragdoll physics after fall animation.
@export var enable_ragdoll: bool = true

## Ragdoll body friction (affects sliding after death).
@export var ragdoll_friction: float = 5.0

## Ragdoll body linear damping (slows down motion over time).
@export var ragdoll_linear_damping: float = 3.0

## Ragdoll body angular damping (slows down rotation).
@export var ragdoll_angular_damping: float = 5.0

## Maximum angular velocity for ragdoll joints (prevents jittering).
@export var max_angular_velocity: float = 2.0

## Impulse strength applied to ragdoll based on hit direction.
@export var ragdoll_impulse_strength: float = 150.0

## Joint softness for PinJoint2D (0 = stiff, higher = more flexible).
@export var joint_softness: float = 0.1

## Joint bias for PinJoint2D (affects constraint solving).
@export var joint_bias: float = 0.0

## Whether to persist the ragdoll after death (don't clean up).
## When true, the body parts will remain as physics objects in the scene.
@export var persist_body_after_death: bool = true

## Animation phase states.
enum AnimationPhase {
	NONE,           ## No death animation active
	FALLING,        ## Pre-made fall animation playing
	RAGDOLL,        ## Ragdoll physics active
	AT_REST         ## Body has come to rest
}

## Current animation phase.
var _current_phase: AnimationPhase = AnimationPhase.NONE

## Animation timer.
var _animation_timer: float = 0.0

## Direction the bullet came from (used for angle-based animation selection).
var _hit_direction: Vector2 = Vector2.RIGHT

## Hit angle in radians (0 = right, PI/2 = down, PI = left, -PI/2 = up).
var _hit_angle: float = 0.0

## Animation index based on hit angle (0-23, each representing 15 degrees).
var _animation_index: int = 0

## Original sprite positions before death animation.
var _original_body_pos: Vector2 = Vector2.ZERO
var _original_head_pos: Vector2 = Vector2.ZERO
var _original_left_arm_pos: Vector2 = Vector2.ZERO
var _original_right_arm_pos: Vector2 = Vector2.ZERO

## Original sprite rotations before death animation.
var _original_body_rot: float = 0.0
var _original_head_rot: float = 0.0
var _original_left_arm_rot: float = 0.0
var _original_right_arm_rot: float = 0.0

## References to character sprites (set by parent).
var _body_sprite: Sprite2D = null
var _head_sprite: Sprite2D = null
var _left_arm_sprite: Sprite2D = null
var _right_arm_sprite: Sprite2D = null

## Reference to character model container.
var _character_model: Node2D = null

## Ragdoll bodies created during ragdoll phase.
var _ragdoll_bodies: Array[RigidBody2D] = []

## Ragdoll joints created during ragdoll phase.
var _ragdoll_joints: Array[PinJoint2D] = []

## Whether ragdoll has been activated this death cycle.
var _ragdoll_activated: bool = false

## Whether the death animation is currently active.
var _is_active: bool = false

## Pre-defined fall animation data for each angle index (0-23).
## Each animation defines keyframes for body parts during the fall.
## Format: { "body": [...], "head": [...], "left_arm": [...], "right_arm": [...] }
## Each keyframe: { "time": 0.0-1.0, "pos": Vector2, "rot": float (degrees) }
var _fall_animations: Array[Dictionary] = []


func _ready() -> void:
	_generate_fall_animations()


func _process(delta: float) -> void:
	if not _is_active:
		return

	match _current_phase:
		AnimationPhase.FALLING:
			_update_fall_animation(delta)
		AnimationPhase.RAGDOLL:
			_update_ragdoll_phase(delta)


## Initialize the death animation component with sprite references.
## Call this from the parent character's _ready() function.
## @param body: The body Sprite2D node.
## @param head: The head Sprite2D node.
## @param left_arm: The left arm Sprite2D node.
## @param right_arm: The right arm Sprite2D node.
## @param model: The character model Node2D container.
func initialize(body: Sprite2D, head: Sprite2D, left_arm: Sprite2D, right_arm: Sprite2D, model: Node2D) -> void:
	_body_sprite = body
	_head_sprite = head
	_left_arm_sprite = left_arm
	_right_arm_sprite = right_arm
	_character_model = model


## Start the death animation with the given hit direction.
## @param hit_direction: The direction the bullet was traveling when it hit.
func start_death_animation(hit_direction: Vector2) -> void:
	if _is_active:
		return  # Already playing

	_is_active = true
	_hit_direction = hit_direction.normalized()
	_hit_angle = hit_direction.angle()

	# Calculate animation index (0-23 for 15-degree intervals).
	# Add PI to convert from [-PI, PI] to [0, 2*PI], then divide by angle step.
	var normalized_angle := fmod(_hit_angle + PI, TAU)
	_animation_index = int(normalized_angle / (TAU / 24.0)) % 24

	# Store original positions and rotations
	_store_original_transforms()

	# Start fall animation phase
	_current_phase = AnimationPhase.FALLING
	_animation_timer = 0.0
	_ragdoll_activated = false

	death_animation_started.emit()

	if is_inside_tree():
		var file_logger: Node = get_node_or_null("/root/FileLogger")
		if file_logger and file_logger.has_method("info"):
			file_logger.info("[DeathAnim] Started - Angle: %.1f deg, Index: %d" % [
				rad_to_deg(_hit_angle), _animation_index
			])


## Stop the death animation and clean up ragdoll bodies.
## Called when respawning.
## @param force_cleanup: If true, always clean up ragdoll bodies even if persist is enabled.
func reset(force_cleanup: bool = true) -> void:
	_is_active = false
	_current_phase = AnimationPhase.NONE
	_animation_timer = 0.0
	_ragdoll_activated = false

	# Clean up ragdoll bodies and joints (force cleanup on reset for respawn)
	_cleanup_ragdoll(force_cleanup)

	# Restore original transforms
	_restore_original_transforms()


## Store original sprite positions and rotations before death animation.
func _store_original_transforms() -> void:
	if _body_sprite:
		_original_body_pos = _body_sprite.position
		_original_body_rot = _body_sprite.rotation
	if _head_sprite:
		_original_head_pos = _head_sprite.position
		_original_head_rot = _head_sprite.rotation
	if _left_arm_sprite:
		_original_left_arm_pos = _left_arm_sprite.position
		_original_left_arm_rot = _left_arm_sprite.rotation
	if _right_arm_sprite:
		_original_right_arm_pos = _right_arm_sprite.position
		_original_right_arm_rot = _right_arm_sprite.rotation


## Restore original sprite transforms after death animation reset.
func _restore_original_transforms() -> void:
	if _body_sprite:
		_body_sprite.position = _original_body_pos
		_body_sprite.rotation = _original_body_rot
		_body_sprite.visible = true
	if _head_sprite:
		_head_sprite.position = _original_head_pos
		_head_sprite.rotation = _original_head_rot
		_head_sprite.visible = true
	if _left_arm_sprite:
		_left_arm_sprite.position = _original_left_arm_pos
		_left_arm_sprite.rotation = _original_left_arm_rot
		_left_arm_sprite.visible = true
	if _right_arm_sprite:
		_right_arm_sprite.position = _original_right_arm_pos
		_right_arm_sprite.rotation = _original_right_arm_rot
		_right_arm_sprite.visible = true


## Update the pre-made fall animation.
func _update_fall_animation(delta: float) -> void:
	_animation_timer += delta
	var progress := clampf(_animation_timer / fall_animation_duration, 0.0, 1.0)

	# Apply animation keyframes
	_apply_fall_animation_frame(progress)

	# Check if we should activate ragdoll
	if enable_ragdoll and not _ragdoll_activated and progress >= ragdoll_activation_point:
		_activate_ragdoll()

	# Check if animation is complete
	if progress >= 1.0:
		if enable_ragdoll and _ragdoll_activated:
			_current_phase = AnimationPhase.RAGDOLL
		else:
			_current_phase = AnimationPhase.AT_REST
			death_animation_completed.emit()


## Apply fall animation frame based on progress (0.0 to 1.0).
func _apply_fall_animation_frame(progress: float) -> void:
	if _animation_index < 0 or _animation_index >= _fall_animations.size():
		return

	var anim_data := _fall_animations[_animation_index]

	# Apply to each body part
	if _body_sprite and anim_data.has("body"):
		_apply_keyframes_to_sprite(_body_sprite, anim_data["body"], progress, _original_body_pos, _original_body_rot)

	if _head_sprite and anim_data.has("head"):
		_apply_keyframes_to_sprite(_head_sprite, anim_data["head"], progress, _original_head_pos, _original_head_rot)

	if _left_arm_sprite and anim_data.has("left_arm"):
		_apply_keyframes_to_sprite(_left_arm_sprite, anim_data["left_arm"], progress, _original_left_arm_pos, _original_left_arm_rot)

	if _right_arm_sprite and anim_data.has("right_arm"):
		_apply_keyframes_to_sprite(_right_arm_sprite, anim_data["right_arm"], progress, _original_right_arm_pos, _original_right_arm_rot)


## Apply keyframes to a sprite based on animation progress.
func _apply_keyframes_to_sprite(sprite: Sprite2D, keyframes: Array, progress: float, base_pos: Vector2, base_rot: float) -> void:
	if keyframes.is_empty():
		return

	# Find the two keyframes to interpolate between
	var prev_kf: Dictionary = keyframes[0]
	var next_kf: Dictionary = keyframes[0]

	for i in range(keyframes.size()):
		var kf: Dictionary = keyframes[i]
		if kf["time"] <= progress:
			prev_kf = kf
			if i + 1 < keyframes.size():
				next_kf = keyframes[i + 1]
			else:
				next_kf = kf
		else:
			next_kf = kf
			break

	# Calculate interpolation factor between keyframes
	var t := 0.0
	if next_kf["time"] > prev_kf["time"]:
		t = (progress - prev_kf["time"]) / (next_kf["time"] - prev_kf["time"])

	# Apply ease-out for natural motion
	t = 1.0 - pow(1.0 - t, 2.0)

	# Interpolate position and rotation
	var pos_offset: Vector2 = prev_kf["pos"].lerp(next_kf["pos"], t)
	var rot_offset: float = lerpf(prev_kf["rot"], next_kf["rot"], t)

	sprite.position = base_pos + pos_offset
	sprite.rotation = base_rot + deg_to_rad(rot_offset)


## Activate ragdoll physics by creating RigidBody2D nodes for each body part.
func _activate_ragdoll() -> void:
	if _ragdoll_activated:
		return

	_ragdoll_activated = true
	ragdoll_activated.emit()

	if is_inside_tree():
		var file_logger: Node = get_node_or_null("/root/FileLogger")
		if file_logger and file_logger.has_method("info"):
			file_logger.info("[DeathAnim] Ragdoll activated at %.0f%% fall progress" % (
				ragdoll_activation_point * 100.0
			))

	# Create ragdoll bodies for each sprite
	var body_rb: RigidBody2D = null
	var head_rb: RigidBody2D = null
	var left_arm_rb: RigidBody2D = null
	var right_arm_rb: RigidBody2D = null

	if _body_sprite:
		body_rb = _create_ragdoll_body(_body_sprite, 1.5, 12.0)  # Body is heavier and larger

	if _head_sprite:
		head_rb = _create_ragdoll_body(_head_sprite, 0.5, 8.0)

	if _left_arm_sprite:
		left_arm_rb = _create_ragdoll_body(_left_arm_sprite, 0.3, 6.0)

	if _right_arm_sprite:
		right_arm_rb = _create_ragdoll_body(_right_arm_sprite, 0.3, 6.0)

	# Create joints connecting body parts
	# Head to body
	if body_rb and head_rb:
		var joint := _create_ragdoll_joint(body_rb, head_rb, Vector2(-6, -2))  # Head offset
		_ragdoll_joints.append(joint)

	# Left arm to body
	if body_rb and left_arm_rb:
		var joint := _create_ragdoll_joint(body_rb, left_arm_rb, Vector2(0, 6))  # Shoulder position
		_ragdoll_joints.append(joint)

	# Right arm to body
	if body_rb and right_arm_rb:
		var joint := _create_ragdoll_joint(body_rb, right_arm_rb, Vector2(-8, 6))  # Shoulder position
		_ragdoll_joints.append(joint)

	# Apply impulse based on hit direction
	if body_rb:
		var impulse := _hit_direction * ragdoll_impulse_strength
		body_rb.apply_central_impulse(impulse)

		# Add some angular impulse for rotation
		var angular_impulse := randf_range(-2.0, 2.0)
		body_rb.apply_torque_impulse(angular_impulse * 50.0)


## Create a ragdoll RigidBody2D for a sprite.
func _create_ragdoll_body(sprite: Sprite2D, mass: float, collision_radius: float) -> RigidBody2D:
	if not sprite or not _character_model:
		return null

	# Create RigidBody2D
	var rb := RigidBody2D.new()
	rb.mass = mass
	rb.linear_damp = ragdoll_linear_damping
	rb.angular_damp = ragdoll_angular_damping
	rb.max_contacts_reported = 0
	rb.contact_monitor = false
	rb.gravity_scale = 0.0  # Top-down, no gravity

	# Set physics material properties via properties
	rb.physics_material_override = PhysicsMaterial.new()
	rb.physics_material_override.friction = ragdoll_friction
	rb.physics_material_override.bounce = 0.0

	# Create collision shape (small circle to prevent jittering)
	var collision := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = collision_radius * 0.5  # Smaller collision to prevent jitter
	collision.shape = shape
	rb.add_child(collision)

	# Position the rigid body at the sprite's global position
	var global_pos := sprite.global_position
	rb.global_position = global_pos
	rb.rotation = sprite.global_rotation

	# Set collision layer to avoid player/enemy collision
	rb.collision_layer = 32  # Custom layer for ragdoll
	rb.collision_mask = 4    # Collide with obstacles only

	# Add to scene
	get_tree().current_scene.add_child(rb)
	_ragdoll_bodies.append(rb)

	# Reparent sprite to rigid body
	sprite.get_parent().remove_child(sprite)
	rb.add_child(sprite)
	sprite.position = Vector2.ZERO
	sprite.rotation = 0.0

	return rb


## Create a PinJoint2D connecting two ragdoll bodies.
func _create_ragdoll_joint(body_a: RigidBody2D, body_b: RigidBody2D, anchor_offset: Vector2) -> PinJoint2D:
	var joint := PinJoint2D.new()
	joint.node_a = body_a.get_path()
	joint.node_b = body_b.get_path()
	joint.softness = joint_softness
	joint.bias = joint_bias

	# Position joint at the connection point
	joint.global_position = body_a.global_position + anchor_offset.rotated(body_a.rotation)

	# Add to scene
	get_tree().current_scene.add_child(joint)

	return joint


## Update ragdoll phase (check if bodies have come to rest).
func _update_ragdoll_phase(delta: float) -> void:
	_animation_timer += delta

	# Check if all bodies have slowed down enough to be considered at rest
	var all_at_rest := true
	var velocity_threshold := 5.0
	var angular_threshold := 0.5

	for rb in _ragdoll_bodies:
		if is_instance_valid(rb):
			# Clamp angular velocity to prevent jittering
			if absf(rb.angular_velocity) > max_angular_velocity:
				rb.angular_velocity = signf(rb.angular_velocity) * max_angular_velocity

			# Apply additional damping when velocity is low (prevents micro-jitter)
			if rb.linear_velocity.length() < 20.0:
				rb.linear_velocity *= 0.95  # Extra damping
			if absf(rb.angular_velocity) < 1.0:
				rb.angular_velocity *= 0.9  # Extra angular damping

			if rb.linear_velocity.length() > velocity_threshold or absf(rb.angular_velocity) > angular_threshold:
				all_at_rest = false
				break

	# After some time or when at rest, transition to final state
	if all_at_rest or _animation_timer > 5.0:  # Max 5 seconds of ragdoll
		_current_phase = AnimationPhase.AT_REST

		# Freeze ragdoll bodies to save performance and prevent jittering
		for rb in _ragdoll_bodies:
			if is_instance_valid(rb):
				rb.freeze = true
				rb.linear_velocity = Vector2.ZERO
				rb.angular_velocity = 0.0

		death_animation_completed.emit()


## Clean up ragdoll bodies and joints.
## If persist_body_after_death is true, bodies remain in the scene.
## @param force_cleanup: If true, always clean up regardless of persist setting.
func _cleanup_ragdoll(force_cleanup: bool = false) -> void:
	if persist_body_after_death and not force_cleanup:
		# Keep the ragdoll bodies in the scene, just clear references
		# The bodies will persist as standalone physics objects
		_ragdoll_bodies.clear()
		_ragdoll_joints.clear()
		return

	# Restore sprites to character model before cleanup
	for rb in _ragdoll_bodies:
		if is_instance_valid(rb):
			# Find and restore any sprites
			for child in rb.get_children():
				if child is Sprite2D:
					rb.remove_child(child)
					if _character_model:
						_character_model.add_child(child)
			rb.queue_free()

	_ragdoll_bodies.clear()

	for joint in _ragdoll_joints:
		if is_instance_valid(joint):
			joint.queue_free()

	_ragdoll_joints.clear()


## Generate fall animations for all 24 angle indices.
## Each animation defines unique keyframes based on the direction of the hit.
func _generate_fall_animations() -> void:
	_fall_animations.clear()

	# Generate 24 animations, one for each 15-degree interval
	for i in range(24):
		var angle := float(i) * 15.0 - 180.0  # Degrees, -180 to +165
		var anim := _create_fall_animation_for_angle(angle)
		_fall_animations.append(anim)


## Create fall animation data for a specific hit angle.
## @param angle: Hit angle in degrees (-180 to +180).
func _create_fall_animation_for_angle(angle: float) -> Dictionary:
	# Convert angle to radians for calculations
	var rad := deg_to_rad(angle)

	# Calculate fall direction (opposite to hit direction - body falls away from bullet)
	var fall_dir := Vector2(cos(rad), sin(rad))

	# Base fall distance and rotation
	var fall_distance := 25.0
	var body_rotation := angle * 0.5  # Body rotates partially toward hit
	var head_lag := 15.0  # Head lags behind body rotation
	var arm_swing := 30.0  # Arms swing on impact

	# Randomize slightly for variety
	var variation := randf_range(-5.0, 5.0)
	body_rotation += variation

	# Calculate final positions
	var body_final_pos := fall_dir * fall_distance
	var head_final_pos := fall_dir * (fall_distance * 0.8) + Vector2(randf_range(-3, 3), randf_range(-3, 3))

	# Arms fly out on the side opposite to hit
	var left_arm_final_pos := fall_dir * (fall_distance * 0.6) + Vector2(-fall_dir.y, fall_dir.x) * 8.0
	var right_arm_final_pos := fall_dir * (fall_distance * 0.6) + Vector2(fall_dir.y, -fall_dir.x) * 8.0

	return {
		"body": [
			{ "time": 0.0, "pos": Vector2.ZERO, "rot": 0.0 },
			{ "time": 0.2, "pos": fall_dir * fall_distance * 0.3, "rot": body_rotation * 0.4 },
			{ "time": 0.5, "pos": fall_dir * fall_distance * 0.7, "rot": body_rotation * 0.8 },
			{ "time": 0.8, "pos": body_final_pos * 0.95, "rot": body_rotation * 0.95 },
			{ "time": 1.0, "pos": body_final_pos, "rot": body_rotation }
		],
		"head": [
			{ "time": 0.0, "pos": Vector2.ZERO, "rot": 0.0 },
			{ "time": 0.15, "pos": fall_dir * fall_distance * 0.1, "rot": -head_lag * 0.3 },  # Head snaps back first
			{ "time": 0.3, "pos": fall_dir * fall_distance * 0.4, "rot": body_rotation * 0.3 - head_lag * 0.5 },
			{ "time": 0.6, "pos": fall_dir * fall_distance * 0.75, "rot": body_rotation * 0.7 + head_lag * 0.2 },
			{ "time": 1.0, "pos": head_final_pos, "rot": body_rotation + head_lag * 0.3 }
		],
		"left_arm": [
			{ "time": 0.0, "pos": Vector2.ZERO, "rot": 0.0 },
			{ "time": 0.1, "pos": Vector2(-fall_dir.y, fall_dir.x) * 5.0, "rot": -arm_swing },  # Arm swings out
			{ "time": 0.4, "pos": left_arm_final_pos * 0.5, "rot": -arm_swing * 0.5 + body_rotation * 0.3 },
			{ "time": 0.7, "pos": left_arm_final_pos * 0.85, "rot": arm_swing * 0.3 + body_rotation * 0.7 },
			{ "time": 1.0, "pos": left_arm_final_pos, "rot": arm_swing * 0.5 + body_rotation }
		],
		"right_arm": [
			{ "time": 0.0, "pos": Vector2.ZERO, "rot": 0.0 },
			{ "time": 0.1, "pos": Vector2(fall_dir.y, -fall_dir.x) * 5.0, "rot": arm_swing },  # Arm swings out
			{ "time": 0.4, "pos": right_arm_final_pos * 0.5, "rot": arm_swing * 0.5 + body_rotation * 0.3 },
			{ "time": 0.7, "pos": right_arm_final_pos * 0.85, "rot": -arm_swing * 0.3 + body_rotation * 0.7 },
			{ "time": 1.0, "pos": right_arm_final_pos, "rot": -arm_swing * 0.5 + body_rotation }
		]
	}


## Check if death animation is currently active.
func is_active() -> bool:
	return _is_active


## Check if death animation has completed (body at rest).
func is_complete() -> bool:
	return _current_phase == AnimationPhase.AT_REST


## Get current animation phase.
func get_phase() -> AnimationPhase:
	return _current_phase
