extends GutTest
## Unit tests for Tutorial level script.
##
## Tests the tutorial flow state machine, multi-hint display logic, and step progression.
## Issue #808: reload and grenade hints are shown simultaneously; each completes independently.
## Issue #945: (1) Reload hint appears after 2 shots. (2) Simultaneous hints use different colors.
## (3) The NEXT button in multi-step actions is highlighted in red using BBCode.
##
## Bug fixes (second review round):
## Fix #1: Hint spacing increased to 50px to prevent overlap when hints wrap to 2 lines.
## Fix #2: `step` in ReloadSequenceProgress is LAST COMPLETED step (0=nothing done);
##          highlight step+1 as next.
## Fix #3: Revolver hammer-cock hint shown from weapon pickup (before 2 shots).
## Fix #4: Bolt-cycle hint (sniper/shotgun) shown after 1st shot, not 2nd.
## Fix #5: Revolver/shotgun reload hints are static; ReloadSequenceProgress must not overwrite them.


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
	const HINT_HAMMER_COCK := "hammer_cock"

	## Unique colors for each hint (Issue #945)
	const HINT_COLOR_FIRE_MODE := Color(0.3, 0.9, 1.0, 1.0)
	const HINT_COLOR_RELOAD := Color(0.4, 1.0, 0.5, 1.0)
	const HINT_COLOR_GRENADE := Color(1.0, 0.65, 0.0, 1.0)
	const HINT_COLOR_BOLT_CYCLE := Color(0.85, 0.6, 1.0, 1.0)
	const HINT_COLOR_SCOPE := Color(0.3, 0.9, 1.0, 1.0)
	const HINT_COLOR_HAMMER_COCK := Color(1.0, 0.8, 0.3, 1.0)

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

	## Issue #945: Shot tracking for delayed reload hint reveal
	var _shots_fired: int = 0
	var _reload_hint_revealed: bool = false
	## Bug fix #4: bolt-cycle hint revealed after 1st shot (sniper/shotgun)
	var _bolt_cycle_hint_revealed: bool = false

	## Active hints dictionary: hint_key -> hint_text (simulates visible labels)
	var _active_hints: Dictionary = {}
	## Active hint colors dictionary: hint_key -> Color (Issue #945)
	var _active_hint_colors: Dictionary = {}

	func get_current_step() -> TutorialStep:
		return _current_step

	func get_active_hints() -> Dictionary:
		return _active_hints.duplicate()

	func get_hint_color(hint_key: String) -> Color:
		return _active_hint_colors.get(hint_key, Color.WHITE)

	func is_hint_active(hint_key: String) -> bool:
		return _active_hints.has(hint_key)

	func is_any_hint_active() -> bool:
		return not _active_hints.is_empty()

	func advance_to_step(step: TutorialStep) -> void:
		_current_step = step
		_show_hints_for_step(step)

	func _dismiss_hint(hint_key: String) -> void:
		_active_hints.erase(hint_key)
		_active_hint_colors.erase(hint_key)

	func _get_hint_color(hint_key: String) -> Color:
		match hint_key:
			HINT_FIRE_MODE:
				return HINT_COLOR_FIRE_MODE
			HINT_RELOAD:
				return HINT_COLOR_RELOAD
			HINT_GRENADE:
				return HINT_COLOR_GRENADE
			HINT_BOLT_CYCLE:
				return HINT_COLOR_BOLT_CYCLE
			HINT_SCOPE:
				return HINT_COLOR_SCOPE
			HINT_HAMMER_COCK:
				return HINT_COLOR_HAMMER_COCK
			_:
				return Color(1.0, 1.0, 0.3, 1.0)

	func _add_hint(hint_key: String, text: String) -> void:
		_active_hints[hint_key] = text
		_active_hint_colors[hint_key] = _get_hint_color(hint_key)

	## Bug fix: bolt-cycle and hammer-cock hints NOT added here.
	##   Bolt-cycle shown after 1st shot (fix #4), hammer-cock shown from start (fix #3).
	func _add_reload_hints() -> void:
		if _has_shotgun:
			# Shotgun: bolt-cycle hint already shown after 1st shot; same mechanic as reload.
			pass
		elif _has_sniper_rifle:
			# Sniper: reload hint only. Bolt-cycle hint shown after 1st shot.
			_add_hint(HINT_RELOAD, _build_reload_hint_bbcode(0, 3))
		elif _has_revolver:
			# Revolver: cylinder reload hint. Hammer-cock hint shown from start (fix #3).
			_add_hint(HINT_RELOAD, "[color=#ff4444][R открыть][/color] [color=#888888][ПКМ↑ патрон] [скролл] [R закрыть][/color]")
		elif _has_makarov_pm:
			_add_hint(HINT_RELOAD, _build_reload_hint_bbcode(0, 2))
		else:
			_add_hint(HINT_RELOAD, _build_reload_hint_bbcode(0, 3))
		# Grenade hint shown simultaneously with reload (Issue #808)
		if not _active_hints.has(HINT_GRENADE):
			_add_hint(HINT_GRENADE, "[color=#ff4444][G+ПКМ вправо][/color] [color=#888888][G+ПКМ→отпусти G] [ПКМ бросок][/color]")

	func _show_hints_for_step(step: TutorialStep) -> void:
		match step:
			TutorialStep.SWITCH_FIRE_MODE:
				_add_hint(HINT_FIRE_MODE, "[color=#ff4444][B][/color] Переключи режим стрельбы")
			TutorialStep.RELOAD:
				# Issue #945: Only show reload hints if already revealed (2 shots fired)
				if _reload_hint_revealed:
					_add_reload_hints()
			TutorialStep.SCOPE_TRAINING:
				_add_hint(HINT_SCOPE, "[color=#ff4444][ПКМ][/color] Прицелься через оптику")
				if not _active_hints.has(HINT_GRENADE):
					_add_hint(HINT_GRENADE, "[color=#ff4444][G+ПКМ вправо][/color] [color=#888888][G+ПКМ→отпусти G] [ПКМ бросок][/color]")
			TutorialStep.THROW_GRENADE:
				if not _active_hints.has(HINT_GRENADE):
					_add_hint(HINT_GRENADE, "[color=#ff4444][G+ПКМ вправо][/color] [color=#888888][G+ПКМ→отпусти G] [ПКМ бросок][/color]")
			TutorialStep.COMPLETED:
				_active_hints.clear()
				_active_hint_colors.clear()

	## Issue #945: Called when the weapon fires — counts shots and reveals hints.
	## Bug fix #4: bolt-cycle hint (sniper/shotgun) shown after 1st shot.
	## Bug fix: reload hint still revealed after 2nd shot.
	func on_weapon_fired() -> void:
		_shots_fired += 1
		# Bug fix #4: reveal bolt-cycle hint after 1st shot for sniper/shotgun
		if _shots_fired >= 1 and not _bolt_cycle_hint_revealed:
			if _has_sniper_rifle or _has_shotgun:
				_bolt_cycle_hint_revealed = true
				_reveal_bolt_cycle_hint()
		if not _reload_hint_revealed and _shots_fired >= 2:
			_reload_hint_revealed = true
			_reveal_reload_hint()

	## Bug fix #4: Reveal bolt-cycle hint after 1st shot.
	func _reveal_bolt_cycle_hint() -> void:
		if _current_step != TutorialStep.RELOAD:
			return
		if _has_sniper_rifle:
			if not _active_hints.has(HINT_BOLT_CYCLE):
				_add_hint(HINT_BOLT_CYCLE, "[color=#ff4444][←↓↑→][/color] Передёрни затвор")
		elif _has_shotgun:
			if not _active_hints.has(HINT_BOLT_CYCLE):
				_add_hint(HINT_BOLT_CYCLE, "[color=#ff4444][ПКМ↑ открыть][/color] [color=#888888][СКМ+ПКМ↓ x8] [ПКМ↓ закрыть][/color]")

	func _reveal_reload_hint() -> void:
		if _current_step != TutorialStep.RELOAD:
			return
		_add_reload_hints()

	## Issue #945 + Bug fix #5: Called when reload sequence progresses.
	## Revolver/shotgun use static hints — do not overwrite them.
	## Bug fix #2: `step` is LAST COMPLETED step; highlight step+1 as next action.
	func on_reload_sequence_progress(step: int, total: int) -> void:
		# Bug fix #5: revolver and shotgun use static hints — skip dynamic update
		if _has_revolver or _has_shotgun:
			return
		if not _active_hints.has(HINT_RELOAD):
			return
		var new_text := _build_reload_hint_bbcode(step, total)
		if not new_text.is_empty():
			_active_hints[HINT_RELOAD] = new_text

	## Issue #945: Build BBCode text for reload hint with NEXT button highlighted red.
	## Bug fix #2: `step` is LAST COMPLETED step (0 = nothing done, 1 = first press done, etc.).
	## Bug fix #5: Revolver/shotgun return empty string (they have static hints).
	func _build_reload_hint_bbcode(step: int, total: int) -> String:
		# Guard: revolver and shotgun use static hints
		if _has_revolver or _has_shotgun:
			return ""
		if _has_makarov_pm or (not _has_sniper_rifle and total <= 2):
			# 2-step reload R -> R; step=0 → next is first R
			match step:
				0:
					return "[color=#ff4444][R][/color] [color=#888888][R][/color] Перезарядись"
				1:
					return "[color=#888888][R][/color] [color=#ff4444][R][/color] Перезарядись"
				_:
					return "[color=#888888][R] [R][/color] Перезарядись"
		else:
			# 3-step reload R -> F -> R; step=0 → next is first R
			match step:
				0:
					return "[color=#ff4444][R][/color] [color=#888888][F] [R][/color] Перезарядись"
				1:
					return "[color=#888888][R][/color] [color=#ff4444][F][/color] [color=#888888][R][/color] Перезарядись"
				2:
					return "[color=#888888][R] [F][/color] [color=#ff4444][R][/color] Перезарядись"
				_:
					return "[color=#888888][R] [F] [R][/color] Перезарядись"

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

	func on_hammer_cocked() -> void:
		## Dismiss hammer cock hint when hammer is cocked (RMB or LMB fire) (Issue #808).
		_dismiss_hint(HINT_HAMMER_COCK)

	func on_reload_completed() -> void:
		if _current_step != TutorialStep.RELOAD:
			return
		if not _has_reloaded:
			_has_reloaded = true
			_dismiss_hint(HINT_RELOAD)
			_dismiss_hint(HINT_HAMMER_COCK)
			# If grenade was already thrown, go to COMPLETED; otherwise wait for grenade
			if _has_thrown_grenade:
				advance_to_step(TutorialStep.COMPLETED)
			else:
				advance_to_step(TutorialStep.THROW_GRENADE)

	func on_grenade_thrown() -> void:
		# Allow grenade dismissal from RELOAD step too (thrown before reload completes)
		if _current_step != TutorialStep.THROW_GRENADE and _current_step != TutorialStep.RELOAD:
			return
		if not _has_thrown_grenade:
			_has_thrown_grenade = true
			_dismiss_hint(HINT_GRENADE)
			# If grenade thrown before reload, stay in RELOAD step (reload hint still visible)
			if _current_step == TutorialStep.THROW_GRENADE:
				advance_to_step(TutorialStep.COMPLETED)

	func is_tutorial_complete() -> bool:
		return _current_step == TutorialStep.COMPLETED

	func set_initial_step_based_on_weapon(has_assault_rifle: bool) -> void:
		if has_assault_rifle:
			_current_step = TutorialStep.SWITCH_FIRE_MODE
			_add_hint(HINT_FIRE_MODE, "[color=#ff4444][B][/color] Переключи режим стрельбы")
		else:
			_current_step = TutorialStep.RELOAD
			# Issue #945: Reload hints NOT shown at startup — appear only after 2 shots.
			# Bug fix #3: Revolver hammer-cock hint shown immediately from weapon pickup.
			if _has_revolver:
				_add_hint(HINT_HAMMER_COCK, "[color=#ff4444][ПКМ][/color] Взведи курок")


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
# Issue #945: Reload Hint Delayed Until 2 Shots Fired
# ============================================================================


