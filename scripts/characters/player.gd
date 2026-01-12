extends CharacterBody2D
## Player character controller for top-down movement and shooting.
##
## Uses physics-based movement with acceleration and friction for smooth control.
## Supports WASD and arrow key input via configured input actions.
## Shoots bullets towards the mouse cursor on left mouse button click.
## Features limited ammunition (3 magazines of 30 bullets = 90 total) with no reload for balanced gameplay.

## Maximum movement speed in pixels per second.
## Higher speeds (350+) give a running feel, lower speeds (200) feel like walking.
@export var max_speed: float = 350.0

## Acceleration rate - how quickly the player reaches max speed.
@export var acceleration: float = 2000.0

## Friction rate - how quickly the player slows down when not moving.
@export var friction: float = 1600.0

## Bullet scene to instantiate when shooting.
@export var bullet_scene: PackedScene

## Offset from player center for bullet spawn position.
@export var bullet_spawn_offset: float = 20.0

## Maximum ammo capacity (3 magazines of 30 bullets).
@export var max_ammo: int = 90

## Minimum spread angle in degrees (always applied, even on first shot).
@export var min_spread_degrees: float = 0.5

## Maximum spread angle in degrees (reached after sustained fire).
@export var max_spread_degrees: float = 4.0

## Number of shots before spread starts increasing significantly.
## First N shots have minimal spread (min_spread_degrees).
@export var accurate_shots: int = 3

## How quickly spread increases per shot after accurate_shots threshold.
@export var spread_increase_per_shot: float = 0.6

## Time in seconds without shooting before spread resets.
@export var spread_reset_time: float = 0.25

## Current ammo count.
var current_ammo: int = 90

## Current spread angle in degrees (starts at minimum).
var _current_spread: float = 0.5

## Number of consecutive shots fired in current burst.
var _burst_shot_count: int = 0

## Time since last shot (for spread reset).
var _time_since_last_shot: float = 999.0

## Signal emitted when ammo changes.
signal ammo_changed(current: int, max_ammo: int)

## Signal emitted when player is out of ammo.
signal out_of_ammo


func _ready() -> void:
	# Initialize ammo
	current_ammo = max_ammo

	# Initialize spread
	_current_spread = min_spread_degrees
	_burst_shot_count = 0

	# Preload bullet scene if not set in inspector
	if bullet_scene == null:
		bullet_scene = preload("res://scenes/projectiles/Bullet.tscn")

	# Emit initial ammo signal
	ammo_changed.emit(current_ammo, max_ammo)


func _physics_process(delta: float) -> void:
	var input_direction := _get_input_direction()

	if input_direction != Vector2.ZERO:
		# Apply acceleration towards the input direction
		velocity = velocity.move_toward(input_direction * max_speed, acceleration * delta)
	else:
		# Apply friction to slow down
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)

	move_and_slide()

	# Update spread reset timer
	_time_since_last_shot += delta
	if _time_since_last_shot >= spread_reset_time:
		# Reset spread after not shooting for a while
		_burst_shot_count = 0
		_current_spread = min_spread_degrees

	# Handle shooting input
	if Input.is_action_just_pressed("shoot"):
		_shoot()


func _get_input_direction() -> Vector2:
	var direction := Vector2.ZERO
	direction.x = Input.get_axis("move_left", "move_right")
	direction.y = Input.get_axis("move_up", "move_down")

	# Normalize to prevent faster diagonal movement
	if direction.length() > 1.0:
		direction = direction.normalized()

	return direction


func _shoot() -> void:
	if bullet_scene == null:
		return

	# Check if player has ammo
	if current_ammo <= 0:
		out_of_ammo.emit()
		return

	# Consume ammo
	current_ammo -= 1
	ammo_changed.emit(current_ammo, max_ammo)

	# Update burst counter and spread
	_burst_shot_count += 1
	_time_since_last_shot = 0.0
	_update_spread()

	# Calculate direction towards mouse cursor
	var mouse_pos := get_global_mouse_position()
	var shoot_direction := (mouse_pos - global_position).normalized()

	# Apply spread (random angle offset)
	var spread_radians := deg_to_rad(_current_spread)
	var random_spread := randf_range(-spread_radians, spread_radians)
	shoot_direction = shoot_direction.rotated(random_spread)

	# Create bullet instance
	var bullet := bullet_scene.instantiate()

	# Set bullet position with offset in shoot direction
	bullet.global_position = global_position + shoot_direction * bullet_spawn_offset

	# Set bullet direction
	bullet.direction = shoot_direction

	# Add bullet to the scene tree (parent's parent to avoid it being a child of player)
	get_tree().current_scene.add_child(bullet)


## Updates the current spread based on burst shot count.
## First few shots (accurate_shots) have minimal spread, then it increases.
func _update_spread() -> void:
	if _burst_shot_count <= accurate_shots:
		# First N shots have minimal spread
		_current_spread = min_spread_degrees
	else:
		# Spread increases for each shot after the accurate threshold
		var extra_shots := _burst_shot_count - accurate_shots
		_current_spread = min_spread_degrees + (extra_shots * spread_increase_per_shot)
		_current_spread = minf(_current_spread, max_spread_degrees)
