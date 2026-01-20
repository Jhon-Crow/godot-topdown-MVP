extends Node
## FlankSquadManager - Coordinates tactical flanking maneuvers when player stays in cover too long.
##
## This autoload singleton tracks the player's cover position and time spent there.
## When the player stays behind the same cover for 10+ seconds, it organizes nearby
## enemies into a coordinated flanking squad with specific tactical roles.
##
## Squad formation based on group size:
## - 1 enemy: LEAD_ATTACKER - flanks from below, aims at cover edges
## - 2 enemies: LEAD_ATTACKER + SUPPORTING (from below)
## - 3 enemies: 2 from below + UPPER_LEAD_ATTACKER from above
## - 4 enemies: Full teams - 2 below + 2 above (each with lead + support)

## Tactical roles for flanking squad members.
enum TacticalRole {
	NONE,              ## Not in a squad
	LEAD_ATTACKER,     ## Primary flanker, aims at cover corners
	SUPPORTING,        ## Stays behind lead, alternates aim between movement and cover
	UPPER_LEAD_ATTACKER,  ## Same as LEAD_ATTACKER but flanks from above
	UPPER_SUPPORTING   ## Same as SUPPORTING but with UPPER_LEAD_ATTACKER
}

## Flank direction for subgroups.
enum FlankDirection {
	LOWER,  ## Flanks from below (negative Y in Godot 2D)
	UPPER   ## Flanks from above (positive Y in Godot 2D)
}

## Current player cover tracking.
var _player_cover_position: Vector2 = Vector2.ZERO
var _player_cover_time: float = 0.0
var _player_last_position: Vector2 = Vector2.ZERO

## Active flanking squads (can have multiple if player moves between covers).
var _active_squad: Dictionary = {
	"members": [],  # Array of enemy nodes
	"target_cover": Vector2.ZERO,  # The cover being flanked
	"roles": {},  # Dictionary: enemy_id -> TacticalRole
	"subgroups": {},  # Dictionary: enemy_id -> FlankDirection
	"lower_ready": false,  # Whether lower subgroup reached sync position
	"upper_ready": false,  # Whether upper subgroup reached sync position
	"phase": "forming"  # "forming", "positioning", "flanking", "assaulting"
}

## Time threshold before coordinated flank is triggered (seconds).
const COVER_TIME_THRESHOLD: float = 10.0

## Distance threshold to consider player at "same" cover (pixels).
const COVER_POSITION_THRESHOLD: float = 50.0

## Maximum distance for enemies to be recruited into flanking squad.
const SQUAD_RECRUITMENT_DISTANCE: float = 800.0

## Maximum squad size.
const MAX_SQUAD_SIZE: int = 4

## Distance behind lead attacker for supporting role.
const SUPPORTING_OFFSET: float = 40.0

## Angle offset for supporting role (diagonally behind).
const SUPPORTING_ANGLE_OFFSET: float = 0.3  # ~17 degrees

## Sync distance from cover corner before simultaneous advance (for 3-4 enemy squads).
const SYNC_POSITION_DISTANCE: float = 100.0

## Reference to player node.
var _player: Node2D = null

## Enable debug logging.
var debug_logging: bool = false

## Signal emitted when a flank squad is formed.
signal squad_formed(members: Array, target_cover: Vector2)

## Signal emitted when a flank squad is disbanded.
signal squad_disbanded(reason: String)

## Signal emitted when squad phase changes.
signal squad_phase_changed(phase: String)


func _ready() -> void:
	_log_to_file("FlankSquadManager ready")


func _physics_process(delta: float) -> void:
	_find_player_if_needed()

	if _player == null:
		return

	_update_player_cover_tracking(delta)
	_update_active_squad(delta)


## Find player if not already found.
func _find_player_if_needed() -> void:
	if _player != null and is_instance_valid(_player):
		return

	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_player = players[0]


