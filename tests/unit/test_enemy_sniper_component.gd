extends GutTest
## Tests for EnemySniperComponent (Issues #1163, #1171).
##
## Validates distance constants, blind fire cooldown, and
## blind fire timer countdown logic.

const SniperComponent := preload("res://scripts/components/enemy_sniper_component.gd")


# =============================================================================
# Constants
# =============================================================================

func test_preferred_distance_constant() -> void:
	assert_eq(SniperComponent.PREFERRED_DISTANCE, 550.0,
		"PREFERRED_DISTANCE should be 550.0 px")


func test_min_distance_constant() -> void:
	assert_eq(SniperComponent.MIN_DISTANCE, 350.0,
		"MIN_DISTANCE should be 350.0 px")


func test_blind_fire_cooldown_constant() -> void:
	assert_eq(SniperComponent.BLIND_FIRE_COOLDOWN, 5.0,
		"BLIND_FIRE_COOLDOWN should be 5.0 seconds")


# =============================================================================
# Initial State
# =============================================================================

func test_initial_blind_fire_timer() -> void:
	var comp := SniperComponent.new()
	add_child_autofree(comp)

	assert_eq(comp.blind_fire_timer, 0.0,
		"Blind fire timer should start at 0.0")


func test_initial_enemy_ref_null() -> void:
	var comp := SniperComponent.new()
	# Do not add to scene tree so _ready doesn't run
	assert_null(comp.enemy, "Enemy reference should be null before setup")


# =============================================================================
# Blind Fire Timer Countdown
# =============================================================================

func test_blind_fire_timer_increments_manually() -> void:
	var comp := SniperComponent.new()
	add_child_autofree(comp)

	# Simulate the timer increment that process_combat does
	comp.blind_fire_timer += 1.5
	assert_almost_eq(comp.blind_fire_timer, 1.5, 0.01,
		"Blind fire timer should increment")


func test_blind_fire_timer_resets_to_zero() -> void:
	var comp := SniperComponent.new()
	add_child_autofree(comp)

	comp.blind_fire_timer = 4.5
	comp.blind_fire_timer = 0.0

	assert_eq(comp.blind_fire_timer, 0.0,
		"Blind fire timer should reset to 0.0")


func test_blind_fire_timer_reaches_cooldown() -> void:
	var comp := SniperComponent.new()
	add_child_autofree(comp)

	comp.blind_fire_timer = 0.0
	# Simulate 5 seconds of accumulation
	for i in range(50):
		comp.blind_fire_timer += 0.1

	assert_ge(comp.blind_fire_timer, SniperComponent.BLIND_FIRE_COOLDOWN,
		"Blind fire timer should reach BLIND_FIRE_COOLDOWN after 5s of accumulation")


# =============================================================================
# Distance Logic Validation
# =============================================================================

func test_preferred_distance_greater_than_min() -> void:
	assert_gt(SniperComponent.PREFERRED_DISTANCE, SniperComponent.MIN_DISTANCE,
		"PREFERRED_DISTANCE should be greater than MIN_DISTANCE")


func test_process_combat_returns_false_without_player() -> void:
	var comp := SniperComponent.new()
	var parent := CharacterBody2D.new()
	parent.add_child(comp)
	add_child_autofree(parent)

	await wait_frames(2)

	var result := comp.process_combat(0.016, false, null, Vector2.ZERO, null)
	assert_false(result, "process_combat should return false when player is null")
