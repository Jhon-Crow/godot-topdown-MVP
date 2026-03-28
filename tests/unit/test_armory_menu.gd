extends GutTest
## Unit tests for ArmoryMenu.
##
## Tests the weapon/grenade selection menu logic with Apply-based workflow.
## The armory menu separates firearms and grenades into distinct categories,
## shows a left sidebar with stats, and requires clicking "Apply" to confirm.


# ============================================================================
# Mock ArmoryMenu for Testing
# ============================================================================


class MockArmoryMenu:
	## Dictionary of firearms (non-grenade weapons).
	const FIREARMS: Dictionary = {
		"makarov_pm": {
			"name": "PM",
			"icon_path": "res://assets/sprites/weapons/makarov_pm_icon.png",
			"unlocked": true,
			"description": "Makarov PM starting pistol"
		},
		"m16": {
			"name": "M16",
			"icon_path": "res://assets/sprites/weapons/m16_rifle.png",
			"unlocked": true,
			"description": "Standard assault rifle with auto/burst modes, red laser sight"
		},
		"shotgun": {
			"name": "Shotgun",
			"icon_path": "res://assets/sprites/weapons/shotgun_icon.png",
			"unlocked": true,
			"description": "Pump-action shotgun"
		},
		"mini_uzi": {
			"name": "Mini UZI",
			"icon_path": "res://assets/sprites/weapons/mini_uzi_icon.png",
			"unlocked": true,
			"description": "High fire rate SMG"
		},
		"silenced_pistol": {
			"name": "Silenced Pistol",
			"icon_path": "res://assets/sprites/weapons/silenced_pistol_topdown.png",
			"unlocked": true,
			"description": "Beretta M9 with suppressor"
		},
		"sniper": {
			"name": "ASVK",
			"icon_path": "res://assets/sprites/weapons/asvk_topdown.png",
			"unlocked": true,
			"description": "Anti-materiel sniper"
		},
		"ak47": {
			"name": "???",
			"icon_path": "",
			"unlocked": false,
			"description": "Coming soon"
		}
	}

	## Grenade data (separate from firearms).
	const GRENADES: Dictionary = {
		0: {"name": "Flashbang", "description": "Stun grenade"},
		1: {"name": "Frag Grenade", "description": "Offensive grenade"},
		2: {"name": "F-1 Grenade", "description": "Defensive grenade"}
	}

	## Active item data (separate from firearms and grenades).
	const ACTIVE_ITEMS: Dictionary = {
		0: {"name": "None", "description": "No active item equipped."},
		1: {"name": "Flashlight", "description": "Tactical flashlight"},
		2: {"name": "Homing Bullets", "description": "Homing bullets active item"},
		3: {"name": "Teleport Bracers", "description": "Teleportation bracers"}
	}

	## Applied (active) weapon ID.
	var applied_weapon: String = "makarov_pm"

	## Applied (active) grenade type.
	var applied_grenade_type: int = 0

	## Applied active item type.
	var applied_active_item: int = 0

	## Pending weapon selection (not yet applied).
	var pending_weapon: String = "makarov_pm"

	## Pending grenade type (not yet applied).
	var pending_grenade_type: int = 0

	## Pending active item type (not yet applied).
	var pending_active_item: int = 0

	## Signal tracking.
	var back_pressed_emitted: int = 0
	var weapon_selected_emitted: Array = []
	var grenade_selected_emitted: Array = []
	var active_item_selected_emitted: Array = []
	var apply_count: int = 0

	## Count unlocked firearms.
	func count_unlocked_firearms() -> int:
		var count := 0
		for weapon_id in FIREARMS:
			if FIREARMS[weapon_id]["unlocked"]:
				count += 1
		return count

	## Get total firearm count.
	func count_total_firearms() -> int:
		return FIREARMS.size()

	## Get total grenade count.
	func count_total_grenades() -> int:
		return GRENADES.size()

	## Get total active item count.
	func count_total_active_items() -> int:
		return ACTIVE_ITEMS.size()

	## Check if weapon is unlocked.
	func is_weapon_unlocked(weapon_id: String) -> bool:
		if not weapon_id in FIREARMS:
			return false
		return FIREARMS[weapon_id]["unlocked"]

	## Select a weapon (sets pending, does NOT apply immediately).
	func select_weapon(weapon_id: String) -> bool:
		if not is_weapon_unlocked(weapon_id):
			return false

		pending_weapon = weapon_id
		return true

	## Select a grenade by type (sets pending, does NOT apply immediately).
	func select_grenade(grenade_type: int) -> bool:
		if grenade_type not in GRENADES:
			return false

		pending_grenade_type = grenade_type
		return true

	## Select an active item by type (sets pending, does NOT apply immediately).
	func select_active_item(item_type: int) -> bool:
		if item_type not in ACTIVE_ITEMS:
			return false

		pending_active_item = item_type
		return true

	## Check if there are unapplied changes.
	func has_pending_changes() -> bool:
		return pending_weapon != applied_weapon or pending_grenade_type != applied_grenade_type or pending_active_item != applied_active_item

	## Apply pending selections.
	func apply() -> bool:
		if not has_pending_changes():
			return false

		if pending_weapon != applied_weapon:
			weapon_selected_emitted.append(pending_weapon)
		if pending_grenade_type != applied_grenade_type:
			grenade_selected_emitted.append(pending_grenade_type)
		if pending_active_item != applied_active_item:
			active_item_selected_emitted.append(pending_active_item)

		applied_weapon = pending_weapon
		applied_grenade_type = pending_grenade_type
		applied_active_item = pending_active_item
		apply_count += 1
		return true

	## Handle back button press.
	func press_back() -> void:
		back_pressed_emitted += 1

	## Select weapon and record which reload preview sound was requested.
	## Mimics the armory menu logic: weapons call play_weapon_reload_preview(weapon_id).
	func select_weapon_with_sound(weapon_id: String) -> bool:
		if not select_weapon(weapon_id):
			return false
		reload_preview_calls.append(weapon_id)
		return true

	## Tracks weapon IDs passed to play_weapon_reload_preview.
	var reload_preview_calls: Array = []

	# ---- Accordion shine overlay simulation (Issue #1561) ----

	## Tracks which mock button names have a shine overlay applied.
	var accordion_shine_active: Dictionary = {}

	## Simulate applying gold condition-met style (font color + shine overlay) to an accordion button.
	func apply_accordion_button_condition_met_style(button_name: String) -> void:
		accordion_shine_active[button_name] = true

	## Simulate resetting accordion button to default style (removes shine overlay).
	func apply_accordion_button_default_style(button_name: String) -> void:
		accordion_shine_active.erase(button_name)

	## Returns true if the given button has an active shine overlay.
	func has_accordion_shine(button_name: String) -> bool:
		return accordion_shine_active.get(button_name, false)


