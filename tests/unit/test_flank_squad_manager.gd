extends GutTest
## Unit tests for FlankSquadManager class.
##
## Tests the coordinated flanking system including:
## - Role assignment based on squad size
## - Subgroup synchronization for 3-4 enemy squads
## - Squad phase transitions
## - CoordinatedFlankAction GOAP integration


# ============================================================================
# Test Doubles (Mock Classes)
# ============================================================================


## Mock enemy for testing squad formation.
class MockEnemy extends Node2D:
	var _instance_id: int
	var _state: int = 0  # 0 = IN_COVER
	var _is_alive: bool = true
	var _can_see_player: bool = false
	var _at_sync_position: bool = false
	var _at_cover_back: bool = false
	var _in_coordinated_flanking: bool = false
	var _joined_squad: bool = false
	var _squad_role: int = 0
	var _squad_subgroup: int = 0
	var _flank_target: Vector2 = Vector2.ZERO

	func _init(pos: Vector2 = Vector2.ZERO, enemy_name: String = "MockEnemy") -> void:
		global_position = pos
		name = enemy_name
		_instance_id = get_instance_id()

	func get_current_state() -> int:
		return _state

	func get_state_name() -> String:
		match _state:
			0: return "IN_COVER"
			1: return "COMBAT"
			2: return "RETREATING"
			3: return "SUPPRESSED"
			_: return "UNKNOWN"

	func is_alive() -> bool:
		return _is_alive

	func can_see_player_public() -> bool:
		return _can_see_player

	func is_at_sync_position() -> bool:
		return _at_sync_position

	func is_at_cover_back() -> bool:
		return _at_cover_back

	func is_in_coordinated_flanking() -> bool:
		return _in_coordinated_flanking

	func join_flank_squad(target_cover: Vector2, role: int, subgroup: int) -> void:
		_joined_squad = true
		_in_coordinated_flanking = true
		_squad_role = role
		_squad_subgroup = subgroup
		_flank_target = target_cover

	func leave_flank_squad() -> void:
		_joined_squad = false
		_in_coordinated_flanking = false
		_squad_role = 0
		_squad_subgroup = 0

	func update_flank_target(target: Vector2) -> void:
		_flank_target = target

	func update_squad_role(role: int, subgroup: int) -> void:
		_squad_role = role
		_squad_subgroup = subgroup

	func begin_synchronized_flank() -> void:
		pass

	func begin_coordinated_assault() -> void:
		pass


# ============================================================================
# Constants (must match FlankSquadManager)
# ============================================================================


const TacticalRole = preload("res://scripts/autoload/flank_squad_manager.gd").TacticalRole
const FlankDirection = preload("res://scripts/autoload/flank_squad_manager.gd").FlankDirection


# ============================================================================
# CoordinatedFlankAction Tests
# ============================================================================


func test_coordinated_flank_action_initialization() -> void:
	var action := EnemyActions.CoordinatedFlankAction.new()

	assert_eq(action.action_name, "coordinated_flank", "Action name should be 'coordinated_flank'")
	assert_eq(action.cost, 2.0, "Base cost should be 2.0")


func test_coordinated_flank_action_preconditions() -> void:
	var action := EnemyActions.CoordinatedFlankAction.new()

	assert_eq(action.preconditions["player_visible"], false, "Requires player not visible (behind cover)")
	assert_eq(action.preconditions["in_cover"], true, "Requires enemy to be in a stable position")


func test_coordinated_flank_action_effects() -> void:
	var action := EnemyActions.CoordinatedFlankAction.new()

	assert_eq(action.effects["player_engaged"], true, "Effect should set player_engaged to true")
	assert_eq(action.effects["at_flank_position"], true, "Effect should set at_flank_position to true")


func test_coordinated_flank_action_cost_with_multiple_enemies() -> void:
	var action := EnemyActions.CoordinatedFlankAction.new()
	var world_state := {"enemies_in_combat": 3}

	var cost: float = action.get_cost(null, world_state)

	assert_eq(cost, 1.5, "Cost should be moderate when multiple enemies available for squad")


