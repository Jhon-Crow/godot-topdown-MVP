class_name SquadCoordinatorComponent
extends RefCounted
## Squad coordination for enemies within 1000 px (Issue #1373).
##
## Enemies within SQUAD_RADIUS form a dynamic squad and coordinate as a team:
##   - Cover deconfliction: enemies claim cover positions so allies pick different spots.
##   - Firing lane awareness: enemies avoid crossing allies' lines of fire during movement.
##   - Suppressive fire coordination: when allies move, nearby enemies in cover keep firing.
##   - Role assignment (group GOAP): each squad member is assigned SUPPRESSOR / FLANKER /
##     RUSHER / HOLDER so the squad attacks from multiple angles simultaneously.
##   - Path coordination: minimum inter-enemy spacing enforced during movement.
##
## Inspired by F.E.A.R.'s two-layer AI (individual GOAP + squad behaviors).
## Implemented as a per-enemy RefCounted component (same pattern as TacticalGroupComponent).
##
## Usage:
##   In enemy._ready():
##     _squad_coordinator = SquadCoordinatorComponent.new(self)
##   In cover selection:
##     if _squad_coordinator.is_cover_claimed(cover_pos): skip
##     else: _squad_coordinator.claim_cover(cover_pos)
##   In movement:
##     target_pos = _squad_coordinator.get_coordinated_target(target_pos, delta)
##   In shooting decision:
##     if _squad_coordinator.should_provide_covering_fire(): keep shooting


## ──────────────────────────────────────────────────────────────────────────────
## Constants
## ──────────────────────────────────────────────────────────────────────────────

## Radius within which enemies form a squad (px). Issue #1373 requests 1000 px.
const SQUAD_RADIUS: float = 1000.0

## How often (seconds) to recompute the squad and role assignments.
const UPDATE_INTERVAL: float = 0.5

## Minimum group size to activate squad coordination (including self).
const MIN_SQUAD_SIZE: int = 2

## Minimum distance between two cover claims to consider them "same position" (px).
const COVER_CLAIM_TOLERANCE: float = 80.0

## Minimum distance enemies maintain from each other during coordinated movement (px).
const MIN_INTER_ENEMY_DISTANCE: float = 120.0

## How far ahead to check for firing lane crossings (px).
const FIRING_LANE_CHECK_DISTANCE: float = 300.0

## Half-width of the firing lane danger zone (px).
const FIRING_LANE_HALF_WIDTH: float = 40.0

## Cover claim expiry time — claims older than this are released (seconds).
const COVER_CLAIM_EXPIRY: float = 5.0


## ──────────────────────────────────────────────────────────────────────────────
## Squad Roles (group GOAP output)
## ──────────────────────────────────────────────────────────────────────────────

## Roles assigned to each squad member for coordinated behavior.
enum SquadRole {
	NONE,        ## No squad active
	SUPPRESSOR,  ## Stay in cover, keep firing to pin the player
	FLANKER,     ## Move to flank position (side/rear of player)
	RUSHER,      ## Close distance aggressively
	HOLDER       ## Hold current position, wait for opportunity
}


## ──────────────────────────────────────────────────────────────────────────────
## State
## ──────────────────────────────────────────────────────────────────────────────

## Reference to the owning enemy node.
var enemy: Node2D = null

## Current squad members (including self). Refreshed every UPDATE_INTERVAL.
var _squad_members: Array[Node2D] = []

## This enemy's assigned role in the squad.
var current_role: SquadRole = SquadRole.NONE

## Countdown timer for the next squad update.
var _update_timer: float = 0.0

## Cover position this enemy has claimed (Vector2.INF = no claim).
var _claimed_cover: Vector2 = Vector2.INF

## Timestamp when cover was claimed (for expiry).
var _cover_claim_time: float = 0.0

## Whether the squad feature is currently active.
var _enabled: bool = true


## ──────────────────────────────────────────────────────────────────────────────
## Lifecycle
## ──────────────────────────────────────────────────────────────────────────────

