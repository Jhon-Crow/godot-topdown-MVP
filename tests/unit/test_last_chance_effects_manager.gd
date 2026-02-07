extends GutTest
## Unit tests for LastChanceEffectsManager autoload.
##
## Tests the last chance time-freeze effect that triggers on hard difficulty
## when the player is about to die. Covers trigger conditions, effect lifecycle,
## grenade vs threat triggers, player death handling, helper functions,
## color saturation math, and comprehensive reset behavior.


# ============================================================================
# Mock DifficultyManager for Hard Mode Checks
# ============================================================================


class MockDifficultyManager:
	## Whether the game is in hard mode.
	var _is_hard_mode: bool = false

	func is_hard_mode() -> bool:
		return _is_hard_mode

	func set_hard_mode(enabled: bool) -> void:
		_is_hard_mode = enabled


# ============================================================================
# Mock Node for Tree Helper Tests
# ============================================================================


class MockNode:
	## Parent node reference (null for root).
	var _parent: MockNode = null

	## Child nodes.
	var _children: Array = []

	## Node name for identification.
	var name: String = ""

	func _init(node_name: String = "") -> void:
		name = node_name

	func get_parent() -> MockNode:
		return _parent

	func get_children() -> Array:
		return _children

	func add_child(child: MockNode) -> void:
		child._parent = self
		_children.append(child)


# ============================================================================
# Mock LastChanceEffectsManager for Logic Tests
# ============================================================================


class MockLastChanceEffectsManager:
	## Duration of the time freeze in real seconds.
	const FREEZE_DURATION_REAL_SECONDS: float = 6.0

	## Blue sepia intensity for the shader (0.0-1.0).
	const SEPIA_INTENSITY: float = 0.7

	## Brightness reduction for non-player elements (0.0-1.0, where 1.0 is normal).
	const BRIGHTNESS: float = 0.6

	## Ripple effect strength.
	const RIPPLE_STRENGTH: float = 0.008

	## Ripple effect frequency.
	const RIPPLE_FREQUENCY: float = 25.0

	## Ripple effect speed.
	const RIPPLE_SPEED: float = 2.0

	## Duration of the fade-out animation in seconds (Issue #442).
	const FADE_OUT_DURATION_SECONDS: float = 0.4

	## Player saturation multiplier during last chance.
	const PLAYER_SATURATION_MULTIPLIER: float = 4.0

	## Distance to push threatening bullets away from player (in pixels).
	const BULLET_PUSH_DISTANCE: float = 200.0

	## Whether the last chance effect is currently active.
	var _is_effect_active: bool = false

	## Whether the last chance effect has already been used this life.
	var _effect_used: bool = false

	## Whether this is a grenade-triggered effect.
	var _is_grenade_triggered: bool = false

	## Current effect duration in real seconds.
	var _current_effect_duration: float = FREEZE_DURATION_REAL_SECONDS

	## Whether the visual effects are currently fading out.
	var _is_fading_out: bool = false

	## Cached player health from signals.
	var _player_current_health: float = 0.0

	## Whether we have connected to player signals.
	var _connected_to_player: bool = false

	## Reference to a mock difficulty manager for trigger checks.
	var _difficulty_manager: MockDifficultyManager = null

	## Whether a player reference is set (simulates _player != null).
	var _has_player: bool = false

	## Frozen arrays for tracking frozen objects.
	var _frozen_player_bullets: Array = []
	var _frozen_grenades: Array = []
	var _frozen_casings: Array = []
	var _frozen_shrapnel: Array = []
	var _frozen_explosion_effects: Array = []
	var _frozen_explosion_visuals: Array = []

	## Original process modes dictionary.
	var _original_process_modes: Dictionary = {}

	## Player original colors dictionary.
	var _player_original_colors: Dictionary = {}

	## Whether player was invulnerable before effect.
	var _player_was_invulnerable: bool = false

	## Tracking calls for verification.
	var _freeze_time_called: bool = false
	var _unfreeze_time_called: bool = false
	var _fade_out_started: bool = false
	var _visual_effects_applied: bool = false
	var _visual_effects_removed: bool = false
	var _push_bullets_called: bool = false
	var _grant_invulnerability_called: bool = false
	var _reset_enemy_memory_called: bool = false

	## Check if the last chance effect can be triggered.
	## Mirrors the logic from the real _can_trigger_effect().
	func can_trigger_effect() -> bool:
		# Effect already used this life?
		if _effect_used:
			return false

		# Effect already active?
		if _is_effect_active:
			return false

		# Only trigger in hard mode
		if _difficulty_manager == null:
			return false

		if not _difficulty_manager.is_hard_mode():
			return false

		# Check player exists
		if not _has_player:
			return false

		# Check player health (1 HP or less but alive)
		if _player_current_health > 1.0 or _player_current_health <= 0.0:
			return false

		return true

	## Start the last chance effect.
	## Mirrors the logic from the real _start_last_chance_effect().
	func start_last_chance_effect(duration_seconds: float = FREEZE_DURATION_REAL_SECONDS, is_grenade: bool = false) -> void:
		if _is_effect_active:
			return

		_is_effect_active = true
		_is_grenade_triggered = is_grenade
		_current_effect_duration = duration_seconds
		if not is_grenade:
			_effect_used = true  # Mark as used (only triggers once per life, not for grenade)
			_push_bullets_called = true
			_grant_invulnerability_called = true

		_freeze_time_called = true
		_visual_effects_applied = true

	## End the last chance effect.
	## Mirrors the logic from the real _end_last_chance_effect().
	func end_last_chance_effect() -> void:
		if not _is_effect_active:
			return

		_is_effect_active = false
		_reset_enemy_memory_called = true
		_unfreeze_time_called = true
		_fade_out_started = true
		_is_fading_out = true

	## Trigger grenade last chance effect.
	## Mirrors the logic from the real trigger_grenade_last_chance().
	func trigger_grenade_last_chance(duration_seconds: float) -> void:
		if _is_effect_active:
			return

		if not _has_player:
			return

		start_last_chance_effect(duration_seconds, true)

	## Handle player death.
	## Mirrors the logic from the real _on_player_died().
	func on_player_died() -> void:
		if _is_effect_active:
			end_last_chance_effect()
		# Reset effect usage on death so it can trigger again next life
		_effect_used = false

	## Saturate a color by a multiplier.
	## Mirrors the exact logic from the real _saturate_color().
	func saturate_color(color: Color, multiplier: float) -> Color:
		# Calculate luminance using standard weights
		var luminance := color.r * 0.299 + color.g * 0.587 + color.b * 0.114

		# Increase saturation by moving away from grayscale
		var saturated_r: float = lerp(luminance, color.r, multiplier)
		var saturated_g: float = lerp(luminance, color.g, multiplier)
		var saturated_b: float = lerp(luminance, color.b, multiplier)

		# Clamp to valid color range
		return Color(
			clampf(saturated_r, 0.0, 1.0),
			clampf(saturated_g, 0.0, 1.0),
			clampf(saturated_b, 0.0, 1.0),
			color.a
		)

	## Check if a node is a descendant of an ancestor.
	## Mirrors the exact logic from the real _is_descendant_of().
	func is_descendant_of(ancestor: MockNode, node: MockNode) -> bool:
		if ancestor == null or node == null:
			return false

		var parent := node.get_parent()
		while parent != null:
			if parent == ancestor:
				return true
			parent = parent.get_parent()

		return false

	## Count total number of descendant nodes.
	## Mirrors the exact logic from the real _count_descendants().
	func count_descendants(node: MockNode) -> int:
		var count := 0
		for child in node.get_children():
			count += 1 + count_descendants(child)
		return count

	## Reset all effects (comprehensive reset).
	## Mirrors the logic from the real reset_effects().
	func reset_effects() -> void:
		if _is_effect_active:
			_is_effect_active = false
			_unfreeze_time_called = true

		# Reset fade-out state (Issue #442)
		_is_fading_out = false

		# Always remove visual effects immediately on scene change (Issue #452)
		_visual_effects_removed = true

		_has_player = false
		_connected_to_player = false
		_effect_used = false
		_is_grenade_triggered = false
		_current_effect_duration = FREEZE_DURATION_REAL_SECONDS
		_player_current_health = 0.0
		_frozen_player_bullets.clear()
		_frozen_grenades.clear()
		_frozen_casings.clear()
		_frozen_shrapnel.clear()
		_frozen_explosion_effects.clear()
		_frozen_explosion_visuals.clear()
		_original_process_modes.clear()
		_player_original_colors.clear()
		_player_was_invulnerable = false

	## Returns whether the last chance effect is currently active.
	func is_effect_active() -> bool:
		return _is_effect_active

	## Returns whether the last chance effect has been used this life.
	func is_effect_used() -> bool:
		return _effect_used