func test_reload_hint_not_shown_at_start() -> void:
	## Issue #945: Reload hint must NOT appear at start — only after 2 shots.
	tutorial.set_initial_step_based_on_weapon(false)

	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD),
		"Reload hint must NOT be shown at tutorial start (Issue #945 - appears after 2 shots)")
	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_GRENADE),
		"Grenade hint must NOT be shown before reload hint (Issue #945)")


func test_reload_hint_not_shown_after_one_shot() -> void:
	## Issue #945: After only 1 shot, reload hint should still be hidden.
	tutorial.set_initial_step_based_on_weapon(false)

	tutorial.on_weapon_fired()

	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD),
		"Reload hint should NOT appear after only 1 shot (Issue #945)")


func test_reload_hint_shown_after_two_shots() -> void:
	## Issue #945: After 2 shots, both reload and grenade hints should appear.
	tutorial.set_initial_step_based_on_weapon(false)

	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD),
		"Reload hint should appear after 2 shots (Issue #945)")
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_GRENADE),
		"Grenade hint should also appear after 2 shots (Issue #945)")


func test_reload_hint_shown_after_more_than_two_shots() -> void:
	## Issue #945: If player fires 3+ shots, reload hint still appears.
	tutorial.set_initial_step_based_on_weapon(false)

	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()  # Extra shot after reveal

	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD),
		"Reload hint should remain after more than 2 shots")


