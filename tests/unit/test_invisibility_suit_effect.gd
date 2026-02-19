extends GutTest
## Unit tests for InvisibilitySuitEffect (Issue #673).
##
## Tests the invisibility suit effect core logic including:
## - Charge management (2 charges per battle)
## - Activation/deactivation timing (4 seconds duration)
## - Fade in/out transitions
## - Shader mix amount control
## - Signal emissions
## - State tracking


# ============================================================================
# Mock InvisibilitySuitEffect for Testing Core Logic
# ============================================================================


class MockInvisibilitySuitEffect:
	## Duration of invisibility effect in seconds.
	const EFFECT_DURATION: float = 4.0

	## Maximum charges per battle.
	const MAX_CHARGES: int = 2

	## Time for the cloak to fade in (seconds).
	const FADE_IN_TIME: float = 0.3

	## Time for the cloak to fade out (seconds).
	const FADE_OUT_TIME: float = 0.5

	## Current number of charges remaining.
	var charges: int = MAX_CHARGES

	## Whether the invisibility effect is currently active.
	var is_active: bool = false

	## Timer tracking remaining effect duration.
	var _effect_timer: float = 0.0

	## Current fade amount (0.0 = visible, 1.0 = fully cloaked).
	var _current_mix: float = 0.0

	## Whether we are currently fading in or out.
	var _is_fading_in: bool = false
	var _is_fading_out: bool = false

	## Signal tracking for tests.
	var activated_signals: Array = []
	var deactivated_signals: Array = []
	var charges_changed_signals: Array = []

	## Track shader applications.
	var shader_applied: bool = false
	var shader_removed: bool = false


	## Attempt to activate the invisibility effect.
	## Returns true if activation was successful.
	func activate() -> bool:
		if is_active:
			return false  # Already active

		if charges <= 0:
			return false

		# Consume a charge
		charges -= 1
		is_active = true
		_effect_timer = EFFECT_DURATION
		_is_fading_in = true
		_is_fading_out = false
		_current_mix = 0.0

		# Apply shader to all player sprites
		shader_applied = true

		activated_signals.append(charges)
		charges_changed_signals.append({"current": charges, "max": MAX_CHARGES})
		return true


	## Deactivate the invisibility effect (start fade out).
	func deactivate() -> void:
		if not is_active:
			return

		_is_fading_in = false
		_is_fading_out = true


	## Force-stop the invisibility effect immediately (no fade).
	func force_stop() -> void:
		is_active = false
		_is_fading_in = false
		_is_fading_out = false
		_current_mix = 0.0
		_effect_timer = 0.0
		shader_removed = true

		deactivated_signals.append(charges)


	## Process function simulating _process(delta).
	func process(delta: float) -> void:
		if not is_active and not _is_fading_out:
			return

		# Handle fade in
		if _is_fading_in:
			_current_mix = minf(_current_mix + delta / FADE_IN_TIME, 1.0)
			if _current_mix >= 1.0:
				_is_fading_in = false

		# Count down effect timer
		if is_active:
			_effect_timer -= delta
			if _effect_timer <= 0.0:
				deactivate()

		# Handle fade out
		if _is_fading_out:
			_current_mix = maxf(_current_mix - delta / FADE_OUT_TIME, 0.0)
			if _current_mix <= 0.0:
				_is_fading_out = false
				is_active = false
				shader_removed = true
				deactivated_signals.append(charges)


	## Check if the player is currently invisible to enemies.
	## Returns true during the active phase (including fade-in), false during fade-out.
	func is_invisible() -> bool:
		return is_active


	## Get the remaining effect time in seconds.
	func get_remaining_time() -> float:
		return _effect_timer if is_active else 0.0


	## Get the current number of charges.
	func get_charges() -> int:
		return charges


	## Get the current shader mix amount.
	func get_current_mix() -> float:
		return _current_mix


var effect: MockInvisibilitySuitEffect


func before_each() -> void:
	effect = MockInvisibilitySuitEffect.new()


func after_each() -> void:
	effect = null


# ============================================================================
# Constants Tests
# ============================================================================


func test_effect_duration_is_4_seconds() -> void:
	assert_eq(MockInvisibilitySuitEffect.EFFECT_DURATION, 4.0,
		"Effect duration should be 4 seconds")


func test_max_charges_is_2() -> void:
	assert_eq(MockInvisibilitySuitEffect.MAX_CHARGES, 2,
		"Max charges per battle should be 2")


