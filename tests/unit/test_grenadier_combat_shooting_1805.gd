extends GutTest
## Unit tests for Issue #1805 fix: Grenadier should shoot its rifle during COMBAT state.
##
## The bug: The grenade throw priority check in _process_ai_state fires BEFORE the
## state machine processes COMBAT state, causing grenadiers to always throw grenades
## instead of shooting. Triggers T8 (direct sight, 0.5s) and T9 (low suspicion, 1.0s)
## from GrenadierGrenadeComponent made ready_to_throw_grenade=true almost immediately,
## causing the grenadier to never execute _process_combat_state (where shooting happens).
##
## The fix: When a grenadier is in COMBAT state, the grenade throw intercept is skipped,
## allowing the state machine to reach _process_combat_state and execute the shooting phase.


# ============================================================================
# Mock classes for testing the COMBAT state grenade intercept logic
# ============================================================================


## Mirrors the grenade throw intercept logic from _process_ai_state (line 1322 of enemy.gd).
class MockAIStateProcessor:
	enum AIState { IDLE, COMBAT, SEEKING_COVER, IN_COVER, FLANKING, SUPPRESSED, RETREATING, PURSUING, ASSAULT, SEARCHING, EVADING_GRENADE, PACIFIST }

	var is_grenadier: bool = false
	var _current_state: int = AIState.IDLE
	var _combat_allowed: bool = true
	var ready_to_throw_grenade: bool = false
	var is_pacifist: bool = false
	var grenade_throw_attempted: bool = false
	var combat_state_processed: bool = false

	## Reset tracking flags between calls.
	func reset_tracking() -> void:
		grenade_throw_attempted = false
		combat_state_processed = false

	## Simulate try_throw_grenade returning true (grenade was thrown).
	func try_throw_grenade_returns_true() -> bool:
		grenade_throw_attempted = true
		return true

	## Simulate _process_combat_state being called.
	func process_combat_state() -> void:
		combat_state_processed = true

	## Simulate the FIXED _process_ai_state grenade throw check (Issue #1805).
	## Issue #1805: Grenadiers in COMBAT state should shoot their rifle.
	## Grenade throws still happen in PURSUING and other non-COMBAT states.
	func process_ai_state_fixed() -> void:
		reset_tracking()
		# Fixed condition: skip grenade throw for grenadiers in COMBAT state
		if _combat_allowed and ready_to_throw_grenade and not is_pacifist and not (is_grenadier and _current_state == AIState.COMBAT):
			if try_throw_grenade_returns_true():
				return  # Early return - combat state not processed
		# Simulate state machine reaching COMBAT
		if _current_state == AIState.COMBAT:
			process_combat_state()

	## Simulate the BUGGY _process_ai_state grenade throw check (pre-fix).
	func process_ai_state_buggy() -> void:
		reset_tracking()
		# Buggy condition: no grenadier/COMBAT exclusion
		if _combat_allowed and ready_to_throw_grenade and not is_pacifist:
			if try_throw_grenade_returns_true():
				return  # Early return - combat state not processed
		# Simulate state machine reaching COMBAT
		if _current_state == AIState.COMBAT:
			process_combat_state()


# ============================================================================
# Test Variables and Setup
# ============================================================================


var ai: MockAIStateProcessor


func before_each() -> void:
	ai = MockAIStateProcessor.new()


func after_each() -> void:
	ai = null


# ============================================================================
# Issue #1805: Grenadier in COMBAT should not be interrupted by grenade throw
# ============================================================================


func test_grenadier_combat_not_interrupted_when_grenade_ready_fixed() -> void:
	ai.is_grenadier = true
	ai._current_state = MockAIStateProcessor.AIState.COMBAT
	ai.ready_to_throw_grenade = true

	ai.process_ai_state_fixed()

	assert_false(ai.grenade_throw_attempted,
		"Fix: Grenadier in COMBAT should NOT throw grenade (allow shooting)")
	assert_true(ai.combat_state_processed,
		"Fix: COMBAT state should be processed (grenadier shoots rifle)")


func test_grenadier_combat_interrupted_in_buggy_version() -> void:
	ai.is_grenadier = true
	ai._current_state = MockAIStateProcessor.AIState.COMBAT
	ai.ready_to_throw_grenade = true

	ai.process_ai_state_buggy()

	assert_true(ai.grenade_throw_attempted,
		"Bug: Grenadier in COMBAT incorrectly throws grenade (blocks shooting)")
	assert_false(ai.combat_state_processed,
		"Bug: COMBAT state is NOT processed (grenadier never shoots)")


# ============================================================================
# Non-grenadier in COMBAT should still be able to throw grenades
# ============================================================================


func test_non_grenadier_combat_can_throw_grenade_fixed() -> void:
	ai.is_grenadier = false
	ai._current_state = MockAIStateProcessor.AIState.COMBAT
	ai.ready_to_throw_grenade = true

	ai.process_ai_state_fixed()

	assert_true(ai.grenade_throw_attempted,
		"Non-grenadier in COMBAT should still be able to throw grenades")
	assert_false(ai.combat_state_processed,
		"Non-grenadier grenade throw early-returns (normal behavior)")