var manager: MockLastChanceEffectsManager
var difficulty: MockDifficultyManager


func before_each() -> void:
	manager = MockLastChanceEffectsManager.new()
	difficulty = MockDifficultyManager.new()
	manager._difficulty_manager = difficulty


func after_each() -> void:
	manager = null
	difficulty = null


# ============================================================================
# Constants Tests
# ============================================================================


func test_freeze_duration_real_seconds_is_six() -> void:
	assert_eq(manager.FREEZE_DURATION_REAL_SECONDS, 6.0,
		"Freeze duration should be 6.0 real seconds")


func test_sepia_intensity_is_0_7() -> void:
	assert_eq(manager.SEPIA_INTENSITY, 0.7,
		"Sepia intensity should be 0.7")


func test_brightness_is_0_6() -> void:
	assert_eq(manager.BRIGHTNESS, 0.6,
		"Brightness should be 0.6")


func test_ripple_strength_is_0_008() -> void:
	assert_eq(manager.RIPPLE_STRENGTH, 0.008,
		"Ripple strength should be 0.008")


func test_ripple_frequency_is_25() -> void:
	assert_eq(manager.RIPPLE_FREQUENCY, 25.0,
		"Ripple frequency should be 25.0")


func test_ripple_speed_is_2() -> void:
	assert_eq(manager.RIPPLE_SPEED, 2.0,
		"Ripple speed should be 2.0")


func test_fade_out_duration_is_0_4() -> void:
	assert_eq(manager.FADE_OUT_DURATION_SECONDS, 0.4,
		"Fade-out duration should be 0.4 seconds")


func test_player_saturation_multiplier_is_4() -> void:
	assert_eq(manager.PLAYER_SATURATION_MULTIPLIER, 4.0,
		"Player saturation multiplier should be 4.0")


func test_bullet_push_distance_is_200() -> void:
	assert_eq(manager.BULLET_PUSH_DISTANCE, 200.0,
		"Bullet push distance should be 200.0 pixels")


# ============================================================================
# Initial State Tests
# ============================================================================


func test_initial_effect_not_active() -> void:
	assert_false(manager._is_effect_active,
		"Effect should not be active initially")


func test_initial_effect_not_used() -> void:
	assert_false(manager._effect_used,
		"Effect should not be used initially")


func test_initial_not_grenade_triggered() -> void:
	assert_false(manager._is_grenade_triggered,
		"Effect should not be grenade-triggered initially")


func test_initial_effect_duration_equals_freeze_duration() -> void:
	assert_eq(manager._current_effect_duration, 6.0,
		"Initial effect duration should equal FREEZE_DURATION_REAL_SECONDS")


func test_initial_not_fading_out() -> void:
	assert_false(manager._is_fading_out,
		"Should not be fading out initially")


func test_initial_player_health_zero() -> void:
	assert_eq(manager._player_current_health, 0.0,
		"Initial player health cache should be 0.0")


func test_initial_not_connected_to_player() -> void:
	assert_false(manager._connected_to_player,
		"Should not be connected to player initially")


func test_initial_frozen_arrays_empty() -> void:
	assert_eq(manager._frozen_player_bullets.size(), 0,
		"Frozen player bullets should be empty initially")
	assert_eq(manager._frozen_grenades.size(), 0,
		"Frozen grenades should be empty initially")
	assert_eq(manager._frozen_casings.size(), 0,
		"Frozen casings should be empty initially")
	assert_eq(manager._frozen_shrapnel.size(), 0,
		"Frozen shrapnel should be empty initially")
	assert_eq(manager._frozen_explosion_effects.size(), 0,
		"Frozen explosion effects should be empty initially")
	assert_eq(manager._frozen_explosion_visuals.size(), 0,
		"Frozen explosion visuals should be empty initially")