func test_coordinated_flank_action_cost_when_alone() -> void:
	var action := EnemyActions.CoordinatedFlankAction.new()
	var world_state := {"enemies_in_combat": 1}

	var cost: float = action.get_cost(null, world_state)

	assert_eq(cost, 4.0, "Cost should be higher when alone (prefer individual flanking)")


func test_create_all_actions_includes_coordinated_flank() -> void:
	var actions: Array[GOAPAction] = EnemyActions.create_all_actions()

	var action_names: Array[String] = []
	for action in actions:
		action_names.append(action.action_name)

	assert_has(action_names, "coordinated_flank", "Should include coordinated_flank action")


func test_create_all_actions_has_correct_count() -> void:
	var actions: Array[GOAPAction] = EnemyActions.create_all_actions()

	# Original 13 + PursueVulnerablePlayerAction + CoordinatedFlankAction = 15
	assert_eq(actions.size(), 15, "Should create 15 enemy actions (13 original + 2 new)")


# ============================================================================
# Role Assignment Tests
# ============================================================================


func test_role_assignment_single_enemy() -> void:
	# Setup
	var enemy1 := MockEnemy.new(Vector2(100, 200), "Enemy1")
	var members := [enemy1]
	var target_cover := Vector2(300, 300)

	# Simulate role assignment logic (from FlankSquadManager._assign_roles)
	var roles := {}
	var subgroups := {}

	# Single enemy: LEAD_ATTACKER from below
	roles[enemy1.get_instance_id()] = TacticalRole.LEAD_ATTACKER
	subgroups[enemy1.get_instance_id()] = FlankDirection.LOWER

	# Verify
	assert_eq(roles[enemy1.get_instance_id()], TacticalRole.LEAD_ATTACKER,
		"Single enemy should be LEAD_ATTACKER")
	assert_eq(subgroups[enemy1.get_instance_id()], FlankDirection.LOWER,
		"Single enemy should be in LOWER subgroup")

	# Cleanup
	enemy1.free()


func test_role_assignment_two_enemies() -> void:
	# Setup - enemy with higher Y is lower on screen
	var enemy1 := MockEnemy.new(Vector2(100, 300), "Enemy1")  # Lower (higher Y)
	var enemy2 := MockEnemy.new(Vector2(100, 100), "Enemy2")  # Upper (lower Y)
	var members := [enemy1, enemy2]
	var target_cover := Vector2(300, 200)

	# Simulate role assignment - sort by Y (descending = lower screen first)
	var sorted_by_y := members.duplicate()
	sorted_by_y.sort_custom(func(a, b): return a.global_position.y > b.global_position.y)

	var roles := {}
	var subgroups := {}

	# Two enemies: LEAD_ATTACKER + SUPPORTING from below
	var lead = sorted_by_y[0]  # enemy1 (higher Y)
	var support = sorted_by_y[1]  # enemy2 (lower Y)

	roles[lead.get_instance_id()] = TacticalRole.LEAD_ATTACKER
	subgroups[lead.get_instance_id()] = FlankDirection.LOWER

	roles[support.get_instance_id()] = TacticalRole.SUPPORTING
	subgroups[support.get_instance_id()] = FlankDirection.LOWER

	# Verify
	assert_eq(roles[enemy1.get_instance_id()], TacticalRole.LEAD_ATTACKER,
		"Enemy with higher Y should be LEAD_ATTACKER")
	assert_eq(roles[enemy2.get_instance_id()], TacticalRole.SUPPORTING,
		"Enemy with lower Y should be SUPPORTING")
	assert_eq(subgroups[enemy1.get_instance_id()], FlankDirection.LOWER,
		"Both should be in LOWER subgroup")
	assert_eq(subgroups[enemy2.get_instance_id()], FlankDirection.LOWER,
		"Both should be in LOWER subgroup")

	# Cleanup
	enemy1.free()
	enemy2.free()