## Mock AudioManager that records play_weapon_reload_preview calls.
class MockAudioManager:
	## Weapon IDs for which play_weapon_reload_preview was called.
	var reload_preview_calls: Array = []
	## Whether play_ui_click was called.
	var ui_click_count: int = 0

	func has_method(method_name: String) -> bool:
		return method_name in ["play_weapon_reload_preview", "play_ui_click"]

	func play_weapon_reload_preview(weapon_id: String) -> void:
		reload_preview_calls.append(weapon_id)

	func play_ui_click() -> void:
		ui_click_count += 1


var menu: MockArmoryMenu


func before_each() -> void:
	menu = MockArmoryMenu.new()


func after_each() -> void:
	menu = null


# ============================================================================
# Weapon Data Tests
# ============================================================================


func test_firearms_dictionary_exists() -> void:
	assert_true(menu.FIREARMS.size() > 0,
		"FIREARMS dictionary should have entries")


func test_grenades_dictionary_exists() -> void:
	assert_true(menu.GRENADES.size() > 0,
		"GRENADES dictionary should have entries")


func test_makarov_pm_is_unlocked() -> void:
	assert_true(menu.is_weapon_unlocked("makarov_pm"),
		"Makarov PM should be unlocked")


func test_m16_is_unlocked() -> void:
	assert_true(menu.is_weapon_unlocked("m16"),
		"M16 should be unlocked")


func test_ak47_is_locked() -> void:
	assert_false(menu.is_weapon_unlocked("ak47"),
		"AK47 should be locked")


func test_unknown_weapon_not_unlocked() -> void:
	assert_false(menu.is_weapon_unlocked("unknown_weapon"),
		"Unknown weapon should not be unlocked")


