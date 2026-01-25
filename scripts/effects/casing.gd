extends RigidBody2D
## Bullet casing that gets ejected from weapons and falls to the ground.
##
## Casings are spawned when weapons fire, ejected in the opposite direction
## of the shot with some randomness. They fall to the ground and can be
## kicked by characters, producing satisfying bounce sounds.

## Lifetime in seconds before auto-destruction (0 = infinite).
@export var lifetime: float = 0.0

## Caliber data for determining casing appearance.
@export var caliber_data: Resource = null

## Enable verbose debug logging for troubleshooting collision issues.
@export var debug_logging: bool = false

## Whether the casing has landed on the ground.
var _has_landed: bool = false

## Timer for lifetime management.
var _lifetime_timer: float = 0.0

## Timer for automatic landing (since no floor in top-down game).
var _auto_land_timer: float = 0.0

## Time before casing automatically "lands" and stops moving.
const AUTO_LAND_TIME: float = 2.0

## Minimum velocity for playing bounce sound (pixels/sec).
const BOUNCE_SOUND_VELOCITY_THRESHOLD: float = 75.0

## Cooldown between bounce sounds to prevent audio spam.
const BOUNCE_SOUND_COOLDOWN: float = 0.1

## Timer for bounce sound cooldown.
var _bounce_sound_cooldown_timer: float = 0.0

## Force applied when kicked by a character.
const KICK_FORCE: float = 50.0

## Stores velocity before time freeze (to restore after unfreeze).
var _frozen_linear_velocity: Vector2 = Vector2.ZERO
var _frozen_angular_velocity: float = 0.0

## Whether the casing is currently frozen in time.
var _is_time_frozen: bool = false

## Reference to the kick detector Area2D.
var _kick_detector: Area2D = null

## Cooldown timer for manual overlap check to prevent spam.
var _overlap_check_cooldown: float = 0.0

## Cooldown duration for overlap checks (seconds).
const OVERLAP_CHECK_COOLDOWN: float = 0.1

## Track bodies we've already kicked by (to prevent repeat kicks).
var _recently_kicked_by: Array[int] = []

## Timer for clearing the recently kicked list.
var _kick_memory_timer: float = 0.0

## How long to remember a kick (seconds).
const KICK_MEMORY_DURATION: float = 0.3


func _ready() -> void:
	# Connect to collision signals to detect landing
	body_entered.connect(_on_body_entered)

	# Set initial rotation to random for variety
	rotation = randf_range(0, 2 * PI)

	# Set casing appearance based on caliber
	_set_casing_appearance()

	# Connect kick detector signals
	_kick_detector = get_node_or_null("KickDetector")
	if _kick_detector:
		_kick_detector.body_entered.connect(_on_kick_detector_body_entered)
		if debug_logging:
			_log_debug("KickDetector connected, monitoring=%s, mask=%d" % [_kick_detector.monitoring, _kick_detector.collision_mask])
	else:
		if debug_logging:
			_log_debug("WARNING: KickDetector not found!")


## Logs a debug message if debug_logging is enabled.
func _log_debug(message: String) -> void:
	if not debug_logging:
		return
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager and game_manager.has_method("log_to_file"):
		game_manager.log_to_file("[Casing] " + message)
	else:
		print("[Casing] " + message)


func _physics_process(delta: float) -> void:
	# If time is frozen, maintain frozen state (velocity should stay at zero)
	if _is_time_frozen:
		linear_velocity = Vector2.ZERO
		angular_velocity = 0.0
		return

	# Update bounce sound cooldown
	if _bounce_sound_cooldown_timer > 0:
		_bounce_sound_cooldown_timer -= delta

	# Update kick memory timer
	if _kick_memory_timer > 0:
		_kick_memory_timer -= delta
		if _kick_memory_timer <= 0:
			_recently_kicked_by.clear()

	# Update overlap check cooldown
	if _overlap_check_cooldown > 0:
		_overlap_check_cooldown -= delta

	# Handle lifetime if set
	if lifetime > 0:
		_lifetime_timer += delta
		if _lifetime_timer >= lifetime:
			queue_free()
			return

	# Fallback: Manual overlap detection for kick (in case Area2D signals don't work)
	# This is especially important for fast-moving characters in Godot 4
	if _kick_detector and _overlap_check_cooldown <= 0:
		_check_manual_overlaps()

	# Auto-land after a few seconds if not kicked recently
	if not _has_landed and linear_velocity.length() < 10.0:
		_auto_land_timer += delta
		if _auto_land_timer >= AUTO_LAND_TIME:
			_land()
	else:
		# Reset auto-land timer if moving (was kicked)
		_auto_land_timer = 0.0

	# Once landed, stop all movement and rotation
	if _has_landed and linear_velocity.length() < 5.0:
		linear_velocity = Vector2.ZERO
		angular_velocity = 0.0
		# Disable physics processing to save performance
		set_physics_process(false)


