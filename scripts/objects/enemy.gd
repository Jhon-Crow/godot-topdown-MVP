extends CharacterBody2D
## Enemy AI that can patrol, guard, and shoot at the player.
##
## Supports two idle behaviors:
## - PATROL: Moves between patrol points
## - GUARD: Stands in place watching for the player
##
## When the player is in line of sight, the enemy will shoot at them.

## Behavior modes for the enemy.
enum BehaviorMode {
	PATROL,  ## Moves between patrol points
	GUARD    ## Stands in one place
}

## Current behavior mode.
@export var behavior_mode: BehaviorMode = BehaviorMode.GUARD

## Maximum movement speed in pixels per second (for patrolling).
@export var move_speed: float = 80.0

## Detection range for spotting the player.
@export var detection_range: float = 400.0

## Time between shots in seconds.
@export var shoot_cooldown: float = 1.0

## Bullet scene to instantiate when shooting.
@export var bullet_scene: PackedScene

## Offset from enemy center for bullet spawn position.
@export var bullet_spawn_offset: float = 30.0

## Patrol points as offsets from the initial position.
## Only used when behavior_mode is PATROL.
@export var patrol_offsets: Array[Vector2] = [Vector2(100, 0), Vector2(-100, 0)]

## Wait time at each patrol point in seconds.
@export var patrol_wait_time: float = 1.5

## Color when at full health.
@export var full_health_color: Color = Color(0.9, 0.2, 0.2, 1.0)

## Color when at low health (interpolates based on health percentage).
@export var low_health_color: Color = Color(0.3, 0.1, 0.1, 1.0)

## Color to flash when hit.
@export var hit_flash_color: Color = Color(1.0, 1.0, 1.0, 1.0)

## Duration of hit flash effect in seconds.
@export var hit_flash_duration: float = 0.1

## Whether to destroy the enemy after death.
@export var destroy_on_death: bool = false

## Delay before respawning or destroying (in seconds).
@export var respawn_delay: float = 2.0

## Minimum random health.
@export var min_health: int = 2

## Maximum random health.
@export var max_health: int = 4

## Signal emitted when the enemy is hit.
signal hit

## Signal emitted when the enemy dies.
signal died

## Reference to the sprite for color changes.
@onready var _sprite: Sprite2D = $Sprite2D

## RayCast2D for line of sight detection.
@onready var _raycast: RayCast2D = $RayCast2D

## Wall detection raycasts for obstacle avoidance (created at runtime).
var _wall_raycasts: Array[RayCast2D] = []

## Distance to check for walls ahead.
const WALL_CHECK_DISTANCE: float = 40.0

## Number of raycasts for wall detection (spread around the enemy).
const WALL_CHECK_COUNT: int = 3

## Current health of the enemy.
var _current_health: int = 0

## Maximum health of the enemy (set at spawn).
var _max_health: int = 0

## Whether the enemy is alive.
var _is_alive: bool = true

## Reference to the player (found at runtime).
var _player: Node2D = null

## Time since last shot.
var _shoot_timer: float = 0.0

## Patrol state variables.
var _patrol_points: Array[Vector2] = []
var _current_patrol_index: int = 0
var _is_waiting_at_patrol_point: bool = false
var _patrol_wait_timer: float = 0.0
var _initial_position: Vector2

## Whether the enemy can currently see the player.
var _can_see_player: bool = false


func _ready() -> void:
	_initial_position = global_position
	_initialize_health()
	_update_health_visual()
	_setup_patrol_points()
	_find_player()
	_setup_wall_detection()

	# Preload bullet scene if not set in inspector
	if bullet_scene == null:
		bullet_scene = preload("res://scenes/projectiles/Bullet.tscn")


## Initialize health with random value between min and max.
func _initialize_health() -> void:
	_max_health = randi_range(min_health, max_health)
	_current_health = _max_health
	_is_alive = true


## Setup patrol points based on patrol offsets from initial position.
func _setup_patrol_points() -> void:
	_patrol_points.clear()
	_patrol_points.append(_initial_position)
	for offset in patrol_offsets:
		_patrol_points.append(_initial_position + offset)


## Setup wall detection raycasts for obstacle avoidance.
func _setup_wall_detection() -> void:
	# Create multiple raycasts spread in front of the enemy
	for i in range(WALL_CHECK_COUNT):
		var raycast := RayCast2D.new()
		raycast.enabled = true
		raycast.collision_mask = 4  # Only detect obstacles (layer 3)
		raycast.exclude_parent = true
		add_child(raycast)
		_wall_raycasts.append(raycast)


## Find the player node in the scene tree.
func _find_player() -> void:
	# Try to find the player by group first
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_player = players[0]
		return

	# Fallback: search for player by node name or type
	var root := get_tree().current_scene
	if root:
		_player = _find_player_recursive(root)


## Recursively search for a player node.
func _find_player_recursive(node: Node) -> Node2D:
	if node.name == "Player" and node is Node2D:
		return node
	for child in node.get_children():
		var result := _find_player_recursive(child)
		if result:
			return result
	return null


func _physics_process(delta: float) -> void:
	if not _is_alive:
		return

	# Update shoot cooldown timer
	_shoot_timer += delta

	# Check for player visibility and try to find player if not found
	if _player == null:
		_find_player()

	_check_player_visibility()

	# If player is visible, shoot at them
	if _can_see_player and _player:
		_aim_at_player()
		if _shoot_timer >= shoot_cooldown:
			_shoot()
			_shoot_timer = 0.0
	else:
		# Execute idle behavior
		match behavior_mode:
			BehaviorMode.PATROL:
				_process_patrol(delta)
			BehaviorMode.GUARD:
				_process_guard(delta)

	move_and_slide()


