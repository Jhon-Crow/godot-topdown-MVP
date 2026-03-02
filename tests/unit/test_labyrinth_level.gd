extends GutTest
## Unit tests for the LabyrinthLevel tutorial hint system.
##
## Tests Issue #945 changes applied to the Laboratory level:
## (1) Reload hint appears only after 2 shots (same as tutorial_level.gd).
## (2) Each simultaneous hint has a unique color.
## (3) The NEXT button in a multi-step reload is highlighted in red using BBCode.
##
## Also validates Issue #808 behaviour: reload and grenade hints are shown
## simultaneously, and each dismisses independently.


# ============================================================================
# Mock Labyrinth Tutorial Hint System
# ============================================================================


class MockLabyrinthTutorial:
	## Tutorial step machine (mirrors labyrinth_level.gd).
	enum TutorialStep {
		RELOAD,
		THROW_GRENADE,
		COMPLETED
	}

	## Hint keys (mirrors labyrinth_level.gd constants).
	const TUTORIAL_HINT_RELOAD := "reload"
	const TUTORIAL_HINT_GRENADE := "grenade"
	const TUTORIAL_HINT_HAMMER_COCK := "hammer_cock"
	const TUTORIAL_HINT_BOLT_CYCLE := "bolt_cycle"

	## Unique colors per hint type (Issue #945).
	const TUTORIAL_HINT_COLOR_RELOAD := Color(0.4, 1.0, 0.5, 1.0)
	const TUTORIAL_HINT_COLOR_GRENADE := Color(1.0, 0.65, 0.0, 1.0)
	const TUTORIAL_HINT_COLOR_BOLT_CYCLE := Color(0.85, 0.6, 1.0, 1.0)
	const TUTORIAL_HINT_COLOR_HAMMER_COCK := Color(1.0, 0.8, 0.3, 1.0)

	var _tutorial_step: TutorialStep = TutorialStep.RELOAD
	var _tutorial_has_reloaded: bool = false
	var _tutorial_has_thrown_grenade: bool = false
	var _tutorial_has_shotgun: bool = false
	var _tutorial_has_sniper_rifle: bool = false
	var _tutorial_has_revolver: bool = false
	var _tutorial_has_makarov_pm: bool = false

	## Issue #945: shot counter and reveal flag.
	var _tutorial_shots_fired: int = 0
	var _tutorial_reload_hint_revealed: bool = false

	## Active hints: hint_key -> hint_text (simulates visible labels).
	var _active_hints: Dictionary = {}
	## Active hint colors: hint_key -> Color (Issue #945).
	var _active_hint_colors: Dictionary = {}

	func is_hint_active(hint_key: String) -> bool:
		return _active_hints.has(hint_key)

	func is_any_hint_active() -> bool:
		return not _active_hints.is_empty()

	func get_hint_text(hint_key: String) -> String:
		return _active_hints.get(hint_key, "")

	func get_hint_color(hint_key: String) -> Color:
		return _active_hint_colors.get(hint_key, Color.WHITE)

	func get_active_hint_count() -> int:
		return _active_hints.size()

	func get_step() -> TutorialStep:
		return _tutorial_step

	func _get_tutorial_hint_color(hint_key: String) -> Color:
		match hint_key:
			TUTORIAL_HINT_RELOAD:
				return TUTORIAL_HINT_COLOR_RELOAD
			TUTORIAL_HINT_GRENADE:
				return TUTORIAL_HINT_COLOR_GRENADE
			TUTORIAL_HINT_BOLT_CYCLE:
				return TUTORIAL_HINT_COLOR_BOLT_CYCLE
			TUTORIAL_HINT_HAMMER_COCK:
				return TUTORIAL_HINT_COLOR_HAMMER_COCK
			_:
				return Color(1.0, 1.0, 0.3, 1.0)

	func _add_hint(hint_key: String, text: String) -> void:
		_active_hints[hint_key] = text
		_active_hint_colors[hint_key] = _get_tutorial_hint_color(hint_key)

	func _dismiss_hint(hint_key: String) -> void:
		_active_hints.erase(hint_key)
		_active_hint_colors.erase(hint_key)

	## Build BBCode text for the reload hint based on current step (Issue #945).
	func _build_tutorial_reload_hint_bbcode(step: int, total: int) -> String:
		if _tutorial_has_makarov_pm or (not _tutorial_has_revolver and not _tutorial_has_sniper_rifle
				and not _tutorial_has_shotgun and total == 2):
			match step:
				1:
					return "[color=#ff4444][R][/color] [color=#888888][R][/color] Перезарядись"
				2:
					return "[color=#888888][R][/color] [color=#ff4444][R][/color] Перезарядись"
				_:
					return "[R] [R] Перезарядись"
		else:
			match step:
				1:
					return "[color=#ff4444][R][/color] [color=#888888][F] [R][/color] Перезарядись"
				2:
					return "[color=#888888][R][/color] [color=#ff4444][F][/color] [color=#888888][R][/color] Перезарядись"
				3:
					return "[color=#888888][R] [F][/color] [color=#ff4444][R][/color] Перезарядись"
				_:
					return "[R] [F] [R] Перезарядись"

	func _add_tutorial_reload_hints() -> void:
		if _tutorial_has_shotgun:
			_add_hint(TUTORIAL_HINT_RELOAD,
				"[color=#ff4444][ПКМ↑ открыть][/color] [color=#888888][СКМ+ПКМ↓ x8] [ПКМ↓ закрыть][/color]")
		elif _tutorial_has_sniper_rifle:
			_add_hint(TUTORIAL_HINT_RELOAD,
				"[color=#ff4444][R][/color] [color=#888888][F] [R][/color] Перезарядись")
			_add_hint(TUTORIAL_HINT_BOLT_CYCLE,
				"[color=#ff4444][←↓↑→][/color] Передёрни затвор")
		elif _tutorial_has_revolver:
			_add_hint(TUTORIAL_HINT_RELOAD,
				"[color=#ff4444][R открыть][/color] [color=#888888][ПКМ↑ патрон] [скролл] [R закрыть][/color]")
			_add_hint(TUTORIAL_HINT_HAMMER_COCK,
				"[color=#ff4444][ПКМ][/color] Взведи курок")
		elif _tutorial_has_makarov_pm:
			_add_hint(TUTORIAL_HINT_RELOAD,
				"[color=#ff4444][R][/color] [color=#888888][R][/color] Перезарядись")
		else:
			_add_hint(TUTORIAL_HINT_RELOAD,
				"[color=#ff4444][R][/color] [color=#888888][F] [R][/color] Перезарядись")
		if not _active_hints.has(TUTORIAL_HINT_GRENADE):
			_add_hint(TUTORIAL_HINT_GRENADE,
				"[color=#ff4444][G+ПКМ вправо][/color] [color=#888888][G+ПКМ→отпусти G] [ПКМ бросок][/color]")

	## Simulate _setup_tutorial_hints(): only sets the step, does NOT show hints (Issue #945).
	func setup_tutorial_hints() -> void:
		_tutorial_step = TutorialStep.RELOAD

	## Simulate _on_tutorial_weapon_fired() (Issue #945).
	func on_tutorial_weapon_fired() -> void:
		if _tutorial_reload_hint_revealed:
			return
		_tutorial_shots_fired += 1
		if _tutorial_shots_fired >= 2:
			_tutorial_reload_hint_revealed = true
			_reveal_tutorial_reload_hint()

	func _reveal_tutorial_reload_hint() -> void:
		if _tutorial_step != TutorialStep.RELOAD:
			return
		_add_tutorial_reload_hints()

	## Simulate _on_tutorial_reload_sequence_progress() (Issue #945).
	func on_tutorial_reload_sequence_progress(step: int, total: int) -> void:
		if not _active_hints.has(TUTORIAL_HINT_RELOAD):
			return
		_active_hints[TUTORIAL_HINT_RELOAD] = _build_tutorial_reload_hint_bbcode(step, total)

	## Simulate _on_tutorial_reload_completed() (Issue #808).
	func on_tutorial_reload_completed() -> void:
		if _tutorial_step != TutorialStep.RELOAD:
			return
		if not _tutorial_has_reloaded:
			_tutorial_has_reloaded = true
			_dismiss_hint(TUTORIAL_HINT_RELOAD)
			_dismiss_hint(TUTORIAL_HINT_HAMMER_COCK)
			if _tutorial_has_thrown_grenade:
				_tutorial_step = TutorialStep.COMPLETED
				_dismiss_all_hints()
			else:
				_tutorial_step = TutorialStep.THROW_GRENADE
				if not _active_hints.has(TUTORIAL_HINT_GRENADE):
					_add_hint(TUTORIAL_HINT_GRENADE,
						"[color=#ff4444][G+ПКМ вправо][/color] [color=#888888][G+ПКМ→отпусти G] [ПКМ бросок][/color]")

	## Simulate _on_tutorial_grenade_thrown() (Issue #808).
	func on_tutorial_grenade_thrown() -> void:
		if _tutorial_step != TutorialStep.THROW_GRENADE and _tutorial_step != TutorialStep.RELOAD:
			return
		if not _tutorial_has_thrown_grenade:
			_tutorial_has_thrown_grenade = true
			_dismiss_hint(TUTORIAL_HINT_GRENADE)
			if _tutorial_step == TutorialStep.THROW_GRENADE:
				_tutorial_step = TutorialStep.COMPLETED
				_dismiss_all_hints()

	## Simulate _on_tutorial_sniper_bolt_step_changed() (Issue #808).
	func on_tutorial_sniper_bolt_step_changed(step: int, total_steps: int) -> void:
		if _tutorial_step != TutorialStep.RELOAD:
			return
		if step >= total_steps and not _tutorial_has_reloaded:
			_tutorial_has_reloaded = true
			_dismiss_hint(TUTORIAL_HINT_RELOAD)
			_dismiss_hint(TUTORIAL_HINT_BOLT_CYCLE)
			if _tutorial_has_thrown_grenade:
				_tutorial_step = TutorialStep.COMPLETED
				_dismiss_all_hints()
			else:
				_tutorial_step = TutorialStep.THROW_GRENADE

	## Simulate _on_tutorial_hammer_cocked() (Issue #808).
	func on_tutorial_hammer_cocked() -> void:
		_dismiss_hint(TUTORIAL_HINT_HAMMER_COCK)

	func _dismiss_all_hints() -> void:
		_active_hints.clear()
		_active_hint_colors.clear()


