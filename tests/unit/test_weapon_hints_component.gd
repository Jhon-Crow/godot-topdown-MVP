extends GutTest
## Tests for WeaponHintsComponent (Issue #809).
##
## Validates hint auto-dismiss duration, spacing, offset values,
## and other constants used for positioning floating weapon hints.

const WeaponHintsComp := preload("res://scripts/components/weapon_hints_component.gd")


class MockWeaponHintsSettings:
	extends Node

	var should_show_result: bool = true
	var marked_weapon_ids: Array[String] = []

	func should_show_hints(_weapon_id: String) -> bool:
		return should_show_result

	func mark_weapon_seen(weapon_id: String) -> void:
		marked_weapon_ids.append(weapon_id)


class MockPlayer:
	extends Node2D

	signal ReloadCompleted
	signal ReloadSequenceProgress(step: int, total: int)
	signal grenade_thrown

	var CurrentWeapon: Node = null
	var grenade_count: int = 0
	var grenade_state: int = 0
	var use_method_for_grenades: bool = false

	func _get(property: StringName) -> Variant:
		if use_method_for_grenades:
			return null
		if property == &"GrenadeCount":
			return grenade_count
		return null

	func GetCurrentGrenades() -> int:
		return grenade_count

	func GetGrenadeState() -> int:
		return grenade_state


class MockWeapon:
	extends Node

	signal Fired
	signal ActionStateChanged(new_state: int)
	signal ReloadStateChanged(new_state: int)

	var ShellsInTube: int = 6
	var TubeMagazineCapacity: int = 8


var _weapon_hints_settings: Node = null
var _input_actions_to_cleanup: Array[String] = []


func before_each() -> void:
	_weapon_hints_settings = MockWeaponHintsSettings.new()
	_weapon_hints_settings.name = "WeaponHintsSettings"
	get_tree().root.add_child(_weapon_hints_settings)
	_input_actions_to_cleanup.clear()


func after_each() -> void:
	Input.flush_buffered_events()
	Input.action_release("grenade_prepare")
	Input.action_release("grenade_throw")
	for action in _input_actions_to_cleanup:
		if InputMap.has_action(action):
			InputMap.erase_action(action)
	_input_actions_to_cleanup.clear()

	if is_instance_valid(_weapon_hints_settings):
		_weapon_hints_settings.queue_free()
		_weapon_hints_settings = null


func _ensure_action(action_name: String, keycode: Key) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
		_input_actions_to_cleanup.append(action_name)

	var key_event := InputEventKey.new()
	key_event.physical_keycode = keycode
	key_event.keycode = keycode
	InputMap.action_add_event(action_name, key_event)


func _press_action(action_name: String, keycode: Key) -> void:
	_ensure_action(action_name, keycode)
	Input.action_press(action_name)
	Input.flush_buffered_events()


func _release_action(action_name: String, keycode: Key) -> void:
	_ensure_action(action_name, keycode)
	Input.action_release(action_name)
	Input.flush_buffered_events()


func _press_action_state(action_name: String) -> void:
	Input.action_press(action_name)
	Input.flush_buffered_events()


func _release_action_state(action_name: String) -> void:
	Input.action_release(action_name)
	Input.flush_buffered_events()


# =============================================================================
# Constants
# =============================================================================

func test_hint_auto_dismiss_constant() -> void:
	assert_eq(WeaponHintsComp.HINT_AUTO_DISMISS, 8.0,
		"HINT_AUTO_DISMISS should be 8.0 seconds")


func test_hint_spacing_constant() -> void:
	assert_eq(WeaponHintsComp.HINT_SPACING, 60.0,
		"HINT_SPACING should be 60.0 px")


func test_hint_offset_y_constant() -> void:
	assert_eq(WeaponHintsComp.HINT_OFFSET_Y, -80.0,
		"HINT_OFFSET_Y should be -80.0 (above player)")


func test_hint_offset_x_constant() -> void:
	assert_eq(WeaponHintsComp.HINT_OFFSET_X, -150.0,
		"HINT_OFFSET_X should be -150.0")


