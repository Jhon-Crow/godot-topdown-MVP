class_name GOAPAction
extends RefCounted
## Base class for GOAP (Goal Oriented Action Planning) actions.
##
## This is a foundation for implementing goal-oriented AI behavior.
## Actions have preconditions (what must be true to execute) and
## effects (what becomes true after execution).
##
## To create a new action, extend this class and override the methods.

## Name of this action for debugging.
var action_name: String = "base_action"

## Cost of performing this action (lower is preferred).
var cost: float = 1.0

## Preconditions required for this action to be valid.
## Dictionary of state_key -> required_value pairs.
var preconditions: Dictionary = {}

## Effects of this action on the world state.
## Dictionary of state_key -> new_value pairs.
var effects: Dictionary = {}


func _init(name: String = "base_action", action_cost: float = 1.0) -> void:
	action_name = name
	cost = action_cost


## Check if this action can be executed given the current world state.
func is_valid(world_state: Dictionary) -> bool:
	for key in preconditions:
		if not world_state.has(key):
			return false
		if world_state[key] != preconditions[key]:
			return false
	return true


## Get the resulting world state after applying this action's effects.
func get_result_state(world_state: Dictionary) -> Dictionary:
	var result := world_state.duplicate()
	for key in effects:
		result[key] = effects[key]
	return result


## Check if this action can satisfy the given goal.
## Returns true if any of the action's effects match a goal condition.
func can_satisfy_goal(goal: Dictionary) -> bool:
	for key in goal:
		if effects.has(key) and effects[key] == goal[key]:
			return true
	return false


## Execute the action. Override this in subclasses.
## Returns true if action started successfully.
func execute(_agent: Node) -> bool:
	return true


## Check if the action is complete. Override this in subclasses.
func is_complete(_agent: Node) -> bool:
	return true


## Get dynamic cost based on current state. Override for context-sensitive costs.
func get_cost(_agent: Node, _world_state: Dictionary) -> float:
	return cost


## Create a string representation for debugging.
func _to_string() -> String:
	return "GOAPAction(%s, cost=%.1f)" % [action_name, cost]
