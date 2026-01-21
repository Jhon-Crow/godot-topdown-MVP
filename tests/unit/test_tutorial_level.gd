extends GutTest
## Unit tests for Tutorial level script.
##
## Tests the tutorial flow state machine, step progression, and prompt text logic.


# ============================================================================
# Mock Tutorial Level Helper
# ============================================================================


class MockTutorialLevel:
	## Tutorial states
	enum TutorialStep {
		MOVE_TO_TARGETS,
		SHOOT_TARGETS,
		SWITCH_FIRE_MODE,
		RELOAD,
		COMPLETED
	}

	var _current_step: TutorialStep = TutorialStep.MOVE_TO_TARGETS
	var _targets_hit: int = 0
	var _total_targets: int = 0
	var _has_reloaded: bool = false
	var _has_switched_fire_mode: bool = false
	var _has_assault_rifle: bool = false
	var _reached_target_zone: bool = false

	## Distance threshold for being "near" targets
	const TARGET_PROXIMITY_THRESHOLD: float = 300.0

	## Prompt text for each step (Russian)
	const PROMPTS := {
		TutorialStep.MOVE_TO_TARGETS: "[WASD] Подойди к мишеням",
		TutorialStep.SHOOT_TARGETS: "[ЛКМ] Стреляй по мишеням",
		TutorialStep.SWITCH_FIRE_MODE: "[B] Переключи режим стрельбы",
		TutorialStep.RELOAD: "[R] [F] [R] Перезарядись",
		TutorialStep.COMPLETED: ""
	}

	func get_current_step() -> TutorialStep:
		return _current_step

	func get_prompt_text() -> String:
		return PROMPTS[_current_step]

	func advance_to_step(step: TutorialStep) -> void:
		_current_step = step

	func set_targets_total(count: int) -> void:
		_total_targets = count

	func on_target_hit() -> void:
		if _current_step != TutorialStep.SHOOT_TARGETS:
			return

		_targets_hit += 1

		if _targets_hit >= _total_targets:
			if _has_assault_rifle:
				advance_to_step(TutorialStep.SWITCH_FIRE_MODE)
			else:
				advance_to_step(TutorialStep.RELOAD)

	func on_player_near_targets() -> void:
		if _current_step != TutorialStep.MOVE_TO_TARGETS:
			return

		if not _reached_target_zone:
			_reached_target_zone = true
			advance_to_step(TutorialStep.SHOOT_TARGETS)

	func on_fire_mode_changed() -> void:
		if _current_step != TutorialStep.SWITCH_FIRE_MODE:
			return

		if not _has_switched_fire_mode:
			_has_switched_fire_mode = true
			advance_to_step(TutorialStep.RELOAD)

	func on_reload_completed() -> void:
		if _current_step != TutorialStep.RELOAD:
			return

		if not _has_reloaded:
			_has_reloaded = true
			advance_to_step(TutorialStep.COMPLETED)

	func is_tutorial_complete() -> bool:
		return _current_step == TutorialStep.COMPLETED

	func is_prompt_visible() -> bool:
		return _current_step != TutorialStep.COMPLETED

	func calculate_target_zone_center(target_positions: Array[Vector2]) -> Vector2:
		if target_positions.is_empty():
			return Vector2.ZERO

		var sum := Vector2.ZERO
		for pos in target_positions:
			sum += pos
		return sum / target_positions.size()

	func is_player_near_targets(player_pos: Vector2, target_center: Vector2) -> bool:
		return player_pos.distance_to(target_center) < TARGET_PROXIMITY_THRESHOLD


var tutorial: MockTutorialLevel


func before_each() -> void:
	tutorial = MockTutorialLevel.new()


func after_each() -> void:
	tutorial = null


# ============================================================================
# Initial State Tests
# ============================================================================


func test_initial_step_is_move_to_targets() -> void:
	assert_eq(tutorial.get_current_step(), MockTutorialLevel.TutorialStep.MOVE_TO_TARGETS,
		"Tutorial should start at MOVE_TO_TARGETS step")


func test_initial_prompt_text() -> void:
	var text := tutorial.get_prompt_text()
	assert_true(text.contains("WASD"), "Initial prompt should mention WASD")


func test_prompt_is_visible_initially() -> void:
	assert_true(tutorial.is_prompt_visible(), "Prompt should be visible initially")