func test_sniper_is_unlocked() -> void:
	assert_true(menu.is_weapon_unlocked("sniper"),
		"ASVK sniper should be unlocked")


func test_silenced_pistol_is_unlocked() -> void:
	assert_true(menu.is_weapon_unlocked("silenced_pistol"),
		"Silenced Pistol should be unlocked")


func test_mini_uzi_is_unlocked() -> void:
	assert_true(menu.is_weapon_unlocked("mini_uzi"),
		"Mini UZI should be unlocked")


# ============================================================================
# Weapon Count Tests
# ============================================================================


func test_count_unlocked_firearms() -> void:
	var count := menu.count_unlocked_firearms()

	# PM, M16, Shotgun, Mini UZI, Silenced Pistol, ASVK (6 unlocked)
	assert_eq(count, 6,
		"Should count correct number of unlocked firearms")


func test_count_total_firearms() -> void:
	var count := menu.count_total_firearms()

	assert_eq(count, 8,
		"Should count total firearms correctly (6 unlocked + 2 locked)")


func test_count_total_grenades() -> void:
	var count := menu.count_total_grenades()

	assert_eq(count, 3,
		"Should count total grenades correctly (flashbang, frag, defensive)")


# ============================================================================
# Pending Selection Tests (no immediate apply)
# ============================================================================


func test_select_weapon_sets_pending() -> void:
	var result := menu.select_weapon("shotgun")

	assert_true(result,
		"Should successfully set pending weapon")
	assert_eq(menu.pending_weapon, "shotgun",
		"Pending weapon should be updated")
	assert_eq(menu.applied_weapon, "makarov_pm",
		"Applied weapon should NOT change until Apply")


func test_select_weapon_does_not_emit_signal() -> void:
	menu.select_weapon("shotgun")

	assert_eq(menu.weapon_selected_emitted.size(), 0,
		"Should NOT emit weapon_selected until Apply")


func test_select_same_weapon_still_succeeds_as_pending() -> void:
	menu.pending_weapon = "makarov_pm"
	var result := menu.select_weapon("makarov_pm")

	assert_true(result,
		"Should allow selecting same weapon (sets pending)")


func test_select_locked_weapon() -> void:
	var result := menu.select_weapon("ak47")

	assert_false(result,
		"Should not select locked weapon")
	assert_eq(menu.pending_weapon, "makarov_pm",
		"Pending weapon should remain unchanged")


func test_select_grenade_sets_pending() -> void:
	var result := menu.select_grenade(1)  # Frag

	assert_true(result,
		"Should successfully set pending grenade")
	assert_eq(menu.pending_grenade_type, 1,
		"Pending grenade type should be updated")
	assert_eq(menu.applied_grenade_type, 0,
		"Applied grenade type should NOT change until Apply")


func test_select_grenade_does_not_emit_signal() -> void:
	menu.select_grenade(1)

	assert_eq(menu.grenade_selected_emitted.size(), 0,
		"Should NOT emit grenade signal until Apply")


func test_select_invalid_grenade_type() -> void:
	var result := menu.select_grenade(99)

	assert_false(result,
		"Should not select invalid grenade type")
	assert_eq(menu.pending_grenade_type, 0,
		"Grenade type should remain unchanged")


# ============================================================================
# has_pending_changes Tests
# ============================================================================


func test_no_pending_changes_initially() -> void:
	assert_false(menu.has_pending_changes(),
		"Should have no pending changes initially")


func test_has_pending_changes_after_weapon_select() -> void:
	menu.select_weapon("shotgun")

	assert_true(menu.has_pending_changes(),
		"Should have pending changes after selecting a different weapon")


func test_has_pending_changes_after_grenade_select() -> void:
	menu.select_grenade(2)

	assert_true(menu.has_pending_changes(),
		"Should have pending changes after selecting a different grenade")


func test_no_pending_changes_when_same_selection() -> void:
	menu.select_weapon("makarov_pm")
	menu.select_grenade(0)

	assert_false(menu.has_pending_changes(),
		"Should have no pending changes when same as applied")


# ============================================================================
# Apply Tests
# ============================================================================


