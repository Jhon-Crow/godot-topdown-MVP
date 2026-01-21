extends Node
## Autoload singleton for managing score calculation and tracking.
##
## Implements a Hotline Miami-inspired scoring system with:
## - Combo system: Consecutive kills within a time window multiply score
## - Time bonus: Fast completion rewards players
## - Accuracy bonus: Higher hit rate = more points
## - Damage penalty: Taking hits reduces final score
## - Aggressiveness: Kills per second bonus for fast-paced play
## - Grade system: S, A+, A, B, C, D, F based on performance

## Score tracking
var _base_kill_points: int = 0
var _combo_bonus_points: int = 0
var _time_bonus_points: int = 0
var _accuracy_bonus_points: int = 0
var _aggressiveness_bonus_points: int = 0
var _damage_penalty_points: int = 0
var _ricochet_bonus_points: int = 0
var _penetration_bonus_points: int = 0
var _total_score: int = 0

## Ricochet/Penetration kill tracking
var _ricochet_kills: int = 0
var _penetration_kills: int = 0
var _total_kills_for_aggressiveness: int = 0

## Combo tracking
var _current_combo: int = 0
var _max_combo: int = 0
var _combo_timer: float = 0.0
var _combo_active: bool = false

## Time tracking
var _level_start_time: float = 0.0
var _level_end_time: float = 0.0
var _is_tracking: bool = false

## Damage tracking
var _damage_taken: int = 0

## Constants for scoring (inspired by Hotline Miami)
## Base points per kill
const BASE_KILL_POINTS: int = 100

## Combo time window in seconds (time to get next kill to keep combo)
const COMBO_WINDOW: float = 2.5

## Combo bonus multiplier table - points awarded for reaching combo levels
## Formula: combo_level * combo_level * 50 (quadratic scaling)
## Example: 2x combo = 200pts, 5x combo = 1250pts, 10x combo = 5000pts
const COMBO_MULTIPLIER_BASE: int = 50

## Time bonus parameters (reduced weight to prioritize accuracy)
## Maximum time bonus points
const TIME_BONUS_MAX: int = 5000
## Time in seconds when time bonus reaches 0
const TIME_BONUS_ZERO_AT: float = 300.0

## Accuracy bonus parameters (increased weight to prioritize precision)
## Points per accuracy percentage (max 100% = 15000 points)
const ACCURACY_POINTS_PER_PERCENT: int = 150

## Aggressiveness bonus parameters
## Points per kill per minute rate
const AGGRESSIVENESS_POINTS_PER_KPM: int = 100
## Maximum aggressiveness bonus
const AGGRESSIVENESS_MAX: int = 5000

## Damage penalty parameters
## Points lost per hit taken
const DAMAGE_PENALTY_PER_HIT: int = 500

## Ricochet kill bonus parameters
## Base points for a ricochet kill (bullet bounced off wall before hitting)
const RICOCHET_KILL_BASE_BONUS: int = 300
## Ricochet bonus requires aggressive play: minimum kills per minute to receive bonus
const RICOCHET_MIN_AGGRESSIVENESS: float = 15.0  # 15 kills per minute = aggressive

## Penetration kill bonus parameters
## Base points for a wall penetration kill (bullet went through wall before hitting)
const PENETRATION_KILL_BASE_BONUS: int = 250
## Penetration bonus requires aggressive play: minimum kills per minute to receive bonus
const PENETRATION_MIN_AGGRESSIVENESS: float = 15.0  # 15 kills per minute = aggressive

## Grade thresholds (percentage of theoretical maximum score)
## Theoretical max varies by level, so we use relative thresholds
const GRADE_THRESHOLDS: Dictionary = {
	"S": 0.95,   # 95%+ of max possible (perfect play)
	"A+": 0.88,  # 88-95%
	"A": 0.78,   # 78-88%
	"B": 0.65,   # 65-78%
	"C": 0.50,   # 50-65%
	"D": 0.35,   # 35-50%
	# Below 35% = F
}

## Signal emitted when combo changes
signal combo_changed(combo: int, is_active: bool)

## Signal emitted when score is calculated
signal score_calculated(total_score: int, grade: String)

## Signal emitted when a kill contributes to score
signal kill_scored(points: int, combo: int)


func _ready() -> void:
	_reset_all()


func _process(delta: float) -> void:
	if _combo_active:
		_combo_timer -= delta
		if _combo_timer <= 0.0:
			_end_combo()


## Reset all score tracking for a new level
func reset_for_new_level() -> void:
	_reset_all()
	_level_start_time = Time.get_ticks_msec() / 1000.0
	_is_tracking = true


## Internal reset function
func _reset_all() -> void:
	_base_kill_points = 0
	_combo_bonus_points = 0
	_time_bonus_points = 0
	_accuracy_bonus_points = 0
	_aggressiveness_bonus_points = 0
	_damage_penalty_points = 0
	_ricochet_bonus_points = 0
	_penetration_bonus_points = 0
	_total_score = 0
	_current_combo = 0
	_max_combo = 0
	_combo_timer = 0.0
	_combo_active = false
	_level_start_time = 0.0
	_ricochet_kills = 0
	_penetration_kills = 0
	_total_kills_for_aggressiveness = 0
	_level_end_time = 0.0
	_is_tracking = false
	_damage_taken = 0


