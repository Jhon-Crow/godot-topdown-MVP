class_name TacticalGroupComponent
extends RefCounted
## Tactical group movement for enemies within 500 px (Issue #1287).
##
## When multiple enemies are within GROUP_RADIUS (500 px) of the player they
## form a temporary "tactical group" and coordinate their approach so they
## encircle the player instead of all rushing from the same direction.
##
## Algorithm:
##   1. Once per UPDATE_INTERVAL seconds an enemy queries all allies within
##      GROUP_RADIUS.  If at least MIN_GROUP_SIZE allies are found, a group is
##      recognised and each member is assigned an angular "slot" evenly spread
##      around the player (e.g. 3 enemies → 0°, 120°, 240°).
##   2. Each enemy is assigned the slot whose current angle is closest to its
##      own angle relative to the player.  The assigned slot gives an
##      "approach offset" vector: the enemy should aim for a position
##      APPROACH_DISTANCE pixels from the player in its slot direction.
##   3. When the enemy is already within CLOSE_RANGE of the player (combat
##      range), no offset is applied — the enemy engages normally.
##   4. The component is stateless between frames beyond caching: all slot
##      assignments are recomputed every UPDATE_INTERVAL seconds.
##
## Usage:
##   In enemy._ready():
##     _tactical_group = TacticalGroupComponent.new(self)
##   In the PURSUING / COMBAT movement target calculation:
##     var adjusted := _tactical_group.get_adjusted_target(player_pos)
##     # use adjusted instead of player_pos for _move_to_target_nav()

## Radius within which enemies unite into a tactical group (px).
const GROUP_RADIUS: float = 500.0

## Minimum number of allies (including self) to form a group.
const MIN_GROUP_SIZE: int = 2

## How far from the player the approach offset target is placed (px).
## Enemies orbit to this radius before closing in — keeps them from
## all running through the same spot.
const APPROACH_DISTANCE: float = 160.0

## Within this radius of the player the offset is blended out so the
## enemy can actually engage the target.
const CLOSE_RANGE: float = 80.0

## How often (seconds) to recompute the group assignment.
const UPDATE_INTERVAL: float = 0.4

## Reference to the owning enemy node.
var enemy: Node2D = null

## Assigned angle (radians) around the player for this enemy's slot.
## Set to NAN when no group is active.
var _assigned_angle: float = NAN

## Countdown timer for the next group update.
var _update_timer: float = 0.0

## Whether the group feature is currently active (controlled by ExperimentalSettings).
var _enabled: bool = true


func _init(enemy_ref: Node2D) -> void:
	enemy = enemy_ref


## Main entry point.  Call this before computing the navigation target.
##
## Returns an adjusted target position:
##   - When a group is active and the enemy is not yet in close range, the
##     returned position is offset from player_pos in this enemy's assigned
##     direction so enemies spread out around the player.
##   - Otherwise returns player_pos unchanged.
func get_adjusted_target(player_pos: Vector2, delta: float) -> Vector2:
	if enemy == null or not is_instance_valid(enemy):
		return player_pos

	if not _is_feature_enabled():
		_assigned_angle = NAN
		return player_pos

	# Tick the update timer.
	_update_timer -= delta
	if _update_timer <= 0.0:
		_update_timer = UPDATE_INTERVAL
		_recompute_group(player_pos)

	if is_nan(_assigned_angle):
		return player_pos

	# Within close range — blend offset to zero so the enemy can engage.
	var dist: float = enemy.global_position.distance_to(player_pos)
	if dist <= CLOSE_RANGE:
		return player_pos

	# Build the offset approach position.
	var offset_dir: Vector2 = Vector2.from_angle(_assigned_angle)
	var approach_pos: Vector2 = player_pos + offset_dir * APPROACH_DISTANCE

	# Blend: as the enemy enters the close range transition zone, reduce the
	# offset so movement feels smooth rather than snapping to player_pos.
	var blend: float = clampf((dist - CLOSE_RANGE) / APPROACH_DISTANCE, 0.0, 1.0)
	return player_pos.lerp(approach_pos, blend)