var lab: MockLabyrinthTutorial


func before_each() -> void:
	lab = MockLabyrinthTutorial.new()
	lab.setup_tutorial_hints()


func after_each() -> void:
	lab = null


# ============================================================================
# Issue #945: No Hints at Level Start — Reload Hint Delayed Until 2 Shots
# ============================================================================


func test_no_hints_shown_at_level_start() -> void:
	## Issue #945: No hints (reload or grenade) should appear immediately on level load.
	assert_false(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_RELOAD),
		"Reload hint must NOT be shown at Lab level start (Issue #945)")
	assert_false(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_GRENADE),
		"Grenade hint must NOT be shown at Lab level start (Issue #945)")
	assert_false(lab.is_any_hint_active(),
		"No tutorial hints should be visible at Lab level start (Issue #945)")


func test_reload_hint_not_shown_after_one_shot() -> void:
	## Issue #945: After only 1 shot, reload hint should still be hidden.
	lab.on_tutorial_weapon_fired()

	assert_false(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_RELOAD),
		"Reload hint should NOT appear after only 1 shot (Issue #945)")
	assert_false(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_GRENADE),
		"Grenade hint should NOT appear after only 1 shot (Issue #945)")


func test_reload_hint_shown_after_two_shots() -> void:
	## Issue #945: After 2 shots, reload and grenade hints should both appear.
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_weapon_fired()

	assert_true(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_RELOAD),
		"Reload hint should appear after 2 shots (Issue #945)")
	assert_true(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_GRENADE),
		"Grenade hint should also appear after 2 shots (Issue #945)")