func test_shots_before_fire_mode_switch_still_count() -> void:
	## Issue #945: Shots fired during fire mode step should count toward the 2-shot threshold.
	tutorial._has_assault_rifle = true
	tutorial.set_initial_step_based_on_weapon(true)

	# Fire 2 shots during fire mode step (before advancing to RELOAD step)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()
	# _reload_hint_revealed is now true, but step is SWITCH_FIRE_MODE so hints not shown yet

	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD),
		"Reload hint should NOT appear before advancing to RELOAD step")

	# Now switch fire mode to advance to RELOAD step
	tutorial.on_fire_mode_changed()

	assert_eq(tutorial.get_current_step(), MockTutorialLevel.TutorialStep.RELOAD)
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD),
		"Reload hint should appear immediately when advancing to RELOAD step (shots already counted)")


func test_weapon_fired_idempotent_after_reveal() -> void:
	## Issue #945: Additional shots after reveal should not cause duplicate hints.
	tutorial.set_initial_step_based_on_weapon(false)

	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()  # Reveal
	tutorial.on_weapon_fired()  # Additional shots should not cause issues
	tutorial.on_weapon_fired()

	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD),
		"Reload hint remains after additional shots")
	# Hint text should not be duplicated
	assert_eq(tutorial.get_active_hints().size(), 2,
		"Only 2 hints (reload + grenade) should be active, not duplicates")


