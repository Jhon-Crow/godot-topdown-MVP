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
		8: true
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
			_:
				return {}


class MockUnlockManager extends Node:
	func is_weapon_condition_met(weapon_id: String) -> bool:
		return weapon_id == "shotgun" or weapon_id == "m16"

	func is_grenade_condition_met(grenade_type: int) -> bool:
		return grenade_type == 1 or grenade_type == 2

	func is_active_item_condition_met(item_type: int) -> bool:
		return item_type == 7 or item_type == 8


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
	assert_false("weapon:m16" in keys, "Already unlocked weapons should not be announced")
	assert_false("grenade:2" in keys, "Already unlocked grenades should not be announced")
	assert_false("active_item:8" in keys, "Already unlocked active items should not be announced")
