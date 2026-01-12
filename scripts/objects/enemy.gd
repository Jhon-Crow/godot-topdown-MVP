extends CharacterBody2D
## Enemy AI with tactical behaviors including patrol, guard, cover, and flanking.
##
## Supports multiple behavior modes:
## - PATROL: Moves between patrol points
## - GUARD: Stands in place watching for the player
##
## Tactical features:
## - Uses cover when under fire (suppression)
## - Attempts to flank the player from the sides
## - Coordinates with other enemies (optional)
## - GOAP foundation for goal-oriented planning

## AI States for tactical behavior.
enum AIState {
	IDLE,       ## Default idle state (patrol or guard)
	COMBAT,     ## Actively engaging the player
	SEEKING_COVER,  ## Moving to cover position
	IN_COVER,   ## Taking cover from player fire
	FLANKING,   ## Attempting to flank the player
	SUPPRESSED  ## Under fire, staying in cover
}

## Behavior modes for the enemy.
enum BehaviorMode {
	PATROL,  ## Moves between patrol points
	GUARD    ## Stands in one place
}

## Current behavior mode.
@export var behavior_mode: BehaviorMode = BehaviorMode.GUARD

## Maximum movement speed in pixels per second.
@export var move_speed: float = 220.0

## Combat movement speed (faster when flanking/seeking cover).
@export var combat_move_speed: float = 320.0

## Rotation speed in radians per second for gradual turning.
## Default is 15 rad/sec for challenging but fair combat.
@export var rotation_speed: float = 15.0

## Detection range for spotting the player.
## Set to 0 or negative to allow unlimited detection range (line-of-sight only).
## This allows enemies to see the player even outside the viewport if no obstacles block view.
@export var detection_range: float = 0.0

## Time between shots in seconds.
## Default matches assault rifle fire rate (10 shots/second = 0.1s cooldown).
@export var shoot_cooldown: float = 0.1

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

## Threat sphere radius - bullets within this radius trigger suppression.
@export var threat_sphere_radius: float = 100.0

## Time to stay suppressed after bullets leave threat sphere.
@export var suppression_cooldown: float = 2.0

## Flank angle from player's facing direction (radians).
@export var flank_angle: float = PI / 3.0  # 60 degrees

## Distance to maintain while flanking.
@export var flank_distance: float = 200.0

## Enable/disable flanking behavior.
@export var enable_flanking: bool = true

## Enable/disable cover behavior.
@export var enable_cover: bool = true

## Enable/disable debug logging.
@export var debug_logging: bool = false

## Enable/disable lead prediction (shooting ahead of moving targets).
@export var enable_lead_prediction: bool = true

## Bullet speed for lead prediction calculation.
## Should match the actual bullet speed (default is 2500 for assault rifle).
@export var bullet_speed: float = 2500.0

## Ammunition system - magazine size (bullets per magazine).
@export var magazine_size: int = 30

## Ammunition system - number of magazines the enemy carries.
@export var total_magazines: int = 5

## Ammunition system - time to reload in seconds.
@export var reload_time: float = 2.0

## Delay (in seconds) between spotting player and starting to shoot.
## Gives player a brief reaction time when entering enemy line of sight.
@export var detection_delay: float = 0.05

## Signal emitted when the enemy is hit.
signal hit

## Signal emitted when the enemy dies.
signal died

## Signal emitted when AI state changes.
signal state_changed(new_state: AIState)

## Signal emitted when ammunition changes.
signal ammo_changed(current_ammo: int, reserve_ammo: int)

## Signal emitted when reloading starts.
signal reload_started

## Signal emitted when reloading finishes.
signal reload_finished

## Signal emitted when all ammunition is depleted.
signal ammo_depleted

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

## Cover detection raycasts (created at runtime).
var _cover_raycasts: Array[RayCast2D] = []

## Number of raycasts for cover detection.
const COVER_CHECK_COUNT: int = 16

## Distance to check for cover.
const COVER_CHECK_DISTANCE: float = 300.0

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

## Current ammo in the magazine.
var _current_ammo: int = 0

## Reserve ammo (ammo in remaining magazines).
var _reserve_ammo: int = 0

## Whether the enemy is currently reloading.
var _is_reloading: bool = false

## Timer for reload progress.
var _reload_timer: float = 0.0

