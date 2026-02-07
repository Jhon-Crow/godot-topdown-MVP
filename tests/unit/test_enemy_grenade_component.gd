extends GutTest
## Unit tests for EnemyGrenadeComponent.
##
## Tests the enemy grenade throwing decision logic including all 7 trigger
## conditions, is_ready guard clauses, event handlers (on_ally_died,
## on_vulnerable_sound), add_grenades, and _reset_triggers.


# ============================================================================
# Mock EnemyGrenadeComponent for Logic Tests
# ============================================================================


class MockEnemyGrenadeComponent:
	## Configuration - mirrors export vars from EnemyGrenadeComponent.
	var grenade_count: int = 0
	var enabled: bool = true
	var throw_cooldown: float = 15.0
	var max_throw_distance: float = 600.0
	var min_throw_distance: float = 275.0
	var safety_margin: float = 50.0
	var inaccuracy: float = 0.15
	var throw_delay: float = 0.4

	## Constants - identical to EnemyGrenadeComponent.
	const HIDDEN_THRESHOLD := 6.0
	const PURSUIT_SPEED_THRESHOLD := 50.0
	const KILL_THRESHOLD := 2
	const KILL_WITNESS_WINDOW := 30.0
	const SOUND_VALIDITY_WINDOW := 5.0
	const SUSTAINED_FIRE_THRESHOLD := 10.0
	const FIRE_GAP_TOLERANCE := 2.0
	const VIEWPORT_ZONE_FRACTION := 6.0
	const DESPERATION_HEALTH_THRESHOLD := 1
	const SUSPICION_HIDDEN_TIME := 3.0

	## State - mirrors EnemyGrenadeComponent state.
	var grenades_remaining: int = 0
	var _cooldown: float = 0.0
	var _is_throwing: bool = false

	## Trigger 1: Suppression.
	var _hidden_timer: float = 0.0
	var _was_suppressed: bool = false

	## Trigger 2: Pursuit.
	var _prev_dist: float = 0.0
	var _approach_speed: float = 0.0

	## Trigger 3: Witnessed Kills.
	var _kills_witnessed: int = 0
	var _kill_reset_timer: float = 0.0

	## Trigger 4: Sound.
	var _heard_sound: bool = false
	var _sound_pos: Vector2 = Vector2.ZERO
	var _sound_time: float = 0.0

	## Trigger 5: Sustained Fire.
	var _fire_zone: Vector2 = Vector2.ZERO
	var _fire_time: float = 0.0
	var _fire_duration: float = 0.0
	var _fire_valid: bool = false

	## Trigger 7: Suspicion.
	var _suspicion_timer: float = 0.0

	## Mock time source: set this to simulate Time.get_ticks_msec() / 1000.0.
	var _mock_time: float = 100.0

	## Reset all trigger state - mirrors _reset_triggers().
	func _reset_triggers() -> void:
		_hidden_timer = 0.0
		_was_suppressed = false
		_kills_witnessed = 0
		_heard_sound = false
		_fire_valid = false
		_fire_duration = 0.0
		_suspicion_timer = 0.0

	## Trigger 1: Suppressed and hidden long enough.
	func _t1() -> bool:
		return _was_suppressed and _hidden_timer >= HIDDEN_THRESHOLD

	## Trigger 2: Approaching under fire fast enough.
	func _t2(under_fire: bool) -> bool:
		return under_fire and _approach_speed >= PURSUIT_SPEED_THRESHOLD

	## Trigger 3: Witnessed enough ally kills.
	func _t3() -> bool:
		return _kills_witnessed >= KILL_THRESHOLD

	## Trigger 4: Heard a sound and cannot see the source.
	func _t4(can_see: bool) -> bool:
		if not _heard_sound:
			return false
		if _mock_time - _sound_time > SOUND_VALIDITY_WINDOW:
			_heard_sound = false
			return false
		return not can_see

	## Trigger 5: Sustained fire detected in a zone.
	func _t5() -> bool:
		return _fire_valid and _fire_duration >= SUSTAINED_FIRE_THRESHOLD

	## Trigger 6: Desperation at low health.
	func _t6(health: int) -> bool:
		return health <= DESPERATION_HEALTH_THRESHOLD

	## Trigger 7: Suspicion-based, player hidden with high suspicion.
	func _t7() -> bool:
		return _suspicion_timer >= SUSPICION_HIDDEN_TIME

	## Check if ready to throw - mirrors is_ready() from EnemyGrenadeComponent.
	func is_ready(can_see: bool, under_fire: bool, health: int) -> bool:
		if not enabled or grenades_remaining <= 0 or _cooldown > 0.0 or _is_throwing:
			return false
		return _t1() or _t2(under_fire) or _t3() or _t4(can_see) or _t5() or _t6(health) or _t7()

	## Handle ally death event - mirrors on_ally_died().
	func on_ally_died(pos: Vector2, by_player: bool, can_see_pos: bool) -> void:
		if not by_player or not enabled or grenades_remaining <= 0 or not can_see_pos:
			return
		_kills_witnessed += 1
		_kill_reset_timer = KILL_WITNESS_WINDOW

	## Handle vulnerable sound event - mirrors on_vulnerable_sound().
	func on_vulnerable_sound(pos: Vector2, can_see: bool) -> void:
		if not enabled or grenades_remaining <= 0 or can_see:
			return
		_heard_sound = true
		_sound_pos = pos
		_sound_time = _mock_time

	## Add grenades - mirrors add_grenades().
	func add_grenades(count: int) -> void:
		grenades_remaining += count


# ============================================================================
# Test Variables and Setup
# ============================================================================


