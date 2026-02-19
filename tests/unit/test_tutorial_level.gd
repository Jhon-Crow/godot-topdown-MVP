extends GutTest
## Unit tests for Tutorial level script.
##
## Tests the tutorial flow state machine, multi-hint display logic, and step progression.
## Issue #808: reload and grenade hints are shown simultaneously; each completes independently.


# ============================================================================
# Mock Tutorial Level Helper
# ============================================================================


class MockTutorialLevel:
	## Tutorial states
	enum TutorialStep {
		SWITCH_FIRE_MODE,
		RELOAD,
		SCOPE_TRAINING,
		THROW_GRENADE,
		COMPLETED
	}

	## Hint keys (mirrors tutorial_level.gd constants)
	const HINT_RELOAD := "reload"
	const HINT_GRENADE := "grenade"
	const HINT_BOLT_CYCLE := "bolt_cycle"
	const HINT_SCOPE := "scope"
	const HINT_FIRE_MODE := "fire_mode"

	var _current_step: TutorialStep = TutorialStep.SWITCH_FIRE_MODE
	var _has_reloaded: bool = false
	var _has_switched_fire_mode: bool = false
	var _has_thrown_grenade: bool = false
	var _has_assault_rifle: bool = false
	var _has_sniper_rifle: bool = false
	var _has_revolver: bool = false
	var _has_shotgun: bool = false
	var _has_makarov_pm: bool = false
	var _sniper_bolt_cycled: bool = false
	var _scope_used: bool = false

	## Active hints dictionary: hint_key -> hint_text (simulates visible labels)
	var _active_hints: Dictionary = {}

	func get_current_step() -> TutorialStep:
		return _current_step

	func get_active_hints() -> Dictionary:
		return _active_hints.duplicate()

	func is_hint_active(hint_key: String) -> bool:
		return _active_hints.has(hint_key)

	func is_any_hint_active() -> bool:
		return not _active_hints.is_empty()

	func advance_to_step(step: TutorialStep) -> void:
		_current_step = step
		_show_hints_for_step(step)

	func _dismiss_hint(hint_key: String) -> void:
		_active_hints.erase(hint_key)

	func _add_hint(hint_key: String, text: String) -> void:
		_active_hints[hint_key] = text

	func _add_reload_hints() -> void:
		if _has_sniper_rifle:
			_add_hint(HINT_RELOAD, "[R] [F] [R] Перезарядись")
			_add_hint(HINT_BOLT_CYCLE, "[←↓↑→] Передёрни затвор")
		elif _has_shotgun:
			_add_hint(HINT_RELOAD, "[ПКМ↑ открыть] [СКМ+ПКМ↓ x8] [ПКМ↓ закрыть]")
		elif _has_revolver:
			_add_hint(HINT_RELOAD, "[R открыть] [ПКМ↑ патрон] [скролл] [R закрыть]")
		elif _has_makarov_pm:
			_add_hint(HINT_RELOAD, "[R] [R] Перезарядись")
		else:
			_add_hint(HINT_RELOAD, "[R] [F] [R] Перезарядись")
		# Grenade hint shown simultaneously with reload (Issue #808)
		if not _active_hints.has(HINT_GRENADE):
			_add_hint(HINT_GRENADE, "[G+ПКМ вправо] [G+ПКМ→отпусти G] [ПКМ бросок]")

	func _show_hints_for_step(step: TutorialStep) -> void:
		match step:
			TutorialStep.SWITCH_FIRE_MODE:
				_add_hint(HINT_FIRE_MODE, "[B] Переключи режим стрельбы")
			TutorialStep.RELOAD:
				_add_reload_hints()
			TutorialStep.SCOPE_TRAINING:
				_add_hint(HINT_SCOPE, "[ПКМ] Прицелься через оптику")
				if not _active_hints.has(HINT_GRENADE):
					_add_hint(HINT_GRENADE, "[G+ПКМ вправо] [G+ПКМ→отпусти G] [ПКМ бросок]")
			TutorialStep.THROW_GRENADE:
				if not _active_hints.has(HINT_GRENADE):
					_add_hint(HINT_GRENADE, "[G+ПКМ вправо] [G+ПКМ→отпусти G] [ПКМ бросок]")
			TutorialStep.COMPLETED:
				_active_hints.clear()

	func on_fire_mode_changed() -> void:
		if _current_step != TutorialStep.SWITCH_FIRE_MODE:
			return
		if not _has_switched_fire_mode:
			_has_switched_fire_mode = true
			_dismiss_hint(HINT_FIRE_MODE)
			advance_to_step(TutorialStep.RELOAD)

	func on_sniper_bolt_step_changed(step: int, total_steps: int) -> void:
		if _current_step != TutorialStep.RELOAD:
			return
		if step >= total_steps and not _sniper_bolt_cycled:
			_sniper_bolt_cycled = true
			_has_reloaded = true
			_dismiss_hint(HINT_RELOAD)
			_dismiss_hint(HINT_BOLT_CYCLE)
			advance_to_step(TutorialStep.SCOPE_TRAINING)

	func on_scope_state_changed(is_active: bool) -> void:
		if _current_step != TutorialStep.SCOPE_TRAINING:
			return
		if is_active and not _scope_used:
			_scope_used = true
			_dismiss_hint(HINT_SCOPE)
			advance_to_step(TutorialStep.THROW_GRENADE)

	func on_reload_completed() -> void:
		if _current_step != TutorialStep.RELOAD:
			return
		if not _has_reloaded:
			_has_reloaded = true
			_dismiss_hint(HINT_RELOAD)
			advance_to_step(TutorialStep.THROW_GRENADE)

	func on_grenade_thrown() -> void:
		if _current_step != TutorialStep.THROW_GRENADE:
			return
		if not _has_thrown_grenade:
			_has_thrown_grenade = true
			_dismiss_hint(HINT_GRENADE)
			advance_to_step(TutorialStep.COMPLETED)

	func is_tutorial_complete() -> bool:
		return _current_step == TutorialStep.COMPLETED

	func set_initial_step_based_on_weapon(has_assault_rifle: bool) -> void:
		if has_assault_rifle:
			_current_step = TutorialStep.SWITCH_FIRE_MODE
			_add_hint(HINT_FIRE_MODE, "[B] Переключи режим стрельбы")
		else:
			_current_step = TutorialStep.RELOAD
			_add_reload_hints()


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