## Patrol state variables.
var _patrol_points: Array[Vector2] = []
var _current_patrol_index: int = 0
var _is_waiting_at_patrol_point: bool = false
var _patrol_wait_timer: float = 0.0
var _initial_position: Vector2

## Whether the enemy can currently see the player.
var _can_see_player: bool = false

## Current AI state.
var _current_state: AIState = AIState.IDLE

## Current cover position (if any).
var _cover_position: Vector2 = Vector2.ZERO

## Is currently in a valid cover position.
var _has_valid_cover: bool = false

## Timer for suppression cooldown.
var _suppression_timer: float = 0.0

## Whether enemy is currently under fire (bullets in threat sphere).
var _under_fire: bool = false

## Flank target position.
var _flank_target: Vector2 = Vector2.ZERO

## Threat sphere Area2D for detecting nearby bullets.
var _threat_sphere: Area2D = null

## Bullets currently in threat sphere.
var _bullets_in_threat_sphere: Array = []

## GOAP world state for goal-oriented planning.
var _goap_world_state: Dictionary = {}

## Detection delay timer - tracks time since entering combat.
var _detection_timer: float = 0.0

## Whether the detection delay has elapsed.
var _detection_delay_elapsed: bool = false



func _ready() -> void:
	_initial_position = global_position
	_initialize_health()
	_initialize_ammo()
	_update_health_visual()
	_setup_patrol_points()
	_find_player()
	_setup_wall_detection()
	_setup_cover_detection()
	_setup_threat_sphere()
	_initialize_goap_state()

	# Preload bullet scene if not set in inspector
	if bullet_scene == null:
		bullet_scene = preload("res://scenes/projectiles/Bullet.tscn")


## Initialize health with random value between min and max.
func _initialize_health() -> void:
	_max_health = randi_range(min_health, max_health)
	_current_health = _max_health
	_is_alive = true


## Initialize ammunition with full magazine and reserve ammo.
func _initialize_ammo() -> void:
	_current_ammo = magazine_size
	# Reserve ammo is (total_magazines - 1) * magazine_size since one magazine is loaded
	_reserve_ammo = (total_magazines - 1) * magazine_size
	_is_reloading = false
	_reload_timer = 0.0


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


## Setup cover detection raycasts for finding cover positions.
func _setup_cover_detection() -> void:
	for i in range(COVER_CHECK_COUNT):
		var raycast := RayCast2D.new()
		raycast.enabled = true
		raycast.collision_mask = 4  # Only detect obstacles (layer 3)
		raycast.exclude_parent = true
		add_child(raycast)
		_cover_raycasts.append(raycast)


## Setup threat sphere for detecting nearby bullets.
func _setup_threat_sphere() -> void:
	_threat_sphere = Area2D.new()
	_threat_sphere.name = "ThreatSphere"
	_threat_sphere.collision_layer = 0
	_threat_sphere.collision_mask = 16  # Detect projectiles (layer 5)

	var collision_shape := CollisionShape2D.new()
	var circle_shape := CircleShape2D.new()
	circle_shape.radius = threat_sphere_radius
	collision_shape.shape = circle_shape
	_threat_sphere.add_child(collision_shape)

	add_child(_threat_sphere)

	# Connect signals
	_threat_sphere.area_entered.connect(_on_threat_area_entered)
	_threat_sphere.area_exited.connect(_on_threat_area_exited)


## Initialize GOAP world state.
func _initialize_goap_state() -> void:
	_goap_world_state = {
		"player_visible": false,
		"has_cover": false,
		"in_cover": false,
		"under_fire": false,
		"health_low": false,
		"can_flank": false,
		"at_flank_position": false
	}


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

	# Update reload timer
	_update_reload(delta)

	# Check for player visibility and try to find player if not found
	if _player == null:
		_find_player()

	_check_player_visibility()
	_update_goap_state()
	_update_suppression(delta)

	# Process AI state machine
	_process_ai_state(delta)

	move_and_slide()


## Update GOAP world state based on current conditions.
func _update_goap_state() -> void:
	_goap_world_state["player_visible"] = _can_see_player
	_goap_world_state["under_fire"] = _under_fire
	_goap_world_state["health_low"] = _get_health_percent() < 0.5
	_goap_world_state["in_cover"] = _current_state == AIState.IN_COVER
	_goap_world_state["has_cover"] = _has_valid_cover


