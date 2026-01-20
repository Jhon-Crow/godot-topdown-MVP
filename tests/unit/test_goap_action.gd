extends GutTest
## Unit tests for GOAPAction class.
##
## Tests the base GOAP action functionality including:
## - Precondition validation
## - State transformation
## - Goal satisfaction checking
## - Action initialization


func test_action_initialization_default_values() -> void:
	var action := GOAPAction.new()

	assert_eq(action.action_name, "base_action", "Default action name should be 'base_action'")
	assert_eq(action.cost, 1.0, "Default cost should be 1.0")
	assert_eq(action.preconditions.size(), 0, "Default preconditions should be empty")
	assert_eq(action.effects.size(), 0, "Default effects should be empty")


func test_action_initialization_with_parameters() -> void:
	var action := GOAPAction.new("test_action", 5.0)

	assert_eq(action.action_name, "test_action", "Action name should match parameter")
	assert_eq(action.cost, 5.0, "Cost should match parameter")


func test_is_valid_with_empty_preconditions() -> void:
	var action := GOAPAction.new()
	var world_state := {"key": "value"}

	assert_true(action.is_valid(world_state), "Action with no preconditions should always be valid")


func test_is_valid_with_matching_preconditions() -> void:
	var action := GOAPAction.new()
	action.preconditions = {
		"has_weapon": true,
		"has_ammo": true
	}
	var world_state := {
		"has_weapon": true,
		"has_ammo": true,
		"health": 100
	}

	assert_true(action.is_valid(world_state), "Action should be valid when all preconditions are met")


func test_is_valid_with_missing_precondition_key() -> void:
	var action := GOAPAction.new()
	action.preconditions = {"has_weapon": true}
	var world_state := {"health": 100}

	assert_false(action.is_valid(world_state), "Action should be invalid when precondition key is missing")


func test_is_valid_with_wrong_precondition_value() -> void:
	var action := GOAPAction.new()
	action.preconditions = {"has_weapon": true}
	var world_state := {"has_weapon": false}

	assert_false(action.is_valid(world_state), "Action should be invalid when precondition value doesn't match")


func test_is_valid_with_partial_preconditions_met() -> void:
	var action := GOAPAction.new()
	action.preconditions = {
		"has_weapon": true,
		"has_ammo": true
	}
	var world_state := {
		"has_weapon": true,
		"has_ammo": false
	}

	assert_false(action.is_valid(world_state), "Action should be invalid when only some preconditions are met")


func test_get_result_state_applies_effects() -> void:
	var action := GOAPAction.new()
	action.effects = {
		"in_cover": true,
		"under_fire": false
	}
	var world_state := {
		"health": 100,
		"in_cover": false,
		"under_fire": true
	}

	var result := action.get_result_state(world_state)

	assert_eq(result["in_cover"], true, "Effect should change in_cover to true")
	assert_eq(result["under_fire"], false, "Effect should change under_fire to false")
	assert_eq(result["health"], 100, "Non-affected state should remain unchanged")


func test_get_result_state_does_not_modify_original() -> void:
	var action := GOAPAction.new()
	action.effects = {"modified": true}
	var world_state := {"modified": false}

	var _result := action.get_result_state(world_state)

	assert_eq(world_state["modified"], false, "Original state should not be modified")


func test_get_result_state_adds_new_keys() -> void:
	var action := GOAPAction.new()
	action.effects = {"new_key": "new_value"}
	var world_state := {"existing_key": "existing_value"}

	var result := action.get_result_state(world_state)

	assert_eq(result["new_key"], "new_value", "New effect keys should be added to result state")
	assert_eq(result["existing_key"], "existing_value", "Existing keys should remain")


func test_can_satisfy_goal_returns_true_when_effect_matches_goal() -> void:
	var action := GOAPAction.new()
	action.effects = {"player_engaged": true}
	var goal := {"player_engaged": true}

	assert_true(action.can_satisfy_goal(goal), "Action should satisfy goal when effect matches")


func test_can_satisfy_goal_returns_false_when_no_match() -> void:
	var action := GOAPAction.new()
	action.effects = {"in_cover": true}
	var goal := {"player_engaged": true}

	assert_false(action.can_satisfy_goal(goal), "Action should not satisfy goal when no effect matches")


func test_can_satisfy_goal_returns_false_when_value_mismatch() -> void:
	var action := GOAPAction.new()
	action.effects = {"player_engaged": false}
	var goal := {"player_engaged": true}

	assert_false(action.can_satisfy_goal(goal), "Action should not satisfy goal when effect value doesn't match")


func test_can_satisfy_goal_returns_true_for_partial_goal_match() -> void:
	var action := GOAPAction.new()
	action.effects = {"player_engaged": true}
	var goal := {
		"player_engaged": true,
		"in_cover": true
	}

	assert_true(action.can_satisfy_goal(goal), "Action should satisfy goal if any effect matches any goal condition")


func test_execute_returns_true_by_default() -> void:
	var action := GOAPAction.new()

	assert_true(action.execute(null), "Default execute should return true")


func test_is_complete_returns_true_by_default() -> void:
	var action := GOAPAction.new()

	assert_true(action.is_complete(null), "Default is_complete should return true")


func test_get_cost_returns_action_cost() -> void:
	var action := GOAPAction.new("test", 3.5)

	assert_eq(action.get_cost(null, {}), 3.5, "get_cost should return action's cost")


func test_to_string_format() -> void:
	var action := GOAPAction.new("test_action", 2.5)

	var str_result := action._to_string()

	assert_true(str_result.contains("test_action"), "String should contain action name")
	assert_true(str_result.contains("2.5"), "String should contain cost")