func _init(enemy_ref: Node2D) -> void:
	enemy = enemy_ref


## ──────────────────────────────────────────────────────────────────────────────
## Cover Deconfliction
## ──────────────────────────────────────────────────────────────────────────────

## Check if a candidate cover position is already claimed by a squad mate.
## Returns true if the position is claimed (caller should skip this cover).
func is_cover_claimed(cover_pos: Vector2) -> bool:
	if not _enabled or enemy == null:
		return false

	for node: Node in enemy.get_tree().get_nodes_in_group("enemies"):
		if node == enemy or not is_instance_valid(node):
			continue
		var e: Node2D = node as Node2D
		if e == null:
			continue
		# Only check enemies within squad radius.
		if e.global_position.distance_to(enemy.global_position) > SQUAD_RADIUS:
			continue
		# Check if this enemy has a squad coordinator with an active claim.
		if not e.has_method("get_squad_claimed_cover"):
			continue
		var claimed: Vector2 = e.get_squad_claimed_cover()
		if claimed == Vector2.INF:
			continue
		if cover_pos.distance_to(claimed) < COVER_CLAIM_TOLERANCE:
			return true  # Already claimed by a squad mate

	return false


## Claim a cover position for this enemy.
func claim_cover(cover_pos: Vector2) -> void:
	_claimed_cover = cover_pos
	_cover_claim_time = _get_time()


## Release the current cover claim.
func release_cover() -> void:
	_claimed_cover = Vector2.INF


## Get the currently claimed cover position (Vector2.INF = no claim).
func get_claimed_cover() -> Vector2:
	# Expire stale claims.
	if _claimed_cover != Vector2.INF and (_get_time() - _cover_claim_time) > COVER_CLAIM_EXPIRY:
		_claimed_cover = Vector2.INF
	return _claimed_cover


## ──────────────────────────────────────────────────────────────────────────────
## Firing Lane Awareness
## ──────────────────────────────────────────────────────────────────────────────

## Check if a target movement position would cross a squad mate's firing lane.
## Returns true if the position is dangerous (ally is shooting through that area).
func is_in_ally_firing_lane(position: Vector2) -> bool:
	if not _enabled or enemy == null:
		return false

	for node: Node in enemy.get_tree().get_nodes_in_group("enemies"):
		if node == enemy or not is_instance_valid(node):
			continue
		var e: Node2D = node as Node2D
		if e == null:
			continue
		if e.global_position.distance_to(enemy.global_position) > SQUAD_RADIUS:
			continue
		# Check if the ally is currently shooting (in COMBAT state and can see target).
		if not e.has_method("is_actively_shooting"):
			continue
		if not e.is_actively_shooting():
			continue
		# Get ally's firing direction.
		if not e.has_method("get_firing_direction"):
			continue
		var fire_dir: Vector2 = e.get_firing_direction()
		if fire_dir == Vector2.ZERO:
			continue
		# Check if our target position is within the firing lane.
		var ally_pos: Vector2 = e.global_position
		var to_pos: Vector2 = position - ally_pos
		var along: float = to_pos.dot(fire_dir)
		if along < 0.0 or along > FIRING_LANE_CHECK_DISTANCE:
			continue  # Behind the shooter or too far
		var perp: float = abs(to_pos.dot(fire_dir.rotated(PI / 2.0)))
		if perp < FIRING_LANE_HALF_WIDTH:
			return true  # In the danger zone

	return false


## Compute a laterally adjusted position that avoids ally firing lanes.
## Returns the original position if it's safe, or a shifted position if not.
func avoid_firing_lanes(position: Vector2) -> Vector2:
	if not is_in_ally_firing_lane(position):
		return position
	# Try shifting left and right perpendicular to the direction of travel.
	var to_pos: Vector2 = (position - enemy.global_position).normalized()
	var perp: Vector2 = to_pos.rotated(PI / 2.0)
	var shift_left: Vector2 = position + perp * FIRING_LANE_HALF_WIDTH * 2.0
	var shift_right: Vector2 = position - perp * FIRING_LANE_HALF_WIDTH * 2.0
	# Pick whichever is safer.
	if not is_in_ally_firing_lane(shift_left):
		return shift_left
	if not is_in_ally_firing_lane(shift_right):
		return shift_right
	return position  # Both blocked — proceed anyway


