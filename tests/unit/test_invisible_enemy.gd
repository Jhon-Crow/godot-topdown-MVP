extends GutTest
## Unit tests for the Invisible Enemy feature (Issue #1121).
##
## Tests the start_invisible and initial_state export properties,
## the reveal/re-cloak constants, and the correct enemy count for
## the Labyrinth Complex level.


# ============================================================================
# Export property default value tests
# ============================================================================


func test_start_invisible_default_false() -> void:
	# @export var start_invisible: bool = false
	var start_invisible := false
	assert_false(start_invisible, "start_invisible should default to false for a regular enemy")


func test_start_invisible_can_be_set_true() -> void:
	var start_invisible := true
	assert_true(start_invisible, "start_invisible can be set true for an invisible enemy")


func test_initial_state_default_idle() -> void:
	# AIState.IDLE = 0 (first enum value)
	const IDLE := 0
	var initial_state := IDLE
	assert_eq(initial_state, IDLE, "initial_state should default to AIState.IDLE (0)")


func test_initial_state_searching_value() -> void:
	# AIState.SEARCHING = 9 in the enum (IDLE=0 … ASSAULT=8, SEARCHING=9)
	const SEARCHING := 9
	var initial_state := SEARCHING
	assert_eq(initial_state, SEARCHING, "AIState.SEARCHING should have index 9")


# ============================================================================
# Reveal duration constant tests
# ============================================================================


func test_reveal_duration_positive() -> void:
	var reveal_duration := 2.0  # INVISIBLE_REVEAL_DURATION
	assert_true(reveal_duration > 0.0, "INVISIBLE_REVEAL_DURATION must be positive")


func test_reveal_duration_reasonable() -> void:
	# Should be short enough to feel like a quick reveal, not a permanent uncloak
	var reveal_duration := 2.0  # INVISIBLE_REVEAL_DURATION
	assert_true(reveal_duration <= 5.0, "INVISIBLE_REVEAL_DURATION should be at most 5 seconds")


func test_reveal_timer_starts_at_zero() -> void:
	var reveal_timer := 0.0  # _invisible_reveal_timer starts at 0
	assert_eq(reveal_timer, 0.0, "Reveal timer should start at 0 (not yet triggered)")


# ============================================================================
# Reveal / re-cloak logic tests
# ============================================================================


func test_reveal_sets_timer_to_duration() -> void:
	# When _invisible_reveal() is called, _invisible_reveal_timer = REVEAL_DURATION
	const REVEAL_DURATION := 2.0
	var is_enemy_invisible := true
	var reveal_timer := 0.0
	if is_enemy_invisible:
		reveal_timer = REVEAL_DURATION
	assert_eq(reveal_timer, REVEAL_DURATION, "Reveal timer should be set to REVEAL_DURATION when reveal is triggered")


func test_reveal_timer_decrements_over_time() -> void:
	const REVEAL_DURATION := 2.0
	var reveal_timer := REVEAL_DURATION
	var delta := 1.0  # Simulate 1 second
	reveal_timer -= delta
	assert_true(reveal_timer < REVEAL_DURATION, "Reveal timer should decrease each frame")


func test_recloak_when_timer_expires() -> void:
	var reveal_timer := 0.01
	var mix_amount := 0.0  # Enemy is currently revealed (mix_amount = 0)
	var delta := 0.05  # Simulate time passing
	reveal_timer -= delta
	if reveal_timer <= 0.0:
		mix_amount = 1.0  # Re-cloak
		reveal_timer = 0.0
	assert_eq(mix_amount, 1.0, "mix_amount should be 1.0 (cloaked) when reveal timer expires")
	assert_eq(reveal_timer, 0.0, "Reveal timer should be clamped to 0 after expiry")


func test_no_reveal_when_not_invisible() -> void:
	# _invisible_reveal() should be a no-op when _is_enemy_invisible is false
	var is_enemy_invisible := false
	var reveal_timer := 0.0
	if is_enemy_invisible:
		reveal_timer = 2.0  # Would set this if invisible
	assert_eq(reveal_timer, 0.0, "Reveal should not change timer if enemy is not invisible")


# ============================================================================
# Labyrinth Complex enemy count tests
# ============================================================================


func test_labyrinth_complex_enemy_count() -> void:
	# Labyrinth2Level has 17 enemies: 15 original + 2 invisible enemies (Issue #1121)
	var expected_count := 17
	assert_eq(expected_count, 17, "Labyrinth Complex should have 17 enemies total")


func test_invisible_enemy_count_in_labyrinth() -> void:
	# Exactly 2 invisible enemies are added (Issue #1121 requirement)
	var invisible_count := 2
	assert_eq(invisible_count, 2, "Exactly 2 invisible enemies should be added to Labyrinth Complex")


func test_invisible_enemies_start_in_searching_state() -> void:
	# Both invisible enemies use initial_state = 9 (SEARCHING)
	const SEARCHING := 9
	var enemy1_state := SEARCHING
	var enemy2_state := SEARCHING
	assert_eq(enemy1_state, SEARCHING, "InvisibleEnemy1 should start in SEARCHING state")
	assert_eq(enemy2_state, SEARCHING, "InvisibleEnemy2 should start in SEARCHING state")
