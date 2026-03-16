class_name BffTargetingComponent
extends RefCounted
## Handles detection and targeting of the BFF companion for enemy AI (Issue #934).
##
## Enemies should treat the BFF companion as a secondary threat target,
## attacking it when the companion is visible or closer than the main player.
## This component extracts companion-targeting logic from enemy.gd to keep
## that file within the CI line-count limit.

## Whether the companion is currently visible to the enemy.
var can_see_companion: bool = false

## The BFF companion node (null if not present).
var companion: Node2D = null

## The best current target: player or companion, whichever is more accessible.
var current_target: Node2D = null

## Parent enemy node (set on creation).
var _parent: Node2D = null


func _init(parent: Node2D) -> void:
	_parent = parent


## Find alive BFF companion in the scene tree.
## Called each physics frame to keep the reference valid.
func find_companion() -> void:
	if _parent == null:
		companion = null
		return
	var companions: Array = _parent.get_tree().get_nodes_in_group("bff_companions")
	for c in companions:
		if c == _parent:
			continue
		if is_instance_valid(c) and c.get("_is_alive") != false:
			companion = c as Node2D
			return
	companion = null


## Check if the BFF companion is visible to the parent enemy.
## Uses the parent's FOV, detection range, and raycast LOS checks.
##
## Parameters:
## - is_blinded: whether the parent enemy is blinded
## - confusion_timer: memory reset confusion timer (blocks visibility when > 0)
## - detection_range: enemy detection range (0 = unlimited)
## - raycast: parent enemy's RayCast2D for LOS checks
## - get_check_points_fn: Callable(Vector2) -> Array[Vector2] — returns check points on a target
## - is_visible_fn: Callable(Vector2) -> bool — returns true if a point has LOS
## - is_in_fov_fn: Callable(Vector2) -> bool — returns true if position is in FOV
func check_visibility(
		is_blinded: bool,
		confusion_timer: float,
		detection_range: float,
		raycast: Node,
		get_check_points_fn: Callable,
		is_visible_fn: Callable,
		is_in_fov_fn: Callable) -> void:
	can_see_companion = false

	if companion == null or not is_instance_valid(companion):
		return
	if is_blinded or confusion_timer > 0.0:
		return
	if raycast == null:
		return
	if companion.get("_is_alive") == false:
		return

	var dist := _parent.global_position.distance_to(companion.global_position)
	if detection_range > 0 and dist > detection_range:
		return
	if not is_in_fov_fn.call(companion.global_position):
		return

	var check_points: Array = get_check_points_fn.call(companion.global_position)
	for point in check_points:
		if is_visible_fn.call(point):
			can_see_companion = true
			return


## Select the best target between player and companion.
## Prefers the visible target; if both visible, picks the closer one.
##
## Parameters:
## - player: the main player node (may be null)
## - can_see_player: whether the parent can currently see the player
func select_best_target(player: Node2D, can_see_player: bool) -> void:
	var has_player := player != null and can_see_player
	var has_companion := companion != null and can_see_companion

	if not has_player and not has_companion:
		current_target = player  # Fall back to player for memory-based pursuit
		return

	if has_player and not has_companion:
		current_target = player
		return

	if has_companion and not has_player:
		current_target = companion
		return

	# Both visible — pick the closer one
	var dist_player := _parent.global_position.distance_to(player.global_position)
	var dist_companion := _parent.global_position.distance_to(companion.global_position)
	current_target = companion if dist_companion < dist_player else player