## Update suppression state.
func _update_suppression(delta: float) -> void:
	# Clean up destroyed bullets from tracking
	_bullets_in_threat_sphere = _bullets_in_threat_sphere.filter(func(b): return is_instance_valid(b))

	if _bullets_in_threat_sphere.is_empty():
		if _under_fire:
			_suppression_timer += delta
			if _suppression_timer >= suppression_cooldown:
				_under_fire = false
				_suppression_timer = 0.0
				_log_debug("Suppression ended")
	else:
		_under_fire = true
		_suppression_timer = 0.0


## Update reload state.
func _update_reload(delta: float) -> void:
	if not _is_reloading:
		return

	_reload_timer += delta
	if _reload_timer >= reload_time:
		_finish_reload()


## Start reloading the weapon.
func _start_reload() -> void:
	# Can't reload if already reloading or no reserve ammo
	if _is_reloading or _reserve_ammo <= 0:
		return

	_is_reloading = true
	_reload_timer = 0.0
	reload_started.emit()
	_log_debug("Reloading... (%d reserve ammo)" % _reserve_ammo)


## Finish the reload process.
func _finish_reload() -> void:
	_is_reloading = false
	_reload_timer = 0.0

	# Calculate how many rounds to load
	var ammo_needed := magazine_size - _current_ammo
	var ammo_to_load := mini(ammo_needed, _reserve_ammo)

	_reserve_ammo -= ammo_to_load
	_current_ammo += ammo_to_load

	reload_finished.emit()
	ammo_changed.emit(_current_ammo, _reserve_ammo)
	_log_debug("Reload complete. Magazine: %d/%d, Reserve: %d" % [_current_ammo, magazine_size, _reserve_ammo])


## Check if the enemy can shoot (has ammo and not reloading).
func _can_shoot() -> bool:
	# Can't shoot if reloading
	if _is_reloading:
		return false

	# Can't shoot if no ammo in magazine
	if _current_ammo <= 0:
		# Try to start reload if we have reserve ammo
		if _reserve_ammo > 0:
			_start_reload()
		else:
			# No ammo at all - emit depleted signal once
			if not _goap_world_state.get("ammo_depleted", false):
				_goap_world_state["ammo_depleted"] = true
				ammo_depleted.emit()
				_log_debug("All ammunition depleted!")
		return false

	return true


## Process the AI state machine.
func _process_ai_state(delta: float) -> void:
	var previous_state := _current_state

	# State transitions based on conditions
	match _current_state:
		AIState.IDLE:
			_process_idle_state(delta)
		AIState.COMBAT:
			_process_combat_state(delta)
		AIState.SEEKING_COVER:
			_process_seeking_cover_state(delta)
		AIState.IN_COVER:
			_process_in_cover_state(delta)
		AIState.FLANKING:
			_process_flanking_state(delta)
		AIState.SUPPRESSED:
			_process_suppressed_state(delta)

	if previous_state != _current_state:
		state_changed.emit(_current_state)
		_log_debug("State changed: %s -> %s" % [AIState.keys()[previous_state], AIState.keys()[_current_state]])


## Process IDLE state - patrol or guard behavior.
func _process_idle_state(delta: float) -> void:
	# Transition to combat if player is visible
	if _can_see_player and _player:
		_transition_to_combat()
		return

	# Execute idle behavior
	match behavior_mode:
		BehaviorMode.PATROL:
			_process_patrol(delta)
		BehaviorMode.GUARD:
			_process_guard(delta)


## Process COMBAT state - actively engaging player.
func _process_combat_state(delta: float) -> void:
	# In combat, enemy stands still and shoots (no velocity)
	velocity = Vector2.ZERO

	# Check for suppression - high priority
	if _under_fire and enable_cover:
		_transition_to_seeking_cover()
		return

	# If can't see player, try flanking or return to idle
	if not _can_see_player:
		if enable_flanking and _player:
			_transition_to_flanking()
		else:
			_transition_to_idle()
		return

	# Update detection delay timer
	if not _detection_delay_elapsed:
		_detection_timer += delta
		if _detection_timer >= detection_delay:
			_detection_delay_elapsed = true

	# Aim and shoot at player (only shoot after detection delay)
	if _player:
		_aim_at_player()
		if _detection_delay_elapsed and _shoot_timer >= shoot_cooldown:
			_shoot()
			_shoot_timer = 0.0


