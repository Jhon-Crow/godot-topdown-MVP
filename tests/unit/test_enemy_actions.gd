extends GutTest
## Unit tests for EnemyActions class.
##
## Tests the enemy AI action definitions including:
## - Action initialization
## - Preconditions and effects
## - Dynamic cost calculations


# ============================================================================
# SeekCoverAction Tests
# ============================================================================


func test_seek_cover_action_initialization() -> void:
	var action := EnemyActions.SeekCoverAction.new()

	assert_eq(action.action_name, "seek_cover", "Action name should be 'seek_cover'")
	assert_eq(action.cost, 2.0, "Base cost should be 2.0")


func test_seek_cover_action_preconditions() -> void:
	var action := EnemyActions.SeekCoverAction.new()

	assert_eq(action.preconditions["has_cover"], true, "Requires has_cover to be true")
	assert_eq(action.preconditions["in_cover"], false, "Requires in_cover to be false")


func test_seek_cover_action_effects() -> void:
	var action := EnemyActions.SeekCoverAction.new()

	assert_eq(action.effects["in_cover"], true, "Effect should set in_cover to true")
	assert_eq(action.effects["under_fire"], false, "Effect should set under_fire to false")


func test_seek_cover_action_cost_when_player_visible() -> void:
	var action := EnemyActions.SeekCoverAction.new()
	var world_state := {"player_visible": true}

	var cost: float = action.get_cost(null, world_state)

	assert_eq(cost, 3.0, "Cost should be higher when player is visible")


func test_seek_cover_action_cost_when_player_not_visible() -> void:
	var action := EnemyActions.SeekCoverAction.new()
	var world_state := {"player_visible": false}

	var cost: float = action.get_cost(null, world_state)

	assert_eq(cost, 2.0, "Cost should be normal when player is not visible")


# ============================================================================
# EngagePlayerAction Tests
# ============================================================================


func test_engage_player_action_initialization() -> void:
	var action := EnemyActions.EngagePlayerAction.new()

	assert_eq(action.action_name, "engage_player", "Action name should be 'engage_player'")
	assert_eq(action.cost, 1.0, "Base cost should be 1.0")


func test_engage_player_action_preconditions() -> void:
	var action := EnemyActions.EngagePlayerAction.new()

	assert_eq(action.preconditions["player_visible"], true, "Requires player_visible to be true")


func test_engage_player_action_effects() -> void:
	var action := EnemyActions.EngagePlayerAction.new()

	assert_eq(action.effects["player_engaged"], true, "Effect should set player_engaged to true")


func test_engage_player_action_cost_in_cover() -> void:
	var action := EnemyActions.EngagePlayerAction.new()
	var world_state := {"in_cover": true, "under_fire": false}

	var cost: float = action.get_cost(null, world_state)

	assert_eq(cost, 0.5, "Cost should be lower when in cover")


func test_engage_player_action_cost_under_fire() -> void:
	var action := EnemyActions.EngagePlayerAction.new()
	var world_state := {"in_cover": false, "under_fire": true}

	var cost: float = action.get_cost(null, world_state)

	assert_eq(cost, 2.0, "Cost should be higher when under fire")


func test_engage_player_action_cost_normal() -> void:
	var action := EnemyActions.EngagePlayerAction.new()
	var world_state := {"in_cover": false, "under_fire": false}

	var cost: float = action.get_cost(null, world_state)

	assert_eq(cost, 1.0, "Cost should be normal otherwise")


# ============================================================================
# FlankPlayerAction Tests
# ============================================================================


func test_flank_player_action_initialization() -> void:
	var action := EnemyActions.FlankPlayerAction.new()

	assert_eq(action.action_name, "flank_player", "Action name should be 'flank_player'")
	assert_eq(action.cost, 3.0, "Base cost should be 3.0")


func test_flank_player_action_preconditions() -> void:
	var action := EnemyActions.FlankPlayerAction.new()

	assert_eq(action.preconditions["player_visible"], false, "Requires player not visible")
	assert_eq(action.preconditions["under_fire"], false, "Requires not under fire")


func test_flank_player_action_effects() -> void:
	var action := EnemyActions.FlankPlayerAction.new()

	assert_eq(action.effects["at_flank_position"], true, "Should reach flank position")
	assert_eq(action.effects["player_visible"], true, "Should make player visible")


# ============================================================================
# PatrolAction Tests
# ============================================================================


func test_patrol_action_initialization() -> void:
	var action := EnemyActions.PatrolAction.new()

	assert_eq(action.action_name, "patrol", "Action name should be 'patrol'")
	assert_eq(action.cost, 1.0, "Base cost should be 1.0")


