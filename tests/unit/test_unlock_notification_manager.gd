extends GutTest
## Regression tests for the unlock notification toast requested in Issue #1831.


const NOTIFICATION_MANAGER_SCRIPT := "res://scripts/autoload/unlock_notification_manager.gd"


class MockGameManager extends Node:
	var unlocked_weapons: Dictionary = {
		"shotgun": false,
		"m16": true
	}

	func is_weapon_unlocked(weapon_id: String) -> bool:
		return unlocked_weapons.get(weapon_id, false)


class MockGrenadeManager extends Node:
	var unlocked_grenades: Dictionary = {
		1: false,
		2: true
	}

	func get_all_grenade_types() -> Array:
		return unlocked_grenades.keys()

	func is_grenade_unlocked(grenade_type: int) -> bool:
		return unlocked_grenades.get(grenade_type, false)

	func get_grenade_data(grenade_type: int) -> Dictionary:
		match grenade_type:
			1:
				return {"name": "Frag Grenade", "name_key": "GRENADE_FRAG_NAME"}
			2:
				return {"name": "F-1 Grenade", "name_key": "GRENADE_DEFENSIVE_NAME"}
			_:
				return {}


class MockActiveItemManager extends Node:
	var unlocked_active_items: Dictionary = {
		7: false,
		8: true,
		9: false
	}

	func get_all_active_item_types() -> Array:
		return unlocked_active_items.keys()

	func is_active_item_unlocked(item_type: int) -> bool:
		return unlocked_active_items.get(item_type, false)

	func get_active_item_data(item_type: int) -> Dictionary:
		match item_type:
			7:
				return {"name": "Force Field", "name_key": "ITEM_FORCE_FIELD_NAME"}
			8:
				return {"name": "Trajectory Glasses", "name_key": "ITEM_TRAJECTORY_GLASSES_NAME"}
			9:
				return {"name": "Laser Sight", "name_key": "ITEM_LASER_SIGHT_NAME"}
			_:
				return {}


class MockUnlockManager extends Node:
	func is_weapon_condition_met(weapon_id: String) -> bool:
		return weapon_id == "shotgun" or weapon_id == "m16"

	func is_grenade_condition_met(grenade_type: int) -> bool:
		return grenade_type == 1 or grenade_type == 2

	func is_active_item_condition_met(item_type: int) -> bool:
		return item_type == 7 or item_type == 8 or item_type == 9


func test_unlock_notification_manager_script_exists() -> void:
	assert_not_null(load(NOTIFICATION_MANAGER_SCRIPT),
		"UnlockNotificationManager autoload script should exist")


func test_notification_uses_requested_opened_text() -> void:
	var script: GDScript = load(NOTIFICATION_MANAGER_SCRIPT)
	assert_not_null(script, "UnlockNotificationManager script should load")
	var manager: Node = autofree(script.new())

	var previous_locale: String = TranslationServer.get_locale()
	TranslationServer.set_locale("ru")
	assert_eq(manager.build_notification_text("weapon", "Дробовик"), "Открыт оружие Дробовик !",
		"Toast text should include the unlocked weapon category and name")
	TranslationServer.set_locale(previous_locale)


func test_notification_text_includes_active_item_category_and_name() -> void:
	var script: GDScript = load(NOTIFICATION_MANAGER_SCRIPT)
	assert_not_null(script, "UnlockNotificationManager script should load")
	var manager: Node = autofree(script.new())

	var previous_locale: String = TranslationServer.get_locale()
	TranslationServer.set_locale("ru")
	assert_eq(manager.build_notification_text("active_item", "Бронированная кожа"),
		"Открыт предмет Бронированная кожа !",
		"Toast text should include the item category and Armored Skin name")
	TranslationServer.set_locale(previous_locale)


