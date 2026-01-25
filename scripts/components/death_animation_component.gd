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

## Speed multiplier for the death animation (1.0 = normal speed, 0.1 = slow motion).
@export var animation_speed: float = 1.0

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
@export var ragdoll_impulse_strength: float = 100.0

## Joint softness for PinJoint2D (0 = stiff, higher = more flexible).
@export var joint_softness: float = 0.0

## Joint bias for PinJoint2D (affects constraint solving, higher = stiffer).
@export var joint_bias: float = 0.2

## Whether to persist the ragdoll after death (don't clean up).
## When true, the body parts will remain as physics objects in the scene.
@export var persist_body_after_death: bool = true

## Whether ragdoll bodies react to bullets after death.
## When true, shooting a dead body will cause it to move/twitch.
@export var react_to_bullets: bool = true

## Impulse strength multiplier for post-death bullet hits.
## Different weapon types have different base impulses, this scales them.
@export var bullet_reaction_impulse_scale: float = 1.0

## Time to re-freeze ragdoll after bullet hit reaction (seconds).
## Set to -1 to never re-freeze after a hit.
@export var refreeze_delay_after_hit: float = 1.5

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

## Type of weapon that caused the death (affects animation style).
var _weapon_type: String = "rifle"

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
var _weapon_sprite: Sprite2D = null

## Reference to character model container.
var _character_model: Node2D = null

## Original weapon transform.
var _original_weapon_pos: Vector2 = Vector2.ZERO
var _original_weapon_rot: float = 0.0
var _original_weapon_offset: Vector2 = Vector2.ZERO

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

## Timer for re-freezing ragdoll after bullet hit.
var _refreeze_timer: float = -1.0

## Whether we're waiting to re-freeze after a bullet hit.
var _waiting_to_refreeze: bool = false

## Whether this ragdoll has been registered with RagdollManager for persistence.
var _registered_with_manager: bool = false

## Weapon-specific impulse profiles for post-death reactions.
## Format: { "weapon_type": { "impulse": float, "angular": float, "description": String } }
const BULLET_IMPULSE_PROFILES := {
	"shotgun": { "impulse": 250.0, "angular": 80.0, "description": "Strong knockback" },
	"rifle": { "impulse": 120.0, "angular": 40.0, "description": "Medium twitching" },
	"assault_rifle": { "impulse": 100.0, "angular": 35.0, "description": "Medium twitching" },
	"uzi": { "impulse": 60.0, "angular": 25.0, "description": "Light rapid twitching" },
	"smg": { "impulse": 70.0, "angular": 30.0, "description": "Light twitching" },
	"pistol": { "impulse": 50.0, "angular": 20.0, "description": "Light push" },
	"default": { "impulse": 80.0, "angular": 30.0, "description": "Default reaction" }
}


func _ready() -> void:
	_generate_fall_animations()


func _process(delta: float) -> void:
	# Handle re-freeze timer for bullet reactions (runs even when not in active animation)
	if _waiting_to_refreeze and refreeze_delay_after_hit >= 0:
		_refreeze_timer -= delta
		if _refreeze_timer <= 0:
			_refreeze_ragdoll_bodies()
			_waiting_to_refreeze = false

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
## @param weapon: Optional weapon Sprite2D node.
func initialize(body: Sprite2D, head: Sprite2D, left_arm: Sprite2D, right_arm: Sprite2D, model: Node2D, weapon: Sprite2D = null) -> void:
	_body_sprite = body
	_head_sprite = head
	_left_arm_sprite = left_arm
	_right_arm_sprite = right_arm
	_character_model = model
	_weapon_sprite = weapon


## Start the death animation with the given hit direction and weapon type.
## @param hit_direction: The direction the bullet was traveling when it hit.
## @param weapon_type: The type of weapon that caused the death (for different animations).
func start_death_animation(hit_direction: Vector2, weapon_type: String = "rifle") -> void:
	if _is_active:
		return  # Already playing

	_is_active = true
	_hit_direction = hit_direction.normalized()
	_hit_angle = hit_direction.angle()
	_weapon_type = weapon_type

	# Generate animations for this weapon type
	_generate_fall_animations(_weapon_type)

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
	# Reset registration flag - new death animation can register new bodies
	_registered_with_manager = false

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
	if _weapon_sprite:
		_original_weapon_pos = _weapon_sprite.position
		_original_weapon_rot = _weapon_sprite.rotation
		_original_weapon_offset = _weapon_sprite.offset


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
	if _weapon_sprite:
		_weapon_sprite.position = _original_weapon_pos
		_weapon_sprite.rotation = _original_weapon_rot
		_weapon_sprite.offset = _original_weapon_offset
		_weapon_sprite.visible = true