# ============================================================================
# _can_trigger_effect() Condition Tests
# ============================================================================


func test_can_trigger_when_all_conditions_met() -> void:
	difficulty.set_hard_mode(true)
	manager._has_player = true
	manager._player_current_health = 1.0

	assert_true(manager.can_trigger_effect(),
		"Should trigger when hard mode, player exists, health is 1.0, effect unused")


func test_cannot_trigger_when_effect_already_used() -> void:
	difficulty.set_hard_mode(true)
	manager._has_player = true
	manager._player_current_health = 1.0
	manager._effect_used = true

	assert_false(manager.can_trigger_effect(),
		"Should not trigger when effect already used this life")


func test_cannot_trigger_when_effect_already_active() -> void:
	difficulty.set_hard_mode(true)
	manager._has_player = true
	manager._player_current_health = 1.0
	manager._is_effect_active = true

	assert_false(manager.can_trigger_effect(),
		"Should not trigger when effect is already active")


func test_cannot_trigger_when_not_hard_mode() -> void:
	difficulty.set_hard_mode(false)
	manager._has_player = true
	manager._player_current_health = 1.0

	assert_false(manager.can_trigger_effect(),
		"Should not trigger when not in hard mode")


func test_cannot_trigger_when_no_difficulty_manager() -> void:
	manager._difficulty_manager = null
	manager._has_player = true
	manager._player_current_health = 1.0

	assert_false(manager.can_trigger_effect(),
		"Should not trigger when DifficultyManager is null")


func test_cannot_trigger_when_no_player() -> void:
	difficulty.set_hard_mode(true)
	manager._has_player = false
	manager._player_current_health = 1.0

	assert_false(manager.can_trigger_effect(),
		"Should not trigger when player is null")


func test_cannot_trigger_when_player_health_above_one() -> void:
	difficulty.set_hard_mode(true)
	manager._has_player = true
	manager._player_current_health = 2.0

	assert_false(manager.can_trigger_effect(),
		"Should not trigger when player health is above 1.0")


func test_cannot_trigger_when_player_health_zero() -> void:
	difficulty.set_hard_mode(true)
	manager._has_player = true
	manager._player_current_health = 0.0

	assert_false(manager.can_trigger_effect(),
		"Should not trigger when player health is 0.0 (dead)")


func test_cannot_trigger_when_player_health_negative() -> void:
	difficulty.set_hard_mode(true)
	manager._has_player = true
	manager._player_current_health = -1.0

	assert_false(manager.can_trigger_effect(),
		"Should not trigger when player health is negative (dead)")


func test_can_trigger_when_player_health_exactly_one() -> void:
	difficulty.set_hard_mode(true)
	manager._has_player = true
	manager._player_current_health = 1.0

	assert_true(manager.can_trigger_effect(),
		"Should trigger when player health is exactly 1.0")


func test_can_trigger_when_player_health_slightly_below_one() -> void:
	difficulty.set_hard_mode(true)
	manager._has_player = true
	manager._player_current_health = 0.5

	assert_true(manager.can_trigger_effect(),
		"Should trigger when player health is between 0 and 1 (alive but low)")


func test_can_trigger_when_player_health_barely_above_zero() -> void:
	difficulty.set_hard_mode(true)
	manager._has_player = true
	manager._player_current_health = 0.01

	assert_true(manager.can_trigger_effect(),
		"Should trigger when player health is barely above zero")


func test_cannot_trigger_health_exactly_at_boundary_above() -> void:
	difficulty.set_hard_mode(true)
	manager._has_player = true
	manager._player_current_health = 1.001

	assert_false(manager.can_trigger_effect(),
		"Should not trigger when player health is slightly above 1.0")


# ============================================================================
# Effect Start Lifecycle Tests
# ============================================================================


func test_start_effect_sets_active() -> void:
	manager.start_last_chance_effect()

	assert_true(manager._is_effect_active,
		"Effect should be active after starting")


func test_start_effect_sets_default_duration() -> void:
	manager.start_last_chance_effect()

	assert_eq(manager._current_effect_duration, 6.0,
		"Default effect duration should be FREEZE_DURATION_REAL_SECONDS")


func test_start_effect_sets_custom_duration() -> void:
	manager.start_last_chance_effect(3.0)

	assert_eq(manager._current_effect_duration, 3.0,
		"Effect duration should match the provided value")


func test_start_effect_marks_used_for_threat_trigger() -> void:
	manager.start_last_chance_effect(6.0, false)

	assert_true(manager._effect_used,
		"Non-grenade trigger should mark effect as used")


func test_start_effect_does_not_mark_used_for_grenade_trigger() -> void:
	manager.start_last_chance_effect(2.0, true)

	assert_false(manager._effect_used,
		"Grenade trigger should NOT mark effect as used")


func test_start_effect_sets_grenade_flag() -> void:
	manager.start_last_chance_effect(2.0, true)

	assert_true(manager._is_grenade_triggered,
		"Grenade flag should be set when triggered by grenade")


func test_start_effect_clears_grenade_flag_for_threat() -> void:
	manager.start_last_chance_effect(6.0, false)

	assert_false(manager._is_grenade_triggered,
		"Grenade flag should be false for threat trigger")


func test_start_effect_calls_freeze_time() -> void:
	manager.start_last_chance_effect()

	assert_true(manager._freeze_time_called,
		"Starting effect should freeze time")


func test_start_effect_applies_visual_effects() -> void:
	manager.start_last_chance_effect()

	assert_true(manager._visual_effects_applied,
		"Starting effect should apply visual effects")


func test_start_effect_pushes_bullets_for_threat() -> void:
	manager.start_last_chance_effect(6.0, false)

	assert_true(manager._push_bullets_called,
		"Threat trigger should push threatening bullets away")


func test_start_effect_does_not_push_bullets_for_grenade() -> void:
	manager.start_last_chance_effect(2.0, true)

	assert_false(manager._push_bullets_called,
		"Grenade trigger should NOT push bullets away")


func test_start_effect_grants_invulnerability_for_threat() -> void:
	manager.start_last_chance_effect(6.0, false)

	assert_true(manager._grant_invulnerability_called,
		"Threat trigger should grant player invulnerability")