# ============================================================================
# Issue #945: Unique Colors for Simultaneously Displayed Hints
# ============================================================================


func test_reload_hint_has_green_color() -> void:
	## Issue #945: Reload hint should use green color.
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	assert_eq(tutorial.get_hint_color(MockTutorialLevel.HINT_RELOAD),
		MockTutorialLevel.HINT_COLOR_RELOAD,
		"Reload hint should have green color (Issue #945 - unique colors per hint)")


func test_grenade_hint_has_orange_color() -> void:
	## Issue #945: Grenade hint should use orange color.
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	assert_eq(tutorial.get_hint_color(MockTutorialLevel.HINT_GRENADE),
		MockTutorialLevel.HINT_COLOR_GRENADE,
		"Grenade hint should have orange color (Issue #945 - unique colors per hint)")


func test_fire_mode_hint_has_cyan_color() -> void:
	## Issue #945: Fire mode hint should use cyan color.
	tutorial.set_initial_step_based_on_weapon(true)

	assert_eq(tutorial.get_hint_color(MockTutorialLevel.HINT_FIRE_MODE),
		MockTutorialLevel.HINT_COLOR_FIRE_MODE,
		"Fire mode hint should have cyan color (Issue #945 - unique colors per hint)")


func test_bolt_cycle_hint_has_purple_color() -> void:
	## Issue #945: Bolt cycle hint should use purple color.
	## Bug fix #4: Bolt-cycle hint now appears after 1st shot, not 2nd.
	tutorial._has_sniper_rifle = true
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()  # 1st shot triggers bolt-cycle hint

	assert_eq(tutorial.get_hint_color(MockTutorialLevel.HINT_BOLT_CYCLE),
		MockTutorialLevel.HINT_COLOR_BOLT_CYCLE,
		"Bolt cycle hint should have purple color (Issue #945 - unique colors per hint)")


func test_hammer_cock_hint_has_yellow_color() -> void:
	## Issue #945: Hammer cock hint should use yellow color.
	## Bug fix #3: Hammer-cock hint now appears from weapon pickup (before any shots).
	tutorial._has_revolver = true
	tutorial.set_initial_step_based_on_weapon(false)
	# No shots needed — hammer-cock hint appears immediately

	assert_eq(tutorial.get_hint_color(MockTutorialLevel.HINT_HAMMER_COCK),
		MockTutorialLevel.HINT_COLOR_HAMMER_COCK,
		"Hammer cock hint should have yellow color immediately on revolver pickup (Bug fix #3)")


func test_simultaneously_shown_hints_have_different_colors() -> void:
	## Issue #945: All simultaneously displayed hints should have different colors.
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	var reload_color := tutorial.get_hint_color(MockTutorialLevel.HINT_RELOAD)
	var grenade_color := tutorial.get_hint_color(MockTutorialLevel.HINT_GRENADE)

	assert_ne(reload_color, grenade_color,
		"Simultaneously shown hints must have different colors (Issue #945)")


# ============================================================================
# Issue #945: Red Highlight on NEXT Button in Multi-Step Actions
# ============================================================================


func test_reload_hint_initial_text_has_red_first_step() -> void:
	## Issue #945: Initial reload hint shows first step (R) in red.
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	var hint_text: String = tutorial.get_active_hints()[MockTutorialLevel.HINT_RELOAD]
	assert_true(hint_text.contains("[color=#ff4444]"),
		"Reload hint should contain red color markup for next button (Issue #945)")
	assert_true(hint_text.begins_with("[color=#ff4444][R]"),
		"First button [R] should be highlighted red at start of reload sequence (Issue #945)")


