extends GutTest
## Unit tests for SquadCoordinatorComponent (Issue #1373).
##
## Tests squad formation, cover deconfliction, role assignment,
## firing lane awareness, and coordinated movement.


# ============================================================================
# Mock Enemy for testing squad coordination
# ============================================================================

class MockSquadEnemy extends Node2D:
	var _state: int = 1  # COMBAT
	var _health: float = 3.0
	var _max_health: float = 4.0
	var _has_cover: bool = false
	var _can_see: bool = true
	var _is_shooting: bool = false
	var _fire_dir: Vector2 = Vector2.RIGHT
	var _claimed_cover: Vector2 = Vector2.INF
	var _squad_coordinator: SquadCoordinatorComponent = null

	func get_current_state() -> int: return _state
	func is_alive_enemy() -> bool: return true
	func get_health_ratio() -> float: return _health / _max_health if _max_health > 0 else 0.0
	func has_valid_cover_position() -> bool: return _has_cover
	func can_see_player_now() -> bool: return _can_see
	func is_actively_shooting() -> bool: return _is_shooting
	func get_firing_direction() -> Vector2: return _fire_dir if _is_shooting else Vector2.ZERO
	func get_squad_claimed_cover() -> Vector2: return _claimed_cover


# ============================================================================
# Helper methods
# ============================================================================

var _enemies: Array[MockSquadEnemy] = []


func _create_enemy(pos: Vector2, state: int = 1) -> MockSquadEnemy:
	var e := MockSquadEnemy.new()
	e.global_position = pos
	e._state = state
	add_child(e)
	e.add_to_group("enemies")
	_enemies.append(e)
	return e


func after_each() -> void:
	for e in _enemies:
		if is_instance_valid(e):
			e.remove_from_group("enemies")
			e.queue_free()
	_enemies.clear()


# ============================================================================
# Tests: Squad Formation
# ============================================================================

func test_no_squad_when_alone() -> void:
	var e := _create_enemy(Vector2(100, 100))
	var squad := SquadCoordinatorComponent.new(e)
	squad.tick(0.6, Vector2(500, 500))  # Tick past UPDATE_INTERVAL
	assert_eq(squad.current_role, SquadCoordinatorComponent.SquadRole.NONE,
		"Single enemy should have no squad role")
	assert_eq(squad.get_squad_size(), 0,
		"Squad size should be 0 when alone (below MIN_SQUAD_SIZE)")


func test_squad_forms_with_two_enemies() -> void:
	var e1 := _create_enemy(Vector2(100, 100), 1)  # COMBAT
	var e2 := _create_enemy(Vector2(200, 100), 7)  # PURSUING
	var squad1 := SquadCoordinatorComponent.new(e1)
	var squad2 := SquadCoordinatorComponent.new(e2)
	squad1.tick(0.6, Vector2(500, 500))
	squad2.tick(0.6, Vector2(500, 500))
	assert_ne(squad1.current_role, SquadCoordinatorComponent.SquadRole.NONE,
		"Enemy 1 should have a squad role when 2 enemies present")
	assert_ne(squad2.current_role, SquadCoordinatorComponent.SquadRole.NONE,
		"Enemy 2 should have a squad role when 2 enemies present")
	assert_eq(squad1.get_squad_size(), 2, "Squad should have 2 members")


func test_squad_not_formed_when_too_far() -> void:
	var e1 := _create_enemy(Vector2(0, 0), 1)
	var e2 := _create_enemy(Vector2(1200, 0), 1)  # Beyond SQUAD_RADIUS (1000)
	var squad1 := SquadCoordinatorComponent.new(e1)
	squad1.tick(0.6, Vector2(500, 500))
	assert_eq(squad1.current_role, SquadCoordinatorComponent.SquadRole.NONE,
		"Enemies beyond 1000px should not form a squad")


func test_idle_enemies_excluded_from_squad() -> void:
	var e1 := _create_enemy(Vector2(100, 100), 1)  # COMBAT
	var e2 := _create_enemy(Vector2(200, 100), 0)  # IDLE — not active
	var squad := SquadCoordinatorComponent.new(e1)
	squad.tick(0.6, Vector2(500, 500))
	assert_eq(squad.current_role, SquadCoordinatorComponent.SquadRole.NONE,
		"IDLE enemies should not count toward squad formation")


# ============================================================================
# Tests: Cover Deconfliction
# ============================================================================

func test_cover_claim_and_check() -> void:
	var e1 := _create_enemy(Vector2(100, 100), 1)
	var e2 := _create_enemy(Vector2(200, 100), 1)
	e1._claimed_cover = Vector2(400, 400)
	var squad := SquadCoordinatorComponent.new(e2)
	# Position within tolerance of e1's claim
	assert_true(squad.is_cover_claimed(Vector2(420, 400)),
		"Cover within 80px of ally's claim should be considered claimed")
	# Position far from e1's claim
	assert_false(squad.is_cover_claimed(Vector2(600, 600)),
		"Cover far from ally's claim should not be considered claimed")


func test_cover_released_on_request() -> void:
	var e := _create_enemy(Vector2(100, 100), 1)
	var squad := SquadCoordinatorComponent.new(e)
	squad.claim_cover(Vector2(300, 300))
	assert_eq(squad.get_claimed_cover(), Vector2(300, 300),
		"Claimed cover should be returned")
	squad.release_cover()
	assert_eq(squad.get_claimed_cover(), Vector2.INF,
		"Released cover should return INF")