var comp: MockEnemyGrenadeComponent


func before_each() -> void:
	comp = MockEnemyGrenadeComponent.new()
	comp.enabled = true
	comp.grenades_remaining = 5
	comp._cooldown = 0.0
	comp._is_throwing = false


func after_each() -> void:
	comp = null


# ============================================================================
# Constants Verification Tests
# ============================================================================


func test_constant_hidden_threshold() -> void:
	assert_eq(MockEnemyGrenadeComponent.HIDDEN_THRESHOLD, 6.0,
		"HIDDEN_THRESHOLD should be 6.0")


func test_constant_pursuit_speed_threshold() -> void:
	assert_eq(MockEnemyGrenadeComponent.PURSUIT_SPEED_THRESHOLD, 50.0,
		"PURSUIT_SPEED_THRESHOLD should be 50.0")


func test_constant_kill_threshold() -> void:
	assert_eq(MockEnemyGrenadeComponent.KILL_THRESHOLD, 2,
		"KILL_THRESHOLD should be 2")


func test_constant_kill_witness_window() -> void:
	assert_eq(MockEnemyGrenadeComponent.KILL_WITNESS_WINDOW, 30.0,
		"KILL_WITNESS_WINDOW should be 30.0")


func test_constant_sound_validity_window() -> void:
	assert_eq(MockEnemyGrenadeComponent.SOUND_VALIDITY_WINDOW, 5.0,
		"SOUND_VALIDITY_WINDOW should be 5.0")


func test_constant_sustained_fire_threshold() -> void:
	assert_eq(MockEnemyGrenadeComponent.SUSTAINED_FIRE_THRESHOLD, 10.0,
		"SUSTAINED_FIRE_THRESHOLD should be 10.0")


func test_constant_fire_gap_tolerance() -> void:
	assert_eq(MockEnemyGrenadeComponent.FIRE_GAP_TOLERANCE, 2.0,
		"FIRE_GAP_TOLERANCE should be 2.0")


func test_constant_viewport_zone_fraction() -> void:
	assert_eq(MockEnemyGrenadeComponent.VIEWPORT_ZONE_FRACTION, 6.0,
		"VIEWPORT_ZONE_FRACTION should be 6.0")


func test_constant_desperation_health_threshold() -> void:
	assert_eq(MockEnemyGrenadeComponent.DESPERATION_HEALTH_THRESHOLD, 1,
		"DESPERATION_HEALTH_THRESHOLD should be 1")


func test_constant_suspicion_hidden_time() -> void:
	assert_eq(MockEnemyGrenadeComponent.SUSPICION_HIDDEN_TIME, 3.0,
		"SUSPICION_HIDDEN_TIME should be 3.0")


# ============================================================================
# Default Configuration Tests
# ============================================================================


func test_default_throw_cooldown() -> void:
	var fresh := MockEnemyGrenadeComponent.new()
	assert_eq(fresh.throw_cooldown, 15.0,
		"Default throw_cooldown should be 15.0")


func test_default_max_throw_distance() -> void:
	var fresh := MockEnemyGrenadeComponent.new()
	assert_eq(fresh.max_throw_distance, 600.0,
		"Default max_throw_distance should be 600.0")


func test_default_min_throw_distance() -> void:
	var fresh := MockEnemyGrenadeComponent.new()
	assert_eq(fresh.min_throw_distance, 275.0,
		"Default min_throw_distance should be 275.0")


func test_default_safety_margin() -> void:
	var fresh := MockEnemyGrenadeComponent.new()
	assert_eq(fresh.safety_margin, 50.0,
		"Default safety_margin should be 50.0")


func test_default_inaccuracy() -> void:
	var fresh := MockEnemyGrenadeComponent.new()
	assert_eq(fresh.inaccuracy, 0.15,
		"Default inaccuracy should be 0.15")


func test_default_throw_delay() -> void:
	var fresh := MockEnemyGrenadeComponent.new()
	assert_eq(fresh.throw_delay, 0.4,
		"Default throw_delay should be 0.4")


func test_default_enabled() -> void:
	var fresh := MockEnemyGrenadeComponent.new()
	assert_true(fresh.enabled,
		"Component should be enabled by default")


func test_default_grenade_count() -> void:
	var fresh := MockEnemyGrenadeComponent.new()
	assert_eq(fresh.grenade_count, 0,
		"Default grenade_count should be 0")


# ============================================================================
# Initial State Tests
# ============================================================================


func test_initial_grenades_remaining_is_zero() -> void:
	var fresh := MockEnemyGrenadeComponent.new()
	assert_eq(fresh.grenades_remaining, 0,
		"grenades_remaining should start at 0")


func test_initial_cooldown_is_zero() -> void:
	var fresh := MockEnemyGrenadeComponent.new()
	assert_eq(fresh._cooldown, 0.0,
		"_cooldown should start at 0.0")


func test_initial_is_throwing_is_false() -> void:
	var fresh := MockEnemyGrenadeComponent.new()
	assert_false(fresh._is_throwing,
		"_is_throwing should start as false")


func test_initial_hidden_timer_is_zero() -> void:
	var fresh := MockEnemyGrenadeComponent.new()
	assert_eq(fresh._hidden_timer, 0.0,
		"_hidden_timer should start at 0.0")


func test_initial_was_suppressed_is_false() -> void:
	var fresh := MockEnemyGrenadeComponent.new()
	assert_false(fresh._was_suppressed,
		"_was_suppressed should start as false")


