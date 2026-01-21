extends GutTest
## Unit tests for ScoreManager functionality.
##
## Tests the score calculation, combo system, rank determination, and tracking logic.
## Note: These tests focus on the pure calculation methods that can be tested
## without requiring the full Godot scene tree.


# We test the ScoreManager logic by creating a mock instance
# that mirrors the core functionality


class MockScoreManager:
	## Mock class that mirrors ScoreManager's testable functionality

	# Constants (matching ScoreManager)
	const COMBO_TIMEOUT: float = 2.0
	const POINTS_PER_KILL: int = 100
	const TIME_BONUS_MAX: int = 5000
	const TIME_BONUS_DURATION: float = 120.0
	const ACCURACY_BONUS_MAX: int = 2000
	const DAMAGE_PENALTY_PER_HIT: int = 200
	const RICOCHET_KILL_BONUS: int = 150
	const PENETRATION_KILL_BONUS: int = 150
	const AGGRESSIVENESS_THRESHOLD: float = 0.4
	const RANK_THRESHOLDS: Dictionary = {
		"S": 1.0,
		"A+": 0.85,
		"A": 0.70,
		"B": 0.55,
		"C": 0.40,
		"D": 0.25,
		"F": 0.0
	}

	# State variables
	var _level_start_time: float = 0.0
	var _level_completion_time: float = 0.0
	var _damage_taken: int = 0
	var _total_enemies: int = 0
	var _total_kills: int = 0
	var _current_combo: int = 0
	var _max_combo: int = 0
	var _combo_timer: float = 0.0
	var _combo_points: int = 0
	var _ricochet_kills: int = 0
	var _penetration_kills: int = 0
	var _time_moving_toward_enemies: float = 0.0
	var _total_combat_time: float = 0.0
	var _in_combat: bool = false
	var _level_active: bool = false

	# Mock accuracy values (since we don't have GameManager)
	var mock_accuracy: float = 0.0
	var mock_shots_fired: int = 0
	var mock_hits_landed: int = 0


	func start_level(total_enemies: int) -> void:
		_level_start_time = 0.0
		_level_completion_time = 0.0
		_damage_taken = 0
		_total_enemies = total_enemies
		_total_kills = 0
		_current_combo = 0
		_max_combo = 0
		_combo_timer = 0.0
		_combo_points = 0
		_ricochet_kills = 0
		_penetration_kills = 0
		_time_moving_toward_enemies = 0.0
		_total_combat_time = 0.0
		_in_combat = false
		_level_active = true


	func register_damage_taken(amount: int = 1) -> void:
		_damage_taken += amount


	func register_kill(is_ricochet_kill: bool = false, is_penetration_kill: bool = false) -> void:
		_total_kills += 1

		if is_ricochet_kill:
			_ricochet_kills += 1
		if is_penetration_kill:
			_penetration_kills += 1

		_current_combo += 1
		_combo_timer = 0.0

		if _current_combo > _max_combo:
			_max_combo = _current_combo

		# Calculate combo points using exponential formula
		var combo_score := 250 * (_current_combo * _current_combo) + 250 * _current_combo
		_combo_points += combo_score


	func _end_combo() -> void:
		if _current_combo > 0:
			_current_combo = 0


	func enter_combat() -> void:
		_in_combat = true


	func exit_combat() -> void:
		_in_combat = false


	func set_aggressiveness(time_toward: float, total_time: float) -> void:
		_time_moving_toward_enemies = time_toward
		_total_combat_time = total_time


	func get_aggressiveness() -> float:
		if _total_combat_time <= 0.0:
			return 0.0
		return _time_moving_toward_enemies / _total_combat_time


	func calculate_score() -> Dictionary:
		var accuracy: float = mock_accuracy
		var shots_fired: int = mock_shots_fired
		var hits_landed: int = mock_hits_landed

		# Calculate base kill points
		var kill_points: int = _total_kills * POINTS_PER_KILL

		# Calculate time bonus (decreases over time)
		var time_factor: float = maxf(0.0, 1.0 - (_level_completion_time / TIME_BONUS_DURATION))
		var time_bonus: int = int(TIME_BONUS_MAX * time_factor)

		# Calculate accuracy bonus
		var accuracy_bonus: int = int(ACCURACY_BONUS_MAX * (accuracy / 100.0))

		# Calculate damage penalty
		var damage_penalty: int = _damage_taken * DAMAGE_PENALTY_PER_HIT

		# Calculate special kill bonus (only if aggressive enough)
		var aggressiveness: float = get_aggressiveness()

		var special_kill_bonus: int = 0
		var special_kills_eligible: bool = aggressiveness >= AGGRESSIVENESS_THRESHOLD

		if special_kills_eligible:
			special_kill_bonus = (_ricochet_kills * RICOCHET_KILL_BONUS) + (_penetration_kills * PENETRATION_KILL_BONUS)

		# Calculate total score
		var total_score: int = kill_points + _combo_points + time_bonus + accuracy_bonus + special_kill_bonus - damage_penalty
		total_score = maxi(0, total_score)

		# Calculate maximum possible score
		var max_possible_score: int = _calculate_max_possible_score()

		# Determine rank
		var rank: String = _calculate_rank(total_score, max_possible_score)

		return {
			"total_score": total_score,
			"rank": rank,
			"kills": _total_kills,
			"total_enemies": _total_enemies,
			"kill_points": kill_points,
			"combo_points": _combo_points,
			"max_combo": _max_combo,
			"time_bonus": time_bonus,
			"completion_time": _level_completion_time,
			"accuracy_bonus": accuracy_bonus,
			"accuracy": accuracy,
			"shots_fired": shots_fired,
			"hits_landed": hits_landed,
			"damage_penalty": damage_penalty,
			"damage_taken": _damage_taken,
			"special_kill_bonus": special_kill_bonus,
			"ricochet_kills": _ricochet_kills,
			"penetration_kills": _penetration_kills,
			"aggressiveness": aggressiveness,
			"special_kills_eligible": special_kills_eligible,
			"max_possible_score": max_possible_score
		}


	func _calculate_max_possible_score() -> int:
		var max_kill_points: int = _total_enemies * POINTS_PER_KILL

		var max_combo_points: int = 0
		for i in range(1, _total_enemies + 1):
			max_combo_points += 250 * (i * i) + 250 * i

		var max_time_bonus: int = TIME_BONUS_MAX
		var max_accuracy_bonus: int = ACCURACY_BONUS_MAX
		var max_special_bonus: int = _total_enemies * (RICOCHET_KILL_BONUS + PENETRATION_KILL_BONUS)

		return max_kill_points + max_combo_points + max_time_bonus + max_accuracy_bonus + max_special_bonus


	func _calculate_rank(score: int, max_score: int) -> String:
		if max_score <= 0:
			return "F"

		var score_ratio: float = float(score) / float(max_score)

		if score_ratio >= RANK_THRESHOLDS["S"]:
			return "S"
		elif score_ratio >= RANK_THRESHOLDS["A+"]:
			return "A+"
		elif score_ratio >= RANK_THRESHOLDS["A"]:
			return "A"
		elif score_ratio >= RANK_THRESHOLDS["B"]:
			return "B"
		elif score_ratio >= RANK_THRESHOLDS["C"]:
			return "C"
		elif score_ratio >= RANK_THRESHOLDS["D"]:
			return "D"
		else:
			return "F"


	func reset() -> void:
		_level_start_time = 0.0
		_level_completion_time = 0.0
		_damage_taken = 0
		_total_enemies = 0
		_total_kills = 0
		_current_combo = 0
		_max_combo = 0
		_combo_timer = 0.0
		_combo_points = 0
		_ricochet_kills = 0
		_penetration_kills = 0
		_time_moving_toward_enemies = 0.0
		_total_combat_time = 0.0
		_in_combat = false
		_level_active = false
		mock_accuracy = 0.0
		mock_shots_fired = 0
		mock_hits_landed = 0


