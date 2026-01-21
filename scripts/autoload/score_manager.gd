extends Node
## Autoload singleton for managing score calculations after level completion.
##
## Tracks player performance metrics and calculates final score with rank.
## Based on Hotline Miami scoring system with the following categories:
## - Kills: Base points for eliminating enemies
## - Combo: Exponential bonus for rapid consecutive kills
## - Time Bonus: Points for completing the level quickly
## - Accuracy: Bonus for high hit-to-shot ratio
## - Damage Taken: Penalty for health lost
## - Special Kills: Bonus for ricochet/penetration kills (requires aggressiveness)
##
## Ranks: F, D, C, B, A, A+, S (highest)

## Combo timeout in seconds - kills within this time continue the combo.
const COMBO_TIMEOUT: float = 2.0

## Base points per kill.
const POINTS_PER_KILL: int = 100

## Time bonus settings.
const TIME_BONUS_MAX: int = 5000  ## Maximum time bonus points
const TIME_BONUS_DURATION: float = 120.0  ## Seconds before time bonus reaches 0

## Accuracy bonus settings.
const ACCURACY_BONUS_MAX: int = 2000  ## Maximum accuracy bonus for 100% accuracy

## Damage penalty per hit taken.
const DAMAGE_PENALTY_PER_HIT: int = 200

## Special kill bonuses (ricochet/penetration).
## These bonuses only apply when combined with aggressiveness.
const RICOCHET_KILL_BONUS: int = 150
const PENETRATION_KILL_BONUS: int = 150

## Aggressiveness threshold - player must have this ratio of combat time vs hiding.
## Measured as: time spent moving toward enemies / total time.
const AGGRESSIVENESS_THRESHOLD: float = 0.4

## Rank thresholds (score required for each rank).
## These are base thresholds that scale with enemy count.
const RANK_THRESHOLDS: Dictionary = {
	"S": 1.0,    ## 100% of max possible score
	"A+": 0.85,  ## 85% of max possible score
	"A": 0.70,   ## 70% of max possible score
	"B": 0.55,   ## 55% of max possible score
	"C": 0.40,   ## 40% of max possible score
	"D": 0.25,   ## 25% of max possible score
	"F": 0.0     ## Below D threshold
}

## Level start time (for time bonus calculation).
var _level_start_time: float = 0.0

## Level completion time in seconds.
var _level_completion_time: float = 0.0

## Total damage taken during the level.
var _damage_taken: int = 0

## Total enemies in the level.
var _total_enemies: int = 0

## Total kills.
var _total_kills: int = 0

## Current combo count.
var _current_combo: int = 0

## Maximum combo achieved.
var _max_combo: int = 0

## Timer since last kill (for combo).
var _combo_timer: float = 0.0

## Total combo points accumulated.
var _combo_points: int = 0

## Special kills tracking.
var _ricochet_kills: int = 0
var _penetration_kills: int = 0

## Aggressiveness tracking.
var _time_moving_toward_enemies: float = 0.0
var _total_combat_time: float = 0.0
var _in_combat: bool = false

## Whether the level is active (for tracking).
var _level_active: bool = false

## Reference to player for position tracking.
var _player: Node2D = null

## Last known player position for movement tracking.
var _last_player_position: Vector2 = Vector2.ZERO

## Average enemy position for aggressiveness calculation.
var _average_enemy_position: Vector2 = Vector2.ZERO

## Signal emitted when score is calculated at level end.
signal score_calculated(score_data: Dictionary)

## Signal emitted when combo changes.
signal combo_changed(combo: int, points: int)


func _ready() -> void:
	# Set process mode to always run (even during time freeze effects)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_log_to_file("ScoreManager ready")


func _process(delta: float) -> void:
	if not _level_active:
		return

	# Update combo timer
	if _current_combo > 0:
		_combo_timer += delta
		if _combo_timer >= COMBO_TIMEOUT:
			_end_combo()

	# Update aggressiveness tracking
	_update_aggressiveness(delta)


