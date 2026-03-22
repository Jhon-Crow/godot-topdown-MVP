extends GutTest
## Regression tests for Issue #1338: suppressed enemies must stay in cover
## when the player goes out of sight, and enemies must immediately seek cover
## when player bullets enter their threat zone.
##
## Bug 1: When an enemy was SUPPRESSED and the player disappeared from view,
## the enemy would transition SUPPRESSED -> IN_COVER -> PURSUING immediately,
## instead of staying in cover for a post-suppression period.
##
## Bug 2: When player bullets entered an enemy's threat zone during COMBAT or
## PURSUING, the enemy would not immediately seek cover due to the
## threat_reaction_delay, allowing them to stay exposed or charge the player.
##
## Bug 3: When enemies were hit while RETREATING/SEEKING_COVER under fire,
## Issue #910's hit handler would pull them back into COMBAT, defeating cover.
##
## Fix: (a) POST_SUPPRESSION_COVER_DURATION timer keeps enemy in cover after
## suppression ends. (b) _on_threat_area_entered immediately sets _under_fire
## and triggers retreat from COMBAT/PURSUING. (c) Hit handler respects active
## fire and doesn't pull enemies out of RETREATING/SEEKING_COVER.


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


# ============================================================================
# Mock for immediate threat reaction (Issue #1338 - Bug 2)
# ============================================================================


class MockThreatReaction:
	## Simulates the _on_threat_area_entered logic from enemy.gd,
	## focusing on immediate suppression and retreat behavior.

	var _current_state: String = "COMBAT"
	var _under_fire: bool = false
	var _suppression_timer: float = 0.0
	var _threat_reaction_delay_elapsed: bool = false
	var _bullets_in_threat_sphere: Array = []
	var enable_cover: bool = true
	var _force_field_active: bool = false
	var _transition_log: Array[String] = []

	func on_threat_area_entered() -> void:
		_bullets_in_threat_sphere.append("bullet")
		# Issue #1338: Immediate reaction logic (mirrors enemy.gd)
		if not _force_field_active:
			_under_fire = true; _suppression_timer = 0.0; _threat_reaction_delay_elapsed = true
			if enable_cover and _current_state in ["COMBAT", "PURSUING"]:
				var prev_state := _current_state
				_current_state = "RETREATING"
				_transition_log.append("%s -> RETREATING (immediate)" % prev_state)


class MockRetreatingLogic:
	## Simulates the RETREATING/SEEKING_COVER state logic from enemy.gd,
	## focusing on Issue #1338: enemy must continue retreating to cover
	## even when player leaves visibility.

	const RETREATING_MIN_DURATION: float = 0.3

	var _current_state: String = "RETREATING"
	var _has_valid_cover: bool = true
	var _cover_position: Vector2 = Vector2(500, 500)
	var _enemy_position: Vector2 = Vector2(100, 100)
	var _is_visible_from_player: bool = true
	var _under_fire: bool = true
	var _can_see_player: bool = false
	var _retreating_entry_time: float = 0.0
	var _time: float = 0.0
	var _transition_log: Array[String] = []

	func process_retreating(delta: float) -> void:
		_time += delta
		var time_in_state := _time - _retreating_entry_time
		if not _has_valid_cover: return

		var distance_to_cover := _enemy_position.distance_to(_cover_position)
		var near_cover := distance_to_cover < 10.0
		var hidden := not _is_visible_from_player

		if near_cover:
			if hidden:
				if time_in_state >= RETREATING_MIN_DURATION:
					_current_state = "IN_COVER"
					_transition_log.append("RETREATING -> IN_COVER (near cover and hidden)")
				return
			else:
				_has_valid_cover = false
				return
		elif hidden and not _under_fire and not _can_see_player:
			if time_in_state >= 5.0:
				_current_state = "IN_COVER"
				_transition_log.append("RETREATING -> IN_COVER (timeout)")
				return
		# Otherwise: keep moving to cover (the actual behavior we want)


