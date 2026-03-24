extends GutTest
## Tests for FlashbangStatusComponent (Issue #328).
##
## Validates blinded/stunned state transitions, timer countdown for
## both effects, and apply_flashbang_effect behaviour.

const FlashbangStatus := preload("res://scripts/components/flashbang_status_component.gd")


# =============================================================================
# Initial State
# =============================================================================

func test_initial_state_not_blinded() -> void:
	var comp := FlashbangStatus.new()
	add_child_autofree(comp)

	assert_false(comp.is_blinded(), "Should not be blinded initially")


func test_initial_state_not_stunned() -> void:
	var comp := FlashbangStatus.new()
	add_child_autofree(comp)

	assert_false(comp.is_stunned(), "Should not be stunned initially")


func test_initial_timers_zero() -> void:
	var comp := FlashbangStatus.new()
	add_child_autofree(comp)

	assert_eq(comp._blindness_timer, 0.0, "Blindness timer should start at 0.0")
	assert_eq(comp._stun_timer, 0.0, "Stun timer should start at 0.0")


# =============================================================================
# Blinded State Transitions
# =============================================================================

func test_set_blinded_true() -> void:
	var comp := FlashbangStatus.new()
	add_child_autofree(comp)

	comp.set_blinded(true)
	assert_true(comp.is_blinded(), "Should be blinded after set_blinded(true)")


func test_set_blinded_false() -> void:
	var comp := FlashbangStatus.new()
	add_child_autofree(comp)

	comp.set_blinded(true)
	comp.set_blinded(false)
	assert_false(comp.is_blinded(), "Should not be blinded after set_blinded(false)")


func test_blinded_changed_signal_emitted_on_blind() -> void:
	var comp := FlashbangStatus.new()
	add_child_autofree(comp)

	watch_signals(comp)
	comp.set_blinded(true)
	assert_signal_emitted(comp, "blinded_changed")


func test_blinded_changed_signal_emitted_on_unblind() -> void:
	var comp := FlashbangStatus.new()
	add_child_autofree(comp)

	comp.set_blinded(true)
	watch_signals(comp)
	comp.set_blinded(false)
	assert_signal_emitted(comp, "blinded_changed")


func test_blinded_changed_signal_not_emitted_when_already_blinded() -> void:
	var comp := FlashbangStatus.new()
	add_child_autofree(comp)

	comp.set_blinded(true)
	watch_signals(comp)
	comp.set_blinded(true)  # No change
	assert_signal_not_emitted(comp, "blinded_changed")


# =============================================================================
# Stunned State Transitions
# =============================================================================

func test_set_stunned_true() -> void:
	var comp := FlashbangStatus.new()
	add_child_autofree(comp)

	comp.set_stunned(true)
	assert_true(comp.is_stunned(), "Should be stunned after set_stunned(true)")


func test_set_stunned_false() -> void:
	var comp := FlashbangStatus.new()
	add_child_autofree(comp)

	comp.set_stunned(true)
	comp.set_stunned(false)
	assert_false(comp.is_stunned(), "Should not be stunned after set_stunned(false)")


func test_stunned_changed_signal_emitted_on_stun() -> void:
	var comp := FlashbangStatus.new()
	add_child_autofree(comp)

	watch_signals(comp)
	comp.set_stunned(true)
	assert_signal_emitted(comp, "stunned_changed")


func test_stunned_changed_signal_emitted_on_unstun() -> void:
	var comp := FlashbangStatus.new()
	add_child_autofree(comp)

	comp.set_stunned(true)
	watch_signals(comp)
	comp.set_stunned(false)
	assert_signal_emitted(comp, "stunned_changed")


func test_stunned_changed_signal_not_emitted_when_already_stunned() -> void:
	var comp := FlashbangStatus.new()
	add_child_autofree(comp)

	comp.set_stunned(true)
	watch_signals(comp)
	comp.set_stunned(true)  # No change
	assert_signal_not_emitted(comp, "stunned_changed")


# =============================================================================
# Timer Countdown
# =============================================================================