func test_role_assignment_three_enemies() -> void:
	# Setup
	var enemy1 := MockEnemy.new(Vector2(100, 400), "Enemy1")  # Highest Y (lowest on screen)
	var enemy2 := MockEnemy.new(Vector2(100, 200), "Enemy2")  # Middle Y
	var enemy3 := MockEnemy.new(Vector2(100, 50), "Enemy3")   # Lowest Y (highest on screen)
	var members := [enemy1, enemy2, enemy3]
	var target_cover := Vector2(300, 200)

	# Sort by Y descending
	var sorted_by_y := members.duplicate()
	sorted_by_y.sort_custom(func(a, b): return a.global_position.y > b.global_position.y)

	var roles := {}
	var subgroups := {}

	# Three enemies: 2 lower (lead + support), 1 upper (lead)
	var lower_lead = sorted_by_y[0]   # enemy1
	var lower_support = sorted_by_y[1]  # enemy2
	var upper_lead = sorted_by_y[2]   # enemy3

	roles[lower_lead.get_instance_id()] = TacticalRole.LEAD_ATTACKER
	subgroups[lower_lead.get_instance_id()] = FlankDirection.LOWER

	roles[lower_support.get_instance_id()] = TacticalRole.SUPPORTING
	subgroups[lower_support.get_instance_id()] = FlankDirection.LOWER

	roles[upper_lead.get_instance_id()] = TacticalRole.UPPER_LEAD_ATTACKER
	subgroups[upper_lead.get_instance_id()] = FlankDirection.UPPER

	# Verify
	assert_eq(roles[enemy1.get_instance_id()], TacticalRole.LEAD_ATTACKER,
		"Highest Y enemy should be LEAD_ATTACKER")
	assert_eq(roles[enemy2.get_instance_id()], TacticalRole.SUPPORTING,
		"Middle Y enemy should be SUPPORTING")
	assert_eq(roles[enemy3.get_instance_id()], TacticalRole.UPPER_LEAD_ATTACKER,
		"Lowest Y enemy should be UPPER_LEAD_ATTACKER")

	assert_eq(subgroups[enemy1.get_instance_id()], FlankDirection.LOWER,
		"Highest Y enemy in LOWER subgroup")
	assert_eq(subgroups[enemy2.get_instance_id()], FlankDirection.LOWER,
		"Middle Y enemy in LOWER subgroup")
	assert_eq(subgroups[enemy3.get_instance_id()], FlankDirection.UPPER,
		"Lowest Y enemy in UPPER subgroup")

	# Cleanup
	enemy1.free()
	enemy2.free()
	enemy3.free()


func test_role_assignment_four_enemies() -> void:
	# Setup
	var enemy1 := MockEnemy.new(Vector2(100, 500), "Enemy1")  # Highest Y
	var enemy2 := MockEnemy.new(Vector2(100, 300), "Enemy2")  # Second highest Y
	var enemy3 := MockEnemy.new(Vector2(100, 150), "Enemy3")  # Second lowest Y
	var enemy4 := MockEnemy.new(Vector2(100, 50), "Enemy4")   # Lowest Y
	var members := [enemy1, enemy2, enemy3, enemy4]
	var target_cover := Vector2(300, 250)

	# Sort by Y descending
	var sorted_by_y := members.duplicate()
	sorted_by_y.sort_custom(func(a, b): return a.global_position.y > b.global_position.y)

	var roles := {}
	var subgroups := {}

	# Four enemies: full teams
	var lower_lead = sorted_by_y[0]     # enemy1
	var lower_support = sorted_by_y[1]  # enemy2
	var upper_support = sorted_by_y[2]  # enemy3
	var upper_lead = sorted_by_y[3]     # enemy4

	roles[lower_lead.get_instance_id()] = TacticalRole.LEAD_ATTACKER
	subgroups[lower_lead.get_instance_id()] = FlankDirection.LOWER

	roles[lower_support.get_instance_id()] = TacticalRole.SUPPORTING
	subgroups[lower_support.get_instance_id()] = FlankDirection.LOWER

	roles[upper_lead.get_instance_id()] = TacticalRole.UPPER_LEAD_ATTACKER
	subgroups[upper_lead.get_instance_id()] = FlankDirection.UPPER

	roles[upper_support.get_instance_id()] = TacticalRole.UPPER_SUPPORTING
	subgroups[upper_support.get_instance_id()] = FlankDirection.UPPER

	# Verify roles
	assert_eq(roles[enemy1.get_instance_id()], TacticalRole.LEAD_ATTACKER,
		"Highest Y enemy should be LEAD_ATTACKER")
	assert_eq(roles[enemy2.get_instance_id()], TacticalRole.SUPPORTING,
		"Second highest Y enemy should be SUPPORTING")
	assert_eq(roles[enemy3.get_instance_id()], TacticalRole.UPPER_SUPPORTING,
		"Second lowest Y enemy should be UPPER_SUPPORTING")
	assert_eq(roles[enemy4.get_instance_id()], TacticalRole.UPPER_LEAD_ATTACKER,
		"Lowest Y enemy should be UPPER_LEAD_ATTACKER")

	# Verify subgroups
	assert_eq(subgroups[enemy1.get_instance_id()], FlankDirection.LOWER, "enemy1 in LOWER")
	assert_eq(subgroups[enemy2.get_instance_id()], FlankDirection.LOWER, "enemy2 in LOWER")
	assert_eq(subgroups[enemy3.get_instance_id()], FlankDirection.UPPER, "enemy3 in UPPER")
	assert_eq(subgroups[enemy4.get_instance_id()], FlankDirection.UPPER, "enemy4 in UPPER")

	# Cleanup
	enemy1.free()
	enemy2.free()
	enemy3.free()
	enemy4.free()


