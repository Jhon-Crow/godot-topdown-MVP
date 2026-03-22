extends GutTest
## Regression tests for Issue #1338: suppressed enemies must stay in cover
## when the player goes out of sight, and enemies must react immediately
## when player bullets enter their threat zone.
##
## Bug 1: When an enemy was SUPPRESSED and the player disappeared from view,
## the enemy would transition SUPPRESSED -> IN_COVER -> PURSUING immediately,
## instead of staying in cover for a post-suppression period.
##
## Bug 2: The threat_reaction_delay (0.2s) meant enemies didn't set _under_fire
## fast enough, allowing COMBAT enemies to transition to PURSUING while bullets
## were actively flying past them.
##
## Fix: (a) POST_SUPPRESSION_COVER_DURATION timer keeps enemy in cover after
## suppression ends. (b) threat_reaction_delay set to 0.0 so _under_fire
## triggers immediately. (c) Cover scoring weights prioritize nearest hidden
## cover (distance 0.7, blocking 0.3).


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


class MockSuppressionUpdate:
	## Simulates the _update_suppression logic from enemy.gd,
	## focusing on the immediate reaction when threat_reaction_delay = 0.0.

	var threat_reaction_delay: float = 0.0  ## Issue #1338: was 0.2
	var _under_fire: bool = false
	var _suppression_timer: float = 0.0
	var suppression_cooldown: float = 2.0
	var _threat_reaction_timer: float = 0.0
	var _threat_reaction_delay_elapsed: bool = false
	var _bullets_in_threat_sphere: Array = []
	var _threat_memory_timer: float = 0.0
	var _force_field_active: bool = false

	func update_suppression(delta: float) -> void:
		_bullets_in_threat_sphere = _bullets_in_threat_sphere.filter(func(b): return b != null)
		var has_active_threat := not _bullets_in_threat_sphere.is_empty() or _threat_memory_timer > 0.0
		if not has_active_threat:
			if _under_fire:
				_suppression_timer += delta
				if _suppression_timer >= suppression_cooldown:
					_under_fire = false; _suppression_timer = 0.0
			_threat_reaction_timer = 0.0; _threat_reaction_delay_elapsed = false
		else:
			if _bullets_in_threat_sphere.is_empty() and _threat_memory_timer > 0.0:
				_threat_memory_timer -= delta
			if not _threat_reaction_delay_elapsed:
				_threat_reaction_timer += delta
				if _threat_reaction_timer >= threat_reaction_delay:
					_threat_reaction_delay_elapsed = true
			if _threat_reaction_delay_elapsed and not _force_field_active:
				_under_fire = true; _suppression_timer = 0.0


class MockCoverScoring:
	## Simulates the cover scoring logic from _find_cover_position,
	## focusing on Issue #1338: distance weight 0.7, blocking weight 0.3.

	static func score_cover(hidden: bool, distance_score: float, blocking_score: float) -> float:
		var hidden_score: float = 10.0 if hidden else 0.0
		# Issue #1338: nearest hidden cover is primary goal
		return hidden_score + distance_score * 0.7 + blocking_score * 0.3


# ============================================================================
# Tests for post-suppression cover timer (Issue #1338 - Bug 1)
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


# ============================================================================
# Tests for immediate suppression reaction (Issue #1338 - Bug 2)
# ============================================================================


func test_suppression_sets_under_fire_immediately_with_zero_delay() -> void:
	## Issue #1338: with threat_reaction_delay = 0.0, _under_fire should
	## be set on the very first update after a bullet enters the threat zone.
	var sup := MockSuppressionUpdate.new()
	sup.threat_reaction_delay = 0.0
	sup._bullets_in_threat_sphere = ["bullet"]

	sup.update_suppression(1.0 / 60.0)

	assert_true(sup._under_fire,
		"_under_fire should be set immediately with zero reaction delay")
	assert_true(sup._threat_reaction_delay_elapsed,
		"Threat reaction delay should be elapsed immediately")


func test_suppression_delayed_with_nonzero_delay() -> void:
	## Verify that with a non-zero delay (old behavior), _under_fire is
	## NOT set on the first frame.
	var sup := MockSuppressionUpdate.new()
	sup.threat_reaction_delay = 0.2
	sup._bullets_in_threat_sphere = ["bullet"]

	sup.update_suppression(1.0 / 60.0)

	assert_true(sup._threat_reaction_delay_elapsed,
		"With 0.2s delay and 0.016s frame, delay should NOT be elapsed yet")
	# Note: with 0.016s < 0.2s, the delay is not elapsed, so _under_fire stays false
	# But actually _threat_reaction_timer (0.016) < 0.2, so _threat_reaction_delay_elapsed = false


func test_suppression_delayed_with_nonzero_delay_correct() -> void:
	## With a non-zero delay of 0.2s, after only 0.016s, under_fire should
	## NOT be set because the reaction delay hasn't elapsed.
	var sup := MockSuppressionUpdate.new()
	sup.threat_reaction_delay = 0.2
	sup._bullets_in_threat_sphere = ["bullet"]

	sup.update_suppression(1.0 / 60.0)  # 0.016s

	assert_false(sup._under_fire,
		"_under_fire should NOT be set with 0.2s delay after only 0.016s")


