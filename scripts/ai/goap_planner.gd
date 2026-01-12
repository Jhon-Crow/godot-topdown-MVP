class_name GOAPPlanner
extends RefCounted
## GOAP (Goal Oriented Action Planning) planner.
##
## This planner uses A* search to find the optimal sequence of actions
## to achieve a goal from the current world state.
##
## Usage:
##   var planner = GOAPPlanner.new()
##   planner.add_action(some_action)
##   var plan = planner.plan(current_state, goal_state)
##   if plan.size() > 0:
##       execute_plan(plan)

## Available actions for planning.
var _actions: Array[GOAPAction] = []

## Maximum planning depth to prevent infinite loops.
var max_depth: int = 10

## Enable debug logging.
var debug_logging: bool = false


## Add an action to the planner's available actions.
func add_action(action: GOAPAction) -> void:
	_actions.append(action)


## Remove an action from the planner.
func remove_action(action: GOAPAction) -> void:
	_actions.erase(action)


## Clear all actions.
func clear_actions() -> void:
	_actions.clear()


## Plan a sequence of actions to achieve the goal from the current state.
## Returns an array of GOAPAction, or empty array if no plan found.
func plan(current_state: Dictionary, goal: Dictionary, agent: Node = null) -> Array[GOAPAction]:
	_log("Planning from state: %s to goal: %s" % [current_state, goal])

	# Check if goal is already satisfied
	if _is_goal_satisfied(current_state, goal):
		_log("Goal already satisfied!")
		return []

	# A* search for optimal plan
	var open_set: Array = []  # Array of PlanNode
	var closed_set: Dictionary = {}  # state_hash -> best_cost

	# Start node
	var start_node := PlanNode.new(current_state, [], 0.0)
	start_node.heuristic = _estimate_cost(current_state, goal)
	open_set.append(start_node)

	var iterations := 0
	var max_iterations := 1000  # Prevent infinite loops

	while not open_set.is_empty() and iterations < max_iterations:
		iterations += 1

		# Get node with lowest f-score (cost + heuristic)
		open_set.sort_custom(func(a, b): return (a.cost + a.heuristic) < (b.cost + b.heuristic))
		var current: PlanNode = open_set.pop_front()

		# Check if we reached the goal
		if _is_goal_satisfied(current.state, goal):
			_log("Plan found in %d iterations: %s" % [iterations, current.actions])
			return current.actions

		# Skip if we've seen this state with lower cost
		var state_hash := _hash_state(current.state)
		if closed_set.has(state_hash) and closed_set[state_hash] <= current.cost:
			continue
		closed_set[state_hash] = current.cost

		# Check depth limit
		if current.actions.size() >= max_depth:
			continue

		# Expand node with all valid actions
		for action in _actions:
			if action.is_valid(current.state):
				var new_state := action.get_result_state(current.state)
				var action_cost := action.get_cost(agent, current.state) if agent else action.cost
				var new_cost := current.cost + action_cost

				# Create new plan with this action
				var new_actions: Array[GOAPAction] = current.actions.duplicate()
				new_actions.append(action)

				var new_node := PlanNode.new(new_state, new_actions, new_cost)
				new_node.heuristic = _estimate_cost(new_state, goal)

				open_set.append(new_node)

	_log("No plan found after %d iterations" % iterations)
	return []


## Check if all goal conditions are satisfied in the current state.
func _is_goal_satisfied(state: Dictionary, goal: Dictionary) -> bool:
	for key in goal:
		if not state.has(key):
			return false
		if state[key] != goal[key]:
			return false
	return true


## Estimate the cost to reach the goal (heuristic for A*).
## Returns the number of unsatisfied goal conditions.
func _estimate_cost(state: Dictionary, goal: Dictionary) -> float:
	var unsatisfied := 0.0
	for key in goal:
		if not state.has(key) or state[key] != goal[key]:
			unsatisfied += 1.0
	return unsatisfied


## Create a hash string for a state (for closed set lookup).
func _hash_state(state: Dictionary) -> String:
	var keys := state.keys()
	keys.sort()
	var parts: Array[String] = []
	for key in keys:
		parts.append("%s=%s" % [key, state[key]])
	return ",".join(parts)


## Log a debug message.
func _log(message: String) -> void:
	if debug_logging:
		print("[GOAPPlanner] %s" % message)


## Internal class for A* search nodes.
class PlanNode:
	var state: Dictionary
	var actions: Array[GOAPAction]
	var cost: float
	var heuristic: float

	func _init(s: Dictionary, a: Array[GOAPAction], c: float) -> void:
		state = s
		actions = a
		cost = c
		heuristic = 0.0