## Track player's position and time at cover.
func _update_player_cover_tracking(delta: float) -> void:
	if _player == null:
		return

	var player_pos := _player.global_position

	# Check if player is behind cover (not visible to enemies)
	var is_in_cover := _is_player_in_cover()

	if not is_in_cover:
		# Player not in cover, reset tracking
		if _player_cover_time > 0.0:
			_log_debug("Player left cover, resetting tracking")
		_player_cover_position = Vector2.ZERO
		_player_cover_time = 0.0
		_player_last_position = player_pos
		return

	# Check if player moved to different cover
	var distance_from_last := player_pos.distance_to(_player_last_position)

	if _player_cover_position == Vector2.ZERO:
		# First time in cover
		_player_cover_position = player_pos
		_player_cover_time = 0.0
		_log_debug("Player entered cover at %s" % player_pos)
	elif distance_from_last > COVER_POSITION_THRESHOLD:
		# Player moved to different cover
		_player_cover_position = player_pos
		_player_cover_time = 0.0
		_log_debug("Player moved to new cover at %s" % player_pos)
	else:
		# Player staying at same cover
		_player_cover_time += delta

	_player_last_position = player_pos

	# Check if threshold reached and no active squad
	if _player_cover_time >= COVER_TIME_THRESHOLD and _active_squad["members"].is_empty():
		_log_debug("Cover time threshold reached (%.1fs), attempting to form flank squad" % _player_cover_time)
		_attempt_form_flank_squad()


## Check if player is currently behind cover (hidden from most enemies).
func _is_player_in_cover() -> bool:
	if _player == null:
		return false

	var enemies := get_tree().get_nodes_in_group("enemies")
	var hidden_count := 0
	var visible_count := 0

	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		if enemy.has_method("can_see_player_public"):
			if enemy.can_see_player_public():
				visible_count += 1
			else:
				hidden_count += 1
		elif enemy.has_method("is_in_combat_engagement"):
			# Fallback: if enemy is not engaged, assume player is hidden from them
			if not enemy.is_in_combat_engagement():
				hidden_count += 1
			else:
				visible_count += 1

	# Player is "in cover" if hidden from majority of enemies
	var total := hidden_count + visible_count
	if total == 0:
		return false

	return hidden_count > visible_count


## Attempt to form a flanking squad from nearby enemies.
func _attempt_form_flank_squad() -> void:
	if _player == null:
		return

	var target_cover := _player_cover_position
	var candidates: Array = []
	var enemies := get_tree().get_nodes_in_group("enemies")

	# Find eligible enemies
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		if not enemy.has_method("get_current_state"):
			continue

		# Check distance
		var distance := enemy.global_position.distance_to(target_cover)
		if distance > SQUAD_RECRUITMENT_DISTANCE:
			continue

		# Check if enemy is in a state that allows joining squad
		# Accept: IN_COVER, COMBAT, PURSUING, IDLE, SEEKING_COVER
		# Reject: RETREATING, SUPPRESSED, already in COORDINATED_FLANKING
		var state = enemy.get_current_state()
		var state_name: String = ""
		if enemy.has_method("get_state_name"):
			state_name = enemy.get_state_name()
		else:
			state_name = str(state)

		# Check if enemy is already in coordinated flanking
		if enemy.has_method("is_in_coordinated_flanking") and enemy.is_in_coordinated_flanking():
			continue

		# Check if enemy has coordination capability
		if not enemy.has_method("join_flank_squad"):
			continue

		# Skip enemies that are retreating or suppressed
		if state_name in ["RETREATING", "SUPPRESSED"]:
			continue

		candidates.append({
			"enemy": enemy,
			"distance": distance,
			"position": enemy.global_position
		})

	if candidates.is_empty():
		_log_debug("No eligible enemies found for flank squad")
		return

	# Sort by distance (closest first)
	candidates.sort_custom(func(a, b): return a["distance"] < b["distance"])

	# Take up to MAX_SQUAD_SIZE enemies
	var squad_size := mini(candidates.size(), MAX_SQUAD_SIZE)
	var squad_members: Array = []

	for i in range(squad_size):
		squad_members.append(candidates[i]["enemy"])

	# Form the squad
	_form_squad(squad_members, target_cover)


## Form a flanking squad with the given members.
func _form_squad(members: Array, target_cover: Vector2) -> void:
	if members.is_empty():
		return

	_active_squad["members"] = members
	_active_squad["target_cover"] = target_cover
	_active_squad["roles"] = {}
	_active_squad["subgroups"] = {}
	_active_squad["lower_ready"] = false
	_active_squad["upper_ready"] = false
	_active_squad["phase"] = "forming"

	# Assign roles based on squad size
	_assign_roles(members)

	# Notify each member
	for enemy in members:
		if is_instance_valid(enemy) and enemy.has_method("join_flank_squad"):
			var role: TacticalRole = _active_squad["roles"].get(enemy.get_instance_id(), TacticalRole.NONE)
			var subgroup: FlankDirection = _active_squad["subgroups"].get(enemy.get_instance_id(), FlankDirection.LOWER)
			enemy.join_flank_squad(target_cover, role, subgroup)

	_active_squad["phase"] = "positioning"

	_log_to_file("Flank squad formed: %d members targeting cover at %s" % [members.size(), target_cover])
	squad_formed.emit(members, target_cover)
	squad_phase_changed.emit("positioning")