func test_initial_fire_mode_hint_shown() -> void:
	tutorial.set_initial_step_based_on_weapon(true)
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_FIRE_MODE),
		"Fire mode hint should be active initially for assault rifle")


func test_tutorial_not_complete_initially() -> void:
	assert_false(tutorial.is_tutorial_complete(), "Tutorial should not be complete initially")


# ============================================================================
# Multi-Hint Simultaneous Display Tests (Issue #808)
# ============================================================================


func test_reload_and_grenade_hints_shown_simultaneously() -> void:
	tutorial.set_initial_step_based_on_weapon(false)

	# Both reload and grenade hints should be active at the same time
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD),
		"Reload hint should be active during RELOAD step")
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_GRENADE),
		"Grenade hint should be active simultaneously with reload hint (Issue #808)")


func test_reload_hint_dismissed_grenade_hint_remains() -> void:
	tutorial.set_initial_step_based_on_weapon(false)

	# Complete reload
	tutorial.on_reload_completed()

	# Only reload hint should be gone; grenade hint should remain
	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD),
		"Reload hint should be dismissed after reload completes")
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_GRENADE),
		"Grenade hint should remain visible after reload (Issue #808)")


func test_grenade_hint_dismissed_after_throw() -> void:
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_reload_completed()

	tutorial.on_grenade_thrown()

	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_GRENADE),
		"Grenade hint should be dismissed after grenade is thrown")


func test_no_hints_after_completion() -> void:
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_reload_completed()
	tutorial.on_grenade_thrown()

	assert_false(tutorial.is_any_hint_active(),
		"No hints should be active after tutorial completion")