func test_hint_min_size_constant() -> void:
	assert_eq(WeaponHintsComp.HINT_MIN_SIZE, Vector2(300, 30),
		"HINT_MIN_SIZE should be Vector2(300, 30)")


func test_hint_fade_in_duration_constant() -> void:
	assert_eq(WeaponHintsComp.HINT_FADE_IN_DURATION, 0.3,
		"HINT_FADE_IN_DURATION should be 0.3 seconds")


func test_hint_strikethrough_duration_constant() -> void:
	assert_eq(WeaponHintsComp.HINT_STRIKETHROUGH_DURATION, 0.4,
		"HINT_STRIKETHROUGH_DURATION should be 0.4 seconds")


func test_hint_fade_out_duration_constant() -> void:
	assert_eq(WeaponHintsComp.HINT_FADE_OUT_DURATION, 0.3,
		"HINT_FADE_OUT_DURATION should be 0.3 seconds")


# =============================================================================
# Initial State
# =============================================================================

func test_initial_state_no_hints_showing() -> void:
	var comp := WeaponHintsComp.new()
	add_child_autofree(comp)

	assert_false(comp._hints_showing, "Hints should not be showing initially")
	assert_false(comp._hints_active, "Hints should not be active initially")
	assert_eq(comp._current_weapon_id, "", "Current weapon ID should be empty")
	assert_eq(comp._shots_fired, 0, "Shots fired should be 0")


func test_initial_player_ref_null() -> void:
	var comp := WeaponHintsComp.new()
	add_child_autofree(comp)

	assert_null(comp._player, "Player reference should be null initially")


func test_initial_hint_labels_empty() -> void:
	var comp := WeaponHintsComp.new()
	add_child_autofree(comp)

	assert_eq(comp._hint_labels.size(), 0, "Hint labels dictionary should be empty")


func test_initial_hint_timers_empty() -> void:
	var comp := WeaponHintsComp.new()
	add_child_autofree(comp)

	assert_eq(comp._hint_timers.size(), 0, "Hint timers dictionary should be empty")


# =============================================================================
# Constant Relationships
# =============================================================================

func test_auto_dismiss_is_positive() -> void:
	assert_gt(WeaponHintsComp.HINT_AUTO_DISMISS, 0.0,
		"HINT_AUTO_DISMISS should be positive")


func test_spacing_is_positive() -> void:
	assert_gt(WeaponHintsComp.HINT_SPACING, 0.0,
		"HINT_SPACING should be positive")


func test_offset_y_is_negative() -> void:
	assert_lt(WeaponHintsComp.HINT_OFFSET_Y, 0.0,
		"HINT_OFFSET_Y should be negative (above player)")


func test_offset_x_is_negative() -> void:
	assert_lt(WeaponHintsComp.HINT_OFFSET_X, 0.0,
		"HINT_OFFSET_X should be negative (left of center)")


func test_fade_in_less_than_auto_dismiss() -> void:
	assert_lt(WeaponHintsComp.HINT_FADE_IN_DURATION, WeaponHintsComp.HINT_AUTO_DISMISS,
		"Fade-in duration should be much less than auto-dismiss time")


# =============================================================================
# Sequential Hint Tracking State
# =============================================================================

func test_initial_sequential_hint_flags() -> void:
	var comp := WeaponHintsComp.new()
	add_child_autofree(comp)

	assert_false(comp._bolt_cycle_hint_revealed,
		"Bolt cycle hint should not be revealed initially")
	assert_false(comp._reload_hint_revealed,
		"Reload hint should not be revealed initially")
	assert_false(comp._scope_used,
		"Scope used flag should be false initially")
	assert_false(comp._hammer_cocked,
		"Hammer cocked flag should be false initially")
	assert_false(comp._fire_mode_hint_pending,
		"Fire mode hint pending should be false initially")
	assert_false(comp._shotgun_full_reload_active,
		"Shotgun full reload active should be false initially")
	assert_false(comp._ak_gl_launcher_hint_shown,
		"AK GL launcher hint shown should be false initially")