## Manual overlap check as fallback for Area2D signal detection.
## This helps with fast-moving characters that might be missed by the signal.
func _check_manual_overlaps() -> void:
	if not _kick_detector:
		return

	var overlapping_bodies: Array[Node2D] = _kick_detector.get_overlapping_bodies()
	for body in overlapping_bodies:
		if body is CharacterBody2D:
			var body_id: int = body.get_instance_id()
			# Skip if we recently kicked by this body
			if body_id in _recently_kicked_by:
				continue
			# Process the kick
			if debug_logging:
				_log_debug("Manual overlap detected: %s" % body.name)
			_process_kick(body)
			# Add to recently kicked list
			_recently_kicked_by.append(body_id)
			_kick_memory_timer = KICK_MEMORY_DURATION
			_overlap_check_cooldown = OVERLAP_CHECK_COOLDOWN


## Makes the casing "land" by stopping all movement.
func _land() -> void:
	_has_landed = true


## Called when a character kicks the casing (Area2D overlap).
func _on_kick_detector_body_entered(body: Node2D) -> void:
	# Only react to CharacterBody2D (player or enemies)
	if not body is CharacterBody2D:
		return

	var body_id: int = body.get_instance_id()
	# Skip if we recently kicked by this body
	if body_id in _recently_kicked_by:
		return

	if debug_logging:
		_log_debug("Signal body_entered: %s" % body.name)

	_process_kick(body)

	# Add to recently kicked list
	_recently_kicked_by.append(body_id)
	_kick_memory_timer = KICK_MEMORY_DURATION


## Processes a kick from a character (player or enemy).
## Called by both signal handler and manual overlap detection.
func _process_kick(body: CharacterBody2D) -> void:
	# Wake up the casing if it was landed
	if _has_landed:
		_has_landed = false
		set_physics_process(true)

	# Calculate kick direction (away from character)
	var kick_direction: Vector2 = (global_position - body.global_position).normalized()
	if kick_direction.length() < 0.1:
		kick_direction = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()

	# Get character velocity for more realistic kick
	var char_velocity: Vector2 = Vector2.ZERO
	if body.has_method("get_velocity"):
		char_velocity = body.get_velocity()
	elif "velocity" in body:
		char_velocity = body.velocity

	# Apply impulse based on character velocity + base kick
	var impulse_strength: float = KICK_FORCE + char_velocity.length() * 0.1
	var impulse: Vector2 = kick_direction * impulse_strength

	# Add some of the character's movement direction
	if char_velocity.length() > 10.0:
		impulse += char_velocity.normalized() * (char_velocity.length() * 0.15)

	apply_central_impulse(impulse)

	# Add some spin for visual interest
	angular_velocity = randf_range(-20.0, 20.0)

	# Play bounce sound if moving fast enough
	_try_play_bounce_sound()

	if debug_logging:
		_log_debug("Kicked by %s with impulse %.1f" % [body.name, impulse.length()])