class MockCoverSelection:
	## Simulates the cover selection logic from enemy.gd,
	## focusing on Issue #1338: use last known player position for cover search.

	var _can_see_player: bool = true
	var _player_position: Vector2 = Vector2(0, 0)
	var _last_known_player_position: Vector2 = Vector2.ZERO
	var player_pos_used: Vector2 = Vector2.ZERO

	func get_cover_search_origin() -> Vector2:
		if _can_see_player:
			return _player_position
		elif _last_known_player_position != Vector2.ZERO:
			return _last_known_player_position
		else:
			return _player_position

	func find_cover() -> void:
		player_pos_used = get_cover_search_origin()


class MockHitHandler:
	## Simulates the hit handler logic from enemy.gd,
	## focusing on Issue #910 vs #1338 interaction.

	var _current_state: String = "RETREATING"
	var _under_fire: bool = false
	var _bullets_in_threat_sphere: Array = []
	var _transition_log: Array[String] = []

	func on_hit() -> void:
		if _current_state in ["IDLE", "SEARCHING", "RETREATING", "SEEKING_COVER"]:
			if _current_state in ["RETREATING", "SEEKING_COVER"] and (_under_fire or not _bullets_in_threat_sphere.is_empty()):
				_transition_log.append("HIT: staying in %s (under fire)" % _current_state)
			else:
				var prev_state := _current_state
				_current_state = "COMBAT"
				_transition_log.append("HIT: %s -> COMBAT (#910)" % prev_state)


# ============================================================================
# Tests for immediate threat reaction (Issue #1338 - Bug 2)
# ============================================================================


func test_combat_enemy_immediately_retreats_on_bullet_threat() -> void:
	## Issue #1338 core: enemy in COMBAT must immediately retreat when
	## a player bullet enters the threat zone, without waiting for
	## threat_reaction_delay.
	var threat := MockThreatReaction.new()
	threat._current_state = "COMBAT"
	threat._under_fire = false

	threat.on_threat_area_entered()

	assert_eq(threat._current_state, "RETREATING",
		"COMBAT enemy should immediately retreat when bullet enters threat zone")
	assert_true(threat._under_fire,
		"_under_fire should be set immediately on bullet threat")
	assert_true(threat._threat_reaction_delay_elapsed,
		"Threat reaction delay should be bypassed")


func test_pursuing_enemy_immediately_retreats_on_bullet_threat() -> void:
	## Issue #1338: enemy in PURSUING must immediately retreat when
	## player bullets enter the threat zone instead of continuing pursuit.
	var threat := MockThreatReaction.new()
	threat._current_state = "PURSUING"
	threat._under_fire = false

	threat.on_threat_area_entered()

	assert_eq(threat._current_state, "RETREATING",
		"PURSUING enemy should immediately retreat when bullet enters threat zone")


func test_idle_enemy_does_not_retreat_on_bullet_threat() -> void:
	## Only COMBAT and PURSUING enemies should immediately retreat.
	## IDLE enemies have different handling.
	var threat := MockThreatReaction.new()
	threat._current_state = "IDLE"
	threat._under_fire = false

	threat.on_threat_area_entered()

	assert_true(threat._under_fire,
		"_under_fire should still be set for IDLE enemy")
	assert_eq(threat._current_state, "IDLE",
		"IDLE enemy should not transition to RETREATING on bullet threat")


func test_force_field_blocks_immediate_retreat() -> void:
	## When force field is active, bullet threats should not trigger
	## immediate retreat.
	var threat := MockThreatReaction.new()
	threat._current_state = "COMBAT"
	threat._force_field_active = true

	threat.on_threat_area_entered()

	assert_eq(threat._current_state, "COMBAT",
		"Force field should block immediate retreat on bullet threat")
	assert_false(threat._under_fire,
		"_under_fire should not be set when force field is active")