## Assign tactical roles based on squad size.
func _assign_roles(members: Array) -> void:
	var squad_size := members.size()
	var target_cover := _active_squad["target_cover"]

	# Sort members by their position relative to target cover
	# Those below (higher Y in Godot 2D where Y increases downward) go to lower subgroup
	# Those above (lower Y) go to upper subgroup
	var sorted_by_y: Array = members.duplicate()
	sorted_by_y.sort_custom(func(a, b):
		return a.global_position.y > b.global_position.y
	)

	match squad_size:
		1:
			# Single enemy: LEAD_ATTACKER from below
			var enemy = members[0]
			_active_squad["roles"][enemy.get_instance_id()] = TacticalRole.LEAD_ATTACKER
			_active_squad["subgroups"][enemy.get_instance_id()] = FlankDirection.LOWER
			_log_debug("Squad of 1: %s as LEAD_ATTACKER (lower)" % enemy.name)

		2:
			# Two enemies: LEAD_ATTACKER + SUPPORTING from below
			# First in sorted list (higher Y = lower on screen = goes lower)
			var lead = sorted_by_y[0]
			var support = sorted_by_y[1]

			_active_squad["roles"][lead.get_instance_id()] = TacticalRole.LEAD_ATTACKER
			_active_squad["subgroups"][lead.get_instance_id()] = FlankDirection.LOWER

			_active_squad["roles"][support.get_instance_id()] = TacticalRole.SUPPORTING
			_active_squad["subgroups"][support.get_instance_id()] = FlankDirection.LOWER

			_log_debug("Squad of 2: %s as LEAD_ATTACKER, %s as SUPPORTING (both lower)" % [lead.name, support.name])

		3:
			# Three enemies: 2 from below (lead + support), 1 from above (upper lead)
			var lower_lead = sorted_by_y[0]
			var lower_support = sorted_by_y[1]
			var upper_lead = sorted_by_y[2]  # Lowest Y = highest on screen = upper

			_active_squad["roles"][lower_lead.get_instance_id()] = TacticalRole.LEAD_ATTACKER
			_active_squad["subgroups"][lower_lead.get_instance_id()] = FlankDirection.LOWER

			_active_squad["roles"][lower_support.get_instance_id()] = TacticalRole.SUPPORTING
			_active_squad["subgroups"][lower_support.get_instance_id()] = FlankDirection.LOWER

			_active_squad["roles"][upper_lead.get_instance_id()] = TacticalRole.UPPER_LEAD_ATTACKER
			_active_squad["subgroups"][upper_lead.get_instance_id()] = FlankDirection.UPPER

			_log_debug("Squad of 3: %s LEAD (lower), %s SUPPORT (lower), %s UPPER_LEAD" % [
				lower_lead.name, lower_support.name, upper_lead.name
			])

		4, _:
			# Four enemies: Full teams - 2 below, 2 above
			var lower_lead = sorted_by_y[0]
			var lower_support = sorted_by_y[1]
			var upper_support = sorted_by_y[2]
			var upper_lead = sorted_by_y[3]  # Lowest Y = upper

			_active_squad["roles"][lower_lead.get_instance_id()] = TacticalRole.LEAD_ATTACKER
			_active_squad["subgroups"][lower_lead.get_instance_id()] = FlankDirection.LOWER

			_active_squad["roles"][lower_support.get_instance_id()] = TacticalRole.SUPPORTING
			_active_squad["subgroups"][lower_support.get_instance_id()] = FlankDirection.LOWER

			_active_squad["roles"][upper_lead.get_instance_id()] = TacticalRole.UPPER_LEAD_ATTACKER
			_active_squad["subgroups"][upper_lead.get_instance_id()] = FlankDirection.UPPER

			_active_squad["roles"][upper_support.get_instance_id()] = TacticalRole.UPPER_SUPPORTING
			_active_squad["subgroups"][upper_support.get_instance_id()] = FlankDirection.UPPER

			_log_debug("Squad of 4: %s/%s (lower), %s/%s (upper)" % [
				lower_lead.name, lower_support.name, upper_lead.name, upper_support.name
			])


