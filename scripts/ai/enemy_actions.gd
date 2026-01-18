class_name EnemyActions
extends RefCounted
## Collection of GOAP actions for enemy AI.
##
## These actions define what enemies can do to achieve their goals.
## Each action has preconditions, effects, and costs that the
## GOAP planner uses to find optimal action sequences.


## Action to find and move to cover.
class SeekCoverAction extends GOAPAction:
	func _init() -> void:
		super._init("seek_cover", 2.0)
		preconditions = {
			"has_cover": true,
			"in_cover": false
		}
		effects = {
			"in_cover": true,
			"under_fire": false
		}

	func get_cost(_agent: Node, world_state: Dictionary) -> float:
		# Higher cost if we're actively engaging
		if world_state.get("player_visible", false):
			return 3.0
		return 2.0


## Action to engage the player in combat.
class EngagePlayerAction extends GOAPAction:
	func _init() -> void:
		super._init("engage_player", 1.0)
		preconditions = {
			"player_visible": true
		}
		effects = {
			"player_engaged": true
		}

	func get_cost(_agent: Node, world_state: Dictionary) -> float:
		# Lower cost if we have advantage (in cover, not under fire)
		if world_state.get("in_cover", false):
			return 0.5
		if world_state.get("under_fire", false):
			return 2.0
		return 1.0


## Action to flank the player.
class FlankPlayerAction extends GOAPAction:
	func _init() -> void:
		super._init("flank_player", 3.0)
		preconditions = {
			"player_visible": false,
			"under_fire": false
		}
		effects = {
			"at_flank_position": true,
			"player_visible": true
		}


## Action to patrol the area.
class PatrolAction extends GOAPAction:
	func _init() -> void:
		super._init("patrol", 1.0)
		preconditions = {
			"player_visible": false,
			"under_fire": false
		}
		effects = {
			"area_patrolled": true
		}


## Action to stay suppressed (wait for fire to stop).
class StaySuppressedAction extends GOAPAction:
	func _init() -> void:
		super._init("stay_suppressed", 0.5)
		preconditions = {
			"under_fire": true,
			"in_cover": true
		}
		effects = {
			"waiting_for_safe": true
		}


## Action to return fire while suppressed.
class ReturnFireAction extends GOAPAction:
	func _init() -> void:
		super._init("return_fire", 1.5)
		preconditions = {
			"player_visible": true,
			"in_cover": true
		}
		effects = {
			"player_engaged": true
		}


## Action to find cover (search for cover positions).
class FindCoverAction extends GOAPAction:
	func _init() -> void:
		super._init("find_cover", 0.5)
		preconditions = {
			"has_cover": false
		}
		effects = {
			"has_cover": true
		}


## Action to retreat when health is low.
class RetreatAction extends GOAPAction:
	func _init() -> void:
		super._init("retreat", 4.0)
		preconditions = {
			"health_low": true
		}
		effects = {
			"in_cover": true,
			"retreated": true
		}

	func get_cost(_agent: Node, world_state: Dictionary) -> float:
		# Very high priority if under fire with low health
		if world_state.get("under_fire", false):
			return 1.0
		return 4.0


## Action to retreat with fire when under suppression (tactical retreat).
## Cost varies based on number of hits taken during encounter.
class RetreatWithFireAction extends GOAPAction:
	func _init() -> void:
		super._init("retreat_with_fire", 1.5)
		preconditions = {
			"under_fire": true
		}
		effects = {
			"in_cover": true,
			"is_retreating": true
		}

	func get_cost(_agent: Node, world_state: Dictionary) -> float:
		# Cost is lower (higher priority) when under fire
		# Priority also depends on hits taken
		var hits: int = world_state.get("hits_taken", 0)
		if hits == 0:
			# Full HP - can afford to fight while retreating
			return 1.0
		elif hits == 1:
			# One hit - quick burst then escape
			return 0.8
		else:
			# Multiple hits - just run!
			return 0.5


## Action to pursue the player by moving cover-to-cover.
## Used when enemy is far from player and can't hit them from current position.
class PursuePlayerAction extends GOAPAction:
	func _init() -> void:
		super._init("pursue_player", 2.5)
		preconditions = {
			"player_visible": false,
			"player_close": false
		}
		effects = {
			"is_pursuing": true,
			"player_close": true
		}

	func get_cost(_agent: Node, world_state: Dictionary) -> float:
		# Lower cost if we can't hit from current position
		if not world_state.get("can_hit_from_cover", false):
			return 1.5
		return 3.0


## Action to initiate coordinated assault when multiple enemies are in combat.
## All enemies rush the player simultaneously after a 5 second wait.
class AssaultPlayerAction extends GOAPAction:
	func _init() -> void:
		super._init("assault_player", 1.0)
		preconditions = {
			"player_visible": true
		}
		effects = {
			"is_assaulting": true,
			"player_engaged": true
		}

	func get_cost(_agent: Node, world_state: Dictionary) -> float:
		# Only low cost if multiple enemies are in combat
		var enemies_count: int = world_state.get("enemies_in_combat", 0)
		if enemies_count >= 2:
			return 0.5  # High priority for coordinated attack
		return 5.0  # Very high cost if alone (prefer other actions)


## Action to attack a distracted player (aim > 23° away from enemy).
## This action has the LOWEST cost (highest priority) of all actions.
## When the player is visible but not aiming at the enemy, this action takes precedence
## over all other behaviors, forcing an immediate attack.
class AttackDistractedPlayerAction extends GOAPAction:
	func _init() -> void:
		super._init("attack_distracted_player", 0.1)  # Very low cost = highest priority
		preconditions = {
			"player_visible": true,
			"player_distracted": true
		}
		effects = {
			"player_engaged": true
		}

	func get_cost(_agent: Node, world_state: Dictionary) -> float:
		# This action always has the lowest cost when conditions are met
		# to ensure it takes absolute priority over all other actions.
		# Return even lower cost to guarantee it's selected.
		if world_state.get("player_distracted", false):
			return 0.05  # Absolute highest priority
		return 100.0  # Should never happen if preconditions are correct


## Create and return all enemy actions.
static func create_all_actions() -> Array[GOAPAction]:
	var actions: Array[GOAPAction] = []
	actions.append(SeekCoverAction.new())
	actions.append(EngagePlayerAction.new())
	actions.append(FlankPlayerAction.new())
	actions.append(PatrolAction.new())
	actions.append(StaySuppressedAction.new())
	actions.append(ReturnFireAction.new())
	actions.append(FindCoverAction.new())
	actions.append(RetreatAction.new())
	actions.append(RetreatWithFireAction.new())
	actions.append(PursuePlayerAction.new())
	actions.append(AssaultPlayerAction.new())
	actions.append(AttackDistractedPlayerAction.new())
	return actions
