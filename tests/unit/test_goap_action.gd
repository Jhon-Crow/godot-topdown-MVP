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


# ============================================================================
# ThrowGrenadeAction Tests (Issue #657)
# ============================================================================


func test_throw_grenade_action_initialization() -> void:
	var action := EnemyActions.ThrowGrenadeAction.new()

	assert_eq(action.action_name, "throw_grenade", "Action name should be 'throw_grenade'")
	assert_eq(action.cost, 0.3, "Base cost should be 0.3")


func test_throw_grenade_action_preconditions() -> void:
	var action := EnemyActions.ThrowGrenadeAction.new()

	assert_true(action.preconditions.has("has_grenades"), "Should require has_grenades")
	assert_eq(action.preconditions["has_grenades"], true, "has_grenades should be true")
	assert_true(action.preconditions.has("grenadier_throw_ready"), "Should require grenadier_throw_ready")
	assert_eq(action.preconditions["grenadier_throw_ready"], true, "grenadier_throw_ready should be true")


func test_throw_grenade_action_effects() -> void:
	var action := EnemyActions.ThrowGrenadeAction.new()

	assert_true(action.effects.has("grenade_thrown"), "Should have grenade_thrown effect")
	assert_eq(action.effects["grenade_thrown"], true, "grenade_thrown should be true")
	assert_true(action.effects.has("player_engaged"), "Should have player_engaged effect")


func test_throw_grenade_action_valid_when_ready() -> void:
	var action := EnemyActions.ThrowGrenadeAction.new()
	var state := {"has_grenades": true, "grenadier_throw_ready": true}

	assert_true(action.is_valid(state), "Should be valid when grenadier has grenades and is ready")


func test_throw_grenade_action_invalid_when_no_grenades() -> void:
	var action := EnemyActions.ThrowGrenadeAction.new()
	var state := {"has_grenades": false, "grenadier_throw_ready": true}

	assert_false(action.is_valid(state), "Should be invalid when no grenades")


func test_throw_grenade_action_invalid_when_not_ready() -> void:
	var action := EnemyActions.ThrowGrenadeAction.new()
	var state := {"has_grenades": true, "grenadier_throw_ready": false}

	assert_false(action.is_valid(state), "Should be invalid when not ready to throw")


func test_throw_grenade_action_low_cost_when_ready() -> void:
	var action := EnemyActions.ThrowGrenadeAction.new()
	var state := {"grenadier_throw_ready": true}

	assert_eq(action.get_cost(null, state), 0.2,
		"Cost should be 0.2 when grenadier is ready to throw")


func test_throw_grenade_action_high_cost_when_not_ready() -> void:
	var action := EnemyActions.ThrowGrenadeAction.new()
	var state := {"grenadier_throw_ready": false}

	assert_eq(action.get_cost(null, state), 100.0,
		"Cost should be 100.0 when grenadier is not ready")


func test_throw_grenade_action_in_create_all_actions() -> void:
	var actions := EnemyActions.create_all_actions()
	var found := false
	for action in actions:
		if action.action_name == "throw_grenade":
			found = true
			break

	assert_true(found, "ThrowGrenadeAction should be included in create_all_actions()")