## Register a kill for scoring (basic version for backwards compatibility)
func register_kill() -> void:
	register_kill_extended(false, false)


## Register a kill for scoring with ricochet/penetration info.
## Ricochet and penetration bonuses are only awarded during aggressive play.
## @param is_ricochet_kill: True if the killing bullet ricocheted before hitting.
## @param is_penetration_kill: True if the killing bullet penetrated a wall before hitting.
func register_kill_extended(is_ricochet_kill: bool, is_penetration_kill: bool) -> void:
	if not _is_tracking:
		return

	# Track total kills for aggressiveness calculation
	_total_kills_for_aggressiveness += 1

	# Add base kill points
	_base_kill_points += BASE_KILL_POINTS

	# Update combo
	_current_combo += 1
	if _current_combo > _max_combo:
		_max_combo = _current_combo

	# Calculate combo bonus (quadratic scaling)
	var combo_bonus := _current_combo * _current_combo * COMBO_MULTIPLIER_BASE
	_combo_bonus_points += combo_bonus

	# Calculate current aggressiveness (kills per minute)
	var elapsed_time := get_elapsed_time()
	var current_aggressiveness := 0.0
	if elapsed_time > 0.0:
		current_aggressiveness = (float(_total_kills_for_aggressiveness) / elapsed_time) * 60.0

	# Ricochet bonus - only awarded if playing aggressively
	var ricochet_bonus := 0
	if is_ricochet_kill:
		_ricochet_kills += 1
		if current_aggressiveness >= RICOCHET_MIN_AGGRESSIVENESS:
			ricochet_bonus = RICOCHET_KILL_BASE_BONUS
			_ricochet_bonus_points += ricochet_bonus
			print("[ScoreManager] Ricochet kill bonus +%d (aggressiveness: %.1f/min)" % [ricochet_bonus, current_aggressiveness])

	# Penetration bonus - only awarded if playing aggressively
	var penetration_bonus := 0
	if is_penetration_kill:
		_penetration_kills += 1
		if current_aggressiveness >= PENETRATION_MIN_AGGRESSIVENESS:
			penetration_bonus = PENETRATION_KILL_BASE_BONUS
			_penetration_bonus_points += penetration_bonus
			print("[ScoreManager] Penetration kill bonus +%d (aggressiveness: %.1f/min)" % [penetration_bonus, current_aggressiveness])

	# Reset combo timer
	_combo_timer = COMBO_WINDOW
	_combo_active = true

	# Emit signals (total bonus includes ricochet and penetration)
	var total_kill_bonus := BASE_KILL_POINTS + combo_bonus + ricochet_bonus + penetration_bonus
	combo_changed.emit(_current_combo, true)
	kill_scored.emit(total_kill_bonus, _current_combo)


## Register damage taken by player
func register_damage() -> void:
	if not _is_tracking:
		return

	_damage_taken += 1
	_damage_penalty_points += DAMAGE_PENALTY_PER_HIT


## End the current combo
func _end_combo() -> void:
	_combo_active = false
	_current_combo = 0
	_combo_timer = 0.0
	combo_changed.emit(0, false)


## Calculate final score at level completion
## shots_fired: total shots fired during level
## hits_landed: total hits landed during level
## total_kills: total enemies killed
## Returns: Dictionary with score breakdown and grade
func calculate_final_score(shots_fired: int, hits_landed: int, total_kills: int) -> Dictionary:
	if not _is_tracking:
		return _create_empty_result()

	_level_end_time = Time.get_ticks_msec() / 1000.0
	var completion_time := _level_end_time - _level_start_time

	# Calculate time bonus (linear decay from max to 0)
	if completion_time < TIME_BONUS_ZERO_AT:
		var time_ratio := 1.0 - (completion_time / TIME_BONUS_ZERO_AT)
		_time_bonus_points = int(TIME_BONUS_MAX * time_ratio)
	else:
		_time_bonus_points = 0

	# Calculate accuracy bonus
	var accuracy := 0.0
	if shots_fired > 0:
		accuracy = (float(hits_landed) / float(shots_fired)) * 100.0
	_accuracy_bonus_points = int(accuracy * ACCURACY_POINTS_PER_PERCENT)

	# Calculate aggressiveness bonus (kills per minute)
	var kills_per_minute := 0.0
	if completion_time > 0.0:
		kills_per_minute = (float(total_kills) / completion_time) * 60.0
	_aggressiveness_bonus_points = mini(
		int(kills_per_minute * AGGRESSIVENESS_POINTS_PER_KPM),
		AGGRESSIVENESS_MAX
	)

	# Calculate total score (including ricochet and penetration bonuses)
	_total_score = (
		_base_kill_points +
		_combo_bonus_points +
		_time_bonus_points +
		_accuracy_bonus_points +
		_aggressiveness_bonus_points +
		_ricochet_bonus_points +
		_penetration_bonus_points -
		_damage_penalty_points
	)

	# Ensure score doesn't go negative
	if _total_score < 0:
		_total_score = 0

	# Calculate grade
	var grade := _calculate_grade(total_kills, completion_time, accuracy)

	# Create result dictionary
	var result := {
		"base_kill_points": _base_kill_points,
		"combo_bonus_points": _combo_bonus_points,
		"time_bonus_points": _time_bonus_points,
		"accuracy_bonus_points": _accuracy_bonus_points,
		"aggressiveness_bonus_points": _aggressiveness_bonus_points,
		"ricochet_bonus_points": _ricochet_bonus_points,
		"penetration_bonus_points": _penetration_bonus_points,
		"damage_penalty_points": _damage_penalty_points,
		"total_score": _total_score,
		"grade": grade,
		"max_combo": _max_combo,
		"completion_time": completion_time,
		"accuracy": accuracy,
		"damage_taken": _damage_taken,
		"kills_per_minute": kills_per_minute,
		"ricochet_kills": _ricochet_kills,
		"penetration_kills": _penetration_kills,
	}

	score_calculated.emit(_total_score, grade)

	return result