## Process SEEKING_COVER state - moving to cover position.
func _process_seeking_cover_state(_delta: float) -> void:
	if not _has_valid_cover:
		# Try to find cover
		_find_cover_position()
		if not _has_valid_cover:
			# No cover found, stay in combat
			_transition_to_combat()
			return

	# Check if we're already hidden from the player (the main goal)
	if not _is_visible_from_player():
		_transition_to_in_cover()
		_log_debug("Hidden from player, entering cover state")
		return

	# Move towards cover
	var direction := (_cover_position - global_position).normalized()
	var distance := global_position.distance_to(_cover_position)

	if distance < 10.0:
		# Reached the cover position, but still visible - try to find better cover
		if _is_visible_from_player():
			_has_valid_cover = false
			_find_cover_position()
			if not _has_valid_cover:
				# No better cover found, stay in combat
				_transition_to_combat()
				return

	# Apply wall avoidance
	var avoidance := _check_wall_ahead(direction)
	if avoidance != Vector2.ZERO:
		direction = (direction * 0.5 + avoidance * 0.5).normalized()

	velocity = direction * combat_move_speed
	rotation = direction.angle()

	# Can still shoot while moving to cover
	if _can_see_player and _player and _shoot_timer >= shoot_cooldown:
		_aim_at_player()
		_shoot()
		_shoot_timer = 0.0


## Process IN_COVER state - taking cover from enemy fire.
func _process_in_cover_state(_delta: float) -> void:
	velocity = Vector2.ZERO

	# If still under fire, stay suppressed
	if _under_fire:
		_transition_to_suppressed()
		return

	# Check if player has flanked us - if we're now visible from player's position,
	# we need to find new cover
	if _is_visible_from_player():
		_log_debug("Player flanked our cover position, seeking new cover")
		_has_valid_cover = false  # Invalidate current cover
		_transition_to_seeking_cover()
		return

	# If not under fire and can see player, engage
	if _can_see_player and _player:
		_aim_at_player()
		if _shoot_timer >= shoot_cooldown:
			_shoot()
			_shoot_timer = 0.0

	# If player is no longer visible and not under fire, try flanking or return to combat
	if not _can_see_player and not _under_fire:
		if enable_flanking and _player:
			_transition_to_flanking()
		else:
			_transition_to_combat()


## Process FLANKING state - attempting to flank the player.
func _process_flanking_state(_delta: float) -> void:
	# If under fire, seek cover instead
	if _under_fire and enable_cover:
		_transition_to_seeking_cover()
		return

	# If can see player, engage in combat
	if _can_see_player:
		_transition_to_combat()
		return

	if _player == null:
		_transition_to_idle()
		return

	# Calculate flank position
	_calculate_flank_position()

	# Move towards flank position
	var direction := (_flank_target - global_position).normalized()
	var distance := global_position.distance_to(_flank_target)

	if distance < 20.0:
		# Reached flank position, engage
		_transition_to_combat()
	else:
		# Apply wall avoidance
		var avoidance := _check_wall_ahead(direction)
		if avoidance != Vector2.ZERO:
			direction = (direction * 0.5 + avoidance * 0.5).normalized()

		velocity = direction * combat_move_speed
		rotation = direction.angle()


## Process SUPPRESSED state - staying in cover under fire.
func _process_suppressed_state(_delta: float) -> void:
	velocity = Vector2.ZERO

	# Check if player has flanked us - if we're now visible from player's position,
	# we need to find new cover even while suppressed
	if _is_visible_from_player():
		_log_debug("Player flanked our cover position while suppressed, seeking new cover")
		_has_valid_cover = false  # Invalidate current cover
		_transition_to_seeking_cover()
		return

	# Can still shoot while suppressed
	if _can_see_player and _player:
		_aim_at_player()
		if _shoot_timer >= shoot_cooldown:
			_shoot()
			_shoot_timer = 0.0

	# If no longer under fire, exit suppression
	if not _under_fire:
		_transition_to_in_cover()


## Transition to IDLE state.
func _transition_to_idle() -> void:
	_current_state = AIState.IDLE


## Transition to COMBAT state.
func _transition_to_combat() -> void:
	_current_state = AIState.COMBAT
	# Reset detection delay timer when entering combat
	_detection_timer = 0.0
	_detection_delay_elapsed = false


