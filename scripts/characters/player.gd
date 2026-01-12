extends CharacterBody2D
## Player character controller for top-down movement and shooting.
##
## Uses physics-based movement with acceleration and friction for smooth control.
## Supports WASD and arrow key input via configured input actions.
## Shoots bullets towards the mouse cursor on left mouse button click.
## Features limited ammunition system with progressive spread.
## Includes health system for taking damage from enemy projectiles.

## Maximum movement speed in pixels per second.
@export var max_speed: float = 300.0

## Acceleration rate - how quickly the player reaches max speed.
@export var acceleration: float = 1200.0

## Friction rate - how quickly the player slows down when not moving.
@export var friction: float = 1000.0

## Bullet scene to instantiate when shooting.
@export var bullet_scene: PackedScene

## Offset from player center for bullet spawn position.
@export var bullet_spawn_offset: float = 20.0

## Maximum ammunition (90 bullets = 3 magazines of 30).
@export var max_ammo: int = 90

## Maximum health of the player.
@export var max_health: int = 5

## Reload mode: simple (press R once) or sequence (R-F-R).
@export_enum("Simple", "Sequence") var reload_mode: int = 1  # Default to Sequence mode

## Time to reload in seconds (only used in Simple mode).
@export var reload_time: float = 1.5

## Color when at full health.
@export var full_health_color: Color = Color(0.2, 0.6, 1.0, 1.0)

## Color when at low health (interpolates based on health percentage).
@export var low_health_color: Color = Color(0.1, 0.2, 0.4, 1.0)

## Color to flash when hit.
@export var hit_flash_color: Color = Color(1.0, 1.0, 1.0, 1.0)

## Duration of hit flash effect in seconds.
@export var hit_flash_duration: float = 0.1

## Current ammunition count.
var _current_ammo: int = 90

## Current health of the player.
var _current_health: int = 5

## Whether the player is alive.
var _is_alive: bool = true

## Reference to the sprite for color changes.
@onready var _sprite: Sprite2D = $Sprite2D

## Progressive spread system parameters.
## Number of shots before spread starts increasing.
const SPREAD_THRESHOLD: int = 3
## Initial minimal spread in degrees.
const INITIAL_SPREAD: float = 0.5
## Spread increase per shot after threshold (degrees).
const SPREAD_INCREMENT: float = 0.6
## Maximum spread in degrees.
const MAX_SPREAD: float = 4.0
## Time in seconds for spread to reset after stopping fire.
const SPREAD_RESET_TIME: float = 0.25

## Current number of consecutive shots.
var _shot_count: int = 0
## Timer since last shot.
var _shot_timer: float = 0.0

## Reload sequence state (0 = waiting for R, 1 = waiting for F, 2 = waiting for R).
var _reload_sequence_step: int = 0

## Whether the player is currently in reload sequence (for Sequence mode).
var _is_reloading_sequence: bool = false

## Whether the player is currently reloading (for Simple mode).
var _is_reloading_simple: bool = false

## Timer for simple reload progress.
var _reload_timer: float = 0.0

## Signal emitted when ammo changes.
signal ammo_changed(current: int, maximum: int)

## Signal emitted when ammo is depleted.
signal ammo_depleted

## Signal emitted when the player is hit.
signal hit

## Signal emitted when health changes.
signal health_changed(current: int, maximum: int)

## Signal emitted when the player dies.
signal died

## Signal emitted when reload sequence progresses.
signal reload_sequence_progress(step: int, total: int)

## Signal emitted when reload completes.
signal reload_completed


func _ready() -> void:
	# Preload bullet scene if not set in inspector
	if bullet_scene == null:
		bullet_scene = preload("res://scenes/projectiles/Bullet.tscn")
	_current_ammo = max_ammo
	_current_health = max_health
	_is_alive = true
	_update_health_visual()


func _physics_process(delta: float) -> void:
	if not _is_alive:
		return

	var input_direction := _get_input_direction()

	if input_direction != Vector2.ZERO:
		# Apply acceleration towards the input direction
		velocity = velocity.move_toward(input_direction * max_speed, acceleration * delta)
	else:
		# Apply friction to slow down
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)

	move_and_slide()

	# Update spread reset timer
	_shot_timer += delta
	if _shot_timer >= SPREAD_RESET_TIME:
		_shot_count = 0

	# Update simple reload timer
	if _is_reloading_simple:
		_reload_timer += delta
		if _reload_timer >= reload_time:
			_complete_simple_reload()

	# Handle shooting input
	if Input.is_action_just_pressed("shoot"):
		_shoot()

	# Handle reload input based on mode
	if reload_mode == 0:  # Simple mode
		_handle_simple_reload_input()
	else:  # Sequence mode
		_handle_sequence_reload_input()