func test_patrol_action_preconditions() -> void:
	var action := EnemyActions.PatrolAction.new()

	assert_eq(action.preconditions["player_visible"], false, "Requires player not visible")
	assert_eq(action.preconditions["under_fire"], false, "Requires not under fire")


func test_patrol_action_effects() -> void:
	var action := EnemyActions.PatrolAction.new()

	assert_eq(action.effects["area_patrolled"], true, "Effect should set area_patrolled")


# ============================================================================
# StaySuppressedAction Tests
# ============================================================================


func test_stay_suppressed_action_initialization() -> void:
	var action := EnemyActions.StaySuppressedAction.new()

	assert_eq(action.action_name, "stay_suppressed", "Action name should be 'stay_suppressed'")
	assert_eq(action.cost, 0.5, "Base cost should be 0.5 (low priority)")


func test_stay_suppressed_action_preconditions() -> void:
	var action := EnemyActions.StaySuppressedAction.new()

	assert_eq(action.preconditions["under_fire"], true, "Requires being under fire")
	assert_eq(action.preconditions["in_cover"], true, "Requires being in cover")


func test_stay_suppressed_action_effects() -> void:
	var action := EnemyActions.StaySuppressedAction.new()

	assert_eq(action.effects["waiting_for_safe"], true, "Effect should set waiting_for_safe")


# ============================================================================
# ReturnFireAction Tests
# ============================================================================


func test_return_fire_action_initialization() -> void:
	var action := EnemyActions.ReturnFireAction.new()

	assert_eq(action.action_name, "return_fire", "Action name should be 'return_fire'")
	assert_eq(action.cost, 1.5, "Base cost should be 1.5")


func test_return_fire_action_preconditions() -> void:
	var action := EnemyActions.ReturnFireAction.new()

	assert_eq(action.preconditions["player_visible"], true, "Requires player visible")
	assert_eq(action.preconditions["in_cover"], true, "Requires being in cover")


func test_return_fire_action_effects() -> void:
	var action := EnemyActions.ReturnFireAction.new()

	assert_eq(action.effects["player_engaged"], true, "Effect should set player_engaged")


# ============================================================================
# FindCoverAction Tests
# ============================================================================


func test_find_cover_action_initialization() -> void:
	var action := EnemyActions.FindCoverAction.new()

	assert_eq(action.action_name, "find_cover", "Action name should be 'find_cover'")
	assert_eq(action.cost, 0.5, "Base cost should be 0.5 (high priority)")


func test_find_cover_action_preconditions() -> void:
	var action := EnemyActions.FindCoverAction.new()

	assert_eq(action.preconditions["has_cover"], false, "Requires not having cover")


func test_find_cover_action_effects() -> void:
	var action := EnemyActions.FindCoverAction.new()

	assert_eq(action.effects["has_cover"], true, "Effect should set has_cover")


# ============================================================================
# RetreatAction Tests
# ============================================================================


func test_retreat_action_initialization() -> void:
	var action := EnemyActions.RetreatAction.new()

	assert_eq(action.action_name, "retreat", "Action name should be 'retreat'")
	assert_eq(action.cost, 4.0, "Base cost should be 4.0 (low priority normally)")


func test_retreat_action_preconditions() -> void:
	var action := EnemyActions.RetreatAction.new()

	assert_eq(action.preconditions["health_low"], true, "Requires low health")


func test_retreat_action_effects() -> void:
	var action := EnemyActions.RetreatAction.new()

	assert_eq(action.effects["in_cover"], true, "Effect should set in_cover")
	assert_eq(action.effects["retreated"], true, "Effect should set retreated")


func test_retreat_action_cost_under_fire() -> void:
	var action := EnemyActions.RetreatAction.new()
	var world_state := {"under_fire": true}

	var cost: float = action.get_cost(null, world_state)

	assert_eq(cost, 1.0, "Cost should be much lower when under fire with low health")


func test_retreat_action_cost_not_under_fire() -> void:
	var action := EnemyActions.RetreatAction.new()
	var world_state := {"under_fire": false}

	var cost: float = action.get_cost(null, world_state)

	assert_eq(cost, 4.0, "Cost should be normal when not under fire")


# ============================================================================
# RetreatWithFireAction Tests
# ============================================================================


func test_retreat_with_fire_action_initialization() -> void:
	var action := EnemyActions.RetreatWithFireAction.new()

	assert_eq(action.action_name, "retreat_with_fire", "Action name should be 'retreat_with_fire'")
	assert_eq(action.cost, 1.5, "Base cost should be 1.5")