## Transition to SEEKING_COVER state.
func _transition_to_seeking_cover() -> void:
	_current_state = AIState.SEEKING_COVER
	_find_cover_position()


## Transition to IN_COVER state.
func _transition_to_in_cover() -> void:
	_current_state = AIState.IN_COVER


## Transition to FLANKING state.
func _transition_to_flanking() -> void:
	_current_state = AIState.FLANKING
	_calculate_flank_position()


## Transition to SUPPRESSED state.
func _transition_to_suppressed() -> void:
	_current_state = AIState.SUPPRESSED


## Check if the enemy is visible from the player's position.
## Uses raycasting from player to enemy to determine if there are obstacles blocking line of sight.
## This is the inverse of _can_see_player - it checks if the PLAYER can see the ENEMY.
## Checks multiple points on the enemy body (center and corners) to account for enemy size.
func _is_visible_from_player() -> bool:
	if _player == null:
		return false

	# Check visibility to multiple points on the enemy body
	# This accounts for the enemy's size - corners can stick out from cover
	var check_points := _get_enemy_check_points(global_position)

	for point in check_points:
		if _is_point_visible_from_player(point):
			return true

	return false


## Get multiple check points on the enemy body for visibility testing.
## Returns center and 4 corner points offset by the enemy's radius.
func _get_enemy_check_points(center: Vector2) -> Array[Vector2]:
	# Enemy collision radius is 24, sprite is 48x48
	# Use a slightly smaller radius to avoid edge cases
	const ENEMY_RADIUS: float = 22.0

	var points: Array[Vector2] = []
	points.append(center)  # Center point

	# 4 corner points (diagonal directions)
	var diagonal_offset := ENEMY_RADIUS * 0.707  # cos(45°) ≈ 0.707
	points.append(center + Vector2(diagonal_offset, diagonal_offset))
	points.append(center + Vector2(-diagonal_offset, diagonal_offset))
	points.append(center + Vector2(diagonal_offset, -diagonal_offset))
	points.append(center + Vector2(-diagonal_offset, -diagonal_offset))

	return points


## Check if a single point is visible from the player's position.
func _is_point_visible_from_player(point: Vector2) -> bool:
	if _player == null:
		return false

	var player_pos := _player.global_position
	var distance := player_pos.distance_to(point)

	# Use direct space state to check line of sight from player to point
	var space_state := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.new()
	query.from = player_pos
	query.to = point
	query.collision_mask = 4  # Only check obstacles (layer 3)
	query.exclude = []

	var result := space_state.intersect_ray(query)

	if result.is_empty():
		# No obstacle between player and point - point is visible
		return true
	else:
		# Check if we hit an obstacle before reaching the point
		var hit_position: Vector2 = result["position"]
		var distance_to_hit := player_pos.distance_to(hit_position)

		# If we hit something closer than the point, the point is hidden
		if distance_to_hit < distance - 10.0:  # 10 pixel tolerance
			return false
		else:
			return true


## Check if a specific position would make the enemy visible from the player's position.
## Checks all enemy body points (center and corners) to account for enemy size.
## Used to validate cover positions before moving to them.
func _is_position_visible_from_player(pos: Vector2) -> bool:
	if _player == null:
		return true  # Assume visible if no player

	# Check visibility for all enemy body points at the given position
	var check_points := _get_enemy_check_points(pos)

	for point in check_points:
		if _is_point_visible_from_player(point):
			return true

	return false


