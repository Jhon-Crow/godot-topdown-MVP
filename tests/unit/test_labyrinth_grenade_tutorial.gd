extends GutTest


class MockGrenadeTutorial:
	const TUTORIAL_HINT_GRENADE := "grenade"

	var _tutorial_hints: Dictionary = {}
	var _tutorial_grenade_hint_step: int = 0
	var _tutorial_grenade_g_was_held: bool = false
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

	func update_step(g_pressed: bool) -> void:
		if not _tutorial_hints.has(TUTORIAL_HINT_GRENADE):
			_tutorial_grenade_g_was_held = false
			_tutorial_grenade_hint_step = 0
			return

		if _tutorial_grenade_hint_step == 0 and g_pressed:
			_tutorial_grenade_hint_step = 1
			_tutorial_grenade_g_was_held = true
		elif _tutorial_grenade_hint_step == 1 and not g_pressed and _tutorial_grenade_g_was_held:
			_tutorial_grenade_hint_step = 0
			_tutorial_grenade_g_was_held = false

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
	tutorial.update_step(true)
	assert_eq(tutorial._tutorial_grenade_hint_step, 1,
		"Holding grenade prepare should advance the hint to the release step")
	assert_eq(tutorial._tutorial_hint_strike_progress[tutorial.TUTORIAL_HINT_GRENADE], 0.25,
		"First hint segment should be struck through while the combo is held")

	tutorial.update_step(false)
	assert_eq(tutorial._tutorial_grenade_hint_step, 0,
		"Aborting the combo should reset the grenade tutorial back to the first step")
	assert_eq(tutorial._tutorial_hint_strike_progress[tutorial.TUTORIAL_HINT_GRENADE], 0.0,
		"Aborting the combo should clear the partial strikethrough progress")
	assert_string_contains(tutorial._tutorial_hints[tutorial.TUTORIAL_HINT_GRENADE].text, "[color=#ff4444][G+ПКМ вправо][/color]",
		"After reset the first instruction should be highlighted again")
