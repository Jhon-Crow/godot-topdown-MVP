extends Node
## Component that handles enemy cover finding and positioning (Issue #336).
## Extracted from enemy.gd to reduce file size below 2500 lines.
class_name EnemyCoverSystem

## Signal emitted when cover is found or lost.
signal cover_found(position: Vector2)
signal cover_lost

# Configuration
var cover_check_count: int = 16  ## Number of cover check raycasts
var cover_check_distance: float = 300.0  ## Max distance to check for cover
var min_cover_distance: float = 50.0  ## Minimum distance for valid cover
var pursuit_same_obstacle_penalty: float = 4.0  ## Penalty for reusing same cover

# State
var _enemy: CharacterBody2D = null
var _player: Node2D = null
var _cover_raycasts: Array[RayCast2D] = []
var _cover_position: Vector2 = Vector2.ZERO
var _has_valid_cover: bool = false
var _current_cover_obstacle: Object = null
var _nav_agent: NavigationAgent2D = null


func _ready() -> void:
	_enemy = get_parent() as CharacterBody2D


## Initialize with required references.
func initialize(nav_agent: NavigationAgent2D, player: Node2D) -> void:
	_nav_agent = nav_agent
	_player = player
	_setup_cover_raycasts()


## Set the player reference.
func set_player(player: Node2D) -> void:
	_player = player


## Setup cover detection raycasts.
func _setup_cover_raycasts() -> void:
	if _enemy == null:
		return

	_cover_raycasts.clear()

	for i in range(cover_check_count):
		var raycast := RayCast2D.new()
		raycast.enabled = false
		raycast.collision_mask = 2  # Walls/obstacles
		var angle := (float(i) / float(cover_check_count)) * TAU
		raycast.target_position = Vector2.RIGHT.rotated(angle) * cover_check_distance
		_enemy.add_child(raycast)
		_cover_raycasts.append(raycast)


## Find the best cover position from current location.
## Returns true if valid cover was found.
func find_cover_position() -> bool:
	if _enemy == null or _player == null:
		_has_valid_cover = false
		return false

	var best_cover := Vector2.ZERO
	var best_score := -INF
	var best_obstacle: Object = null

	for raycast in _cover_raycasts:
		raycast.force_raycast_update()

		if not raycast.is_colliding():
			continue

		var hit_point := raycast.get_collision_point()
		var hit_normal := raycast.get_collision_normal()
		var obstacle := raycast.get_collider()

		# Position behind cover (offset from hit point along normal)
		var cover_pos := hit_point + hit_normal * 40.0

		# Validate cover position
		if not _is_cover_position_valid(cover_pos):
			continue

		# Score the cover position
		var score := _score_cover_position(cover_pos, hit_point, obstacle)

		if score > best_score:
			best_score = score
			best_cover = cover_pos
			best_obstacle = obstacle

	if best_score > -INF:
		_cover_position = best_cover
		_current_cover_obstacle = best_obstacle
		_has_valid_cover = true
		cover_found.emit(_cover_position)
		return true
	else:
		_has_valid_cover = false
		cover_lost.emit()
		return false


## Find cover that advances toward the player (for pursuit).
func find_pursuit_cover_toward_player() -> bool:
	if _enemy == null or _player == null:
		return false

	var to_player := (_player.global_position - _enemy.global_position).normalized()
	var best_cover := Vector2.ZERO
	var best_score := -INF
	var best_obstacle: Object = null

	for raycast in _cover_raycasts:
		raycast.force_raycast_update()

		if not raycast.is_colliding():
			continue

		var hit_point := raycast.get_collision_point()
		var hit_normal := raycast.get_collision_normal()
		var obstacle := raycast.get_collider()

		var cover_pos := hit_point + hit_normal * 40.0

		if not _is_cover_position_valid(cover_pos):
			continue

		# Must be closer to player than current position
		var current_dist := _enemy.global_position.distance_to(_player.global_position)
		var cover_dist := cover_pos.distance_to(_player.global_position)

		if cover_dist >= current_dist * 0.95:  # Allow some tolerance
			continue

		var score := _score_pursuit_cover(cover_pos, to_player, obstacle)

		if score > best_score:
			best_score = score
			best_cover = cover_pos
			best_obstacle = obstacle

	if best_score > -INF:
		_cover_position = best_cover
		_current_cover_obstacle = best_obstacle
		_has_valid_cover = true
		return true

	return false


## Find cover closest to the player (for assault).
func find_cover_closest_to_player() -> bool:
	if _enemy == null or _player == null:
		return false

	var best_cover := Vector2.ZERO
	var best_dist := INF

	for raycast in _cover_raycasts:
		raycast.force_raycast_update()

		if not raycast.is_colliding():
			continue

		var hit_point := raycast.get_collision_point()
		var hit_normal := raycast.get_collision_normal()
		var cover_pos := hit_point + hit_normal * 40.0

		if not _is_cover_position_valid(cover_pos):
			continue

		var dist := cover_pos.distance_to(_player.global_position)
		if dist < best_dist:
			best_dist = dist
			best_cover = cover_pos

	if best_dist < INF:
		_cover_position = best_cover
		_has_valid_cover = true
		return true

	return false


