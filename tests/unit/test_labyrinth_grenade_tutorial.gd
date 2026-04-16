extends GutTest


class MockGrenadeTutorial:
	const TUTORIAL_HINT_GRENADE := "grenade"
	const GRENADE_STATE_IDLE := 0
	const GRENADE_STATE_WAITING_FOR_G_RELEASE := 2
	const GRENADE_STATE_AIMING := 3

	var _tutorial_hints: Dictionary = {}
	var _tutorial_grenade_hint_step: int = 0
	var _tutorial_grenade_g_was_held: bool = false
	var _tutorial_grenade_throw_was_held: bool = false
	var _tutorial_hint_strike_progress: Dictionary = {TUTORIAL_HINT_GRENADE: 0.0}

	func _build_tutorial_grenade_hint_bbcode(step: int) -> String:
		match step:
			0:
				_extend_tutorial_hint_strikethrough(TUTORIAL_HINT_GRENADE, 0.0)
				return "[color=#ff4444][G+ПКМ вправо][/color] [color=#888888][G+ПКМ→отпусти G] [ПКМ бросок][/color]"
			1:
				_extend_tutorial_hint_strikethrough(TUTORIAL_HINT_GRENADE, 0.25)
				return "[color=#888888][G+ПКМ вправо][/color] [color=#ff4444][G+ПКМ→отпусти G][/color] [color=#888888][ПКМ бросок][/color]"
			2:
				_extend_tutorial_hint_strikethrough(TUTORIAL_HINT_GRENADE, 0.6)
				return "[color=#888888][G+ПКМ вправо] [G+ПКМ→отпусти G][/color] [color=#ff4444][ПКМ бросок][/color]"
			_:
				_extend_tutorial_hint_strikethrough(TUTORIAL_HINT_GRENADE, 0.85)
				return "[color=#888888][G+ПКМ вправо] [G+ПКМ→отпусти G] [ПКМ бросок][/color]"

	func _extend_tutorial_hint_strikethrough(hint_key: String, target_progress: float) -> void:
		var current_progress: float = _tutorial_hint_strike_progress.get(hint_key, 0.0)
		if is_equal_approx(target_progress, current_progress):
			return
		_tutorial_hint_strike_progress[hint_key] = target_progress

	func _reset_tutorial_grenade_hint_progress() -> void:
		_tutorial_grenade_hint_step = 0
		_tutorial_grenade_g_was_held = false
		_tutorial_grenade_throw_was_held = false

		if not _tutorial_hints.has(TUTORIAL_HINT_GRENADE):
			return

		var label = _tutorial_hints[TUTORIAL_HINT_GRENADE]
		var new_text := _build_tutorial_grenade_hint_bbcode(0)
		if label.text != new_text:
			label.text = new_text

	func update_step(g_pressed: bool, grenade_throw_pressed: bool, grenade_state: int = GRENADE_STATE_IDLE) -> void:
		if not _tutorial_hints.has(TUTORIAL_HINT_GRENADE):
			_reset_tutorial_grenade_hint_progress()
			return

		if grenade_state == GRENADE_STATE_IDLE and _tutorial_grenade_hint_step > 0:
			_reset_tutorial_grenade_hint_progress()
			return

		if grenade_state == GRENADE_STATE_WAITING_FOR_G_RELEASE:
			_tutorial_grenade_hint_step = 1
			_tutorial_grenade_g_was_held = true
			_tutorial_grenade_throw_was_held = true
		elif grenade_state == GRENADE_STATE_AIMING:
			_tutorial_grenade_hint_step = 2
			_tutorial_grenade_g_was_held = false
			_tutorial_grenade_throw_was_held = true
		var label = _tutorial_hints[TUTORIAL_HINT_GRENADE]
		var new_text := _build_tutorial_grenade_hint_bbcode(_tutorial_grenade_hint_step)
		if label.text != new_text:
			label.text = new_text


var tutorial: MockGrenadeTutorial


func before_each() -> void:
	tutorial = MockGrenadeTutorial.new()
	var label := RichTextLabel.new()
	label.text = tutorial._build_tutorial_grenade_hint_bbcode(0)
	tutorial._tutorial_hints[tutorial.TUTORIAL_HINT_GRENADE] = label