func test_reload_sequence_step0_highlights_first_r_red() -> void:
	## Bug fix #2: step=0 means nothing done yet; first [R] should be red.
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	tutorial.on_reload_sequence_progress(0, 3)

	var hint_text: String = tutorial.get_active_hints()[MockTutorialLevel.HINT_RELOAD]
	assert_true(hint_text.begins_with("[color=#ff4444][R]"),
		"Step 0: first [R] should be highlighted red (Bug fix #2 — step is last completed)")
	assert_true(hint_text.contains("[color=#888888]"),
		"Step 0: subsequent steps should be greyed (Bug fix #2)")


func test_reload_sequence_step1_highlights_f_red() -> void:
	## Bug fix #2: step=1 means R was pressed; next is F (highlighted red).
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	tutorial.on_reload_sequence_progress(1, 3)

	var hint_text: String = tutorial.get_active_hints()[MockTutorialLevel.HINT_RELOAD]
	assert_true(hint_text.contains("[color=#ff4444][F]"),
		"Step 1: [F] should be highlighted red as next button (Bug fix #2 — R just pressed)")
	assert_true(hint_text.contains("[color=#888888][R][/color]"),
		"Step 1: first [R] should be greyed (just pressed) (Bug fix #2)")


func test_reload_sequence_step2_highlights_final_r_red() -> void:
	## Bug fix #2: step=2 means R+F pressed; next is final R (highlighted red).
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	tutorial.on_reload_sequence_progress(2, 3)

	var hint_text: String = tutorial.get_active_hints()[MockTutorialLevel.HINT_RELOAD]
	assert_true(hint_text.contains("[color=#ff4444][R]"),
		"Step 2: final [R] should be highlighted red (Bug fix #2 — R+F already pressed)")
	assert_true(hint_text.contains("[color=#888888][R] [F]"),
		"Step 2: earlier steps [R] and [F] should be greyed (Bug fix #2)")


func test_reload_sequence_step3_all_greyed() -> void:
	## Bug fix #2: step=3 means all steps done; all greyed out.
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	tutorial.on_reload_sequence_progress(3, 3)

	var hint_text: String = tutorial.get_active_hints()[MockTutorialLevel.HINT_RELOAD]
	assert_false(hint_text.contains("[color=#ff4444]"),
		"Step 3: no button should be highlighted red — all steps done (Bug fix #2)")


func test_pistol_reload_step0_highlights_first_r() -> void:
	## Bug fix #2: Makarov PM step=0 — nothing done, first R is red.
	tutorial._has_makarov_pm = true
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	tutorial.on_reload_sequence_progress(0, 2)

	var hint_text: String = tutorial.get_active_hints()[MockTutorialLevel.HINT_RELOAD]
	assert_true(hint_text.begins_with("[color=#ff4444][R]"),
		"Pistol step 0: first [R] should be red (Bug fix #2)")


func test_pistol_reload_step1_highlights_second_r() -> void:
	## Bug fix #2: Makarov PM step=1 means first R pressed; second R is now red.
	tutorial._has_makarov_pm = true
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	tutorial.on_reload_sequence_progress(1, 2)

	var hint_text: String = tutorial.get_active_hints()[MockTutorialLevel.HINT_RELOAD]
	assert_true(hint_text.contains("[color=#888888][R][/color] [color=#ff4444][R]"),
		"Pistol step 1: second [R] should be red, first grayed (Bug fix #2)")


func test_pistol_reload_step2_all_greyed() -> void:
	## Bug fix #2: Makarov PM step=2 means both R pressed; all greyed.
	tutorial._has_makarov_pm = true
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	tutorial.on_reload_sequence_progress(2, 2)

	var hint_text: String = tutorial.get_active_hints()[MockTutorialLevel.HINT_RELOAD]
	assert_false(hint_text.contains("[color=#ff4444]"),
		"Pistol step 2: no button should be highlighted — both pressed (Bug fix #2)")


func test_reload_sequence_progress_ignored_when_hint_not_visible() -> void:
	## Issue #945: If reload hint is not showing (not yet revealed), progress update is safe to ignore.
	tutorial.set_initial_step_based_on_weapon(false)
	# Do NOT fire 2 shots, so reload hint is not visible

	# Should not crash and hint should not appear
	tutorial.on_reload_sequence_progress(1, 3)

	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD),
		"Reload hint should remain hidden if not yet revealed (Issue #945)")


# ============================================================================
# Multi-Hint Simultaneous Display Tests (Issue #808)
# ============================================================================


func test_reload_and_grenade_hints_shown_simultaneously() -> void:
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	# Both reload and grenade hints should be active at the same time
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD),
		"Reload hint should be active during RELOAD step")
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_GRENADE),
		"Grenade hint should be active simultaneously with reload hint (Issue #808)")