func test_retreat_with_fire_action_preconditions() -> void:
	var action := EnemyActions.RetreatWithFireAction.new()

	assert_eq(action.preconditions["under_fire"], true, "Requires being under fire")


func test_retreat_with_fire_action_effects() -> void:
	var action := EnemyActions.RetreatWithFireAction.new()

	assert_eq(action.effects["in_cover"], true, "Effect should set in_cover")
	assert_eq(action.effects["is_retreating"], true, "Effect should set is_retreating")


func test_retreat_with_fire_cost_no_hits() -> void:
	var action := EnemyActions.RetreatWithFireAction.new()
	var world_state := {"hits_taken": 0}

	var cost: float = action.get_cost(null, world_state)

	assert_eq(cost, 1.0, "Cost with no hits taken")


func test_retreat_with_fire_cost_one_hit() -> void:
	var action := EnemyActions.RetreatWithFireAction.new()
	var world_state := {"hits_taken": 1}

	var cost: float = action.get_cost(null, world_state)

	assert_eq(cost, 0.8, "Cost with one hit taken")


func test_retreat_with_fire_cost_multiple_hits() -> void:
	var action := EnemyActions.RetreatWithFireAction.new()
	var world_state := {"hits_taken": 3}

	var cost: float = action.get_cost(null, world_state)

	assert_eq(cost, 0.5, "Cost with multiple hits taken (priority to escape)")


# ============================================================================
# PursuePlayerAction Tests
# ============================================================================


func test_pursue_player_action_initialization() -> void:
	var action := EnemyActions.PursuePlayerAction.new()

	assert_eq(action.action_name, "pursue_player", "Action name should be 'pursue_player'")
	assert_eq(action.cost, 2.5, "Base cost should be 2.5")


func test_pursue_player_action_preconditions() -> void:
	var action := EnemyActions.PursuePlayerAction.new()

	assert_eq(action.preconditions["player_visible"], false, "Requires player not visible")
	assert_eq(action.preconditions["player_close"], false, "Requires player not close")


func test_pursue_player_action_effects() -> void:
	var action := EnemyActions.PursuePlayerAction.new()

	assert_eq(action.effects["is_pursuing"], true, "Effect should set is_pursuing")
	assert_eq(action.effects["player_close"], true, "Effect should set player_close")


func test_pursue_player_cost_cannot_hit_from_cover() -> void:
	var action := EnemyActions.PursuePlayerAction.new()
	var world_state := {"can_hit_from_cover": false}

	var cost: float = action.get_cost(null, world_state)

	assert_eq(cost, 1.5, "Cost should be lower when can't hit from cover")


func test_pursue_player_cost_can_hit_from_cover() -> void:
	var action := EnemyActions.PursuePlayerAction.new()
	var world_state := {"can_hit_from_cover": true}

	var cost: float = action.get_cost(null, world_state)

	assert_eq(cost, 3.0, "Cost should be higher when can hit from cover")


# ============================================================================
# AssaultPlayerAction Tests
# ============================================================================


func test_assault_player_action_initialization() -> void:
	var action := EnemyActions.AssaultPlayerAction.new()

	assert_eq(action.action_name, "assault_player", "Action name should be 'assault_player'")
	assert_eq(action.cost, 1.0, "Base cost should be 1.0")


func test_assault_player_action_preconditions() -> void:
	var action := EnemyActions.AssaultPlayerAction.new()

	assert_eq(action.preconditions["player_visible"], true, "Requires player visible")


func test_assault_player_action_effects() -> void:
	var action := EnemyActions.AssaultPlayerAction.new()

	assert_eq(action.effects["is_assaulting"], true, "Effect should set is_assaulting")
	assert_eq(action.effects["player_engaged"], true, "Effect should set player_engaged")


func test_assault_player_cost_with_multiple_enemies() -> void:
	var action := EnemyActions.AssaultPlayerAction.new()
	var world_state := {"enemies_in_combat": 3}

	var cost: float = action.get_cost(null, world_state)

	assert_eq(cost, 0.5, "Cost should be low for coordinated attack")


func test_assault_player_cost_alone() -> void:
	var action := EnemyActions.AssaultPlayerAction.new()
	var world_state := {"enemies_in_combat": 1}

	var cost: float = action.get_cost(null, world_state)

	assert_eq(cost, 5.0, "Cost should be very high when alone (prefer other actions)")


# ============================================================================
# AttackDistractedPlayerAction Tests
# ============================================================================


