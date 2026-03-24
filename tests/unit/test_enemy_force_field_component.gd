extends GutTest
## Tests for EnemyForceFieldComponent (Issue #1034).
##
## Validates force field activation, duration countdown, deactivation,
## and recharge logic without requiring the scene tree or packed scenes.

const ForceFieldComponent := preload("res://scripts/components/enemy_force_field_component.gd")


# =============================================================================
# Constants
# =============================================================================

func test_duration_constant() -> void:
	assert_eq(ForceFieldComponent.DURATION, 4.0, "DURATION should be 4.0 seconds")


func test_recharge_time_constant() -> void:
	assert_eq(ForceFieldComponent.RECHARGE_TIME, 5.0, "RECHARGE_TIME should be 5.0 seconds")


# =============================================================================
# Initial State
# =============================================================================

func test_initial_state_inactive() -> void:
	var comp := ForceFieldComponent.new()
	var parent := Node2D.new()
	parent.add_child(comp)
	add_child_autofree(parent)

	assert_false(comp.is_active(), "Force field should start inactive")
	assert_false(comp._recharging, "Should not start in recharging state")
	assert_eq(comp._timer, 0.0, "Timer should start at 0.0")
	assert_eq(comp._recharge_elapsed, 0.0, "Recharge elapsed should start at 0.0")


# =============================================================================
# Active / Inactive State
# =============================================================================

func test_is_active_returns_internal_active_flag() -> void:
	var comp := ForceFieldComponent.new()
	var parent := Node2D.new()
	parent.add_child(comp)
	add_child_autofree(parent)

	assert_false(comp.is_active(), "Should be inactive initially")
	comp._active = true
	assert_true(comp.is_active(), "Should be active when _active is true")
	comp._active = false
	assert_false(comp.is_active(), "Should be inactive when _active is false")


# =============================================================================
# Update Logic — Activation (no effect loaded, so we test state transitions)
# =============================================================================

func test_update_does_nothing_when_no_effect() -> void:
	# When _force_field_effect is null, update should return early without error
	var comp := ForceFieldComponent.new()
	var parent := Node2D.new()
	parent.add_child(comp)
	add_child_autofree(parent)

	comp.update(0.5, true)
	assert_false(comp.is_active(), "Should remain inactive with no effect loaded")


# =============================================================================
# Timer Countdown (manual state manipulation)
# =============================================================================

func test_active_timer_counts_down() -> void:
	var comp := ForceFieldComponent.new()
	var parent := Node2D.new()
	parent.add_child(comp)
	add_child_autofree(parent)

	# Simulate active state with a mock effect
	var mock_effect := Node2D.new()
	parent.add_child(mock_effect)
	comp._force_field_effect = mock_effect
	comp._active = true
	comp._timer = ForceFieldComponent.DURATION

	# Tick 1 second
	comp.update(1.0, false)
	assert_true(comp.is_active(), "Should still be active after 1s")
	assert_almost_eq(comp._timer, 3.0, 0.01, "Timer should be 3.0 after 1s")


func test_active_timer_expires_starts_recharge() -> void:
	var comp := ForceFieldComponent.new()
	var parent := Node2D.new()
	parent.add_child(comp)
	add_child_autofree(parent)

	var mock_effect := Node2D.new()
	mock_effect.set("remaining_charge", 10.0)
	parent.add_child(mock_effect)
	comp._force_field_effect = mock_effect
	comp._active = true
	comp._timer = 0.5

	# Tick past expiry
	comp.update(1.0, false)
	assert_false(comp.is_active(), "Should be inactive after timer expires")
	assert_true(comp._recharging, "Should be recharging after deactivation")
	assert_eq(comp._recharge_elapsed, 0.0, "Recharge elapsed should reset to 0.0")


# =============================================================================
# Recharge Logic
# =============================================================================

func test_recharge_elapsed_increments() -> void:
	var comp := ForceFieldComponent.new()
	var parent := Node2D.new()
	parent.add_child(comp)
	add_child_autofree(parent)

	var mock_effect := Node2D.new()
	parent.add_child(mock_effect)
	comp._force_field_effect = mock_effect
	comp._recharging = true
	comp._recharge_elapsed = 0.0

	comp.update(2.0, false)
	assert_almost_eq(comp._recharge_elapsed, 2.0, 0.01, "Recharge elapsed should be 2.0 after 2s")
	assert_true(comp._recharging, "Should still be recharging before RECHARGE_TIME")


func test_recharge_completes_after_recharge_time() -> void:
	var comp := ForceFieldComponent.new()
	var parent := Node2D.new()
	parent.add_child(comp)
	add_child_autofree(parent)

	var mock_effect := Node2D.new()
	parent.add_child(mock_effect)
	comp._force_field_effect = mock_effect
	comp._recharging = true
	comp._recharge_elapsed = 4.5

	# Tick past RECHARGE_TIME
	comp.update(1.0, false)
	assert_false(comp._recharging, "Should no longer be recharging after RECHARGE_TIME")
	assert_eq(comp._recharge_elapsed, 0.0, "Recharge elapsed should reset after recharge completes")


# =============================================================================
# Force Field Deactivated Signal Handler
# =============================================================================

func test_on_force_field_deactivated_starts_recharge() -> void:
	var comp := ForceFieldComponent.new()
	var parent := Node2D.new()
	parent.add_child(comp)
	add_child_autofree(parent)

	comp._active = true
	comp._on_force_field_deactivated()

	assert_false(comp._active, "Should be inactive after deactivated signal")
	assert_true(comp._recharging, "Should be recharging after deactivated signal")
	assert_eq(comp._recharge_elapsed, 0.0, "Recharge elapsed should be 0.0")


func test_on_force_field_deactivated_ignored_when_already_inactive() -> void:
	var comp := ForceFieldComponent.new()
	var parent := Node2D.new()
	parent.add_child(comp)
	add_child_autofree(parent)

	comp._active = false
	comp._recharging = false
	comp._on_force_field_deactivated()

	assert_false(comp._recharging, "Should not start recharging when already inactive")


# =============================================================================
# Cannot Activate While Recharging
# =============================================================================

func test_cannot_activate_while_recharging() -> void:
	var comp := ForceFieldComponent.new()
	var parent := Node2D.new()
	parent.add_child(comp)
	add_child_autofree(parent)

	var mock_effect := Node2D.new()
	parent.add_child(mock_effect)
	comp._force_field_effect = mock_effect
	comp._recharging = true

	# Try to activate by seeing target
	comp.update(0.016, true)
	assert_false(comp.is_active(), "Should not activate while recharging")