## Find cover for flanking toward a target position.
func find_flank_cover_toward_target(target_pos: Vector2, flank_side: float) -> bool:
	if _enemy == null or _player == null:
		return false

	var to_player := (_player.global_position - _enemy.global_position).normalized()
	var flank_dir := to_player.rotated(flank_side * PI / 3.0)  # 60 degree offset

	var best_cover := Vector2.ZERO
	var best_score := -INF

	for raycast in _cover_raycasts:
		raycast.force_raycast_update()

		if not raycast.is_colliding():
			continue

		var hit_point := raycast.get_collision_point()
		var hit_normal := raycast.get_collision_normal()
		var cover_pos := hit_point + hit_normal * 40.0

		if not _is_cover_position_valid(cover_pos):
			continue

		# Score based on alignment with flank direction
		var to_cover := (cover_pos - _enemy.global_position).normalized()
		var flank_alignment := to_cover.dot(flank_dir)

		# Also consider getting closer to target
		var progress := (_enemy.global_position.distance_to(target_pos) -
						cover_pos.distance_to(target_pos))

		var score := flank_alignment * 2.0 + progress / 100.0

		if score > best_score:
			best_score = score
			best_cover = cover_pos

	if best_score > -INF:
		_cover_position = best_cover
		_has_valid_cover = true
		return true

	return false


## Check if a cover position is valid (reachable and safe).
func _is_cover_position_valid(pos: Vector2) -> bool:
	if _enemy == null:
		return false

	# Check minimum distance
	var dist := _enemy.global_position.distance_to(pos)
	if dist < min_cover_distance:
		return false

	# Check if position is navigable
	if not _can_reach_position(pos):
		return false

	return true


## Check if a position can be reached via navigation.
func _can_reach_position(pos: Vector2) -> bool:
	if _nav_agent == null or _enemy == null:
		return true  # Assume reachable if no nav

	_nav_agent.target_position = pos
	var path := _nav_agent.get_current_navigation_path()

	if path.is_empty():
		return false

	# Check if path distance is reasonable
	var path_dist := 0.0
	for i in range(1, path.size()):
		path_dist += path[i - 1].distance_to(path[i])

	var direct_dist := _enemy.global_position.distance_to(pos)

	# Path shouldn't be more than 3x the direct distance
	return path_dist < direct_dist * 3.0


## Score a general cover position.
func _score_cover_position(cover_pos: Vector2, hit_point: Vector2, obstacle: Object) -> float:
	var score := 0.0

	# Distance score (closer is better, but not too close)
	var dist := _enemy.global_position.distance_to(cover_pos)
	score += clampf(1.0 - dist / cover_check_distance, 0.0, 1.0) * 2.0

	# Blocking score (how well it blocks line of sight to player)
	if _player != null:
		var to_player := (_player.global_position - cover_pos).normalized()
		var to_cover := (hit_point - cover_pos).normalized()
		var blocking := to_cover.dot(to_player)
		score += blocking * 3.0

	# Penalty for reusing same obstacle
	if obstacle == _current_cover_obstacle and _current_cover_obstacle != null:
		score -= pursuit_same_obstacle_penalty

	# Bonus if actually hidden from player
	if not _is_position_visible_from_player(cover_pos):
		score += 5.0

	return score


## Score a pursuit cover position.
func _score_pursuit_cover(cover_pos: Vector2, to_player: Vector2, obstacle: Object) -> float:
	var score := 0.0

	# Progress toward player
	var to_cover := (cover_pos - _enemy.global_position).normalized()
	score += to_cover.dot(to_player) * 3.0

	# Distance score
	var dist := _enemy.global_position.distance_to(cover_pos)
	score += clampf(dist / 100.0, 0.0, 2.0)

	# Penalty for reusing same obstacle
	if obstacle == _current_cover_obstacle and _current_cover_obstacle != null:
		score -= pursuit_same_obstacle_penalty

	return score


## Check if a position is visible from the player.
func _is_position_visible_from_player(pos: Vector2) -> bool:
	if _player == null or _enemy == null:
		return true

	var space_state := _enemy.get_world_2d().direct_space_state
	if space_state == null:
		return true

	var query := PhysicsRayQueryParameters2D.create(
		_player.global_position,
		pos,
		2  # Wall collision layer
	)
	query.exclude = [_player]

	var result := space_state.intersect_ray(query)
	return result.is_empty()


# --- Accessors ---

func get_cover_position() -> Vector2:
	return _cover_position


func has_valid_cover() -> bool:
	return _has_valid_cover


func get_current_obstacle() -> Object:
	return _current_cover_obstacle


func clear_cover() -> void:
	_has_valid_cover = false
	_cover_position = Vector2.ZERO
	_current_cover_obstacle = null