func test_initial_kills_witnessed_is_zero() -> void:
	var fresh := MockEnemyGrenadeComponent.new()
	assert_eq(fresh._kills_witnessed, 0,
		"_kills_witnessed should start at 0")


func test_initial_heard_sound_is_false() -> void:
	var fresh := MockEnemyGrenadeComponent.new()
	assert_false(fresh._heard_sound,
		"_heard_sound should start as false")


func test_initial_fire_valid_is_false() -> void:
	var fresh := MockEnemyGrenadeComponent.new()
	assert_false(fresh._fire_valid,
		"_fire_valid should start as false")


func test_initial_suspicion_timer_is_zero() -> void:
	var fresh := MockEnemyGrenadeComponent.new()
	assert_eq(fresh._suspicion_timer, 0.0,
		"_suspicion_timer should start at 0.0")


# ============================================================================
# Trigger 1: Suppression (_t1) Tests
# ============================================================================


func test_t1_false_when_not_suppressed() -> void:
	comp._was_suppressed = false
	comp._hidden_timer = 10.0

	assert_false(comp._t1(),
		"T1 should be false when not suppressed, even with high hidden timer")


func test_t1_false_when_hidden_timer_below_threshold() -> void:
	comp._was_suppressed = true
	comp._hidden_timer = 5.9

	assert_false(comp._t1(),
		"T1 should be false when hidden timer is below HIDDEN_THRESHOLD")


func test_t1_true_when_suppressed_and_hidden_long_enough() -> void:
	comp._was_suppressed = true
	comp._hidden_timer = 6.0

	assert_true(comp._t1(),
		"T1 should be true when suppressed and hidden for >= HIDDEN_THRESHOLD")


func test_t1_true_when_suppressed_and_hidden_well_above_threshold() -> void:
	comp._was_suppressed = true
	comp._hidden_timer = 20.0

	assert_true(comp._t1(),
		"T1 should be true when hidden timer is well above threshold")


func test_t1_false_when_both_conditions_unmet() -> void:
	comp._was_suppressed = false
	comp._hidden_timer = 0.0

	assert_false(comp._t1(),
		"T1 should be false when neither suppressed nor hidden")


func test_t1_boundary_exactly_at_threshold() -> void:
	comp._was_suppressed = true
	comp._hidden_timer = 6.0

	assert_true(comp._t1(),
		"T1 should be true at exactly HIDDEN_THRESHOLD (6.0)")


func test_t1_boundary_just_below_threshold() -> void:
	comp._was_suppressed = true
	comp._hidden_timer = 5.999

	assert_false(comp._t1(),
		"T1 should be false just below HIDDEN_THRESHOLD")


# ============================================================================
# Trigger 2: Pursuit (_t2) Tests
# ============================================================================


func test_t2_false_when_not_under_fire() -> void:
	comp._approach_speed = 100.0

	assert_false(comp._t2(false),
		"T2 should be false when not under fire, even with high speed")


func test_t2_false_when_speed_below_threshold() -> void:
	comp._approach_speed = 49.9

	assert_false(comp._t2(true),
		"T2 should be false when approach speed is below PURSUIT_SPEED_THRESHOLD")


func test_t2_true_when_under_fire_and_fast_approach() -> void:
	comp._approach_speed = 50.0

	assert_true(comp._t2(true),
		"T2 should be true when under fire and approach speed >= PURSUIT_SPEED_THRESHOLD")


func test_t2_true_with_very_high_approach_speed() -> void:
	comp._approach_speed = 200.0

	assert_true(comp._t2(true),
		"T2 should be true with high approach speed and under fire")


func test_t2_false_when_both_conditions_unmet() -> void:
	comp._approach_speed = 10.0

	assert_false(comp._t2(false),
		"T2 should be false when neither under fire nor fast approach")


func test_t2_boundary_exactly_at_threshold() -> void:
	comp._approach_speed = 50.0

	assert_true(comp._t2(true),
		"T2 should be true at exactly PURSUIT_SPEED_THRESHOLD (50.0)")


func test_t2_boundary_just_below_threshold() -> void:
	comp._approach_speed = 49.999

	assert_false(comp._t2(true),
		"T2 should be false just below PURSUIT_SPEED_THRESHOLD")


# ============================================================================
# Trigger 3: Witnessed Kills (_t3) Tests
# ============================================================================


func test_t3_false_with_zero_kills() -> void:
	comp._kills_witnessed = 0

	assert_false(comp._t3(),
		"T3 should be false with 0 kills witnessed")


func test_t3_false_with_one_kill() -> void:
	comp._kills_witnessed = 1

	assert_false(comp._t3(),
		"T3 should be false with only 1 kill witnessed (threshold is 2)")


func test_t3_true_with_two_kills() -> void:
	comp._kills_witnessed = 2

	assert_true(comp._t3(),
		"T3 should be true when kills witnessed reaches KILL_THRESHOLD (2)")


func test_t3_true_with_many_kills() -> void:
	comp._kills_witnessed = 10

	assert_true(comp._t3(),
		"T3 should be true when kills witnessed exceeds threshold")


func test_t3_boundary_exactly_at_threshold() -> void:
	comp._kills_witnessed = 2

	assert_true(comp._t3(),
		"T3 should be true at exactly KILL_THRESHOLD (2)")


# ============================================================================
# Trigger 4: Sound (_t4) Tests
# ============================================================================


func test_t4_false_when_no_sound_heard() -> void:
	comp._heard_sound = false

	assert_false(comp._t4(false),
		"T4 should be false when no sound has been heard")


func test_t4_false_when_can_see() -> void:
	comp._heard_sound = true
	comp._sound_time = 99.0
	comp._mock_time = 100.0

	assert_false(comp._t4(true),
		"T4 should be false when enemy can see the player")