func after_each() -> void:
	tutorial = null


func test_grenade_hint_resets_when_prepare_is_aborted() -> void:
	tutorial.update_step(true, true, tutorial.GRENADE_STATE_WAITING_FOR_G_RELEASE)
	assert_eq(tutorial._tutorial_grenade_hint_step, 1,
		"Only the real G+RMB prepare state should advance the hint to the release step")
	assert_eq(tutorial._tutorial_hint_strike_progress[tutorial.TUTORIAL_HINT_GRENADE], 0.25,
		"First hint segment should be struck through while the prepare state is active")

	tutorial.update_step(true, false, tutorial.GRENADE_STATE_IDLE)
	assert_eq(tutorial._tutorial_grenade_hint_step, 0,
		"Releasing RMB before the throw is armed should reset the grenade tutorial back to the first step")
	assert_eq(tutorial._tutorial_hint_strike_progress[tutorial.TUTORIAL_HINT_GRENADE], 0.0,
		"Aborting the combo should clear the partial strikethrough progress")
	assert_string_contains(tutorial._tutorial_hints[tutorial.TUTORIAL_HINT_GRENADE].text, "[color=#ff4444][G+ПКМ вправо][/color]",
		"After reset the first instruction should be highlighted again")


func test_grenade_hint_advances_to_throw_only_after_g_is_released_while_rmb_stays_held() -> void:
	tutorial.update_step(true, true, tutorial.GRENADE_STATE_WAITING_FOR_G_RELEASE)
	tutorial.update_step(false, true, tutorial.GRENADE_STATE_AIMING)

	assert_eq(tutorial._tutorial_grenade_hint_step, 2,
		"Releasing G while RMB remains held should move the tutorial to the throw step")
	assert_eq(tutorial._tutorial_hint_strike_progress[tutorial.TUTORIAL_HINT_GRENADE], 0.6,
		"Throw step should extend the strikethrough through the first two segments")
	assert_string_contains(tutorial._tutorial_hints[tutorial.TUTORIAL_HINT_GRENADE].text, "[color=#ff4444][ПКМ бросок][/color]",
		"Throw step should highlight the final RMB throw action")


func test_grenade_hint_does_not_advance_without_real_prepare_state() -> void:
	tutorial.update_step(true, true, tutorial.GRENADE_STATE_IDLE)

	assert_eq(tutorial._tutorial_grenade_hint_step, 0,
		"Raw input alone must not advance the grenade tutorial before the grenade state machine arms the throw")
	assert_eq(tutorial._tutorial_hint_strike_progress[tutorial.TUTORIAL_HINT_GRENADE], 0.0,
		"Without the real prepare state, the grenade hint should stay at its initial strikethrough progress")


func test_grenade_hint_press_and_release_g_without_activation_stays_initial() -> void:
	tutorial.update_step(true, false, tutorial.GRENADE_STATE_IDLE)
	tutorial.update_step(false, false, tutorial.GRENADE_STATE_IDLE)

	assert_eq(tutorial._tutorial_grenade_hint_step, 0,
		"Pressing and releasing G without activating the grenade must leave the tutorial at the initial step")
	assert_eq(tutorial._tutorial_hint_strike_progress[tutorial.TUTORIAL_HINT_GRENADE], 0.0,
		"Pressing and releasing G without activation must not strike through any grenade hint segment")