func test_fade_in_time_is_0_3_seconds() -> void:
	assert_eq(MockInvisibilitySuitEffect.FADE_IN_TIME, 0.3,
		"Fade in time should be 0.3 seconds")


func test_fade_out_time_is_0_5_seconds() -> void:
	assert_eq(MockInvisibilitySuitEffect.FADE_OUT_TIME, 0.5,
		"Fade out time should be 0.5 seconds")


# ============================================================================
# Initial State Tests
# ============================================================================


func test_starts_with_full_charges() -> void:
	assert_eq(effect.get_charges(), 2,
		"Should start with 2 charges")


func test_starts_inactive() -> void:
	assert_false(effect.is_active,
		"Should start inactive")


func test_starts_visible() -> void:
	assert_false(effect.is_invisible(),
		"Should start visible (not invisible)")


func test_starts_with_zero_mix() -> void:
	assert_eq(effect.get_current_mix(), 0.0,
		"Should start with 0.0 shader mix (fully visible)")


func test_starts_not_fading() -> void:
	assert_false(effect._is_fading_in,
		"Should not be fading in initially")
	assert_false(effect._is_fading_out,
		"Should not be fading out initially")


# ============================================================================
# Activation Tests
# ============================================================================


func test_activate_consumes_charge() -> void:
	effect.activate()
	assert_eq(effect.get_charges(), 1,
		"Activation should consume one charge")


func test_activate_sets_active() -> void:
	effect.activate()
	assert_true(effect.is_active,
		"Should be active after activation")


func test_activate_makes_invisible() -> void:
	effect.activate()
	assert_true(effect.is_invisible(),
		"Should be invisible after activation")


func test_activate_sets_timer() -> void:
	effect.activate()
	assert_eq(effect.get_remaining_time(), 4.0,
		"Timer should be set to effect duration")


func test_activate_starts_fade_in() -> void:
	effect.activate()
	assert_true(effect._is_fading_in,
		"Should start fading in on activation")


func test_activate_returns_true_on_success() -> void:
	var result := effect.activate()
	assert_true(result, "activate() should return true on success")


func test_activate_emits_activated_signal() -> void:
	effect.activate()
	assert_eq(effect.activated_signals.size(), 1,
		"Should emit activated signal")
	assert_eq(effect.activated_signals[0], 1,
		"Signal should contain remaining charges (1)")


func test_activate_emits_charges_changed_signal() -> void:
	effect.activate()
	assert_eq(effect.charges_changed_signals.size(), 1,
		"Should emit charges changed signal")
	assert_eq(effect.charges_changed_signals[0]["current"], 1)
	assert_eq(effect.charges_changed_signals[0]["max"], 2)


func test_activate_applies_shader() -> void:
	effect.activate()
	assert_true(effect.shader_applied,
		"Shader should be applied on activation")


# ============================================================================
# Cannot Activate Tests
# ============================================================================


func test_cannot_activate_when_already_active() -> void:
	effect.activate()
	var result := effect.activate()
	assert_false(result, "Cannot activate when already active")
	assert_eq(effect.get_charges(), 1,
		"Should not consume extra charge")


func test_cannot_activate_with_zero_charges() -> void:
	effect.charges = 0
	var result := effect.activate()
	assert_false(result, "Cannot activate with zero charges")
	assert_false(effect.is_active, "Should remain inactive")


func test_cannot_activate_emits_no_signal() -> void:
	effect.activate()
	effect.activated_signals.clear()
	effect.activate()  # Try again while active
	assert_eq(effect.activated_signals.size(), 0,
		"Should not emit signal on failed activation")


# ============================================================================
# Effect Duration Tests
# ============================================================================


func test_timer_decreases_over_time() -> void:
	effect.activate()
	effect.process(1.0)
	assert_almost_eq(effect.get_remaining_time(), 3.0, 0.001,
		"Timer should decrease by delta")


func test_effect_ends_after_duration() -> void:
	effect.activate()
	effect.process(4.0)  # Process full duration
	assert_true(effect._is_fading_out,
		"Should start fading out after duration")


func test_still_invisible_during_active_phase() -> void:
	effect.activate()
	effect.process(2.0)  # Half duration
	assert_true(effect.is_invisible(),
		"Should remain invisible during active phase")


func test_still_invisible_at_end_of_duration() -> void:
	effect.activate()
	effect.process(3.9)  # Almost at end
	assert_true(effect.is_invisible(),
		"Should still be invisible just before duration ends")


# ============================================================================
# Fade In Tests
# ============================================================================