func _get_input_direction() -> Vector2:
	var direction := Vector2.ZERO
	direction.x = Input.get_axis("move_left", "move_right")
	direction.y = Input.get_axis("move_up", "move_down")

	# Normalize to prevent faster diagonal movement
	if direction.length() > 1.0:
		direction = direction.normalized()

	return direction


## Calculate current spread based on consecutive shots.
func _get_current_spread() -> float:
	if _shot_count <= SPREAD_THRESHOLD:
		return INITIAL_SPREAD
	else:
		var extra_shots := _shot_count - SPREAD_THRESHOLD
		var spread := INITIAL_SPREAD + extra_shots * SPREAD_INCREMENT
		return minf(spread, MAX_SPREAD)


func _shoot() -> void:
	if bullet_scene == null:
		return

	# Check ammo
	if _current_ammo <= 0:
		# Play empty click sound
		var audio_manager: Node = get_node_or_null("/root/AudioManager")
		if audio_manager and audio_manager.has_method("play_empty_click"):
			audio_manager.play_empty_click(global_position)
		ammo_depleted.emit()
		return

	# Calculate direction towards mouse cursor
	var mouse_pos := get_global_mouse_position()
	var shoot_direction := (mouse_pos - global_position).normalized()

	# Apply spread
	var spread := _get_current_spread()
	var spread_radians := deg_to_rad(spread)
	var random_spread := randf_range(-spread_radians, spread_radians)
	shoot_direction = shoot_direction.rotated(random_spread)

	# Create bullet instance
	var bullet := bullet_scene.instantiate()

	# Set bullet position with offset in shoot direction
	bullet.global_position = global_position + shoot_direction * bullet_spawn_offset

	# Set bullet direction
	bullet.direction = shoot_direction

	# Set shooter ID to identify this player as the source
	# This prevents the player from being hit by their own bullets
	bullet.shooter_id = get_instance_id()

	# Add bullet to the scene tree (parent's parent to avoid it being a child of player)
	get_tree().current_scene.add_child(bullet)

	# Play shooting sound
	var audio_manager: Node = get_node_or_null("/root/AudioManager")
	if audio_manager and audio_manager.has_method("play_m16_shot"):
		audio_manager.play_m16_shot(global_position)

	# Play shell casing sound with a small delay
	if audio_manager and audio_manager.has_method("play_shell_rifle"):
		_play_delayed_shell_sound()

	# Update ammo and shot count
	_current_ammo -= 1
	_shot_count += 1
	_shot_timer = 0.0
	ammo_changed.emit(_current_ammo, max_ammo)


## Play shell casing sound with a delay to simulate the casing hitting the ground.
func _play_delayed_shell_sound() -> void:
	await get_tree().create_timer(0.15).timeout
	var audio_manager: Node = get_node_or_null("/root/AudioManager")
	if audio_manager and audio_manager.has_method("play_shell_rifle"):
		audio_manager.play_shell_rifle(global_position)


## Get current ammo count.
func get_current_ammo() -> int:
	return _current_ammo


## Get maximum ammo count.
func get_max_ammo() -> int:
	return max_ammo


## Handle simple reload input (just press R once).
## Reload takes reload_time seconds to complete.
func _handle_simple_reload_input() -> void:
	# Don't start reload if already reloading or at max ammo
	if _is_reloading_simple or _current_ammo >= max_ammo:
		return

	if Input.is_action_just_pressed("reload"):
		_is_reloading_simple = true
		_reload_timer = 0.0
		# Play full reload sound for simple mode
		var audio_manager: Node = get_node_or_null("/root/AudioManager")
		if audio_manager and audio_manager.has_method("play_reload_full"):
			audio_manager.play_reload_full(global_position)
		reload_sequence_progress.emit(1, 1)


## Complete the simple reload.
func _complete_simple_reload() -> void:
	_current_ammo = max_ammo
	_is_reloading_simple = false
	_reload_timer = 0.0
	ammo_changed.emit(_current_ammo, max_ammo)
	reload_completed.emit()