func test_apply_weapon_change() -> void:
	menu.select_weapon("shotgun")
	var result := menu.apply()

	assert_true(result,
		"Apply should succeed with pending changes")
	assert_eq(menu.applied_weapon, "shotgun",
		"Applied weapon should be updated after Apply")
	assert_eq(menu.weapon_selected_emitted.size(), 1,
		"Should emit weapon_selected on Apply")
	assert_eq(menu.weapon_selected_emitted[0], "shotgun",
		"Signal should contain new weapon ID")


func test_apply_grenade_change() -> void:
	menu.select_grenade(1)
	var result := menu.apply()

	assert_true(result,
		"Apply should succeed with pending grenade change")
	assert_eq(menu.applied_grenade_type, 1,
		"Applied grenade type should be updated after Apply")
	assert_eq(menu.grenade_selected_emitted.size(), 1,
		"Should emit grenade signal on Apply")


func test_apply_both_changes() -> void:
	menu.select_weapon("sniper")
	menu.select_grenade(2)
	var result := menu.apply()

	assert_true(result,
		"Apply should succeed")
	assert_eq(menu.applied_weapon, "sniper",
		"Weapon should be applied")
	assert_eq(menu.applied_grenade_type, 2,
		"Grenade should be applied")
	assert_eq(menu.weapon_selected_emitted.size(), 1,
		"Should emit one weapon signal")
	assert_eq(menu.grenade_selected_emitted.size(), 1,
		"Should emit one grenade signal")


func test_apply_without_changes_returns_false() -> void:
	var result := menu.apply()

	assert_false(result,
		"Apply should return false with no pending changes")
	assert_eq(menu.apply_count, 0,
		"Apply count should remain zero")


func test_apply_clears_pending_state() -> void:
	menu.select_weapon("mini_uzi")
	menu.apply()

	assert_false(menu.has_pending_changes(),
		"Should have no pending changes after Apply")


func test_double_apply_does_nothing() -> void:
	menu.select_weapon("shotgun")
	menu.apply()
	var second_result := menu.apply()

	assert_false(second_result,
		"Second apply should return false (no changes)")
	assert_eq(menu.apply_count, 1,
		"Apply count should be 1")


# ============================================================================
# Back Button Tests
# ============================================================================


func test_back_button_emits_signal() -> void:
	menu.press_back()

	assert_eq(menu.back_pressed_emitted, 1,
		"Should emit back_pressed signal")


func test_multiple_back_presses() -> void:
	menu.press_back()
	menu.press_back()
	menu.press_back()

	assert_eq(menu.back_pressed_emitted, 3,
		"Should emit signal for each press")


# ============================================================================
# Sequential Selection Tests
# ============================================================================


func test_switch_weapons_pending() -> void:
	menu.select_weapon("shotgun")
	menu.select_weapon("mini_uzi")

	assert_eq(menu.pending_weapon, "mini_uzi",
		"Latest pending weapon should be mini_uzi")
	assert_eq(menu.applied_weapon, "makarov_pm",
		"Applied weapon should still be makarov_pm")


func test_switch_grenades_pending() -> void:
	menu.select_grenade(1)
	menu.select_grenade(2)

	assert_eq(menu.pending_grenade_type, 2,
		"Latest pending grenade should be defensive")
	assert_eq(menu.applied_grenade_type, 0,
		"Applied grenade should still be flashbang")


func test_select_weapon_and_grenade_then_apply() -> void:
	menu.select_weapon("shotgun")
	menu.select_grenade(1)
	menu.apply()

	assert_eq(menu.applied_weapon, "shotgun",
		"Weapon should be applied")
	assert_eq(menu.applied_grenade_type, 1,
		"Grenade should be applied")


# ============================================================================
# Edge Case Tests
# ============================================================================


func test_empty_weapon_id() -> void:
	var result := menu.select_weapon("")

	assert_false(result,
		"Empty weapon ID should fail")


func test_null_like_weapon_id() -> void:
	var result := menu.is_weapon_unlocked("null")

	assert_false(result,
		"String 'null' should not match any weapon")


func test_case_sensitivity() -> void:
	var lower := menu.is_weapon_unlocked("makarov_pm")
	var upper := menu.is_weapon_unlocked("Makarov_PM")

	assert_true(lower,
		"Lowercase should work")
	assert_false(upper,
		"Uppercase should not work (case sensitive)")