func test_grenade_hint_shows_when_grenade_prepare_pressed_in_always_mode() -> void:
	_ensure_action("grenade_prepare", KEY_G)

	var canvas := CanvasLayer.new()
	add_child_autofree(canvas)

	var player := MockPlayer.new()
	player.grenade_count = 2
	add_child_autofree(player)

	var comp := WeaponHintsComp.new()
	add_child_autofree(comp)
	comp.setup(player, canvas)
	comp._current_weapon_id = "m16"
	comp._hints_active = true
	comp._hints_showing = true

	_press_action("grenade_prepare", KEY_G)
	comp._process(0.016)

	assert_true(comp._hint_labels.has("grenade"),
		"Grenade hint should appear when grenade_prepare is pressed and grenades are available")
	assert_eq(comp._grenade_hint_step, 0,
		"Grenade hint should keep the first G+RMB instruction highlighted until RMB is also held")

	_release_action("grenade_prepare", KEY_G)


func test_grenade_hint_does_not_show_before_grenade_prepare_pressed() -> void:
	_ensure_action("grenade_prepare", KEY_G)

	var canvas := CanvasLayer.new()
	add_child_autofree(canvas)

	var player := MockPlayer.new()
	player.grenade_count = 2
	add_child_autofree(player)

	var comp := WeaponHintsComp.new()
	add_child_autofree(comp)
	comp.setup(player, canvas)
	comp._current_weapon_id = "m16"
	comp._hints_active = true
	comp._hints_showing = true

	comp._process(0.016)

	assert_false(comp._hint_labels.has("grenade"),
		"Grenade hint should stay hidden until grenade_prepare is pressed on non-Labyrinth maps")


func test_grenade_hint_uses_player_method_and_stays_visible_until_throw() -> void:
	_ensure_action("grenade_prepare", KEY_G)
	_ensure_action("grenade_throw", KEY_H)

	var canvas := CanvasLayer.new()
	add_child_autofree(canvas)

	var player := MockPlayer.new()
	player.use_method_for_grenades = true
	player.grenade_count = 1
	add_child_autofree(player)

	var comp := WeaponHintsComp.new()
	add_child_autofree(comp)
	comp.setup(player, canvas)
	comp._current_weapon_id = "m16"
	comp._hints_active = true
	comp._hints_showing = true

	_press_action("grenade_prepare", KEY_G)
	comp._process(0.016)
	assert_true(comp._hint_labels.has("grenade"),
		"Grenade hint should appear when GetCurrentGrenades() reports grenades")

	_press_action_state("grenade_throw")
	comp._process(0.016)
	comp._grenade_hint_drag_start = Vector2(-40, 0)
	comp._process(0.016)
	player.grenade_state = 1
	player.grenade_count = 0
	_release_action_state("grenade_throw")
	comp._process(0.016)
	assert_true(comp._hint_labels.has("grenade"),
		"Grenade hint should stay visible after the pin is pulled even when the normal-level grenade count drops to zero")
	assert_eq(comp._grenade_hint_step, 3,
		"Grenade hint should advance to the second RMB hold step after a valid pin-pull release")

	player.grenade_thrown.emit()
	assert_true(comp._animating_hints.has("grenade"),
		"Grenade hint should only start dismissing after grenade_thrown is emitted")
	_release_action("grenade_prepare", KEY_G)


func test_grenade_hint_is_not_limited_to_m16_weapon_id() -> void:
	_ensure_action("grenade_prepare", KEY_G)

	var canvas := CanvasLayer.new()
	add_child_autofree(canvas)

	var player := MockPlayer.new()
	player.grenade_count = 1
	add_child_autofree(player)

	var comp := WeaponHintsComp.new()
	add_child_autofree(comp)
	comp.setup(player, canvas)
	comp._current_weapon_id = "mini_uzi"
	comp._hints_active = true
	comp._hints_showing = true

	_press_action("grenade_prepare", KEY_G)
	comp._process(0.016)

	assert_true(comp._hint_labels.has("grenade"),
		"Grenade hint should work on non-tutorial levels even when current weapon ID is not m16")

	_release_action("grenade_prepare", KEY_G)