var score_manager: MockScoreManager


func before_each() -> void:
	score_manager = MockScoreManager.new()


func after_each() -> void:
	score_manager = null


# ============================================================================
# Initial State Tests
# ============================================================================


func test_initial_state_is_reset() -> void:
	assert_eq(score_manager._damage_taken, 0, "Initial damage should be 0")
	assert_eq(score_manager._total_kills, 0, "Initial kills should be 0")
	assert_eq(score_manager._current_combo, 0, "Initial combo should be 0")
	assert_eq(score_manager._max_combo, 0, "Initial max combo should be 0")
	assert_eq(score_manager._combo_points, 0, "Initial combo points should be 0")
	assert_eq(score_manager._ricochet_kills, 0, "Initial ricochet kills should be 0")
	assert_eq(score_manager._penetration_kills, 0, "Initial penetration kills should be 0")
	assert_false(score_manager._level_active, "Level should not be active initially")


func test_start_level_initializes_state() -> void:
	score_manager.start_level(10)

	assert_eq(score_manager._total_enemies, 10, "Total enemies should be set")
	assert_true(score_manager._level_active, "Level should be active after start")
	assert_eq(score_manager._damage_taken, 0, "Damage should be reset")
	assert_eq(score_manager._total_kills, 0, "Kills should be reset")