func test_attack_distracted_player_action_initialization() -> void:
	var action := EnemyActions.AttackDistractedPlayerAction.new()

	assert_eq(action.action_name, "attack_distracted_player", "Action name should be 'attack_distracted_player'")
	assert_eq(action.cost, 0.1, "Base cost should be 0.1 (very low = high priority)")


func test_attack_distracted_player_action_preconditions() -> void:
	var action := EnemyActions.AttackDistractedPlayerAction.new()

	assert_eq(action.preconditions["player_visible"], true, "Requires player visible")
	assert_eq(action.preconditions["player_distracted"], true, "Requires player distracted")


func test_attack_distracted_player_action_effects() -> void:
	var action := EnemyActions.AttackDistractedPlayerAction.new()

	assert_eq(action.effects["player_engaged"], true, "Effect should set player_engaged")


func test_attack_distracted_player_cost_when_distracted() -> void:
	var action := EnemyActions.AttackDistractedPlayerAction.new()
	var world_state := {"player_distracted": true}

	var cost: float = action.get_cost(null, world_state)

	assert_eq(cost, 0.05, "Cost should be extremely low when player is distracted (highest priority)")


func test_attack_distracted_player_cost_when_not_distracted() -> void:
	var action := EnemyActions.AttackDistractedPlayerAction.new()
	var world_state := {"player_distracted": false}

	var cost: float = action.get_cost(null, world_state)

	assert_eq(cost, 100.0, "Cost should be very high when player is not distracted")


# ============================================================================
# create_all_actions Tests
# ============================================================================


func test_create_all_actions_returns_all_actions() -> void:
	var actions: Array[GOAPAction] = EnemyActions.create_all_actions()

	assert_eq(actions.size(), 13, "Should create 13 enemy actions")


func test_create_all_actions_includes_all_types() -> void:
	var actions: Array[GOAPAction] = EnemyActions.create_all_actions()

	var action_names: Array[String] = []
	for action in actions:
		action_names.append(action.action_name)

	assert_has(action_names, "seek_cover", "Should include seek_cover")
	assert_has(action_names, "engage_player", "Should include engage_player")
	assert_has(action_names, "flank_player", "Should include flank_player")
	assert_has(action_names, "patrol", "Should include patrol")
	assert_has(action_names, "stay_suppressed", "Should include stay_suppressed")
	assert_has(action_names, "return_fire", "Should include return_fire")
	assert_has(action_names, "find_cover", "Should include find_cover")
	assert_has(action_names, "retreat", "Should include retreat")
	assert_has(action_names, "retreat_with_fire", "Should include retreat_with_fire")
	assert_has(action_names, "pursue_player", "Should include pursue_player")
	assert_has(action_names, "assault_player", "Should include assault_player")
	assert_has(action_names, "attack_distracted_player", "Should include attack_distracted_player")
	assert_has(action_names, "attack_vulnerable_player", "Should include attack_vulnerable_player")


# ============================================================================
# Integration Tests with Planner
# ============================================================================


func test_actions_work_with_planner() -> void:
	var planner := GOAPPlanner.new()
	var actions := EnemyActions.create_all_actions()

	for action in actions:
		planner.add_action(action)

	# Test simple scenario: enemy needs to find and seek cover
	var state := {"has_cover": false, "in_cover": false}
	var goal := {"in_cover": true}

	var plan: Array[GOAPAction] = planner.plan(state, goal)

	assert_gt(plan.size(), 0, "Planner should find a plan to get in cover")
	# Should be find_cover -> seek_cover
	if plan.size() >= 2:
		assert_eq(plan[0].action_name, "find_cover", "First action should be find_cover")
		assert_eq(plan[1].action_name, "seek_cover", "Second action should be seek_cover")


func test_actions_engagement_scenario() -> void:
	var planner := GOAPPlanner.new()
	var actions := EnemyActions.create_all_actions()

	for action in actions:
		planner.add_action(action)

	# Scenario: enemy sees player and wants to engage
	var state := {"player_visible": true}
	var goal := {"player_engaged": true}

	var plan: Array[GOAPAction] = planner.plan(state, goal)

	assert_gt(plan.size(), 0, "Planner should find a plan to engage player")
	# engage_player should be the cheapest option
	assert_eq(plan[0].action_name, "engage_player", "Should choose engage_player")


