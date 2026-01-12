extends CharacterBody2D
## Player character controller for top-down movement and shooting.
##
## Uses physics-based movement with acceleration and friction for smooth control.
## Supports WASD and arrow key input via configured input actions.
## Shoots bullets towards the mouse cursor on left mouse button click.
## Features limited ammunition (30 bullets) with no reload for balanced gameplay.

## Maximum movement speed in pixels per second.
@export var max_speed: float = 200.0

## Acceleration rate - how quickly the player reaches max speed.
@export var acceleration: float = 1200.0

## Friction rate - how quickly the player slows down when not moving.
@export var friction: float = 1000.0

## Bullet scene to instantiate when shooting.
@export var bullet_scene: PackedScene

## Offset from player center for bullet spawn position.
@export var bullet_spawn_offset: float = 20.0

## Maximum ammo capacity (single magazine, no reload).
@export var max_ammo: int = 30

## Current ammo count.
var current_ammo: int = 30

## Signal emitted when ammo changes.
signal ammo_changed(current: int, max_ammo: int)

## Signal emitted when player is out of ammo.
signal out_of_ammo


func _ready() -> void:
	# Initialize ammo
	current_ammo = max_ammo

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

	# Calculate direction towards mouse cursor
	var mouse_pos := get_global_mouse_position()
	var shoot_direction := (mouse_pos - global_position).normalized()

	# Create bullet instance
	var bullet := bullet_scene.instantiate()

	# Set bullet position with offset in shoot direction
	bullet.global_position = global_position + shoot_direction * bullet_spawn_offset

	# Set bullet direction
	bullet.direction = shoot_direction

	# Add bullet to the scene tree (parent's parent to avoid it being a child of player)
	get_tree().current_scene.add_child(bullet)