## Update the pre-made fall animation.
func _update_fall_animation(delta: float) -> void:
	_animation_timer += delta * animation_speed
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

	# Get scale from character model for proper sizing
	var model_scale := 1.0
	if _character_model:
		model_scale = _character_model.scale.x

	# Hide original sprites during ragdoll phase
	if _body_sprite:
		_body_sprite.visible = false
	if _head_sprite:
		_head_sprite.visible = false
	if _left_arm_sprite:
		_left_arm_sprite.visible = false
	if _right_arm_sprite:
		_right_arm_sprite.visible = false
	if _weapon_sprite:
		_weapon_sprite.visible = false

	# Create ragdoll bodies for each sprite
	var body_rb: RigidBody2D = null
	var head_rb: RigidBody2D = null
	var left_arm_rb: RigidBody2D = null
	var right_arm_rb: RigidBody2D = null
	var weapon_rb: RigidBody2D = null

	if _body_sprite:
		body_rb = _create_ragdoll_body(_body_sprite, 1.5, 12.0 * model_scale)  # Body is heavier and larger

	if _head_sprite:
		head_rb = _create_ragdoll_body(_head_sprite, 0.5, 8.0 * model_scale)

	if _left_arm_sprite:
		left_arm_rb = _create_ragdoll_body(_left_arm_sprite, 0.3, 6.0 * model_scale)

	if _right_arm_sprite:
		right_arm_rb = _create_ragdoll_body(_right_arm_sprite, 0.3, 6.0 * model_scale)

	# Create weapon ragdoll body (weapon stays with dead body)
	if _weapon_sprite:
		weapon_rb = _create_ragdoll_body_for_weapon(_weapon_sprite, 0.2, 4.0 * model_scale)

	# Create joints connecting body parts
	# Head to body
	if body_rb and head_rb:
		var head_joint := _create_ragdoll_joint(body_rb, head_rb, Vector2(-6, -2) * model_scale)
		_ragdoll_joints.append(head_joint)

	# Left arm to body
	if body_rb and left_arm_rb:
		var left_arm_joint := _create_ragdoll_joint(body_rb, left_arm_rb, Vector2(0, 6) * model_scale)
		_ragdoll_joints.append(left_arm_joint)

	# Right arm to body
	if body_rb and right_arm_rb:
		var right_arm_joint := _create_ragdoll_joint(body_rb, right_arm_rb, Vector2(-8, 6) * model_scale)
		_ragdoll_joints.append(right_arm_joint)

	# Weapon to right arm (held in hand)
	if right_arm_rb and weapon_rb:
		# Weapon attaches at the end of the right arm (hand position)
		var weapon_joint := _create_ragdoll_joint(right_arm_rb, weapon_rb, Vector2(12, 0) * model_scale)
		_ragdoll_joints.append(weapon_joint)

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

	# Create collision shape (circle for ragdoll parts)
	var collision := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = collision_radius  # Full radius for better collision
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

	# Create a duplicate sprite for the ragdoll body (don't reparent original)
	var ragdoll_sprite := Sprite2D.new()
	ragdoll_sprite.texture = sprite.texture
	ragdoll_sprite.region_enabled = sprite.region_enabled
	ragdoll_sprite.region_rect = sprite.region_rect
	ragdoll_sprite.offset = sprite.offset
	ragdoll_sprite.flip_h = sprite.flip_h
	ragdoll_sprite.flip_v = sprite.flip_v
	ragdoll_sprite.modulate = sprite.modulate
	ragdoll_sprite.z_index = sprite.z_index
	ragdoll_sprite.z_as_relative = sprite.z_as_relative

	rb.add_child(ragdoll_sprite)
	ragdoll_sprite.position = Vector2.ZERO
	ragdoll_sprite.rotation = 0.0

	# Add hit detection area for bullet reactions
	if react_to_bullets:
		var hit_area := Area2D.new()
		hit_area.name = "BulletHitArea"
		hit_area.collision_layer = 0  # Don't detect others
		hit_area.collision_mask = 16  # Layer 5 = bullets (1 << 4 = 16)
		hit_area.monitoring = true
		hit_area.monitorable = false

		var hit_shape := CollisionShape2D.new()
		var hit_circle := CircleShape2D.new()
		hit_circle.radius = collision_radius * 1.2  # Slightly larger for easier detection
		hit_shape.shape = hit_circle
		hit_area.add_child(hit_shape)

		rb.add_child(hit_area)
		hit_area.area_entered.connect(_on_ragdoll_bullet_hit.bind(rb))

	return rb