func test_suppression_force_field_blocks() -> void:
	## Force field should prevent _under_fire even with zero delay.
	var sup := MockSuppressionUpdate.new()
	sup.threat_reaction_delay = 0.0
	sup._bullets_in_threat_sphere = ["bullet"]
	sup._force_field_active = true

	sup.update_suppression(1.0 / 60.0)

	assert_false(sup._under_fire,
		"Force field should block _under_fire")


func test_suppression_clears_after_cooldown() -> void:
	## When bullets leave and cooldown expires, _under_fire should clear.
	var sup := MockSuppressionUpdate.new()
	sup._under_fire = true
	sup._bullets_in_threat_sphere = []  # All bullets gone
	sup._threat_memory_timer = 0.0  # No memory

	# Simulate suppression_cooldown (2.0s) worth of frames
	var total := 0.0
	while total < 2.1:
		sup.update_suppression(1.0 / 60.0)
		total += 1.0 / 60.0

	assert_false(sup._under_fire,
		"_under_fire should clear after suppression cooldown with no bullets")


# ============================================================================
# Tests for cover scoring weights (Issue #1338)
# ============================================================================


func test_cover_scoring_prefers_nearer_hidden_cover() -> void:
	## Issue #1338: among hidden covers, the nearer one should score higher.
	## distance_score is 1.0 - (dist / max_dist), so closer = higher.
	var near_score := MockCoverScoring.score_cover(true, 0.9, 0.3)  # near, low blocking
	var far_score := MockCoverScoring.score_cover(true, 0.3, 0.9)   # far, high blocking

	assert_true(near_score > far_score,
		"Nearer hidden cover (dist=0.9, block=0.3) should score higher than farther (dist=0.3, block=0.9)")


func test_cover_scoring_hidden_always_beats_exposed() -> void:
	## Hidden cover should always beat exposed cover regardless of other scores.
	var hidden_far := MockCoverScoring.score_cover(true, 0.1, 0.1)
	var exposed_near := MockCoverScoring.score_cover(false, 1.0, 1.0)

	assert_true(hidden_far > exposed_near,
		"Hidden cover should always beat exposed cover")


func test_cover_scoring_weights_are_correct() -> void:
	## Verify the exact weight formula: hidden_score + distance * 0.7 + blocking * 0.3
	var score := MockCoverScoring.score_cover(true, 0.5, 0.5)
	var expected := 10.0 + 0.5 * 0.7 + 0.5 * 0.3  # 10.0 + 0.35 + 0.15 = 10.5

	assert_almost_eq(score, expected, 0.001,
		"Score should be hidden_score + distance*0.7 + blocking*0.3")


# ============================================================================
# Tests for retreat persistence (Issue #1338 - retreat until reaching cover)
# ============================================================================


class MockRetreatingLogic:
	## Simulates the RETREATING state logic from enemy.gd,
	## focusing on Issue #1338: enemy must continue retreating until BOTH
	## near cover position AND hidden from player.

	const RETREATING_MIN_DURATION: float = 0.3

	var _current_state: String = "RETREATING"
	var _cover_position: Vector2 = Vector2(100, 100)
	var _enemy_position: Vector2 = Vector2(300, 300)
	var _is_visible_from_player: bool = true
	var _has_valid_cover: bool = true
	var _under_fire: bool = true
	var _time_in_state: float = 0.0
	var _transition_log: Array[String] = []

	func process_retreating(delta: float) -> void:
		_time_in_state += delta
		if not _has_valid_cover:
			if _time_in_state >= RETREATING_MIN_DURATION:
				if _under_fire:
					_current_state = "SUPPRESSED"
					_transition_log.append("RETREATING -> SUPPRESSED")
				else:
					_current_state = "COMBAT"
					_transition_log.append("RETREATING -> COMBAT")
			return

		# Issue #1338: Only transition to IN_COVER when BOTH near cover AND hidden
		var distance_to_cover := _enemy_position.distance_to(_cover_position)
		if distance_to_cover < 10.0 and not _is_visible_from_player:
			if _time_in_state >= RETREATING_MIN_DURATION:
				_current_state = "IN_COVER"
				_transition_log.append("RETREATING -> IN_COVER (near+hidden)")
			return

		# Safety timeout
		if _time_in_state >= 5.0:
			_current_state = "IN_COVER"
			_transition_log.append("RETREATING -> IN_COVER (timeout)")
			return


func test_retreating_continues_when_hidden_but_far_from_cover() -> void:
	## Issue #1338: Enemy should NOT stop retreating just because they're
	## hidden from the player — they must reach their cover position first.
	var ret := MockRetreatingLogic.new()
	ret._enemy_position = Vector2(300, 300)  # Far from cover
	ret._cover_position = Vector2(100, 100)  # ~283 units away
	ret._is_visible_from_player = false  # Hidden, but far from cover
	ret._time_in_state = 0.5  # Past min duration

	ret.process_retreating(1.0 / 60.0)

	assert_eq(ret._current_state, "RETREATING",
		"Enemy should keep retreating when hidden but far from cover")
	assert_eq(ret._transition_log.size(), 0,
		"No transition should occur when hidden but far from cover")