func test_notification_text_includes_grenade_category_and_name() -> void:
	var script: GDScript = load(NOTIFICATION_MANAGER_SCRIPT)
	assert_not_null(script, "UnlockNotificationManager script should load")
	var manager: Node = autofree(script.new())

	var previous_locale: String = TranslationServer.get_locale()
	TranslationServer.set_locale("ru")
	assert_eq(manager.build_notification_text("grenade", "Наступательная"),
		"Открыт граната Наступательная !",
		"Toast text should include the grenade category and name")
	TranslationServer.set_locale(previous_locale)


func test_display_duration_is_four_seconds() -> void:
	var script: GDScript = load(NOTIFICATION_MANAGER_SCRIPT)
	assert_not_null(script, "UnlockNotificationManager script should load")
	var manager: Node = autofree(script.new())

	assert_eq(manager.DISPLAY_DURATION, 4.0,
		"Unlock notifications should stay visible for exactly four seconds")
	assert_eq(manager.SLIDE_OUT_REPEAT_COUNT, 1,
		"Unlock notifications should play the exit slide exactly once per toast")


func test_gold_text_remains_above_shine_overlay() -> void:
	var script: GDScript = load(NOTIFICATION_MANAGER_SCRIPT)
	assert_not_null(script, "UnlockNotificationManager script should load")
	var manager: CanvasLayer = autofree(script.new())
	add_child(manager)
	await get_tree().process_frame

	var toast: Control = manager.get_node("UnlockNotificationRoot/UnlockToast")
	var shine_overlay: ColorRect = toast.get_node("GoldShineOverlay")
	var background: Panel = toast.get_node("ToastBackground")
	var content_margin: MarginContainer = toast.get_node("ContentMargin")
	var content_row: HBoxContainer = content_margin.get_node("ContentRow")
	var label: Label = content_margin.get_node("ContentRow/MessageLabel")
	var shadow_label: Label = toast.get_node("MessageShadowLabel")
	var font_color: Color = label.get_theme_color("font_color")

	assert_eq(toast.modulate.a, 1.0,
		"Toast container alpha should stay opaque so child label text is never faded by parent modulation")
	assert_eq(background.modulate.a, 0.0,
		"Toast background should own fade animation instead of the content parent")
	assert_gt(content_margin.z_index, shine_overlay.z_index,
		"Content should render above the shine overlay")
	assert_gt(content_margin.z_index, background.z_index,
		"Content should render above the toast background")
	assert_gt(shadow_label.z_index, shine_overlay.z_index,
		"Fallback text label should render above the shine overlay in exported builds")
	assert_gt(content_margin.size.x, 0.0,
		"Content margin should have explicit width so exported builds lay out the label")
	assert_gt(content_row.size.x, 0.0,
		"Content row should have explicit width so the label is not clipped to zero")
	assert_gt(content_row.size.y, 0.0,
		"Content row should have explicit height so the label is visible")
	assert_gt(shadow_label.size.x, 0.0,
		"Fallback text label should have explicit width independent of nested containers")
	assert_gt(shadow_label.size.y, 0.0,
		"Fallback text label should have explicit height independent of nested containers")
	assert_gt(font_color.r, 0.9, "Toast text should use a visible gold color")
	assert_gt(font_color.g, 0.75, "Toast text should use a visible gold color")
	assert_gt(font_color.b, 0.25, "Toast text should use a visible gold color")
	assert_eq(font_color.a, 1.0, "Toast text should be fully opaque")