## Create a ragdoll RigidBody2D for a weapon sprite.
## Similar to _create_ragdoll_body but handles weapon offset properly.
func _create_ragdoll_body_for_weapon(sprite: Sprite2D, mass: float, collision_radius: float) -> RigidBody2D:
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

	# Create collision shape (rectangle for weapons is better, but circle is simpler)
	var collision := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = collision_radius
	collision.shape = shape
	rb.add_child(collision)

	# Position the rigid body at the sprite's global position (accounting for weapon offset)
	var global_pos := sprite.global_position
	rb.global_position = global_pos
	rb.rotation = sprite.global_rotation

	# Set collision layer to avoid player/enemy collision
	rb.collision_layer = 32  # Custom layer for ragdoll
	rb.collision_mask = 4    # Collide with obstacles only

	# Add to scene
	get_tree().current_scene.add_child(rb)
	_ragdoll_bodies.append(rb)

	# Create a duplicate sprite for the ragdoll body
	var ragdoll_sprite := Sprite2D.new()
	ragdoll_sprite.texture = sprite.texture
	ragdoll_sprite.region_enabled = sprite.region_enabled
	ragdoll_sprite.region_rect = sprite.region_rect
	# For weapon, preserve the offset so it looks correct
	ragdoll_sprite.offset = sprite.offset
	ragdoll_sprite.flip_h = sprite.flip_h
	ragdoll_sprite.flip_v = sprite.flip_v
	ragdoll_sprite.modulate = sprite.modulate
	ragdoll_sprite.z_index = sprite.z_index
	ragdoll_sprite.z_as_relative = sprite.z_as_relative

	rb.add_child(ragdoll_sprite)
	ragdoll_sprite.position = Vector2.ZERO
	ragdoll_sprite.rotation = 0.0

	# Weapons don't need bullet hit detection (they're not body parts)
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
	_animation_timer += delta * animation_speed

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

		# Register with RagdollManager for persistence across scene reloads
		if persist_body_after_death:
			_register_with_ragdoll_manager()

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

	# Clean up ragdoll bodies (ragdoll sprites are duplicates, so just free everything)
	for rb in _ragdoll_bodies:
		if is_instance_valid(rb):
			rb.queue_free()

	_ragdoll_bodies.clear()

	for joint in _ragdoll_joints:
		if is_instance_valid(joint):
			joint.queue_free()

	_ragdoll_joints.clear()


## Generate fall animations for all 24 angle indices.
## Each animation defines unique keyframes based on the direction of the hit and weapon type.
func _generate_fall_animations(weapon_type: String = "rifle") -> void:
	_fall_animations.clear()

	# Generate 24 animations, one for each 15-degree interval
	for i in range(24):
		var angle := float(i) * 15.0 - 180.0  # Degrees, -180 to +165
		var anim := _create_fall_animation_for_angle(angle, weapon_type)
		_fall_animations.append(anim)