func test_all_unlocked_weapons_selectable() -> void:
	var unlocked_weapons := ["makarov_pm", "m16", "shotgun", "mini_uzi", "silenced_pistol", "sniper"]

	for weapon_id in unlocked_weapons:
		var result := menu.select_weapon(weapon_id)
		assert_true(result,
			"Should be able to select %s" % weapon_id)


func test_all_grenades_selectable() -> void:
	for grenade_type in [0, 1, 2]:
		var result := menu.select_grenade(grenade_type)
		assert_true(result,
			"Should be able to select grenade type %d" % grenade_type)


func test_cycle_all_weapons_and_apply() -> void:
	var weapons := ["m16", "shotgun", "mini_uzi", "silenced_pistol", "sniper", "makarov_pm"]
	for weapon_id in weapons:
		menu.select_weapon(weapon_id)
		menu.apply()
	assert_eq(menu.applied_weapon, "makarov_pm",
		"Should end on PM after cycling all weapons and applying")
	assert_eq(menu.weapon_selected_emitted.size(), 6,
		"Should emit signal for each Apply")


# ============================================================================
# Active Item Tests
# ============================================================================


func test_active_items_dictionary_exists() -> void:
	assert_true(menu.ACTIVE_ITEMS.size() > 0,
		"ACTIVE_ITEMS dictionary should have entries")


func test_count_total_active_items() -> void:
	var count := menu.count_total_active_items()
	assert_eq(count, 3,
		"Should count total active items correctly (none, flashlight, homing bullets)")


func test_select_active_item_sets_pending() -> void:
	var result := menu.select_active_item(1)  # Flashlight
	assert_true(result,
		"Should successfully set pending active item")
	assert_eq(menu.pending_active_item, 1,
		"Pending active item should be updated")
	assert_eq(menu.applied_active_item, 0,
		"Applied active item should NOT change until Apply")


func test_select_active_item_does_not_emit_signal() -> void:
	menu.select_active_item(1)
	assert_eq(menu.active_item_selected_emitted.size(), 0,
		"Should NOT emit active_item signal until Apply")


func test_select_invalid_active_item_type() -> void:
	var result := menu.select_active_item(99)
	assert_false(result,
		"Should not select invalid active item type")
	assert_eq(menu.pending_active_item, 0,
		"Active item type should remain unchanged")


func test_has_pending_changes_after_active_item_select() -> void:
	menu.select_active_item(1)
	assert_true(menu.has_pending_changes(),
		"Should have pending changes after selecting a different active item")


func test_apply_active_item_change() -> void:
	menu.select_active_item(1)
	var result := menu.apply()
	assert_true(result,
		"Apply should succeed with pending active item change")
	assert_eq(menu.applied_active_item, 1,
		"Applied active item should be updated after Apply")
	assert_eq(menu.active_item_selected_emitted.size(), 1,
		"Should emit active item signal on Apply")


func test_apply_weapon_grenade_and_active_item() -> void:
	menu.select_weapon("sniper")
	menu.select_grenade(2)
	menu.select_active_item(1)
	var result := menu.apply()
	assert_true(result, "Apply should succeed")
	assert_eq(menu.applied_weapon, "sniper", "Weapon should be applied")
	assert_eq(menu.applied_grenade_type, 2, "Grenade should be applied")
	assert_eq(menu.applied_active_item, 1, "Active item should be applied")


# ============================================================================
# Reload Sound Preview Tests (Issue #1564)
# ============================================================================


func test_select_weapon_records_reload_preview_call() -> void:
	var result := menu.select_weapon_with_sound("shotgun")
	assert_true(result,
		"Selecting shotgun should succeed")
	assert_eq(menu.reload_preview_calls.size(), 1,
		"One reload preview should be recorded when weapon is selected")
	assert_eq(menu.reload_preview_calls[0], "shotgun",
		"Reload preview should be called with the correct weapon ID")


func test_select_each_weapon_records_its_own_reload_preview() -> void:
	var weapons := ["makarov_pm", "m16", "shotgun", "mini_uzi", "silenced_pistol", "sniper", "revolver"]
	for weapon_id in weapons:
		menu.reload_preview_calls.clear()
		menu.select_weapon_with_sound(weapon_id)
		assert_eq(menu.reload_preview_calls.size(), 1,
			"Exactly one reload preview call expected for " + weapon_id)
		assert_eq(menu.reload_preview_calls[0], weapon_id,
			"Reload preview weapon_id should match selected weapon for " + weapon_id)


