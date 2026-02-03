extends RigidBody2D
## Bullet casing that gets ejected from weapons and falls to the ground.
##
## Casings are spawned when weapons fire, ejected in the opposite direction
## of the shot with some randomness. They fall to the ground and remain there
## permanently as persistent environmental detail.

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


func _ready() -> void:
	# Connect to collision signals to detect landing
	body_entered.connect(_on_body_entered)

	# Set initial rotation to random for variety
	rotation = randf_range(0, 2 * PI)

	# Set casing appearance based on caliber
	_set_casing_appearance()


func _physics_process(delta: float) -> void:
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
		# Disable physics processing to save performance
		set_physics_process(false)


## Makes the casing "land" by stopping all movement.
func _land() -> void:
	_has_landed = true


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
		elif caliber_data.has_method("get"):
			caliber_name = caliber_data.get("caliber_name") if caliber_data.has("caliber_name") else ""

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


## Receives a kick impulse from a character (player or enemy) walking into this casing.
## Called by BaseCharacter after MoveAndSlide() detects collision with the casing.
## @param impulse The kick impulse vector (direction * force).
func receive_kick(impulse: Vector2) -> void:
	if _is_time_frozen:
		return

	# Re-enable physics if casing was landed
	if _has_landed:
		_has_landed = false
		_auto_land_timer = 0.0
		set_physics_process(true)

	# Apply the kick impulse
	apply_central_impulse(impulse)

	# Add random spin for realism
	angular_velocity = randf_range(-15.0, 15.0)

	# Play kick sound if impulse is strong enough
	_play_kick_sound(impulse.length())


## Minimum impulse strength to play kick sound.
const MIN_KICK_SOUND_IMPULSE: float = 5.0

## Plays the casing kick sound if impulse is above threshold.
## @param impulse_strength The magnitude of the kick impulse.
func _play_kick_sound(impulse_strength: float) -> void:
	if impulse_strength < MIN_KICK_SOUND_IMPULSE:
		return

	var audio_manager: Node = get_node_or_null("/root/AudioManager")
	if audio_manager == null:
		return

	# Use the shell rifle sound for casing kicks (similar metallic clink)
	if audio_manager.has_method("play_shell_rifle"):
		audio_manager.play_shell_rifle(global_position)