## Sets the visual appearance of the casing based on its caliber.
func _set_casing_appearance() -> void:
	var sprite = $Sprite2D
	if sprite == null:
		return

	# Try to get the casing sprite from caliber data
	if caliber_data != null and caliber_data is CaliberData:
		var caliber: CaliberData = caliber_data as CaliberData
		if caliber.casing_sprite != null:
			sprite.texture = caliber.casing_sprite
			# Reset modulate to show actual sprite colors
			sprite.modulate = Color.WHITE
			return

	# Fallback: If no sprite in caliber data, use color-based appearance
	# Default color (rifle casing - brass)
	var casing_color = Color(0.9, 0.8, 0.4)  # Brass color

	if caliber_data != null:
		# Check caliber name to determine color
		var caliber_name: String = ""
		if caliber_data is CaliberData:
			caliber_name = (caliber_data as CaliberData).caliber_name
		elif "caliber_name" in caliber_data:
			caliber_name = caliber_data.caliber_name

		if "buckshot" in caliber_name.to_lower() or "Buckshot" in caliber_name:
			casing_color = Color(0.8, 0.2, 0.2)  # Red for shotgun
		elif "9x19" in caliber_name or "9mm" in caliber_name.to_lower():
			casing_color = Color(0.7, 0.7, 0.7)  # Silver for pistol
		# Rifle (5.45x39mm) keeps default brass color

	# Apply the color to the sprite
	sprite.modulate = casing_color


## Called when the casing collides with something (usually the ground).
func _on_body_entered(body: Node2D) -> void:
	# Check velocity for bounce sound on wall collision
	if linear_velocity.length() >= BOUNCE_SOUND_VELOCITY_THRESHOLD:
		_try_play_bounce_sound()

	# Only consider landing if we hit a static body (ground/walls)
	if body is StaticBody2D or body is TileMap:
		# Don't land immediately if moving fast (just bounced off wall)
		if linear_velocity.length() < 20.0:
			_land()


## Attempts to play the bounce sound if cooldown has passed.
func _try_play_bounce_sound() -> void:
	if _bounce_sound_cooldown_timer > 0:
		return
	if linear_velocity.length() < BOUNCE_SOUND_VELOCITY_THRESHOLD:
		return

	_bounce_sound_cooldown_timer = BOUNCE_SOUND_COOLDOWN
	_play_bounce_sound()


## Plays the appropriate shell casing bounce sound based on caliber.
func _play_bounce_sound() -> void:
	var audio_manager = get_node_or_null("/root/AudioManager")
	if audio_manager == null:
		return

	# Determine casing type from caliber for appropriate sound
	var casing_type: String = "rifle"  # Default
	if caliber_data != null:
		var caliber_name: String = ""
		if caliber_data is CaliberData:
			caliber_name = (caliber_data as CaliberData).caliber_name
		elif "caliber_name" in caliber_data:
			caliber_name = caliber_data.caliber_name

		if "buckshot" in caliber_name.to_lower() or "Buckshot" in caliber_name:
			casing_type = "shotgun"
		elif "9x19" in caliber_name or "9mm" in caliber_name.to_lower():
			casing_type = "pistol"

	# Play the shell casing sound
	if audio_manager.has_method("play_shell_casing"):
		audio_manager.play_shell_casing(global_position, casing_type)


## Freezes the casing's movement during time stop effects.
## Called by LastChanceEffectsManager or other time-manipulation systems.
func freeze_time() -> void:
	if _is_time_frozen:
		return

	# Store current velocities to restore later
	_frozen_linear_velocity = linear_velocity
	_frozen_angular_velocity = angular_velocity

	# Stop all movement
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0

	# Mark as frozen
	_is_time_frozen = true


## Unfreezes the casing's movement after time stop effects end.
## Called by LastChanceEffectsManager or other time-manipulation systems.
func unfreeze_time() -> void:
	if not _is_time_frozen:
		return

	# Restore velocities from before the freeze
	linear_velocity = _frozen_linear_velocity
	angular_velocity = _frozen_angular_velocity

	# Clear frozen state
	_is_time_frozen = false
	_frozen_linear_velocity = Vector2.ZERO
	_frozen_angular_velocity = 0.0


## Called when character pushes the casing via physics collision.
## This provides additional push force when characters walk through casings.
func apply_character_push(character_velocity: Vector2, push_direction: Vector2) -> void:
	if _is_time_frozen:
		return

	# Wake up the casing if it was landed
	if _has_landed:
		_has_landed = false
		set_physics_process(true)

	# Apply impulse based on character velocity
	var push_strength: float = character_velocity.length() * 0.2
	push_strength = clampf(push_strength, 20.0, 100.0)
	apply_central_impulse(push_direction * push_strength)

	# Add spin
	angular_velocity = randf_range(-15.0, 15.0)