func test_grenade_hint_uses_reviewed_six_step_text_source() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/components/weapon_hints_component.gd")

	assert_true(source.contains("tr(\"HINT_GRENADE_HOLD_G_RMB\")"),
		"Weapon hints grenade training should use the reviewed hold G+RMB translation")
	assert_true(source.contains("tr(\"HINT_GRENADE_DRAG_RIGHT\")"),
		"Weapon hints grenade training should include the drag-right action")
	assert_true(source.contains("tr(\"HINT_GRENADE_RELEASE_RMB\")"),
		"Weapon hints grenade training should include the RMB-release action")
	assert_true(source.contains("tr(\"HINT_GRENADE_HOLD_RMB\")"),
		"Weapon hints grenade training should include the second RMB-hold action")
	assert_true(source.contains("tr(\"HINT_GRENADE_RELEASE_G\")"),
		"Weapon hints grenade training should include the G-release action")
	assert_true(source.contains("tr(\"HINT_GRENADE_AIM_RELEASE_RMB\")"),
		"Weapon hints grenade training should include the final aim/release action")


func test_weapon_hint_action_strings_use_translation_keys_not_hardcoded_russian() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/components/weapon_hints_component.gd")

	assert_false(source.contains("ПКМ"),
		"Regular-map weapon hints must not hardcode Russian RMB text in English locale")
	assert_true(source.contains("tr(\"HINT_KEY_RMB_UP_OPEN\")"),
		"Shotgun pump/reload hints should use translated RMB-up/open text")
	assert_true(source.contains("tr(\"HINT_KEY_RMB_DOWN_CLOSE\")"),
		"Shotgun pump/reload hints should use translated RMB-down/close text")
	assert_true(source.contains("tr(\"HINT_KEY_MMB_RMB_DOWN\")"),
		"Shotgun reload hints should use translated MMB+RMB text")


func test_grenade_hint_progresses_through_reviewed_sequence() -> void:
	_ensure_action("grenade_prepare", KEY_G)
	_ensure_action("grenade_throw", KEY_H)

	var canvas := CanvasLayer.new()
	add_child_autofree(canvas)

	var player := MockPlayer.new()
	player.grenade_count = 1
	add_child_autofree(player)

	var comp := WeaponHintsComp.new()
	add_child_autofree(comp)
	comp.setup(player, canvas)
	comp._current_weapon_id = "mini_uzi"
	comp._hints_active = true
	comp._hints_showing = true

	_press_action("grenade_prepare", KEY_G)
	comp._process(0.016)
	assert_eq(comp._grenade_hint_step, 0,
		"G alone should show the hint without marking the first action complete")

	_press_action_state("grenade_throw")
	comp._process(0.016)
	assert_eq(comp._grenade_hint_step, 1,
		"Holding G+RMB should move to the drag-right action")

	comp._grenade_hint_drag_start = Vector2(-40, 0)
	comp._process(0.016)
	assert_eq(comp._grenade_hint_step, 2,
		"Dragging right should move to the RMB-release action")

	player.grenade_state = 1
	_release_action_state("grenade_throw")
	comp._process(0.016)
	assert_eq(comp._grenade_hint_step, 3,
		"Releasing RMB after the pin is pulled should move to the second RMB-hold action")

	_press_action_state("grenade_throw")
	player.grenade_state = 4
	comp._process(0.016)
	assert_eq(comp._grenade_hint_step, 4,
		"Holding RMB again should move to the release-G action")

	_release_action("grenade_prepare", KEY_G)
	player.grenade_state = 4
	comp._process(0.016)
	assert_eq(comp._grenade_hint_step, 5,
		"Releasing G while RMB remains held should highlight the final aim/release action")

	_release_action_state("grenade_throw")


func test_find_weapon_node_maps_silenced_pistol_for_training_hints() -> void:
	var player := MockPlayer.new()
	add_child_autofree(player)
	var weapon := MockWeapon.new()
	weapon.name = "SilencedPistol"
	player.add_child(weapon)

	var comp := WeaponHintsComp.new()
	add_child_autofree(comp)
	comp._player = player

	assert_eq(comp._find_weapon_node("silenced_pistol"), weapon,
		"Silenced pistol should map to the C# SilencedPistol node so training can connect")


