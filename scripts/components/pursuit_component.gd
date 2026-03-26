class_name PursuitComponent
extends RefCounted
## Cover-finding logic for the PURSUING AI state (Issue #1289).
##
## Encapsulates the algorithm that selects the best cover position an enemy
## should move toward while pursuing the player cover-to-cover.
##
## The algorithm:
##   1. Casts rays in all directions to find nearby obstacles.
##   2. Keeps only candidates that bring the enemy closer to the player
##      (Issue #93: minimum-progress filter).
##   3. Rejects positions off the navmesh (Issue #1289: prevents paths through walls).
##   4. Scores survivors by hidden-ness, approach progress, and penalties for:
##      - Same obstacle as current cover.
##      - Lit by player flashlight (Issue #574).
##      - Already targeted by another enemy (Issue #1289: enemy spread).
##      - Inside a machine gunner's firing sector (Issue #1552: MG zone avoidance).
##   5. Falls back to passage waypoints when no scored position is found.
##
## Usage:
##   In enemy._ready():
##     _pursuit_component = PursuitComponent.new(self)
##   In enemy._find_pursuit_cover_toward_player():
##     var result := _pursuit_component.find_cover()
##     if result.found:
##         _pursuit_next_cover   = result.cover
##         _has_pursuit_cover    = true
##         _current_cover_obstacle = result.obstacle
##     else:
##         _has_pursuit_cover = false

## Enlarged nav step while pursuing (2× scene default 40 px). Fewer micro-waypoints
## means smoother pursuit movement and more efficient path following (Issue #1289).
const PURSUIT_PATH_DESIRED_DISTANCE: float = 80.0

## Penalty subtracted from a cover score when another enemy is already heading there.
## Encourages enemies to spread across different cover positions (Issue #1289).
const PURSUIT_ENEMY_OCCUPIED_PENALTY: float = 3.0

## Radius (px) within which a cover is considered occupied by another enemy (Issue #1289).
const PURSUIT_ENEMY_OCCUPIED_RADIUS: float = 80.0

## Reference to the enemy node that owns this component.
var _enemy: Node2D = null


func _init(enemy_ref: Node2D) -> void:
	_enemy = enemy_ref


