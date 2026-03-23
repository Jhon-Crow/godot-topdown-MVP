extends Node
## Dash effect controller (Issue #1071).
##
## Implements a Hyper Light Drifter-style dash for the player.
## When activated via Space key, the player dashes in the current
## movement direction (or facing direction if stationary) at high speed.
## The player is immune to all damage during the dash.
##
## Gameplay rules:
## - Unlimited charges (no charge limit)
## - 1.2 second cooldown between dashes
## - All damage sources are ignored during dash
## - Visual: afterimage trail using modulate flicker

## Duration of the dash in seconds.
const DASH_DURATION: float = 0.15

## Speed multiplier applied during dash (relative to player max_speed).
const DASH_SPEED_MULTIPLIER: float = 4.0

## Cooldown between dashes in seconds.
const DASH_COOLDOWN: float = 1.2

## Number of afterimage ghosts to spawn during dash.
const AFTERIMAGE_COUNT: int = 3

## Afterimage lifetime in seconds.
const AFTERIMAGE_LIFETIME: float = 0.25

## Afterimage initial alpha.
const AFTERIMAGE_ALPHA: float = 0.5

## Whether the dash is currently active (player is mid-dash).
var is_active: bool = false

## Remaining dash duration timer.
var _dash_timer: float = 0.0

## Remaining cooldown timer.
var _cooldown_timer: float = 0.0

## Direction of the current dash.
var _dash_direction: Vector2 = Vector2.ZERO

## Reference to the player node.
var _player: CharacterBody2D = null

## Cached player max_speed for restoring after dash.
var _original_max_speed: float = 300.0

## Timer for spawning afterimages during dash.
var _afterimage_timer: float = 0.0

## Interval between afterimage spawns.
var _afterimage_interval: float = 0.0

## Signal emitted when dash starts.
signal dash_started

## Signal emitted when dash ends.
signal dash_ended

## Signal emitted when cooldown finishes (ready to dash again).
signal cooldown_finished


## Initialize with a reference to the player node.
func initialize(player: CharacterBody2D) -> void:
	_player = player
	_original_max_speed = player.max_speed
	FileLogger.info("[Dash] Initialized with player: %s, cooldown: %.1fs, duration: %.2fs" % [
		player.name, DASH_COOLDOWN, DASH_DURATION
	])


## Attempt to activate the dash.
## @param direction: The direction to dash in (normalized).
## Returns true if dash started successfully.
func activate(direction: Vector2) -> bool:
	if is_active:
		return false  # Already dashing

	if _cooldown_timer > 0.0:
		FileLogger.info("[Dash] On cooldown (%.2fs remaining)" % _cooldown_timer)
		return false

	if direction == Vector2.ZERO:
		# If no movement direction, dash toward mouse cursor
		if _player != null:
			direction = (_player.get_global_mouse_position() - _player.global_position).normalized()
		else:
			return false

	_dash_direction = direction.normalized()
	is_active = true
	_dash_timer = DASH_DURATION
	_afterimage_timer = 0.0
	_afterimage_interval = DASH_DURATION / float(AFTERIMAGE_COUNT) if AFTERIMAGE_COUNT > 0 else DASH_DURATION

	# Apply dash velocity
	if _player != null:
		_player.velocity = _dash_direction * _original_max_speed * DASH_SPEED_MULTIPLIER

	FileLogger.info("[Dash] Activated! Direction: (%.2f, %.2f)" % [_dash_direction.x, _dash_direction.y])
	dash_started.emit()
	return true


## Check if the player is currently dashing (immune to damage).
func is_dashing() -> bool:
	return is_active


## Check if dash is on cooldown.
func is_on_cooldown() -> bool:
	return _cooldown_timer > 0.0


## Get the remaining cooldown time.
func get_cooldown_remaining() -> float:
	return _cooldown_timer


## Get the cooldown progress (0.0 = just started cooldown, 1.0 = ready).
func get_cooldown_progress() -> float:
	if _cooldown_timer <= 0.0:
		return 1.0
	return 1.0 - (_cooldown_timer / DASH_COOLDOWN)


func _physics_process(delta: float) -> void:
	# Update cooldown timer
	if _cooldown_timer > 0.0:
		_cooldown_timer -= delta
		if _cooldown_timer <= 0.0:
			_cooldown_timer = 0.0
			cooldown_finished.emit()

	if not is_active:
		return

	# Update dash timer
	_dash_timer -= delta

	# Spawn afterimages at intervals
	_afterimage_timer += delta
	if _afterimage_timer >= _afterimage_interval:
		_afterimage_timer -= _afterimage_interval
		_spawn_afterimage()

	# Maintain dash velocity (override friction/deceleration)
	if _player != null:
		_player.velocity = _dash_direction * _original_max_speed * DASH_SPEED_MULTIPLIER

	# End dash when timer expires
	if _dash_timer <= 0.0:
		_end_dash()


## End the dash and start cooldown.
func _end_dash() -> void:
	is_active = false
	_dash_timer = 0.0
	_cooldown_timer = DASH_COOLDOWN

	# Reduce velocity smoothly (don't stop abruptly)
	if _player != null:
		_player.velocity = _dash_direction * _original_max_speed * 0.5

	FileLogger.info("[Dash] Ended. Cooldown: %.1fs" % DASH_COOLDOWN)
	dash_ended.emit()


## Spawn an afterimage ghost at the player's current position.
func _spawn_afterimage() -> void:
	if _player == null or not is_instance_valid(_player):
		return

	# Find the PlayerModel to create afterimage from
	var player_model: Node2D = _player.get_node_or_null("PlayerModel")
	if player_model == null:
		return

	# Create a lightweight afterimage using a simple Sprite2D snapshot
	# We duplicate the Body sprite and fade it out
	var body_sprite: Node = player_model.get_node_or_null("Body")
	if body_sprite == null or not (body_sprite is Sprite2D):
		return

	var ghost := Sprite2D.new()
	ghost.texture = (body_sprite as Sprite2D).texture
	ghost.global_position = _player.global_position
	ghost.rotation = player_model.rotation
	ghost.modulate = Color(0.4, 0.7, 1.0, AFTERIMAGE_ALPHA)  # Light blue tint like HLD
	ghost.z_index = _player.z_index - 1

	# Add to scene tree (same parent as player for correct coordinate space)
	var parent: Node = _player.get_parent()
	if parent == null:
		ghost.queue_free()
		return
	parent.add_child(ghost)

	# Fade out and remove afterimage
	var tween := ghost.create_tween()
	tween.tween_property(ghost, "modulate:a", 0.0, AFTERIMAGE_LIFETIME)
	tween.tween_callback(ghost.queue_free)
