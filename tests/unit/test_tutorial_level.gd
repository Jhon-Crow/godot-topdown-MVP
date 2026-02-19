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
		SWITCH_FIRE_MODE,
		RELOAD,
		THROW_GRENADE,
		COMPLETED
	}

	var _current_step: TutorialStep = TutorialStep.SWITCH_FIRE_MODE
	var _has_reloaded: bool = false
	var _has_switched_fire_mode: bool = false
	var _has_thrown_grenade: bool = false
	var _has_assault_rifle: bool = false

	## Prompt text for each step (Russian)
	const PROMPTS := {
		TutorialStep.SWITCH_FIRE_MODE: "[B] Переключи режим стрельбы",
		TutorialStep.RELOAD: "[R] [F] [R] Перезарядись",
		TutorialStep.THROW_GRENADE: "[G+ПКМ вправо] [G+ПКМ→отпусти G] [ПКМ бросок]",
		TutorialStep.COMPLETED: ""
	}

	func get_current_step() -> TutorialStep:
		return _current_step

	func get_prompt_text() -> String:
		return PROMPTS[_current_step]

	func advance_to_step(step: TutorialStep) -> void:
		_current_step = step

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
			advance_to_step(TutorialStep.THROW_GRENADE)

	func on_grenade_thrown() -> void:
		if _current_step != TutorialStep.THROW_GRENADE:
			return

		if not _has_thrown_grenade:
			_has_thrown_grenade = true
			advance_to_step(TutorialStep.COMPLETED)

	func is_tutorial_complete() -> bool:
		return _current_step == TutorialStep.COMPLETED

	func is_prompt_visible() -> bool:
		return _current_step != TutorialStep.COMPLETED

	func set_initial_step_based_on_weapon(has_assault_rifle: bool) -> void:
		if has_assault_rifle:
			_current_step = TutorialStep.SWITCH_FIRE_MODE
		else:
			_current_step = TutorialStep.RELOAD


var tutorial: MockTutorialLevel


func before_each() -> void:
	tutorial = MockTutorialLevel.new()


func after_each() -> void:
	tutorial = null


# ============================================================================
# Initial State Tests
# ============================================================================


func test_initial_step_is_switch_fire_mode() -> void:
	assert_eq(tutorial.get_current_step(), MockTutorialLevel.TutorialStep.SWITCH_FIRE_MODE,
		"Tutorial should start at SWITCH_FIRE_MODE step by default")


func test_initial_step_is_reload_without_rifle() -> void:
	tutorial.set_initial_step_based_on_weapon(false)
	assert_eq(tutorial.get_current_step(), MockTutorialLevel.TutorialStep.RELOAD,
		"Tutorial should start at RELOAD step for non-assault rifles")


func test_initial_prompt_text() -> void:
	var text := tutorial.get_prompt_text()
	assert_true(text.contains("[B]"), "Initial prompt should mention B key for fire mode")


func test_prompt_is_visible_initially() -> void:
	assert_true(tutorial.is_prompt_visible(), "Prompt should be visible initially")


func test_tutorial_not_complete_initially() -> void:
	assert_false(tutorial.is_tutorial_complete(), "Tutorial should not be complete initially")


# ============================================================================
# Step Progression Tests
# ============================================================================


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


func test_reload_advances_to_grenade() -> void:
	tutorial.advance_to_step(MockTutorialLevel.TutorialStep.RELOAD)

	tutorial.on_reload_completed()

	assert_eq(tutorial.get_current_step(), MockTutorialLevel.TutorialStep.THROW_GRENADE,
		"Should advance to THROW_GRENADE after reload")


func test_grenade_throw_completes_tutorial() -> void:
	tutorial.advance_to_step(MockTutorialLevel.TutorialStep.THROW_GRENADE)

	tutorial.on_grenade_thrown()

	assert_eq(tutorial.get_current_step(), MockTutorialLevel.TutorialStep.COMPLETED,
		"Should advance to COMPLETED after throwing grenade")
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


func test_fire_mode_change_ignored_in_wrong_step() -> void:
	tutorial.advance_to_step(MockTutorialLevel.TutorialStep.RELOAD)

	tutorial.on_fire_mode_changed()

	assert_eq(tutorial.get_current_step(), MockTutorialLevel.TutorialStep.RELOAD,
		"Fire mode change should be ignored in RELOAD step")


func test_reload_ignored_in_wrong_step() -> void:
	tutorial.advance_to_step(MockTutorialLevel.TutorialStep.SWITCH_FIRE_MODE)

	tutorial.on_reload_completed()

	assert_eq(tutorial.get_current_step(), MockTutorialLevel.TutorialStep.SWITCH_FIRE_MODE,
		"Reload should be ignored in SWITCH_FIRE_MODE step")


func test_grenade_throw_ignored_in_wrong_step() -> void:
	tutorial.advance_to_step(MockTutorialLevel.TutorialStep.RELOAD)

	tutorial.on_grenade_thrown()

	assert_eq(tutorial.get_current_step(), MockTutorialLevel.TutorialStep.RELOAD,
		"Grenade throw should be ignored in RELOAD step")


# ============================================================================
# Full Tutorial Flow Test
# ============================================================================


func test_complete_tutorial_flow_with_rifle() -> void:
	tutorial._has_assault_rifle = true
	tutorial.set_initial_step_based_on_weapon(true)

	# Step 1: Switch fire mode
	assert_eq(tutorial.get_current_step(), MockTutorialLevel.TutorialStep.SWITCH_FIRE_MODE)

	tutorial.on_fire_mode_changed()

	# Step 2: Reload
	assert_eq(tutorial.get_current_step(), MockTutorialLevel.TutorialStep.RELOAD)

	tutorial.on_reload_completed()

	# Step 3: Throw grenade
	assert_eq(tutorial.get_current_step(), MockTutorialLevel.TutorialStep.THROW_GRENADE)

	tutorial.on_grenade_thrown()

	# Step 4: Complete
	assert_true(tutorial.is_tutorial_complete(), "Tutorial should be complete")


func test_complete_tutorial_flow_without_rifle() -> void:
	tutorial._has_assault_rifle = false
	tutorial.set_initial_step_based_on_weapon(false)

	# Should skip fire mode step and start with reload
	assert_eq(tutorial.get_current_step(), MockTutorialLevel.TutorialStep.RELOAD,
		"Should start with reload step without assault rifle")

	tutorial.on_reload_completed()

	# Step 2: Throw grenade
	assert_eq(tutorial.get_current_step(), MockTutorialLevel.TutorialStep.THROW_GRENADE)

	tutorial.on_grenade_thrown()

	assert_true(tutorial.is_tutorial_complete())