## ──────────────────────────────────────────────────────────────────────────────
## Suppressive Fire Coordination
## ──────────────────────────────────────────────────────────────────────────────

## Returns true if this enemy should provide covering fire for moving allies.
## Condition: at least one squad mate is actively moving (PURSUING/FLANKING/ASSAULT)
## and this enemy is in a static state (IN_COVER/COMBAT with cover).
func should_provide_covering_fire() -> bool:
	if not _enabled or enemy == null:
		return false
	if current_role != SquadRole.SUPPRESSOR:
		return false
	# Check if any squad mate is actively moving toward the player.
	for member: Node2D in _squad_members:
		if member == enemy or not is_instance_valid(member):
			continue
		if not member.has_method("get_current_state"):
			continue
		var state: int = int(member.get_current_state())
		# PURSUING=7, FLANKING=4, ASSAULT=8
		if state in [4, 7, 8]:
			return true
	return false


## ──────────────────────────────────────────────────────────────────────────────
## Role Assignment (Group GOAP)
## ──────────────────────────────────────────────────────────────────────────────

## Main tick — call every physics frame. Recomputes squad at UPDATE_INTERVAL.
func tick(delta: float, player_pos: Vector2) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	if not _is_feature_enabled():
		current_role = SquadRole.NONE
		_squad_members.clear()
		return

	_update_timer -= delta
	if _update_timer <= 0.0:
		_update_timer = UPDATE_INTERVAL
		_recompute_squad(player_pos)


## Recompute squad membership and assign roles.
func _recompute_squad(player_pos: Vector2) -> void:
	_squad_members.clear()

	# Collect all alive, active enemies within SQUAD_RADIUS of THIS enemy.
	for node: Node in enemy.get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(node):
			continue
		var e: Node2D = node as Node2D
		if e == null:
			continue
		if not _is_enemy_active(e):
			continue
		if e.global_position.distance_to(enemy.global_position) <= SQUAD_RADIUS:
			_squad_members.append(e)

	if _squad_members.size() < MIN_SQUAD_SIZE:
		current_role = SquadRole.NONE
		return

	# Sort by instance ID for deterministic ordering.
	_squad_members.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		return a.get_instance_id() < b.get_instance_id())

	_assign_roles(player_pos)


## Assign roles to all squad members using a scoring system.
## Each enemy scores for each role; best-fit greedy assignment avoids duplicates.
func _assign_roles(player_pos: Vector2) -> void:
	var n: int = _squad_members.size()
	var my_index: int = _squad_members.find(enemy)
	if my_index < 0:
		current_role = SquadRole.NONE
		return

	# Build a score matrix: scores[member_idx][role] = fitness.
	# Higher = better fit for this role.
	var scores: Array = []  # Array[Array[float]]
	for i: int in range(n):
		var e: Node2D = _squad_members[i]
		scores.append(_score_roles(e, player_pos))

	# Available roles: distribute evenly, but at least 1 suppressor if squad ≥ 2.
	var role_pool: Array[SquadRole] = _build_role_pool(n)

	# Greedy assignment: iterate members in order, each picks their best available role.
	var assigned_roles: Array[SquadRole] = []
	assigned_roles.resize(n)
	for i_idx: int in range(n):
		assigned_roles[i_idx] = SquadRole.NONE
	var used_indices: Array[bool] = []
	used_indices.resize(role_pool.size())
	used_indices.fill(false)

	for i: int in range(n):
		var best_role_idx: int = -1
		var best_score: float = -INF
		for r: int in range(role_pool.size()):
			if used_indices[r]:
				continue
			var role: SquadRole = role_pool[r]
			var role_score: float = scores[i][role]
			if role_score > best_score:
				best_score = role_score
				best_role_idx = r
		if best_role_idx >= 0:
			assigned_roles[i] = role_pool[best_role_idx]
			used_indices[best_role_idx] = true

	current_role = assigned_roles[my_index]