func test_mock_audio_manager_play_weapon_reload_preview() -> void:
	var audio_manager := MockAudioManager.new()
	audio_manager.play_weapon_reload_preview("revolver")
	assert_eq(audio_manager.reload_preview_calls.size(), 1,
		"MockAudioManager should record play_weapon_reload_preview call")
	assert_eq(audio_manager.reload_preview_calls[0], "revolver",
		"Recorded weapon_id should be 'revolver'")


func test_mock_audio_manager_play_ui_click() -> void:
	var audio_manager := MockAudioManager.new()
	audio_manager.play_ui_click()
	assert_eq(audio_manager.ui_click_count, 1,
		"MockAudioManager should record play_ui_click call")


func test_mock_audio_manager_has_method_reload_preview() -> void:
	var audio_manager := MockAudioManager.new()
	assert_true(audio_manager.has_method("play_weapon_reload_preview"),
		"MockAudioManager should report having play_weapon_reload_preview")


func test_mock_audio_manager_has_method_ui_click() -> void:
	var audio_manager := MockAudioManager.new()
	assert_true(audio_manager.has_method("play_ui_click"),
		"MockAudioManager should report having play_ui_click")


func test_locked_weapon_does_not_trigger_reload_preview() -> void:
	var result := menu.select_weapon_with_sound("ak47")  # locked
	assert_false(result,
		"Selecting a locked weapon should fail")
	assert_eq(menu.reload_preview_calls.size(), 0,
		"No reload preview should be recorded for a locked weapon")


func test_unknown_weapon_does_not_trigger_reload_preview() -> void:
	var result := menu.select_weapon_with_sound("unknown_weapon")
	assert_false(result,
		"Selecting an unknown weapon should fail")
	assert_eq(menu.reload_preview_calls.size(), 0,
		"No reload preview should be recorded for an unknown weapon")


# ============================================================================
# Accordion Button Shine Overlay Tests (Issue #1561)
# ============================================================================


func test_accordion_button_has_no_shine_by_default() -> void:
	assert_false(menu.has_accordion_shine("weapon_accordion"),
		"Accordion button should have no shine overlay by default")


func test_condition_met_style_adds_shine_overlay() -> void:
	menu.apply_accordion_button_condition_met_style("weapon_accordion")

	assert_true(menu.has_accordion_shine("weapon_accordion"),
		"Applying condition-met style should add shine overlay to accordion button")


func test_default_style_removes_shine_overlay() -> void:
	menu.apply_accordion_button_condition_met_style("weapon_accordion")
	menu.apply_accordion_button_default_style("weapon_accordion")

	assert_false(menu.has_accordion_shine("weapon_accordion"),
		"Resetting to default style should remove shine overlay from accordion button")


func test_condition_met_style_applied_independently_per_button() -> void:
	menu.apply_accordion_button_condition_met_style("weapon_accordion")

	assert_true(menu.has_accordion_shine("weapon_accordion"),
		"Weapon accordion button should have shine overlay")
	assert_false(menu.has_accordion_shine("grenade_accordion"),
		"Grenade accordion button should NOT have shine overlay")
	assert_false(menu.has_accordion_shine("active_item_accordion"),
		"Active item accordion button should NOT have shine overlay")


func test_all_accordion_buttons_can_have_shine_independently() -> void:
	menu.apply_accordion_button_condition_met_style("weapon_accordion")
	menu.apply_accordion_button_condition_met_style("grenade_accordion")
	menu.apply_accordion_button_condition_met_style("active_item_accordion")

	assert_true(menu.has_accordion_shine("weapon_accordion"),
		"Weapon accordion should have shine")
	assert_true(menu.has_accordion_shine("grenade_accordion"),
		"Grenade accordion should have shine")
	assert_true(menu.has_accordion_shine("active_item_accordion"),
		"Active item accordion should have shine")


func test_default_style_removes_only_targeted_button_shine() -> void:
	menu.apply_accordion_button_condition_met_style("weapon_accordion")
	menu.apply_accordion_button_condition_met_style("grenade_accordion")
	menu.apply_accordion_button_default_style("weapon_accordion")

	assert_false(menu.has_accordion_shine("weapon_accordion"),
		"Weapon accordion shine should be removed after default style reset")
	assert_true(menu.has_accordion_shine("grenade_accordion"),
		"Grenade accordion shine should remain untouched")


