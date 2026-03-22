class_name CombatPathComponent
extends Node
## Pre-defined combat path registry for a level.
##
## Levels can add AttackingPath and RetreatPath child nodes (Node2D with Marker2D children)
## to this component. Enemies in combat states query it to get the nearest pre-authored
## waypoint instead of performing expensive runtime raycast cover searches.
##
## Usage in a level scene:
##   - Add a CombatPathComponent node as a child of the level root.
##   - Add child nodes named "AttackingPaths" and "RetreatPaths" (Node2D).
##   - Each is a Node2D whose children are Marker2D waypoints.
##
## Enemies call get_nearest_attacking_waypoint() / get_nearest_retreat_waypoint()
## when entering combat movement states.

## All registered attacking waypoints (advance toward player).
var _attacking_waypoints: Array[Vector2] = []

## All registered retreat waypoints (fall back from player).
var _retreat_waypoints: Array[Vector2] = []

## Whether any paths were registered.
var has_paths: bool = false


func _ready() -> void:
	add_to_group("combat_path_components")
	_collect_paths()


## Collect waypoints from AttackingPaths and RetreatPaths child groups.
func _collect_paths() -> void:
	_attacking_waypoints.clear()
	_retreat_waypoints.clear()

	var attacking_root := get_node_or_null("AttackingPaths")
	if attacking_root:
		for child in attacking_root.get_children():
			_collect_markers_from(child, _attacking_waypoints)

	var retreat_root := get_node_or_null("RetreatPaths")
	if retreat_root:
		for child in retreat_root.get_children():
			_collect_markers_from(child, _retreat_waypoints)

	has_paths = _attacking_waypoints.size() > 0 or _retreat_waypoints.size() > 0

	if has_paths:
		print("[CombatPathComponent] Registered %d attacking + %d retreat waypoints." % [
			_attacking_waypoints.size(), _retreat_waypoints.size()
		])


## Collect all Marker2D positions from a node and its children.
func _collect_markers_from(node: Node, out: Array[Vector2]) -> void:
	if node is Marker2D:
		out.append((node as Marker2D).global_position)
	for child in node.get_children():
		_collect_markers_from(child, out)


## Maximum straight-line distance for the corner-escape fallback waypoint.
## Keeps the fallback local so enemies don't navigate across rooms to escape corners.
const FALLBACK_MAX_DIST: float = 350.0

## Maximum straight-line travel distance to a candidate waypoint.
## Prevents enemies from being routed to waypoints in other rooms that are
## reachable on the scoring map but blocked by walls on the nav mesh.
## E.g., corridor enemies (x≈1200) must not route to Security Room (x≈620)
## through Room2_WallRight (x=912–936, no doorway, nav-mesh impassable).
const MAX_TRAVEL_DIST: float = 400.0

## Return the nearest attacking waypoint that makes progress toward [toward_pos].
## [from_pos] is the enemy's current position.
## Returns Vector2.ZERO if no suitable waypoint exists.
##
## When no waypoint is strictly closer to the target than the enemy (enemy already
## very close, or cornered near the target), falls back to the nearest waypoint
## within FALLBACK_MAX_DIST so the enemy can escape corners without crossing rooms.
func get_nearest_attacking_waypoint(from_pos: Vector2, toward_pos: Vector2) -> Vector2:
	if _attacking_waypoints.is_empty():
		return Vector2.ZERO

	var my_dist_to_target := from_pos.distance_to(toward_pos)
	var best := Vector2.ZERO
	var best_score := -INF
	# Fallback: closest nearby waypoint (corner-escape only, capped by FALLBACK_MAX_DIST)
	var nearest_fallback := Vector2.ZERO
	var nearest_fallback_dist := INF

	for wp in _attacking_waypoints:
		var dist_from_me := from_pos.distance_to(wp)
		# Skip waypoints that are essentially where we already are
		if dist_from_me < 20.0:
			continue
		# Track the raw-nearest nearby waypoint as a local fallback
		if dist_from_me < nearest_fallback_dist and dist_from_me <= FALLBACK_MAX_DIST:
			nearest_fallback_dist = dist_from_me
			nearest_fallback = wp
		# Skip waypoints that are too far away; they likely require navigating around
		# walls that make the straight-line score misleading (cross-room false positives).
		if dist_from_me > MAX_TRAVEL_DIST:
			continue
		var wp_dist_to_target := wp.distance_to(toward_pos)
		# Only score waypoints that bring us closer to the target
		if wp_dist_to_target >= my_dist_to_target:
			continue
		# Score: progress toward target, penalise travel distance.
		# Penalty 0.5 lets same-room advances score positively while avoiding
		# borderline cross-room waypoints that require long detours around walls.
		var progress := my_dist_to_target - wp_dist_to_target
		var score := progress - dist_from_me * 0.5
		if score > best_score:
			best_score = score
			best = wp

	# If no progress waypoint found, use the nearest local one as a corner-escape anchor
	if best == Vector2.ZERO:
		return nearest_fallback
	return best


## Return the nearest retreat waypoint that creates distance from [away_from_pos].
## [from_pos] is the enemy's current position.
## Returns Vector2.ZERO if no suitable waypoint exists.
func get_nearest_retreat_waypoint(from_pos: Vector2, away_from_pos: Vector2) -> Vector2:
	if _retreat_waypoints.is_empty():
		return Vector2.ZERO

	var my_dist_from_threat := from_pos.distance_to(away_from_pos)
	var best := Vector2.ZERO
	var best_score := -INF

	for wp in _retreat_waypoints:
		var wp_dist_from_threat := wp.distance_to(away_from_pos)
		# Only consider waypoints that put more distance between us and the threat
		if wp_dist_from_threat <= my_dist_from_threat:
			continue
		var dist_from_me := from_pos.distance_to(wp)
		# Skip waypoints that are essentially where we already are
		if dist_from_me < 20.0:
			continue
		# Score: extra safety distance, penalise travel cost
		var safety_gain := wp_dist_from_threat - my_dist_from_threat
		var score := safety_gain - dist_from_me * 0.3
		if score > best_score:
			best_score = score
			best = wp

	return best
