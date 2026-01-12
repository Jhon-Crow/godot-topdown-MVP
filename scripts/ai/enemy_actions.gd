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
		var hits := world_state.get("hits_taken", 0)
		if hits == 0:
			# Full HP - can afford to fight while retreating
			return 1.0
		elif hits == 1:
			# One hit - quick burst then escape
			return 0.8
		else:
			# Multiple hits - just run!
			return 0.5


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
	return actions