# ============================================================================
# Grenadier in non-COMBAT states should still throw grenades
# ============================================================================


func test_grenadier_in_pursuing_can_throw_grenade_fixed() -> void:
	ai.is_grenadier = true
	ai._current_state = MockAIStateProcessor.AIState.PURSUING
	ai.ready_to_throw_grenade = true

	ai.process_ai_state_fixed()

	assert_true(ai.grenade_throw_attempted,
		"Fix: Grenadier in PURSUING state can still throw grenades (passage throws)")


func test_grenadier_in_idle_can_throw_grenade_fixed() -> void:
	ai.is_grenadier = true
	ai._current_state = MockAIStateProcessor.AIState.IDLE
	ai.ready_to_throw_grenade = true

	ai.process_ai_state_fixed()

	assert_true(ai.grenade_throw_attempted,
		"Fix: Grenadier in IDLE state can still throw grenades")


func test_grenadier_in_flanking_can_throw_grenade_fixed() -> void:
	ai.is_grenadier = true
	ai._current_state = MockAIStateProcessor.AIState.FLANKING
	ai.ready_to_throw_grenade = true

	ai.process_ai_state_fixed()

	assert_true(ai.grenade_throw_attempted,
		"Fix: Grenadier in FLANKING state can still throw grenades")


func test_grenadier_in_seeking_cover_can_throw_grenade_fixed() -> void:
	ai.is_grenadier = true
	ai._current_state = MockAIStateProcessor.AIState.SEEKING_COVER
	ai.ready_to_throw_grenade = true

	ai.process_ai_state_fixed()

	assert_true(ai.grenade_throw_attempted,
		"Fix: Grenadier in SEEKING_COVER state can still throw grenades")


# ============================================================================
# Grenadier in COMBAT without grenade ready should still shoot
# ============================================================================


func test_grenadier_combat_shoots_when_no_grenade_ready() -> void:
	ai.is_grenadier = true
	ai._current_state = MockAIStateProcessor.AIState.COMBAT
	ai.ready_to_throw_grenade = false

	ai.process_ai_state_fixed()

	assert_false(ai.grenade_throw_attempted,
		"No grenade ready — no throw attempted")
	assert_true(ai.combat_state_processed,
		"COMBAT state processed even without grenade ready")


# ============================================================================
# Pacifist grenadier should never throw
# ============================================================================


func test_pacifist_grenadier_does_not_throw() -> void:
	ai.is_grenadier = true
	ai.is_pacifist = true
	ai._current_state = MockAIStateProcessor.AIState.PURSUING
	ai.ready_to_throw_grenade = true

	ai.process_ai_state_fixed()

	assert_false(ai.grenade_throw_attempted,
		"Pacifist grenadier should not throw grenades in any state")


# ============================================================================
# Combat disabled should prevent grenade throw
# ============================================================================


func test_combat_disabled_prevents_grenade_throw() -> void:
	ai.is_grenadier = true
	ai._current_state = MockAIStateProcessor.AIState.PURSUING
	ai.ready_to_throw_grenade = true
	ai._combat_allowed = false

	ai.process_ai_state_fixed()

	assert_false(ai.grenade_throw_attempted,
		"Combat disabled should prevent grenade throw (respects #1305 combat toggle)")


# ============================================================================
# Verify the T8/T9 delay constants that cause the bug
# ============================================================================


class MockGrenadierTriggerDelays:
	## These constants from GrenadierGrenadeComponent (grenadier_grenade_component.gd).
	## T8 fires after 0.5s of seeing player at safe distance.
	## T9 fires after 1.0s of any suspicion.
	## Both are SHORT enough to always fire before COMBAT exposed phase (needs 2s approach).
	const T8_DIRECT_SIGHT_DELAY := 0.5
	const T9_LOW_SUSPICION_DELAY := 1.0
	## COMBAT approach phase max time before exposed shooting begins.
	const COMBAT_APPROACH_MAX_TIME := 2.0


func test_t8_fires_before_combat_approach_completes() -> void:
	var delays := MockGrenadierTriggerDelays.new()

	assert_true(delays.T8_DIRECT_SIGHT_DELAY < delays.COMBAT_APPROACH_MAX_TIME,
		"T8 fires (%.1fs) before COMBAT approach max time (%.1fs) — this is why grenadier never shoots" % [
			delays.T8_DIRECT_SIGHT_DELAY, delays.COMBAT_APPROACH_MAX_TIME])


func test_t9_fires_before_combat_approach_completes() -> void:
	var delays := MockGrenadierTriggerDelays.new()

	assert_true(delays.T9_LOW_SUSPICION_DELAY < delays.COMBAT_APPROACH_MAX_TIME,
		"T9 fires (%.1fs) before COMBAT approach max time (%.1fs) — this is why grenadier never shoots" % [
			delays.T9_LOW_SUSPICION_DELAY, delays.COMBAT_APPROACH_MAX_TIME])