func test_blindness_timer_counts_down() -> void:
	var comp := FlashbangStatus.new()
	add_child_autofree(comp)

	comp._blindness_timer = 3.0
	comp._is_blinded = true
	comp.update(1.0)

	assert_almost_eq(comp._blindness_timer, 2.0, 0.01,
		"Blindness timer should decrement by delta")
	assert_true(comp.is_blinded(), "Should still be blinded with remaining time")


func test_stun_timer_counts_down() -> void:
	var comp := FlashbangStatus.new()
	add_child_autofree(comp)

	comp._stun_timer = 3.0
	comp._is_stunned = true
	comp.update(1.0)

	assert_almost_eq(comp._stun_timer, 2.0, 0.01,
		"Stun timer should decrement by delta")
	assert_true(comp.is_stunned(), "Should still be stunned with remaining time")


func test_blindness_timer_expires_removes_blind() -> void:
	var comp := FlashbangStatus.new()
	add_child_autofree(comp)

	comp._blindness_timer = 0.5
	comp._is_blinded = true
	comp.update(1.0)

	assert_eq(comp._blindness_timer, 0.0, "Blindness timer should be clamped to 0.0")
	assert_false(comp.is_blinded(), "Should not be blinded after timer expires")


func test_stun_timer_expires_removes_stun() -> void:
	var comp := FlashbangStatus.new()
	add_child_autofree(comp)

	comp._stun_timer = 0.5
	comp._is_stunned = true
	comp.update(1.0)

	assert_eq(comp._stun_timer, 0.0, "Stun timer should be clamped to 0.0")
	assert_false(comp.is_stunned(), "Should not be stunned after timer expires")


func test_update_does_nothing_when_timers_zero() -> void:
	var comp := FlashbangStatus.new()
	add_child_autofree(comp)

	comp.update(1.0)

	assert_false(comp.is_blinded(), "Should not be blinded")
	assert_false(comp.is_stunned(), "Should not be stunned")
	assert_eq(comp._blindness_timer, 0.0, "Blindness timer should remain 0")
	assert_eq(comp._stun_timer, 0.0, "Stun timer should remain 0")


# =============================================================================
# apply_flashbang_effect
# =============================================================================

func test_apply_flashbang_effect_sets_both_timers() -> void:
	var comp := FlashbangStatus.new()
	add_child_autofree(comp)

	comp.apply_flashbang_effect(3.0, 2.0)

	assert_eq(comp._blindness_timer, 3.0, "Blindness timer should be 3.0")
	assert_eq(comp._stun_timer, 2.0, "Stun timer should be 2.0")
	assert_true(comp.is_blinded(), "Should be blinded after apply")
	assert_true(comp.is_stunned(), "Should be stunned after apply")


func test_apply_flashbang_effect_takes_max_duration() -> void:
	var comp := FlashbangStatus.new()
	add_child_autofree(comp)

	comp._blindness_timer = 5.0
	comp._is_blinded = true
	comp.apply_flashbang_effect(3.0, 2.0)

	assert_eq(comp._blindness_timer, 5.0,
		"Should keep the larger existing blindness timer")
	assert_eq(comp._stun_timer, 2.0,
		"Stun timer should be set to the new value when larger")


func test_apply_flashbang_effect_zero_durations_ignored() -> void:
	var comp := FlashbangStatus.new()
	add_child_autofree(comp)

	comp.apply_flashbang_effect(0.0, 0.0)

	assert_false(comp.is_blinded(), "Should not be blinded with 0 duration")
	assert_false(comp.is_stunned(), "Should not be stunned with 0 duration")


func test_apply_flashbang_effect_only_blind() -> void:
	var comp := FlashbangStatus.new()
	add_child_autofree(comp)

	comp.apply_flashbang_effect(2.0, 0.0)

	assert_true(comp.is_blinded(), "Should be blinded")
	assert_false(comp.is_stunned(), "Should not be stunned with 0 stun duration")


func test_apply_flashbang_effect_only_stun() -> void:
	var comp := FlashbangStatus.new()
	add_child_autofree(comp)

	comp.apply_flashbang_effect(0.0, 2.0)

	assert_false(comp.is_blinded(), "Should not be blinded with 0 blind duration")
	assert_true(comp.is_stunned(), "Should be stunned")
