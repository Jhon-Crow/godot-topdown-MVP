extends GutTest
## Unit tests for GOAPPlanner class.
##
## Tests the GOAP planning algorithm including:
## - Goal satisfaction checking
## - Cost estimation (heuristic)
## - State hashing
## - A* planning algorithm


var planner: GOAPPlanner


func before_each() -> void:
	planner = GOAPPlanner.new()


func after_each() -> void:
	planner = null


# ============================================================================
# Goal Satisfaction Tests
# ============================================================================


func test_is_goal_satisfied_with_matching_state() -> void:
	var state := {"in_cover": true, "player_visible": true}
	var goal := {"in_cover": true}

	var result: bool = planner._is_goal_satisfied(state, goal)

	assert_true(result, "Goal should be satisfied when state contains matching values")


func test_is_goal_satisfied_with_empty_goal() -> void:
	var state := {"some_key": "some_value"}
	var goal := {}

	var result: bool = planner._is_goal_satisfied(state, goal)

	assert_true(result, "Empty goal should always be satisfied")


func test_is_goal_satisfied_with_missing_key() -> void:
	var state := {"in_cover": true}
	var goal := {"player_visible": true}

	var result: bool = planner._is_goal_satisfied(state, goal)

	assert_false(result, "Goal should not be satisfied when key is missing from state")


func test_is_goal_satisfied_with_wrong_value() -> void:
	var state := {"in_cover": false}
	var goal := {"in_cover": true}

	var result: bool = planner._is_goal_satisfied(state, goal)

	assert_false(result, "Goal should not be satisfied when value doesn't match")


func test_is_goal_satisfied_with_multiple_conditions() -> void:
	var state := {"in_cover": true, "player_visible": true, "has_ammo": false}
	var goal := {"in_cover": true, "player_visible": true}

	var result: bool = planner._is_goal_satisfied(state, goal)

	assert_true(result, "Goal should be satisfied when all conditions are met")


func test_is_goal_satisfied_fails_with_partial_match() -> void:
	var state := {"in_cover": true, "player_visible": false}
	var goal := {"in_cover": true, "player_visible": true}

	var result: bool = planner._is_goal_satisfied(state, goal)

	assert_false(result, "Goal should not be satisfied with only partial match")


# ============================================================================
# Cost Estimation (Heuristic) Tests
# ============================================================================


func test_estimate_cost_returns_zero_when_goal_satisfied() -> void:
	var state := {"goal_key": "goal_value"}
	var goal := {"goal_key": "goal_value"}

	var cost: float = planner._estimate_cost(state, goal)

	assert_eq(cost, 0.0, "Cost should be 0 when goal is satisfied")


func test_estimate_cost_counts_unsatisfied_conditions() -> void:
	var state := {"a": 1}
	var goal := {"a": 2, "b": 1, "c": 1}

	var cost: float = planner._estimate_cost(state, goal)

	# a has wrong value (1 vs 2), b is missing, c is missing = 3 unsatisfied
	assert_eq(cost, 3.0, "Cost should equal number of unsatisfied goal conditions")


func test_estimate_cost_with_missing_keys() -> void:
	var state := {}
	var goal := {"a": 1, "b": 2}

	var cost: float = planner._estimate_cost(state, goal)

	assert_eq(cost, 2.0, "Missing keys should count as unsatisfied")


func test_estimate_cost_with_empty_goal() -> void:
	var state := {"key": "value"}
	var goal := {}

	var cost: float = planner._estimate_cost(state, goal)

	assert_eq(cost, 0.0, "Empty goal should have zero cost")


# ============================================================================
# State Hashing Tests
# ============================================================================


func test_hash_state_produces_same_hash_for_same_state() -> void:
	var state := {"b": 2, "a": 1}

	var hash1: String = planner._hash_state(state)
	var hash2: String = planner._hash_state(state)

	assert_eq(hash1, hash2, "Same state should produce same hash")


func test_hash_state_produces_same_hash_regardless_of_key_order() -> void:
	var state1 := {"a": 1, "b": 2}
	var state2 := {"b": 2, "a": 1}

	var hash1: String = planner._hash_state(state1)
	var hash2: String = planner._hash_state(state2)

	assert_eq(hash1, hash2, "Key order should not affect hash")


func test_hash_state_produces_different_hash_for_different_state() -> void:
	var state1 := {"a": 1}
	var state2 := {"a": 2}

	var hash1: String = planner._hash_state(state1)
	var hash2: String = planner._hash_state(state2)

	assert_ne(hash1, hash2, "Different states should produce different hashes")


func test_hash_state_empty_state() -> void:
	var state := {}

	var hash_result: String = planner._hash_state(state)

	assert_eq(hash_result, "", "Empty state should produce empty hash")


# ============================================================================
# Action Management Tests
# ============================================================================


func test_add_action() -> void:
	var action := GOAPAction.new("test", 1.0)

	planner.add_action(action)

	assert_eq(planner._actions.size(), 1, "Should have one action after adding")


func test_remove_action() -> void:
	var action := GOAPAction.new("test", 1.0)
	planner.add_action(action)

	planner.remove_action(action)

	assert_eq(planner._actions.size(), 0, "Should have no actions after removing")


func test_clear_actions() -> void:
	planner.add_action(GOAPAction.new("test1", 1.0))
	planner.add_action(GOAPAction.new("test2", 1.0))

	planner.clear_actions()

	assert_eq(planner._actions.size(), 0, "Should have no actions after clearing")