func test_tutorial_not_complete_initially() -> void:
	assert_false(tutorial.is_tutorial_complete(), "Tutorial should not be complete initially")


# ============================================================================
# Step Progression Tests
# ============================================================================


func test_advance_to_shoot_targets() -> void:
	tutorial.on_player_near_targets()

	assert_eq(tutorial.get_current_step(), MockTutorialLevel.TutorialStep.SHOOT_TARGETS,
		"Should advance to SHOOT_TARGETS after reaching targets")


func test_shoot_targets_prompt_text() -> void:
	tutorial.advance_to_step(MockTutorialLevel.TutorialStep.SHOOT_TARGETS)

	var text := tutorial.get_prompt_text()
	assert_true(text.contains("ЛКМ"), "Shoot prompt should mention left mouse button")


func test_all_targets_hit_advances_to_reload_without_rifle() -> void:
	tutorial.advance_to_step(MockTutorialLevel.TutorialStep.SHOOT_TARGETS)
	tutorial._has_assault_rifle = false
	tutorial.set_targets_total(3)

	tutorial.on_target_hit()
	tutorial.on_target_hit()
	tutorial.on_target_hit()

	assert_eq(tutorial.get_current_step(), MockTutorialLevel.TutorialStep.RELOAD,
		"Should advance to RELOAD after all targets hit (no assault rifle)")


func test_all_targets_hit_advances_to_fire_mode_with_rifle() -> void:
	tutorial.advance_to_step(MockTutorialLevel.TutorialStep.SHOOT_TARGETS)
	tutorial._has_assault_rifle = true
	tutorial.set_targets_total(3)

	tutorial.on_target_hit()
	tutorial.on_target_hit()
	tutorial.on_target_hit()

	assert_eq(tutorial.get_current_step(), MockTutorialLevel.TutorialStep.SWITCH_FIRE_MODE,
		"Should advance to SWITCH_FIRE_MODE after all targets hit (with assault rifle)")


func test_fire_mode_change_advances_to_reload() -> void:
	tutorial.advance_to_step(MockTutorialLevel.TutorialStep.SWITCH_FIRE_MODE)

	tutorial.on_fire_mode_changed()

	assert_eq(tutorial.get_current_step(), MockTutorialLevel.TutorialStep.RELOAD,
		"Should advance to RELOAD after switching fire mode")


func test_reload_prompt_text() -> void:
	tutorial.advance_to_step(MockTutorialLevel.TutorialStep.RELOAD)

	var text := tutorial.get_prompt_text()
	assert_true(text.contains("[R]") and text.contains("[F]"),
		"Reload prompt should mention R-F-R sequence")


func test_reload_completes_tutorial() -> void:
	tutorial.advance_to_step(MockTutorialLevel.TutorialStep.RELOAD)

	tutorial.on_reload_completed()

	assert_eq(tutorial.get_current_step(), MockTutorialLevel.TutorialStep.COMPLETED,
		"Should advance to COMPLETED after reload")
	assert_true(tutorial.is_tutorial_complete(), "Tutorial should be complete")


func test_completed_prompt_is_empty() -> void:
	tutorial.advance_to_step(MockTutorialLevel.TutorialStep.COMPLETED)

	assert_eq(tutorial.get_prompt_text(), "", "Completed step should have empty prompt")


func test_prompt_not_visible_when_completed() -> void:
	tutorial.advance_to_step(MockTutorialLevel.TutorialStep.COMPLETED)

	assert_false(tutorial.is_prompt_visible(), "Prompt should not be visible when completed")


# ============================================================================
# State Guard Tests
# ============================================================================


func test_target_hit_ignored_in_move_step() -> void:
	# Still in MOVE_TO_TARGETS step
	tutorial.set_targets_total(3)
	tutorial.on_target_hit()

	assert_eq(tutorial.get_current_step(), MockTutorialLevel.TutorialStep.MOVE_TO_TARGETS,
		"Target hit should be ignored in MOVE_TO_TARGETS step")


func test_fire_mode_change_ignored_in_wrong_step() -> void:
	tutorial.advance_to_step(MockTutorialLevel.TutorialStep.SHOOT_TARGETS)

	tutorial.on_fire_mode_changed()

	assert_eq(tutorial.get_current_step(), MockTutorialLevel.TutorialStep.SHOOT_TARGETS,
		"Fire mode change should be ignored in SHOOT_TARGETS step")