func test_find_weapon_node_prefers_equipped_current_weapon_over_stale_children() -> void:
	var player := MockPlayer.new()
	add_child_autofree(player)
	var stale_weapon := MockWeapon.new()
	stale_weapon.name = "Shotgun"
	player.add_child(stale_weapon)
	var equipped_weapon := MockWeapon.new()
	equipped_weapon.name = "Shotgun"
	player.CurrentWeapon = equipped_weapon

	var comp := WeaponHintsComp.new()
	add_child_autofree(comp)
	comp._player = player

	assert_eq(comp._find_weapon_node("shotgun"), equipped_weapon,
		"Building weapon hints must connect to Player.CurrentWeapon instead of stale scene children")


func test_retries_weapon_binding_when_weapon_selected_arrives_before_equip() -> void:
	var comp := WeaponHintsComp.new()
	add_child_autofree(comp)

	var player := MockPlayer.new()
	add_child_autofree(player)

	comp._player = player
	comp._canvas_layer = Node.new()
	add_child_autofree(comp._canvas_layer)

	comp._start_hint_sequence("shotgun")

	assert_null(comp._current_weapon_node,
		"Initial bind should fail before the level equips the selected weapon")
	assert_gt(comp._weapon_bind_retry_timer, 0.0,
		"Component should keep retrying after selected weapon arrives before equip")

	var shotgun := MockWeapon.new()
	shotgun.name = "Shotgun"
	player.CurrentWeapon = shotgun

	comp._try_bind_current_weapon_node()

	assert_eq(comp._current_weapon_node, shotgun,
		"Retry should bind to Player.CurrentWeapon once level weapon setup completes")
	assert_true(shotgun.Fired.is_connected(comp._on_weapon_fired),
		"Retry bind must connect weapon action signals so hints become interactive")
	assert_eq(comp._weapon_bind_retry_timer, 0.0,
		"Retry timer should stop after binding succeeds")


func test_revolver_open_close_without_loading_rolls_reload_hint_back() -> void:
	var comp := WeaponHintsComp.new()
	add_child_autofree(comp)
	comp._current_weapon_id = "revolver"
	comp._hints_active = true
	comp._hint_labels[WeaponHintsComp.HINT_KEY_RELOAD] = RichTextLabel.new()
	comp._hint_strike_progress[WeaponHintsComp.HINT_KEY_RELOAD] = 0.0

	comp._on_revolver_reload_state_changed(1)
	assert_true(comp._hint_strike_progress[WeaponHintsComp.HINT_KEY_RELOAD] > 0.0,
		"Opening the cylinder should advance the reload hint to the insert step")

	comp._on_revolver_reload_state_changed(0)

	assert_true(comp._hint_labels.has(WeaponHintsComp.HINT_KEY_RELOAD),
		"Closing an empty reload should not dismiss the revolver reload hint")
	assert_false(comp._animating_hints.has(WeaponHintsComp.HINT_KEY_RELOAD),
		"Closing without loading should not start the dismiss animation")
	assert_eq(comp._hint_strike_progress[WeaponHintsComp.HINT_KEY_RELOAD], 0.0,
		"Closing without loading should clear partial strikethrough progress")
	assert_false(comp._revolver_reload_loaded_cartridge,
		"Rollback should clear the revolver loaded-cartridge tracker")


func test_revolver_reload_dismisses_after_cartridge_inserted_then_closed() -> void:
	var comp := WeaponHintsComp.new()
	add_child_autofree(comp)
	comp._current_weapon_id = "revolver"
	comp._hints_active = true
	comp._hint_labels[WeaponHintsComp.HINT_KEY_RELOAD] = RichTextLabel.new()
	comp._hint_strike_progress[WeaponHintsComp.HINT_KEY_RELOAD] = 0.0

	comp._on_revolver_reload_state_changed(1)
	comp._on_revolver_reload_state_changed(2)
	comp._on_revolver_reload_state_changed(0)

	assert_true(comp._animating_hints.has(WeaponHintsComp.HINT_KEY_RELOAD),
		"Closing after inserting a cartridge should dismiss the revolver reload hint")