# ============================================================================
# Damage Tracking Tests
# ============================================================================


func test_register_damage_taken_increments() -> void:
	score_manager.register_damage_taken(1)

	assert_eq(score_manager._damage_taken, 1, "Damage should be 1 after one hit")


func test_register_multiple_damage() -> void:
	score_manager.register_damage_taken(1)
	score_manager.register_damage_taken(2)
	score_manager.register_damage_taken(1)

	assert_eq(score_manager._damage_taken, 4, "Damage should accumulate")


func test_damage_penalty_calculation() -> void:
	score_manager.start_level(5)
	score_manager.register_damage_taken(3)

	var score_data := score_manager.calculate_score()

	# 3 damage * 200 penalty = 600
	assert_eq(score_data.damage_penalty, 600, "Damage penalty should be 600 for 3 hits")


# ============================================================================
# Kill Tracking Tests
# ============================================================================


func test_register_kill_increments_count() -> void:
	score_manager.start_level(5)
	score_manager.register_kill()

	assert_eq(score_manager._total_kills, 1, "Kills should be 1 after one kill")


func test_register_multiple_kills() -> void:
	score_manager.start_level(5)
	score_manager.register_kill()
	score_manager.register_kill()
	score_manager.register_kill()

	assert_eq(score_manager._total_kills, 3, "Kills should be 3 after three kills")


func test_kill_points_calculation() -> void:
	score_manager.start_level(5)
	score_manager.register_kill()
	score_manager.register_kill()
	score_manager._end_combo()

	var score_data := score_manager.calculate_score()

	# 2 kills * 100 points = 200
	assert_eq(score_data.kill_points, 200, "Kill points should be 200 for 2 kills")


# ============================================================================
# Combo System Tests
# ============================================================================


func test_combo_increments_on_kills() -> void:
	score_manager.start_level(5)
	score_manager.register_kill()

	assert_eq(score_manager._current_combo, 1, "Combo should be 1 after first kill")

	score_manager.register_kill()

	assert_eq(score_manager._current_combo, 2, "Combo should be 2 after second kill")


func test_max_combo_tracks_highest() -> void:
	score_manager.start_level(10)
	score_manager.register_kill()
	score_manager.register_kill()
	score_manager.register_kill()  # Combo: 3
	score_manager._end_combo()
	score_manager.register_kill()
	score_manager.register_kill()  # Combo: 2
	score_manager._end_combo()

	assert_eq(score_manager._max_combo, 3, "Max combo should be 3")


