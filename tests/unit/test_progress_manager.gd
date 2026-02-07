extends GutTest
## Unit tests for ProgressManager functionality.
##
## Tests the progress saving, loading, rank comparison, and level completion tracking.
## Uses a mock class to test logic without requiring autoload or file system.


# ============================================================================
# Mock Progress Manager
# ============================================================================


class MockProgressManager:
	## Mock class that mirrors ProgressManager's testable functionality.

	const RANK_ORDER: Array[String] = ["F", "D", "C", "B", "A", "A+", "S"]

	## In-memory cache of progress data.
	var _progress: Dictionary = {}

	func save_level_progress(level_path: String, difficulty_name: String, rank: String, score: int) -> void:
		var key: String = _make_key(level_path, difficulty_name)
		var existing: Dictionary = _progress.get(key, {})
		var existing_rank: String = existing.get("rank", "")
		var existing_score: int = existing.get("score", 0)

		var is_better_rank: bool = _is_rank_better(rank, existing_rank)
		var is_better_score: bool = score > existing_score

		if is_better_rank or is_better_score:
			var best_rank: String = rank if is_better_rank else existing_rank
			var best_score: int = score if is_better_score else existing_score
			_progress[key] = {"rank": best_rank, "score": best_score}

	func get_best_rank(level_path: String, difficulty_name: String) -> String:
		var key: String = _make_key(level_path, difficulty_name)
		var data: Dictionary = _progress.get(key, {})
		return data.get("rank", "")

	func get_best_score(level_path: String, difficulty_name: String) -> int:
		var key: String = _make_key(level_path, difficulty_name)
		var data: Dictionary = _progress.get(key, {})
		return data.get("score", 0)

	func is_level_completed(level_path: String, difficulty_name: String) -> bool:
		var key: String = _make_key(level_path, difficulty_name)
		return key in _progress

	func get_all_progress() -> Dictionary:
		return _progress.duplicate()

	func clear_all_progress() -> void:
		_progress.clear()

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

	func _make_key(level_path: String, difficulty_name: String) -> String:
		return "%s:%s" % [level_path, difficulty_name]


var progress: MockProgressManager


func before_each() -> void:
	progress = MockProgressManager.new()


func after_each() -> void:
	progress = null


# ============================================================================
# Initial State Tests
# ============================================================================


func test_initial_progress_is_empty() -> void:
	assert_true(progress.get_all_progress().is_empty(), "Progress should start empty")


func test_level_not_completed_initially() -> void:
	assert_false(progress.is_level_completed("res://scenes/levels/BuildingLevel.tscn", "Normal"),
		"Level should not be completed initially")


func test_best_rank_empty_initially() -> void:
	assert_eq(progress.get_best_rank("res://scenes/levels/BuildingLevel.tscn", "Normal"), "",
		"Best rank should be empty initially")


func test_best_score_zero_initially() -> void:
	assert_eq(progress.get_best_score("res://scenes/levels/BuildingLevel.tscn", "Normal"), 0,
		"Best score should be 0 initially")


# ============================================================================
# Saving Progress Tests
# ============================================================================


func test_save_first_completion() -> void:
	progress.save_level_progress("res://scenes/levels/BuildingLevel.tscn", "Normal", "B", 5000)

	assert_true(progress.is_level_completed("res://scenes/levels/BuildingLevel.tscn", "Normal"),
		"Level should be marked as completed")
	assert_eq(progress.get_best_rank("res://scenes/levels/BuildingLevel.tscn", "Normal"), "B",
		"Best rank should be B")
	assert_eq(progress.get_best_score("res://scenes/levels/BuildingLevel.tscn", "Normal"), 5000,
		"Best score should be 5000")


func test_save_better_rank_updates() -> void:
	progress.save_level_progress("res://scenes/levels/BuildingLevel.tscn", "Normal", "C", 3000)
	progress.save_level_progress("res://scenes/levels/BuildingLevel.tscn", "Normal", "A", 7000)

	assert_eq(progress.get_best_rank("res://scenes/levels/BuildingLevel.tscn", "Normal"), "A",
		"Best rank should update to A")