func test_start_effect_does_not_grant_invulnerability_for_grenade() -> void:
	manager.start_last_chance_effect(2.0, true)

	assert_false(manager._grant_invulnerability_called,
		"Grenade trigger should NOT grant invulnerability")


func test_start_effect_does_nothing_when_already_active() -> void:
	manager.start_last_chance_effect(6.0, false)

	# Reset tracking flags
	manager._freeze_time_called = false
	manager._visual_effects_applied = false

	# Try to start again
	manager.start_last_chance_effect(3.0, true)

	assert_false(manager._freeze_time_called,
		"Should not re-freeze time when already active")
	assert_false(manager._visual_effects_applied,
		"Should not re-apply visuals when already active")
	# Duration should remain the original
	assert_eq(manager._current_effect_duration, 6.0,
		"Duration should not change when start is rejected")


# ============================================================================
# Effect End Lifecycle Tests
# ============================================================================


func test_end_effect_sets_inactive() -> void:
	manager.start_last_chance_effect()
	manager.end_last_chance_effect()

	assert_false(manager._is_effect_active,
		"Effect should be inactive after ending")


func test_end_effect_unfreezes_time() -> void:
	manager.start_last_chance_effect()
	manager.end_last_chance_effect()

	assert_true(manager._unfreeze_time_called,
		"Ending effect should unfreeze time")


func test_end_effect_starts_fade_out() -> void:
	manager.start_last_chance_effect()
	manager.end_last_chance_effect()

	assert_true(manager._fade_out_started,
		"Ending effect should start the fade-out animation")
	assert_true(manager._is_fading_out,
		"Fade-out flag should be true after ending effect")


func test_end_effect_resets_enemy_memory() -> void:
	manager.start_last_chance_effect()
	manager.end_last_chance_effect()

	assert_true(manager._reset_enemy_memory_called,
		"Ending effect should reset all enemy memory (Issue #318)")


func test_end_effect_does_nothing_when_not_active() -> void:
	# Effect not active, try to end
	manager.end_last_chance_effect()

	assert_false(manager._unfreeze_time_called,
		"Should not unfreeze time when effect was not active")
	assert_false(manager._fade_out_started,
		"Should not start fade-out when effect was not active")


# ============================================================================
# Grenade Trigger Tests
# ============================================================================


func test_grenade_trigger_starts_effect() -> void:
	manager._has_player = true
	manager.trigger_grenade_last_chance(2.0)

	assert_true(manager._is_effect_active,
		"Grenade trigger should start the effect")


func test_grenade_trigger_uses_provided_duration() -> void:
	manager._has_player = true
	manager.trigger_grenade_last_chance(2.5)

	assert_eq(manager._current_effect_duration, 2.5,
		"Grenade trigger should use the provided duration")


func test_grenade_trigger_sets_grenade_flag() -> void:
	manager._has_player = true
	manager.trigger_grenade_last_chance(2.0)

	assert_true(manager._is_grenade_triggered,
		"Grenade trigger should set the grenade flag")


func test_grenade_trigger_does_not_mark_effect_used() -> void:
	manager._has_player = true
	manager.trigger_grenade_last_chance(2.0)

	assert_false(manager._effect_used,
		"Grenade trigger should NOT mark effect as used (can be reused)")


func test_grenade_trigger_skips_when_already_active() -> void:
	manager._has_player = true
	manager.start_last_chance_effect(6.0, false)

	# Reset tracking
	manager._freeze_time_called = false

	manager.trigger_grenade_last_chance(2.0)

	assert_false(manager._freeze_time_called,
		"Grenade trigger should skip when effect is already active")
	assert_eq(manager._current_effect_duration, 6.0,
		"Duration should remain the original when grenade trigger is rejected")


func test_grenade_trigger_skips_when_no_player() -> void:
	manager._has_player = false
	manager.trigger_grenade_last_chance(2.0)

	assert_false(manager._is_effect_active,
		"Grenade trigger should skip when no player is found")


func test_grenade_trigger_allows_reuse_after_end() -> void:
	manager._has_player = true

	# First grenade trigger
	manager.trigger_grenade_last_chance(2.0)
	assert_true(manager._is_effect_active, "First grenade trigger should work")

	# End the effect
	manager.end_last_chance_effect()
	assert_false(manager._is_effect_active, "Effect should end")

	# Reset tracking
	manager._freeze_time_called = false

	# Second grenade trigger should work (not marked as used)
	manager.trigger_grenade_last_chance(1.5)
	assert_true(manager._is_effect_active,
		"Grenade trigger should work again after previous grenade effect ended")
	assert_eq(manager._current_effect_duration, 1.5,
		"Second grenade trigger should use its own duration")


# ============================================================================
# _effect_used Flag Behavior Tests
# ============================================================================


func test_threat_trigger_blocks_second_trigger() -> void:
	# First threat trigger
	manager.start_last_chance_effect(6.0, false)
	assert_true(manager._effect_used, "Threat trigger should mark effect as used")

	# End the effect
	manager.end_last_chance_effect()

	# Effect is used, so can_trigger_effect should fail
	difficulty.set_hard_mode(true)
	manager._has_player = true
	manager._player_current_health = 1.0

	assert_false(manager.can_trigger_effect(),
		"Effect should not be triggerable again after being used by threat")


func test_grenade_trigger_does_not_block_threat_trigger() -> void:
	# Grenade trigger first
	manager._has_player = true
	manager.trigger_grenade_last_chance(2.0)
	manager.end_last_chance_effect()

	# Threat trigger should still be available
	difficulty.set_hard_mode(true)
	manager._player_current_health = 1.0

	assert_true(manager.can_trigger_effect(),
		"Grenade usage should not block subsequent threat triggers")


func test_effect_used_flag_resets_on_player_death() -> void:
	# Use the effect via threat trigger
	manager.start_last_chance_effect(6.0, false)
	assert_true(manager._effect_used, "Effect should be marked as used")
	manager.end_last_chance_effect()

	# Player dies
	manager.on_player_died()

	assert_false(manager._effect_used,
		"Effect used flag should reset on player death")


func test_effect_used_flag_resets_on_scene_change() -> void:
	# Use the effect via threat trigger
	manager.start_last_chance_effect(6.0, false)
	assert_true(manager._effect_used, "Effect should be marked as used")
	manager.end_last_chance_effect()

	# Scene change (reset)
	manager.reset_effects()

	assert_false(manager._effect_used,
		"Effect used flag should reset on scene change")