func test_mix_increases_during_fade_in() -> void:
	effect.activate()
	effect.process(0.1)  # 1/3 of fade in time
	assert_gt(effect.get_current_mix(), 0.0,
		"Mix should increase during fade in")
	assert_lt(effect.get_current_mix(), 1.0,
		"Mix should not reach 1.0 yet")


func test_fade_in_completes_at_fade_time() -> void:
	effect.activate()
	effect.process(0.3)  # Full fade in time
	assert_almost_eq(effect.get_current_mix(), 1.0, 0.001,
		"Mix should reach 1.0 after fade in time")


func test_fade_in_flag_cleared_after_complete() -> void:
	effect.activate()
	effect.process(0.3)
	assert_false(effect._is_fading_in,
		"Fading in flag should be cleared after completion")


func test_mix_clamped_at_one() -> void:
	effect.activate()
	effect.process(1.0)  # Well past fade in time
	assert_almost_eq(effect.get_current_mix(), 1.0, 0.001,
		"Mix should be clamped at 1.0")


# ============================================================================
# Fade Out Tests
# ============================================================================


func test_fade_out_starts_when_deactivated() -> void:
	effect.activate()
	effect.process(0.5)  # Let it fade in
	effect.deactivate()
	assert_true(effect._is_fading_out,
		"Should start fading out on deactivate")


func test_mix_decreases_during_fade_out() -> void:
	effect.activate()
	effect.process(1.0)  # Fully faded in
	effect.deactivate()
	var mix_before := effect.get_current_mix()
	effect.process(0.1)
	assert_lt(effect.get_current_mix(), mix_before,
		"Mix should decrease during fade out")


func test_fade_out_completes() -> void:
	effect.activate()
	effect.process(1.0)  # Fully faded in, mix = 1.0
	effect.deactivate()
	effect.process(0.5)  # Full fade out time
	assert_almost_eq(effect.get_current_mix(), 0.0, 0.001,
		"Mix should reach 0.0 after fade out")


func test_becomes_inactive_after_fade_out() -> void:
	effect.activate()
	effect.process(1.0)
	effect.deactivate()
	effect.process(0.5)
	assert_false(effect.is_active,
		"Should be inactive after fade out completes")


func test_shader_removed_after_fade_out() -> void:
	effect.activate()
	effect.process(1.0)
	effect.deactivate()
	effect.process(0.5)
	assert_true(effect.shader_removed,
		"Shader should be removed after fade out")


func test_deactivated_signal_after_fade_out() -> void:
	effect.activate()
	effect.process(1.0)
	effect.deactivate()
	effect.process(0.5)
	assert_eq(effect.deactivated_signals.size(), 1,
		"Should emit deactivated signal after fade out")


# ============================================================================
# Force Stop Tests
# ============================================================================


func test_force_stop_immediately_deactivates() -> void:
	effect.activate()
	effect.force_stop()
	assert_false(effect.is_active,
		"Should be immediately inactive after force stop")


func test_force_stop_resets_mix() -> void:
	effect.activate()
	effect.process(0.5)  # Build up mix
	effect.force_stop()
	assert_eq(effect.get_current_mix(), 0.0,
		"Mix should be reset to 0 on force stop")


func test_force_stop_clears_timer() -> void:
	effect.activate()
	effect.force_stop()
	assert_eq(effect.get_remaining_time(), 0.0,
		"Timer should be cleared on force stop")


func test_force_stop_emits_deactivated_signal() -> void:
	effect.activate()
	effect.force_stop()
	assert_eq(effect.deactivated_signals.size(), 1,
		"Should emit deactivated signal on force stop")


func test_force_stop_removes_shader() -> void:
	effect.activate()
	effect.force_stop()
	assert_true(effect.shader_removed,
		"Shader should be removed on force stop")


# ============================================================================
# Multiple Charges Tests
# ============================================================================


func test_can_use_both_charges() -> void:
	# First use
	effect.activate()
	effect.force_stop()
	assert_eq(effect.get_charges(), 1)

	# Second use
	var result := effect.activate()
	assert_true(result, "Should be able to use second charge")
	assert_eq(effect.get_charges(), 0)


func test_cannot_use_third_charge() -> void:
	# Use both charges
	effect.activate()
	effect.force_stop()
	effect.activate()
	effect.force_stop()

	# Try third
	var result := effect.activate()
	assert_false(result, "Should not have third charge")


func test_charges_do_not_regenerate() -> void:
	effect.activate()
	effect.force_stop()
	# Simulate time passing
	effect.process(10.0)
	assert_eq(effect.get_charges(), 1,
		"Charges should not regenerate over time")