## Starts tracking for a new level.
## @param total_enemies: Number of enemies in the level.
func start_level(total_enemies: int) -> void:
	_level_start_time = Time.get_ticks_msec() / 1000.0
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
	_player = null
	_last_player_position = Vector2.ZERO
	_average_enemy_position = Vector2.ZERO

	_log_to_file("Level started with %d enemies" % total_enemies)


## Sets the player reference for aggressiveness tracking.
## @param player: The player node.
func set_player(player: Node2D) -> void:
	_player = player
	if _player:
		_last_player_position = _player.global_position


## Updates the average enemy position for aggressiveness calculation.
## @param enemies: Array of enemy nodes.
func update_enemy_positions(enemies: Array) -> void:
	if enemies.is_empty():
		return

	var sum_position := Vector2.ZERO
	var count := 0
	for enemy in enemies:
		if enemy is Node2D and enemy.has_method("is_alive") and enemy.is_alive():
			sum_position += enemy.global_position
			count += 1

	if count > 0:
		_average_enemy_position = sum_position / count


## Updates aggressiveness tracking.
func _update_aggressiveness(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return

	# Only track aggressiveness during combat (when enemies are aware of player)
	if _in_combat:
		_total_combat_time += delta

		# Check if player is moving toward enemies
		var current_pos := _player.global_position
		if _average_enemy_position != Vector2.ZERO:
			var old_distance := _last_player_position.distance_to(_average_enemy_position)
			var new_distance := current_pos.distance_to(_average_enemy_position)

			# Player moved toward enemies
			if new_distance < old_distance:
				_time_moving_toward_enemies += delta

		_last_player_position = current_pos


## Marks the player as in combat (for aggressiveness tracking).
func enter_combat() -> void:
	_in_combat = true


## Marks combat as ended (for aggressiveness tracking).
func exit_combat() -> void:
	_in_combat = false


## Registers damage taken by the player.
## @param amount: Amount of damage taken.
func register_damage_taken(amount: int = 1) -> void:
	_damage_taken += amount
	_log_to_file("Damage taken: %d (total: %d)" % [amount, _damage_taken])


## Registers a kill with optional special kill information.
## @param is_ricochet_kill: Whether the kill was via ricochet.
## @param is_penetration_kill: Whether the kill was via wall penetration.
func register_kill(is_ricochet_kill: bool = false, is_penetration_kill: bool = false) -> void:
	_total_kills += 1

	# Track special kills
	if is_ricochet_kill:
		_ricochet_kills += 1
		_log_to_file("Ricochet kill registered")
	if is_penetration_kill:
		_penetration_kills += 1
		_log_to_file("Penetration kill registered")

	# Update combo
	_current_combo += 1
	_combo_timer = 0.0

	if _current_combo > _max_combo:
		_max_combo = _current_combo

	# Calculate combo points using exponential formula (like Hotline Miami)
	# Score = 250 * combo^2 + 250 * combo
	var combo_score := 250 * (_current_combo * _current_combo) + 250 * _current_combo
	_combo_points += combo_score

	combo_changed.emit(_current_combo, combo_score)
	_log_to_file("Kill registered. Combo: %d (points: %d)" % [_current_combo, combo_score])


## Ends the current combo.
func _end_combo() -> void:
	if _current_combo > 0:
		_log_to_file("Combo ended at %d. Max combo: %d" % [_current_combo, _max_combo])
		_current_combo = 0
		combo_changed.emit(0, 0)


## Called when the level is completed (all enemies eliminated).
## Calculates and returns the final score.
## @return: Dictionary with all score data.
func complete_level() -> Dictionary:
	_level_active = false
	_level_completion_time = (Time.get_ticks_msec() / 1000.0) - _level_start_time
	_end_combo()

	var score_data := calculate_score()
	score_calculated.emit(score_data)

	_log_to_file("Level completed! Final score: %d, Rank: %s" % [score_data.total_score, score_data.rank])

	return score_data


## Calculates the final score based on all tracked metrics.
## @return: Dictionary with all score components and final rank.
func calculate_score() -> Dictionary:
	# Get accuracy from GameManager
	var game_manager: Node = get_node_or_null("/root/GameManager")
	var accuracy: float = 0.0
	var shots_fired: int = 0
	var hits_landed: int = 0

	if game_manager:
		accuracy = game_manager.get_accuracy()
		shots_fired = game_manager.shots_fired
		hits_landed = game_manager.hits_landed

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
	var aggressiveness: float = 0.0
	if _total_combat_time > 0.0:
		aggressiveness = _time_moving_toward_enemies / _total_combat_time

	var special_kill_bonus: int = 0
	var special_kills_eligible: bool = aggressiveness >= AGGRESSIVENESS_THRESHOLD

	if special_kills_eligible:
		special_kill_bonus = (_ricochet_kills * RICOCHET_KILL_BONUS) + (_penetration_kills * PENETRATION_KILL_BONUS)

	# Calculate total score
	var total_score: int = kill_points + _combo_points + time_bonus + accuracy_bonus + special_kill_bonus - damage_penalty
	total_score = maxi(0, total_score)  # Don't allow negative scores

	# Calculate maximum possible score for rank calculation
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


## Calculates the maximum possible score for the level.
## Used for rank calculation.
func _calculate_max_possible_score() -> int:
	# Max kill points
	var max_kill_points: int = _total_enemies * POINTS_PER_KILL

	# Max combo points (if all enemies killed in one combo)
	# Sum of 250 * i^2 + 250 * i for i = 1 to n
	var max_combo_points: int = 0
	for i in range(1, _total_enemies + 1):
		max_combo_points += 250 * (i * i) + 250 * i

	# Max time bonus
	var max_time_bonus: int = TIME_BONUS_MAX

	# Max accuracy bonus (100% accuracy)
	var max_accuracy_bonus: int = ACCURACY_BONUS_MAX

	# No damage penalty for perfect run
	var min_damage_penalty: int = 0

	# Max special kill bonus (all enemies killed via special means while aggressive)
	var max_special_bonus: int = _total_enemies * (RICOCHET_KILL_BONUS + PENETRATION_KILL_BONUS)

	return max_kill_points + max_combo_points + max_time_bonus + max_accuracy_bonus + max_special_bonus - min_damage_penalty


## Calculates the rank based on score percentage.
## @param score: The player's total score.
## @param max_score: The maximum possible score.
## @return: The rank string.
func _calculate_rank(score: int, max_score: int) -> String:
	if max_score <= 0:
		return "F"

	var score_ratio: float = float(score) / float(max_score)

	# Check ranks from highest to lowest
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


## Returns the current combo count.
func get_current_combo() -> int:
	return _current_combo


## Returns the maximum combo achieved.
func get_max_combo() -> int:
	return _max_combo


## Returns the total damage taken.
func get_damage_taken() -> int:
	return _damage_taken


## Returns the current level completion time.
func get_current_time() -> float:
	if not _level_active:
		return _level_completion_time
	return (Time.get_ticks_msec() / 1000.0) - _level_start_time


## Returns whether the level is currently active.
func is_level_active() -> bool:
	return _level_active


## Resets all tracking data (for scene restart).
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
	_player = null
	_last_player_position = Vector2.ZERO
	_average_enemy_position = Vector2.ZERO


## Log a message to the file logger if available.
func _log_to_file(message: String) -> void:
	var file_logger: Node = get_node_or_null("/root/FileLogger")
	if file_logger and file_logger.has_method("log_info"):
		file_logger.log_info("[ScoreManager] " + message)
	else:
		print("[ScoreManager] " + message)