# ============================================================================
# Player Death Handling Tests
# ============================================================================


func test_player_death_ends_active_effect() -> void:
	manager.start_last_chance_effect()
	assert_true(manager._is_effect_active, "Effect should be active")

	manager.on_player_died()

	assert_false(manager._is_effect_active,
		"Player death should end the active effect")


func test_player_death_resets_effect_used() -> void:
	manager.start_last_chance_effect(6.0, false)
	manager.end_last_chance_effect()
	assert_true(manager._effect_used, "Effect should be marked as used")

	manager.on_player_died()

	assert_false(manager._effect_used,
		"Player death should reset effect used flag for next life")


func test_player_death_unfreezes_time_if_effect_active() -> void:
	manager.start_last_chance_effect()
	manager.on_player_died()

	assert_true(manager._unfreeze_time_called,
		"Player death should unfreeze time if effect was active")


func test_player_death_no_unfreeze_if_effect_not_active() -> void:
	# Effect not active, player dies
	manager.on_player_died()

	assert_false(manager._unfreeze_time_called,
		"Player death should not unfreeze time if effect was not active")


func test_player_death_while_grenade_effect_active() -> void:
	manager._has_player = true
	manager.trigger_grenade_last_chance(2.0)
	assert_true(manager._is_effect_active, "Grenade effect should be active")
	assert_false(manager._effect_used, "Grenade should not set used flag")

	manager.on_player_died()

	assert_false(manager._is_effect_active,
		"Player death should end grenade effect")
	assert_false(manager._effect_used,
		"Effect used flag should be false after death (reset)")


# ============================================================================
# _is_descendant_of() Helper Tests
# ============================================================================


func test_is_descendant_of_direct_child() -> void:
	var parent_node := MockNode.new("parent")
	var child_node := MockNode.new("child")
	parent_node.add_child(child_node)

	assert_true(manager.is_descendant_of(parent_node, child_node),
		"Direct child should be a descendant of parent")


func test_is_descendant_of_grandchild() -> void:
	var grandparent := MockNode.new("grandparent")
	var parent_node := MockNode.new("parent")
	var child_node := MockNode.new("child")
	grandparent.add_child(parent_node)
	parent_node.add_child(child_node)

	assert_true(manager.is_descendant_of(grandparent, child_node),
		"Grandchild should be a descendant of grandparent")


func test_is_descendant_of_deep_hierarchy() -> void:
	var root := MockNode.new("root")
	var level1 := MockNode.new("level1")
	var level2 := MockNode.new("level2")
	var level3 := MockNode.new("level3")
	var level4 := MockNode.new("level4")
	root.add_child(level1)
	level1.add_child(level2)
	level2.add_child(level3)
	level3.add_child(level4)

	assert_true(manager.is_descendant_of(root, level4),
		"Deeply nested node should be a descendant of root")


func test_is_descendant_of_not_parent() -> void:
	var node_a := MockNode.new("A")
	var node_b := MockNode.new("B")
	# No parent-child relationship

	assert_false(manager.is_descendant_of(node_a, node_b),
		"Unrelated node should not be a descendant")


func test_is_descendant_of_reversed_order() -> void:
	var parent_node := MockNode.new("parent")
	var child_node := MockNode.new("child")
	parent_node.add_child(child_node)

	assert_false(manager.is_descendant_of(child_node, parent_node),
		"Parent should NOT be a descendant of child")


func test_is_descendant_of_same_node() -> void:
	var node := MockNode.new("self")

	assert_false(manager.is_descendant_of(node, node),
		"A node should not be considered a descendant of itself")


func test_is_descendant_of_null_ancestor() -> void:
	var node := MockNode.new("node")

	assert_false(manager.is_descendant_of(null, node),
		"Should return false when ancestor is null")


func test_is_descendant_of_null_node() -> void:
	var ancestor := MockNode.new("ancestor")

	assert_false(manager.is_descendant_of(ancestor, null),
		"Should return false when node is null")


func test_is_descendant_of_both_null() -> void:
	assert_false(manager.is_descendant_of(null, null),
		"Should return false when both are null")


func test_is_descendant_of_sibling_nodes() -> void:
	var parent_node := MockNode.new("parent")
	var child_a := MockNode.new("childA")
	var child_b := MockNode.new("childB")
	parent_node.add_child(child_a)
	parent_node.add_child(child_b)

	assert_false(manager.is_descendant_of(child_a, child_b),
		"Sibling nodes should not be descendants of each other")


# ============================================================================
# _count_descendants() Helper Tests
# ============================================================================


func test_count_descendants_no_children() -> void:
	var node := MockNode.new("leaf")

	assert_eq(manager.count_descendants(node), 0,
		"Node with no children should have 0 descendants")


func test_count_descendants_one_child() -> void:
	var parent_node := MockNode.new("parent")
	var child := MockNode.new("child")
	parent_node.add_child(child)

	assert_eq(manager.count_descendants(parent_node), 1,
		"Node with one child should have 1 descendant")


func test_count_descendants_multiple_direct_children() -> void:
	var parent_node := MockNode.new("parent")
	parent_node.add_child(MockNode.new("child1"))
	parent_node.add_child(MockNode.new("child2"))
	parent_node.add_child(MockNode.new("child3"))

	assert_eq(manager.count_descendants(parent_node), 3,
		"Node with three direct children should have 3 descendants")


func test_count_descendants_nested_hierarchy() -> void:
	var root := MockNode.new("root")
	var child := MockNode.new("child")
	var grandchild := MockNode.new("grandchild")
	root.add_child(child)
	child.add_child(grandchild)

	assert_eq(manager.count_descendants(root), 2,
		"Root -> child -> grandchild should count 2 descendants for root")


func test_count_descendants_complex_tree() -> void:
	# Build a tree:
	#       root
	#      /    \
	#    A       B
	#   / \      |
	#  C   D     E
	var root := MockNode.new("root")
	var a := MockNode.new("A")
	var b := MockNode.new("B")
	var c := MockNode.new("C")
	var d := MockNode.new("D")
	var e := MockNode.new("E")
	root.add_child(a)
	root.add_child(b)
	a.add_child(c)
	a.add_child(d)
	b.add_child(e)

	assert_eq(manager.count_descendants(root), 5,
		"Root with 5 total descendants should return 5")
	assert_eq(manager.count_descendants(a), 2,
		"Node A with 2 children should return 2")
	assert_eq(manager.count_descendants(b), 1,
		"Node B with 1 child should return 1")
	assert_eq(manager.count_descendants(c), 0,
		"Leaf node C should return 0")