func test_reload_ignored_in_wrong_step() -> void:
	tutorial.advance_to_step(MockTutorialLevel.TutorialStep.SHOOT_TARGETS)

	tutorial.on_reload_completed()

	assert_eq(tutorial.get_current_step(), MockTutorialLevel.TutorialStep.SHOOT_TARGETS,
		"Reload should be ignored in SHOOT_TARGETS step")


func test_player_near_targets_only_triggers_once() -> void:
	tutorial.on_player_near_targets()  # Advances to SHOOT_TARGETS
	tutorial._current_step = MockTutorialLevel.TutorialStep.MOVE_TO_TARGETS  # Reset for test
	tutorial.on_player_near_targets()  # Should not advance again

	# The second call should not do anything because _reached_target_zone is true
	assert_true(tutorial._reached_target_zone, "Target zone flag should remain true")


# ============================================================================
# Target Zone Calculation Tests
# ============================================================================


func test_calculate_target_zone_center() -> void:
	var positions: Array[Vector2] = [Vector2(100, 100), Vector2(200, 100), Vector2(150, 200)]
	var center := tutorial.calculate_target_zone_center(positions)

	# Average: (100+200+150)/3 = 150, (100+100+200)/3 = 133.33
	assert_almost_eq(center.x, 150.0, 0.01, "Center X should be average of X positions")
	assert_almost_eq(center.y, 133.33, 0.01, "Center Y should be average of Y positions")


func test_calculate_target_zone_center_empty() -> void:
	var positions: Array[Vector2] = []
	var center := tutorial.calculate_target_zone_center(positions)

	assert_eq(center, Vector2.ZERO, "Empty positions should return zero vector")


func test_is_player_near_targets() -> void:
	var player_pos := Vector2(100, 100)
	var target_center := Vector2(150, 100)  # 50 pixels away

	assert_true(tutorial.is_player_near_targets(player_pos, target_center),
		"Player within threshold should be 'near'")


func test_is_player_not_near_targets() -> void:
	var player_pos := Vector2(0, 0)
	var target_center := Vector2(500, 500)  # ~707 pixels away

	assert_false(tutorial.is_player_near_targets(player_pos, target_center),
		"Player beyond threshold should not be 'near'")


func test_proximity_threshold_value() -> void:
	assert_eq(MockTutorialLevel.TARGET_PROXIMITY_THRESHOLD, 300.0,
		"Proximity threshold should be 300 pixels")


# ============================================================================
# Full Tutorial Flow Test
# ============================================================================


func test_complete_tutorial_flow_with_rifle() -> void:
	tutorial._has_assault_rifle = true
	tutorial.set_targets_total(2)

	# Step 1: Move to targets
	assert_eq(tutorial.get_current_step(), MockTutorialLevel.TutorialStep.MOVE_TO_TARGETS)

	tutorial.on_player_near_targets()

	# Step 2: Shoot targets
	assert_eq(tutorial.get_current_step(), MockTutorialLevel.TutorialStep.SHOOT_TARGETS)

	tutorial.on_target_hit()
	tutorial.on_target_hit()

	# Step 3: Switch fire mode
	assert_eq(tutorial.get_current_step(), MockTutorialLevel.TutorialStep.SWITCH_FIRE_MODE)

	tutorial.on_fire_mode_changed()

	# Step 4: Reload
	assert_eq(tutorial.get_current_step(), MockTutorialLevel.TutorialStep.RELOAD)

	tutorial.on_reload_completed()

	# Step 5: Complete
	assert_true(tutorial.is_tutorial_complete(), "Tutorial should be complete")


func test_complete_tutorial_flow_without_rifle() -> void:
	tutorial._has_assault_rifle = false
	tutorial.set_targets_total(2)

	tutorial.on_player_near_targets()
	tutorial.on_target_hit()
	tutorial.on_target_hit()

	# Should skip fire mode step
	assert_eq(tutorial.get_current_step(), MockTutorialLevel.TutorialStep.RELOAD,
		"Should skip fire mode step without assault rifle")

	tutorial.on_reload_completed()

	assert_true(tutorial.is_tutorial_complete())