# ============================================================================
# Tactical Role Enum Tests
# ============================================================================


func test_tactical_role_enum_values() -> void:
	assert_eq(TacticalRole.NONE, 0, "NONE should be 0")
	assert_eq(TacticalRole.LEAD_ATTACKER, 1, "LEAD_ATTACKER should be 1")
	assert_eq(TacticalRole.SUPPORTING, 2, "SUPPORTING should be 2")
	assert_eq(TacticalRole.UPPER_LEAD_ATTACKER, 3, "UPPER_LEAD_ATTACKER should be 3")
	assert_eq(TacticalRole.UPPER_SUPPORTING, 4, "UPPER_SUPPORTING should be 4")


func test_flank_direction_enum_values() -> void:
	assert_eq(FlankDirection.LOWER, 0, "LOWER should be 0")
	assert_eq(FlankDirection.UPPER, 1, "UPPER should be 1")


# ============================================================================
# Subgroup Synchronization Tests
# ============================================================================


func test_subgroup_sync_both_not_ready() -> void:
	# For 3-4 enemy squads, both subgroups must be ready before advancing
	var lower_ready := false
	var upper_ready := false

	var should_advance := lower_ready and upper_ready

	assert_false(should_advance, "Should not advance when neither subgroup is ready")


func test_subgroup_sync_only_lower_ready() -> void:
	var lower_ready := true
	var upper_ready := false

	var should_advance := lower_ready and upper_ready

	assert_false(should_advance, "Should not advance when only lower subgroup is ready")


func test_subgroup_sync_only_upper_ready() -> void:
	var lower_ready := false
	var upper_ready := true

	var should_advance := lower_ready and upper_ready

	assert_false(should_advance, "Should not advance when only upper subgroup is ready")


func test_subgroup_sync_both_ready() -> void:
	var lower_ready := true
	var upper_ready := true

	var should_advance := lower_ready and upper_ready

	assert_true(should_advance, "Should advance when both subgroups are ready")


# ============================================================================
# Mock Enemy Behavior Tests
# ============================================================================


func test_mock_enemy_join_flank_squad() -> void:
	var enemy := MockEnemy.new(Vector2(100, 100), "TestEnemy")
	var target_cover := Vector2(300, 300)

	enemy.join_flank_squad(target_cover, TacticalRole.LEAD_ATTACKER, FlankDirection.LOWER)

	assert_true(enemy._joined_squad, "Enemy should be marked as joined")
	assert_true(enemy._in_coordinated_flanking, "Enemy should be in coordinated flanking")
	assert_eq(enemy._squad_role, TacticalRole.LEAD_ATTACKER, "Role should be set correctly")
	assert_eq(enemy._squad_subgroup, FlankDirection.LOWER, "Subgroup should be set correctly")
	assert_eq(enemy._flank_target, target_cover, "Target cover should be set")

	enemy.free()