## Update active squad state.
func _update_active_squad(delta: float) -> void:
	if _active_squad["members"].is_empty():
		return

	# Clean up dead/invalid members
	var valid_members: Array = []
	for enemy in _active_squad["members"]:
		if is_instance_valid(enemy):
			# Check if enemy is still alive
			if enemy.has_method("is_alive") and enemy.is_alive():
				valid_members.append(enemy)
			elif not enemy.has_method("is_alive"):
				valid_members.append(enemy)

	if valid_members.size() != _active_squad["members"].size():
		_log_debug("Squad member count changed: %d -> %d" % [_active_squad["members"].size(), valid_members.size()])
		_active_squad["members"] = valid_members

		# Disband if no members left
		if valid_members.is_empty():
			_disband_squad("all_members_eliminated")
			return

		# Reassign roles if needed
		if valid_members.size() < 4:
			_reassign_roles_after_casualty()

	# Check if player moved away from the target cover
	if _player != null:
		var player_distance := _player.global_position.distance_to(_active_squad["target_cover"])
		if player_distance > COVER_POSITION_THRESHOLD * 3:
			# Player moved significantly - update target or disband
			if _is_player_in_cover():
				# Update target cover
				_active_squad["target_cover"] = _player_cover_position
				for enemy in valid_members:
					if enemy.has_method("update_flank_target"):
						enemy.update_flank_target(_player_cover_position)
			else:
				# Player exposed - disband and let normal combat take over
				_disband_squad("player_exposed")
				return

	# Update phase based on member positions (for 3-4 member squads)
	if _active_squad["phase"] == "positioning" and valid_members.size() >= 3:
		_check_subgroup_sync_positions()


## Check if subgroups have reached their sync positions (for 3-4 enemy squads).
func _check_subgroup_sync_positions() -> void:
	var target_cover := _active_squad["target_cover"]
	var lower_ready := true
	var upper_ready := true

	for enemy in _active_squad["members"]:
		if not is_instance_valid(enemy):
			continue

		var subgroup: FlankDirection = _active_squad["subgroups"].get(enemy.get_instance_id(), FlankDirection.LOWER)

		# Check if enemy reached sync position
		if enemy.has_method("is_at_sync_position"):
			var at_sync := enemy.is_at_sync_position()
			if subgroup == FlankDirection.LOWER and not at_sync:
				lower_ready = false
			elif subgroup == FlankDirection.UPPER and not at_sync:
				upper_ready = false

	# Check if both subgroups ready (only relevant for 3-4 enemy squads)
	var has_upper := false
	for subgroup in _active_squad["subgroups"].values():
		if subgroup == FlankDirection.UPPER:
			has_upper = true
			break

	if has_upper:
		if lower_ready and upper_ready and _active_squad["phase"] == "positioning":
			_active_squad["phase"] = "flanking"
			_active_squad["lower_ready"] = true
			_active_squad["upper_ready"] = true

			# Notify all members to begin synchronized flank
			for enemy in _active_squad["members"]:
				if enemy.has_method("begin_synchronized_flank"):
					enemy.begin_synchronized_flank()

			_log_to_file("Both subgroups in position - beginning synchronized flank")
			squad_phase_changed.emit("flanking")
	else:
		# For 1-2 enemy squads, go straight to flanking
		if _active_squad["phase"] == "positioning":
			_active_squad["phase"] = "flanking"
			squad_phase_changed.emit("flanking")


## Reassign roles after a squad member is eliminated.
func _reassign_roles_after_casualty() -> void:
	var members := _active_squad["members"]
	if members.is_empty():
		return

	# Clear old roles
	_active_squad["roles"].clear()
	_active_squad["subgroups"].clear()

	# Reassign based on new squad size
	_assign_roles(members)

	# Notify members of new roles
	for enemy in members:
		if is_instance_valid(enemy) and enemy.has_method("update_squad_role"):
			var role: TacticalRole = _active_squad["roles"].get(enemy.get_instance_id(), TacticalRole.NONE)
			var subgroup: FlankDirection = _active_squad["subgroups"].get(enemy.get_instance_id(), FlankDirection.LOWER)
			enemy.update_squad_role(role, subgroup)