## Score how well an enemy fits each role. Returns Array[float] indexed by SquadRole.
func _score_roles(e: Node2D, player_pos: Vector2) -> Array:
	var role_scores: Array = [0.0, 0.0, 0.0, 0.0, 0.0]  # NONE=0, SUPPRESSOR=1, FLANKER=2, RUSHER=3, HOLDER=4

	var dist: float = e.global_position.distance_to(player_pos)
	var angle_to_player: float = (player_pos - e.global_position).angle()

	# Get enemy state info.
	var state: int = -1
	if e.has_method("get_current_state"):
		state = int(e.get_current_state())
	var health_ratio: float = 1.0
	if e.has_method("get_health_ratio"):
		health_ratio = e.get_health_ratio()
	var has_cover: bool = false
	if e.has_method("has_valid_cover_position"):
		has_cover = e.has_valid_cover_position()
	var can_see_player: bool = false
	if e.has_method("can_see_player_now"):
		can_see_player = e.can_see_player_now()

	# SUPPRESSOR: prefers enemies that are in cover and can see the player.
	role_scores[SquadRole.SUPPRESSOR] = 0.0
	if has_cover:
		role_scores[SquadRole.SUPPRESSOR] += 3.0
	if can_see_player:
		role_scores[SquadRole.SUPPRESSOR] += 2.0
	if state in [3, 5]:  # IN_COVER=3, SUPPRESSED=5
		role_scores[SquadRole.SUPPRESSOR] += 2.0
	# Prefer enemies farther from player for suppression.
	role_scores[SquadRole.SUPPRESSOR] += clampf(dist / 500.0, 0.0, 2.0)

	# FLANKER: prefers enemies that are off to the side and have flanking capability.
	role_scores[SquadRole.FLANKER] = 0.0
	# Check angular offset from mean squad direction.
	var mean_angle: float = _compute_mean_angle_to_player(player_pos)
	var angle_diff: float = abs(angle_difference(angle_to_player, mean_angle))
	role_scores[SquadRole.FLANKER] += angle_diff * 2.0  # More offset = better flanker
	if state == 4:  # FLANKING
		role_scores[SquadRole.FLANKER] += 3.0
	if health_ratio > 0.5:
		role_scores[SquadRole.FLANKER] += 1.0

	# RUSHER: prefers enemies that are close, healthy, and aggressive.
	role_scores[SquadRole.RUSHER] = 0.0
	role_scores[SquadRole.RUSHER] += clampf((500.0 - dist) / 500.0, 0.0, 2.0)  # Closer = better
	role_scores[SquadRole.RUSHER] += health_ratio * 2.0
	if state in [1, 7, 8]:  # COMBAT=1, PURSUING=7, ASSAULT=8
		role_scores[SquadRole.RUSHER] += 2.0

	# HOLDER: prefers enemies in static states or low health.
	role_scores[SquadRole.HOLDER] = 0.0
	if state in [0, 2, 3, 6]:  # IDLE=0, SEEKING_COVER=2, IN_COVER=3, RETREATING=6
		role_scores[SquadRole.HOLDER] += 3.0
	role_scores[SquadRole.HOLDER] += (1.0 - health_ratio) * 2.0

	return role_scores


## Build a pool of roles to assign. Ensures balanced team composition.
func _build_role_pool(n: int) -> Array[SquadRole]:
	var pool: Array[SquadRole] = []
	if n <= 1:
		pool.append(SquadRole.RUSHER)
		return pool

	# At least 1 suppressor, 1 flanker. Fill rest with rushers/holders.
	pool.append(SquadRole.SUPPRESSOR)
	if n >= 3:
		pool.append(SquadRole.FLANKER)
	else:
		pool.append(SquadRole.RUSHER)

	# Additional members: alternate between rusher and suppressor.
	for i: int in range(2, n):
		if i % 3 == 0:
			pool.append(SquadRole.SUPPRESSOR)
		elif i % 3 == 1:
			pool.append(SquadRole.FLANKER)
		else:
			pool.append(SquadRole.RUSHER)

	return pool