func test_cover_disabled_does_not_retreat() -> void:
	## When cover behavior is disabled, enemy should not retreat.
	var threat := MockThreatReaction.new()
	threat._current_state = "COMBAT"
	threat.enable_cover = false

	threat.on_threat_area_entered()

	assert_true(threat._under_fire,
		"_under_fire should still be set even with cover disabled")
	assert_eq(threat._current_state, "COMBAT",
		"Enemy with cover disabled should not retreat on bullet threat")


# ============================================================================
# Tests for hit handler under fire (Issue #1338 - Bug 3)
# ============================================================================


func test_hit_does_not_pull_retreating_enemy_to_combat_under_fire() -> void:
	## Issue #1338: when an enemy is hit while RETREATING under active fire,
	## it should stay in RETREATING instead of being pulled to COMBAT.
	var handler := MockHitHandler.new()
	handler._current_state = "RETREATING"
	handler._under_fire = true

	handler.on_hit()

	assert_eq(handler._current_state, "RETREATING",
		"Hit should not pull RETREATING enemy to COMBAT when under fire")


func test_hit_does_not_pull_seeking_cover_enemy_to_combat_under_fire() -> void:
	## Issue #1338: when an enemy is hit while SEEKING_COVER under active fire,
	## it should stay in SEEKING_COVER.
	var handler := MockHitHandler.new()
	handler._current_state = "SEEKING_COVER"
	handler._under_fire = true

	handler.on_hit()

	assert_eq(handler._current_state, "SEEKING_COVER",
		"Hit should not pull SEEKING_COVER enemy to COMBAT when under fire")


func test_hit_does_not_pull_retreating_enemy_with_bullets_in_threat() -> void:
	## Issue #1338: even if _under_fire hasn't been set yet, if bullets are
	## in the threat sphere, don't pull enemy out of cover-seeking.
	var handler := MockHitHandler.new()
	handler._current_state = "RETREATING"
	handler._under_fire = false
	handler._bullets_in_threat_sphere = ["bullet"]

	handler.on_hit()

	assert_eq(handler._current_state, "RETREATING",
		"Hit should not pull RETREATING enemy to COMBAT with bullets in threat sphere")


func test_hit_still_triggers_combat_from_idle() -> void:
	## Issue #910 preserved: hitting an IDLE enemy should still trigger COMBAT.
	var handler := MockHitHandler.new()
	handler._current_state = "IDLE"
	handler._under_fire = false

	handler.on_hit()

	assert_eq(handler._current_state, "COMBAT",
		"Hit should trigger COMBAT from IDLE (Issue #910 preserved)")


func test_hit_triggers_combat_from_retreating_when_not_under_fire() -> void:
	## Issue #910 preserved: hitting a RETREATING enemy should trigger COMBAT
	## when NOT under active fire (no bullets, no suppression).
	var handler := MockHitHandler.new()
	handler._current_state = "RETREATING"
	handler._under_fire = false
	handler._bullets_in_threat_sphere = []

	handler.on_hit()

	assert_eq(handler._current_state, "COMBAT",
		"Hit should trigger COMBAT from RETREATING when not under fire (Issue #910)")


# ============================================================================
# Tests for retreat persistence when player leaves visibility (Issue #1338)
# ============================================================================


func test_retreating_enemy_continues_to_cover_when_player_invisible() -> void:
	## Issue #1338: when the player goes out of sight, the enemy must continue
	## retreating to its cover position instead of stopping or entering IN_COVER.
	var retreat := MockRetreatingLogic.new()
	retreat._is_visible_from_player = false  # Player can't see enemy
	retreat._can_see_player = false  # Enemy can't see player
	retreat._under_fire = true  # Still under fire
	retreat._enemy_position = Vector2(100, 100)  # Far from cover
	retreat._cover_position = Vector2(500, 500)

	for i in range(30):
		retreat.process_retreating(1.0 / 60.0)

	assert_eq(retreat._current_state, "RETREATING",
		"Enemy should continue retreating to cover even when player is not visible")
	assert_true(retreat._transition_log.is_empty(),
		"No state transition should have occurred while retreating to distant cover")


