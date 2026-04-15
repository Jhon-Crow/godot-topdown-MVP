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

	var previous_target := nav_agent.target_position
	nav_agent.target_position = target

	if nav_agent.is_navigation_finished():
		var distance := enemy.global_position.distance_to(target)
		nav_agent.target_position = previous_target
		return distance <= 50.0

	var path_distance := nav_agent.distance_to_target()
	var straight_distance := enemy.global_position.distance_to(target)
	nav_agent.target_position = previous_target

	if path_distance <= 0.0:
		return false
	if path_distance > straight_distance * 3.0 and path_distance > 500.0:
		if enemy.has_method("_log_debug"):
			enemy._log_debug("Flank path too long: %.0f vs straight %.0f" % [path_distance, straight_distance])
		return false
	return true