# ============================================================================
# _saturate_color() Math Tests
# ============================================================================


func test_saturate_color_white_stays_white() -> void:
	var white := Color(1.0, 1.0, 1.0, 1.0)
	var result := manager.saturate_color(white, 4.0)

	# White has equal RGB so luminance == each channel; saturation has no effect
	assert_almost_eq(result.r, 1.0, 0.01,
		"White saturated should stay white (R)")
	assert_almost_eq(result.g, 1.0, 0.01,
		"White saturated should stay white (G)")
	assert_almost_eq(result.b, 1.0, 0.01,
		"White saturated should stay white (B)")


func test_saturate_color_black_stays_black() -> void:
	var black := Color(0.0, 0.0, 0.0, 1.0)
	var result := manager.saturate_color(black, 4.0)

	assert_almost_eq(result.r, 0.0, 0.01,
		"Black saturated should stay black (R)")
	assert_almost_eq(result.g, 0.0, 0.01,
		"Black saturated should stay black (G)")
	assert_almost_eq(result.b, 0.0, 0.01,
		"Black saturated should stay black (B)")


func test_saturate_color_preserves_alpha() -> void:
	var color := Color(0.5, 0.3, 0.7, 0.5)
	var result := manager.saturate_color(color, 2.0)

	assert_eq(result.a, 0.5,
		"Saturation should not affect alpha channel")


func test_saturate_color_multiplier_one_no_change() -> void:
	var color := Color(0.8, 0.3, 0.5, 1.0)
	var result := manager.saturate_color(color, 1.0)

	assert_almost_eq(result.r, 0.8, 0.001,
		"Multiplier 1.0 should not change R channel")
	assert_almost_eq(result.g, 0.3, 0.001,
		"Multiplier 1.0 should not change G channel")
	assert_almost_eq(result.b, 0.5, 0.001,
		"Multiplier 1.0 should not change B channel")


func test_saturate_color_multiplier_zero_becomes_grayscale() -> void:
	var color := Color(1.0, 0.0, 0.0, 1.0)  # Pure red
	var result := manager.saturate_color(color, 0.0)

	# Luminance of pure red: 0.299
	var expected_luminance := 1.0 * 0.299 + 0.0 * 0.587 + 0.0 * 0.114
	assert_almost_eq(result.r, expected_luminance, 0.001,
		"Multiplier 0.0 should make R equal to luminance (grayscale)")
	assert_almost_eq(result.g, expected_luminance, 0.001,
		"Multiplier 0.0 should make G equal to luminance (grayscale)")
	assert_almost_eq(result.b, expected_luminance, 0.001,
		"Multiplier 0.0 should make B equal to luminance (grayscale)")


func test_saturate_color_high_multiplier_clamps() -> void:
	var color := Color(1.0, 0.0, 0.0, 1.0)  # Pure red
	var result := manager.saturate_color(color, 10.0)

	# Values should be clamped between 0.0 and 1.0
	assert_gte(result.r, 0.0, "R should not go below 0.0")
	assert_lte(result.r, 1.0, "R should not exceed 1.0")
	assert_gte(result.g, 0.0, "G should not go below 0.0")
	assert_lte(result.g, 1.0, "G should not exceed 1.0")
	assert_gte(result.b, 0.0, "B should not go below 0.0")
	assert_lte(result.b, 1.0, "B should not exceed 1.0")


func test_saturate_color_luminance_calculation() -> void:
	# Verify the luminance formula: L = R*0.299 + G*0.587 + B*0.114
	var color := Color(0.5, 0.5, 0.5, 1.0)  # Gray
	var expected_luminance := 0.5 * 0.299 + 0.5 * 0.587 + 0.5 * 0.114  # = 0.5

	# For gray, multiplier should have no visible effect since all channels equal luminance
	var result := manager.saturate_color(color, 4.0)
	assert_almost_eq(result.r, 0.5, 0.001,
		"Gray color saturated should remain gray (R)")
	assert_almost_eq(result.g, 0.5, 0.001,
		"Gray color saturated should remain gray (G)")
	assert_almost_eq(result.b, 0.5, 0.001,
		"Gray color saturated should remain gray (B)")


func test_saturate_color_increases_color_difference() -> void:
	var color := Color(0.8, 0.3, 0.5, 1.0)
	var result := manager.saturate_color(color, 2.0)

	# Higher multiplier should increase the difference between channels
	var original_range := color.r - color.g  # 0.5
	var result_range := result.r - result.g

	assert_gt(result_range, original_range,
		"Higher saturation should increase the difference between channels")


func test_saturate_color_pure_green() -> void:
	var green := Color(0.0, 1.0, 0.0, 1.0)
	var result := manager.saturate_color(green, 4.0)

	# Luminance of pure green: 0.587
	# R: lerp(0.587, 0.0, 4.0) = 0.587 + 4.0 * (0.0 - 0.587) = 0.587 - 2.348 = -1.761 -> clamped to 0.0
	# G: lerp(0.587, 1.0, 4.0) = 0.587 + 4.0 * (1.0 - 0.587) = 0.587 + 1.652 = 2.239 -> clamped to 1.0
	# B: lerp(0.587, 0.0, 4.0) = 0.587 + 4.0 * (0.0 - 0.587) = 0.587 - 2.348 = -1.761 -> clamped to 0.0
	assert_almost_eq(result.r, 0.0, 0.01,
		"Pure green saturated 4x should clamp R to 0.0")
	assert_almost_eq(result.g, 1.0, 0.01,
		"Pure green saturated 4x should clamp G to 1.0")
	assert_almost_eq(result.b, 0.0, 0.01,
		"Pure green saturated 4x should clamp B to 0.0")