## Handle reload sequence input (R-F-R).
## Player must press R, then F, then R again to complete reload.
## Reload happens instantly once sequence is completed.
func _handle_sequence_reload_input() -> void:
	# Don't process reload if already at max ammo
	if _current_ammo >= max_ammo:
		_reload_sequence_step = 0
		_is_reloading_sequence = false
		return

	var audio_manager: Node = get_node_or_null("/root/AudioManager")

	match _reload_sequence_step:
		0:
			# Waiting for first R press
			if Input.is_action_just_pressed("reload"):
				_reload_sequence_step = 1
				_is_reloading_sequence = true
				# Play magazine out sound
				if audio_manager and audio_manager.has_method("play_reload_mag_out"):
					audio_manager.play_reload_mag_out(global_position)
				reload_sequence_progress.emit(1, 3)
		1:
			# Waiting for F press
			if Input.is_action_just_pressed("reload_step"):
				_reload_sequence_step = 2
				# Play magazine in sound
				if audio_manager and audio_manager.has_method("play_reload_mag_in"):
					audio_manager.play_reload_mag_in(global_position)
				reload_sequence_progress.emit(2, 3)
			elif Input.is_action_just_pressed("reload"):
				# R pressed again - restart sequence with mag out sound
				_reload_sequence_step = 1
				if audio_manager and audio_manager.has_method("play_reload_mag_out"):
					audio_manager.play_reload_mag_out(global_position)
				reload_sequence_progress.emit(1, 3)
		2:
			# Waiting for final R press
			if Input.is_action_just_pressed("reload"):
				# Play bolt cycling sound and complete reload
				if audio_manager and audio_manager.has_method("play_m16_bolt"):
					audio_manager.play_m16_bolt(global_position)
				_complete_reload()
			elif Input.is_action_just_pressed("reload_step"):
				# Wrong key pressed, reset sequence
				_reload_sequence_step = 1
				if audio_manager and audio_manager.has_method("play_reload_mag_out"):
					audio_manager.play_reload_mag_out(global_position)
				reload_sequence_progress.emit(1, 3)


## Complete the reload - instantly refill ammo.
func _complete_reload() -> void:
	_current_ammo = max_ammo
	_reload_sequence_step = 0
	_is_reloading_sequence = false
	ammo_changed.emit(_current_ammo, max_ammo)
	reload_completed.emit()
	reload_sequence_progress.emit(3, 3)


## Check if player is currently reloading (either mode).
func is_reloading() -> bool:
	return _is_reloading_sequence or _is_reloading_simple


## Get current reload sequence step (0-2).
func get_reload_step() -> int:
	return _reload_sequence_step


## Cancel the reload (both modes) and reset.
func cancel_reload() -> void:
	_reload_sequence_step = 0
	_is_reloading_sequence = false
	_is_reloading_simple = false
	_reload_timer = 0.0


## Called when hit by a projectile.
func on_hit() -> void:
	if not _is_alive:
		return

	hit.emit()

	# Show hit flash effect
	_show_hit_flash()

	# Apply damage
	_current_health -= 1
	health_changed.emit(_current_health, max_health)

	# Play appropriate hit sound
	var audio_manager: Node = get_node_or_null("/root/AudioManager")
	if _current_health <= 0:
		# Play lethal hit sound
		if audio_manager and audio_manager.has_method("play_hit_lethal"):
			audio_manager.play_hit_lethal(global_position)
		_on_death()
	else:
		# Play non-lethal hit sound
		if audio_manager and audio_manager.has_method("play_hit_non_lethal"):
			audio_manager.play_hit_non_lethal(global_position)
		_update_health_visual()


## Shows a brief flash effect when hit.
func _show_hit_flash() -> void:
	if not _sprite:
		return

	_sprite.modulate = hit_flash_color

	await get_tree().create_timer(hit_flash_duration).timeout

	# Restore color based on current health (if still alive)
	if _is_alive:
		_update_health_visual()


## Updates the sprite color based on current health percentage.
func _update_health_visual() -> void:
	if not _sprite:
		return

	# Interpolate color based on health percentage
	var health_percent := _get_health_percent()
	_sprite.modulate = full_health_color.lerp(low_health_color, 1.0 - health_percent)


## Returns the current health as a percentage (0.0 to 1.0).
func _get_health_percent() -> float:
	if max_health <= 0:
		return 0.0
	return float(_current_health) / float(max_health)


## Called when the player dies.
func _on_death() -> void:
	_is_alive = false
	died.emit()
	# Visual feedback - make sprite darker/transparent
	if _sprite:
		_sprite.modulate = Color(0.3, 0.3, 0.3, 0.5)


## Get current health.
func get_current_health() -> int:
	return _current_health


## Get maximum health.
func get_max_health() -> int:
	return max_health


## Check if player is alive.
func is_alive() -> bool:
	return _is_alive