## Create fall animation data for a specific hit angle and weapon type.
## @param angle: Hit angle in degrees (-180 to +180).
## @param weapon_type: The weapon type affecting animation intensity.
func _create_fall_animation_for_angle(angle: float, weapon_type: String = "rifle") -> Dictionary:
	# Convert angle to radians for calculations
	var rad := deg_to_rad(angle)

	# Calculate fall direction (opposite to hit direction - body falls away from bullet)
	var fall_dir := Vector2(cos(rad), sin(rad))

	# Base fall distance and rotation (varies by weapon)
	var fall_distance := 25.0
	var body_rotation := angle * 0.5  # Body rotates partially toward hit
	var head_lag := 15.0  # Head lags behind body rotation
	var arm_swing := 30.0  # Arms swing on impact

	# Adjust animation intensity based on weapon type
	match weapon_type.to_lower():
		"shotgun":
			# Shotguns cause more violent deaths
			fall_distance *= 1.5
			body_rotation *= 1.3
			head_lag *= 1.2
			arm_swing *= 1.4
		"pistol", "uzi":
			# Smaller caliber weapons cause less dramatic falls
			fall_distance *= 0.7
			body_rotation *= 0.8
			head_lag *= 0.9
			arm_swing *= 0.8
		"rifle":
			# Default rifle behavior
			pass

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


## Called when a bullet hits a ragdoll body part.
## Applies impulse based on bullet direction and weapon type.
func _on_ragdoll_bullet_hit(bullet_area: Area2D, ragdoll_body: RigidBody2D) -> void:
	if not is_instance_valid(ragdoll_body) or not is_instance_valid(bullet_area):
		return

	# Get bullet direction and weapon info
	var bullet_direction := Vector2.RIGHT
	var weapon_type := "default"

	# Try to get bullet direction from velocity or direction property
	if bullet_area.has_method("get_direction"):
		bullet_direction = bullet_area.get_direction()
	elif bullet_area.get("direction") != null:
		bullet_direction = bullet_area.direction
	elif bullet_area.get("linear_velocity") != null:
		bullet_direction = bullet_area.linear_velocity.normalized()
	else:
		# Estimate from position difference
		bullet_direction = (ragdoll_body.global_position - bullet_area.global_position).normalized()

	# Try to get weapon type from caliber data
	if bullet_area.has_method("get_caliber_data"):
		var caliber_data = bullet_area.get_caliber_data()
		if caliber_data and caliber_data.has("weapon_type"):
			weapon_type = caliber_data.weapon_type
	elif bullet_area.get("caliber_data") != null:
		var caliber_data = bullet_area.caliber_data
		if caliber_data and caliber_data.has("weapon_type"):
			weapon_type = caliber_data.weapon_type

	# Apply impulse to the ragdoll body
	apply_bullet_impulse_to_body(ragdoll_body, bullet_direction, weapon_type, bullet_area.global_position)


## Apply bullet impulse to a specific ragdoll body.
## @param body: The RigidBody2D to apply impulse to.
## @param bullet_direction: The direction the bullet was traveling.
## @param weapon_type: The type of weapon that fired the bullet.
## @param hit_position: Global position where the bullet hit.
func apply_bullet_impulse_to_body(body: RigidBody2D, bullet_direction: Vector2, weapon_type: String, hit_position: Vector2) -> void:
	if not is_instance_valid(body):
		return

	# Get impulse profile for weapon type
	var profile: Dictionary = BULLET_IMPULSE_PROFILES.get(weapon_type.to_lower(), BULLET_IMPULSE_PROFILES["default"])

	var base_impulse: float = profile["impulse"]
	var angular_impulse: float = profile["angular"]

	# Scale by the component's multiplier
	base_impulse *= bullet_reaction_impulse_scale
	angular_impulse *= bullet_reaction_impulse_scale

	# Unfreeze the body if it was frozen
	if body.freeze:
		body.freeze = false

	# Calculate impulse at hit point (offset from center creates rotation)
	var offset := hit_position - body.global_position
	var impulse := bullet_direction.normalized() * base_impulse

	# Apply impulse at offset position
	body.apply_impulse(impulse, offset)

	# Add some angular impulse for twitching effect
	var random_angular := randf_range(-1.0, 1.0) * angular_impulse
	body.apply_torque_impulse(random_angular)

	# Also apply smaller impulse to connected bodies for propagation
	_propagate_impulse_to_connected_bodies(body, bullet_direction, base_impulse * 0.3)

	# Start re-freeze timer
	if refreeze_delay_after_hit >= 0:
		_refreeze_timer = refreeze_delay_after_hit
		_waiting_to_refreeze = true

	# Log the hit
	if is_inside_tree():
		var file_logger: Node = get_node_or_null("/root/FileLogger")
		if file_logger and file_logger.has_method("debug"):
			file_logger.debug("[DeathAnim] Bullet hit ragdoll - Weapon: %s, Impulse: %.1f" % [weapon_type, base_impulse])