func test_saturate_color_with_player_saturation_multiplier() -> void:
	# Test using the actual PLAYER_SATURATION_MULTIPLIER constant
	var skin_color := Color(0.9, 0.7, 0.6, 1.0)
	var result := manager.saturate_color(skin_color, MockLastChanceEffectsManager.PLAYER_SATURATION_MULTIPLIER)

	# All values should be valid
	assert_gte(result.r, 0.0, "R should be non-negative")
	assert_lte(result.r, 1.0, "R should not exceed 1.0")
	assert_gte(result.g, 0.0, "G should be non-negative")
	assert_lte(result.g, 1.0, "G should not exceed 1.0")
	assert_gte(result.b, 0.0, "B should be non-negative")
	assert_lte(result.b, 1.0, "B should not exceed 1.0")
	assert_eq(result.a, 1.0, "Alpha should remain unchanged")


# ============================================================================
# reset_effects() Comprehensive Reset Tests
# ============================================================================


func test_reset_clears_active_effect() -> void:
	manager.start_last_chance_effect()
	manager.reset_effects()

	assert_false(manager._is_effect_active,
		"Reset should clear active effect state")


func test_reset_clears_fading_out() -> void:
	manager.start_last_chance_effect()
	manager.end_last_chance_effect()
	assert_true(manager._is_fading_out, "Should be fading out after end")

	manager.reset_effects()

	assert_false(manager._is_fading_out,
		"Reset should clear fading out state (Issue #442)")


func test_reset_removes_visual_effects() -> void:
	manager.start_last_chance_effect()
	manager.reset_effects()

	assert_true(manager._visual_effects_removed,
		"Reset should remove visual effects immediately (Issue #452)")


func test_reset_clears_player_reference() -> void:
	manager._has_player = true
	manager._connected_to_player = true

	manager.reset_effects()

	assert_false(manager._has_player,
		"Reset should clear player reference")
	assert_false(manager._connected_to_player,
		"Reset should clear player connection flag")


func test_reset_clears_effect_used_flag() -> void:
	manager.start_last_chance_effect(6.0, false)
	assert_true(manager._effect_used, "Effect should be marked as used")

	manager.reset_effects()

	assert_false(manager._effect_used,
		"Reset should clear effect used flag")


func test_reset_clears_grenade_flag() -> void:
	manager._has_player = true
	manager.trigger_grenade_last_chance(2.0)
	assert_true(manager._is_grenade_triggered, "Grenade flag should be set")

	manager.reset_effects()

	assert_false(manager._is_grenade_triggered,
		"Reset should clear grenade triggered flag")


func test_reset_restores_default_duration() -> void:
	manager._has_player = true
	manager.trigger_grenade_last_chance(2.0)
	assert_eq(manager._current_effect_duration, 2.0, "Duration should be 2.0")

	manager.reset_effects()

	assert_eq(manager._current_effect_duration, 6.0,
		"Reset should restore default freeze duration")


func test_reset_clears_cached_player_health() -> void:
	manager._player_current_health = 1.0

	manager.reset_effects()

	assert_eq(manager._player_current_health, 0.0,
		"Reset should clear cached player health")


func test_reset_clears_all_frozen_arrays() -> void:
	manager._frozen_player_bullets.append("bullet1")
	manager._frozen_grenades.append("grenade1")
	manager._frozen_casings.append("casing1")
	manager._frozen_shrapnel.append("shrapnel1")
	manager._frozen_explosion_effects.append("explosion1")
	manager._frozen_explosion_visuals.append("visual1")

	manager.reset_effects()

	assert_eq(manager._frozen_player_bullets.size(), 0,
		"Reset should clear frozen player bullets")
	assert_eq(manager._frozen_grenades.size(), 0,
		"Reset should clear frozen grenades")
	assert_eq(manager._frozen_casings.size(), 0,
		"Reset should clear frozen casings")
	assert_eq(manager._frozen_shrapnel.size(), 0,
		"Reset should clear frozen shrapnel")
	assert_eq(manager._frozen_explosion_effects.size(), 0,
		"Reset should clear frozen explosion effects")
	assert_eq(manager._frozen_explosion_visuals.size(), 0,
		"Reset should clear frozen explosion visuals")


func test_reset_clears_original_process_modes() -> void:
	manager._original_process_modes["node1"] = 0
	manager._original_process_modes["node2"] = 1

	manager.reset_effects()

	assert_eq(manager._original_process_modes.size(), 0,
		"Reset should clear original process modes dictionary")


func test_reset_clears_player_original_colors() -> void:
	manager._player_original_colors["sprite1"] = Color.WHITE
	manager._player_original_colors["sprite2"] = Color.RED

	manager.reset_effects()

	assert_eq(manager._player_original_colors.size(), 0,
		"Reset should clear player original colors dictionary")


func test_reset_clears_invulnerability_flag() -> void:
	manager._player_was_invulnerable = true

	manager.reset_effects()

	assert_false(manager._player_was_invulnerable,
		"Reset should clear player invulnerability tracking flag")


func test_reset_unfreezes_time_if_effect_active() -> void:
	manager.start_last_chance_effect()
	manager._unfreeze_time_called = false  # Reset tracking from start

	manager.reset_effects()

	assert_true(manager._unfreeze_time_called,
		"Reset should unfreeze time if effect was active")


func test_reset_does_not_unfreeze_time_if_effect_not_active() -> void:
	manager.reset_effects()

	assert_false(manager._unfreeze_time_called,
		"Reset should not unfreeze time if effect was not active")


# ============================================================================
# Public Accessor Method Tests
# ============================================================================


func test_is_effect_active_returns_false_initially() -> void:
	assert_false(manager.is_effect_active(),
		"is_effect_active() should return false initially")


func test_is_effect_active_returns_true_when_active() -> void:
	manager.start_last_chance_effect()

	assert_true(manager.is_effect_active(),
		"is_effect_active() should return true when effect is active")


func test_is_effect_active_returns_false_after_end() -> void:
	manager.start_last_chance_effect()
	manager.end_last_chance_effect()

	assert_false(manager.is_effect_active(),
		"is_effect_active() should return false after ending")


func test_is_effect_used_returns_false_initially() -> void:
	assert_false(manager.is_effect_used(),
		"is_effect_used() should return false initially")


func test_is_effect_used_returns_true_after_threat_trigger() -> void:
	manager.start_last_chance_effect(6.0, false)

	assert_true(manager.is_effect_used(),
		"is_effect_used() should return true after threat trigger")


