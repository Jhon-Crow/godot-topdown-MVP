extends GutTest
## Tests for shieldbearer-as-cover behavior (Issue #1446).
##
## Validates that other enemies perceive a shieldbearer with an active shield
## as mobile cover: they move behind the shieldbearer, enter IN_COVER state,
## can shoot from formation, and disengage when the shield breaks.

const ShieldComponent := preload("res://scripts/components/enemy_shield_component.gd")


## Minimal mock for an enemy that can follow a shieldbearer formation.
class MockFormationEnemy:
	enum AIState { IDLE, COMBAT, SEEKING_COVER, IN_COVER, SUPPRESSED }

	var _formation_shielder: Node2D = null
	var _formation_target_pos: Vector2 = Vector2.ZERO
	var _cover_position: Vector2 = Vector2.ZERO
	var _has_valid_cover: bool = false
	var _current_state: AIState = AIState.IDLE

	func set_formation_follow_target(shielder: Node2D, pos: Vector2) -> void:
		_formation_shielder = shielder
		_formation_target_pos = pos

	## Simulate arriving at formation position — set cover state (mirrors enemy.gd logic).
	func arrive_at_formation() -> void:
		if _formation_shielder == null:
			return
		_cover_position = _formation_target_pos
		_has_valid_cover = true
		if _current_state != AIState.IN_COVER and _current_state != AIState.COMBAT and _current_state != AIState.SUPPRESSED:
			_current_state = AIState.IN_COVER

	## Simulate shieldbearer validation check (mirrors enemy.gd _process_ai_state logic).
	func validate_formation_shielder() -> void:
		if _formation_shielder != null and not _formation_shielder.has_method("is_shield_active"):
			_formation_shielder = null
		elif _formation_shielder != null and not _formation_shielder.is_shield_active():
			_formation_shielder = null

	## Simulate _process_in_cover_state "lost sight of player" branch (mirrors enemy.gd line 1803).
	## Returns true if the enemy would transition to PURSUING (only when _formation_shielder is null).
	func process_in_cover_lost_sight() -> bool:
		# Mirrors: if _formation_shielder == null and not (can_see) and not under_fire and not suppressive:
		if _formation_shielder == null:
			_current_state = AIState.IDLE  # stand-in for PURSUING
			return true
		return false  # formation enemy stays in cover — Issue #1446 fix

	func is_in_cover() -> bool:
		return _current_state == AIState.IN_COVER

	func has_valid_cover() -> bool:
		return _has_valid_cover


## Mock shieldbearer node.
class MockShieldbearer extends Node2D:
	var _shield_active: bool = true

	func is_shield_active() -> bool:
		return _shield_active


# =============================================================================
# Formation Follow → Cover State
# =============================================================================


func test_enemy_enters_cover_when_at_formation_position() -> void:
	var shielder := MockShieldbearer.new()
	add_child_autofree(shielder)
	shielder._shield_active = true

	var follower := MockFormationEnemy.new()
	follower.set_formation_follow_target(shielder, Vector2(100, 0))
	follower.arrive_at_formation()

	assert_true(follower.is_in_cover(),
		"Enemy should enter IN_COVER state when at formation position behind shieldbearer")


func test_cover_position_matches_formation_target() -> void:
	var shielder := MockShieldbearer.new()
	add_child_autofree(shielder)

	var follower := MockFormationEnemy.new()
	var formation_pos := Vector2(200, 50)
	follower.set_formation_follow_target(shielder, formation_pos)
	follower.arrive_at_formation()

	assert_eq(follower._cover_position, formation_pos,
		"Cover position should match formation target position")


func test_has_valid_cover_when_behind_shieldbearer() -> void:
	var shielder := MockShieldbearer.new()
	add_child_autofree(shielder)

	var follower := MockFormationEnemy.new()
	follower.set_formation_follow_target(shielder, Vector2(100, 0))
	follower.arrive_at_formation()

	assert_true(follower.has_valid_cover(),
		"Enemy should have valid cover when behind shieldbearer")


# =============================================================================
# Shield Break → Cover Invalidation
# =============================================================================


func test_formation_clears_when_shield_breaks() -> void:
	var shielder := MockShieldbearer.new()
	add_child_autofree(shielder)
	shielder._shield_active = true

	var follower := MockFormationEnemy.new()
	follower.set_formation_follow_target(shielder, Vector2(100, 0))
	follower.arrive_at_formation()

	assert_true(follower.is_in_cover(), "Should be in cover initially")

	# Shield breaks
	shielder._shield_active = false
	follower.validate_formation_shielder()

	assert_eq(follower._formation_shielder, null,
		"Formation shielder should be cleared when shield breaks")