# ============================================================================
# Weapon Special Feature Hint Tests (Issue #808)
# ============================================================================


func test_sniper_shows_bolt_cycle_hint_separately() -> void:
	tutorial._has_sniper_rifle = true
	tutorial.set_initial_step_based_on_weapon(false)

	# Both bolt cycle hint and reload hint should be separate lines
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD),
		"Sniper should have reload hint")
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_BOLT_CYCLE),
		"Sniper should have separate bolt-cycle hint (weapon special feature, Issue #808)")
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_GRENADE),
		"Grenade hint should also be shown simultaneously")


func test_sniper_bolt_cycle_dismisses_bolt_hint_not_grenade() -> void:
	tutorial._has_sniper_rifle = true
	tutorial.set_initial_step_based_on_weapon(false)

	# Simulate bolt cycle completed
	tutorial.on_sniper_bolt_step_changed(4, 4)

	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_BOLT_CYCLE),
		"Bolt cycle hint should be dismissed after bolt cycling")
	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD),
		"Reload hint dismissed after sniper bolt cycle completes")
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_GRENADE),
		"Grenade hint should remain (Issue #808)")


func test_sniper_scope_hint_shown_after_bolt_cycle() -> void:
	tutorial._has_sniper_rifle = true
	tutorial.set_initial_step_based_on_weapon(false)

	tutorial.on_sniper_bolt_step_changed(4, 4)

	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_SCOPE),
		"Scope hint should appear after bolt cycling")
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_GRENADE),
		"Grenade hint remains alongside scope hint (Issue #808)")


func test_sniper_scope_dismissed_grenade_remains() -> void:
	tutorial._has_sniper_rifle = true
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_sniper_bolt_step_changed(4, 4)

	tutorial.on_scope_state_changed(true)

	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_SCOPE),
		"Scope hint dismissed after scope used")
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_GRENADE),
		"Grenade hint remains after scope training (Issue #808)")


func test_revolver_shows_reload_hint() -> void:
	tutorial._has_revolver = true
	tutorial.set_initial_step_based_on_weapon(false)

	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD),
		"Revolver should have reload hint")
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_GRENADE),
		"Grenade hint shown simultaneously with revolver reload (Issue #808)")


func test_shotgun_shows_reload_hint() -> void:
	tutorial._has_shotgun = true
	tutorial.set_initial_step_based_on_weapon(false)

	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD),
		"Shotgun should have reload hint")
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_GRENADE),
		"Grenade hint shown simultaneously with shotgun reload (Issue #808)")


# ============================================================================
# Step Progression Tests
# ============================================================================


func test_fire_mode_change_advances_to_reload() -> void:
	tutorial.set_initial_step_based_on_weapon(true)

	tutorial.on_fire_mode_changed()

	assert_eq(tutorial.get_current_step(), MockTutorialLevel.TutorialStep.RELOAD,
		"Should advance to RELOAD after switching fire mode")


func test_fire_mode_hint_dismissed_on_switch() -> void:
	tutorial.set_initial_step_based_on_weapon(true)

	tutorial.on_fire_mode_changed()

	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_FIRE_MODE),
		"Fire mode hint should be dismissed after switching fire mode")


func test_reload_advances_to_grenade() -> void:
	tutorial.set_initial_step_based_on_weapon(false)

	tutorial.on_reload_completed()

	assert_eq(tutorial.get_current_step(), MockTutorialLevel.TutorialStep.THROW_GRENADE,
		"Should advance to THROW_GRENADE after reload")


func test_grenade_throw_completes_tutorial() -> void:
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_reload_completed()

	tutorial.on_grenade_thrown()

	assert_eq(tutorial.get_current_step(), MockTutorialLevel.TutorialStep.COMPLETED,
		"Should advance to COMPLETED after throwing grenade")
	assert_true(tutorial.is_tutorial_complete(), "Tutorial should be complete")


# ============================================================================
# State Guard Tests
# ============================================================================