func test_combo_points_formula() -> void:
	# Formula: 250 * combo^2 + 250 * combo
	# Kill 1: 250 * 1 + 250 = 500
	# Kill 2: 250 * 4 + 500 = 1500
	# Kill 3: 250 * 9 + 750 = 3000
	# Total: 5000

	score_manager.start_level(5)
	score_manager.register_kill()  # 500
	score_manager.register_kill()  # 1500
	score_manager.register_kill()  # 3000

	assert_eq(score_manager._combo_points, 5000, "Combo points should follow exponential formula")


func test_combo_points_single_kill() -> void:
	score_manager.start_level(5)
	score_manager.register_kill()

	# 250 * 1^2 + 250 * 1 = 500
	assert_eq(score_manager._combo_points, 500, "Single kill combo should be 500 points")


func test_combo_ends_resets_current() -> void:
	score_manager.start_level(5)
	score_manager.register_kill()
	score_manager.register_kill()
	score_manager._end_combo()

	assert_eq(score_manager._current_combo, 0, "Current combo should reset after end")
	assert_eq(score_manager._max_combo, 2, "Max combo should be preserved")


# ============================================================================
# Special Kills Tests
# ============================================================================


func test_ricochet_kill_tracked() -> void:
	score_manager.start_level(5)
	score_manager.register_kill(true, false)

	assert_eq(score_manager._ricochet_kills, 1, "Ricochet kills should be 1")
	assert_eq(score_manager._penetration_kills, 0, "Penetration kills should be 0")


func test_penetration_kill_tracked() -> void:
	score_manager.start_level(5)
	score_manager.register_kill(false, true)

	assert_eq(score_manager._ricochet_kills, 0, "Ricochet kills should be 0")
	assert_eq(score_manager._penetration_kills, 1, "Penetration kills should be 1")


func test_both_special_kills_tracked() -> void:
	score_manager.start_level(5)
	score_manager.register_kill(true, true)  # Both ricochet and penetration

	assert_eq(score_manager._ricochet_kills, 1, "Ricochet kills should be 1")
	assert_eq(score_manager._penetration_kills, 1, "Penetration kills should be 1")


func test_special_kills_bonus_requires_aggressiveness() -> void:
	score_manager.start_level(5)
	score_manager.register_kill(true, false)  # Ricochet kill
	score_manager.register_kill(false, true)  # Penetration kill
	score_manager._end_combo()

	# Low aggressiveness (30% < 40% threshold)
	score_manager.set_aggressiveness(3.0, 10.0)

	var score_data := score_manager.calculate_score()

	assert_eq(score_data.special_kill_bonus, 0, "Special bonus should be 0 with low aggressiveness")
	assert_false(score_data.special_kills_eligible, "Special kills should not be eligible")


func test_special_kills_bonus_with_sufficient_aggressiveness() -> void:
	score_manager.start_level(5)
	score_manager.register_kill(true, false)  # Ricochet kill
	score_manager.register_kill(false, true)  # Penetration kill
	score_manager._end_combo()

	# High aggressiveness (50% > 40% threshold)
	score_manager.set_aggressiveness(5.0, 10.0)

	var score_data := score_manager.calculate_score()

	# 1 ricochet * 150 + 1 penetration * 150 = 300
	assert_eq(score_data.special_kill_bonus, 300, "Special bonus should be 300")
	assert_true(score_data.special_kills_eligible, "Special kills should be eligible")


func test_special_kills_bonus_at_threshold() -> void:
	score_manager.start_level(5)
	score_manager.register_kill(true, false)
	score_manager._end_combo()

	# Exactly at threshold (40%)
	score_manager.set_aggressiveness(4.0, 10.0)

	var score_data := score_manager.calculate_score()

	assert_eq(score_data.special_kill_bonus, 150, "Special bonus should apply at exactly threshold")