func test_save_worse_rank_does_not_downgrade() -> void:
	progress.save_level_progress("res://scenes/levels/BuildingLevel.tscn", "Normal", "A", 7000)
	progress.save_level_progress("res://scenes/levels/BuildingLevel.tscn", "Normal", "C", 8000)

	assert_eq(progress.get_best_rank("res://scenes/levels/BuildingLevel.tscn", "Normal"), "A",
		"Best rank should remain A (not downgrade to C)")


func test_save_better_score_updates() -> void:
	progress.save_level_progress("res://scenes/levels/BuildingLevel.tscn", "Normal", "B", 5000)
	progress.save_level_progress("res://scenes/levels/BuildingLevel.tscn", "Normal", "B", 8000)

	assert_eq(progress.get_best_score("res://scenes/levels/BuildingLevel.tscn", "Normal"), 8000,
		"Best score should update to 8000")


func test_save_worse_score_does_not_downgrade() -> void:
	progress.save_level_progress("res://scenes/levels/BuildingLevel.tscn", "Normal", "B", 8000)
	progress.save_level_progress("res://scenes/levels/BuildingLevel.tscn", "Normal", "B", 3000)

	assert_eq(progress.get_best_score("res://scenes/levels/BuildingLevel.tscn", "Normal"), 8000,
		"Best score should remain 8000 (not downgrade)")


func test_keeps_best_rank_and_best_score_independently() -> void:
	# First run: rank A, score 7000
	progress.save_level_progress("res://scenes/levels/BuildingLevel.tscn", "Normal", "A", 7000)
	# Second run: rank B, score 9000 (worse rank but better score)
	progress.save_level_progress("res://scenes/levels/BuildingLevel.tscn", "Normal", "B", 9000)

	assert_eq(progress.get_best_rank("res://scenes/levels/BuildingLevel.tscn", "Normal"), "A",
		"Should keep better rank A")
	assert_eq(progress.get_best_score("res://scenes/levels/BuildingLevel.tscn", "Normal"), 9000,
		"Should keep better score 9000")


# ============================================================================
# Per-Difficulty Progress Tests
# ============================================================================


func test_progress_is_per_difficulty() -> void:
	progress.save_level_progress("res://scenes/levels/BuildingLevel.tscn", "Easy", "A", 8000)
	progress.save_level_progress("res://scenes/levels/BuildingLevel.tscn", "Hard", "C", 3000)

	assert_eq(progress.get_best_rank("res://scenes/levels/BuildingLevel.tscn", "Easy"), "A",
		"Easy rank should be A")
	assert_eq(progress.get_best_rank("res://scenes/levels/BuildingLevel.tscn", "Hard"), "C",
		"Hard rank should be C")
	assert_eq(progress.get_best_rank("res://scenes/levels/BuildingLevel.tscn", "Normal"), "",
		"Normal rank should be empty (not completed)")


func test_progress_is_per_level() -> void:
	progress.save_level_progress("res://scenes/levels/BuildingLevel.tscn", "Normal", "S", 12000)
	progress.save_level_progress("res://scenes/levels/TestTier.tscn", "Normal", "B", 5000)

	assert_eq(progress.get_best_rank("res://scenes/levels/BuildingLevel.tscn", "Normal"), "S",
		"Building Level rank should be S")
	assert_eq(progress.get_best_rank("res://scenes/levels/TestTier.tscn", "Normal"), "B",
		"Test Tier rank should be B")


func test_four_difficulty_modes_tracked() -> void:
	var level: String = "res://scenes/levels/CastleLevel.tscn"
	progress.save_level_progress(level, "Easy", "A+", 9000)
	progress.save_level_progress(level, "Normal", "B", 6000)
	progress.save_level_progress(level, "Hard", "D", 2000)
	progress.save_level_progress(level, "Power Fantasy", "S", 15000)

	assert_eq(progress.get_best_rank(level, "Easy"), "A+")
	assert_eq(progress.get_best_rank(level, "Normal"), "B")
	assert_eq(progress.get_best_rank(level, "Hard"), "D")
	assert_eq(progress.get_best_rank(level, "Power Fantasy"), "S")


# ============================================================================
# Rank Comparison Tests
# ============================================================================


func test_rank_s_better_than_a_plus() -> void:
	assert_true(progress._is_rank_better("S", "A+"), "S should be better than A+")


func test_rank_a_plus_better_than_a() -> void:
	assert_true(progress._is_rank_better("A+", "A"), "A+ should be better than A")


