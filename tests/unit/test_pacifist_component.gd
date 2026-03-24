extends GutTest
## Tests for PacifistComponent (Issue #959: Loudspeaker effect).
##
## Validates retaliation duration, timer countdown, start/end retaliation,
## immunity flag, and pacifism state transitions.

const PacifistComp := preload("res://scripts/components/pacifist_component.gd")


# =============================================================================
# Constants
# =============================================================================

func test_retaliation_duration_constant() -> void:
	assert_eq(PacifistComp.RETALIATION_DURATION, 3.0,
		"RETALIATION_DURATION should be 3.0 seconds")


# =============================================================================
# Initial State
# =============================================================================

func test_initial_state_not_pacifist() -> void:
	var mock_enemy := Node2D.new()
	add_child_autofree(mock_enemy)
	var comp := PacifistComp.new(mock_enemy)

	assert_false(comp.is_pacifist, "Should not be pacifist initially")
	assert_false(comp.is_immune, "Should not be immune initially")
	assert_eq(comp.retaliation_timer, 0.0, "Retaliation timer should start at 0.0")
	assert_null(comp.attacker, "Attacker should be null initially")


func test_init_stores_enemy_reference() -> void:
	var mock_enemy := Node2D.new()
	add_child_autofree(mock_enemy)
	var comp := PacifistComp.new(mock_enemy)

	assert_eq(comp.enemy, mock_enemy, "Should store the enemy reference")


# =============================================================================
# Pacifism State
# =============================================================================

func test_start_pacifism_sets_state() -> void:
	var mock_enemy := Node2D.new()
	add_child_autofree(mock_enemy)
	var comp := PacifistComp.new(mock_enemy)

	var result := comp.start_pacifism()

	assert_true(result, "start_pacifism should return true on success")
	assert_true(comp.is_pacifist, "Should be pacifist after start_pacifism")
	assert_null(comp.attacker, "Attacker should be null")
	assert_eq(comp.retaliation_timer, 0.0, "Retaliation timer should be 0.0")


func test_start_pacifism_idempotent() -> void:
	var mock_enemy := Node2D.new()
	add_child_autofree(mock_enemy)
	var comp := PacifistComp.new(mock_enemy)

	comp.start_pacifism()
	var result := comp.start_pacifism()

	assert_false(result, "start_pacifism should return false when already pacifist")
	assert_true(comp.is_pacifist, "Should still be pacifist")


# =============================================================================
# Immunity Flag
# =============================================================================

func test_immune_enemy_cannot_become_pacifist() -> void:
	var mock_enemy := Node2D.new()
	add_child_autofree(mock_enemy)
	var comp := PacifistComp.new(mock_enemy)

	comp.set_immune(true)
	var result := comp.start_pacifism()

	assert_false(result, "start_pacifism should return false when immune")
	assert_false(comp.is_pacifist, "Should not become pacifist when immune")


func test_set_immune_flag() -> void:
	var mock_enemy := Node2D.new()
	add_child_autofree(mock_enemy)
	var comp := PacifistComp.new(mock_enemy)

	comp.set_immune(true)
	assert_true(comp.is_immune, "Should be immune after set_immune(true)")

	comp.set_immune(false)
	assert_false(comp.is_immune, "Should not be immune after set_immune(false)")


# =============================================================================
# Retaliation
# =============================================================================

func test_start_retaliation_sets_timer_and_attacker() -> void:
	var mock_enemy := Node2D.new()
	var mock_attacker := Node2D.new()
	add_child_autofree(mock_enemy)
	add_child_autofree(mock_attacker)
	var comp := PacifistComp.new(mock_enemy)

	comp.start_pacifism()
	comp.start_retaliation(mock_attacker)

	assert_eq(comp.retaliation_timer, PacifistComp.RETALIATION_DURATION,
		"Retaliation timer should be set to RETALIATION_DURATION")
	assert_eq(comp.attacker, mock_attacker,
		"Attacker should be set")
	assert_true(comp.is_retaliating(),
		"Should be retaliating")


func test_start_retaliation_ignored_when_not_pacifist() -> void:
	var mock_enemy := Node2D.new()
	var mock_attacker := Node2D.new()
	add_child_autofree(mock_enemy)
	add_child_autofree(mock_attacker)
	var comp := PacifistComp.new(mock_enemy)

	comp.start_retaliation(mock_attacker)

	assert_eq(comp.retaliation_timer, 0.0,
		"Retaliation timer should remain 0 when not pacifist")
	assert_null(comp.attacker, "Attacker should remain null when not pacifist")