## Find a valid cover position relative to the player.
## The cover position must be hidden from the player's line of sight.
func _find_cover_position() -> void:
	if _player == null:
		_has_valid_cover = false
		return

	var player_pos := _player.global_position
	var best_cover: Vector2 = Vector2.ZERO
	var best_score: float = -INF
	var found_hidden_cover: bool = false

	# Cast rays in all directions to find obstacles
	for i in range(COVER_CHECK_COUNT):
		var angle := (float(i) / COVER_CHECK_COUNT) * TAU
		var direction := Vector2.from_angle(angle)

		var raycast := _cover_raycasts[i]
		raycast.target_position = direction * COVER_CHECK_DISTANCE
		raycast.force_raycast_update()

		if raycast.is_colliding():
			var collision_point := raycast.get_collision_point()
			var collision_normal := raycast.get_collision_normal()

			# Cover position is on the opposite side of the obstacle from player
			var direction_from_player := (collision_point - player_pos).normalized()

			# Position behind cover (offset from collision point along normal)
			# Offset must be large enough to hide the entire enemy body (radius ~24 pixels)
			# Using 35 pixels to provide some margin for the enemy's collision shape
			var cover_pos := collision_point + collision_normal * 35.0

			# First priority: Check if this position is actually hidden from player
			var is_hidden := not _is_position_visible_from_player(cover_pos)

			# Only consider hidden positions unless we have no choice
			if is_hidden or not found_hidden_cover:
				# Score based on:
				# 1. Whether position is hidden (highest priority)
				# 2. Distance from enemy (closer is better)
				# 3. Position relative to player (behind cover from player's view)
				var hidden_score: float = 10.0 if is_hidden else 0.0  # Heavy weight for hidden positions

				var distance_score := 1.0 - (global_position.distance_to(cover_pos) / COVER_CHECK_DISTANCE)

				# Check if this position is on the far side of obstacle from player
				var cover_direction := (cover_pos - player_pos).normalized()
				var dot_product := direction_from_player.dot(cover_direction)
				var blocking_score: float = maxf(0.0, dot_product)

				var total_score: float = hidden_score + distance_score * 0.3 + blocking_score * 0.7

				# If we find a hidden position, only accept other hidden positions
				if is_hidden and not found_hidden_cover:
					found_hidden_cover = true
					best_score = total_score
					best_cover = cover_pos
				elif (is_hidden or not found_hidden_cover) and total_score > best_score:
					best_score = total_score
					best_cover = cover_pos

	if best_score > 0:
		_cover_position = best_cover
		_has_valid_cover = true
		_log_debug("Found cover at: %s (hidden: %s)" % [_cover_position, found_hidden_cover])
	else:
		_has_valid_cover = false


## Calculate flank position based on player location.
func _calculate_flank_position() -> void:
	if _player == null:
		return

	var player_pos := _player.global_position
	var player_to_enemy := (global_position - player_pos).normalized()

	# Choose left or right flank based on current position
	var flank_side := 1.0 if randf() > 0.5 else -1.0
	var flank_direction := player_to_enemy.rotated(flank_angle * flank_side)

	_flank_target = player_pos + flank_direction * flank_distance
	_log_debug("Flank target: %s" % _flank_target)


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
## If detection_range is 0 or negative, uses unlimited detection range (line-of-sight only).
## This allows the enemy to see the player even outside the viewport if there's no obstacle.
func _check_player_visibility() -> void:
	_can_see_player = false

	if _player == null or not _raycast:
		return

	var distance_to_player := global_position.distance_to(_player.global_position)

	# Check if player is within detection range (only if detection_range is positive)
	# If detection_range <= 0, detection is unlimited (line-of-sight only)
	if detection_range > 0 and distance_to_player > detection_range:
		return

	# Point raycast at player - use actual distance to player for the raycast length
	var direction_to_player := (_player.global_position - global_position).normalized()
	var raycast_length := distance_to_player + 10.0  # Add small buffer to ensure we reach player
	_raycast.target_position = direction_to_player * raycast_length
	_raycast.force_raycast_update()

	# Check if raycast hit something
	if _raycast.is_colliding():
		var collider := _raycast.get_collider()
		# If we hit the player, we can see them
		if collider == _player:
			_can_see_player = true
		# If we hit a wall/obstacle before the player, we can't see them
	else:
		# No collision between us and player - we have clear line of sight
		_can_see_player = true


## Aim the enemy sprite/direction at the player using gradual rotation.
func _aim_at_player() -> void:
	if _player == null:
		return
	var direction := (_player.global_position - global_position).normalized()
	var target_angle := direction.angle()

	# Calculate the shortest rotation direction
	var angle_diff := wrapf(target_angle - rotation, -PI, PI)

	# Get the delta time from the current physics process
	var delta := get_physics_process_delta_time()

	# Apply gradual rotation based on rotation_speed
	if abs(angle_diff) <= rotation_speed * delta:
		# Close enough to snap to target
		rotation = target_angle
	elif angle_diff > 0:
		rotation += rotation_speed * delta
	else:
		rotation -= rotation_speed * delta