## Check if there's a wall ahead in the given direction and return avoidance direction.
## Returns Vector2.ZERO if no wall detected, otherwise returns a vector to avoid the wall.
func _check_wall_ahead(direction: Vector2) -> Vector2:
	if _wall_raycasts.is_empty():
		return Vector2.ZERO

	var avoidance := Vector2.ZERO
	var perpendicular := Vector2(-direction.y, direction.x)  # 90 degrees rotation

	# Check center, left, and right raycasts
	for i in range(WALL_CHECK_COUNT):
		var angle_offset := (i - 1) * 0.5  # -0.5, 0, 0.5 radians (~-28, 0, 28 degrees)
		var check_direction := direction.rotated(angle_offset)

		var raycast := _wall_raycasts[i]
		raycast.target_position = check_direction * WALL_CHECK_DISTANCE
		raycast.force_raycast_update()

		if raycast.is_colliding():
			# Calculate avoidance based on which raycast hit
			if i == 0:  # Left raycast hit
				avoidance += perpendicular  # Steer right
			elif i == 1:  # Center raycast hit
				avoidance += perpendicular if randf() > 0.5 else -perpendicular  # Random steer
			elif i == 2:  # Right raycast hit
				avoidance -= perpendicular  # Steer left

	return avoidance.normalized() if avoidance.length() > 0 else Vector2.ZERO


## Check if the player is visible using raycast.
func _check_player_visibility() -> void:
	_can_see_player = false

	if _player == null or not _raycast:
		return

	var distance_to_player := global_position.distance_to(_player.global_position)

	# Check if player is within detection range
	if distance_to_player > detection_range:
		return

	# Point raycast at player
	var direction_to_player := (_player.global_position - global_position).normalized()
	_raycast.target_position = direction_to_player * detection_range
	_raycast.force_raycast_update()

	# Check if raycast hit something
	if _raycast.is_colliding():
		var collider := _raycast.get_collider()
		# If we hit the player, we can see them
		if collider == _player:
			_can_see_player = true
		# If we hit a wall/obstacle before the player, we can't see them
	else:
		# No collision, check if player is in direct line
		# This shouldn't happen normally if player has collision
		_can_see_player = distance_to_player <= detection_range


## Aim the enemy sprite/direction at the player.
func _aim_at_player() -> void:
	if _player == null:
		return
	var direction := (_player.global_position - global_position).normalized()
	# Rotate the enemy to face the player
	rotation = direction.angle()


## Shoot a bullet towards the player.
func _shoot() -> void:
	if bullet_scene == null or _player == null:
		return

	var direction := (_player.global_position - global_position).normalized()

	# Create bullet instance
	var bullet := bullet_scene.instantiate()

	# Set bullet position with offset in shoot direction
	bullet.global_position = global_position + direction * bullet_spawn_offset

	# Set bullet direction
	bullet.direction = direction

	# Add bullet to the scene tree
	get_tree().current_scene.add_child(bullet)


## Process patrol behavior - move between patrol points.
func _process_patrol(delta: float) -> void:
	if _patrol_points.is_empty():
		return

	# Handle waiting at patrol point
	if _is_waiting_at_patrol_point:
		_patrol_wait_timer += delta
		if _patrol_wait_timer >= patrol_wait_time:
			_is_waiting_at_patrol_point = false
			_patrol_wait_timer = 0.0
			_current_patrol_index = (_current_patrol_index + 1) % _patrol_points.size()
		velocity = Vector2.ZERO
		return

	# Move towards current patrol point
	var target_point := _patrol_points[_current_patrol_index]
	var direction := (target_point - global_position).normalized()
	var distance := global_position.distance_to(target_point)

	if distance < 5.0:
		# Reached patrol point, start waiting
		_is_waiting_at_patrol_point = true
		velocity = Vector2.ZERO
	else:
		# Check for walls and apply avoidance
		var avoidance := _check_wall_ahead(direction)
		if avoidance != Vector2.ZERO:
			# Blend movement direction with avoidance
			direction = (direction * 0.5 + avoidance * 0.5).normalized()

		velocity = direction * move_speed
		# Face movement direction when patrolling
		rotation = direction.angle()


## Process guard behavior - stand still and look around.
func _process_guard(_delta: float) -> void:
	velocity = Vector2.ZERO
	# In guard mode, enemy doesn't move but can still aim at player when visible


## Called when the enemy is hit (by bullet.gd).
func on_hit() -> void:
	if not _is_alive:
		return

	hit.emit()

	# Show hit flash effect
	_show_hit_flash()

	# Apply damage
	_current_health -= 1

	if _current_health <= 0:
		_on_death()
	else:
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
	if _max_health <= 0:
		return 0.0
	return float(_current_health) / float(_max_health)


## Called when the enemy dies.
func _on_death() -> void:
	_is_alive = false
	died.emit()

	if destroy_on_death:
		await get_tree().create_timer(respawn_delay).timeout
		queue_free()
	else:
		await get_tree().create_timer(respawn_delay).timeout
		_reset()


## Resets the enemy to its initial state.
func _reset() -> void:
	global_position = _initial_position
	rotation = 0.0
	_current_patrol_index = 0
	_is_waiting_at_patrol_point = false
	_patrol_wait_timer = 0.0
	_initialize_health()
	_update_health_visual()