func test_distracted_player_attack_has_highest_priority() -> void:
	var planner := GOAPPlanner.new()
	var actions := EnemyActions.create_all_actions()

	for action in actions:
		planner.add_action(action)

	# Scenario: enemy sees distracted player and wants to engage
	# attack_distracted_player should be chosen over engage_player due to lower cost
	var state := {"player_visible": true, "player_distracted": true}
	var goal := {"player_engaged": true}

	var plan: Array[GOAPAction] = planner.plan(state, goal)

	assert_gt(plan.size(), 0, "Planner should find a plan to engage distracted player")
	assert_eq(plan[0].action_name, "attack_distracted_player", "Should choose attack_distracted_player (highest priority)")


func test_distracted_player_attack_overrides_other_states() -> void:
	var planner := GOAPPlanner.new()
	var actions := EnemyActions.create_all_actions()

	for action in actions:
		planner.add_action(action)

	# Scenario: enemy is under fire but player is distracted
	# Even when under fire, attack_distracted_player should be chosen
	var state := {
		"player_visible": true,
		"player_distracted": true,
		"under_fire": true,
		"in_cover": true
	}
	var goal := {"player_engaged": true}

	var plan: Array[GOAPAction] = planner.plan(state, goal)

	assert_gt(plan.size(), 0, "Planner should find a plan even when under fire")
	assert_eq(plan[0].action_name, "attack_distracted_player", "Should choose attack_distracted_player even when under fire")


# ============================================================================
# AttackVulnerablePlayerAction Tests
# ============================================================================


func test_attack_vulnerable_player_action_initialization() -> void:
	var action := EnemyActions.AttackVulnerablePlayerAction.new()

	assert_eq(action.action_name, "attack_vulnerable_player", "Action name should be 'attack_vulnerable_player'")
	assert_eq(action.cost, 0.1, "Base cost should be 0.1 (very low = high priority)")


func test_attack_vulnerable_player_action_preconditions() -> void:
	var action := EnemyActions.AttackVulnerablePlayerAction.new()

	assert_eq(action.preconditions["player_visible"], true, "Requires player visible")
	assert_eq(action.preconditions["player_close"], true, "Requires player close")


func test_attack_vulnerable_player_action_effects() -> void:
	var action := EnemyActions.AttackVulnerablePlayerAction.new()

	assert_eq(action.effects["player_engaged"], true, "Effect should set player_engaged")


func test_attack_vulnerable_player_cost_when_reloading_and_close() -> void:
	var action := EnemyActions.AttackVulnerablePlayerAction.new()
	var world_state := {
		"player_reloading": true,
		"player_ammo_empty": false,
		"player_close": true
	}

	var cost: float = action.get_cost(null, world_state)

	assert_eq(cost, 0.05, "Cost should be extremely low when player is reloading and close (highest priority)")


func test_attack_vulnerable_player_cost_when_ammo_empty_and_close() -> void:
	var action := EnemyActions.AttackVulnerablePlayerAction.new()
	var world_state := {
		"player_reloading": false,
		"player_ammo_empty": true,
		"player_close": true
	}

	var cost: float = action.get_cost(null, world_state)

	assert_eq(cost, 0.05, "Cost should be extremely low when player has empty ammo and close (highest priority)")


func test_attack_vulnerable_player_cost_when_vulnerable_but_not_close() -> void:
	var action := EnemyActions.AttackVulnerablePlayerAction.new()
	var world_state := {
		"player_reloading": true,
		"player_ammo_empty": false,
		"player_close": false
	}

	var cost: float = action.get_cost(null, world_state)

	assert_eq(cost, 100.0, "Cost should be very high when player is vulnerable but not close")


func test_attack_vulnerable_player_cost_when_not_vulnerable() -> void:
	var action := EnemyActions.AttackVulnerablePlayerAction.new()
	var world_state := {
		"player_reloading": false,
		"player_ammo_empty": false,
		"player_close": true
	}

	var cost: float = action.get_cost(null, world_state)

	assert_eq(cost, 100.0, "Cost should be very high when player is not vulnerable")


func test_vulnerable_player_attack_has_highest_priority() -> void:
	var planner := GOAPPlanner.new()
	var actions := EnemyActions.create_all_actions()

	for action in actions:
		planner.add_action(action)

	# Scenario: enemy sees vulnerable (reloading) player who is close
	# attack_vulnerable_player should be chosen over engage_player due to lower cost
	var state := {
		"player_visible": true,
		"player_close": true,
		"player_reloading": true,
		"player_ammo_empty": false
	}
	var goal := {"player_engaged": true}

	var plan: Array[GOAPAction] = planner.plan(state, goal)

	assert_gt(plan.size(), 0, "Planner should find a plan to attack vulnerable player")
	assert_eq(plan[0].action_name, "attack_vulnerable_player", "Should choose attack_vulnerable_player (highest priority)")
