extends GutTest
## Regression tests for Issue #1338: suppressed enemies must stay in cover
## when the player goes out of sight.
##
## Bug: When an enemy was SUPPRESSED and the player disappeared from view,
## the enemy would transition SUPPRESSED -> IN_COVER -> PURSUING immediately,
## instead of staying in cover for a post-suppression period.
##
## Fix: Added POST_SUPPRESSION_COVER_DURATION timer that keeps the enemy
## in cover after suppression ends, preventing immediate pursuit.


# ============================================================================
# Mock Classes
# ============================================================================


class MockInCoverLogic:
	## Simulates the IN_COVER state decision logic from enemy.gd,
	## focusing on the post-suppression cover behavior (Issue #1338).

	const POST_SUPPRESSION_COVER_DURATION: float = 3.0

	var _current_state: String = "IN_COVER"
	var _can_see_player: bool = false
	var _can_see_companion: bool = false
	var _under_fire: bool = false
	var _post_suppression_timer: float = 0.0
	var _has_suppressive_fire: bool = false
	var _transition_log: Array[String] = []

	## Simulates the relevant part of _process_in_cover_state.
	func process_in_cover(delta: float) -> void:
		# Decrement post-suppression timer (Issue #1338)
		if _post_suppression_timer > 0.0:
			_post_suppression_timer -= delta
			if _post_suppression_timer <= 0.0:
				_post_suppression_timer = 0.0

		# The critical decision: should we pursue?
		if not (_can_see_player or _can_see_companion) and not _under_fire and _post_suppression_timer <= 0.0 and not _has_suppressive_fire:
			_current_state = "PURSUING"
			_transition_log.append("IN_COVER -> PURSUING")

	## Simulates transition from SUPPRESSED to IN_COVER when suppression ends.
	func end_suppression() -> void:
		_post_suppression_timer = POST_SUPPRESSION_COVER_DURATION
		_current_state = "IN_COVER"
		_transition_log.append("SUPPRESSED -> IN_COVER (post-suppression)")


# ============================================================================
# Tests
# ============================================================================


var logic: MockInCoverLogic


func before_each() -> void:
	logic = MockInCoverLogic.new()


func after_each() -> void:
	logic = null


func test_post_suppression_timer_set_on_suppression_end() -> void:
	## When transitioning from SUPPRESSED to IN_COVER, the post-suppression
	## timer must be set to POST_SUPPRESSION_COVER_DURATION.
	logic.end_suppression()

	assert_almost_eq(logic._post_suppression_timer,
		MockInCoverLogic.POST_SUPPRESSION_COVER_DURATION, 0.001,
		"Post-suppression timer should be set when suppression ends")
	assert_eq(logic._current_state, "IN_COVER",
		"State should be IN_COVER after suppression ends")


func test_enemy_stays_in_cover_during_post_suppression() -> void:
	## Issue #1338 core regression: after suppression ends and player is
	## out of sight, the enemy must NOT pursue immediately.
	logic._can_see_player = false
	logic._under_fire = false
	logic.end_suppression()

	# Simulate several frames (0.5 seconds) - should stay in cover
	for i in range(30):
		logic.process_in_cover(1.0 / 60.0)

	assert_eq(logic._current_state, "IN_COVER",
		"Enemy should stay in cover during post-suppression period (0.5s elapsed)")
	assert_true(logic._post_suppression_timer > 0.0,
		"Post-suppression timer should still be active")
	assert_true(logic._transition_log.size() == 1,
		"Only the SUPPRESSED->IN_COVER transition should have occurred")


func test_enemy_pursues_after_post_suppression_expires() -> void:
	## After the post-suppression period expires, the enemy should
	## resume normal behavior and pursue if player is not visible.
	logic._can_see_player = false
	logic._under_fire = false
	logic.end_suppression()

	# Simulate enough time to expire the post-suppression timer (3.0+ seconds)
	var total_time := 0.0
	var dt := 1.0 / 60.0
	while total_time < MockInCoverLogic.POST_SUPPRESSION_COVER_DURATION + 0.1:
		logic.process_in_cover(dt)
		total_time += dt

	assert_eq(logic._current_state, "PURSUING",
		"Enemy should pursue after post-suppression period expires")
	assert_almost_eq(logic._post_suppression_timer, 0.0, 0.001,
		"Post-suppression timer should be zero")


func test_enemy_engages_if_player_visible_during_post_suppression() -> void:
	## If the player becomes visible during post-suppression, the enemy
	## should NOT be forced to stay in cover by the timer alone.
	## (The IN_COVER state handles visible player separately, before the
	## pursuing check, so this is a sanity check.)
	logic._can_see_player = true
	logic._under_fire = false
	logic.end_suppression()

	# Process a few frames - should NOT transition to PURSUING
	for i in range(30):
		logic.process_in_cover(1.0 / 60.0)

	assert_eq(logic._current_state, "IN_COVER",
		"Enemy should not pursue when player is visible (handled by other logic)")
	assert_ne(logic._current_state, "PURSUING",
		"Must not pursue if player is visible")


func test_new_suppression_resets_timer() -> void:
	## If the enemy gets suppressed again while in post-suppression cover,
	## the timer should reset to full duration.
	logic._can_see_player = false
	logic._under_fire = false
	logic.end_suppression()

	# Let some time pass (1 second)
	for i in range(60):
		logic.process_in_cover(1.0 / 60.0)

	var timer_after_1s := logic._post_suppression_timer
	assert_true(timer_after_1s < MockInCoverLogic.POST_SUPPRESSION_COVER_DURATION,
		"Timer should have decreased after 1 second")

	# Enemy gets suppressed again and returns to IN_COVER
	logic.end_suppression()

	assert_almost_eq(logic._post_suppression_timer,
		MockInCoverLogic.POST_SUPPRESSION_COVER_DURATION, 0.001,
		"Post-suppression timer should reset to full duration on new suppression")


func test_timer_does_not_go_negative() -> void:
	## The timer should clamp at zero, not go negative.
	logic._can_see_player = true  # Keep in cover (don't pursue)
	logic._post_suppression_timer = 0.1

	# Process more time than the remaining timer
	for i in range(60):
		logic.process_in_cover(1.0 / 60.0)

	assert_almost_eq(logic._post_suppression_timer, 0.0, 0.001,
		"Post-suppression timer should not go below zero")


func test_no_post_suppression_timer_without_suppression() -> void:
	## If the enemy enters IN_COVER without being suppressed (e.g., from
	## RETREATING), the post-suppression timer should be zero and the
	## enemy should pursue normally.
	logic._can_see_player = false
	logic._under_fire = false
	logic._post_suppression_timer = 0.0  # Default, no suppression

	logic.process_in_cover(1.0 / 60.0)

	assert_eq(logic._current_state, "PURSUING",
		"Enemy should pursue immediately if not recently suppressed")


func test_under_fire_prevents_pursuing_regardless_of_timer() -> void:
	## Even without the post-suppression timer, being under fire should
	## prevent transitioning to PURSUING (existing behavior preserved).
	logic._can_see_player = false
	logic._under_fire = true
	logic._post_suppression_timer = 0.0

	logic.process_in_cover(1.0 / 60.0)

	assert_eq(logic._current_state, "IN_COVER",
		"Enemy should stay in cover while under fire")
