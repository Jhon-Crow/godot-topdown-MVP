extends GutTest
## Unit tests for LoudspeakerProgress (Issue #959).
##
## Tests loudspeaker level progression, charge management, cooldown,
## effect/hostility chances, and persistence (to/from_dict).
## All tests run without a Godot scene tree using the real LoudspeakerProgress class.


var progress: LoudspeakerProgress


func before_each() -> void:
	progress = LoudspeakerProgress.new()


func after_each() -> void:
	progress = null


# ============================================================================
# Default Values
# ============================================================================


func test_default_level_is_one() -> void:
	assert_eq(progress.current_level, 1,
		"Loudspeaker should start at level 1")


func test_default_charges_are_two() -> void:
	assert_eq(progress.charges_remaining, 2,
		"Level 1 should start with 2 charges")


func test_default_used_this_level_is_false() -> void:
	assert_false(progress.used_this_level,
		"used_this_level should be false at start")


func test_default_levels_completed_is_zero() -> void:
	assert_eq(progress.levels_completed_with_loudspeaker, 0,
		"No levels completed at start")


# ============================================================================
# Charge Management
# ============================================================================


func test_max_charges_level1_is_two() -> void:
	assert_eq(progress.get_max_charges(), 2,
		"Level 1 should have 2 max charges")


func test_max_charges_level2_is_three() -> void:
	progress.current_level = 2
	assert_eq(progress.get_max_charges(), 3,
		"Level 2 should have 3 max charges")


func test_max_charges_level3_is_six() -> void:
	progress.current_level = 3
	assert_eq(progress.get_max_charges(), 6,
		"Level 3 should have 6 max charges")


func test_max_charges_level4_is_unlimited() -> void:
	progress.current_level = 4
	assert_eq(progress.get_max_charges(), -1,
		"Level 4+ should have unlimited charges (-1)")


func test_use_decrements_charges() -> void:
	progress.use()
	assert_eq(progress.charges_remaining, 1,
		"Using loudspeaker at level 1 should consume 1 charge")


func test_cannot_activate_with_zero_charges() -> void:
	progress.charges_remaining = 0
	assert_false(progress.can_activate(),
		"Cannot activate with 0 charges")


func test_can_activate_with_charges_remaining() -> void:
	assert_true(progress.can_activate(),
		"Can activate when charges remain")


func test_use_sets_used_this_level() -> void:
	progress.use()
	assert_true(progress.used_this_level,
		"used_this_level should be true after first use")


func test_first_use_emits_signal() -> void:
	watch_signals(progress)
	progress.use()
	assert_signal_emitted(progress, "first_use_triggered",
		"first_use_triggered should be emitted on first use")


func test_subsequent_use_does_not_emit_first_use_signal() -> void:
	progress.use()
	watch_signals(progress)
	progress.use()
	assert_signal_not_emitted(progress, "first_use_triggered",
		"first_use_triggered should NOT be emitted on second use")


# ============================================================================
# Cooldown (Level 4+)
# ============================================================================


func test_cooldown_level4_is_two_seconds() -> void:
	progress.current_level = 4
	assert_eq(progress.get_cooldown_duration(), 2.0,
		"Level 4 cooldown should be 2 seconds")


func test_cooldown_level5_is_half_second() -> void:
	progress.current_level = 5
	assert_eq(progress.get_cooldown_duration(), 0.5,
		"Level 5 cooldown should be 0.5 seconds")


func test_cooldown_level1_is_zero() -> void:
	assert_eq(progress.get_cooldown_duration(), 0.0,
		"Level 1 has no cooldown (uses charges)")


func test_level4_use_starts_cooldown() -> void:
	progress.current_level = 4
	progress.charges_remaining = -1
	progress.use()
	assert_gt(progress.cooldown_timer, 0.0,
		"Using at level 4 should start the cooldown timer")


func test_cannot_activate_during_cooldown() -> void:
	progress.current_level = 4
	progress.cooldown_timer = 1.5
	assert_false(progress.can_activate(),
		"Cannot activate while cooldown timer > 0")


func test_cooldown_decrements_with_update() -> void:
	progress.cooldown_timer = 1.0
	progress.update(0.5)
	assert_almost_eq(progress.cooldown_timer, 0.5, 0.001,
		"Cooldown should decrease by delta each update")