func test_reload_hint_dismissed_grenade_hint_remains() -> void:
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	# Complete reload
	tutorial.on_reload_completed()

	# Only reload hint should be gone; grenade hint should remain
	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD),
		"Reload hint should be dismissed after reload completes")
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_GRENADE),
		"Grenade hint should remain visible after reload (Issue #808)")


func test_grenade_hint_dismissed_after_throw() -> void:
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()
	tutorial.on_reload_completed()

	tutorial.on_grenade_thrown()

	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_GRENADE),
		"Grenade hint should be dismissed after grenade is thrown")


func test_no_hints_after_completion() -> void:
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()
	tutorial.on_reload_completed()
	tutorial.on_grenade_thrown()

	assert_false(tutorial.is_any_hint_active(),
		"No hints should be active after tutorial completion")


# ============================================================================
# Weapon Special Feature Hint Tests (Issue #808)
# ============================================================================


func test_sniper_bolt_cycle_hint_shown_after_first_shot() -> void:
	## Bug fix #4: Sniper bolt-cycle hint appears after 1st shot, not 2nd.
	tutorial._has_sniper_rifle = true
	tutorial.set_initial_step_based_on_weapon(false)

	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_BOLT_CYCLE),
		"Bolt-cycle hint should NOT appear before any shots")

	tutorial.on_weapon_fired()  # 1st shot

	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_BOLT_CYCLE),
		"Bolt-cycle hint should appear after 1st shot (Bug fix #4)")
	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD),
		"Reload hint should NOT appear after only 1 shot (still needs 2)")


func test_sniper_shows_bolt_cycle_hint_separately() -> void:
	## Sniper: bolt-cycle hint after 1st shot; reload hint after 2nd shot.
	tutorial._has_sniper_rifle = true
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()  # 1st shot → bolt-cycle hint
	tutorial.on_weapon_fired()  # 2nd shot → reload hint

	# Both bolt cycle hint and reload hint should be separate lines
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD),
		"Sniper should have reload hint after 2nd shot")
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_BOLT_CYCLE),
		"Sniper should have separate bolt-cycle hint (weapon special feature, Issue #808)")
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_GRENADE),
		"Grenade hint should also be shown simultaneously")


func test_sniper_bolt_cycle_dismisses_bolt_hint_not_grenade() -> void:
	tutorial._has_sniper_rifle = true
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

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
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	tutorial.on_sniper_bolt_step_changed(4, 4)

	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_SCOPE),
		"Scope hint should appear after bolt cycling")
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_GRENADE),
		"Grenade hint remains alongside scope hint (Issue #808)")


func test_sniper_scope_dismissed_grenade_remains() -> void:
	tutorial._has_sniper_rifle = true
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()
	tutorial.on_sniper_bolt_step_changed(4, 4)

	tutorial.on_scope_state_changed(true)

	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_SCOPE),
		"Scope hint dismissed after scope used")
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_GRENADE),
		"Grenade hint remains after scope training (Issue #808)")


func test_revolver_shows_hammer_cock_hint_from_start() -> void:
	## Bug fix #3: Revolver hammer-cock hint appears immediately on weapon pickup.
	tutorial._has_revolver = true
	tutorial.set_initial_step_based_on_weapon(false)

	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_HAMMER_COCK),
		"Revolver hammer-cock hint should appear immediately from weapon pickup (Bug fix #3)")
	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD),
		"Revolver reload hint should NOT appear yet (needs 2 shots)")


func test_revolver_shows_reload_hint_after_two_shots() -> void:
	tutorial._has_revolver = true
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD),
		"Revolver should have reload hint after 2 shots")
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_GRENADE),
		"Grenade hint shown simultaneously with revolver reload (Issue #808)")
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_HAMMER_COCK),
		"Hammer cock hint remains visible alongside reload (Bug fix #3)")


func test_revolver_reload_hint_not_overwritten_by_sequence_progress() -> void:
	## Bug fix #5: ReloadSequenceProgress must not overwrite revolver's static hint.
	tutorial._has_revolver = true
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	var revolver_hint_text: String = tutorial.get_active_hints()[MockTutorialLevel.HINT_RELOAD]

	# Simulate signal fire — should be ignored for revolver
	tutorial.on_reload_sequence_progress(1, 3)

	assert_eq(tutorial.get_active_hints()[MockTutorialLevel.HINT_RELOAD], revolver_hint_text,
		"Revolver reload hint should not be overwritten by ReloadSequenceProgress (Bug fix #5)")


