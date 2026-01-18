extends GutTest
## Unit tests for the ScoreManager autoload.
##
## Tests combo system, score calculation, time bonus, accuracy bonus,
## aggressiveness bonus, damage penalty, and grade calculation.


var _score_manager: Node = null


func before_each() -> void:
	# Create a fresh ScoreManager instance for each test
	_score_manager = load("res://scripts/autoload/score_manager.gd").new()
	add_child(_score_manager)


func after_each() -> void:
	if _score_manager:
		_score_manager.queue_free()
		_score_manager = null


## Test initial state after reset
func test_initial_state() -> void:
	_score_manager.reset_for_new_level()

	assert_eq(_score_manager.get_current_combo(), 0, "Initial combo should be 0")
	assert_eq(_score_manager.get_max_combo(), 0, "Initial max combo should be 0")
	assert_false(_score_manager.is_combo_active(), "Combo should not be active initially")
	assert_eq(_score_manager.get_running_score(), 0, "Initial running score should be 0")
	assert_eq(_score_manager.get_damage_taken(), 0, "Initial damage taken should be 0")


## Test single kill scoring
func test_single_kill() -> void:
	_score_manager.reset_for_new_level()
	_score_manager.register_kill()

	assert_eq(_score_manager.get_current_combo(), 1, "Combo should be 1 after first kill")
	assert_eq(_score_manager.get_max_combo(), 1, "Max combo should be 1")
	assert_true(_score_manager.is_combo_active(), "Combo should be active after kill")
	# Base kill: 100 + combo bonus (1*1*50 = 50) = 150
	assert_eq(_score_manager.get_running_score(), 150, "Running score should be 150 after first kill")


## Test combo building
func test_combo_building() -> void:
	_score_manager.reset_for_new_level()

	# Kill 1: 100 base + 50 combo (1*1*50) = 150
	_score_manager.register_kill()
	assert_eq(_score_manager.get_current_combo(), 1)
	assert_eq(_score_manager.get_running_score(), 150)

	# Kill 2: 100 base + 200 combo (2*2*50) = 300, total = 450
	_score_manager.register_kill()
	assert_eq(_score_manager.get_current_combo(), 2)
	assert_eq(_score_manager.get_running_score(), 450)

	# Kill 3: 100 base + 450 combo (3*3*50) = 550, total = 1000
	_score_manager.register_kill()
	assert_eq(_score_manager.get_current_combo(), 3)
	assert_eq(_score_manager.get_running_score(), 1000)


## Test combo quadratic scaling
func test_combo_quadratic_scaling() -> void:
	_score_manager.reset_for_new_level()

	# Register 10 kills in a combo
	for i in range(10):
		_score_manager.register_kill()

	assert_eq(_score_manager.get_current_combo(), 10, "Combo should be 10")
	assert_eq(_score_manager.get_max_combo(), 10, "Max combo should be 10")

	# Calculate expected score:
	# Base kills: 10 * 100 = 1000
	# Combo bonuses: sum of (i^2 * 50) for i=1 to 10
	# = 50 * (1 + 4 + 9 + 16 + 25 + 36 + 49 + 64 + 81 + 100)
	# = 50 * 385 = 19250
	# Total = 1000 + 19250 = 20250
	assert_eq(_score_manager.get_running_score(), 20250, "Running score should be 20250 for 10-kill combo")


## Test damage penalty
func test_damage_penalty() -> void:
	_score_manager.reset_for_new_level()

	# Get 3 kills first
	_score_manager.register_kill()
	_score_manager.register_kill()
	_score_manager.register_kill()

	var score_before_damage := _score_manager.get_running_score()
	assert_eq(score_before_damage, 1000, "Score before damage should be 1000")

	# Take damage
	_score_manager.register_damage()
	assert_eq(_score_manager.get_damage_taken(), 1, "Damage taken should be 1")

	# Running score should be reduced by 500 (DAMAGE_PENALTY_PER_HIT)
	assert_eq(_score_manager.get_running_score(), 500, "Score after 1 hit should be 500")

	# Take more damage
	_score_manager.register_damage()
	_score_manager.register_damage()
	assert_eq(_score_manager.get_damage_taken(), 3, "Damage taken should be 3")
	assert_eq(_score_manager.get_running_score(), -500, "Score can go negative from damage")


