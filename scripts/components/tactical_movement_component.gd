class_name TacticalMovementComponent
extends RefCounted
## Tactical movement coordination for enemies in narrow passages (Issue #1249).
##
## When multiple enemies try to pass through a narrow passage simultaneously,
## they push and jostle each other. This component detects when the path to a
## target is blocked by an ally and makes the enemy yield tactically:
## - The enemy closest to the player has priority and passes first.
## - Others wait at a nearby cover position (or in place if no cover is found).
## - After YIELD_MAX_WAIT_TIME seconds, the yield expires and the enemy forces
##   through regardless (prevents permanent deadlock).
##
## Usage:
##   In enemy._ready(): _tactical_movement = TacticalMovementComponent.new(self)
##   In _move_to_target_nav() before applying velocity:
##     if _tactical_movement.check_and_yield(target_pos, speed, delta): return true


## Distance within which an ally ahead of us counts as "blocking the path".
## Increased from 80 → 100 px to detect blockers a bit earlier (#1249).
const ALLY_BLOCK_DETECTION_RANGE: float = 100.0

## Half-width threshold: if both walls are closer than this, it's a narrow passage (px).
## Increased from 44 → 64 so corridor bottlenecks wider than 88 px are also detected (#1249).
const NARROW_PASSAGE_HALF_WIDTH: float = 64.0

## How long to yield before forcing through (seconds).
const YIELD_MAX_WAIT_TIME: float = 3.0

## Minimum time between successive yield checks to avoid flickering (seconds).
const YIELD_COOLDOWN: float = 0.5

## Distance we search for a lateral cover position to wait at while yielding.
const YIELD_COVER_SEARCH_RADIUS: float = 150.0

## Whether this enemy is currently yielding to another.
var is_yielding: bool = false

## How long we have been yielding so far.
var yield_timer: float = 0.0

## Cooldown timer: prevents re-checking immediately after a yield ends.
var yield_cooldown_timer: float = 0.0

## Lateral cover position to wait at while yielding (Vector2.ZERO = wait in place).
var yield_cover_position: Vector2 = Vector2.ZERO

## Reference to the enemy node this component belongs to.
var enemy: Node2D = null


func _init(enemy_ref: Node2D) -> void:
	enemy = enemy_ref


## Main entry point. Call this from enemy movement logic before applying velocity.
##
## Returns true if the enemy should yield this frame (caller should zero velocity
## or move toward yield_cover_position instead of the main target).
## Returns false if the enemy should proceed normally toward the target.
func check_and_yield(target_pos: Vector2, _speed: float, delta: float) -> bool:
	if enemy == null or not is_instance_valid(enemy):
		return false

	# Tick cooldown after a yield ends.
	if yield_cooldown_timer > 0.0:
		yield_cooldown_timer -= delta
		if yield_cooldown_timer < 0.0:
			yield_cooldown_timer = 0.0

	# If currently yielding, advance timer and check if we should stop.
	if is_yielding:
		yield_timer += delta
		if yield_timer >= YIELD_MAX_WAIT_TIME:
			# Yield timeout — force through regardless.
			reset_yield()
			return false
		# Still yielding this frame.
		return true

	# Not currently yielding. Check if we should start yielding.
	if yield_cooldown_timer > 0.0:
		return false

	# Only check when moving toward a target (avoid checking when idle/in cover).
	if target_pos == Vector2.ZERO:
		return false

	var move_dir: Vector2 = (target_pos - enemy.global_position).normalized()
	if move_dir == Vector2.ZERO:
		return false

	# Check: is the path ahead narrow AND an ally is blocking it?
	if _is_path_through_narrow_passage(move_dir) and _is_ally_blocking_path(move_dir):
		# Check priority: yield only if there is a closer ally to the player.
		if _should_yield_to_closer_ally():
			_start_yield()
			return true

	return false


## Reset yield state (used when yield expires or conditions change).
func reset_yield() -> void:
	is_yielding = false
	yield_timer = 0.0
	yield_cover_position = Vector2.ZERO
	yield_cooldown_timer = YIELD_COOLDOWN


## Get the lateral cover position to move to while yielding.
## Returns Vector2.ZERO if no lateral cover was found (enemy should wait in place).
func get_yield_position() -> Vector2:
	return yield_cover_position


## Returns true if both perpendicular sides of the movement direction are close to walls,
## indicating that the path ahead goes through a narrow passage.
func _is_path_through_narrow_passage(move_dir: Vector2) -> bool:
	if enemy == null:
		return false
	var space_state: PhysicsDirectSpaceState2D = enemy.get_world_2d().direct_space_state
	var perpendicular: Vector2 = move_dir.rotated(PI / 2.0)
	var check_from: Vector2 = enemy.global_position + move_dir * 30.0  # Check a bit ahead

	# Cast left and right of the movement direction.
	for side: float in [-1.0, 1.0]:
		var ray_to: Vector2 = check_from + perpendicular * side * NARROW_PASSAGE_HALF_WIDTH
		var query := PhysicsRayQueryParameters2D.create(check_from, ray_to)
		query.collision_mask = 4  # Obstacles layer only
		query.exclude = [enemy.get_rid()]
		var result: Dictionary = space_state.intersect_ray(query)
		if result.is_empty():
			return false  # Open on at least one side → not narrow

	return true  # Both sides have walls within NARROW_PASSAGE_HALF_WIDTH