func test_t4_true_when_heard_sound_and_cannot_see_within_window() -> void:
	comp._heard_sound = true
	comp._sound_time = 98.0
	comp._mock_time = 100.0  # 2 seconds elapsed, within 5s window

	assert_true(comp._t4(false),
		"T4 should be true when heard sound, cannot see, within validity window")


func test_t4_false_when_sound_expired() -> void:
	comp._heard_sound = true
	comp._sound_time = 90.0
	comp._mock_time = 100.0  # 10 seconds elapsed, exceeds 5s window

	assert_false(comp._t4(false),
		"T4 should be false when sound has expired beyond SOUND_VALIDITY_WINDOW")


func test_t4_clears_heard_sound_when_expired() -> void:
	comp._heard_sound = true
	comp._sound_time = 90.0
	comp._mock_time = 100.0  # Expired

	comp._t4(false)

	assert_false(comp._heard_sound,
		"T4 should clear _heard_sound flag when sound validity expires")


func test_t4_boundary_exactly_at_window_edge() -> void:
	comp._heard_sound = true
	comp._sound_time = 95.0
	comp._mock_time = 100.0  # Exactly 5.0 seconds elapsed

	# 100.0 - 95.0 = 5.0, which is NOT > 5.0, so still valid
	assert_true(comp._t4(false),
		"T4 should be true at exactly SOUND_VALIDITY_WINDOW boundary")


func test_t4_boundary_just_past_window() -> void:
	comp._heard_sound = true
	comp._sound_time = 94.99
	comp._mock_time = 100.0  # 5.01 seconds elapsed

	assert_false(comp._t4(false),
		"T4 should be false just past SOUND_VALIDITY_WINDOW")


func test_t4_false_when_no_sound_even_cannot_see() -> void:
	comp._heard_sound = false

	assert_false(comp._t4(false),
		"T4 should be false when no sound heard, even if cannot see player")


# ============================================================================
# Trigger 5: Sustained Fire (_t5) Tests
# ============================================================================


func test_t5_false_when_fire_not_valid() -> void:
	comp._fire_valid = false
	comp._fire_duration = 20.0

	assert_false(comp._t5(),
		"T5 should be false when fire tracking is not valid")


func test_t5_false_when_duration_below_threshold() -> void:
	comp._fire_valid = true
	comp._fire_duration = 9.9

	assert_false(comp._t5(),
		"T5 should be false when fire duration is below SUSTAINED_FIRE_THRESHOLD")


func test_t5_true_when_valid_and_sustained() -> void:
	comp._fire_valid = true
	comp._fire_duration = 10.0

	assert_true(comp._t5(),
		"T5 should be true when fire is valid and duration >= SUSTAINED_FIRE_THRESHOLD")


func test_t5_true_with_long_sustained_fire() -> void:
	comp._fire_valid = true
	comp._fire_duration = 30.0

	assert_true(comp._t5(),
		"T5 should be true with long sustained fire")


func test_t5_false_when_both_conditions_unmet() -> void:
	comp._fire_valid = false
	comp._fire_duration = 0.0

	assert_false(comp._t5(),
		"T5 should be false when fire is neither valid nor has duration")


func test_t5_boundary_exactly_at_threshold() -> void:
	comp._fire_valid = true
	comp._fire_duration = 10.0

	assert_true(comp._t5(),
		"T5 should be true at exactly SUSTAINED_FIRE_THRESHOLD (10.0)")


func test_t5_boundary_just_below_threshold() -> void:
	comp._fire_valid = true
	comp._fire_duration = 9.999

	assert_false(comp._t5(),
		"T5 should be false just below SUSTAINED_FIRE_THRESHOLD")


# ============================================================================
# Trigger 6: Desperation (_t6) Tests
# ============================================================================


func test_t6_false_at_full_health() -> void:
	assert_false(comp._t6(10),
		"T6 should be false at full health")


func test_t6_false_at_health_above_threshold() -> void:
	assert_false(comp._t6(2),
		"T6 should be false at health 2 (above threshold of 1)")


func test_t6_true_at_threshold_health() -> void:
	assert_true(comp._t6(1),
		"T6 should be true at health == DESPERATION_HEALTH_THRESHOLD (1)")


func test_t6_true_at_zero_health() -> void:
	assert_true(comp._t6(0),
		"T6 should be true at health 0")


func test_t6_true_at_negative_health() -> void:
	assert_true(comp._t6(-1),
		"T6 should be true at negative health")


func test_t6_boundary_exactly_at_threshold() -> void:
	assert_true(comp._t6(1),
		"T6 should be true at exactly DESPERATION_HEALTH_THRESHOLD (1)")


func test_t6_boundary_just_above_threshold() -> void:
	assert_false(comp._t6(2),
		"T6 should be false at health 2 (just above threshold)")


# ============================================================================
# Trigger 7: Suspicion (_t7) Tests
# ============================================================================


func test_t7_false_when_suspicion_timer_zero() -> void:
	comp._suspicion_timer = 0.0

	assert_false(comp._t7(),
		"T7 should be false when suspicion timer is 0")


func test_t7_false_when_suspicion_timer_below_threshold() -> void:
	comp._suspicion_timer = 2.9

	assert_false(comp._t7(),
		"T7 should be false when suspicion timer is below SUSPICION_HIDDEN_TIME")


func test_t7_true_when_suspicion_timer_meets_threshold() -> void:
	comp._suspicion_timer = 3.0

	assert_true(comp._t7(),
		"T7 should be true when suspicion timer >= SUSPICION_HIDDEN_TIME (3.0)")