# ============================================================================
# Aggressiveness Tracking Tests
# ============================================================================


func test_aggressiveness_calculation() -> void:
	score_manager.set_aggressiveness(6.0, 10.0)

	var aggressiveness := score_manager.get_aggressiveness()

	assert_almost_eq(aggressiveness, 0.6, 0.01, "Aggressiveness should be 60%")


func test_aggressiveness_zero_combat_time() -> void:
	score_manager.set_aggressiveness(0.0, 0.0)

	var aggressiveness := score_manager.get_aggressiveness()

	assert_eq(aggressiveness, 0.0, "Aggressiveness should be 0 with no combat time")


func test_combat_state_tracking() -> void:
	assert_false(score_manager._in_combat, "Should not be in combat initially")

	score_manager.enter_combat()
	assert_true(score_manager._in_combat, "Should be in combat after enter_combat")

	score_manager.exit_combat()
	assert_false(score_manager._in_combat, "Should not be in combat after exit_combat")


# ============================================================================
# Time Bonus Tests
# ============================================================================


func test_time_bonus_maximum_at_start() -> void:
	score_manager.start_level(5)
	score_manager._level_completion_time = 0.0

	var score_data := score_manager.calculate_score()

	assert_eq(score_data.time_bonus, 5000, "Time bonus should be max at 0 seconds")


func test_time_bonus_zero_after_duration() -> void:
	score_manager.start_level(5)
	score_manager._level_completion_time = 120.0  # Full duration

	var score_data := score_manager.calculate_score()

	assert_eq(score_data.time_bonus, 0, "Time bonus should be 0 after full duration")


func test_time_bonus_decreases_over_time() -> void:
	score_manager.start_level(5)
	score_manager._level_completion_time = 60.0  # Half duration

	var score_data := score_manager.calculate_score()

	# 50% of 5000 = 2500
	assert_eq(score_data.time_bonus, 2500, "Time bonus should be half at half duration")


func test_time_bonus_does_not_go_negative() -> void:
	score_manager.start_level(5)
	score_manager._level_completion_time = 240.0  # Double the duration

	var score_data := score_manager.calculate_score()

	assert_eq(score_data.time_bonus, 0, "Time bonus should not go negative")


# ============================================================================
# Accuracy Bonus Tests
# ============================================================================


func test_accuracy_bonus_100_percent() -> void:
	score_manager.start_level(5)
	score_manager.mock_accuracy = 100.0

	var score_data := score_manager.calculate_score()

	assert_eq(score_data.accuracy_bonus, 2000, "Accuracy bonus should be max at 100%")


func test_accuracy_bonus_50_percent() -> void:
	score_manager.start_level(5)
	score_manager.mock_accuracy = 50.0

	var score_data := score_manager.calculate_score()

	assert_eq(score_data.accuracy_bonus, 1000, "Accuracy bonus should be half at 50%")


func test_accuracy_bonus_zero_percent() -> void:
	score_manager.start_level(5)
	score_manager.mock_accuracy = 0.0

	var score_data := score_manager.calculate_score()

	assert_eq(score_data.accuracy_bonus, 0, "Accuracy bonus should be 0 at 0%")


# ============================================================================
# Rank Calculation Tests
# ============================================================================


func test_rank_f_for_low_score() -> void:
	var rank := score_manager._calculate_rank(100, 10000)  # 1%

	assert_eq(rank, "F", "Should get F rank for very low score")


func test_rank_d_for_25_percent() -> void:
	var rank := score_manager._calculate_rank(2500, 10000)  # 25%

	assert_eq(rank, "D", "Should get D rank for 25% score")


func test_rank_c_for_40_percent() -> void:
	var rank := score_manager._calculate_rank(4000, 10000)  # 40%

	assert_eq(rank, "C", "Should get C rank for 40% score")