func test_end_retaliation_clears_state() -> void:
	var mock_enemy := Node2D.new()
	var mock_attacker := Node2D.new()
	add_child_autofree(mock_enemy)
	add_child_autofree(mock_attacker)
	var comp := PacifistComp.new(mock_enemy)

	comp.start_pacifism()
	comp.start_retaliation(mock_attacker)
	comp.end_retaliation()

	assert_eq(comp.retaliation_timer, 0.0,
		"Retaliation timer should be 0 after end_retaliation")
	assert_null(comp.attacker,
		"Attacker should be null after end_retaliation")
	assert_false(comp.is_retaliating(),
		"Should not be retaliating after end_retaliation")


func test_is_retaliating_false_when_not_pacifist() -> void:
	var mock_enemy := Node2D.new()
	add_child_autofree(mock_enemy)
	var comp := PacifistComp.new(mock_enemy)

	comp.retaliation_timer = 2.0
	assert_false(comp.is_retaliating(),
		"Should not be retaliating when not pacifist even with timer")


# =============================================================================
# Retaliation Timer Countdown
# =============================================================================

func test_update_decrements_retaliation_timer() -> void:
	var mock_enemy := Node2D.new()
	var mock_attacker := Node2D.new()
	add_child_autofree(mock_enemy)
	add_child_autofree(mock_attacker)
	var comp := PacifistComp.new(mock_enemy)

	comp.start_pacifism()
	comp.start_retaliation(mock_attacker)

	var ended := comp.update(1.0)
	assert_false(ended, "Retaliation should not have ended after 1s")
	assert_almost_eq(comp.retaliation_timer, 2.0, 0.01,
		"Timer should be 2.0 after 1s decrement")


func test_update_retaliation_expires() -> void:
	var mock_enemy := Node2D.new()
	var mock_attacker := Node2D.new()
	add_child_autofree(mock_enemy)
	add_child_autofree(mock_attacker)
	var comp := PacifistComp.new(mock_enemy)

	comp.start_pacifism()
	comp.start_retaliation(mock_attacker)

	# Tick past full duration
	var ended := comp.update(4.0)

	assert_true(ended, "update should return true when retaliation ends")
	assert_eq(comp.retaliation_timer, 0.0,
		"Timer should be 0 after expiry")
	assert_null(comp.attacker,
		"Attacker should be cleared after expiry")


func test_update_returns_false_when_not_pacifist() -> void:
	var mock_enemy := Node2D.new()
	add_child_autofree(mock_enemy)
	var comp := PacifistComp.new(mock_enemy)

	var ended := comp.update(1.0)
	assert_false(ended, "update should return false when not pacifist")


func test_update_returns_false_when_no_retaliation() -> void:
	var mock_enemy := Node2D.new()
	add_child_autofree(mock_enemy)
	var comp := PacifistComp.new(mock_enemy)

	comp.start_pacifism()
	var ended := comp.update(1.0)
	assert_false(ended, "update should return false when pacifist but not retaliating")


# =============================================================================
# Debug Info
# =============================================================================

func test_debug_info_empty_when_not_pacifist() -> void:
	var mock_enemy := Node2D.new()
	add_child_autofree(mock_enemy)
	var comp := PacifistComp.new(mock_enemy)

	assert_eq(comp.get_debug_info(), "",
		"Debug info should be empty when not pacifist")


func test_debug_info_shows_pacifist() -> void:
	var mock_enemy := Node2D.new()
	add_child_autofree(mock_enemy)
	var comp := PacifistComp.new(mock_enemy)

	comp.start_pacifism()
	assert_eq(comp.get_debug_info(), "PACIFIST",
		"Debug info should show PACIFIST")


func test_debug_info_shows_retaliating() -> void:
	var mock_enemy := Node2D.new()
	var mock_attacker := Node2D.new()
	add_child_autofree(mock_enemy)
	add_child_autofree(mock_attacker)
	var comp := PacifistComp.new(mock_enemy)

	comp.start_pacifism()
	comp.start_retaliation(mock_attacker)

	var info := comp.get_debug_info()
	assert_true(info.begins_with("PACIFIST (retaliating"),
		"Debug info should show retaliating state")