func test_t7_true_when_suspicion_timer_exceeds_threshold() -> void:
	comp._suspicion_timer = 10.0

	assert_true(comp._t7(),
		"T7 should be true when suspicion timer well above threshold")


func test_t7_boundary_exactly_at_threshold() -> void:
	comp._suspicion_timer = 3.0

	assert_true(comp._t7(),
		"T7 should be true at exactly SUSPICION_HIDDEN_TIME (3.0)")


func test_t7_boundary_just_below_threshold() -> void:
	comp._suspicion_timer = 2.999

	assert_false(comp._t7(),
		"T7 should be false just below SUSPICION_HIDDEN_TIME")


# ============================================================================
# is_ready() Guard Clause Tests
# ============================================================================


func test_is_ready_false_when_disabled() -> void:
	comp.enabled = false
	comp._was_suppressed = true
	comp._hidden_timer = 10.0

	assert_false(comp.is_ready(false, false, 10),
		"is_ready should return false when component is disabled")


func test_is_ready_false_when_no_grenades() -> void:
	comp.grenades_remaining = 0
	comp._was_suppressed = true
	comp._hidden_timer = 10.0

	assert_false(comp.is_ready(false, false, 10),
		"is_ready should return false when no grenades remaining")


func test_is_ready_false_when_negative_grenades() -> void:
	comp.grenades_remaining = -1
	comp._was_suppressed = true
	comp._hidden_timer = 10.0

	assert_false(comp.is_ready(false, false, 10),
		"is_ready should return false when grenades_remaining is negative")


func test_is_ready_false_when_cooldown_active() -> void:
	comp._cooldown = 5.0
	comp._was_suppressed = true
	comp._hidden_timer = 10.0

	assert_false(comp.is_ready(false, false, 10),
		"is_ready should return false when cooldown is active")


func test_is_ready_false_when_currently_throwing() -> void:
	comp._is_throwing = true
	comp._was_suppressed = true
	comp._hidden_timer = 10.0

	assert_false(comp.is_ready(false, false, 10),
		"is_ready should return false when currently throwing")


func test_is_ready_false_when_no_triggers_active() -> void:
	assert_false(comp.is_ready(true, false, 10),
		"is_ready should return false when no triggers are active")


func test_is_ready_false_when_cooldown_barely_positive() -> void:
	comp._cooldown = 0.001
	comp._was_suppressed = true
	comp._hidden_timer = 10.0

	assert_false(comp.is_ready(false, false, 10),
		"is_ready should return false when cooldown is barely positive")


func test_is_ready_true_when_cooldown_zero_and_trigger_active() -> void:
	comp._cooldown = 0.0
	comp._was_suppressed = true
	comp._hidden_timer = 10.0

	assert_true(comp.is_ready(false, false, 10),
		"is_ready should return true when cooldown is exactly 0 and T1 active")


# ============================================================================
# is_ready() with Individual Triggers Tests
# ============================================================================


func test_is_ready_true_via_t1_suppression() -> void:
	comp._was_suppressed = true
	comp._hidden_timer = 6.0

	assert_true(comp.is_ready(false, false, 10),
		"is_ready should return true when T1 (suppression) is active")


func test_is_ready_true_via_t2_pursuit() -> void:
	comp._approach_speed = 60.0

	assert_true(comp.is_ready(false, true, 10),
		"is_ready should return true when T2 (pursuit) is active")


func test_is_ready_true_via_t3_witnessed_kills() -> void:
	comp._kills_witnessed = 3

	assert_true(comp.is_ready(true, false, 10),
		"is_ready should return true when T3 (witnessed kills) is active")


func test_is_ready_true_via_t4_sound() -> void:
	comp._heard_sound = true
	comp._sound_time = 99.0
	comp._mock_time = 100.0

	assert_true(comp.is_ready(false, false, 10),
		"is_ready should return true when T4 (sound) is active")


func test_is_ready_true_via_t5_sustained_fire() -> void:
	comp._fire_valid = true
	comp._fire_duration = 15.0

	assert_true(comp.is_ready(true, false, 10),
		"is_ready should return true when T5 (sustained fire) is active")


func test_is_ready_true_via_t6_desperation() -> void:
	assert_true(comp.is_ready(true, false, 1),
		"is_ready should return true when T6 (desperation) is active at health 1")


func test_is_ready_true_via_t6_desperation_zero_health() -> void:
	assert_true(comp.is_ready(true, false, 0),
		"is_ready should return true when T6 (desperation) is active at health 0")


func test_is_ready_true_via_t7_suspicion() -> void:
	comp._suspicion_timer = 5.0

	assert_true(comp.is_ready(true, false, 10),
		"is_ready should return true when T7 (suspicion) is active")


# ============================================================================
# is_ready() Multiple Triggers Combined Tests
# ============================================================================


func test_is_ready_true_with_multiple_triggers_active() -> void:
	comp._was_suppressed = true
	comp._hidden_timer = 10.0
	comp._kills_witnessed = 5
	comp._suspicion_timer = 5.0

	assert_true(comp.is_ready(false, false, 10),
		"is_ready should return true when multiple triggers are active simultaneously")


func test_is_ready_true_with_all_triggers_active() -> void:
	comp._was_suppressed = true
	comp._hidden_timer = 10.0
	comp._approach_speed = 100.0
	comp._kills_witnessed = 5
	comp._heard_sound = true
	comp._sound_time = 99.0
	comp._mock_time = 100.0
	comp._fire_valid = true
	comp._fire_duration = 20.0
	comp._suspicion_timer = 5.0

	assert_true(comp.is_ready(false, true, 1),
		"is_ready should return true when all triggers are active")