func test_cooldown_clamps_to_zero() -> void:
	progress.cooldown_timer = 0.3
	progress.update(1.0)
	assert_eq(progress.cooldown_timer, 0.0,
		"Cooldown should not go below 0")


# ============================================================================
# Effect Chance
# ============================================================================


func test_effect_chance_level1_is_two_percent() -> void:
	assert_almost_eq(progress.get_effect_chance(), 0.02, 0.001,
		"Level 1 effect chance should be 2%")


func test_effect_chance_level2_is_five_percent() -> void:
	progress.current_level = 2
	assert_almost_eq(progress.get_effect_chance(), 0.05, 0.001,
		"Level 2 effect chance should be 5%")


func test_effect_chance_level3_is_seven_percent() -> void:
	progress.current_level = 3
	assert_almost_eq(progress.get_effect_chance(), 0.07, 0.001,
		"Level 3 effect chance should be 7%")


func test_effect_chance_level5_is_eleven_percent() -> void:
	progress.current_level = 5
	assert_almost_eq(progress.get_effect_chance(), 0.11, 0.001,
		"Level 5 effect chance should be 11%")


func test_effect_chance_level6_is_ninety_percent() -> void:
	progress.current_level = 6
	assert_almost_eq(progress.get_effect_chance(), 0.90, 0.001,
		"Level 6 effect chance should be 90%")


# ============================================================================
# Hostility Chance
# ============================================================================


func test_hostility_level1_is_fifty_percent() -> void:
	assert_almost_eq(progress.get_hostility_chance(), 0.50, 0.001,
		"Level 1 hostility should be 50%")


func test_hostility_level3_is_forty_percent() -> void:
	progress.current_level = 3
	assert_almost_eq(progress.get_hostility_chance(), 0.40, 0.001,
		"Level 3 hostility should be 40%")


func test_hostility_level4_is_twenty_percent() -> void:
	progress.current_level = 4
	assert_almost_eq(progress.get_hostility_chance(), 0.20, 0.001,
		"Level 4 hostility should be 20%")


func test_hostility_level5_is_zero() -> void:
	progress.current_level = 5
	assert_almost_eq(progress.get_hostility_chance(), 0.0, 0.001,
		"Level 5+ hostility should be 0%")


# ============================================================================
# Level Progression
# ============================================================================


## Helper: simulate completing a level with all charges used.
func _complete_level_full(had_kills: bool) -> void:
	progress.all_charges_used_this_level = true
	progress.on_level_completed(had_kills)
	progress.reset_for_new_level()


func test_complete_one_level_with_kills_advances_to_level2() -> void:
	watch_signals(progress)
	_complete_level_full(true)
	assert_eq(progress.current_level, 2,
		"Completing 1 level (all charges used) with kills should advance to level 2")
	assert_signal_emitted(progress, "level_changed")


func test_level_does_not_advance_without_all_charges_used() -> void:
	# Do NOT set all_charges_used_this_level
	progress.on_level_completed(true)
	assert_eq(progress.current_level, 1,
		"Level should NOT advance if not all charges were used")


func test_complete_two_levels_advances_to_level3() -> void:
	_complete_level_full(true)
	_complete_level_full(true)
	assert_eq(progress.current_level, 3,
		"Completing 2 levels (all charges used each time) should advance to level 3")


func test_complete_three_levels_advances_to_level4() -> void:
	_complete_level_full(true)
	_complete_level_full(true)
	_complete_level_full(true)
	assert_eq(progress.current_level, 4,
		"Completing 3 levels should advance to level 4")


func test_completing_level_without_kills_unlocks_level6() -> void:
	# First reach level 5 (need 4 completed levels)
	_complete_level_full(true)
	_complete_level_full(true)
	_complete_level_full(true)
	_complete_level_full(true)
	assert_eq(progress.current_level, 5)
	# Now complete a level without kills (all charges used)
	_complete_level_full(false)
	assert_eq(progress.current_level, 6,
		"Completing a level without kills (all charges used) should trigger level 6")