## Test time formatting
func test_format_time() -> void:
	_score_manager.reset_for_new_level()

	assert_eq(_score_manager.format_time(0.0), "00:00.00")
	assert_eq(_score_manager.format_time(5.5), "00:05.50")
	assert_eq(_score_manager.format_time(65.25), "01:05.25")
	assert_eq(_score_manager.format_time(3661.99), "61:01.99")


## Test score formatting
func test_format_score() -> void:
	_score_manager.reset_for_new_level()

	assert_eq(_score_manager.format_score(0), "0")
	assert_eq(_score_manager.format_score(999), "999")
	assert_eq(_score_manager.format_score(1000), "1,000")
	assert_eq(_score_manager.format_score(1234567), "1,234,567")
	assert_eq(_score_manager.format_score(-5000), "-5,000")


## Test final score calculation with perfect play
func test_final_score_perfect_play() -> void:
	_score_manager.reset_for_new_level()

	# Simulate 10 kills in quick succession
	for i in range(10):
		_score_manager.register_kill()

	# Wait a tiny bit (simulate fast completion)
	await get_tree().create_timer(0.1).timeout

	# Calculate final score: 10 kills, 10 shots, 10 hits (100% accuracy)
	var result := _score_manager.calculate_final_score(10, 10, 10)

	assert_eq(result.max_combo, 10, "Max combo should be 10")
	assert_eq(result.accuracy, 100.0, "Accuracy should be 100%")
	assert_eq(result.damage_taken, 0, "Damage taken should be 0")
	assert_true(result.total_score > 0, "Total score should be positive")
	assert_true(result.time_bonus_points > 8000, "Time bonus should be high for fast completion")
	assert_eq(result.accuracy_bonus_points, 10000, "Accuracy bonus should be 10000 for 100%")


## Test final score calculation with poor play
func test_final_score_poor_play() -> void:
	_score_manager.reset_for_new_level()

	# Simulate 5 kills with lots of damage taken
	for i in range(5):
		_score_manager.register_kill()
		_score_manager.register_damage()

	# Calculate final score: 5 kills, 100 shots, 5 hits (5% accuracy)
	var result := _score_manager.calculate_final_score(100, 5, 5)

	assert_eq(result.max_combo, 5, "Max combo should be 5")
	assert_eq(result.accuracy, 5.0, "Accuracy should be 5%")
	assert_eq(result.damage_taken, 5, "Damage taken should be 5")
	assert_eq(result.damage_penalty_points, 2500, "Damage penalty should be 2500")
	assert_eq(result.accuracy_bonus_points, 500, "Accuracy bonus should be 500 for 5%")


## Test grade calculation
func test_grade_calculation() -> void:
	_score_manager.reset_for_new_level()

	# Perfect 10-kill combo
	for i in range(10):
		_score_manager.register_kill()

	await get_tree().create_timer(0.05).timeout

	# Perfect accuracy
	var result := _score_manager.calculate_final_score(10, 10, 10)

	# With perfect play, should get A+ or A grade
	assert_true(
		result.grade == "A+" or result.grade == "A",
		"Perfect play should get A+ or A grade, got: " + result.grade
	)


## Test grade thresholds
func test_grade_thresholds() -> void:
	_score_manager.reset_for_new_level()

	# Single kill, poor play
	_score_manager.register_kill()

	# Take lots of damage
	for i in range(10):
		_score_manager.register_damage()

	var result := _score_manager.calculate_final_score(100, 1, 1)

	# With terrible play, should get low grade (D or F)
	assert_true(
		result.grade == "D" or result.grade == "F",
		"Poor play should get D or F grade, got: " + result.grade
	)