func test_shotgun_shows_bolt_cycle_hint_after_first_shot() -> void:
	## Bug fix #4: Shotgun bolt-cycle hint appears after 1st shot.
	## Bug fix: Shotgun uses HINT_BOLT_CYCLE (not HINT_RELOAD) for its reload instruction.
	tutorial._has_shotgun = true
	tutorial.set_initial_step_based_on_weapon(false)

	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_BOLT_CYCLE),
		"Shotgun bolt-cycle hint should NOT appear before any shots")

	tutorial.on_weapon_fired()  # 1st shot

	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_BOLT_CYCLE),
		"Shotgun bolt-cycle hint should appear after 1st shot (Bug fix #4)")
	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD),
		"Shotgun does not use separate RELOAD hint — it uses bolt-cycle hint")


func test_shotgun_shows_grenade_hint_after_two_shots() -> void:
	tutorial._has_shotgun = true
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_BOLT_CYCLE),
		"Shotgun should have bolt-cycle hint")
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_GRENADE),
		"Grenade hint shown simultaneously with shotgun bolt-cycle hint (Issue #808)")


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
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	tutorial.on_reload_completed()

	assert_eq(tutorial.get_current_step(), MockTutorialLevel.TutorialStep.THROW_GRENADE,
		"Should advance to THROW_GRENADE after reload")


func test_grenade_throw_completes_tutorial() -> void:
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()
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
	# Grenade is ignored only in SWITCH_FIRE_MODE, SCOPE_TRAINING, COMPLETED steps
	tutorial.advance_to_step(MockTutorialLevel.TutorialStep.SCOPE_TRAINING)

	tutorial.on_grenade_thrown()

	assert_eq(tutorial.get_current_step(), MockTutorialLevel.TutorialStep.SCOPE_TRAINING,
		"Grenade throw should be ignored in SCOPE_TRAINING step")


# ============================================================================
# Bug Fix Tests: Grenade thrown before reload (Issue #808)
# ============================================================================


func test_grenade_thrown_during_reload_dismisses_grenade_hint() -> void:
	## When grenade is thrown before reload completes, grenade hint should disappear
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	# Throw grenade while still in RELOAD step
	tutorial.on_grenade_thrown()

	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_GRENADE),
		"Grenade hint should be dismissed even when thrown before reload (bug fix)")
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD),
		"Reload hint should still be visible after grenade thrown early")


func test_grenade_thrown_during_reload_keeps_reload_step() -> void:
	## When grenade is thrown during RELOAD step, should stay in RELOAD step
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	tutorial.on_grenade_thrown()

	assert_eq(tutorial.get_current_step(), MockTutorialLevel.TutorialStep.RELOAD,
		"Should stay in RELOAD step when grenade thrown before reload")


func test_reload_after_early_grenade_completes_tutorial() -> void:
	## When grenade thrown first and then reload completes, tutorial should finish
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	tutorial.on_grenade_thrown()  # Grenade first
	tutorial.on_reload_completed()  # Then reload

	assert_true(tutorial.is_tutorial_complete(),
		"Tutorial should complete when reload done after early grenade throw")
	assert_false(tutorial.is_any_hint_active(),
		"No hints should remain after both actions done")


func test_early_grenade_not_double_dismissed() -> void:
	## Throwing grenade twice should not cause errors (idempotent)
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	tutorial.on_grenade_thrown()
	tutorial.on_grenade_thrown()  # Second call should be ignored

	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_GRENADE),
		"Grenade hint still gone after double throw")
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD),
		"Reload hint still shown after double throw attempt")


# ============================================================================
# Revolver Hammer Cock Hint Tests (Issue #808)
# ============================================================================


func test_revolver_shows_hammer_cock_hint() -> void:
	## Bug fix #3: Hammer-cock hint shown from the very start (no shots needed).
	tutorial._has_revolver = true
	tutorial.set_initial_step_based_on_weapon(false)
	# No shots — hammer-cock hint should already be visible

	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_HAMMER_COCK),
		"Revolver should show hammer cock hint immediately on weapon pickup (Bug fix #3)")


func test_revolver_hammer_cock_hint_dismissed_on_reload() -> void:
	tutorial._has_revolver = true
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	tutorial.on_reload_completed()

	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_HAMMER_COCK),
		"Hammer cock hint should be dismissed when reload completes")
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_GRENADE),
		"Grenade hint should remain after revolver reload")


func test_revolver_has_reload_and_hammer_and_grenade_hints() -> void:
	tutorial._has_revolver = true
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD),
		"Revolver reload hint shown")
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_HAMMER_COCK),
		"Revolver hammer cock hint shown simultaneously")
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_GRENADE),
		"Grenade hint shown simultaneously (Issue #808)")


func test_non_revolver_no_hammer_cock_hint() -> void:
	## Other weapons should not show hammer cock hint
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_HAMMER_COCK),
		"Default weapon should not have hammer cock hint")