func test_is_ready_guard_overrides_all_triggers() -> void:
	# Set all triggers active
	comp._was_suppressed = true
	comp._hidden_timer = 10.0
	comp._approach_speed = 100.0
	comp._kills_witnessed = 5
	comp._heard_sound = true
	comp._sound_time = 99.0
	comp._mock_time = 100.0
	comp._fire_valid = true
	comp._fire_duration = 20.0
	comp._suspicion_timer = 5.0

	# But disable the component
	comp.enabled = false

	assert_false(comp.is_ready(false, true, 1),
		"is_ready should return false when disabled, even with all triggers active")


func test_is_ready_no_grenades_overrides_all_triggers() -> void:
	comp._was_suppressed = true
	comp._hidden_timer = 10.0
	comp._kills_witnessed = 5
	comp.grenades_remaining = 0

	assert_false(comp.is_ready(false, false, 1),
		"is_ready should return false with no grenades, even with triggers active")


# ============================================================================
# on_ally_died() Tests
# ============================================================================


func test_on_ally_died_increments_kills_witnessed() -> void:
	comp.on_ally_died(Vector2(100, 100), true, true)

	assert_eq(comp._kills_witnessed, 1,
		"on_ally_died should increment _kills_witnessed by 1")


func test_on_ally_died_sets_kill_reset_timer() -> void:
	comp.on_ally_died(Vector2(100, 100), true, true)

	assert_eq(comp._kill_reset_timer, MockEnemyGrenadeComponent.KILL_WITNESS_WINDOW,
		"on_ally_died should set _kill_reset_timer to KILL_WITNESS_WINDOW")


func test_on_ally_died_accumulates_kills() -> void:
	comp.on_ally_died(Vector2(100, 100), true, true)
	comp.on_ally_died(Vector2(200, 200), true, true)
	comp.on_ally_died(Vector2(300, 300), true, true)

	assert_eq(comp._kills_witnessed, 3,
		"on_ally_died should accumulate kills across multiple calls")


func test_on_ally_died_ignored_when_not_by_player() -> void:
	comp.on_ally_died(Vector2(100, 100), false, true)

	assert_eq(comp._kills_witnessed, 0,
		"on_ally_died should be ignored when kill was not by player")


func test_on_ally_died_ignored_when_disabled() -> void:
	comp.enabled = false
	comp.on_ally_died(Vector2(100, 100), true, true)

	assert_eq(comp._kills_witnessed, 0,
		"on_ally_died should be ignored when component is disabled")


func test_on_ally_died_ignored_when_no_grenades() -> void:
	comp.grenades_remaining = 0
	comp.on_ally_died(Vector2(100, 100), true, true)

	assert_eq(comp._kills_witnessed, 0,
		"on_ally_died should be ignored when no grenades remaining")


func test_on_ally_died_ignored_when_cannot_see_position() -> void:
	comp.on_ally_died(Vector2(100, 100), true, false)

	assert_eq(comp._kills_witnessed, 0,
		"on_ally_died should be ignored when cannot see the death position")


func test_on_ally_died_requires_all_conditions() -> void:
	# All conditions must be met: by_player, enabled, grenades > 0, can_see_pos
	comp.on_ally_died(Vector2(100, 100), true, true)
	assert_eq(comp._kills_witnessed, 1,
		"on_ally_died should work when all conditions are met")


func test_on_ally_died_resets_timer_on_each_kill() -> void:
	comp.on_ally_died(Vector2(100, 100), true, true)
	comp._kill_reset_timer = 10.0  # Simulate time passing

	comp.on_ally_died(Vector2(200, 200), true, true)

	assert_eq(comp._kill_reset_timer, MockEnemyGrenadeComponent.KILL_WITNESS_WINDOW,
		"on_ally_died should refresh the kill reset timer on each new kill")


# ============================================================================
# on_vulnerable_sound() Tests
# ============================================================================


func test_on_vulnerable_sound_sets_heard_sound() -> void:
	comp.on_vulnerable_sound(Vector2(300, 300), false)

	assert_true(comp._heard_sound,
		"on_vulnerable_sound should set _heard_sound to true")


func test_on_vulnerable_sound_stores_position() -> void:
	comp.on_vulnerable_sound(Vector2(300, 300), false)

	assert_eq(comp._sound_pos, Vector2(300, 300),
		"on_vulnerable_sound should store the sound position")


func test_on_vulnerable_sound_stores_time() -> void:
	comp._mock_time = 150.0
	comp.on_vulnerable_sound(Vector2(300, 300), false)

	assert_eq(comp._sound_time, 150.0,
		"on_vulnerable_sound should store the current time")


func test_on_vulnerable_sound_ignored_when_can_see() -> void:
	comp.on_vulnerable_sound(Vector2(300, 300), true)

	assert_false(comp._heard_sound,
		"on_vulnerable_sound should be ignored when enemy can see the player")


func test_on_vulnerable_sound_ignored_when_disabled() -> void:
	comp.enabled = false
	comp.on_vulnerable_sound(Vector2(300, 300), false)

	assert_false(comp._heard_sound,
		"on_vulnerable_sound should be ignored when component is disabled")


func test_on_vulnerable_sound_ignored_when_no_grenades() -> void:
	comp.grenades_remaining = 0
	comp.on_vulnerable_sound(Vector2(300, 300), false)

	assert_false(comp._heard_sound,
		"on_vulnerable_sound should be ignored when no grenades remaining")