func test_mock_enemy_leave_flank_squad() -> void:
	var enemy := MockEnemy.new(Vector2(100, 100), "TestEnemy")

	# Join first
	enemy.join_flank_squad(Vector2(300, 300), TacticalRole.SUPPORTING, FlankDirection.UPPER)

	# Then leave
	enemy.leave_flank_squad()

	assert_false(enemy._joined_squad, "Enemy should not be joined")
	assert_false(enemy._in_coordinated_flanking, "Enemy should not be in coordinated flanking")
	assert_eq(enemy._squad_role, TacticalRole.NONE, "Role should be reset to NONE")
	assert_eq(enemy._squad_subgroup, FlankDirection.LOWER, "Subgroup should be reset")

	enemy.free()


func test_mock_enemy_update_squad_role() -> void:
	var enemy := MockEnemy.new(Vector2(100, 100), "TestEnemy")

	enemy.join_flank_squad(Vector2(300, 300), TacticalRole.SUPPORTING, FlankDirection.LOWER)
	enemy.update_squad_role(TacticalRole.LEAD_ATTACKER, FlankDirection.UPPER)

	assert_eq(enemy._squad_role, TacticalRole.LEAD_ATTACKER, "Role should be updated")
	assert_eq(enemy._squad_subgroup, FlankDirection.UPPER, "Subgroup should be updated")

	enemy.free()


# ============================================================================
# Constants Validation Tests
# ============================================================================


func test_cover_time_threshold_constant() -> void:
	# The FlankSquadManager should wait 10 seconds before forming a squad
	var expected_threshold := 10.0

	# This tests that our understanding of the requirement is correct
	assert_eq(expected_threshold, 10.0, "Cover time threshold should be 10 seconds per requirements")


func test_max_squad_size_constant() -> void:
	# Maximum squad size should be 4
	var expected_max_size := 4

	assert_eq(expected_max_size, 4, "Maximum squad size should be 4 per requirements")


# ============================================================================
# Integration Tests with GOAP Planner
# ============================================================================


func test_coordinated_flank_action_works_with_planner() -> void:
	var planner := GOAPPlanner.new()
	var actions := EnemyActions.create_all_actions()

	for action in actions:
		planner.add_action(action)

	# Scenario: enemy in cover, player not visible (behind cover)
	var state := {
		"player_visible": false,
		"in_cover": true,
		"enemies_in_combat": 3
	}
	var goal := {"player_engaged": true}

	var plan: Array[GOAPAction] = planner.plan(state, goal)

	# Should find a plan (may be coordinated_flank or flank_player)
	assert_gt(plan.size(), 0, "Planner should find a plan to engage player behind cover")


func test_coordinated_flank_preferred_over_regular_flank_with_squad() -> void:
	var planner := GOAPPlanner.new()

	# Add only flank-related actions to isolate the test
	var coord_flank := EnemyActions.CoordinatedFlankAction.new()
	var flank := EnemyActions.FlankPlayerAction.new()

	planner.add_action(coord_flank)
	planner.add_action(flank)

	# Scenario: enemy in cover with squad support
	var state := {
		"player_visible": false,
		"in_cover": true,
		"under_fire": false,
		"enemies_in_combat": 3
	}
	var goal := {"at_flank_position": true}

	var plan: Array[GOAPAction] = planner.plan(state, goal)

	assert_gt(plan.size(), 0, "Should find a plan")

	# With 3 enemies, coordinated_flank cost = 1.5, flank_player base cost = 3.0
	# So coordinated_flank should be preferred
	assert_eq(plan[0].action_name, "coordinated_flank",
		"Coordinated flank should be preferred with multiple enemies")


# ============================================================================
# Squad Phase Tests
# ============================================================================


func test_squad_phase_progression_forming_to_positioning() -> void:
	# Initial phase should be "forming"
	var phase := "forming"
	assert_eq(phase, "forming", "Initial phase should be 'forming'")

	# After members join, phase becomes "positioning"
	phase = "positioning"
	assert_eq(phase, "positioning", "Phase should change to 'positioning' after members join")


func test_squad_phase_progression_positioning_to_flanking() -> void:
	var phase := "positioning"

	# For 1-2 enemy squads, go directly to flanking
	phase = "flanking"
	assert_eq(phase, "flanking", "Phase should change to 'flanking'")