class MockShotgunReloadTutorial:
	const TUTORIAL_HINT_BOLT_CYCLE := "bolt_cycle"

	var _tutorial_hints: Dictionary = {}
	var _tutorial_hint_strike_progress: Dictionary = {TUTORIAL_HINT_BOLT_CYCLE: 0.0}
	var _tutorial_has_reloaded: bool = false
	var _tutorial_shotgun_reload_started: bool = false
	var _reload_completed_calls: int = 0
	var _shells_needed: int = 8

	func _extend_tutorial_hint_strikethrough(hint_key: String, target_progress: float) -> void:
		var current_progress: float = _tutorial_hint_strike_progress.get(hint_key, 0.0)
		if is_equal_approx(target_progress, current_progress):
			return
		_tutorial_hint_strike_progress[hint_key] = target_progress

	func _build_tutorial_shotgun_full_reload_hint_bbcode(state: int) -> String:
		match state:
			0, 1:
				return "[color=#ff4444][ПКМ↑ открыть][/color] [color=#888888][СКМ+ПКМ↓ x%d] [ПКМ↓ закрыть][/color]" % _shells_needed
			2:
				_extend_tutorial_hint_strikethrough(TUTORIAL_HINT_BOLT_CYCLE, 0.25)
				return "[color=#888888][ПКМ↑ открыть][/color] [color=#ff4444][СКМ+ПКМ↓ x%d][/color] [color=#888888][ПКМ↓ закрыть][/color]" % _shells_needed
			3:
				_extend_tutorial_hint_strikethrough(TUTORIAL_HINT_BOLT_CYCLE, 0.55)
				return "[color=#888888][ПКМ↑ открыть] [СКМ+ПКМ↓ x%d][/color] [color=#ff4444][ПКМ↓ закрыть][/color]" % _shells_needed
			_:
				_extend_tutorial_hint_strikethrough(TUTORIAL_HINT_BOLT_CYCLE, 0.8)
				return "[color=#888888][ПКМ↑ открыть] [СКМ+ПКМ↓ x%d] [ПКМ↓ закрыть][/color]" % _shells_needed

	func _on_tutorial_reload_completed() -> void:
		_reload_completed_calls += 1
		_tutorial_has_reloaded = true

	func on_reload_state_changed(new_state: int) -> void:
		if not _tutorial_hints.has(TUTORIAL_HINT_BOLT_CYCLE):
			return

		if new_state >= 2:
			_tutorial_shotgun_reload_started = true

		if new_state == 0:
			if _tutorial_shotgun_reload_started:
				_on_tutorial_reload_completed()
			else:
				_tutorial_hints[TUTORIAL_HINT_BOLT_CYCLE].text = _build_tutorial_shotgun_full_reload_hint_bbcode(0)
			return

		_tutorial_hints[TUTORIAL_HINT_BOLT_CYCLE].text = _build_tutorial_shotgun_full_reload_hint_bbcode(new_state)


func test_shotgun_reload_hint_resets_when_bolt_is_closed_without_loading_shells() -> void:
	var shotgun_tutorial := MockShotgunReloadTutorial.new()
	var label := RichTextLabel.new()
	label.text = shotgun_tutorial._build_tutorial_shotgun_full_reload_hint_bbcode(0)
	shotgun_tutorial._tutorial_hints[shotgun_tutorial.TUTORIAL_HINT_BOLT_CYCLE] = label

	shotgun_tutorial.on_reload_state_changed(0)

	assert_false(shotgun_tutorial._tutorial_has_reloaded,
		"Closing the bolt without loading shells must not complete the shotgun reload tutorial")
	assert_eq(shotgun_tutorial._reload_completed_calls, 0,
		"Canceled shotgun reload should not call the reload completion path")
	assert_eq(shotgun_tutorial._tutorial_hint_strike_progress[shotgun_tutorial.TUTORIAL_HINT_BOLT_CYCLE], 0.0,
		"Canceled shotgun reload should keep the strikethrough at the initial state")
	assert_string_contains(label.text, "[color=#ff4444][ПКМ↑ открыть][/color]",
		"After canceling, the shotgun hint should highlight the initial open action again")


func test_shotgun_reload_hint_completes_only_after_loading_phase_started() -> void:
	var shotgun_tutorial := MockShotgunReloadTutorial.new()
	var label := RichTextLabel.new()
	label.text = shotgun_tutorial._build_tutorial_shotgun_full_reload_hint_bbcode(0)
	shotgun_tutorial._tutorial_hints[shotgun_tutorial.TUTORIAL_HINT_BOLT_CYCLE] = label

	shotgun_tutorial.on_reload_state_changed(2)
	shotgun_tutorial.on_reload_state_changed(0)

	assert_true(shotgun_tutorial._tutorial_has_reloaded,
		"Returning to idle after entering the loading phase should complete the shotgun reload tutorial")
	assert_eq(shotgun_tutorial._reload_completed_calls, 1,
		"Completed shotgun reload should call the reload completion path exactly once")
