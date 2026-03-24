extends Node
## Dash effect controller (Issue #1071).
##
## Implements a Hyper Light Drifter-style dash for the player.
## When activated via Space key, the player dashes in the current
## movement direction (or facing direction if stationary) at high speed.
## The player is immune to all damage during the dash.
##
## Gameplay rules:
## - 3 charges (chain-dashes allowed)
## - Cooldown starts only after the 3rd (last) charge is used
## - All damage sources are ignored during dash
## - Visual: HLD-style afterimage trail with multiple ghost sprites

## Duration of a single dash in seconds.
const DASH_DURATION: float = 0.15

## Speed multiplier applied during dash (relative to player max_speed).
const DASH_SPEED_MULTIPLIER: float = 4.0

## Cooldown after all charges are spent, in seconds.
const DASH_COOLDOWN: float = 1.2

## Maximum number of dash charges.
const MAX_CHARGES: int = 3

## Number of afterimage ghosts to spawn per dash (not counting the immediate first one).
const AFTERIMAGE_COUNT: int = 4

## Afterimage lifetime in seconds.
const AFTERIMAGE_LIFETIME: float = 0.4

## Afterimage initial alpha.
const AFTERIMAGE_ALPHA: float = 0.7

## Time window after a dash ends to chain the next dash (seconds).
## If the player doesn't dash within this window, remaining charges are forfeited
## and cooldown begins.
const CHAIN_WINDOW: float = 0.4

## Whether the dash is currently active (player is mid-dash).
var is_active: bool = false

## Current remaining charges.
var charges: int = MAX_CHARGES

## Remaining dash duration timer.
var _dash_timer: float = 0.0

## Remaining cooldown timer (only active after all charges spent or chain window expires).
var _cooldown_timer: float = 0.0

## Chain window timer — counts down after a dash ends. If it hits 0 with charges
## remaining, the remaining charges are forfeited and full cooldown begins.
var _chain_timer: float = 0.0

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

## Signal emitted when cooldown finishes (all charges restored).
signal cooldown_finished

## Signal emitted when charges change (for UI progress bar).
signal charges_changed(current: int, maximum: int)


## Initialize with a reference to the player node.
func initialize(player: CharacterBody2D) -> void:
	_player = player
	_original_max_speed = player.max_speed
	charges = MAX_CHARGES
	FileLogger.info("[Dash] Initialized with player: %s, %d charges, cooldown: %.1fs, duration: %.2fs" % [
		player.name, MAX_CHARGES, DASH_COOLDOWN, DASH_DURATION
	])


## Attempt to activate the dash.
## @param direction: The direction to dash in (normalized).
## Returns true if dash started successfully.
func activate(direction: Vector2) -> bool:
	if is_active:
		return false  # Already mid-dash

	if charges <= 0:
		if _cooldown_timer > 0.0:
			FileLogger.info("[Dash] No charges, on cooldown (%.2fs remaining)" % _cooldown_timer)
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
	_chain_timer = 0.0  # Reset chain timer while dashing
	_afterimage_timer = 0.0
	_afterimage_interval = DASH_DURATION / float(AFTERIMAGE_COUNT) if AFTERIMAGE_COUNT > 0 else DASH_DURATION

	# Consume one charge
	charges -= 1
	charges_changed.emit(charges, MAX_CHARGES)

	# Apply dash velocity
	if _player != null:
		_player.velocity = _dash_direction * _original_max_speed * DASH_SPEED_MULTIPLIER

	FileLogger.info("[Dash] Activated! Dir: (%.2f, %.2f), charges left: %d/%d" % [
		_dash_direction.x, _dash_direction.y, charges, MAX_CHARGES
	])
	dash_started.emit()

	# Spawn the first afterimage immediately so the trail starts at the dash origin
	_spawn_afterimage()

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


## Get current charges.
func get_charges() -> int:
	return charges


## Get maximum charges.
func get_max_charges() -> int:
	return MAX_CHARGES