func test_retreating_enemy_enters_cover_when_near_and_hidden() -> void:
	## Issue #1338: enemy transitions to IN_COVER only when actually near
	## the cover position AND hidden from player.
	var retreat := MockRetreatingLogic.new()
	retreat._is_visible_from_player = false
	retreat._enemy_position = Vector2(505, 505)  # Very close to cover (< 10 units)
	retreat._cover_position = Vector2(500, 500)
	retreat._retreating_entry_time = -1.0  # Ensure min duration passed

	retreat.process_retreating(1.0 / 60.0)

	assert_eq(retreat._current_state, "IN_COVER",
		"Enemy should enter IN_COVER when near cover and hidden from player")


func test_retreating_enemy_does_not_stop_when_player_leaves_sight_far_from_cover() -> void:
	## Issue #1338: Even when hidden from player and no longer under fire,
	## enemy continues moving to cover until it reaches it or times out.
	var retreat := MockRetreatingLogic.new()
	retreat._is_visible_from_player = false
	retreat._under_fire = false
	retreat._can_see_player = false
	retreat._enemy_position = Vector2(100, 100)  # Far from cover
	retreat._cover_position = Vector2(500, 500)

	# Simulate 2 seconds - not enough for the 5s timeout
	for i in range(120):
		retreat.process_retreating(1.0 / 60.0)

	assert_eq(retreat._current_state, "RETREATING",
		"Enemy should keep retreating when far from cover, even if hidden and not under fire")


func test_retreating_enemy_timeout_transitions_to_in_cover() -> void:
	## Issue #1338: After 5 seconds of retreating while hidden and not under fire,
	## the enemy should give up and transition to IN_COVER as a safety valve.
	var retreat := MockRetreatingLogic.new()
	retreat._is_visible_from_player = false
	retreat._under_fire = false
	retreat._can_see_player = false
	retreat._enemy_position = Vector2(100, 100)  # Far from cover
	retreat._cover_position = Vector2(500, 500)

	# Simulate 6 seconds - past the 5s timeout
	for i in range(360):
		retreat.process_retreating(1.0 / 60.0)

	assert_eq(retreat._current_state, "IN_COVER",
		"Enemy should transition to IN_COVER after retreat timeout (5s)")


# ============================================================================
# Tests for cover selection with last known player position (Issue #1338)
# ============================================================================


func test_cover_search_uses_current_player_pos_when_visible() -> void:
	## When the player is visible, cover search should use the player's
	## current position.
	var cover := MockCoverSelection.new()
	cover._can_see_player = true
	cover._player_position = Vector2(200, 300)
	cover._last_known_player_position = Vector2(100, 100)

	cover.find_cover()

	assert_eq(cover.player_pos_used, Vector2(200, 300),
		"Cover search should use current player position when player is visible")


func test_cover_search_uses_last_known_pos_when_invisible() -> void:
	## Issue #1338: When the player is NOT visible, cover search should use
	## the last known player position to find cover that blocks rays from
	## where the player was last seen.
	var cover := MockCoverSelection.new()
	cover._can_see_player = false
	cover._player_position = Vector2(200, 300)  # Current (but unseen)
	cover._last_known_player_position = Vector2(100, 100)  # Last seen

	cover.find_cover()

	assert_eq(cover.player_pos_used, Vector2(100, 100),
		"Cover search should use last known player position when player is not visible")


func test_cover_search_falls_back_to_current_pos_when_no_last_known() -> void:
	## Edge case: when player is not visible and there's no last known
	## position, fall back to current player position.
	var cover := MockCoverSelection.new()
	cover._can_see_player = false
	cover._player_position = Vector2(200, 300)
	cover._last_known_player_position = Vector2.ZERO  # No last known

	cover.find_cover()

	assert_eq(cover.player_pos_used, Vector2(200, 300),
		"Cover search should fall back to current player position when no last known position")