func test_rank_a_better_than_b() -> void:
	assert_true(progress._is_rank_better("A", "B"), "A should be better than B")


func test_rank_b_better_than_c() -> void:
	assert_true(progress._is_rank_better("B", "C"), "B should be better than C")


func test_rank_c_better_than_d() -> void:
	assert_true(progress._is_rank_better("C", "D"), "C should be better than D")


func test_rank_d_better_than_f() -> void:
	assert_true(progress._is_rank_better("D", "F"), "D should be better than F")


func test_rank_f_not_better_than_s() -> void:
	assert_false(progress._is_rank_better("F", "S"), "F should not be better than S")


func test_rank_b_not_better_than_a() -> void:
	assert_false(progress._is_rank_better("B", "A"), "B should not be better than A")


func test_same_rank_not_better() -> void:
	assert_false(progress._is_rank_better("A", "A"), "Same rank should not be better")


func test_any_rank_better_than_empty() -> void:
	assert_true(progress._is_rank_better("F", ""), "F should be better than empty (no completion)")


func test_invalid_rank_not_better() -> void:
	assert_false(progress._is_rank_better("X", "A"), "Invalid rank should not be better")


# ============================================================================
# Clear Progress Tests
# ============================================================================


func test_clear_all_progress() -> void:
	progress.save_level_progress("res://scenes/levels/BuildingLevel.tscn", "Normal", "A", 7000)
	progress.save_level_progress("res://scenes/levels/TestTier.tscn", "Easy", "S", 12000)

	progress.clear_all_progress()

	assert_true(progress.get_all_progress().is_empty(), "Progress should be empty after clear")
	assert_false(progress.is_level_completed("res://scenes/levels/BuildingLevel.tscn", "Normal"),
		"Level should not be completed after clear")


# ============================================================================
# Key Generation Tests
# ============================================================================


func test_key_format() -> void:
	var key: String = progress._make_key("res://scenes/levels/BuildingLevel.tscn", "Normal")
	assert_eq(key, "res://scenes/levels/BuildingLevel.tscn:Normal",
		"Key should combine path and difficulty with colon")


func test_different_keys_for_different_difficulties() -> void:
	var key_easy: String = progress._make_key("res://scenes/levels/BuildingLevel.tscn", "Easy")
	var key_hard: String = progress._make_key("res://scenes/levels/BuildingLevel.tscn", "Hard")
	assert_ne(key_easy, key_hard, "Keys should differ for different difficulties")


# ============================================================================
# Edge Cases
# ============================================================================


func test_save_with_zero_score() -> void:
	progress.save_level_progress("res://scenes/levels/BuildingLevel.tscn", "Normal", "F", 0)

	assert_true(progress.is_level_completed("res://scenes/levels/BuildingLevel.tscn", "Normal"),
		"Level should be marked as completed even with 0 score")
	assert_eq(progress.get_best_rank("res://scenes/levels/BuildingLevel.tscn", "Normal"), "F",
		"Rank should be F")


func test_all_levels_tracked() -> void:
	var levels: Array[String] = [
		"res://scenes/levels/BuildingLevel.tscn",
		"res://scenes/levels/TestTier.tscn",
		"res://scenes/levels/CastleLevel.tscn",
		"res://scenes/levels/csharp/TestTier.tscn"
	]

	for level in levels:
		progress.save_level_progress(level, "Normal", "B", 5000)

	for level in levels:
		assert_true(progress.is_level_completed(level, "Normal"),
			"Level %s should be completed" % level)


func test_multiple_updates_keep_best() -> void:
	var level: String = "res://scenes/levels/BuildingLevel.tscn"
	# Simulate multiple playthroughs with varying results
	progress.save_level_progress(level, "Normal", "D", 2000)
	progress.save_level_progress(level, "Normal", "C", 3500)
	progress.save_level_progress(level, "Normal", "B", 6000)
	progress.save_level_progress(level, "Normal", "A", 5000)  # Better rank, worse score
	progress.save_level_progress(level, "Normal", "C", 7000)  # Worse rank, better score

	assert_eq(progress.get_best_rank(level, "Normal"), "A",
		"Should keep best rank A across all runs")
	assert_eq(progress.get_best_score(level, "Normal"), 7000,
		"Should keep best score 7000 across all runs")