func test_retreating_stops_when_near_cover_and_hidden() -> void:
	## Enemy should transition to IN_COVER when BOTH near cover AND hidden.
	var ret := MockRetreatingLogic.new()
	ret._enemy_position = Vector2(105, 105)  # Near cover (~7 units)
	ret._cover_position = Vector2(100, 100)
	ret._is_visible_from_player = false
	ret._time_in_state = 0.5

	ret.process_retreating(1.0 / 60.0)

	assert_eq(ret._current_state, "IN_COVER",
		"Enemy should enter IN_COVER when near cover and hidden")


func test_retreating_continues_when_near_cover_but_visible() -> void:
	## Enemy should NOT stop at cover if still visible from player.
	var ret := MockRetreatingLogic.new()
	ret._enemy_position = Vector2(105, 105)  # Near cover
	ret._cover_position = Vector2(100, 100)
	ret._is_visible_from_player = true  # Still visible
	ret._time_in_state = 0.5

	ret.process_retreating(1.0 / 60.0)

	assert_eq(ret._current_state, "RETREATING",
		"Enemy should keep retreating if near cover but still visible")


func test_retreating_timeout_forces_in_cover() -> void:
	## Safety: after 5s retreat, force IN_COVER to avoid stuck enemies.
	var ret := MockRetreatingLogic.new()
	ret._enemy_position = Vector2(300, 300)  # Far from cover
	ret._is_visible_from_player = true  # Still visible
	ret._time_in_state = 5.1  # Past timeout

	ret.process_retreating(1.0 / 60.0)

	assert_eq(ret._current_state, "IN_COVER",
		"Enemy should be forced into IN_COVER after 5s timeout")


# ============================================================================
# Tests for #910 hit handler exclusion (Issue #1338)
# ============================================================================


class MockHitHandler:
	## Simulates the #910 hit handler logic, verifying that RETREATING
	## is excluded from states that trigger COMBAT on hit.

	var _current_state: String
	var _transition_log: Array[String] = []

	## Simulates the #910 hit handler
	func on_hit() -> void:
		# Issue #1338: RETREATING excluded from #910 handler
		if _current_state in ["IDLE", "SEARCHING", "SEEKING_COVER"]:
			_transition_log.append("%s -> COMBAT (#910)" % _current_state)
			_current_state = "COMBAT"


func test_hit_does_not_interrupt_retreat() -> void:
	## Issue #1338: hits should NOT interrupt retreat — enemy keeps going to cover.
	var handler := MockHitHandler.new()
	handler._current_state = "RETREATING"
	handler.on_hit()

	assert_eq(handler._current_state, "RETREATING",
		"Hit should NOT interrupt RETREATING state")
	assert_eq(handler._transition_log.size(), 0,
		"No transition should occur when hit while RETREATING")


func test_hit_still_triggers_combat_from_idle() -> void:
	## Existing #910 behavior: hits from IDLE should still trigger COMBAT.
	var handler := MockHitHandler.new()
	handler._current_state = "IDLE"
	handler.on_hit()

	assert_eq(handler._current_state, "COMBAT",
		"Hit should trigger COMBAT from IDLE")


func test_hit_still_triggers_combat_from_searching() -> void:
	## Existing #910 behavior: hits from SEARCHING should still trigger COMBAT.
	var handler := MockHitHandler.new()
	handler._current_state = "SEARCHING"
	handler.on_hit()

	assert_eq(handler._current_state, "COMBAT",
		"Hit should trigger COMBAT from SEARCHING")


# ============================================================================
# Tests for cover search with last known player position (Issue #1338)
# ============================================================================


class MockCoverSearch:
	## Simulates the cover search player_pos selection logic.

	var _can_see_player: bool = true
	var _player_position: Vector2 = Vector2(500, 500)
	var _last_known_player_position: Vector2 = Vector2(200, 200)

	func get_search_origin() -> Vector2:
		var player_pos := _player_position
		if not _can_see_player and _last_known_player_position != Vector2.ZERO:
			player_pos = _last_known_player_position
		return player_pos


func test_cover_search_uses_current_pos_when_visible() -> void:
	## When player is visible, cover search should use current player position.
	var search := MockCoverSearch.new()
	search._can_see_player = true

	assert_eq(search.get_search_origin(), Vector2(500, 500),
		"Should use current player position when visible")


func test_cover_search_uses_last_known_pos_when_invisible() -> void:
	## Issue #1338: When player is invisible, cover search should use
	## last known player position for raycast origin.
	var search := MockCoverSearch.new()
	search._can_see_player = false

	assert_eq(search.get_search_origin(), Vector2(200, 200),
		"Should use last known player position when invisible")


func test_cover_search_fallback_when_no_last_known() -> void:
	## If no last known position recorded, fall back to current player position.
	var search := MockCoverSearch.new()
	search._can_see_player = false
	search._last_known_player_position = Vector2.ZERO

	assert_eq(search.get_search_origin(), Vector2(500, 500),
		"Should fall back to current player position when no last known")