func test_formation_clears_when_shielder_invalid() -> void:
	var follower := MockFormationEnemy.new()
	# Set a non-Node2D shielder that doesn't have is_shield_active
	var fake_shielder := Node2D.new()
	add_child_autofree(fake_shielder)
	follower._formation_shielder = fake_shielder

	follower.validate_formation_shielder()

	assert_eq(follower._formation_shielder, null,
		"Formation should clear when shielder lacks is_shield_active method")


# =============================================================================
# No Cover Without Shieldbearer
# =============================================================================


func test_no_cover_without_formation_shielder() -> void:
	var follower := MockFormationEnemy.new()
	follower.arrive_at_formation()

	assert_false(follower.is_in_cover(),
		"Enemy should not enter cover without a formation shielder")


func test_no_valid_cover_without_formation_shielder() -> void:
	var follower := MockFormationEnemy.new()
	follower.arrive_at_formation()

	assert_false(follower.has_valid_cover(),
		"Enemy should not have valid cover without a formation shielder")


# =============================================================================
# State Preservation (Don't Override Combat/Suppressed)
# =============================================================================


func test_does_not_override_combat_state() -> void:
	var shielder := MockShieldbearer.new()
	add_child_autofree(shielder)

	var follower := MockFormationEnemy.new()
	follower._current_state = MockFormationEnemy.AIState.COMBAT
	follower.set_formation_follow_target(shielder, Vector2(100, 0))
	follower.arrive_at_formation()

	assert_eq(follower._current_state, MockFormationEnemy.AIState.COMBAT,
		"Should not override COMBAT state when arriving at formation")


func test_does_not_override_suppressed_state() -> void:
	var shielder := MockShieldbearer.new()
	add_child_autofree(shielder)

	var follower := MockFormationEnemy.new()
	follower._current_state = MockFormationEnemy.AIState.SUPPRESSED
	follower.set_formation_follow_target(shielder, Vector2(100, 0))
	follower.arrive_at_formation()

	assert_eq(follower._current_state, MockFormationEnemy.AIState.SUPPRESSED,
		"Should not override SUPPRESSED state when arriving at formation")


# =============================================================================
# Shield Component Constants Used for Cover
# =============================================================================


func test_formation_radius_used_for_cover_range() -> void:
	assert_eq(ShieldComponent.FORMATION_RADIUS, 350.0,
		"FORMATION_RADIUS defines max range for shieldbearer cover detection")


func test_formation_offset_used_for_cover_position() -> void:
	assert_eq(ShieldComponent.FORMATION_OFFSET, 80.0,
		"FORMATION_OFFSET defines distance behind shieldbearer for cover position")


# =============================================================================
# Cover Position Tracks Shieldbearer Movement
# =============================================================================


func test_cover_position_updates_with_shieldbearer() -> void:
	var shielder := MockShieldbearer.new()
	add_child_autofree(shielder)

	var follower := MockFormationEnemy.new()

	# Initial position
	follower.set_formation_follow_target(shielder, Vector2(100, 0))
	follower.arrive_at_formation()
	assert_eq(follower._cover_position, Vector2(100, 0))

	# Shieldbearer moves — formation target updated by shield component
	follower.set_formation_follow_target(shielder, Vector2(150, 30))
	follower.arrive_at_formation()
	assert_eq(follower._cover_position, Vector2(150, 30),
		"Cover position should track shieldbearer movement")


# =============================================================================
# Shieldbearer Cover Candidate Generation
# =============================================================================


func test_shieldbearer_cover_position_is_behind_shielder() -> void:
	# Validate the geometry: cover position should be on the opposite side from player
	var shielder_pos := Vector2(200, 0)
	var player_pos := Vector2(400, 0)

	var shielder_to_player := (player_pos - shielder_pos).normalized()
	var behind_pos := shielder_pos - shielder_to_player * ShieldComponent.FORMATION_OFFSET

	# Behind position should be further from the player than the shielder
	assert_gt(behind_pos.distance_to(player_pos), shielder_pos.distance_to(player_pos),
		"Cover position should be behind shieldbearer (further from player)")


func test_shieldbearer_cover_offset_distance() -> void:
	var shielder_pos := Vector2(200, 0)
	var player_pos := Vector2(400, 0)

	var shielder_to_player := (player_pos - shielder_pos).normalized()
	var behind_pos := shielder_pos - shielder_to_player * ShieldComponent.FORMATION_OFFSET

	var dist := shielder_pos.distance_to(behind_pos)
	assert_almost_eq(dist, ShieldComponent.FORMATION_OFFSET, 0.01,
		"Cover position should be FORMATION_OFFSET pixels behind the shieldbearer")


# =============================================================================
# RCA-1/RCA-2 Fix: Early Return — No State-Machine Fall-Through (Issue #1446 bug)
# =============================================================================