## Shoot a bullet towards the player.
func _shoot() -> void:
	if bullet_scene == null or _player == null:
		return

	# Check if we can shoot (have ammo and not reloading)
	if not _can_shoot():
		return

	var target_position := _player.global_position

	# Apply lead prediction if enabled
	if enable_lead_prediction:
		target_position = _calculate_lead_prediction()

	var direction := (target_position - global_position).normalized()

	# Create bullet instance
	var bullet := bullet_scene.instantiate()

	# Set bullet position with offset in shoot direction
	bullet.global_position = global_position + direction * bullet_spawn_offset

	# Set bullet direction
	bullet.direction = direction

	# Set shooter ID to identify this enemy as the source
	# This prevents enemies from detecting their own bullets in the threat sphere
	bullet.shooter_id = get_instance_id()

	# Add bullet to the scene tree
	get_tree().current_scene.add_child(bullet)

	# Consume ammo
	_current_ammo -= 1
	ammo_changed.emit(_current_ammo, _reserve_ammo)

	# Auto-reload when magazine is empty
	if _current_ammo <= 0 and _reserve_ammo > 0:
		_start_reload()


## Calculate lead prediction - aims where the player will be, not where they are.
## Uses iterative approach for better accuracy with moving targets.
func _calculate_lead_prediction() -> Vector2:
	if _player == null:
		return global_position

	var player_pos := _player.global_position
	var player_velocity := Vector2.ZERO

	# Get player velocity if they are a CharacterBody2D
	if _player is CharacterBody2D:
		player_velocity = _player.velocity

	# If player is stationary, no need for prediction
	if player_velocity.length_squared() < 1.0:
		return player_pos

	# Iterative lead prediction for better accuracy
	# Start with player's current position
	var predicted_pos := player_pos
	var distance := global_position.distance_to(predicted_pos)

	# Iterate 2-3 times for convergence
	for i in range(3):
		# Time for bullet to reach the predicted position
		var time_to_target := distance / bullet_speed

		# Predict where player will be at that time
		predicted_pos = player_pos + player_velocity * time_to_target

		# Update distance for next iteration
		distance = global_position.distance_to(predicted_pos)

	_log_debug("Lead prediction: player at %s moving %s, aiming at %s" % [player_pos, player_velocity, predicted_pos])

	return predicted_pos


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


## Called when a bullet enters the threat sphere.
func _on_threat_area_entered(area: Area2D) -> void:
	# Check if bullet has shooter_id property and if it's from this enemy
	# This prevents enemies from being suppressed by their own bullets
	if "shooter_id" in area and area.shooter_id == get_instance_id():
		return  # Ignore own bullets

	_bullets_in_threat_sphere.append(area)
	_under_fire = true
	_suppression_timer = 0.0
	_log_debug("Bullet entered threat sphere, under fire!")


## Called when a bullet exits the threat sphere.
func _on_threat_area_exited(area: Area2D) -> void:
	_bullets_in_threat_sphere.erase(area)


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
	_current_state = AIState.IDLE
	_has_valid_cover = false
	_under_fire = false
	_suppression_timer = 0.0
	_detection_timer = 0.0
	_detection_delay_elapsed = false
	_bullets_in_threat_sphere.clear()
	_initialize_health()
	_initialize_ammo()
	_update_health_visual()
	_initialize_goap_state()


## Log debug message if debug_logging is enabled.
func _log_debug(message: String) -> void:
	if debug_logging:
		print("[Enemy %s] %s" % [name, message])


## Get current AI state (for external access/debugging).
func get_current_state() -> AIState:
	return _current_state


## Get GOAP world state (for GOAP planner).
func get_goap_world_state() -> Dictionary:
	return _goap_world_state.duplicate()


## Check if enemy is currently under fire.
func is_under_fire() -> bool:
	return _under_fire


## Check if enemy is in cover.
func is_in_cover() -> bool:
	return _current_state == AIState.IN_COVER or _current_state == AIState.SUPPRESSED


## Get current ammo in magazine.
func get_current_ammo() -> int:
	return _current_ammo


## Get reserve ammo.
func get_reserve_ammo() -> int:
	return _reserve_ammo


## Get total ammo (current + reserve).
func get_total_ammo() -> int:
	return _current_ammo + _reserve_ammo


## Check if enemy is currently reloading.
func is_reloading() -> bool:
	return _is_reloading


## Check if enemy has any ammo left.
func has_ammo() -> bool:
	return _current_ammo > 0 or _reserve_ammo > 0