# ============================================================================
# Planning Algorithm Tests
# ============================================================================


func test_plan_returns_empty_when_goal_already_satisfied() -> void:
	var state := {"goal": true}
	var goal := {"goal": true}

	var plan: Array[GOAPAction] = planner.plan(state, goal)

	assert_eq(plan.size(), 0, "Should return empty plan when goal already satisfied")


func test_plan_returns_empty_when_no_actions_available() -> void:
	var state := {"goal": false}
	var goal := {"goal": true}

	var plan: Array[GOAPAction] = planner.plan(state, goal)

	assert_eq(plan.size(), 0, "Should return empty plan when no actions can achieve goal")


func test_plan_finds_single_action_solution() -> void:
	# Create an action that satisfies the goal
	var action := GOAPAction.new("achieve_goal", 1.0)
	action.preconditions = {}
	action.effects = {"goal": true}
	planner.add_action(action)

	var state := {"goal": false}
	var goal := {"goal": true}

	var plan: Array[GOAPAction] = planner.plan(state, goal)

	assert_eq(plan.size(), 1, "Plan should have one action")
	assert_eq(plan[0].action_name, "achieve_goal", "Plan should contain the correct action")


func test_plan_finds_multi_step_solution() -> void:
	# Create action1: requires nothing, produces intermediate_state
	var action1 := GOAPAction.new("step1", 1.0)
	action1.preconditions = {}
	action1.effects = {"intermediate": true}
	planner.add_action(action1)

	# Create action2: requires intermediate_state, produces goal
	var action2 := GOAPAction.new("step2", 1.0)
	action2.preconditions = {"intermediate": true}
	action2.effects = {"goal": true}
	planner.add_action(action2)

	var state := {}
	var goal := {"goal": true}

	var plan: Array[GOAPAction] = planner.plan(state, goal)

	assert_eq(plan.size(), 2, "Plan should have two actions")
	assert_eq(plan[0].action_name, "step1", "First action should be step1")
	assert_eq(plan[1].action_name, "step2", "Second action should be step2")


func test_plan_prefers_lower_cost_path() -> void:
	# Expensive direct action
	var expensive := GOAPAction.new("expensive", 10.0)
	expensive.preconditions = {}
	expensive.effects = {"goal": true}
	planner.add_action(expensive)

	# Cheap direct action
	var cheap := GOAPAction.new("cheap", 1.0)
	cheap.preconditions = {}
	cheap.effects = {"goal": true}
	planner.add_action(cheap)

	var state := {}
	var goal := {"goal": true}

	var plan: Array[GOAPAction] = planner.plan(state, goal)

	assert_eq(plan.size(), 1, "Plan should have one action")
	assert_eq(plan[0].action_name, "cheap", "Planner should choose cheaper action")


func test_plan_respects_preconditions() -> void:
	# Action that can't be executed due to unmet precondition
	var blocked := GOAPAction.new("blocked", 1.0)
	blocked.preconditions = {"prerequisite": true}
	blocked.effects = {"goal": true}
	planner.add_action(blocked)

	var state := {"prerequisite": false}
	var goal := {"goal": true}

	var plan: Array[GOAPAction] = planner.plan(state, goal)

	assert_eq(plan.size(), 0, "Should return empty plan when preconditions can't be met")


func test_plan_respects_max_depth() -> void:
	planner.max_depth = 2

	# Create a chain of 5 actions
	for i in range(5):
		var action := GOAPAction.new("step%d" % i, 1.0)
		if i == 0:
			action.preconditions = {}
		else:
			action.preconditions = {"state%d" % (i - 1): true}
		action.effects = {"state%d" % i: true}
		planner.add_action(action)

	var state := {}
	var goal := {"state4": true}

	var plan: Array[GOAPAction] = planner.plan(state, goal)

	# Plan should be empty because it would require 5 steps but max_depth is 2
	assert_eq(plan.size(), 0, "Should not find plan that exceeds max_depth")


func test_plan_with_complex_world_state() -> void:
	# Test with a more realistic scenario
	var seek_cover := GOAPAction.new("seek_cover", 2.0)
	seek_cover.preconditions = {"has_cover": true}
	seek_cover.effects = {"in_cover": true}
	planner.add_action(seek_cover)

	var find_cover := GOAPAction.new("find_cover", 1.0)
	find_cover.preconditions = {}
	find_cover.effects = {"has_cover": true}
	planner.add_action(find_cover)

	var state := {"player_visible": true}
	var goal := {"in_cover": true}

	var plan: Array[GOAPAction] = planner.plan(state, goal)

	assert_eq(plan.size(), 2, "Plan should have two actions")
	assert_eq(plan[0].action_name, "find_cover", "First should find cover")
	assert_eq(plan[1].action_name, "seek_cover", "Second should seek cover")


func test_plan_preserves_existing_state() -> void:
	var action := GOAPAction.new("action", 1.0)
	action.preconditions = {}
	action.effects = {"new_state": true}
	planner.add_action(action)

	# Create another action that requires both original and new state
	var action2 := GOAPAction.new("final", 1.0)
	action2.preconditions = {"existing": true, "new_state": true}
	action2.effects = {"goal": true}
	planner.add_action(action2)

	var state := {"existing": true}
	var goal := {"goal": true}

	var plan: Array[GOAPAction] = planner.plan(state, goal)

	assert_eq(plan.size(), 2, "Plan should chain actions preserving existing state")