func test_rank_b_for_55_percent() -> void:
	var rank := score_manager._calculate_rank(5500, 10000)  # 55%

	assert_eq(rank, "B", "Should get B rank for 55% score")


func test_rank_a_for_70_percent() -> void:
	var rank := score_manager._calculate_rank(7000, 10000)  # 70%

	assert_eq(rank, "A", "Should get A rank for 70% score")


func test_rank_a_plus_for_85_percent() -> void:
	var rank := score_manager._calculate_rank(8500, 10000)  # 85%

	assert_eq(rank, "A+", "Should get A+ rank for 85% score")


func test_rank_s_for_100_percent() -> void:
	var rank := score_manager._calculate_rank(10000, 10000)  # 100%

	assert_eq(rank, "S", "Should get S rank for 100% score")


func test_rank_f_for_zero_max_score() -> void:
	var rank := score_manager._calculate_rank(100, 0)

	assert_eq(rank, "F", "Should get F rank when max score is 0")


# ============================================================================
# Max Possible Score Calculation Tests
# ============================================================================


func test_max_possible_score_calculation() -> void:
	score_manager.start_level(3)  # 3 enemies

	var max_score := score_manager._calculate_max_possible_score()

	# Kill points: 3 * 100 = 300
	# Combo points: 500 + 1500 + 3000 = 5000
	# Time bonus: 5000
	# Accuracy bonus: 2000
	# Special bonus: 3 * (150 + 150) = 900
	# Total: 300 + 5000 + 5000 + 2000 + 900 = 13200

	assert_eq(max_score, 13200, "Max possible score should be 13200 for 3 enemies")


func test_max_possible_score_zero_enemies() -> void:
	score_manager.start_level(0)

	var max_score := score_manager._calculate_max_possible_score()

	# Only time and accuracy bonus possible
	# 0 + 0 + 5000 + 2000 + 0 = 7000
	assert_eq(max_score, 7000, "Max score with 0 enemies should be 7000")


# ============================================================================
# Total Score Calculation Tests
# ============================================================================


func test_total_score_does_not_go_negative() -> void:
	score_manager.start_level(5)
	score_manager.register_damage_taken(100)  # 100 * 200 = 20000 penalty

	var score_data := score_manager.calculate_score()

	assert_true(score_data.total_score >= 0, "Total score should not be negative")


func test_complete_score_calculation() -> void:
	score_manager.start_level(5)
	score_manager._level_completion_time = 30.0  # 75% of time bonus
	score_manager.mock_accuracy = 80.0
	score_manager.register_kill()  # 500 combo
	score_manager.register_kill()  # 1500 combo
	score_manager._end_combo()
	score_manager.register_damage_taken(1)
	score_manager.set_aggressiveness(5.0, 10.0)  # 50% aggressiveness

	var score_data := score_manager.calculate_score()

	# Kill points: 2 * 100 = 200
	# Combo points: 500 + 1500 = 2000
	# Time bonus: 5000 * 0.75 = 3750
	# Accuracy bonus: 2000 * 0.8 = 1600
	# Special kill bonus: 0 (no special kills)
	# Damage penalty: 1 * 200 = 200
	# Total: 200 + 2000 + 3750 + 1600 + 0 - 200 = 7350

	assert_eq(score_data.total_score, 7350, "Total score should be 7350")


# ============================================================================
# Reset Tests
# ============================================================================


