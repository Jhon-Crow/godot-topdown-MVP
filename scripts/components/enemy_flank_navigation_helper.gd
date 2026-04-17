class_name EnemyFlankNavigationHelper
extends RefCounted
## Shared navmesh-aware flank target validation for Enemy.


static func get_flank_nav_position(nav_agent: NavigationAgent2D, candidate: Vector2) -> Vector2:
	if nav_agent:
		return NavigationServer2D.map_get_closest_point(nav_agent.get_navigation_map(), candidate)
	return candidate


static func is_candidate_flank_position_valid(enemy: Node2D, nav_agent: NavigationAgent2D, candidate: Vector2, player_pos: Vector2) -> bool:
	if candidate == Vector2.ZERO:
		return false
	if candidate.distance_to(player_pos) < 20.0:
		return false
	return is_navigation_target_reasonable(enemy, nav_agent, candidate)


static func is_navigation_target_reasonable(enemy: Node2D, nav_agent: NavigationAgent2D, target: Vector2) -> bool:
	if nav_agent == null:
		return true

	var nav_map := nav_agent.get_navigation_map()
	if not nav_map.is_valid():
		return true

	var straight_distance := enemy.global_position.distance_to(target)
	if straight_distance <= 50.0:
		return true

	var path: PackedVector2Array = NavigationServer2D.map_get_path(nav_map, enemy.global_position, target, true)
	if path.size() < 2:
		if enemy.has_method("_log_debug"):
			enemy._log_debug("Flank path missing between %s and %s" % [enemy.global_position, target])
		return false

	var path_distance := 0.0
	for i in range(1, path.size()):
		path_distance += path[i - 1].distance_to(path[i])

	if path_distance <= 0.0:
		return false
	if path_distance > straight_distance * 3.0 and path_distance > 500.0:
		if enemy.has_method("_log_debug"):
			enemy._log_debug("Flank path too long: %.0f vs straight %.0f" % [path_distance, straight_distance])
		return false
	return true


static func calculate_flank_timeout(enemy: Node2D, nav_agent: NavigationAgent2D, target: Vector2, move_speed: float, minimum_timeout: float) -> float:
	var path_distance := get_navigation_path_distance(enemy, nav_agent, target)
	if path_distance <= 0.0:
		return minimum_timeout
	var travel_time := path_distance / maxf(move_speed, 1.0)
	return clampf(travel_time + 2.0, minimum_timeout, 12.0)


static func get_navigation_path_distance(enemy: Node2D, nav_agent: NavigationAgent2D, target: Vector2) -> float:
	if nav_agent == null:
		return 0.0
	var nav_map := nav_agent.get_navigation_map()
	if not nav_map.is_valid():
		return 0.0
	var path: PackedVector2Array = NavigationServer2D.map_get_path(nav_map, enemy.global_position, target, true)
	if path.size() < 2:
		return 0.0
	var path_distance := 0.0
	for i in range(1, path.size()):
		path_distance += path[i - 1].distance_to(path[i])
	return path_distance


static func calculate_flank_target(enemy: Node2D, player: Node2D, nav_agent: NavigationAgent2D, flank_angle: float, flank_side: float, flank_distance: float) -> Vector2:
	if player == null:
		return Vector2.ZERO
	var raw_target := player.global_position + (enemy.global_position - player.global_position).normalized().rotated(flank_angle * flank_side) * flank_distance
	return get_flank_nav_position(nav_agent, raw_target)


static func choose_best_flank_side(enemy: Node2D, player: Node2D, nav_agent: NavigationAgent2D, flank_angle: float, flank_distance: float, flashlight_detection, raycast) -> float:
	if player == null:
		return 1.0 if randf() > 0.5 else -1.0

	var player_pos := player.global_position
	var player_to_enemy := (enemy.global_position - player_pos).normalized()
	var right_flank_dir := player_to_enemy.rotated(flank_angle)
	var left_flank_dir := player_to_enemy.rotated(-flank_angle)
	var right_flank_pos := get_flank_nav_position(nav_agent, player_pos + right_flank_dir * flank_distance)
	var left_flank_pos := get_flank_nav_position(nav_agent, player_pos + left_flank_dir * flank_distance)
	var right_path_clear := is_candidate_flank_position_valid(enemy, nav_agent, right_flank_pos, player_pos)
	var left_path_clear := is_candidate_flank_position_valid(enemy, nav_agent, left_flank_pos, player_pos)
	var right_has_los := right_path_clear and flank_position_has_los_to_player(enemy, right_flank_pos, player_pos)
	var left_has_los := left_path_clear and flank_position_has_los_to_player(enemy, left_flank_pos, player_pos)

	if right_has_los and not left_has_los:
		return 1.0
	if left_has_los and not right_has_los:
		return -1.0

	if right_has_los and left_has_los and flashlight_detection and player:
		var right_lit: bool = flashlight_detection.is_position_lit(right_flank_pos, player, raycast)
		var left_lit: bool = flashlight_detection.is_position_lit(left_flank_pos, player, raycast)
		if right_lit and not left_lit:
			_log_to_file(enemy, "[#574] Choosing left flank - right side lit by flashlight")
			return -1.0
		if left_lit and not right_lit:
			_log_to_file(enemy, "[#574] Choosing right flank - left side lit by flashlight")
			return 1.0

	if not right_has_los and not left_has_los:
		if right_path_clear and not left_path_clear:
			return 1.0
		if left_path_clear and not right_path_clear:
			return -1.0

		var reduced_distance := flank_distance * 0.5
		var reduced_right := get_flank_nav_position(nav_agent, player_pos + right_flank_dir * reduced_distance)
		var reduced_left := get_flank_nav_position(nav_agent, player_pos + left_flank_dir * reduced_distance)
		var reduced_right_path_clear := is_candidate_flank_position_valid(enemy, nav_agent, reduced_right, player_pos)
		var reduced_left_path_clear := is_candidate_flank_position_valid(enemy, nav_agent, reduced_left, player_pos)
		var reduced_right_has_los := reduced_right_path_clear and flank_position_has_los_to_player(enemy, reduced_right, player_pos)
		var reduced_left_has_los := reduced_left_path_clear and flank_position_has_los_to_player(enemy, reduced_left, player_pos)
		if reduced_right_has_los and not reduced_left_has_los:
			return 1.0
		if reduced_left_has_los and not reduced_right_has_los:
			return -1.0
		if reduced_right_path_clear and not reduced_left_path_clear:
			return 1.0
		if reduced_left_path_clear and not reduced_right_path_clear:
			return -1.0
		if right_path_clear or left_path_clear or reduced_right_path_clear or reduced_left_path_clear:
			_log_to_file(enemy, "Warning: No LOS-positive flank position, falling back to nav-reachable side")
		else:
			_log_to_file(enemy, "Warning: No valid flank position (both sides behind walls)")

	return 1.0 if enemy.global_position.distance_squared_to(right_flank_pos) < enemy.global_position.distance_squared_to(left_flank_pos) else -1.0


static func flank_position_has_los_to_player(enemy: Node2D, flank_pos: Vector2, player_pos: Vector2) -> bool:
	var world_2d := enemy.get_world_2d()
	if world_2d == null:
		return true
	var query := PhysicsRayQueryParameters2D.create(flank_pos, player_pos)
	query.collision_mask = 0b100
	return world_2d.direct_space_state.intersect_ray(query).is_empty()


static func _log_to_file(enemy: Node2D, message: String) -> void:
	if enemy.has_method("_log_to_file"):
		enemy._log_to_file(message)