func test_reload_hint_shown_after_more_than_two_shots() -> void:
	## Issue #945: If player fires 3+ shots, reload hint still appears.
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_weapon_fired()  # Extra shot after reveal

	assert_true(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_RELOAD),
		"Reload hint should remain after more than 2 shots (Issue #945)")


func test_weapon_fired_idempotent_after_reveal() -> void:
	## Issue #945: Additional shots after reveal should not cause duplicate hints.
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_weapon_fired()  # Extra shots after reveal
	lab.on_tutorial_weapon_fired()

	# Standard weapon: reload + grenade = 2 hints
	assert_eq(lab.get_active_hint_count(), 2,
		"Only 2 hints (reload + grenade) should be active (Issue #945)")


# ============================================================================
# Issue #945: Unique Colors per Hint
# ============================================================================


func test_reload_hint_has_green_color() -> void:
	## Issue #945: Reload hint should use green.
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_weapon_fired()

	assert_eq(lab.get_hint_color(MockLabyrinthTutorial.TUTORIAL_HINT_RELOAD),
		MockLabyrinthTutorial.TUTORIAL_HINT_COLOR_RELOAD,
		"Reload hint should have green color (Issue #945)")


func test_grenade_hint_has_orange_color() -> void:
	## Issue #945: Grenade hint should use orange.
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_weapon_fired()

	assert_eq(lab.get_hint_color(MockLabyrinthTutorial.TUTORIAL_HINT_GRENADE),
		MockLabyrinthTutorial.TUTORIAL_HINT_COLOR_GRENADE,
		"Grenade hint should have orange color (Issue #945)")