func test_on_vulnerable_sound_overwrites_previous_sound() -> void:
	comp._mock_time = 100.0
	comp.on_vulnerable_sound(Vector2(100, 100), false)

	comp._mock_time = 105.0
	comp.on_vulnerable_sound(Vector2(500, 500), false)

	assert_eq(comp._sound_pos, Vector2(500, 500),
		"on_vulnerable_sound should overwrite previous sound position")
	assert_eq(comp._sound_time, 105.0,
		"on_vulnerable_sound should overwrite previous sound time")


# ============================================================================
# add_grenades() Tests
# ============================================================================


func test_add_grenades_increases_count() -> void:
	comp.grenades_remaining = 3
	comp.add_grenades(2)

	assert_eq(comp.grenades_remaining, 5,
		"add_grenades should increase grenades_remaining by the given count")


func test_add_grenades_from_zero() -> void:
	comp.grenades_remaining = 0
	comp.add_grenades(5)

	assert_eq(comp.grenades_remaining, 5,
		"add_grenades should work starting from 0 grenades")


func test_add_grenades_with_one() -> void:
	comp.grenades_remaining = 2
	comp.add_grenades(1)

	assert_eq(comp.grenades_remaining, 3,
		"add_grenades should work with count of 1")


func test_add_grenades_with_zero() -> void:
	comp.grenades_remaining = 3
	comp.add_grenades(0)

	assert_eq(comp.grenades_remaining, 3,
		"add_grenades with 0 should not change grenades_remaining")


func test_add_grenades_with_negative_decreases_count() -> void:
	comp.grenades_remaining = 5
	comp.add_grenades(-2)

	assert_eq(comp.grenades_remaining, 3,
		"add_grenades with negative count should decrease grenades_remaining")


func test_add_grenades_multiple_calls_accumulate() -> void:
	comp.grenades_remaining = 0
	comp.add_grenades(3)
	comp.add_grenades(2)
	comp.add_grenades(1)

	assert_eq(comp.grenades_remaining, 6,
		"Multiple add_grenades calls should accumulate")


# ============================================================================
# _reset_triggers() Tests
# ============================================================================


func test_reset_triggers_clears_hidden_timer() -> void:
	comp._hidden_timer = 10.0
	comp._reset_triggers()

	assert_eq(comp._hidden_timer, 0.0,
		"_reset_triggers should clear _hidden_timer to 0.0")


func test_reset_triggers_clears_was_suppressed() -> void:
	comp._was_suppressed = true
	comp._reset_triggers()

	assert_false(comp._was_suppressed,
		"_reset_triggers should clear _was_suppressed to false")


func test_reset_triggers_clears_kills_witnessed() -> void:
	comp._kills_witnessed = 5
	comp._reset_triggers()

	assert_eq(comp._kills_witnessed, 0,
		"_reset_triggers should clear _kills_witnessed to 0")


func test_reset_triggers_clears_heard_sound() -> void:
	comp._heard_sound = true
	comp._reset_triggers()

	assert_false(comp._heard_sound,
		"_reset_triggers should clear _heard_sound to false")


func test_reset_triggers_clears_fire_valid() -> void:
	comp._fire_valid = true
	comp._reset_triggers()

	assert_false(comp._fire_valid,
		"_reset_triggers should clear _fire_valid to false")


func test_reset_triggers_clears_fire_duration() -> void:
	comp._fire_duration = 15.0
	comp._reset_triggers()

	assert_eq(comp._fire_duration, 0.0,
		"_reset_triggers should clear _fire_duration to 0.0")


func test_reset_triggers_clears_suspicion_timer() -> void:
	comp._suspicion_timer = 5.0
	comp._reset_triggers()

	assert_eq(comp._suspicion_timer, 0.0,
		"_reset_triggers should clear _suspicion_timer to 0.0")


func test_reset_triggers_clears_all_state_at_once() -> void:
	# Set all trigger state
	comp._hidden_timer = 10.0
	comp._was_suppressed = true
	comp._kills_witnessed = 5
	comp._heard_sound = true
	comp._fire_valid = true
	comp._fire_duration = 20.0
	comp._suspicion_timer = 8.0

	comp._reset_triggers()

	assert_eq(comp._hidden_timer, 0.0, "hidden_timer should be reset")
	assert_false(comp._was_suppressed, "was_suppressed should be reset")
	assert_eq(comp._kills_witnessed, 0, "kills_witnessed should be reset")
	assert_false(comp._heard_sound, "heard_sound should be reset")
	assert_false(comp._fire_valid, "fire_valid should be reset")
	assert_eq(comp._fire_duration, 0.0, "fire_duration should be reset")
	assert_eq(comp._suspicion_timer, 0.0, "suspicion_timer should be reset")


func test_reset_triggers_makes_all_triggers_false() -> void:
	# Set state so all triggers would fire
	comp._was_suppressed = true
	comp._hidden_timer = 10.0
	comp._approach_speed = 100.0
	comp._kills_witnessed = 5
	comp._heard_sound = true
	comp._sound_time = 99.0
	comp._mock_time = 100.0
	comp._fire_valid = true
	comp._fire_duration = 20.0
	comp._suspicion_timer = 5.0

	comp._reset_triggers()

	assert_false(comp._t1(), "T1 should be false after reset")
	# T2 depends on approach_speed which is not reset (it's recalculated each frame)
	assert_false(comp._t3(), "T3 should be false after reset")
	assert_false(comp._t4(false), "T4 should be false after reset")
	assert_false(comp._t5(), "T5 should be false after reset")
	assert_false(comp._t7(), "T7 should be false after reset")