func test_revolver_hammer_cocked_dismisses_hammer_hint() -> void:
	## When revolver hammer is cocked (RMB), hammer cock hint should disappear (Issue #808)
	tutorial._has_revolver = true
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	tutorial.on_hammer_cocked()

	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_HAMMER_COCK),
		"Hammer cock hint dismissed when hammer is cocked (Issue #808)")
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD),
		"Reload hint remains after hammer cocked")
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_GRENADE),
		"Grenade hint remains after hammer cocked")


func test_revolver_hammer_cocked_twice_is_safe() -> void:
	## Cocking hammer twice should not cause errors (idempotent)
	tutorial._has_revolver = true
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	tutorial.on_hammer_cocked()
	tutorial.on_hammer_cocked()  # Second call should be ignored

	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_HAMMER_COCK),
		"Hammer hint still gone after double cock")


func test_revolver_complete_flow_with_hammer_cock() -> void:
	## Full revolver flow: cock hammer first, then reload, then grenade
	tutorial._has_revolver = true
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	# Cock hammer — only hammer hint disappears
	tutorial.on_hammer_cocked()

	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_HAMMER_COCK),
		"Hammer hint dismissed after cock")
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD),
		"Reload hint remains")
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_GRENADE),
		"Grenade hint remains")

	# Complete reload — only reload hint disappears
	tutorial.on_reload_completed()

	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD),
		"Reload hint dismissed after reload")
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_GRENADE),
		"Grenade hint still visible")

	# Throw grenade — complete tutorial
	tutorial.on_grenade_thrown()

	assert_true(tutorial.is_tutorial_complete(),
		"Tutorial completes after all actions")
	assert_false(tutorial.is_any_hint_active(),
		"No hints remain after completion")


# ============================================================================
# Full Tutorial Flow Tests
# ============================================================================


func test_complete_tutorial_flow_with_rifle() -> void:
	tutorial._has_assault_rifle = true
	tutorial.set_initial_step_based_on_weapon(true)

	# Step 1: Switch fire mode
	assert_eq(tutorial.get_current_step(), MockTutorialLevel.TutorialStep.SWITCH_FIRE_MODE)
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_FIRE_MODE))

	# Fire 2 shots then switch fire mode
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()
	tutorial.on_fire_mode_changed()

	# Step 2: Reload (and grenade shown simultaneously — reload hint appears because 2 shots already fired)
	assert_eq(tutorial.get_current_step(), MockTutorialLevel.TutorialStep.RELOAD)
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD),
		"Reload hint active (2 shots already fired before fire mode switch)")
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

	# Should skip fire mode step and start with RELOAD step
	assert_eq(tutorial.get_current_step(), MockTutorialLevel.TutorialStep.RELOAD,
		"Should start with reload step without assault rifle")
	# Issue #945: NO hints yet — waiting for 2 shots
	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD),
		"Reload hint NOT shown yet (Issue #945 — wait for 2 shots)")

	# Fire 2 shots to reveal hints
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD),
		"Reload hint now visible after 2 shots")
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

	# Fire 2 shots to reveal reload hints
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

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


func test_complete_revolver_flow() -> void:
	tutorial._has_revolver = true
	tutorial.set_initial_step_based_on_weapon(false)

	# Fire 2 shots to reveal reload hints
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	# Revolver starts with reload + hammer cock + grenade hints all simultaneously
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD))
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_HAMMER_COCK))
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_GRENADE))

	# Complete reload (dismisses reload + hammer cock hints, grenade remains)
	tutorial.on_reload_completed()

	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD))
	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_HAMMER_COCK))
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_GRENADE))
	assert_eq(tutorial.get_current_step(), MockTutorialLevel.TutorialStep.THROW_GRENADE)

	# Throw grenade to complete
	tutorial.on_grenade_thrown()

	assert_true(tutorial.is_tutorial_complete())
	assert_false(tutorial.is_any_hint_active())


func test_complete_flow_grenade_first_then_reload() -> void:
	## Full flow: grenade thrown before reload — both should complete tutorial
	tutorial.set_initial_step_based_on_weapon(false)
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	# Grenade thrown first during RELOAD step
	tutorial.on_grenade_thrown()

	assert_false(tutorial.is_hint_active(MockTutorialLevel.HINT_GRENADE),
		"Grenade hint dismissed immediately even before reload")
	assert_true(tutorial.is_hint_active(MockTutorialLevel.HINT_RELOAD),
		"Reload hint still active")
	assert_eq(tutorial.get_current_step(), MockTutorialLevel.TutorialStep.RELOAD,
		"Still in RELOAD step")

	# Now complete reload
	tutorial.on_reload_completed()

	assert_true(tutorial.is_tutorial_complete(),
		"Tutorial completes after reload when grenade already thrown")
	assert_false(tutorial.is_any_hint_active(),
		"No hints remain")