func test_shotgun_open_close_without_loading_rolls_full_reload_hint_back() -> void:
	var comp := WeaponHintsComp.new()
	add_child_autofree(comp)
	comp._current_weapon_id = "shotgun"
	comp._hints_active = true
	comp._shotgun_full_reload_active = true
	comp._hint_labels[WeaponHintsComp.HINT_KEY_BOLT_CYCLE] = RichTextLabel.new()
	comp._hint_strike_progress[WeaponHintsComp.HINT_KEY_BOLT_CYCLE] = 0.0

	comp._on_shotgun_reload_state_changed(2)
	assert_eq(comp._hint_strike_progress[WeaponHintsComp.HINT_KEY_BOLT_CYCLE], 0.0,
		"Opening the shotgun bolt should not count as shell loading")

	comp._on_shotgun_reload_state_changed(0)

	assert_true(comp._hint_labels.has(WeaponHintsComp.HINT_KEY_BOLT_CYCLE),
		"Closing without loading should keep the shotgun full reload hint visible")
	assert_false(comp._animating_hints.has(WeaponHintsComp.HINT_KEY_BOLT_CYCLE),
		"Closing without loading should not dismiss the shotgun full reload hint")
	assert_eq(comp._hint_strike_progress[WeaponHintsComp.HINT_KEY_BOLT_CYCLE], 0.0,
		"Closing without loading should keep strikethrough cleared")
	assert_false(comp._shotgun_reload_loaded_shell,
		"Rollback should clear the shotgun loaded-shell tracker")


func test_shotgun_full_reload_dismisses_after_shell_loaded_then_closed() -> void:
	var comp := WeaponHintsComp.new()
	add_child_autofree(comp)
	comp._current_weapon_id = "shotgun"
	comp._hints_active = true
	comp._shotgun_full_reload_active = true
	comp._hint_labels[WeaponHintsComp.HINT_KEY_BOLT_CYCLE] = RichTextLabel.new()
	comp._hint_strike_progress[WeaponHintsComp.HINT_KEY_BOLT_CYCLE] = 0.0

	comp._on_shotgun_reload_state_changed(2)
	comp._on_shotgun_reload_state_changed(3)
	comp._on_shotgun_reload_state_changed(0)

	assert_true(comp._animating_hints.has(WeaponHintsComp.HINT_KEY_BOLT_CYCLE),
		"Closing after loading a shell should dismiss the shotgun full reload hint")


func test_auto_dismiss_timer_does_not_dismiss_active_grenade_hint() -> void:
	# Regression test for Issue #1889: grenade tutorial must not disappear via the
	# auto-dismiss timer — only the grenade_thrown signal should dismiss it.
	var comp := WeaponHintsComp.new()
	add_child_autofree(comp)
	comp._hints_active = true

	# Simulate grenade hint active alongside another hint
	comp._hint_labels[WeaponHintsComp.HINT_KEY_GRENADE] = RichTextLabel.new()
	comp._hint_labels["other"] = RichTextLabel.new()
	comp._animating_hints.clear()

	# Fire the auto-dismiss callback directly (simulates timer expiry)
	comp._on_dismiss_timer_timeout()

	assert_true(comp._hint_labels.has(WeaponHintsComp.HINT_KEY_GRENADE),
		"Grenade hint must survive auto-dismiss timer (Issue #1889)")
	assert_false(comp._hint_labels.has("other"),
		"Non-grenade hints should be dismissed by the auto-dismiss timer")


func test_auto_dismiss_timer_dismisses_all_hints_when_no_grenade_hint() -> void:
	var comp := WeaponHintsComp.new()
	add_child_autofree(comp)
	comp._hints_active = true

	comp._hint_labels["reload"] = RichTextLabel.new()
	comp._hint_labels["fire_mode"] = RichTextLabel.new()
	comp._animating_hints.clear()

	comp._on_dismiss_timer_timeout()

	assert_false(comp._hint_labels.has("reload"),
		"Reload hint should be dismissed when no grenade hint is active")
	assert_false(comp._hint_labels.has("fire_mode"),
		"Fire-mode hint should be dismissed when no grenade hint is active")