func test_reset_triggers_does_not_affect_non_trigger_state() -> void:
	comp.grenades_remaining = 5
	comp._cooldown = 10.0
	comp._is_throwing = true
	comp._approach_speed = 75.0
	comp._kill_reset_timer = 20.0

	comp._reset_triggers()

	assert_eq(comp.grenades_remaining, 5,
		"_reset_triggers should not affect grenades_remaining")
	assert_eq(comp._cooldown, 10.0,
		"_reset_triggers should not affect _cooldown")
	assert_true(comp._is_throwing,
		"_reset_triggers should not affect _is_throwing")
	assert_eq(comp._approach_speed, 75.0,
		"_reset_triggers should not affect _approach_speed")
	assert_eq(comp._kill_reset_timer, 20.0,
		"_reset_triggers should not affect _kill_reset_timer")


# ============================================================================
# is_ready() After _reset_triggers() Tests
# ============================================================================


func test_is_ready_false_after_reset_triggers() -> void:
	# Activate a trigger
	comp._was_suppressed = true
	comp._hidden_timer = 10.0
	assert_true(comp.is_ready(false, false, 10), "Should be ready before reset")

	# Reset triggers
	comp._reset_triggers()

	assert_false(comp.is_ready(false, false, 10),
		"is_ready should return false after _reset_triggers with no external triggers")


func test_is_ready_still_works_via_t6_after_reset() -> void:
	comp._was_suppressed = true
	comp._hidden_timer = 10.0
	comp._reset_triggers()

	# T6 depends on health parameter, not internal state, so it still works
	assert_true(comp.is_ready(true, false, 1),
		"is_ready should still work via T6 (desperation) after reset since T6 is parameter-based")


# ============================================================================
# Edge Case and Integration Tests
# ============================================================================


func test_t4_does_not_trigger_when_can_see_even_with_valid_sound() -> void:
	comp._heard_sound = true
	comp._sound_time = 99.0
	comp._mock_time = 100.0

	# can_see is true, so T4 should not fire even though sound is valid
	assert_false(comp.is_ready(true, false, 10),
		"T4 should not trigger is_ready when enemy can see the player")


func test_t2_does_not_trigger_without_under_fire_even_with_speed() -> void:
	comp._approach_speed = 200.0

	# under_fire is false
	assert_false(comp.is_ready(true, false, 10),
		"T2 should not trigger is_ready when not under fire")


func test_single_grenade_allows_is_ready() -> void:
	comp.grenades_remaining = 1
	comp._was_suppressed = true
	comp._hidden_timer = 10.0

	assert_true(comp.is_ready(false, false, 10),
		"is_ready should work with exactly 1 grenade remaining")


func test_on_ally_died_then_t3_triggers_is_ready() -> void:
	comp.on_ally_died(Vector2(100, 100), true, true)
	comp.on_ally_died(Vector2(200, 200), true, true)

	assert_true(comp.is_ready(true, false, 10),
		"is_ready should trigger via T3 after witnessing 2 ally deaths")


func test_on_vulnerable_sound_then_t4_triggers_is_ready() -> void:
	comp._mock_time = 100.0
	comp.on_vulnerable_sound(Vector2(300, 300), false)

	assert_true(comp.is_ready(false, false, 10),
		"is_ready should trigger via T4 after hearing a vulnerable sound")


func test_on_vulnerable_sound_expired_does_not_trigger_is_ready() -> void:
	comp._mock_time = 100.0
	comp.on_vulnerable_sound(Vector2(300, 300), false)

	# Advance mock time past the validity window
	comp._mock_time = 106.0

	assert_false(comp.is_ready(false, false, 10),
		"is_ready should not trigger via T4 after sound expires")


func test_cooldown_negative_treated_as_ready() -> void:
	comp._cooldown = -1.0
	comp._was_suppressed = true
	comp._hidden_timer = 10.0

	# Negative cooldown is <= 0.0, so the guard _cooldown > 0.0 is false
	assert_true(comp.is_ready(false, false, 10),
		"Negative cooldown should not block is_ready (only > 0.0 blocks)")


func test_enabled_toggle_blocks_all_events() -> void:
	comp.enabled = false

	comp.on_ally_died(Vector2(100, 100), true, true)
	comp.on_vulnerable_sound(Vector2(300, 300), false)

	assert_eq(comp._kills_witnessed, 0,
		"on_ally_died should be blocked when disabled")
	assert_false(comp._heard_sound,
		"on_vulnerable_sound should be blocked when disabled")
	assert_false(comp.is_ready(false, true, 0),
		"is_ready should be blocked when disabled")


func test_zero_grenades_blocks_all_events() -> void:
	comp.grenades_remaining = 0

	comp.on_ally_died(Vector2(100, 100), true, true)
	comp.on_vulnerable_sound(Vector2(300, 300), false)

	assert_eq(comp._kills_witnessed, 0,
		"on_ally_died should be blocked when no grenades")
	assert_false(comp._heard_sound,
		"on_vulnerable_sound should be blocked when no grenades")
	assert_false(comp.is_ready(false, true, 0),
		"is_ready should be blocked when no grenades")


func test_add_grenades_enables_events_after_zero() -> void:
	comp.grenades_remaining = 0
	comp.on_ally_died(Vector2(100, 100), true, true)
	assert_eq(comp._kills_witnessed, 0, "Should be blocked at 0 grenades")

	comp.add_grenades(3)
	comp.on_ally_died(Vector2(100, 100), true, true)
	assert_eq(comp._kills_witnessed, 1,
		"on_ally_died should work after adding grenades")
