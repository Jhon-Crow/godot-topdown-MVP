extends GutTest
## Unit tests for flashlight-related GOAP actions (Issue #574).
##
## Tests the InvestigateFlashlightAction and AvoidFlashlightPassageAction
## that allow enemies to react to the player's flashlight.


# ============================================================================
# InvestigateFlashlightAction Tests
# ============================================================================


func test_investigate_flashlight_action_initialization() -> void:
	var action := EnemyActions.InvestigateFlashlightAction.new()

	assert_eq(action.action_name, "investigate_flashlight",
		"Action name should be 'investigate_flashlight'")
	assert_eq(action.cost, 1.3, "Base cost should be 1.3")


func test_investigate_flashlight_action_preconditions() -> void:
	var action := EnemyActions.InvestigateFlashlightAction.new()

	assert_eq(action.preconditions["flashlight_detected"], true,
		"Requires flashlight_detected to be true")
	assert_eq(action.preconditions["player_visible"], false,
		"Requires player_visible to be false")


func test_investigate_flashlight_action_effects() -> void:
	var action := EnemyActions.InvestigateFlashlightAction.new()

	assert_eq(action.effects["is_pursuing"], true,
		"Effect should set is_pursuing to true")
	assert_eq(action.effects["player_visible"], true,
		"Effect should set player_visible to true (goal)")


func test_investigate_flashlight_action_cost_when_detected() -> void:
	var action := EnemyActions.InvestigateFlashlightAction.new()
	var world_state := {"flashlight_detected": true}

	var cost: float = action.get_cost(null, world_state)

	assert_eq(cost, 0.9, "Cost should be 0.9 when flashlight is detected")


func test_investigate_flashlight_action_cost_when_not_detected() -> void:
	var action := EnemyActions.InvestigateFlashlightAction.new()
	var world_state := {"flashlight_detected": false}

	var cost: float = action.get_cost(null, world_state)

	assert_eq(cost, 100.0, "Cost should be 100.0 when flashlight is not detected")


func test_investigate_flashlight_action_cost_default_state() -> void:
	var action := EnemyActions.InvestigateFlashlightAction.new()
	var world_state := {}

	var cost: float = action.get_cost(null, world_state)

	assert_eq(cost, 100.0, "Cost should be 100.0 with empty world state")


# ============================================================================
# AvoidFlashlightPassageAction Tests
# ============================================================================


func test_avoid_flashlight_passage_action_initialization() -> void:
	var action := EnemyActions.AvoidFlashlightPassageAction.new()

	assert_eq(action.action_name, "avoid_flashlight_passage",
		"Action name should be 'avoid_flashlight_passage'")
	assert_eq(action.cost, 2.0, "Base cost should be 2.0")


func test_avoid_flashlight_passage_action_preconditions() -> void:
	var action := EnemyActions.AvoidFlashlightPassageAction.new()

	assert_eq(action.preconditions["passage_lit_by_flashlight"], true,
		"Requires passage_lit_by_flashlight to be true")
	assert_eq(action.preconditions["player_visible"], false,
		"Requires player_visible to be false")


func test_avoid_flashlight_passage_action_effects() -> void:
	var action := EnemyActions.AvoidFlashlightPassageAction.new()

	assert_eq(action.effects["passage_lit_by_flashlight"], false,
		"Effect should set passage_lit_by_flashlight to false")
	assert_eq(action.effects["is_pursuing"], true,
		"Effect should set is_pursuing to true (rerouted)")


func test_avoid_flashlight_passage_action_cost_when_lit() -> void:
	var action := EnemyActions.AvoidFlashlightPassageAction.new()
	var world_state := {"passage_lit_by_flashlight": true}

	var cost: float = action.get_cost(null, world_state)

	assert_eq(cost, 1.5, "Cost should be 1.5 when passage is lit")


func test_avoid_flashlight_passage_action_cost_when_not_lit() -> void:
	var action := EnemyActions.AvoidFlashlightPassageAction.new()
	var world_state := {"passage_lit_by_flashlight": false}

	var cost: float = action.get_cost(null, world_state)

	assert_eq(cost, 100.0, "Cost should be 100.0 when passage is not lit")


# ============================================================================
# create_all_actions() Tests
# ============================================================================


func test_create_all_actions_includes_flashlight_actions() -> void:
	var actions := EnemyActions.create_all_actions()

	var has_investigate := false
	var has_avoid := false
	for action in actions:
		if action.action_name == "investigate_flashlight":
			has_investigate = true
		elif action.action_name == "avoid_flashlight_passage":
			has_avoid = true

	assert_true(has_investigate,
		"create_all_actions should include InvestigateFlashlightAction")
	assert_true(has_avoid,
		"create_all_actions should include AvoidFlashlightPassageAction")


func test_create_all_actions_flashlight_action_count() -> void:
	var actions := EnemyActions.create_all_actions()

	# Should have exactly 22 actions total (20 existing + 2 new flashlight actions)
	assert_eq(actions.size(), 22,
		"create_all_actions should return 22 actions (including 2 flashlight actions)")