## Test combo timer expiration
func test_combo_timer_expiration() -> void:
	_score_manager.reset_for_new_level()

	_score_manager.register_kill()
	assert_eq(_score_manager.get_current_combo(), 1)
	assert_true(_score_manager.is_combo_active())

	# Wait for combo to expire (COMBO_WINDOW = 2.5 seconds)
	await get_tree().create_timer(3.0).timeout

	assert_eq(_score_manager.get_current_combo(), 0, "Combo should reset after timeout")
	assert_false(_score_manager.is_combo_active(), "Combo should not be active after timeout")
	# Max combo should still be 1
	assert_eq(_score_manager.get_max_combo(), 1, "Max combo should still be 1")


## Test multiple combos (max combo tracking)
func test_multiple_combos_max_tracking() -> void:
	_score_manager.reset_for_new_level()

	# First combo: 3 kills
	_score_manager.register_kill()
	_score_manager.register_kill()
	_score_manager.register_kill()
	assert_eq(_score_manager.get_max_combo(), 3)

	# Wait for combo to expire
	await get_tree().create_timer(3.0).timeout
	assert_eq(_score_manager.get_current_combo(), 0)

	# Second combo: 5 kills
	for i in range(5):
		_score_manager.register_kill()

	assert_eq(_score_manager.get_current_combo(), 5)
	assert_eq(_score_manager.get_max_combo(), 5, "Max combo should be 5 now")


## Test time bonus decay
func test_time_bonus_decay() -> void:
	_score_manager.reset_for_new_level()
	_score_manager.register_kill()

	# Fast completion (within 1 second)
	await get_tree().create_timer(0.5).timeout
	var fast_result := _score_manager.calculate_final_score(1, 1, 1)

	# Reset for slow test
	_score_manager.reset_for_new_level()
	_score_manager.register_kill()

	# Slow completion (5 seconds)
	await get_tree().create_timer(5.0).timeout
	var slow_result := _score_manager.calculate_final_score(1, 1, 1)

	assert_true(
		fast_result.time_bonus_points > slow_result.time_bonus_points,
		"Fast completion should have higher time bonus"
	)


## Test aggressiveness bonus
func test_aggressiveness_bonus() -> void:
	_score_manager.reset_for_new_level()

	# 10 kills in 1 second = 600 kills per minute
	for i in range(10):
		_score_manager.register_kill()

	await get_tree().create_timer(1.0).timeout

	var result := _score_manager.calculate_final_score(10, 10, 10)

	# 600 KPM * 100 points = 60000, but capped at 5000 (AGGRESSIVENESS_MAX)
	assert_eq(result.aggressiveness_bonus_points, 5000, "Aggressiveness should be capped at 5000")
	assert_true(result.kills_per_minute > 500, "KPM should be very high")


## Test score doesn't go negative
func test_score_minimum_zero() -> void:
	_score_manager.reset_for_new_level()

	# Just take damage without any kills
	for i in range(100):
		_score_manager.register_damage()

	var result := _score_manager.calculate_final_score(10, 0, 0)

	assert_eq(result.total_score, 0, "Total score should not go below 0")


## Test empty result when tracking not started
func test_empty_result_no_tracking() -> void:
	# Don't call reset_for_new_level()
	var result := _score_manager.calculate_final_score(10, 10, 10)

	assert_eq(result.total_score, 0, "Score should be 0 when tracking not started")
	assert_eq(result.grade, "F", "Grade should be F when tracking not started")


## Test signals emission
func test_combo_changed_signal() -> void:
	_score_manager.reset_for_new_level()

	var combo_received := 0
	var is_active_received := false

	_score_manager.combo_changed.connect(func(combo: int, is_active: bool):
		combo_received = combo
		is_active_received = is_active
	)

	_score_manager.register_kill()

	assert_eq(combo_received, 1, "Should receive combo 1")
	assert_true(is_active_received, "Should receive is_active = true")


## Test kill_scored signal
func test_kill_scored_signal() -> void:
	_score_manager.reset_for_new_level()

	var points_received := 0
	var combo_received := 0

	_score_manager.kill_scored.connect(func(points: int, combo: int):
		points_received = points
		combo_received = combo
	)

	_score_manager.register_kill()

	# First kill: 100 base + 50 combo = 150 points
	assert_eq(points_received, 150, "Should receive 150 points for first kill")
	assert_eq(combo_received, 1, "Should receive combo 1")