# ============================================================================
# Tests: Role Assignment
# ============================================================================

func test_role_assignment_with_three_enemies() -> void:
	var e1 := _create_enemy(Vector2(100, 100), 3)  # IN_COVER — good suppressor
	e1._has_cover = true
	e1._can_see = true
	var e2 := _create_enemy(Vector2(800, 100), 4)  # FLANKING
	var e3 := _create_enemy(Vector2(300, 400), 7)  # PURSUING — good rusher
	var squad1 := SquadCoordinatorComponent.new(e1)
	var squad2 := SquadCoordinatorComponent.new(e2)
	var squad3 := SquadCoordinatorComponent.new(e3)
	var player_pos := Vector2(500, 300)
	squad1.tick(0.6, player_pos)
	squad2.tick(0.6, player_pos)
	squad3.tick(0.6, player_pos)
	# All should have roles assigned
	assert_ne(squad1.current_role, SquadCoordinatorComponent.SquadRole.NONE)
	assert_ne(squad2.current_role, SquadCoordinatorComponent.SquadRole.NONE)
	assert_ne(squad3.current_role, SquadCoordinatorComponent.SquadRole.NONE)
	# At least one should be SUPPRESSOR (guaranteed in pool for n>=2)
	var roles := [squad1.current_role, squad2.current_role, squad3.current_role]
	assert_true(SquadCoordinatorComponent.SquadRole.SUPPRESSOR in roles,
		"At least one enemy should be assigned SUPPRESSOR role")


# ============================================================================
# Tests: Suppressive Fire Coordination
# ============================================================================

func test_covering_fire_when_ally_moves() -> void:
	var e1 := _create_enemy(Vector2(100, 100), 3)  # IN_COVER
	e1._has_cover = true
	var e2 := _create_enemy(Vector2(200, 100), 7)  # PURSUING
	var squad := SquadCoordinatorComponent.new(e1)
	squad.tick(0.6, Vector2(500, 500))
	# Force suppressor role for testing
	squad.current_role = SquadCoordinatorComponent.SquadRole.SUPPRESSOR
	squad._squad_members = [e1, e2]
	assert_true(squad.should_provide_covering_fire(),
		"Suppressor should provide covering fire when ally is PURSUING")


func test_no_covering_fire_when_not_suppressor() -> void:
	var e1 := _create_enemy(Vector2(100, 100), 3)
	var e2 := _create_enemy(Vector2(200, 100), 7)
	var squad := SquadCoordinatorComponent.new(e1)
	squad.current_role = SquadCoordinatorComponent.SquadRole.RUSHER
	squad._squad_members = [e1, e2]
	assert_false(squad.should_provide_covering_fire(),
		"Non-suppressor should not provide covering fire")


# ============================================================================
# Tests: Firing Lane Awareness
# ============================================================================

func test_firing_lane_detected() -> void:
	var shooter := _create_enemy(Vector2(100, 200), 1)
	shooter._is_shooting = true
	shooter._fire_dir = Vector2.RIGHT
	var mover := _create_enemy(Vector2(50, 200), 7)
	var squad := SquadCoordinatorComponent.new(mover)
	# Position directly in front of the shooter
	var danger_pos := Vector2(200, 200)
	assert_true(squad.is_in_ally_firing_lane(danger_pos),
		"Position in ally's firing lane should be detected as dangerous")


func test_firing_lane_safe_position() -> void:
	var shooter := _create_enemy(Vector2(100, 200), 1)
	shooter._is_shooting = true
	shooter._fire_dir = Vector2.RIGHT
	var mover := _create_enemy(Vector2(50, 200), 7)
	var squad := SquadCoordinatorComponent.new(mover)
	# Position far off to the side
	var safe_pos := Vector2(200, 500)
	assert_false(squad.is_in_ally_firing_lane(safe_pos),
		"Position far from ally's firing lane should be safe")


# ============================================================================
# Tests: Coordinated Movement (Squad Spacing)
# ============================================================================

func test_squad_spacing_pushes_target_away() -> void:
	var e1 := _create_enemy(Vector2(100, 100), 1)
	var e2 := _create_enemy(Vector2(150, 100), 1)  # Close to target position
	var squad := SquadCoordinatorComponent.new(e1)
	squad._squad_members = [e1, e2]
	squad.current_role = SquadCoordinatorComponent.SquadRole.RUSHER
	# Target position right on top of e2
	var target := Vector2(150, 100)
	var adjusted := squad.get_coordinated_target(target, 0.016)
	assert_ne(adjusted, target,
		"Target on top of ally should be pushed away for spacing")
	# The push should increase distance from e2
	assert_gt(adjusted.distance_to(e2.global_position), target.distance_to(e2.global_position),
		"Adjusted target should be farther from ally than original")


# ============================================================================
# Tests: Debug Info
# ============================================================================

func test_debug_info_empty_when_no_squad() -> void:
	var e := _create_enemy(Vector2(100, 100), 1)
	var squad := SquadCoordinatorComponent.new(e)
	assert_eq(squad.get_debug_info(), "",
		"Debug info should be empty when no squad active")


func test_debug_info_shows_role() -> void:
	var e := _create_enemy(Vector2(100, 100), 1)
	var squad := SquadCoordinatorComponent.new(e)
	squad.current_role = SquadCoordinatorComponent.SquadRole.FLANKER
	squad._squad_members = [e]
	assert_string_contains(squad.get_debug_info(), "FLANKER",
		"Debug info should contain the role name")