func test_reapplying_condition_met_style_does_not_duplicate_shine() -> void:
	menu.apply_accordion_button_condition_met_style("weapon_accordion")
	menu.apply_accordion_button_condition_met_style("weapon_accordion")

	assert_true(menu.has_accordion_shine("weapon_accordion"),
		"Shine should still be active after re-applying condition-met style (no duplicate)")


func test_default_style_on_button_with_no_shine_is_safe() -> void:
	# Should not error when removing a non-existent shine overlay.
	menu.apply_accordion_button_default_style("weapon_accordion")

	assert_false(menu.has_accordion_shine("weapon_accordion"),
		"Button with no shine should remain without shine after default reset")


# ============================================================================
# Weapon Selection Animation Phase Order Tests (Issue #1575)
# ============================================================================


class MockGlintShaderPhaseOrder:
	## Mirrors the phase boundary constants from weapon_select_glint.gdshader (Issue #1575).
	## Phase 1 is the top-edge glint sweep (slow), Phase 2 is the diagonal sweep (fast).
	const TOTAL_DURATION_S: float = 1.02
	const PHASE1_END_PROGRESS: float = 0.784   # 0.80 / 1.02 — end of top-edge sweep
	const PHASE2_START_PROGRESS: float = 0.784 # 0.80 / 1.02 — start of diagonal sweep

	## Returns true if, at the given anim_progress, Phase 1 (top-edge) is active.
	func is_phase1_active(anim_progress: float) -> bool:
		return anim_progress < PHASE1_END_PROGRESS

	## Returns true if, at the given anim_progress, Phase 2 (diagonal) is active.
	func is_phase2_active(anim_progress: float) -> bool:
		return anim_progress >= PHASE2_START_PROGRESS


func test_phase1_top_edge_runs_first() -> void:
	var shader := MockGlintShaderPhaseOrder.new()
	# At progress 0.0 (very start), Phase 1 (top-edge) should be active, Phase 2 should not.
	assert_true(shader.is_phase1_active(0.0),
		"Phase 1 (top-edge glint) should be active at the very start of the animation")
	assert_false(shader.is_phase2_active(0.0),
		"Phase 2 (diagonal sweep) should NOT be active at the very start of the animation")


func test_phase2_diagonal_runs_second() -> void:
	var shader := MockGlintShaderPhaseOrder.new()
	# At progress 0.9 (late in animation), Phase 2 (diagonal) should be active, Phase 1 should not.
	assert_false(shader.is_phase1_active(0.9),
		"Phase 1 (top-edge glint) should NOT be active late in the animation")
	assert_true(shader.is_phase2_active(0.9),
		"Phase 2 (diagonal sweep) should be active late in the animation")


func test_phase1_occupies_majority_of_animation() -> void:
	var shader := MockGlintShaderPhaseOrder.new()
	# Phase 1 covers 0.0 → 0.784 (78.4% of total), Phase 2 covers 0.784 → 1.0 (21.6%).
	assert_true(shader.PHASE1_END_PROGRESS > 0.5,
		"Phase 1 (top-edge glint) should occupy more than half of the total animation duration")
	assert_true(shader.PHASE2_START_PROGRESS > 0.5,
		"Phase 2 (diagonal sweep) should start after the halfway point")


func test_phases_do_not_overlap() -> void:
	var shader := MockGlintShaderPhaseOrder.new()
	assert_eq(shader.PHASE1_END_PROGRESS, shader.PHASE2_START_PROGRESS,
		"Phase 1 end and Phase 2 start must be at the same boundary (no gap or overlap)")


func test_phase_boundary_value() -> void:
	var shader := MockGlintShaderPhaseOrder.new()
	# 0.80 s / 1.02 s ≈ 0.784 — verify the constant is correct.
	var expected_boundary: float = 0.80 / shader.TOTAL_DURATION_S
	assert_almost_eq(shader.PHASE1_END_PROGRESS, expected_boundary, 0.001,
		"Phase boundary should equal 0.80 s / 1.02 s ≈ 0.784")
