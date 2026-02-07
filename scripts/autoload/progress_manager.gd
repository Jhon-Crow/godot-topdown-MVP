extends Node
## Autoload singleton for managing player progress persistence.
##
## Saves and loads the best rank and score achieved per level per difficulty.
## Uses ConfigFile for persistence (same pattern as DifficultyManager).
## Integrates with ScoreManager to automatically save progress on level completion.

## Signal emitted when progress is updated (new best score/rank).
signal progress_updated(level_path: String, difficulty_name: String)

## Save file path.
const SAVE_PATH := "user://progress.cfg"

## Section name in the config file.
const SECTION := "progress"

## Rank ordering for comparison (higher index = better rank).
const RANK_ORDER: Array[String] = ["F", "D", "C", "B", "A", "A+", "S"]

## In-memory cache of progress data.
## Key: "level_path:difficulty_name" → Value: {"rank": String, "score": int}
var _progress: Dictionary = {}


func _ready() -> void:
	_load_progress()
	# Connect to ScoreManager signal for automatic saving
	var score_manager: Node = get_node_or_null("/root/ScoreManager")
	if score_manager and score_manager.has_signal("score_calculated"):
		score_manager.score_calculated.connect(_on_score_calculated)
	_log_to_file("ProgressManager ready, loaded %d entries" % _progress.size())


## Called when ScoreManager emits score_calculated after level completion.
func _on_score_calculated(score_data: Dictionary) -> void:
	# Get current level path
	var current_scene: Node = get_tree().current_scene
	if not current_scene or not current_scene.scene_file_path:
		_log_to_file("Cannot save progress: no current scene")
		return

	var level_path: String = current_scene.scene_file_path

	# Get current difficulty name
	var difficulty_manager: Node = get_node_or_null("/root/DifficultyManager")
	var difficulty_name: String = "Normal"
	if difficulty_manager and difficulty_manager.has_method("get_difficulty_name"):
		difficulty_name = difficulty_manager.get_difficulty_name()

	var rank: String = score_data.get("rank", "F")
	var score: int = score_data.get("total_score", 0)

	save_level_progress(level_path, difficulty_name, rank, score)


## Save progress for a level if it improves on the existing best.
## @param level_path: The scene file path of the level.
## @param difficulty_name: The difficulty mode name (e.g., "Normal", "Hard").
## @param rank: The rank achieved (e.g., "A+", "S").
## @param score: The total score achieved.
func save_level_progress(level_path: String, difficulty_name: String, rank: String, score: int) -> void:
	var key: String = _make_key(level_path, difficulty_name)
	var existing: Dictionary = _progress.get(key, {})
	var existing_rank: String = existing.get("rank", "")
	var existing_score: int = existing.get("score", 0)

	var is_better_rank: bool = _is_rank_better(rank, existing_rank)
	var is_better_score: bool = score > existing_score

	if is_better_rank or is_better_score:
		# Keep the best of each metric
		var best_rank: String = rank if is_better_rank else existing_rank
		var best_score: int = score if is_better_score else existing_score

		_progress[key] = {"rank": best_rank, "score": best_score}
		_save_progress()
		progress_updated.emit(level_path, difficulty_name)
		_log_to_file("Progress saved for %s on %s: rank=%s, score=%d" % [level_path, difficulty_name, best_rank, best_score])
	else:
		_log_to_file("No improvement for %s on %s (existing: rank=%s, score=%d)" % [level_path, difficulty_name, existing_rank, existing_score])


## Get the best rank for a level on a specific difficulty.
## @param level_path: The scene file path of the level.
## @param difficulty_name: The difficulty mode name.
## @return: The best rank string, or "" if not yet completed.
func get_best_rank(level_path: String, difficulty_name: String) -> String:
	var key: String = _make_key(level_path, difficulty_name)
	var data: Dictionary = _progress.get(key, {})
	return data.get("rank", "")


## Get the best score for a level on a specific difficulty.
## @param level_path: The scene file path of the level.
## @param difficulty_name: The difficulty mode name.
## @return: The best score, or 0 if not yet completed.
func get_best_score(level_path: String, difficulty_name: String) -> int:
	var key: String = _make_key(level_path, difficulty_name)
	var data: Dictionary = _progress.get(key, {})
	return data.get("score", 0)


## Check if a level has been completed on a specific difficulty.
## @param level_path: The scene file path of the level.
## @param difficulty_name: The difficulty mode name.
## @return: True if the level has been completed at least once.
func is_level_completed(level_path: String, difficulty_name: String) -> bool:
	var key: String = _make_key(level_path, difficulty_name)
	return key in _progress


## Get all progress data (for display purposes).
## @return: Dictionary with all progress entries.
func get_all_progress() -> Dictionary:
	return _progress.duplicate()


## Clear all progress data.
func clear_all_progress() -> void:
	_progress.clear()
	_save_progress()
	_log_to_file("All progress cleared")


## Compare two ranks. Returns true if new_rank is strictly better than old_rank.
func _is_rank_better(new_rank: String, old_rank: String) -> bool:
	if old_rank.is_empty():
		return true
	var new_index: int = RANK_ORDER.find(new_rank)
	var old_index: int = RANK_ORDER.find(old_rank)
	if new_index == -1:
		return false
	if old_index == -1:
		return true
	return new_index > old_index


## Create a storage key from level path and difficulty name.
func _make_key(level_path: String, difficulty_name: String) -> String:
	return "%s:%s" % [level_path, difficulty_name]


## Save all progress to file.
func _save_progress() -> void:
	var config := ConfigFile.new()
	for key in _progress:
		var data: Dictionary = _progress[key]
		config.set_value(SECTION, key + ":rank", data.get("rank", "F"))
		config.set_value(SECTION, key + ":score", data.get("score", 0))

	var error := config.save(SAVE_PATH)
	if error != OK:
		push_warning("ProgressManager: Failed to save progress: " + str(error))


## Load progress from file.
func _load_progress() -> void:
	var config := ConfigFile.new()
	var error := config.load(SAVE_PATH)
	if error != OK:
		# File doesn't exist or failed to load - start fresh
		_progress = {}
		return

	_progress = {}
	if not config.has_section(SECTION):
		return

	# Collect all unique base keys (level_path:difficulty)
	var base_keys: Dictionary = {}
	for key in config.get_section_keys(SECTION):
		# Keys are stored as "level_path:difficulty:rank" and "level_path:difficulty:score"
		# We need to reconstruct the base key by removing the last segment
		var last_colon: int = key.rfind(":")
		if last_colon == -1:
			continue
		var suffix: String = key.substr(last_colon + 1)
		if suffix != "rank" and suffix != "score":
			continue
		var base_key: String = key.substr(0, last_colon)
		if base_key not in base_keys:
			base_keys[base_key] = {}
		if suffix == "rank":
			base_keys[base_key]["rank"] = config.get_value(SECTION, key, "F")
		elif suffix == "score":
			base_keys[base_key]["score"] = config.get_value(SECTION, key, 0)

	for base_key in base_keys:
		_progress[base_key] = base_keys[base_key]


## Log a message to the file logger if available.
func _log_to_file(message: String) -> void:
	var file_logger: Node = get_node_or_null("/root/FileLogger")
	if file_logger and file_logger.has_method("log_info"):
		file_logger.log_info("[ProgressManager] " + message)
	else:
		print("[ProgressManager] " + message)
