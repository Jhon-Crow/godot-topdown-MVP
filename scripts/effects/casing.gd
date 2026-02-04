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

## Time before enabling collision after spawn (to prevent colliding with player at spawn).
## This fixes Issue #392 where casings would push the player at spawn time.
const SPAWN_COLLISION_DELAY: float = 0.1

## Timer for spawn collision delay.
var _spawn_timer: float = 0.0

## Whether collision has been enabled after spawn delay.
var _spawn_collision_enabled: bool = false


## Enable debug logging for casing physics (Issue #392 debugging).
const DEBUG_CASING_PHYSICS: bool = false


func _ready() -> void:
	# Add to casings group for explosion detection (Issue #432)
	add_to_group("casings")

	# Connect to collision signals to detect landing
	body_entered.connect(_on_body_entered)

	# Set initial rotation to random for variety
	rotation = randf_range(0, 2 * PI)

	# Set casing appearance based on caliber
	_set_casing_appearance()

	# Disable collision at spawn to prevent pushing player (Issue #392)
	# Collision will be re-enabled after SPAWN_COLLISION_DELAY seconds
	_disable_collision()

	# NOTE: Collision exception with player has been REMOVED (Issue #392 Iteration 6)
	# The collision layer/mask setup is sufficient:
	# - Player collision_mask = 4 (doesn't include layer 7 where casings are)
	# - Casing collision_layer = 64 (layer 7)
	# - CasingPusher Area2D collision_mask = 64 (detects layer 7)
	# The collision exception was causing issues with casing physics.
	# _add_player_collision_exception()  # DISABLED

	if DEBUG_CASING_PHYSICS:
		print("[Casing] Spawned at %s with velocity %s (speed: %.1f)" % [global_position, linear_velocity, linear_velocity.length()])


func _physics_process(delta: float) -> void:
	# If time is frozen, maintain frozen state (velocity should stay at zero)
	if _is_time_frozen:
		linear_velocity = Vector2.ZERO
		angular_velocity = 0.0
		return

	# Handle spawn collision delay (Issue #392)
	# Enable collision after the casing has moved away from spawn point
	if not _spawn_collision_enabled:
		_spawn_timer += delta
		if _spawn_timer >= SPAWN_COLLISION_DELAY:
			_enable_collision()
			_spawn_collision_enabled = true

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
	# Play landing sound based on caliber type
	_play_landing_sound()


## Plays the appropriate casing landing sound based on caliber type.
func _play_landing_sound() -> void:
	var audio_manager: Node = get_node_or_null("/root/AudioManager")
	if audio_manager == null:
		return

	_play_casing_sound_for_caliber(audio_manager)


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
	if DEBUG_CASING_PHYSICS:
		print("[Casing] receive_kick called with impulse %s (frozen: %s, landed: %s)" % [impulse, _is_time_frozen, _has_landed])

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

	# Play sound based on caliber type for authenticity
	_play_casing_sound_for_caliber(audio_manager)


## Plays the appropriate casing sound based on caliber type.
## @param audio_manager The AudioManager node.
func _play_casing_sound_for_caliber(audio_manager: Node) -> void:
	var caliber_name: String = _get_caliber_name()

	# Determine sound to play based on caliber
	if "buckshot" in caliber_name.to_lower() or "Buckshot" in caliber_name:
		# Shotgun shell casing
		if audio_manager.has_method("play_shell_shotgun"):
			audio_manager.play_shell_shotgun(global_position)
	elif "9x19" in caliber_name or "9mm" in caliber_name.to_lower():
		# Pistol casing
		if audio_manager.has_method("play_shell_pistol"):
			audio_manager.play_shell_pistol(global_position)
	else:
		# Default to rifle casing sound (5.45x39mm and others)
		if audio_manager.has_method("play_shell_rifle"):
			audio_manager.play_shell_rifle(global_position)


## Gets the caliber name from caliber_data.
## @return The caliber name string, or empty string if not available.
func _get_caliber_name() -> String:
	if caliber_data == null:
		return ""

	if caliber_data is CaliberData:
		return (caliber_data as CaliberData).caliber_name

	# Issue #477 Fix: For Resources loaded from C# (like WeaponData.Caliber),
	# we need to access the property correctly. Resources have a get() method
	# that returns the property value, and we should check if the property exists
	# by checking if get() returns a non-null value.
	if caliber_data is Resource:
		var name_value = caliber_data.get("caliber_name")
		if name_value != null and name_value is String:
			return name_value

	return ""


## Disables collision shape to prevent physics interactions.
## Used at spawn time to prevent pushing the player (Issue #392).
func _disable_collision() -> void:
	var collision_shape := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision_shape != null:
		collision_shape.disabled = true


## Enables collision shape after spawn delay.
## Called after SPAWN_COLLISION_DELAY seconds to allow normal physics interactions.
func _enable_collision() -> void:
	var collision_shape := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision_shape != null:
		collision_shape.disabled = false


## Adds collision exception for player to prevent casings from blocking player movement.
## This is a defense-in-depth measure on top of collision layer separation.
## Uses add_collision_exception_with() which makes the casing ignore the player.
## Note: We only add exception in ONE direction (casing ignores player).
## The player's CasingPusher Area2D handles pushing casings without needing physics collision.
## Adding player.add_collision_exception_with(self) would break CasingPusher detection.
func _add_player_collision_exception() -> void:
	# Find player in scene tree (player is in "player" group)
	var players := get_tree().get_nodes_in_group("player")
	if DEBUG_CASING_PHYSICS:
		print("[Casing] Found %d players in 'player' group" % players.size())
	for player in players:
		if player is PhysicsBody2D:
			# Make this casing ignore the player in collision detection
			# This prevents the casing from pushing the player when they overlap
			add_collision_exception_with(player)
			if DEBUG_CASING_PHYSICS:
				print("[Casing] Added collision exception with player: %s" % player.name)
			# NOTE: Do NOT add player.add_collision_exception_with(self)
			# That would break the player's CasingPusher Area2D detection