func test_fire_mode_change_ignored_in_wrong_step() -> void:
	tutorial.advance_to_step(MockTutorialLevel.TutorialStep.RELOAD)

	tutorial.on_fire_mode_changed()

	assert_eq(tutorial.get_current_step(), MockTutorialLevel.TutorialStep.RELOAD,
		"Fire mode change should be ignored in RELOAD step")


func test_reload_ignored_in_wrong_step() -> void:
	tutorial.set_initial_step_based_on_weapon(true)

	tutorial.on_reload_completed()

	assert_eq(tutorial.get_current_step(), MockTutorialLevel.TutorialStep.SWITCH_FIRE_MODE,
		"Reload should be ignored in SWITCH_FIRE_MODE step")


func test_grenade_throw_ignored_in_wrong_step() -> void:
	tutorial.advance_to_step(MockTutorialLevel.TutorialStep.RELOAD)
	tutorial._add_reload_hints()

	tutorial.on_grenade_thrown()

	assert_eq(tutorial.get_current_step(), MockTutorialLevel.TutorialStep.RELOAD,
		"Grenade throw should be ignored in RELOAD step")


# ============================================================================
# Full Tutorial Flow Tests
# ============================================================================


func test_complete_tutorial_flow_with_rifle() -> void:
	tutorial._has_assault_rifle = true
	tutorial.set_initial_step_based_on_weapon(true)

	# Step 1: Switch fire mode
	assert_eq(tutorial.get_current_step(), MockTutorialLevel.TutorialStep.SWITCH_FIRE_MODE)
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_FIRE_MODE))

	tutorial.on_fire_mode_changed()

	# Step 2: Reload (and grenade shown simultaneously)
	assert_eq(tutorial.get_current_step(), MockTutorialLevel.TutorialStep.RELOAD)
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD),
		"Reload hint active")
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_GRENADE),
		"Grenade hint active simultaneously with reload (Issue #808)")

	tutorial.on_reload_completed()

	# Step 3: Throw grenade (reload hint gone, grenade hint remains)
	assert_eq(tutorial.get_current_step(), MockTutorialLevel.TutorialStep.THROW_GRENADE)
	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD),
		"Reload hint gone")
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_GRENADE),
		"Grenade hint still active")

	tutorial.on_grenade_thrown()

	# Step 4: Complete
	assert_true(tutorial.is_tutorial_complete(), "Tutorial should be complete")
	assert_false(tutorial.is_any_hint_active(), "No hints remain after completion")


func test_complete_tutorial_flow_without_rifle() -> void:
	tutorial._has_assault_rifle = false
	tutorial.set_initial_step_based_on_weapon(false)

	# Should skip fire mode step and start with reload + grenade simultaneously
	assert_eq(tutorial.get_current_step(), MockTutorialLevel.TutorialStep.RELOAD,
		"Should start with reload step without assault rifle")
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD))
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_GRENADE),
		"Grenade hint shown from start alongside reload (Issue #808)")

	tutorial.on_reload_completed()

	assert_eq(tutorial.get_current_step(), MockTutorialLevel.TutorialStep.THROW_GRENADE)
	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD))
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_GRENADE))

	tutorial.on_grenade_thrown()

	assert_true(tutorial.is_tutorial_complete())
	assert_false(tutorial.is_any_hint_active())


func test_complete_sniper_flow() -> void:
	tutorial._has_sniper_rifle = true
	tutorial.set_initial_step_based_on_weapon(false)

	# Sniper starts with reload + bolt cycle + grenade hints all simultaneously
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD))
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_BOLT_CYCLE))
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_GRENADE))

	# Complete bolt cycling
	tutorial.on_sniper_bolt_step_changed(4, 4)

	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD))
	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_BOLT_CYCLE))
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_SCOPE))
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_GRENADE))

	# Use scope
	tutorial.on_scope_state_changed(true)

	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_SCOPE))
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_GRENADE))

	# Throw grenade
	tutorial.on_grenade_thrown()

	assert_true(tutorial.is_tutorial_complete())
	assert_false(tutorial.is_any_hint_active())