## Calculate grade based on performance
func _calculate_grade(total_kills: int, completion_time: float, accuracy: float) -> String:
	# Calculate theoretical maximum score for this level
	# Assumes perfect play: all kills in one combo, max time bonus, 100% accuracy, max aggressiveness, no damage

	# Perfect combo bonus (all kills in sequence)
	var perfect_combo_bonus := 0
	for i in range(1, total_kills + 1):
		perfect_combo_bonus += i * i * COMBO_MULTIPLIER_BASE

	var theoretical_max := (
		total_kills * BASE_KILL_POINTS +  # Base kill points
		perfect_combo_bonus +  # Perfect combo
		TIME_BONUS_MAX +  # Max time bonus
		100 * ACCURACY_POINTS_PER_PERCENT +  # 100% accuracy
		AGGRESSIVENESS_MAX  # Max aggressiveness
	)

	if theoretical_max <= 0:
		return "F"

	var score_ratio := float(_total_score) / float(theoretical_max)

	# Determine grade based on thresholds
	if score_ratio >= GRADE_THRESHOLDS["S"]:
		return "S"
	elif score_ratio >= GRADE_THRESHOLDS["A+"]:
		return "A+"
	elif score_ratio >= GRADE_THRESHOLDS["A"]:
		return "A"
	elif score_ratio >= GRADE_THRESHOLDS["B"]:
		return "B"
	elif score_ratio >= GRADE_THRESHOLDS["C"]:
		return "C"
	elif score_ratio >= GRADE_THRESHOLDS["D"]:
		return "D"
	else:
		return "F"


## Create empty result for when tracking is not active
func _create_empty_result() -> Dictionary:
	return {
		"base_kill_points": 0,
		"combo_bonus_points": 0,
		"time_bonus_points": 0,
		"accuracy_bonus_points": 0,
		"aggressiveness_bonus_points": 0,
		"ricochet_bonus_points": 0,
		"penetration_bonus_points": 0,
		"damage_penalty_points": 0,
		"total_score": 0,
		"grade": "F",
		"max_combo": 0,
		"completion_time": 0.0,
		"accuracy": 0.0,
		"damage_taken": 0,
		"kills_per_minute": 0.0,
		"ricochet_kills": 0,
		"penetration_kills": 0,
	}


## Get current combo count
func get_current_combo() -> int:
	return _current_combo


## Get max combo achieved
func get_max_combo() -> int:
	return _max_combo


## Check if combo is active
func is_combo_active() -> bool:
	return _combo_active


## Get remaining combo time
func get_combo_time_remaining() -> float:
	return _combo_timer


## Get total score so far (before final calculation)
func get_running_score() -> int:
	return _base_kill_points + _combo_bonus_points + _ricochet_bonus_points + _penetration_bonus_points - _damage_penalty_points


## Get damage taken count
func get_damage_taken() -> int:
	return _damage_taken


## Get elapsed time since level start
func get_elapsed_time() -> float:
	if not _is_tracking:
		return 0.0
	return (Time.get_ticks_msec() / 1000.0) - _level_start_time


## Format time as MM:SS.ms
func format_time(seconds: float) -> String:
	var minutes := int(seconds) / 60
	var secs := int(seconds) % 60
	var ms := int((seconds - int(seconds)) * 100)
	return "%02d:%02d.%02d" % [minutes, secs, ms]


## Format score with thousands separator
func format_score(score: int) -> String:
	var score_str := str(abs(score))
	var result := ""
	var count := 0
	for i in range(score_str.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = "," + result
		result = score_str[i] + result
		count += 1
	if score < 0:
		result = "-" + result
	return result