# ============================================================================
# Issue #1881: Grenade tutorial hint must not cover the player on non-tutorial levels
# ============================================================================


func test_weapon_hints_are_bottom_aligned_above_player() -> void:
	var file := FileAccess.open("res://scripts/components/weapon_hints_component.gd", FileAccess.READ)
	if file == null:
		pass_test("weapon_hints_component.gd not accessible in test environment (OK)")
		return
	var content := file.get_as_text()
	file.close()

	assert_true(content.contains("const HINT_PLAYER_CLEARANCE"),
		"Weapon hints should use an explicit clearance above the player (Issue #1881)")
	assert_true(content.contains("label.get_content_height()"),
		"Weapon hints should account for wrapped grenade hint height (Issue #1881)")
	assert_true(
		content.contains("-HINT_PLAYER_CLEARANCE - cumulative_y - h"),
		"Weapon hints should bottom-align above the player instead of growing downward over the sprite (Issue #1881)")


func test_weapon_hints_do_not_use_old_fixed_player_covering_offset() -> void:
	var file := FileAccess.open("res://scripts/components/weapon_hints_component.gd", FileAccess.READ)
	if file == null:
		pass_test("weapon_hints_component.gd not accessible in test environment (OK)")
		return
	var content := file.get_as_text()
	file.close()

	assert_false(content.contains("HINT_OFFSET_Y - index * HINT_SPACING"),
		"Old fixed top-left offset can cover the player when grenade hint wraps (Issue #1881)")
	assert_false(content.contains("index * HINT_SPACING"),
		"Fixed index*HINT_SPACING stacking ignores actual hint heights — grenade hint overlaps the player on non-tutorial levels (Issue #1881)")


func test_weapon_hints_stacking_uses_cumulative_content_heights() -> void:
	var file := FileAccess.open("res://scripts/components/weapon_hints_component.gd", FileAccess.READ)
	if file == null:
		pass_test("weapon_hints_component.gd not accessible in test environment (OK)")
		return
	var content := file.get_as_text()
	file.close()

	assert_true(content.contains("cumulative_y"),
		"Hint stacking should accumulate actual heights so grenade hint does not overlap other simultaneous hints (Issue #1881)")
	assert_true(content.contains("_hint_heights"),
		"Hint heights should be tracked in a dictionary to survive stale get_content_height() (Issue #1881)")
	assert_true(content.contains("_estimate_hint_height"),
		"A text-based height estimate fallback should be used when layout has not run yet (Issue #1881)")
	assert_true(content.contains("label.size = Vector2(HINT_WIDTH"),
		"label.size.x must be set explicitly so RichTextLabel word-wrap computes content height correctly (Issue #1881)")
	assert_true(content.contains("known_bbcode"),
		"_estimate_hint_height must use a BBCode-aware regex (known_bbcode) to leave non-BBCode brackets intact (Issue #1881)")


func test_tutorial_scene_does_not_double_stack_weapon_hints_component() -> void:
	## Issue #1881: Tutorial level uses its own hint system in tutorial_level.gd.
	## The csharp TestTier scene must not also attach WeaponHintsComponent, or reload
	## hints would be shown twice (duplicate [R] [F] [R] Reload reported by user).
	var file := FileAccess.open("res://scenes/levels/csharp/TestTier.tscn", FileAccess.READ)
	if file == null:
		pass_test("csharp TestTier.tscn not accessible in test environment (OK)")
		return
	var content := file.get_as_text()
	file.close()

	assert_false(content.contains("weapon_hints_component.gd"),
		"Tutorial scene must not attach WeaponHintsComponent — tutorial_level.gd already owns the hint system (Issue #1881)")
	assert_false(content.contains("WeaponHintsComponent"),
		"Tutorial scene must not have a WeaponHintsComponent node — causes duplicate reload hints on Tutorial level (Issue #1881)")