## Disband the current squad.
func _disband_squad(reason: String) -> void:
	_log_to_file("Flank squad disbanded: %s" % reason)

	# Notify all members
	for enemy in _active_squad["members"]:
		if is_instance_valid(enemy) and enemy.has_method("leave_flank_squad"):
			enemy.leave_flank_squad()

	# Clear squad data
	_active_squad["members"].clear()
	_active_squad["roles"].clear()
	_active_squad["subgroups"].clear()
	_active_squad["target_cover"] = Vector2.ZERO
	_active_squad["lower_ready"] = false
	_active_squad["upper_ready"] = false
	_active_squad["phase"] = "forming"

	squad_disbanded.emit(reason)


## Called by enemy when they spot the player during flanking.
func on_member_spotted_player(enemy: Node) -> void:
	if not enemy in _active_squad["members"]:
		return

	# Transition to assault phase
	if _active_squad["phase"] != "assaulting":
		_active_squad["phase"] = "assaulting"

		# Notify all members to engage
		for member in _active_squad["members"]:
			if is_instance_valid(member) and member.has_method("begin_coordinated_assault"):
				member.begin_coordinated_assault()

		_log_to_file("Player spotted during flank - beginning coordinated assault")
		squad_phase_changed.emit("assaulting")


## Called by enemy when they reach the flank target (behind cover).
func on_member_reached_cover_back(enemy: Node) -> void:
	if not enemy in _active_squad["members"]:
		return

	# Check if player not found at cover - transition to search/normal mode
	_log_debug("%s reached cover back, checking for player" % enemy.name)

	# If all members reached the back of cover and player not found, disband
	var all_at_back := true
	for member in _active_squad["members"]:
		if is_instance_valid(member) and member.has_method("is_at_cover_back"):
			if not member.is_at_cover_back():
				all_at_back = false
				break

	if all_at_back:
		_log_to_file("All squad members reached cover back - player not found, disbanding")
		_disband_squad("target_cleared")


## Get the role of an enemy in the current squad.
func get_enemy_role(enemy: Node) -> TacticalRole:
	if not enemy in _active_squad["members"]:
		return TacticalRole.NONE
	return _active_squad["roles"].get(enemy.get_instance_id(), TacticalRole.NONE)


## Get the subgroup of an enemy in the current squad.
func get_enemy_subgroup(enemy: Node) -> FlankDirection:
	if not enemy in _active_squad["members"]:
		return FlankDirection.LOWER
	return _active_squad["subgroups"].get(enemy.get_instance_id(), FlankDirection.LOWER)


## Get the lead attacker for a subgroup.
func get_subgroup_lead(subgroup: FlankDirection) -> Node:
	var target_role := TacticalRole.LEAD_ATTACKER if subgroup == FlankDirection.LOWER else TacticalRole.UPPER_LEAD_ATTACKER

	for enemy in _active_squad["members"]:
		if not is_instance_valid(enemy):
			continue
		var role: TacticalRole = _active_squad["roles"].get(enemy.get_instance_id(), TacticalRole.NONE)
		if role == target_role:
			return enemy

	return null


## Get the current squad phase.
func get_squad_phase() -> String:
	return _active_squad["phase"]


## Get whether a subgroup is ready at sync position.
func is_subgroup_ready(subgroup: FlankDirection) -> bool:
	if subgroup == FlankDirection.LOWER:
		return _active_squad["lower_ready"]
	else:
		return _active_squad["upper_ready"]


## Mark a subgroup as ready at sync position.
func set_subgroup_ready(subgroup: FlankDirection, ready: bool) -> void:
	if subgroup == FlankDirection.LOWER:
		_active_squad["lower_ready"] = ready
	else:
		_active_squad["upper_ready"] = ready


## Check if enemy is in the active squad.
func is_in_squad(enemy: Node) -> bool:
	return enemy in _active_squad["members"]


## Get the target cover position.
func get_target_cover() -> Vector2:
	return _active_squad["target_cover"]


## Get supporting offset based on role.
func get_supporting_offset() -> float:
	return SUPPORTING_OFFSET


## Get supporting angle offset.
func get_supporting_angle_offset() -> float:
	return SUPPORTING_ANGLE_OFFSET


## Get sync position distance.
func get_sync_position_distance() -> float:
	return SYNC_POSITION_DISTANCE


## Debug logging.
func _log_debug(message: String) -> void:
	if debug_logging:
		print("[FlankSquadManager] %s" % message)
	_log_to_file(message)


## Log to file.
func _log_to_file(message: String) -> void:
	var file_logger: Node = get_node_or_null("/root/FileLogger")
	if file_logger and file_logger.has_method("log_info"):
		file_logger.log_info("[FlankSquadManager] " + message)