## Recompute slot assignment for this enemy.
func _recompute_group(player_pos: Vector2) -> void:
	if enemy == null:
		return

	# Collect all alive enemies (including self) within GROUP_RADIUS.
	var group_members: Array[Node2D] = []
	for node: Node in enemy.get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(node):
			continue
		var e: Node2D = node as Node2D
		if e == null:
			continue
		# Only include enemies that are aware of / pursuing the player.
		if not _is_enemy_active(e):
			continue
		if e.global_position.distance_to(player_pos) <= GROUP_RADIUS:
			group_members.append(e)

	if group_members.size() < MIN_GROUP_SIZE:
		# Not enough nearby enemies — deactivate grouping.
		_assigned_angle = NAN
		return

	# Sort members by their instance ID for a stable, deterministic order.
	group_members.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		return a.get_instance_id() < b.get_instance_id())

	var n: int = group_members.size()

	# Each slot is evenly spaced around a full circle.
	var slot_angles: Array[float] = []
	for i: int in range(n):
		slot_angles.append((TAU * i) / n)

	# Find this enemy's position in the sorted list.
	var my_index: int = group_members.find(enemy)
	if my_index < 0:
		_assigned_angle = NAN
		return

	# Compute the "natural" angle of each enemy relative to the player.
	var enemy_angles: Array[float] = []
	for e: Node2D in group_members:
		enemy_angles.append((e.global_position - player_pos).angle())

	# Greedy best-slot assignment: assign each enemy to the slot whose angle
	# is closest to the enemy's current bearing, without repeating slots.
	# We do this from the perspective of all members so that each member's
	# slot is consistent across the group.
	var assigned_slots: Array[int] = []
	assigned_slots.resize(n)
	assigned_slots.fill(-1)
	var used_slots: Array[bool] = []
	used_slots.resize(n)
	used_slots.fill(false)

	for i: int in range(n):
		var best_slot: int = -1
		var best_diff: float = INF
		for s: int in range(n):
			if used_slots[s]:
				continue
			var diff: float = _angle_diff(enemy_angles[i], slot_angles[s])
			if diff < best_diff:
				best_diff = diff
				best_slot = s
		if best_slot >= 0:
			assigned_slots[i] = best_slot
			used_slots[best_slot] = true

	if assigned_slots[my_index] >= 0:
		_assigned_angle = slot_angles[assigned_slots[my_index]]
	else:
		_assigned_angle = NAN


## Returns the absolute angular difference between two angles (0..PI).
static func _angle_diff(a: float, b: float) -> float:
	var d: float = fmod(abs(a - b), TAU)
	return d if d <= PI else TAU - d


## Returns true if the enemy is in an active combat/pursuit state and eligible
## for group coordination.
func _is_enemy_active(e: Node2D) -> bool:
	if not e.has_method("get_current_state"):
		return false
	var state: int = int(e.get_current_state())
	# Include: COMBAT=1, SEEKING_COVER=2, IN_COVER=3, FLANKING=4, PURSUING=7,
	#          ASSAULT=8, SUPPRESSED=5, RETREATING=6
	return state in [1, 2, 3, 4, 5, 6, 7, 8]


## Returns true if the tactical group feature is enabled in ExperimentalSettings.
func _is_feature_enabled() -> bool:
	var es: Node = enemy.get_node_or_null("/root/ExperimentalSettings")
	if es == null:
		return true  # Default on when no settings node present
	if es.has_method("is_tactical_group_enabled"):
		return es.is_tactical_group_enabled()
	return true


## Get a debug string summarising the current state (for debug labels).
func get_debug_info() -> String:
	if is_nan(_assigned_angle):
		return ""
	return "GRP slot=%.0f°" % rad_to_deg(_assigned_angle)