## Propagate a smaller impulse to bodies connected via joints.
func _propagate_impulse_to_connected_bodies(hit_body: RigidBody2D, direction: Vector2, impulse_strength: float) -> void:
	for rb in _ragdoll_bodies:
		if is_instance_valid(rb) and rb != hit_body:
			# Unfreeze connected body
			if rb.freeze:
				rb.freeze = false
			# Apply smaller impulse
			rb.apply_central_impulse(direction * impulse_strength * randf_range(0.5, 1.0))


## Re-freeze all ragdoll bodies after bullet reaction settles.
func _refreeze_ragdoll_bodies() -> void:
	for rb in _ragdoll_bodies:
		if is_instance_valid(rb):
			# Only freeze if velocity is low enough
			if rb.linear_velocity.length() < 30.0 and absf(rb.angular_velocity) < 2.0:
				rb.freeze = true
				rb.linear_velocity = Vector2.ZERO
				rb.angular_velocity = 0.0


## Apply bullet impulse to all ragdoll bodies (external call).
## Used when a bullet hits the dead enemy from outside this component.
## @param bullet_direction: Direction the bullet was traveling.
## @param weapon_type: Type of weapon that fired the bullet.
## @param hit_position: Global position where the bullet hit.
func apply_bullet_reaction(bullet_direction: Vector2, weapon_type: String, hit_position: Vector2) -> void:
	# Find the closest ragdoll body to the hit position
	var closest_body: RigidBody2D = null
	var closest_dist := INF

	for rb in _ragdoll_bodies:
		if is_instance_valid(rb):
			var dist := rb.global_position.distance_to(hit_position)
			if dist < closest_dist:
				closest_dist = dist
				closest_body = rb

	if closest_body:
		apply_bullet_impulse_to_body(closest_body, bullet_direction, weapon_type, hit_position)


## Get all ragdoll bodies (for external access).
func get_ragdoll_bodies() -> Array[RigidBody2D]:
	return _ragdoll_bodies


## Check if ragdoll has any valid bodies.
func has_ragdoll_bodies() -> bool:
	for rb in _ragdoll_bodies:
		if is_instance_valid(rb):
			return true
	return false


## Register ragdoll bodies with RagdollManager for persistence across scene reloads.
## This moves the bodies from the current scene to the autoload container.
func _register_with_ragdoll_manager() -> void:
	if _registered_with_manager:
		return  # Already registered

	var ragdoll_manager: Node = get_node_or_null("/root/RagdollManager")
	if ragdoll_manager == null:
		# RagdollManager not available, bodies will not persist
		if is_inside_tree():
			var file_logger: Node = get_node_or_null("/root/FileLogger")
			if file_logger and file_logger.has_method("warn"):
				file_logger.warn("[DeathAnim] RagdollManager not found - bodies will not persist across scene reload")
		return

	# Filter valid bodies and joints
	var valid_bodies: Array[RigidBody2D] = []
	for rb in _ragdoll_bodies:
		if is_instance_valid(rb):
			valid_bodies.append(rb)

	var valid_joints: Array[PinJoint2D] = []
	for joint in _ragdoll_joints:
		if is_instance_valid(joint):
			valid_joints.append(joint)

	if valid_bodies.is_empty():
		return

	# Register with manager (this will reparent bodies to the persistent container)
	if ragdoll_manager.has_method("register_ragdoll_group"):
		var group_index: int = ragdoll_manager.register_ragdoll_group(valid_bodies, valid_joints)
		if group_index >= 0:
			_registered_with_manager = true
			# Clear local references since manager now owns them
			_ragdoll_bodies.clear()
			_ragdoll_joints.clear()

			if is_inside_tree():
				var file_logger: Node = get_node_or_null("/root/FileLogger")
				if file_logger and file_logger.has_method("info"):
					file_logger.info("[DeathAnim] Ragdoll registered with RagdollManager (group #%d) - will persist across scene reload" % group_index)
