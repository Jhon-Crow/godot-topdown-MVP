extends Node
## Autoload singleton for managing screen/camera shake effects.
##
## Provides directional screen shake that accumulates with each shot and recovers
## smoothly based on spread settings. The shake direction is opposite to the
## shooting direction to simulate recoil effect.
##
## Usage:
##   ScreenShakeManager.add_shake(shooting_direction, intensity, recovery_time)

## Current accumulated shake offset (in pixels).
var _shake_offset: Vector2 = Vector2.ZERO

## Current recovery speed (pixels per second).
var _current_recovery_speed: float = 100.0

## Reference to the player's camera (cached for performance).
var _player_camera: Camera2D = null

## Whether screen shake is enabled globally.
var enabled: bool = true

## Minimum recovery time in seconds (50ms as per specification).
const MIN_RECOVERY_TIME: float = 0.05

## Maximum accumulated shake offset to prevent extreme values.
const MAX_SHAKE_OFFSET: float = 50.0


func _ready() -> void:
	# Connect to scene tree changes to reset camera reference on scene reload
	get_tree().tree_changed.connect(_on_tree_changed)


func _process(delta: float) -> void:
	if not enabled or _shake_offset == Vector2.ZERO:
		return

	# Recover shake offset towards zero
	var recovery_amount := _current_recovery_speed * delta
	var current_length := _shake_offset.length()

	if current_length <= recovery_amount:
		# Fully recovered
		_shake_offset = Vector2.ZERO
		_apply_camera_offset(Vector2.ZERO)
	else:
		# Partially recover - move towards zero while maintaining direction
		var recovery_direction := -_shake_offset.normalized()
		_shake_offset += recovery_direction * recovery_amount
		_apply_camera_offset(_shake_offset)


## Adds shake to the current accumulated offset.
## @param shooting_direction: The direction the bullet is traveling (normalized).
## @param intensity: The shake intensity in pixels.
## @param recovery_time: Time in seconds for full recovery (min 50ms).
func add_shake(shooting_direction: Vector2, intensity: float, recovery_time: float) -> void:
	if not enabled or intensity <= 0.0:
		return

	# Shake direction is opposite to shooting direction (recoil effect)
	var shake_direction := -shooting_direction.normalized()

	# Add to accumulated offset
	_shake_offset += shake_direction * intensity

	# Clamp to maximum to prevent extreme values
	if _shake_offset.length() > MAX_SHAKE_OFFSET:
		_shake_offset = _shake_offset.normalized() * MAX_SHAKE_OFFSET

	# Calculate recovery speed based on recovery time
	# Ensure minimum 50ms recovery time
	var clamped_recovery_time := maxf(recovery_time, MIN_RECOVERY_TIME)
	var current_shake_distance := _shake_offset.length()
	_current_recovery_speed = current_shake_distance / clamped_recovery_time

	# Apply immediately
	_apply_camera_offset(_shake_offset)


## Calculates shake intensity based on weapon fire rate.
## Lower fire rate = larger shake per shot.
## @param base_intensity: The base shake intensity from weapon data.
## @param fire_rate: Shots per second.
## @return: Calculated shake intensity per shot.
static func calculate_shake_intensity(base_intensity: float, fire_rate: float) -> float:
	if fire_rate <= 0.0:
		return base_intensity

	# Formula: base_intensity / fire_rate * 10
	# This means a weapon firing at 10 shots/sec gets base_intensity
	# A weapon firing at 5 shots/sec gets 2x base_intensity per shot
	# A weapon firing at 20 shots/sec gets 0.5x base_intensity per shot
	return base_intensity / fire_rate * 10.0


## Calculates recovery time based on current spread ratio.
## @param spread_ratio: Value from 0.0 (min spread) to 1.0 (max spread).
## @param min_recovery: Recovery time at minimum spread (slower).
## @param max_recovery: Recovery time at maximum spread (faster, min 50ms).
## @return: Interpolated recovery time clamped to minimum 50ms.
static func calculate_recovery_time(spread_ratio: float, min_recovery: float, max_recovery: float) -> float:
	# Clamp max_recovery to minimum 50ms as per specification
	var clamped_max := maxf(max_recovery, MIN_RECOVERY_TIME)
	# Interpolate between min and max based on spread ratio
	# At min spread (0.0) -> slower recovery (min_recovery)
	# At max spread (1.0) -> faster recovery (max_recovery)
	return lerpf(min_recovery, clamped_max, spread_ratio)


## Applies the shake offset to the player's camera.
func _apply_camera_offset(offset: Vector2) -> void:
	var camera := _get_player_camera()
	if camera:
		camera.offset = offset


## Gets and caches the player's Camera2D.
func _get_player_camera() -> Camera2D:
	# Return cached camera if still valid
	if is_instance_valid(_player_camera):
		return _player_camera

	# Find player and get their camera
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		var player := players[0]
		_player_camera = player.get_node_or_null("Camera2D") as Camera2D

	return _player_camera


## Resets the shake effect immediately.
func reset_shake() -> void:
	_shake_offset = Vector2.ZERO
	_apply_camera_offset(Vector2.ZERO)


## Tracks the previous scene root to detect scene changes.
var _previous_scene_root: Node = null


## Called when the scene tree structure changes.
## Used to reset shake and camera reference when a new scene is loaded.
func _on_tree_changed() -> void:
	var current_scene := get_tree().current_scene
	if current_scene != null and current_scene != _previous_scene_root:
		_previous_scene_root = current_scene
		_player_camera = null
		reset_shake()
