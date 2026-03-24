extends GutTest
## Tests for EnemyInvisibilityComponent (Issue #1121).
##
## Validates cloak/reveal state transitions, reveal timer countdown,
## and constant values without requiring shaders or the scene tree.

const InvisibilityComponent := preload("res://scripts/components/enemy_invisibility_component.gd")


# =============================================================================
# Constants
# =============================================================================

func test_reveal_duration_constant() -> void:
	assert_eq(InvisibilityComponent.REVEAL_DURATION, 2.0,
		"REVEAL_DURATION should be 2.0 seconds")


func test_enemy_ripple_speed_constant() -> void:
	assert_eq(InvisibilityComponent.ENEMY_RIPPLE_SPEED, 0.6,
		"ENEMY_RIPPLE_SPEED should be 0.6")


func test_enemy_shimmer_intensity_constant() -> void:
	assert_eq(InvisibilityComponent.ENEMY_SHIMMER_INTENSITY, 0.05,
		"ENEMY_SHIMMER_INTENSITY should be 0.05")


# =============================================================================
# Initial State
# =============================================================================

func test_initial_state_not_cloaked() -> void:
	var comp := InvisibilityComponent.new()
	add_child_autofree(comp)

	assert_false(comp.is_cloaked, "Should not be cloaked initially")
	assert_eq(comp._reveal_timer, 0.0, "Reveal timer should start at 0.0")


# =============================================================================
# Cloak / Reveal State Transitions
# =============================================================================

func test_reveal_sets_timer_when_cloaked() -> void:
	var comp := InvisibilityComponent.new()
	add_child_autofree(comp)

	comp.is_cloaked = true
	comp.reveal()

	assert_eq(comp._reveal_timer, InvisibilityComponent.REVEAL_DURATION,
		"Reveal timer should be set to REVEAL_DURATION")


func test_reveal_ignored_when_not_cloaked() -> void:
	var comp := InvisibilityComponent.new()
	add_child_autofree(comp)

	comp.is_cloaked = false
	comp.reveal()

	assert_eq(comp._reveal_timer, 0.0,
		"Reveal timer should remain 0 when not cloaked")


func test_remove_clears_cloak_state() -> void:
	var comp := InvisibilityComponent.new()
	add_child_autofree(comp)

	comp.is_cloaked = true
	comp._reveal_timer = 1.0
	comp.remove()

	assert_false(comp.is_cloaked, "Should not be cloaked after remove()")


# =============================================================================
# Reveal Timer Countdown
# =============================================================================

func test_update_decrements_reveal_timer() -> void:
	var comp := InvisibilityComponent.new()
	add_child_autofree(comp)

	comp.is_cloaked = true
	comp._reveal_timer = 2.0

	comp.update(0.5)
	assert_almost_eq(comp._reveal_timer, 1.5, 0.01,
		"Reveal timer should decrease by delta")


func test_update_clamps_reveal_timer_at_zero() -> void:
	var comp := InvisibilityComponent.new()
	add_child_autofree(comp)

	comp.is_cloaked = true
	comp._reveal_timer = 0.3

	comp.update(0.5)
	assert_eq(comp._reveal_timer, 0.0,
		"Reveal timer should clamp to 0.0 when it expires")


func test_update_does_nothing_when_not_cloaked() -> void:
	var comp := InvisibilityComponent.new()
	add_child_autofree(comp)

	comp.is_cloaked = false
	comp._reveal_timer = 1.0

	comp.update(0.5)
	assert_eq(comp._reveal_timer, 1.0,
		"Reveal timer should not change when not cloaked")


func test_update_does_nothing_when_timer_already_zero() -> void:
	var comp := InvisibilityComponent.new()
	add_child_autofree(comp)

	comp.is_cloaked = true
	comp._reveal_timer = 0.0

	comp.update(0.5)
	assert_eq(comp._reveal_timer, 0.0,
		"Reveal timer should remain 0 when already expired")


# =============================================================================
# Full Cycle: Reveal then Re-cloak
# =============================================================================

func test_reveal_then_recloak_cycle() -> void:
	var comp := InvisibilityComponent.new()
	add_child_autofree(comp)

	comp.is_cloaked = true

	# Reveal
	comp.reveal()
	assert_eq(comp._reveal_timer, 2.0, "Timer should be set on reveal")

	# Tick partway
	comp.update(1.0)
	assert_almost_eq(comp._reveal_timer, 1.0, 0.01, "Timer should tick down")

	# Tick past expiry — re-cloaks (timer hits 0)
	comp.update(1.5)
	assert_eq(comp._reveal_timer, 0.0, "Timer should be 0 after full expiry")
	# Enemy is still cloaked (is_cloaked stays true; mix_amount resets to 1.0)
	assert_true(comp.is_cloaked, "Should remain cloaked after re-cloak")