## Find the best pursuit cover position for the enemy to move toward.
##
## Returns a Dictionary with:
##   found    (bool)    — true if a valid cover was found
##   cover    (Vector2) — the selected cover position
##   obstacle (Object)  — the collider behind which cover is taken (may be null)
func find_cover() -> Dictionary:
	if _enemy == null or not is_instance_valid(_enemy):
		return {found = false, cover = Vector2.ZERO, obstacle = null}

	var target_pos: Vector2 = _enemy._get_target_position()
	if target_pos == _enemy.global_position and _enemy._player == null:
		return {found = false, cover = Vector2.ZERO, obstacle = null}

	# Issue #1227: honour pre-defined combat-path waypoints first.
	var wp_p: Vector2 = _enemy._combat_waypoint(target_pos)
	if wp_p != Vector2.ZERO:
		return {found = true, cover = wp_p, obstacle = null}

	var player_pos: Vector2 = target_pos
	var my_dist: float     = _enemy.global_position.distance_to(player_pos)
	var min_progress: float = my_dist * _enemy.PURSUIT_MIN_PROGRESS_FRACTION

	var best_cover: Vector2 = Vector2.ZERO
	var best_score: float   = -INF
	var best_obstacle: Object = null
	var found_valid: bool   = false

	for i in range(_enemy.COVER_CHECK_COUNT):
		var raycast: RayCast2D = _enemy._cover_raycasts[i]
		raycast.target_position = Vector2.from_angle((float(i) / _enemy.COVER_CHECK_COUNT) * TAU) * _enemy.COVER_CHECK_DISTANCE
		raycast.force_raycast_update()

		if not raycast.is_colliding():
			continue

		var collision_point:  Vector2 = raycast.get_collision_point()
		var collision_normal: Vector2 = raycast.get_collision_normal()
		var collider: Object          = raycast.get_collider()
		var cover_pos: Vector2        = collision_point + collision_normal * 35.0

		var cover_dist_to_player: float = cover_pos.distance_to(player_pos)
		var cover_dist_from_me: float   = _enemy.global_position.distance_to(cover_pos)
		var progress: float             = my_dist - cover_dist_to_player

		# Must be closer to player than current position.
		if cover_dist_to_player >= my_dist:
			continue
		# Must make meaningful progress (Issue #93).
		if progress < min_progress:
			continue
		# Must be far enough away to constitute real movement.
		if cover_dist_from_me < 30.0:
			continue
		# Must have line-of-sight to the cover (straight-line check).
		if not _enemy._can_reach_position(cover_pos):
			continue

		# Issue #1289: Reject positions off the navmesh so the navigation agent
		# never tries to route through walls to reach them.
		var nav_agent = _enemy._nav_agent
		if nav_agent != null:
			var nav_map: RID = nav_agent.get_navigation_map()
			if nav_map.is_valid():
				var snapped: Vector2 = NavigationServer2D.map_get_closest_point(nav_map, cover_pos)
				if cover_pos.distance_to(snapped) > nav_agent.radius * 2.0:
					continue  # Off navmesh — skip

		var is_hidden: bool = not _enemy._is_position_visible_from_player(cover_pos)

		# Penalty: same obstacle as current cover (Issue #93).
		var same_obstacle_penalty: float = 0.0
		if _enemy._current_cover_obstacle != null and collider == _enemy._current_cover_obstacle:
			same_obstacle_penalty = _enemy.PURSUIT_SAME_OBSTACLE_PENALTY

		# Issue #1289: Penalise cover positions already targeted by another enemy.
		var occupied_penalty: float = 0.0
		for other: Node in _enemy.get_tree().get_nodes_in_group("enemies"):
			if other == _enemy or not is_instance_valid(other):
				continue
			var raw_cover = other.get("_pursuit_next_cover")
			var other_cover: Vector2 = raw_cover if raw_cover != null else Vector2.ZERO
			if other_cover != Vector2.ZERO and cover_pos.distance_to(other_cover) < PURSUIT_ENEMY_OCCUPIED_RADIUS:
				occupied_penalty = PURSUIT_ENEMY_OCCUPIED_PENALTY
				break

		# Issue #574: Penalise cover lit by the player's flashlight.
		var flashlight_penalty: float = 0.0
		if _enemy._flashlight_detection and _enemy._player and \
				_enemy._flashlight_detection.is_position_lit(cover_pos, _enemy._player, _enemy._raycast):
			flashlight_penalty = 8.0

		# Issue #1552: Penalise cover inside a machine gunner's firing sector.
		var mg_zone_penalty: float = 0.0
		if MachineGunnerZoneComponent.is_position_in_any_mg_zone(_enemy, cover_pos):
			mg_zone_penalty = MachineGunnerZoneComponent.MG_ZONE_COVER_PENALTY

		var hidden_score: float      = 5.0 if is_hidden else 0.0
		var approach_score: float    = progress / _enemy.CLOSE_COMBAT_DISTANCE
		var distance_penalty: float  = cover_dist_from_me / _enemy.COVER_CHECK_DISTANCE
		var total_score: float       = hidden_score + approach_score * 2.0 \
			- distance_penalty - same_obstacle_penalty - flashlight_penalty - occupied_penalty \
			- mg_zone_penalty

		if total_score > best_score:
			best_score    = total_score
			best_cover    = cover_pos
			best_obstacle = collider
			found_valid   = true

	if found_valid:
		_enemy._log_debug("Found pursuit cover at %s (score: %.2f)" % [best_cover, best_score])
		return {found = true, cover = best_cover, obstacle = best_obstacle}

	# Fallback: nearest passage waypoint (Issue #1226).
	var best_wp: Vector2 = Vector2.ZERO
	var best_d: float    = INF
	for wp in _enemy._passage_waypoints:
		var d: float = _enemy.global_position.distance_to(wp.global_position)
		if d >= 50.0 and d < best_d:
			best_d  = d
			best_wp = wp.global_position
	if best_wp != Vector2.ZERO:
		return {found = true, cover = best_wp, obstacle = null}

	return {found = false, cover = Vector2.ZERO, obstacle = null}
