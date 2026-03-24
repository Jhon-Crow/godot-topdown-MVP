extends GutTest
## Tests for WeaponHintsComponent (Issue #809).
##
## Validates hint auto-dismiss duration, spacing, offset values,
## and other constants used for positioning floating weapon hints.

const WeaponHintsComp := preload("res://scripts/components/weapon_hints_component.gd")


# =============================================================================
# Constants
# =============================================================================

func test_hint_auto_dismiss_constant() -> void:
	assert_eq(WeaponHintsComp.HINT_AUTO_DISMISS, 8.0,
		"HINT_AUTO_DISMISS should be 8.0 seconds")


func test_hint_spacing_constant() -> void:
	assert_eq(WeaponHintsComp.HINT_SPACING, 60.0,
		"HINT_SPACING should be 60.0 px")


func test_hint_offset_y_constant() -> void:
	assert_eq(WeaponHintsComp.HINT_OFFSET_Y, -80.0,
		"HINT_OFFSET_Y should be -80.0 (above player)")


func test_hint_offset_x_constant() -> void:
	assert_eq(WeaponHintsComp.HINT_OFFSET_X, -150.0,
		"HINT_OFFSET_X should be -150.0")


func test_hint_min_size_constant() -> void:
	assert_eq(WeaponHintsComp.HINT_MIN_SIZE, Vector2(300, 30),
		"HINT_MIN_SIZE should be Vector2(300, 30)")


func test_hint_fade_in_duration_constant() -> void:
	assert_eq(WeaponHintsComp.HINT_FADE_IN_DURATION, 0.3,
		"HINT_FADE_IN_DURATION should be 0.3 seconds")


func test_hint_strikethrough_duration_constant() -> void:
	assert_eq(WeaponHintsComp.HINT_STRIKETHROUGH_DURATION, 0.4,
		"HINT_STRIKETHROUGH_DURATION should be 0.4 seconds")


func test_hint_fade_out_duration_constant() -> void:
	assert_eq(WeaponHintsComp.HINT_FADE_OUT_DURATION, 0.3,
		"HINT_FADE_OUT_DURATION should be 0.3 seconds")


# =============================================================================
# Initial State
# =============================================================================

func test_initial_state_no_hints_showing() -> void:
	var comp := WeaponHintsComp.new()
	add_child_autofree(comp)

	assert_false(comp._hints_showing, "Hints should not be showing initially")
	assert_false(comp._hints_active, "Hints should not be active initially")
	assert_eq(comp._current_weapon_id, "", "Current weapon ID should be empty")
	assert_eq(comp._shots_fired, 0, "Shots fired should be 0")


func test_initial_player_ref_null() -> void:
	var comp := WeaponHintsComp.new()
	add_child_autofree(comp)

	assert_null(comp._player, "Player reference should be null initially")


func test_initial_hint_labels_empty() -> void:
	var comp := WeaponHintsComp.new()
	add_child_autofree(comp)

	assert_eq(comp._hint_labels.size(), 0, "Hint labels dictionary should be empty")


func test_initial_hint_timers_empty() -> void:
	var comp := WeaponHintsComp.new()
	add_child_autofree(comp)

	assert_eq(comp._hint_timers.size(), 0, "Hint timers dictionary should be empty")


# =============================================================================
# Constant Relationships
# =============================================================================

func test_auto_dismiss_is_positive() -> void:
	assert_gt(WeaponHintsComp.HINT_AUTO_DISMISS, 0.0,
		"HINT_AUTO_DISMISS should be positive")


func test_spacing_is_positive() -> void:
	assert_gt(WeaponHintsComp.HINT_SPACING, 0.0,
		"HINT_SPACING should be positive")


func test_offset_y_is_negative() -> void:
	assert_lt(WeaponHintsComp.HINT_OFFSET_Y, 0.0,
		"HINT_OFFSET_Y should be negative (above player)")


func test_offset_x_is_negative() -> void:
	assert_lt(WeaponHintsComp.HINT_OFFSET_X, 0.0,
		"HINT_OFFSET_X should be negative (left of center)")


func test_fade_in_less_than_auto_dismiss() -> void:
	assert_lt(WeaponHintsComp.HINT_FADE_IN_DURATION, WeaponHintsComp.HINT_AUTO_DISMISS,
		"Fade-in duration should be much less than auto-dismiss time")


# =============================================================================
# Sequential Hint Tracking State
# =============================================================================

func test_initial_sequential_hint_flags() -> void:
	var comp := WeaponHintsComp.new()
	add_child_autofree(comp)

	assert_false(comp._bolt_cycle_hint_revealed,
		"Bolt cycle hint should not be revealed initially")
	assert_false(comp._reload_hint_revealed,
		"Reload hint should not be revealed initially")
	assert_false(comp._scope_used,
		"Scope used flag should be false initially")
	assert_false(comp._hammer_cocked,
		"Hammer cocked flag should be false initially")
	assert_false(comp._fire_mode_hint_pending,
		"Fire mode hint pending should be false initially")
	assert_false(comp._shotgun_full_reload_active,
		"Shotgun full reload active should be false initially")
	assert_false(comp._ak_gl_launcher_hint_shown,
		"AK GL launcher hint shown should be false initially")