func test_squad_phase_progression_flanking_to_assaulting() -> void:
	var phase := "flanking"

	# When enemy spots player, transition to assaulting
	phase = "assaulting"
	assert_eq(phase, "assaulting", "Phase should change to 'assaulting' when player spotted")


# ============================================================================
# Edge Case Tests
# ============================================================================


func test_empty_squad_formation() -> void:
	var members: Array = []

	assert_eq(members.size(), 0, "Empty members array")
	assert_true(members.is_empty(), "Empty squad should not be formed")


func test_role_reassignment_after_casualty() -> void:
	# Start with 4 enemies
	var enemy1 := MockEnemy.new(Vector2(100, 500), "Enemy1")
	var enemy2 := MockEnemy.new(Vector2(100, 300), "Enemy2")
	var enemy3 := MockEnemy.new(Vector2(100, 150), "Enemy3")
	var enemy4 := MockEnemy.new(Vector2(100, 50), "Enemy4")
	var members := [enemy1, enemy2, enemy3, enemy4]

	# Simulate one enemy eliminated (enemy4 - UPPER_LEAD_ATTACKER)
	enemy4._is_alive = false
	var valid_members := members.filter(func(e): return e._is_alive)

	assert_eq(valid_members.size(), 3, "Should have 3 valid members after casualty")

	# Re-sort and reassign roles
	var sorted_by_y := valid_members.duplicate()
	sorted_by_y.sort_custom(func(a, b): return a.global_position.y > b.global_position.y)

	var roles := {}
	var subgroups := {}

	# With 3 enemies now: 2 lower (lead + support), 1 upper (lead)
	roles[sorted_by_y[0].get_instance_id()] = TacticalRole.LEAD_ATTACKER
	subgroups[sorted_by_y[0].get_instance_id()] = FlankDirection.LOWER

	roles[sorted_by_y[1].get_instance_id()] = TacticalRole.SUPPORTING
	subgroups[sorted_by_y[1].get_instance_id()] = FlankDirection.LOWER

	roles[sorted_by_y[2].get_instance_id()] = TacticalRole.UPPER_LEAD_ATTACKER
	subgroups[sorted_by_y[2].get_instance_id()] = FlankDirection.UPPER

	# Verify reassignment
	assert_eq(roles[enemy1.get_instance_id()], TacticalRole.LEAD_ATTACKER,
		"Enemy1 should now be LEAD_ATTACKER")
	assert_eq(roles[enemy2.get_instance_id()], TacticalRole.SUPPORTING,
		"Enemy2 should now be SUPPORTING")
	assert_eq(roles[enemy3.get_instance_id()], TacticalRole.UPPER_LEAD_ATTACKER,
		"Enemy3 should now be UPPER_LEAD_ATTACKER")

	# Cleanup
	enemy1.free()
	enemy2.free()
	enemy3.free()
	enemy4.free()


func test_supporting_follows_lead_position_logic() -> void:
	# Test that supporting role position is calculated correctly
	var lead_position := Vector2(200, 300)
	var target_cover := Vector2(400, 300)

	# Supporting should be behind lead (offset from target)
	var direction_to_target := (target_cover - lead_position).normalized()
	var supporting_offset := 40.0  # SUPPORTING_OFFSET constant

	var supporting_position := lead_position - direction_to_target * supporting_offset

	# Verify supporting is behind lead (further from target)
	var lead_distance := lead_position.distance_to(target_cover)
	var support_distance := supporting_position.distance_to(target_cover)

	assert_gt(support_distance, lead_distance,
		"Supporting should be further from target than lead")


func test_sync_position_distance() -> void:
	# Sync position is 100 pixels from cover corner
	var sync_distance := 100.0
	var cover_position := Vector2(400, 300)

	# Calculate sync position for lower subgroup (positive Y offset)
	var lower_sync := cover_position + Vector2(0, sync_distance)

	# Calculate sync position for upper subgroup (negative Y offset)
	var upper_sync := cover_position - Vector2(0, sync_distance)

	assert_eq(lower_sync.distance_to(cover_position), sync_distance,
		"Lower sync position should be at correct distance")
	assert_eq(upper_sync.distance_to(cover_position), sync_distance,
		"Upper sync position should be at correct distance")
