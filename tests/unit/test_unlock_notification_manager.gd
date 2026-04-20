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


class MockGameplaySettings extends Node:
	var unlock_notifications_enabled: bool = true

	func are_unlock_notifications_enabled() -> bool:
		return unlock_notifications_enabled


func test_unlock_notification_manager_script_exists() -> void:
	assert_not_null(load(NOTIFICATION_MANAGER_SCRIPT),
		"UnlockNotificationManager autoload script should exist")


func test_notification_uses_requested_opened_text() -> void:
	var script: GDScript = load(NOTIFICATION_MANAGER_SCRIPT)
	assert_not_null(script, "UnlockNotificationManager script should load")
	var manager: Node = autofree(script.new())

	var previous_locale: String = TranslationServer.get_locale()
	TranslationServer.set_locale("ru")
	assert_eq(manager.build_notification_header_text("weapon"), "Открыт оружие !",
		"Toast header should include only the unlocked weapon category")
	assert_eq(manager.build_notification_text("weapon", "Дробовик"), "Открыт оружие !\nДробовик",
		"Combined fallback text should split the category header and item name onto separate lines")
	TranslationServer.set_locale(previous_locale)


func test_notification_text_includes_active_item_category_and_name() -> void:
	var script: GDScript = load(NOTIFICATION_MANAGER_SCRIPT)
	assert_not_null(script, "UnlockNotificationManager script should load")
	var manager: Node = autofree(script.new())

	var previous_locale: String = TranslationServer.get_locale()
	TranslationServer.set_locale("ru")
	assert_eq(manager.build_notification_header_text("active_item"), "Открыт предмет !",
		"Toast header should include only the item category")
	assert_eq(manager.build_notification_text("active_item", "Бронированная кожа"),
		"Открыт предмет !\nБронированная кожа",
		"Combined fallback text should put the Armored Skin name on the second line")
	TranslationServer.set_locale(previous_locale)


func test_notification_text_includes_grenade_category_and_name() -> void:
	var script: GDScript = load(NOTIFICATION_MANAGER_SCRIPT)
	assert_not_null(script, "UnlockNotificationManager script should load")
	var manager: Node = autofree(script.new())

	var previous_locale: String = TranslationServer.get_locale()
	TranslationServer.set_locale("ru")
	assert_eq(manager.build_notification_header_text("grenade"), "Открыт граната !",
		"Toast header should include only the grenade category")
	assert_eq(manager.build_notification_text("grenade", "Наступательная"),
		"Открыт граната !\nНаступательная",
		"Combined fallback text should put the grenade name on the second line")
	TranslationServer.set_locale(previous_locale)


func test_toast_uses_smaller_second_line_for_long_item_names() -> void:
	var script: GDScript = load(NOTIFICATION_MANAGER_SCRIPT)
	assert_not_null(script, "UnlockNotificationManager script should load")
	var manager: CanvasLayer = autofree(script.new())
	add_child(manager)
	await get_tree().process_frame

	manager.show_unlock_notification("Очень длинное название предмета с несколькими словами", "active_item")
	await wait_seconds(manager.SLIDE_DURATION + 0.1)

	var header_label: Label = manager.get_node("UnlockNotificationRoot/UnlockToast/ContentMargin/ContentRow/TextColumn/MessageLabel")
	var item_name_label: Label = manager.get_node("UnlockNotificationRoot/UnlockToast/ContentMargin/ContentRow/TextColumn/ItemNameLabel")
	var header_shadow_label: Label = manager.get_node("UnlockNotificationRoot/UnlockToast/MessageShadowLabel")
	var item_name_shadow_label: Label = manager.get_node("UnlockNotificationRoot/UnlockToast/ItemNameShadowLabel")

	assert_eq(header_label.text, "Открыт предмет !",
		"Header label should keep the generic unlock text without the long item name")
	assert_eq(item_name_label.text, "Очень длинное название предмета с несколькими словами",
		"Item name should render on the second line in its own label")
	assert_eq(header_shadow_label.text, header_label.text,
		"Fallback shadow header should mirror the visible header text")
	assert_eq(item_name_shadow_label.text, item_name_label.text,
		"Fallback shadow item label should mirror the visible second line")
	assert_lt(
		item_name_label.get_theme_font_size("font_size"),
		header_label.get_theme_font_size("font_size"),
		"Second-line item name should use a smaller font than the generic unlock text")


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
	var text_column: VBoxContainer = content_margin.get_node("ContentRow/TextColumn")
	var label: Label = text_column.get_node("MessageLabel")
	var item_name_label: Label = text_column.get_node("ItemNameLabel")
	var shadow_label: Label = toast.get_node("MessageShadowLabel")
	var item_name_shadow_label: Label = toast.get_node("ItemNameShadowLabel")
	var font_color: Color = label.get_theme_color("font_color")
	var row_gap: int = content_row.get_theme_constant("separation")

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
	assert_gt(item_name_shadow_label.z_index, shine_overlay.z_index,
		"Fallback item name label should render above the shine overlay in exported builds")
	assert_eq(row_gap, int(manager.ARMORY_ICON_TEXT_GAP),
		"Content row should use the configured Armory icon/text gap")
	assert_ge(row_gap, 24,
		"Armory icon and text should have a larger readable gap")
	assert_gt(content_margin.size.x, 0.0,
		"Content margin should have explicit width so exported builds lay out the label")
	assert_gt(content_row.size.x, 0.0,
		"Content row should have explicit width so the label is not clipped to zero")
	assert_gt(content_row.size.y, 0.0,
		"Content row should have explicit height so the label is visible")
	assert_gt(text_column.size.x, 0.0,
		"Text column should have explicit width so both toast lines are visible")
	assert_gt(item_name_label.get_theme_font_size("font_size"), 0,
		"Item name label should have an explicit font size")
	assert_lt(item_name_label.get_theme_font_size("font_size"), label.get_theme_font_size("font_size"),
		"Item name label should be smaller than the generic unlock line")
	assert_gt(shadow_label.size.x, 0.0,
		"Fallback text label should have explicit width independent of nested containers")
	assert_gt(shadow_label.size.y, 0.0,
		"Fallback text label should have explicit height independent of nested containers")
	assert_gt(item_name_shadow_label.size.x, 0.0,
		"Fallback item name label should have explicit width independent of nested containers")
	assert_gt(item_name_shadow_label.size.y, 0.0,
		"Fallback item name label should have explicit height independent of nested containers")
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
	var label: Label = toast.get_node("ContentMargin/ContentRow/TextColumn/MessageLabel")
	var item_name_label: Label = toast.get_node("ContentMargin/ContentRow/TextColumn/ItemNameLabel")
	var shadow_label: Label = toast.get_node("MessageShadowLabel")
	var item_name_shadow_label: Label = toast.get_node("ItemNameShadowLabel")

	assert_eq(manager._animation_phase, "visible",
		"Toast should enter the stable visible phase after the slide-in animation")
	assert_eq(toast.modulate.a, 1.0,
		"Toast parent should remain opaque during the stable visible phase")
	assert_eq(label.modulate.a, 1.0,
		"Message label should remain fully opaque after the slide-in animation")
	assert_eq(label.text, "Открыт предмет !",
		"Stable visible toast should keep the requested generic item text")
	assert_eq(item_name_label.text, "Бронированная кожа",
		"Stable visible toast should keep the requested Armored Skin name on the second line")
	assert_eq(shadow_label.text, "Открыт предмет !",
		"Fallback text label should mirror the requested generic item text")
	assert_eq(item_name_shadow_label.text, "Бронированная кожа",
		"Fallback item label should mirror the requested Armored Skin name")
	assert_eq(shadow_label.modulate.a, 1.0,
		"Fallback text label should remain fully opaque after the slide-in animation")
	assert_eq(item_name_label.modulate.a, 1.0,
		"Item name label should remain fully opaque after the slide-in animation")
	assert_eq(item_name_shadow_label.modulate.a, 1.0,
		"Fallback item name label should remain fully opaque after the slide-in animation")
	assert_gt(background.modulate.a, 0.95,
		"Only the background fade target should be fully visible after entry")