func test_toast_animation_keeps_label_opaque_after_entry() -> void:
	var script: GDScript = load(NOTIFICATION_MANAGER_SCRIPT)
	assert_not_null(script, "UnlockNotificationManager script should load")
	var manager: CanvasLayer = autofree(script.new())
	add_child(manager)
	await get_tree().process_frame

	manager.show_unlock_notification("Бронированная кожа", "active_item")
	await wait_seconds(manager.SLIDE_DURATION + 0.1)

	var toast: Control = manager.get_node("UnlockNotificationRoot/UnlockToast")
	var background: Panel = toast.get_node("ToastBackground")
	var label: Label = toast.get_node("ContentMargin/ContentRow/MessageLabel")
	var shadow_label: Label = toast.get_node("MessageShadowLabel")

	assert_eq(manager._animation_phase, "visible",
		"Toast should enter the stable visible phase after the slide-in animation")
	assert_eq(toast.modulate.a, 1.0,
		"Toast parent should remain opaque during the stable visible phase")
	assert_eq(label.modulate.a, 1.0,
		"Message label should remain fully opaque after the slide-in animation")
	assert_eq(label.text, "Открыт предмет Бронированная кожа !",
		"Stable visible toast should keep the requested Armored Skin text")
	assert_eq(shadow_label.text, "Открыт предмет Бронированная кожа !",
		"Fallback text label should mirror the requested Armored Skin text")
	assert_eq(shadow_label.modulate.a, 1.0,
		"Fallback text label should remain fully opaque after the slide-in animation")
	assert_gt(background.modulate.a, 0.95,
		"Only the background fade target should be fully visible after entry")


func test_collects_only_locked_items_with_met_conditions() -> void:
	var script: GDScript = load(NOTIFICATION_MANAGER_SCRIPT)
	assert_not_null(script, "UnlockNotificationManager script should load")
	var manager: Node = autofree(script.new())
	var unlock_manager: Node = autofree(MockUnlockManager.new())
	var game_manager: Node = autofree(MockGameManager.new())
	var grenade_manager: Node = autofree(MockGrenadeManager.new())
	var active_item_manager: Node = autofree(MockActiveItemManager.new())

	var entries: Array = manager.collect_available_unlock_entries_from_managers(
		unlock_manager,
		game_manager,
		grenade_manager,
		active_item_manager)

	var keys: Array[String] = []
	for entry in entries:
		keys.append(entry["key"])

	assert_true("weapon:shotgun" in keys, "Locked shotgun with met condition should be announced")
	assert_true("grenade:1" in keys, "Locked frag grenade with met condition should be announced")
	assert_true("active_item:7" in keys, "Locked force field with met condition should be announced")
	assert_true("active_item:9" in keys, "Locked laser sight with met condition should be announced")
	assert_false("weapon:m16" in keys, "Already unlocked weapons should not be announced")
	assert_false("grenade:2" in keys, "Already unlocked grenades should not be announced")
	assert_false("active_item:8" in keys, "Already unlocked active items should not be announced")


func test_startup_suppressed_unlock_can_announce_after_live_signal() -> void:
	var script: GDScript = load(NOTIFICATION_MANAGER_SCRIPT)
	assert_not_null(script, "UnlockNotificationManager script should load")
	var manager: Node = autofree(script.new())

	manager._startup_suppressed_available_keys["active_item:9"] = true
	manager._announced_available_keys.clear()

	var unlock_manager: Node = autofree(MockUnlockManager.new())
	var game_manager: Node = autofree(MockGameManager.new())
	var grenade_manager: Node = autofree(MockGrenadeManager.new())
	var active_item_manager: Node = autofree(MockActiveItemManager.new())
	for entry in manager.collect_available_unlock_entries_from_managers(
			unlock_manager,
			game_manager,
			grenade_manager,
			active_item_manager):
		var key: String = entry["key"]
		if manager._announced_available_keys.get(key, false):
			continue
		manager._announced_available_keys[key] = true
		manager._startup_suppressed_available_keys.erase(key)
		manager.show_unlock_notification(entry["name"], entry["kind"])

	assert_true(manager._announced_available_keys.get("active_item:9", false),
		"Live stat signals should announce an item even if it was available during startup seeding")
	assert_false(manager._startup_suppressed_available_keys.has("active_item:9"),
		"Startup suppression should be consumed once a live signal announces the unlock")
	assert_true(manager._pending_notifications.size() > 0,
		"A notification should be queued for the live condition signal")