func test_bolt_cycle_hint_has_purple_color() -> void:
	## Issue #945: Bolt cycle hint should use purple (sniper).
	lab._tutorial_has_sniper_rifle = true
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_weapon_fired()

	assert_eq(lab.get_hint_color(MockLabyrinthTutorial.TUTORIAL_HINT_BOLT_CYCLE),
		MockLabyrinthTutorial.TUTORIAL_HINT_COLOR_BOLT_CYCLE,
		"Bolt cycle hint should have purple color (Issue #945)")


func test_hammer_cock_hint_has_yellow_color() -> void:
	## Issue #945: Hammer cock hint should use yellow (revolver).
	lab._tutorial_has_revolver = true
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_weapon_fired()

	assert_eq(lab.get_hint_color(MockLabyrinthTutorial.TUTORIAL_HINT_HAMMER_COCK),
		MockLabyrinthTutorial.TUTORIAL_HINT_COLOR_HAMMER_COCK,
		"Hammer cock hint should have yellow color (Issue #945)")


func test_simultaneous_hints_have_different_colors() -> void:
	## Issue #945: Reload and grenade hints shown at the same time must have different colors.
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_weapon_fired()

	var reload_color := lab.get_hint_color(MockLabyrinthTutorial.TUTORIAL_HINT_RELOAD)
	var grenade_color := lab.get_hint_color(MockLabyrinthTutorial.TUTORIAL_HINT_GRENADE)

	assert_ne(reload_color, grenade_color,
		"Simultaneously shown hints must use different colors (Issue #945)")


# ============================================================================
# Issue #945: Red Highlight on NEXT Button in Multi-Step Reload
# ============================================================================


func test_reload_hint_initial_text_has_red_first_step() -> void:
	## Issue #945: Initial reload hint shows first step (R) in red.
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_weapon_fired()

	var hint_text: String = lab.get_hint_text(MockLabyrinthTutorial.TUTORIAL_HINT_RELOAD)
	assert_true(hint_text.contains("[color=#ff4444]"),
		"Reload hint should contain red colour markup (Issue #945)")
	assert_true(hint_text.begins_with("[color=#ff4444][R]"),
		"First [R] should be highlighted red in initial reload hint (Issue #945)")


func test_reload_sequence_step1_highlights_r_red() -> void:
	## Issue #945: Step 1 — R highlighted red, rest greyed.
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_reload_sequence_progress(1, 3)

	var hint_text: String = lab.get_hint_text(MockLabyrinthTutorial.TUTORIAL_HINT_RELOAD)
	assert_true(hint_text.contains("[color=#ff4444][R]"),
		"Step 1: [R] should be highlighted red (Issue #945)")
	assert_true(hint_text.contains("[color=#888888]"),
		"Step 1: subsequent steps should be greyed (Issue #945)")


func test_reload_sequence_step2_highlights_f_red() -> void:
	## Issue #945: Step 2 — F highlighted red.
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_reload_sequence_progress(2, 3)

	var hint_text: String = lab.get_hint_text(MockLabyrinthTutorial.TUTORIAL_HINT_RELOAD)
	assert_true(hint_text.contains("[color=#ff4444][F]"),
		"Step 2: [F] should be highlighted red (Issue #945)")


func test_reload_sequence_step3_highlights_final_r_red() -> void:
	## Issue #945: Step 3 — final R highlighted red.
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_reload_sequence_progress(3, 3)

	var hint_text: String = lab.get_hint_text(MockLabyrinthTutorial.TUTORIAL_HINT_RELOAD)
	assert_true(hint_text.ends_with("[color=#ff4444][R][/color] Перезарядись"),
		"Step 3: final [R] should be highlighted red (Issue #945)")


func test_makarov_pm_reload_hint_has_two_steps() -> void:
	## Issue #945: Makarov PM uses R -> R reload (2 steps).
	lab._tutorial_has_makarov_pm = true
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_weapon_fired()

	var hint_text: String = lab.get_hint_text(MockLabyrinthTutorial.TUTORIAL_HINT_RELOAD)
	assert_true(hint_text.contains("[R]") and hint_text.contains("[R]"),
		"Makarov PM hint should show [R] [R] sequence (Issue #945)")
	assert_false(hint_text.contains("[F]"),
		"Makarov PM hint should NOT contain [F] (only R -> R reload) (Issue #945)")


# ============================================================================
# Issue #808: Simultaneous Hints and Independent Dismissal
# ============================================================================


func test_reload_and_grenade_hints_shown_simultaneously() -> void:
	## Issue #808: Reload and grenade hints are shown at the same time.
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_weapon_fired()

	assert_true(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_RELOAD),
		"Reload hint should be visible (Issue #808)")
	assert_true(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_GRENADE),
		"Grenade hint should be visible simultaneously (Issue #808)")