func test_reset_clears_all_state() -> void:
	score_manager.start_level(10)
	score_manager.register_kill(true, true)
	score_manager.register_damage_taken(5)
	score_manager.set_aggressiveness(5.0, 10.0)

	score_manager.reset()

	assert_eq(score_manager._damage_taken, 0, "Damage should be reset")
	assert_eq(score_manager._total_kills, 0, "Kills should be reset")
	assert_eq(score_manager._current_combo, 0, "Combo should be reset")
	assert_eq(score_manager._max_combo, 0, "Max combo should be reset")
	assert_eq(score_manager._combo_points, 0, "Combo points should be reset")
	assert_eq(score_manager._ricochet_kills, 0, "Ricochet kills should be reset")
	assert_eq(score_manager._penetration_kills, 0, "Penetration kills should be reset")
	assert_eq(score_manager._total_enemies, 0, "Total enemies should be reset")
	assert_false(score_manager._level_active, "Level should not be active after reset")


# ============================================================================
# Score Data Dictionary Tests
# ============================================================================


func test_score_data_contains_all_fields() -> void:
	score_manager.start_level(5)
	score_manager.register_kill()

	var score_data := score_manager.calculate_score()

	assert_has(score_data, "total_score", "Should have total_score")
	assert_has(score_data, "rank", "Should have rank")
	assert_has(score_data, "kills", "Should have kills")
	assert_has(score_data, "total_enemies", "Should have total_enemies")
	assert_has(score_data, "kill_points", "Should have kill_points")
	assert_has(score_data, "combo_points", "Should have combo_points")
	assert_has(score_data, "max_combo", "Should have max_combo")
	assert_has(score_data, "time_bonus", "Should have time_bonus")
	assert_has(score_data, "completion_time", "Should have completion_time")
	assert_has(score_data, "accuracy_bonus", "Should have accuracy_bonus")
	assert_has(score_data, "accuracy", "Should have accuracy")
	assert_has(score_data, "shots_fired", "Should have shots_fired")
	assert_has(score_data, "hits_landed", "Should have hits_landed")
	assert_has(score_data, "damage_penalty", "Should have damage_penalty")
	assert_has(score_data, "damage_taken", "Should have damage_taken")
	assert_has(score_data, "special_kill_bonus", "Should have special_kill_bonus")
	assert_has(score_data, "ricochet_kills", "Should have ricochet_kills")
	assert_has(score_data, "penetration_kills", "Should have penetration_kills")
	assert_has(score_data, "aggressiveness", "Should have aggressiveness")
	assert_has(score_data, "special_kills_eligible", "Should have special_kills_eligible")
	assert_has(score_data, "max_possible_score", "Should have max_possible_score")


# ============================================================================
# Combined Scenario Tests
# ============================================================================


func test_perfect_run_scenario() -> void:
	score_manager.start_level(5)
	score_manager._level_completion_time = 0.0  # Instant completion
	score_manager.mock_accuracy = 100.0
	score_manager.set_aggressiveness(10.0, 10.0)  # 100% aggressive

	# All kills are special and in one combo
	for i in range(5):
		score_manager.register_kill(true, true)
	score_manager._end_combo()

	var score_data := score_manager.calculate_score()

	assert_eq(score_data.rank, "S", "Perfect run should get S rank")
	assert_eq(score_data.damage_taken, 0, "Perfect run should have no damage")
	assert_eq(score_data.max_combo, 5, "Perfect run should have max combo of 5")
	assert_true(score_data.special_kills_eligible, "Perfect run should be eligible for special bonus")


func test_terrible_run_scenario() -> void:
	score_manager.start_level(5)
	score_manager._level_completion_time = 240.0  # Took way too long
	score_manager.mock_accuracy = 10.0  # Very poor accuracy
	score_manager.set_aggressiveness(1.0, 10.0)  # Hiding a lot
	score_manager.register_damage_taken(10)  # Took lots of damage

	# Only killed 1 enemy
	score_manager.register_kill()
	score_manager._end_combo()

	var score_data := score_manager.calculate_score()

	assert_eq(score_data.rank, "F", "Terrible run should get F rank")
	assert_eq(score_data.time_bonus, 0, "No time bonus for slow run")
	assert_false(score_data.special_kills_eligible, "Should not be eligible with low aggressiveness")