func test_is_effect_used_returns_false_after_grenade_trigger() -> void:
	manager.start_last_chance_effect(2.0, true)

	assert_false(manager.is_effect_used(),
		"is_effect_used() should return false after grenade trigger")


# ============================================================================
# Full Lifecycle Integration Tests
# ============================================================================


func test_full_threat_trigger_lifecycle() -> void:
	# Setup conditions for trigger
	difficulty.set_hard_mode(true)
	manager._has_player = true
	manager._player_current_health = 1.0

	# Verify can trigger
	assert_true(manager.can_trigger_effect(), "Should be able to trigger")

	# Start the effect
	manager.start_last_chance_effect(6.0, false)
	assert_true(manager._is_effect_active, "Effect should be active")
	assert_true(manager._effect_used, "Effect should be marked as used")
	assert_false(manager._is_grenade_triggered, "Should not be grenade triggered")
	assert_eq(manager._current_effect_duration, 6.0, "Duration should be 6.0")

	# Cannot trigger again while active
	assert_false(manager.can_trigger_effect(), "Cannot trigger while active")

	# End the effect
	manager.end_last_chance_effect()
	assert_false(manager._is_effect_active, "Effect should be inactive")
	assert_true(manager._is_fading_out, "Should be fading out")

	# Cannot trigger again (used this life)
	assert_false(manager.can_trigger_effect(), "Cannot trigger after being used")

	# Player dies, resets usage
	manager.on_player_died()
	assert_false(manager._effect_used, "Death should reset used flag")

	# Can trigger again in new life
	assert_true(manager.can_trigger_effect(), "Should be able to trigger in new life")


func test_full_grenade_then_threat_lifecycle() -> void:
	difficulty.set_hard_mode(true)
	manager._has_player = true
	manager._player_current_health = 1.0

	# Grenade trigger first
	manager.trigger_grenade_last_chance(2.0)
	assert_true(manager._is_effect_active, "Grenade effect should be active")
	assert_true(manager._is_grenade_triggered, "Should be grenade triggered")
	assert_false(manager._effect_used, "Grenade should not mark as used")

	# End grenade effect
	manager.end_last_chance_effect()
	assert_false(manager._is_effect_active, "Effect should be inactive")

	# Threat trigger should still work
	assert_true(manager.can_trigger_effect(),
		"Threat trigger should be available after grenade")

	# Start threat trigger
	manager.start_last_chance_effect(6.0, false)
	assert_true(manager._is_effect_active, "Threat effect should be active")
	assert_true(manager._effect_used, "Threat should mark as used")

	# End threat effect
	manager.end_last_chance_effect()

	# Cannot trigger again (used this life)
	assert_false(manager.can_trigger_effect(),
		"Should not be able to trigger after threat usage")


func test_scene_change_during_active_effect() -> void:
	manager._has_player = true
	manager.start_last_chance_effect(6.0, false)
	assert_true(manager._is_effect_active, "Effect should be active")

	# Scene change resets everything
	manager.reset_effects()

	assert_false(manager._is_effect_active,
		"Effect should be inactive after reset")
	assert_false(manager._effect_used,
		"Effect used should be cleared after reset")
	assert_false(manager._is_fading_out,
		"Fading out should be cleared after reset")
	assert_eq(manager._current_effect_duration, 6.0,
		"Duration should be reset to default")
	assert_eq(manager._player_current_health, 0.0,
		"Player health cache should be cleared")
	assert_false(manager._has_player,
		"Player reference should be cleared after scene change")


# ============================================================================
# Edge Cases and Boundary Tests
# ============================================================================


func test_start_with_zero_duration() -> void:
	manager.start_last_chance_effect(0.0, false)

	assert_true(manager._is_effect_active,
		"Effect should still start with zero duration")
	assert_eq(manager._current_effect_duration, 0.0,
		"Duration should be zero as requested")


func test_start_with_very_small_duration() -> void:
	manager.start_last_chance_effect(0.001, true)

	assert_true(manager._is_effect_active,
		"Effect should start with very small duration")
	assert_eq(manager._current_effect_duration, 0.001,
		"Duration should be set to 0.001")


func test_start_with_large_duration() -> void:
	manager.start_last_chance_effect(999.0, false)

	assert_eq(manager._current_effect_duration, 999.0,
		"Large duration should be accepted")


func test_multiple_grenade_triggers_in_sequence() -> void:
	manager._has_player = true

	# First grenade
	manager.trigger_grenade_last_chance(2.0)
	assert_true(manager._is_effect_active, "First grenade should activate")
	manager.end_last_chance_effect()

	# Second grenade
	manager.trigger_grenade_last_chance(1.5)
	assert_true(manager._is_effect_active, "Second grenade should activate")
	manager.end_last_chance_effect()

	# Third grenade
	manager.trigger_grenade_last_chance(3.0)
	assert_true(manager._is_effect_active, "Third grenade should activate")
	assert_eq(manager._current_effect_duration, 3.0,
		"Third grenade should use its own duration")


func test_double_end_effect_is_safe() -> void:
	manager.start_last_chance_effect()
	manager.end_last_chance_effect()

	# Reset tracking
	manager._unfreeze_time_called = false
	manager._reset_enemy_memory_called = false

	# End again (should be a no-op)
	manager.end_last_chance_effect()

	assert_false(manager._unfreeze_time_called,
		"Double end should not unfreeze time again")
	assert_false(manager._reset_enemy_memory_called,
		"Double end should not reset enemy memory again")


func test_double_reset_is_safe() -> void:
	manager.start_last_chance_effect()

	manager.reset_effects()
	manager.reset_effects()

	assert_false(manager._is_effect_active,
		"Double reset should leave effect inactive")
	assert_eq(manager._frozen_player_bullets.size(), 0,
		"Double reset should leave frozen arrays empty")


func test_player_death_multiple_times() -> void:
	# Death without active effect
	manager.on_player_died()
	assert_false(manager._effect_used, "Should remain false")

	# Use effect, then die
	manager.start_last_chance_effect(6.0, false)
	manager.end_last_chance_effect()
	assert_true(manager._effect_used, "Should be marked as used")

	manager.on_player_died()
	assert_false(manager._effect_used, "First death should reset")

	# Die again immediately
	manager.on_player_died()
	assert_false(manager._effect_used, "Second death should remain false")