func test_pacifist_level_jumps_to_6_directly() -> void:
	# Even at level 1, completing pacifist (all charges used) advances to 6
	_complete_level_full(false)
	assert_eq(progress.current_level, 6,
		"Completing any level without kills (all charges used) should jump to level 6")


func test_killing_immune_enemy_advances_to_level7() -> void:
	progress.on_immune_enemy_killed()
	assert_eq(progress.current_level, 7,
		"Killing immune enemy should advance to level 7")


func test_level_capped_at_5_via_normal_completion() -> void:
	# Complete 10 levels — should cap at 5 (not 6), since no pacifist run
	for i in range(10):
		_complete_level_full(true)
	assert_eq(progress.current_level, 5,
		"Normal completion path caps at level 5")


func test_level_changed_signal_emitted_on_advancement() -> void:
	watch_signals(progress)
	_complete_level_full(true)
	assert_signal_emitted(progress, "level_changed",
		"level_changed signal should fire when level increases")


func test_level_changed_signal_not_emitted_when_no_change() -> void:
	# Complete multiple levels that don't change level (already at max normal)
	progress.current_level = 5
	progress.levels_completed_with_loudspeaker = 10
	watch_signals(progress)
	# Call with all_charges_used = true (so on_level_completed runs), but level is already at max
	progress.all_charges_used_this_level = true
	progress.on_level_completed(true)
	assert_signal_not_emitted(progress, "level_changed",
		"level_changed should not fire when level stays the same")


# ============================================================================
# Reset for New Level
# ============================================================================


func test_reset_for_new_level_restores_charges() -> void:
	progress.charges_remaining = 0
	progress.reset_for_new_level()
	assert_eq(progress.charges_remaining, 2,
		"reset_for_new_level should restore charges to max for level 1")


func test_reset_for_new_level_clears_used_this_level() -> void:
	progress.used_this_level = true
	progress.reset_for_new_level()
	assert_false(progress.used_this_level,
		"reset_for_new_level should reset used_this_level to false")


func test_reset_for_new_level_clears_cooldown() -> void:
	progress.cooldown_timer = 2.0
	progress.reset_for_new_level()
	assert_eq(progress.cooldown_timer, 0.0,
		"reset_for_new_level should clear the cooldown timer")


func test_reset_does_not_change_current_level() -> void:
	progress.on_level_completed(true)
	var level_before: int = progress.current_level
	progress.reset_for_new_level()
	assert_eq(progress.current_level, level_before,
		"reset_for_new_level should NOT reset the progression level")


# reset_for_respawn: only resets charges/cooldown/all_charges_used, NOT used_this_level
func test_reset_for_respawn_restores_charges() -> void:
	progress.charges_remaining = 0
	progress.reset_for_respawn()
	assert_eq(progress.charges_remaining, 2,
		"reset_for_respawn should restore charges to max for level 1")


func test_reset_for_respawn_preserves_used_this_level() -> void:
	progress.used_this_level = true
	progress.reset_for_respawn()
	assert_true(progress.used_this_level,
		"reset_for_respawn should NOT reset used_this_level — persists across deaths")


func test_reset_for_respawn_clears_all_charges_used() -> void:
	progress.all_charges_used_this_level = true
	progress.reset_for_respawn()
	assert_false(progress.all_charges_used_this_level,
		"reset_for_respawn should reset all_charges_used_this_level")


func test_reset_for_respawn_clears_cooldown() -> void:
	progress.cooldown_timer = 2.0
	progress.reset_for_respawn()
	assert_eq(progress.cooldown_timer, 0.0,
		"reset_for_respawn should clear the cooldown timer")


# ============================================================================
# Persistence (to_dict / from_dict)
# ============================================================================


func test_to_dict_contains_expected_keys() -> void:
	var data: Dictionary = progress.to_dict()
	assert_has(data, "current_level", "to_dict should contain 'current_level'")
	assert_has(data, "levels_completed", "to_dict should contain 'levels_completed'")
	assert_has(data, "pacifist_level_completed", "to_dict should contain 'pacifist_level_completed'")
	assert_has(data, "immune_enemy_killed", "to_dict should contain 'immune_enemy_killed'")