## ──────────────────────────────────────────────────────────────────────────────
## Coordinated Movement
## ──────────────────────────────────────────────────────────────────────────────

## Adjust target position based on squad role and ally positions.
## Call this before navigation to prevent clustering and coordinate movement.
func get_coordinated_target(target_pos: Vector2, delta: float) -> Vector2:
	if not _enabled or enemy == null or current_role == SquadRole.NONE:
		return target_pos

	# Firing lane avoidance — shift target if it crosses an ally's LOF.
	target_pos = avoid_firing_lanes(target_pos)

	# Inter-enemy spacing: push target away from nearby squad mates.
	target_pos = _apply_squad_spacing(target_pos)

	return target_pos


## Push target position away from nearby squad mates to maintain spacing.
func _apply_squad_spacing(target_pos: Vector2) -> Vector2:
	if _squad_members.size() < 2:
		return target_pos

	var push: Vector2 = Vector2.ZERO
	var push_count: int = 0

	for member: Node2D in _squad_members:
		if member == enemy or not is_instance_valid(member):
			continue
		var diff: Vector2 = target_pos - member.global_position
		var dist: float = diff.length()
		if dist < MIN_INTER_ENEMY_DISTANCE and dist > 0.1:
			# Push target away from this squad mate.
			push += diff.normalized() * (MIN_INTER_ENEMY_DISTANCE - dist)
			push_count += 1

	if push_count > 0:
		target_pos += push / float(push_count)

	return target_pos


## ──────────────────────────────────────────────────────────────────────────────
## Helpers
## ──────────────────────────────────────────────────────────────────────────────

## Returns true if the enemy is in an active state eligible for squad coordination.
func _is_enemy_active(e: Node2D) -> bool:
	if not e.has_method("get_current_state"):
		return false
	if e.has_method("is_alive_enemy") and not e.is_alive_enemy():
		return false
	var state: int = int(e.get_current_state())
	# COMBAT=1, SEEKING_COVER=2, IN_COVER=3, FLANKING=4, SUPPRESSED=5,
	# RETREATING=6, PURSUING=7, ASSAULT=8
	return state in [1, 2, 3, 4, 5, 6, 7, 8]


## Compute the mean angle from all squad members to the player.
func _compute_mean_angle_to_player(player_pos: Vector2) -> float:
	var sin_sum: float = 0.0
	var cos_sum: float = 0.0
	for member: Node2D in _squad_members:
		if not is_instance_valid(member):
			continue
		var angle: float = (player_pos - member.global_position).angle()
		sin_sum += sin(angle)
		cos_sum += cos(angle)
	return atan2(sin_sum, cos_sum)


## Returns true if the squad feature is enabled in ExperimentalSettings.
func _is_feature_enabled() -> bool:
	if enemy == null:
		return false
	var es: Node = enemy.get_node_or_null("/root/ExperimentalSettings")
	if es == null:
		return true  # Default on when no settings node present
	if es.has_method("is_tactical_group_enabled"):
		return es.is_tactical_group_enabled()
	return true


## Get the current engine time (uses Time singleton).
func _get_time() -> float:
	return Time.get_ticks_msec() / 1000.0


## Get the number of active squad members (including self).
func get_squad_size() -> int:
	return _squad_members.size()


## Get a debug string summarising the current state (for debug labels).
func get_debug_info() -> String:
	if current_role == SquadRole.NONE:
		return ""
	var role_name: String = SquadRole.keys()[current_role]
	var cover_info: String = ""
	if _claimed_cover != Vector2.INF:
		cover_info = " cov=(%.0f,%.0f)" % [_claimed_cover.x, _claimed_cover.y]
	return "SQD %s [%d]%s" % [role_name, _squad_members.size(), cover_info]