## Returns true if an ally enemy is within ALLY_BLOCK_DETECTION_RANGE directly ahead.
func _is_ally_blocking_path(move_dir: Vector2) -> bool:
	if enemy == null:
		return false
	var space_state: PhysicsDirectSpaceState2D = enemy.get_world_2d().direct_space_state
	var ray_to: Vector2 = enemy.global_position + move_dir * ALLY_BLOCK_DETECTION_RANGE
	var query := PhysicsRayQueryParameters2D.create(enemy.global_position, ray_to)
	query.collision_mask = 2  # Enemy bodies layer
	query.exclude = [enemy.get_rid()]
	var result: Dictionary = space_state.intersect_ray(query)
	if result.is_empty():
		return false
	# Confirm the hit body is actually an enemy (in "enemies" group).
	var hit_body: Object = result.get("collider")
	if hit_body != null and is_instance_valid(hit_body) and (hit_body as Node).is_in_group("enemies"):
		return true
	return false


## Maximum distance (px) within which an ally can trigger a yield.
## Only enemies within this range can cause a passage conflict — enemies in other rooms must not.
const YIELD_NEARBY_RADIUS: float = 200.0

## Returns true if there is a NEARBY ally enemy that is closer to the player than we are.
## "Nearby" means within YIELD_NEARBY_RADIUS — allies in other rooms are ignored.
## That nearby ally has priority to pass through the narrow passage first.
func _should_yield_to_closer_ally() -> bool:
	if enemy == null:
		return false
	var player: Node2D = enemy.get("_player")
	if player == null or not is_instance_valid(player):
		return false

	var my_dist: float = enemy.global_position.distance_to(player.global_position)

	for body: Node in enemy.get_tree().get_nodes_in_group("enemies"):
		if body == enemy or not is_instance_valid(body):
			continue
		# Only consider allies that are close enough to share the same passage.
		var ally_pos: Vector2 = (body as Node2D).global_position
		if enemy.global_position.distance_to(ally_pos) > YIELD_NEARBY_RADIUS:
			continue  # Ally is in a different area — skip
		var ally_dist: float = ally_pos.distance_to(player.global_position)
		if ally_dist < my_dist - 20.0:  # 20px hysteresis to prevent flickering
			return true  # A nearby ally is closer → we yield

	return false


## Start the yield state. Searches for a lateral position to wait at.
func _start_yield() -> void:
	is_yielding = true
	yield_timer = 0.0
	yield_cover_position = _find_lateral_wait_position()


## Search for a nearby lateral position (to the side of the current path) where
## the enemy can wait without blocking the narrow passage.
## Returns Vector2.ZERO if no suitable position is found.
func _find_lateral_wait_position() -> Vector2:
	if enemy == null:
		return Vector2.ZERO

	var space_state: PhysicsDirectSpaceState2D = enemy.get_world_2d().direct_space_state

	# Try 8 directions, favouring perpendicular ones (away from forward).
	var best_pos: Vector2 = Vector2.ZERO
	var best_dist: float = 0.0

	for i: int in range(8):
		var angle: float = i * (PI / 4.0)
		var dir: Vector2 = Vector2.RIGHT.rotated(angle)
		var candidate: Vector2 = enemy.global_position + dir * YIELD_COVER_SEARCH_RADIUS

		# Check that this direction is not through a wall.
		var query := PhysicsRayQueryParameters2D.create(enemy.global_position, candidate)
		query.collision_mask = 4  # Obstacles only
		query.exclude = [enemy.get_rid()]
		var result: Dictionary = space_state.intersect_ray(query)

		var reachable_pos: Vector2
		if result.is_empty():
			reachable_pos = candidate  # Full distance is clear
		else:
			# Only go up to the wall; need some minimum clearance.
			var wall_dist: float = enemy.global_position.distance_to(result["position"])
			if wall_dist < 40.0:
				continue  # Too close to wall in this direction
			reachable_pos = enemy.global_position + dir * (wall_dist - 32.0)

		# Prefer positions that are more lateral (perpendicular to forward movement).
		# Use distance from starting point as a tiebreaker.
		var lateral_dist: float = enemy.global_position.distance_to(reachable_pos)
		if lateral_dist > best_dist:
			best_dist = lateral_dist
			best_pos = reachable_pos

	return best_pos


## Get a debug string summarising the current state (for debug labels).
func get_debug_info() -> String:
	if not is_yielding:
		return ""
	return "YIELDING %.1fs/%.1fs" % [yield_timer, YIELD_MAX_WAIT_TIME]