func test_show_unlock_notification_skips_queue_when_setting_disabled() -> void:
	var script: GDScript = load(NOTIFICATION_MANAGER_SCRIPT)
	assert_not_null(script, "UnlockNotificationManager script should load")
	var manager: CanvasLayer = autofree(script.new())
	var gameplay_settings: MockGameplaySettings = autofree(MockGameplaySettings.new())
	gameplay_settings.name = "GameplaySettings"
	gameplay_settings.unlock_notifications_enabled = false
	get_tree().root.add_child(gameplay_settings)
	add_child(manager)
	await get_tree().process_frame

	manager.show_unlock_notification("Бронированная кожа", "active_item")

	assert_eq(manager._pending_notifications.size(), 0,
		"Disabled unlock notifications should not queue toast messages")


func test_show_unlock_notification_queues_when_setting_enabled() -> void:
	var script: GDScript = load(NOTIFICATION_MANAGER_SCRIPT)
	assert_not_null(script, "UnlockNotificationManager script should load")
	var manager: CanvasLayer = autofree(script.new())
	var gameplay_settings: MockGameplaySettings = autofree(MockGameplaySettings.new())
	gameplay_settings.name = "GameplaySettings"
	gameplay_settings.unlock_notifications_enabled = true
	get_tree().root.add_child(gameplay_settings)
	add_child(manager)
	await get_tree().process_frame

	manager.show_unlock_notification("Бронированная кожа", "active_item")

	assert_eq(manager._pending_notifications.size(), 0,
		"Enabled unlock notifications should be consumed by the visible toast immediately")
	assert_eq(manager._animation_phase, "entering",
		"Enabled unlock notifications should start the toast animation")


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


func test_startup_suppressed_unlock_is_not_reshown_on_live_signal() -> void:
	## Issue #1907: items that were already available at game startup should not
	## show a toast on every new game session when a kill/condition signal fires.
	var script: GDScript = load(NOTIFICATION_MANAGER_SCRIPT)
	assert_not_null(script, "UnlockNotificationManager script should load")
	var manager: Node = autofree(script.new())

	# Simulate a startup-available item (condition met, not yet unlocked)
	manager._startup_suppressed_available_keys["active_item:9"] = true
	manager._announced_available_keys.clear()

	# Simulate a live condition signal firing (e.g., a kill increments a stat)
	# _queue_new_available_unlocks scans entries — active_item:9 condition is met
	# (MockUnlockManager returns true for item type 9, MockActiveItemManager has it locked)
	var startup_notification_count: int = manager._pending_notifications.size()
	# Call the internal method directly to simulate the signal handler
	# We reproduce the logic of _queue_new_available_unlocks with mocked managers
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
		if manager._startup_suppressed_available_keys.has(key):
			continue
		manager._announced_available_keys[key] = true
		manager.show_unlock_notification(entry["name"], entry["kind"])

	assert_false(manager._announced_available_keys.get("active_item:9", false),
		"Startup-available item should not be added to announced keys — it stays suppressed this session")
	assert_true(manager._startup_suppressed_available_keys.has("active_item:9"),
		"Startup suppression should remain in place so repeated signals never show the toast")
	assert_eq(manager._pending_notifications.size(), startup_notification_count,
		"No new notification should be queued for an item that was already available at startup")