func test_from_dict_restores_level() -> void:
	var other := LoudspeakerProgress.new()
	_complete_level_full(true)
	_complete_level_full(true)
	var data: Dictionary = progress.to_dict()
	other.from_dict(data)
	assert_eq(other.current_level, progress.current_level,
		"from_dict should restore the current level")


func test_from_dict_restores_levels_completed() -> void:
	var other := LoudspeakerProgress.new()
	_complete_level_full(true)
	_complete_level_full(true)
	_complete_level_full(true)
	var data: Dictionary = progress.to_dict()
	other.from_dict(data)
	assert_eq(other.levels_completed_with_loudspeaker, 3,
		"from_dict should restore levels_completed_with_loudspeaker")


func test_from_dict_restores_pacifist_flag() -> void:
	var other := LoudspeakerProgress.new()
	_complete_level_full(false)  # No kills — pacifist run
	var data: Dictionary = progress.to_dict()
	other.from_dict(data)
	assert_true(other.has_completed_pacifist_level,
		"from_dict should restore has_completed_pacifist_level")


func test_from_dict_restores_immune_enemy_flag() -> void:
	var other := LoudspeakerProgress.new()
	progress.on_immune_enemy_killed()
	var data: Dictionary = progress.to_dict()
	other.from_dict(data)
	assert_true(other.has_killed_immune_enemy,
		"from_dict should restore has_killed_immune_enemy")


func test_from_dict_with_empty_dict_uses_defaults() -> void:
	progress.from_dict({})
	assert_eq(progress.current_level, 1,
		"from_dict with empty dict should default to level 1")


# ============================================================================
# Special Level Features
# ============================================================================


func test_pacifism_spreads_at_level5() -> void:
	progress.current_level = 5
	assert_true(progress.can_pacifism_spread(),
		"Pacifism should spread at level 5")


func test_pacifism_does_not_spread_at_level4() -> void:
	progress.current_level = 4
	assert_false(progress.can_pacifism_spread(),
		"Pacifism should not spread below level 5")


func test_should_start_with_pacifists_at_level6() -> void:
	progress.current_level = 6
	assert_true(progress.should_start_with_pacifists(),
		"Level 6 should start with 50% pacifists")


func test_should_not_start_with_pacifists_at_level5() -> void:
	progress.current_level = 5
	assert_false(progress.should_start_with_pacifists(),
		"Level 5 should NOT start with pacifists")


func test_victory_state_at_level7() -> void:
	progress.current_level = 7
	assert_true(progress.is_victory_state(),
		"Level 7 is the victory state")


func test_immune_enemy_only_at_level6() -> void:
	progress.current_level = 6
	assert_true(progress.has_immune_enemy(),
		"Level 6 should have one immune enemy")


func test_no_immune_enemy_at_level5() -> void:
	progress.current_level = 5
	assert_false(progress.has_immune_enemy(),
		"Level 5 should not have an immune enemy")


func test_no_immune_enemy_at_level7() -> void:
	progress.current_level = 7
	assert_false(progress.has_immune_enemy(),
		"Level 7 should not have an immune enemy (already killed)")


# ============================================================================
# All Charges Used Gate
# ============================================================================


func test_all_charges_used_set_on_last_charge() -> void:
	progress.use()  # 1 of 2 used
	assert_false(progress.all_charges_used_this_level,
		"all_charges_used should be false after 1 of 2 charges used")
	progress.use()  # 2 of 2 used
	assert_true(progress.all_charges_used_this_level,
		"all_charges_used should be true after all charges used")


func test_level_does_not_advance_if_charges_not_exhausted() -> void:
	# Only use 1 of 2 charges, then complete level
	progress.use()
	progress.on_level_completed(true)
	assert_eq(progress.current_level, 1,
		"Level should NOT advance if player didn't exhaust all charges")


func test_all_charges_used_resets_on_respawn() -> void:
	progress.all_charges_used_this_level = true
	progress.reset_for_respawn()
	assert_false(progress.all_charges_used_this_level,
		"reset_for_respawn should clear all_charges_used (new run required)")


func test_level4_unlimited_counts_as_all_used_after_first_activation() -> void:
	progress.current_level = 4
	progress.charges_remaining = -1
	progress.use()
	assert_true(progress.all_charges_used_this_level,
		"Unlimited level: all_charges_used should be true after any activation")