func _physics_process(delta: float) -> void:
	# Update cooldown timer
	if _cooldown_timer > 0.0:
		_cooldown_timer -= delta
		if _cooldown_timer <= 0.0:
			_cooldown_timer = 0.0
			charges = MAX_CHARGES
			charges_changed.emit(charges, MAX_CHARGES)
			FileLogger.info("[Dash] Cooldown finished, charges restored: %d/%d" % [charges, MAX_CHARGES])
			cooldown_finished.emit()

	# Update chain window timer (only when not dashing and charges remain)
	if not is_active and _chain_timer > 0.0:
		_chain_timer -= delta
		if _chain_timer <= 0.0:
			_chain_timer = 0.0
			# Chain window expired with unused charges — start cooldown
			if charges > 0 and charges < MAX_CHARGES:
				FileLogger.info("[Dash] Chain window expired with %d charges left, starting cooldown" % charges)
				charges = 0
				charges_changed.emit(charges, MAX_CHARGES)
			if charges <= 0 and _cooldown_timer <= 0.0:
				_cooldown_timer = DASH_COOLDOWN
				FileLogger.info("[Dash] Full cooldown started: %.1fs" % DASH_COOLDOWN)

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


## End the dash and start cooldown or chain window.
func _end_dash() -> void:
	is_active = false
	_dash_timer = 0.0

	# Reduce velocity smoothly (don't stop abruptly)
	if _player != null:
		_player.velocity = _dash_direction * _original_max_speed * 0.5

	if charges <= 0:
		# All charges spent — start cooldown immediately
		_cooldown_timer = DASH_COOLDOWN
		FileLogger.info("[Dash] Ended (all charges spent). Cooldown: %.1fs" % DASH_COOLDOWN)
	else:
		# Charges remain — open chain window for next dash
		_chain_timer = CHAIN_WINDOW
		FileLogger.info("[Dash] Ended. %d charges left, chain window: %.1fs" % [charges, CHAIN_WINDOW])

	dash_ended.emit()


## Spawn an afterimage ghost at the player's current position.
## Creates an HLD-style trail with body + arms sprite copies.
func _spawn_afterimage() -> void:
	if _player == null or not is_instance_valid(_player):
		return

	# Find the PlayerModel to create afterimage from
	var player_model: Node2D = _player.get_node_or_null("PlayerModel")
	if player_model == null:
		FileLogger.info("[Dash] Afterimage skipped: PlayerModel not found on %s" % _player.name)
		return

	# Create a container node for the full player afterimage
	var ghost_container := Node2D.new()
	ghost_container.global_position = _player.global_position
	# Same z_index as the player so afterimages render on the same layer (not hidden behind floor)
	ghost_container.z_index = _player.z_index

	# Copy all visible Sprite2D children from PlayerModel (Body, LeftArm, RightArm, etc.)
	var sprites_added: int = 0
	for child in player_model.get_children():
		if child is Sprite2D and child.visible:
			var ghost_sprite := Sprite2D.new()
			ghost_sprite.texture = child.texture
			ghost_sprite.position = child.position
			ghost_sprite.rotation = child.rotation
			ghost_sprite.scale = child.scale
			ghost_sprite.flip_h = child.flip_h
			ghost_sprite.flip_v = child.flip_v
			ghost_sprite.offset = child.offset
			ghost_sprite.hframes = child.hframes
			ghost_sprite.vframes = child.vframes
			ghost_sprite.frame = child.frame
			ghost_sprite.region_enabled = child.region_enabled
			if child.region_enabled:
				ghost_sprite.region_rect = child.region_rect
			ghost_container.add_child(ghost_sprite)
			sprites_added += 1

	if sprites_added == 0:
		FileLogger.info("[Dash] Afterimage skipped: no visible Sprite2D in PlayerModel (children: %d)" % player_model.get_child_count())
		ghost_container.queue_free()
		return

	# Apply rotation from player model
	ghost_container.rotation = player_model.global_rotation

	# Cyan-blue tint like HLD dash trail
	ghost_container.modulate = Color(0.3, 0.6, 1.0, AFTERIMAGE_ALPHA)

	# Add to scene tree (same parent as player for correct coordinate space)
	var parent: Node = _player.get_parent()
	if parent == null:
		ghost_container.queue_free()
		return
	parent.add_child(ghost_container)

	FileLogger.info("[Dash] Afterimage spawned at (%.1f, %.1f) with %d sprites, z_index=%d" % [
		ghost_container.global_position.x, ghost_container.global_position.y,
		sprites_added, ghost_container.z_index
	])

	# Fade out and remove afterimage
	var tween := ghost_container.create_tween()
	tween.tween_property(ghost_container, "modulate:a", 0.0, AFTERIMAGE_LIFETIME)
	tween.tween_callback(ghost_container.queue_free)