# ============================================================================
# Auto-Deactivate Tests
# ============================================================================


func test_auto_deactivates_after_full_duration() -> void:
	effect.activate()
	# Process through full duration + fade out
	effect.process(4.0)  # Timer expires
	effect.process(0.5)  # Fade out
	assert_false(effect.is_active,
		"Should auto-deactivate after duration")


func test_becomes_visible_after_auto_deactivate() -> void:
	effect.activate()
	effect.process(4.0)  # Timer expires
	effect.process(0.5)  # Fade out
	assert_false(effect.is_invisible(),
		"Should be visible after auto-deactivate completes")


# ============================================================================
# Edge Cases
# ============================================================================


func test_deactivate_does_nothing_when_inactive() -> void:
	effect.deactivate()
	assert_false(effect._is_fading_out,
		"Should not start fade out when already inactive")


func test_process_does_nothing_when_inactive() -> void:
	var initial_mix := effect.get_current_mix()
	effect.process(1.0)
	assert_eq(effect.get_current_mix(), initial_mix,
		"Process should not change mix when inactive")


func test_rapid_activate_deactivate() -> void:
	effect.activate()
	effect.deactivate()
	# Should be fading out, but still counts as "active" until complete
	assert_true(effect._is_fading_out)


func test_reactivate_after_fade_out() -> void:
	effect.activate()
	effect.force_stop()
	# Should be able to activate again
	var result := effect.activate()
	assert_true(result, "Should be able to reactivate after force stop")


# ============================================================================
# Integration-Style Tests
# ============================================================================


func test_full_effect_cycle() -> void:
	# Start
	assert_eq(effect.get_charges(), 2)
	assert_false(effect.is_invisible())

	# Activate
	effect.activate()
	assert_eq(effect.get_charges(), 1)
	assert_true(effect.is_invisible())

	# Fade in
	effect.process(0.3)
	assert_almost_eq(effect.get_current_mix(), 1.0, 0.01)

	# Duration
	effect.process(3.7)  # Total time now 4.0, timer expires
	assert_true(effect._is_fading_out)

	# Fade out
	effect.process(0.5)
	assert_false(effect.is_active)
	assert_false(effect.is_invisible())
	assert_almost_eq(effect.get_current_mix(), 0.0, 0.01)


func test_two_full_cycles() -> void:
	# First cycle
	effect.activate()
	effect.process(4.5)  # Full duration + fade out
	assert_eq(effect.get_charges(), 1)
	assert_false(effect.is_invisible())

	# Second cycle
	effect.activate()
	effect.process(4.5)
	assert_eq(effect.get_charges(), 0)
	assert_false(effect.is_invisible())

	# Third attempt fails
	var result := effect.activate()
	assert_false(result)


# ============================================================================
# ActiveItemManager Integration Tests
# ============================================================================


class MockActiveItemManagerWithInvisibility:
	const ActiveItemType := {
		NONE = 0,
		FLASHLIGHT = 1,
		HOMING_BULLETS = 2,
		TELEPORT_BRACERS = 3,
		INVISIBILITY_SUIT = 4,
		BREAKER_BULLETS = 5
	}

	var current_active_item: int = ActiveItemType.NONE

	func has_invisibility_suit() -> bool:
		return current_active_item == ActiveItemType.INVISIBILITY_SUIT

	func set_active_item(type: int) -> void:
		current_active_item = type


func test_invisibility_suit_type_value() -> void:
	var manager := MockActiveItemManagerWithInvisibility.new()
	assert_eq(manager.ActiveItemType.INVISIBILITY_SUIT, 4,
		"INVISIBILITY_SUIT should be type 4")


func test_has_invisibility_suit_default_false() -> void:
	var manager := MockActiveItemManagerWithInvisibility.new()
	assert_false(manager.has_invisibility_suit(),
		"Should not have invisibility suit by default")


func test_has_invisibility_suit_after_selection() -> void:
	var manager := MockActiveItemManagerWithInvisibility.new()
	manager.set_active_item(4)
	assert_true(manager.has_invisibility_suit(),
		"Should have invisibility suit after selecting it")


func test_invisibility_mutually_exclusive_with_flashlight() -> void:
	var manager := MockActiveItemManagerWithInvisibility.new()
	manager.set_active_item(4)  # Invisibility
	manager.set_active_item(1)  # Flashlight
	assert_false(manager.has_invisibility_suit(),
		"Should not have invisibility after selecting flashlight")
