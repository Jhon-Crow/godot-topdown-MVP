extends RigidBody2D
## Bullet casing that gets ejected from weapons and falls to the ground.
##
## Casings are spawned when weapons fire, ejected in the opposite direction
## of the shot with some randomness. They fall to the ground and remain there
## as persistent environmental detail.
##
## Casings are now interactive - they can be kicked by players and enemies
## walking through them, with realistic physics and sound effects.

## Lifetime in seconds before auto-destruction (0 = infinite).
@export var lifetime: float = 0.0

## Caliber data for determining casing appearance.
@export var caliber_data: Resource = null

## Whether the casing has landed on the ground.
var _has_landed: bool = false

## Timer for lifetime management.
var _lifetime_timer: float = 0.0

## Timer for automatic landing (since no floor in top-down game).
var _auto_land_timer: float = 0.0

## Time before casing automatically "lands" and stops moving.
const AUTO_LAND_TIME: float = 2.0

## Stores velocity before time freeze (to restore after unfreeze).
var _frozen_linear_velocity: Vector2 = Vector2.ZERO
var _frozen_angular_velocity: float = 0.0

## Whether the casing is currently frozen in time.
var _is_time_frozen: bool = false

## Kick force multiplier when characters walk through.
const KICK_FORCE_MULTIPLIER: float = 0.5

## Minimum velocity to play kick sound (pixels per second).
const KICK_SOUND_VELOCITY_THRESHOLD: float = 75.0

## Cooldown between kick sounds (seconds).
const KICK_SOUND_COOLDOWN: float = 0.1

## Timer tracking cooldown between kick sounds.
var _kick_sound_timer: float = 0.0

## Cached caliber type for sound selection.
var _cached_caliber_type: String = "rifle"


func _ready() -> void:
	# Log casing initialization for debugging crash issues
	var logger = get_node_or_null("/root/FileLogger")
	if logger:
		logger.log_debug("Casing: _ready() starting")

	# Connect to collision signals to detect landing
	body_entered.connect(_on_body_entered)

	# Connect KickDetector Area2D signals
	var kick_detector = get_node_or_null("KickDetector")
	if kick_detector:
		kick_detector.body_entered.connect(_on_kick_detector_body_entered)

	# Set initial rotation to random for variety
	rotation = randf_range(0, 2 * PI)

	# Set casing appearance based on caliber
	_set_casing_appearance()

	# Cache the caliber type for sound selection
	_cached_caliber_type = _determine_caliber_type()

	if logger:
		logger.log_debug("Casing: _ready() completed, caliber_type=%s" % _cached_caliber_type)


func _physics_process(delta: float) -> void:
	# Update kick sound cooldown timer
	if _kick_sound_timer > 0:
		_kick_sound_timer -= delta

	# If time is frozen, maintain frozen state (velocity should stay at zero)
	if _is_time_frozen:
		linear_velocity = Vector2.ZERO
		angular_velocity = 0.0
		return

	# Handle lifetime if set
	if lifetime > 0:
		_lifetime_timer += delta
		if _lifetime_timer >= lifetime:
			queue_free()
			return

	# Auto-land after a few seconds if not landed yet
	if not _has_landed:
		_auto_land_timer += delta
		if _auto_land_timer >= AUTO_LAND_TIME:
			_land()

	# Once landed, stop all movement and rotation
	if _has_landed:
		linear_velocity = Vector2.ZERO
		angular_velocity = 0.0
		# Note: We no longer disable physics processing to allow re-kicking


## Makes the casing "land" by stopping all movement.
func _land() -> void:
	_has_landed = true


## Called when a character enters the KickDetector area.
func _on_kick_detector_body_entered(body: Node2D) -> void:
	# Only respond to CharacterBody2D (players and enemies)
	if body is CharacterBody2D:
		_apply_kick(body)


## Applies kick physics when a character walks through the casing.
func _apply_kick(character: CharacterBody2D) -> void:
	# Don't kick if time is frozen
	if _is_time_frozen:
		return

	# Get character velocity
	var character_velocity: Vector2 = character.velocity

	# Only kick if character is actually moving
	if character_velocity.length_squared() < 100.0:  # ~10 px/s minimum
		return

	# Re-enable movement if landed
	if _has_landed:
		_has_landed = false
		_auto_land_timer = 0.0

	# Calculate kick direction (away from character)
	var kick_direction = (global_position - character.global_position).normalized()

	# Calculate kick force based on character speed
	var kick_speed = character_velocity.length() * KICK_FORCE_MULTIPLIER

	# Add some randomness to the kick direction (±0.3 radians = ~17 degrees)
	kick_direction = kick_direction.rotated(randf_range(-0.3, 0.3))

	# Create the kick force vector
	var kick_force = kick_direction * kick_speed

	# Add random angular velocity for realistic tumbling
	angular_velocity = randf_range(-10.0, 10.0)

	# Apply the impulse to the casing
	apply_central_impulse(kick_force)

	# Play kick sound if above velocity threshold and not in cooldown
	var resulting_velocity = linear_velocity.length()
	if resulting_velocity > KICK_SOUND_VELOCITY_THRESHOLD and _kick_sound_timer <= 0:
		_play_kick_sound()
		_kick_sound_timer = KICK_SOUND_COOLDOWN


## Plays the appropriate kick sound based on caliber type.
func _play_kick_sound() -> void:
	# Check if AudioManager is available
	var audio_manager = get_node_or_null("/root/AudioManager")
	if audio_manager == null:
		return

	# Play sound based on caliber type
	match _cached_caliber_type:
		"pistol":
			audio_manager.play_shell_pistol(global_position)
		"shotgun":
			audio_manager.play_shell_shotgun(global_position)
		_:  # Default to rifle
			audio_manager.play_shell_rifle(global_position)


## Determines the caliber type from caliber_data for sound selection.
func _determine_caliber_type() -> String:
	if caliber_data == null:
		return "rifle"

	# Only use CaliberData type - avoid calling methods on unknown Resource types
	# which can crash exported builds (e.g., .has() only works on Dictionary)
	if not (caliber_data is CaliberData):
		return "rifle"

	var caliber: CaliberData = caliber_data as CaliberData
	var caliber_name: String = caliber.caliber_name

	# Determine type from name
	var name_lower = caliber_name.to_lower()
	if "buckshot" in name_lower or "shotgun" in name_lower:
		return "shotgun"
	elif "9x19" in name_lower or "9mm" in name_lower or "pistol" in name_lower:
		return "pistol"
	else:
		return "rifle"


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

	# Only use CaliberData type for color determination
	# Avoid calling methods on unknown Resource types which can crash exported builds
	if caliber_data != null and caliber_data is CaliberData:
		var caliber: CaliberData = caliber_data as CaliberData
		var caliber_name: String = caliber.caliber_name

		if "buckshot" in caliber_name.to_lower() or "Buckshot" in caliber_name:
			casing_color = Color(0.8, 0.2, 0.2)  # Red for shotgun
		elif "9x19" in caliber_name or "9mm" in caliber_name.to_lower():
			casing_color = Color(0.7, 0.7, 0.7)  # Silver for pistol
		# Rifle (5.45x39mm) keeps default brass color

	# Apply the color to the sprite
	sprite.modulate = casing_color


## Called when the casing collides with something (usually the ground).
func _on_body_entered(body: Node2D) -> void:
	# Only consider landing if we hit a static body (ground/walls)
	if body is StaticBody2D or body is TileMap:
		_land()


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