func test_reload_dismisses_only_reload_hint() -> void:
	## Issue #808: Completing reload removes only the reload hint; grenade hint stays.
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_reload_completed()

	assert_false(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_RELOAD),
		"Reload hint should be gone after reload (Issue #808)")
	assert_true(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_GRENADE),
		"Grenade hint should remain after reload (Issue #808)")


func test_grenade_dismisses_only_grenade_hint() -> void:
	## Issue #808: Throwing grenade (from RELOAD step) removes only the grenade hint.
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_grenade_thrown()

	assert_true(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_RELOAD),
		"Reload hint should remain after grenade thrown during reload step (Issue #808)")
	assert_false(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_GRENADE),
		"Grenade hint should be gone after grenade thrown (Issue #808)")


func test_both_hints_dismissed_after_both_actions() -> void:
	## Issue #808: When both actions complete, all hints disappear.
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_reload_completed()
	lab.on_tutorial_grenade_thrown()

	assert_false(lab.is_any_hint_active(),
		"All hints should be gone after completing both actions (Issue #808)")


func test_sniper_shows_bolt_cycle_hint() -> void:
	## Issue #808: Sniper rifle shows bolt-cycle hint alongside reload hint.
	lab._tutorial_has_sniper_rifle = true
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_weapon_fired()

	assert_true(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_RELOAD),
		"Sniper: reload hint should be visible (Issue #808)")
	assert_true(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_BOLT_CYCLE),
		"Sniper: bolt-cycle hint should be visible (Issue #808)")
	assert_true(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_GRENADE),
		"Sniper: grenade hint should be visible simultaneously (Issue #808)")


func test_revolver_shows_hammer_cock_hint() -> void:
	## Issue #808: Revolver shows hammer-cock hint alongside reload hint.
	lab._tutorial_has_revolver = true
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_weapon_fired()

	assert_true(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_RELOAD),
		"Revolver: reload hint should be visible (Issue #808)")
	assert_true(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_HAMMER_COCK),
		"Revolver: hammer-cock hint should be visible (Issue #808)")
	assert_true(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_GRENADE),
		"Revolver: grenade hint should be visible simultaneously (Issue #808)")


func test_hammer_cocked_dismisses_only_hammer_hint() -> void:
	## Issue #808: Cocking the revolver hammer removes only the hammer hint.
	lab._tutorial_has_revolver = true
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_hammer_cocked()

	assert_false(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_HAMMER_COCK),
		"Hammer-cock hint should be dismissed after cocking (Issue #808)")
	assert_true(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_RELOAD),
		"Reload hint should remain after cocking the hammer (Issue #808)")


func test_sniper_bolt_completion_dismisses_reload_and_bolt_hints() -> void:
	## Issue #808: Completing bolt-action cycle removes reload + bolt hints.
	lab._tutorial_has_sniper_rifle = true
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_sniper_bolt_step_changed(4, 4)  # Bolt fully cycled

	assert_false(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_RELOAD),
		"Reload hint should be gone after bolt-cycle completion (Issue #808)")
	assert_false(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_BOLT_CYCLE),
		"Bolt-cycle hint should be gone after bolt-cycle completion (Issue #808)")
	assert_true(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_GRENADE),
		"Grenade hint should remain after bolt-cycle completion (Issue #808)")


func test_grenade_thrown_before_reload_stays_in_reload_step() -> void:
	## Issue #808: Throwing grenade while still in RELOAD step does not skip reload.
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_grenade_thrown()

	assert_eq(lab.get_step(), MockLabyrinthTutorial.TutorialStep.RELOAD,
		"Should remain in RELOAD step after throwing grenade early (Issue #808)")
	assert_true(lab.is_hint_active(MockLabyrinthTutorial.TUTORIAL_HINT_RELOAD),
		"Reload hint should still be visible (Issue #808)")


func test_shotgun_reload_hint_uses_bbcode_red() -> void:
	## Issue #945: Shotgun reload hint uses BBCode with red highlight on first action.
	lab._tutorial_has_shotgun = true
	lab.on_tutorial_weapon_fired()
	lab.on_tutorial_weapon_fired()

	var hint_text: String = lab.get_hint_text(MockLabyrinthTutorial.TUTORIAL_HINT_RELOAD)
	assert_true(hint_text.contains("[color=#ff4444]"),
		"Shotgun reload hint should highlight first action in red (Issue #945)")
	assert_true(hint_text.contains("ПКМ↑ открыть"),
		"Shotgun reload hint should contain the open-bolt instruction")