## Verify arrive_at_formation does NOT run full state machine for formation enemies.
## Regression test for RCA-1: prior code fell through to state machine after cover setup.
func test_arrive_at_formation_sets_cover_and_returns_early() -> void:
	var shielder := MockShieldbearer.new()
	add_child_autofree(shielder)

	var follower := MockFormationEnemy.new()
	follower.set_formation_follow_target(shielder, Vector2(100, 0))
	follower.arrive_at_formation()

	# After arriving, must have cover data set
	assert_true(follower.has_valid_cover(), "Must have valid cover after arriving at formation")
	assert_eq(follower._cover_position, Vector2(100, 0), "Cover position must match formation target")
	# Must have entered IN_COVER (not stayed IDLE or jumped to COMBAT)
	assert_true(follower.is_in_cover(), "Must be IN_COVER after arriving at formation")


## Verify that a formation enemy already in COMBAT state keeps COMBAT after arrive.
## Regression test for RCA-2 ping-pong: previously, enemies oscillated between IN_COVER and COMBAT.
func test_formation_enemy_in_combat_stays_combat_on_arrive() -> void:
	var shielder := MockShieldbearer.new()
	add_child_autofree(shielder)

	var follower := MockFormationEnemy.new()
	follower._current_state = MockFormationEnemy.AIState.COMBAT
	follower.set_formation_follow_target(shielder, Vector2(100, 0))

	# Arrive while in COMBAT — should keep COMBAT (cover data updated, state preserved)
	follower.arrive_at_formation()

	assert_eq(follower._current_state, MockFormationEnemy.AIState.COMBAT,
		"COMBAT state must be preserved when formation enemy arrives (no ping-pong to IN_COVER)")
	# Cover data must still be updated
	assert_true(follower.has_valid_cover(), "Cover data must still be set even when staying in COMBAT")


## Verify that SUPPRESSED state is preserved on arrival (no forced IN_COVER override).
func test_formation_enemy_in_suppressed_stays_suppressed_on_arrive() -> void:
	var shielder := MockShieldbearer.new()
	add_child_autofree(shielder)

	var follower := MockFormationEnemy.new()
	follower._current_state = MockFormationEnemy.AIState.SUPPRESSED
	follower.set_formation_follow_target(shielder, Vector2(100, 0))
	follower.arrive_at_formation()

	assert_eq(follower._current_state, MockFormationEnemy.AIState.SUPPRESSED,
		"SUPPRESSED state must be preserved when formation enemy arrives")


## Verify that cover data is still set even when state is preserved (COMBAT/SUPPRESSED).
func test_cover_data_set_even_when_state_preserved() -> void:
	var shielder := MockShieldbearer.new()
	add_child_autofree(shielder)

	var formation_pos := Vector2(300, 150)
	var follower := MockFormationEnemy.new()
	follower._current_state = MockFormationEnemy.AIState.COMBAT
	follower.set_formation_follow_target(shielder, formation_pos)
	follower.arrive_at_formation()

	assert_eq(follower._cover_position, formation_pos,
		"Cover position must be updated even when state is not changed to IN_COVER")
	assert_true(follower.has_valid_cover(),
		"has_valid_cover must be true even when state is not changed to IN_COVER")


# =============================================================================
# Regression: RCA-5 — Formation enemy in IN_COVER must NOT transition to PURSUING
# when losing sight of player (Issue #1446, third AI session)
# =============================================================================


## Verify that a formation enemy in IN_COVER does NOT transition to PURSUING on lost sight.
## Regression test for ping-pong: IN_COVER -> PURSUING (line 1803) -> IN_COVER (line 1277) -> repeat.
func test_formation_enemy_in_cover_stays_when_losing_sight() -> void:
	var shielder := MockShieldbearer.new()
	add_child_autofree(shielder)

	var follower := MockFormationEnemy.new()
	follower.set_formation_follow_target(shielder, Vector2(100, 0))
	follower.arrive_at_formation()

	assert_true(follower.is_in_cover(), "Must be IN_COVER after arriving at formation")

	# Simulate losing sight of player while in cover behind shieldbearer
	var transitioned := follower.process_in_cover_lost_sight()
	assert_false(transitioned, "Formation enemy must NOT transition to PURSUING on lost sight")
	assert_true(follower.is_in_cover(), "Must remain IN_COVER behind shieldbearer after losing sight")


## Verify that a non-formation enemy in IN_COVER DOES transition to PURSUING on lost sight.
## Ensures the fix only targets formation enemies, not all enemies.
func test_non_formation_enemy_in_cover_pursues_when_losing_sight() -> void:
	var follower := MockFormationEnemy.new()
	# No formation shielder — regular enemy
	follower._current_state = MockFormationEnemy.AIState.IN_COVER

	var transitioned := follower.process_in_cover_lost_sight()
	assert_true(transitioned, "Non-formation enemy MUST transition to PURSUING on lost sight")
