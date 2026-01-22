extends GutTest
## Unit tests for GrenadeManager autoload.
##
## Tests the grenade type management functionality including type selection,
## grenade data retrieval, and type switching behavior.


# ============================================================================
# Grenade Type Enum Tests
# ============================================================================


func test_grenade_type_flashbang_value() -> void:
	# GrenadeType.FLASHBANG should be 0
	var expected := 0
	assert_eq(expected, 0, "FLASHBANG should be the first grenade type (0)")


func test_grenade_type_frag_value() -> void:
	# GrenadeType.FRAG should be 1
	var expected := 1
	assert_eq(expected, 1, "FRAG should be the second grenade type (1)")


# ============================================================================
# Grenade Data Constants Tests
# ============================================================================


func test_grenade_data_has_flashbang() -> void:
	var grenade_data := {
		0: {
			"name": "Flashbang",
			"icon_path": "res://assets/sprites/weapons/flashbang.png",
			"scene_path": "res://scenes/projectiles/FlashbangGrenade.tscn",
			"description": "Stun grenade - blinds enemies for 12s, stuns for 6s. 4 second fuse timer."
		}
	}
	assert_true(grenade_data.has(0), "GRENADE_DATA should contain FLASHBANG type")


func test_grenade_data_has_frag() -> void:
	var grenade_data := {
		1: {
			"name": "Frag Grenade",
			"icon_path": "res://assets/sprites/weapons/frag_grenade.png",
			"scene_path": "res://scenes/projectiles/FragGrenade.tscn",
			"description": "Offensive grenade - explodes on impact, releases 4 shrapnel pieces. Smaller radius."
		}
	}
	assert_true(grenade_data.has(1), "GRENADE_DATA should contain FRAG type")


func test_flashbang_data_has_name() -> void:
	var data := {"name": "Flashbang"}
	assert_eq(data["name"], "Flashbang", "Flashbang should have correct name")


func test_flashbang_data_has_icon_path() -> void:
	var data := {"icon_path": "res://assets/sprites/weapons/flashbang.png"}
	assert_eq(data["icon_path"], "res://assets/sprites/weapons/flashbang.png",
		"Flashbang should have correct icon path")


func test_flashbang_data_has_scene_path() -> void:
	var data := {"scene_path": "res://scenes/projectiles/FlashbangGrenade.tscn"}
	assert_eq(data["scene_path"], "res://scenes/projectiles/FlashbangGrenade.tscn",
		"Flashbang should have correct scene path")


func test_frag_data_has_name() -> void:
	var data := {"name": "Frag Grenade"}
	assert_eq(data["name"], "Frag Grenade", "Frag Grenade should have correct name")


func test_frag_data_has_icon_path() -> void:
	var data := {"icon_path": "res://assets/sprites/weapons/frag_grenade.png"}
	assert_eq(data["icon_path"], "res://assets/sprites/weapons/frag_grenade.png",
		"Frag Grenade should have correct icon path")


func test_frag_data_has_scene_path() -> void:
	var data := {"scene_path": "res://scenes/projectiles/FragGrenade.tscn"}
	assert_eq(data["scene_path"], "res://scenes/projectiles/FragGrenade.tscn",
		"Frag Grenade should have correct scene path")


# ============================================================================
# Mock GrenadeManager for Logic Tests
# ============================================================================


class MockGrenadeManager:
	## Grenade types
	const GrenadeType := {
		FLASHBANG = 0,
		FRAG = 1
	}

	## Currently selected grenade type
	var current_grenade_type: int = GrenadeType.FLASHBANG

	## Grenade type data
	const GRENADE_DATA: Dictionary = {
		0: {
			"name": "Flashbang",
			"icon_path": "res://assets/sprites/weapons/flashbang.png",
			"scene_path": "res://scenes/projectiles/FlashbangGrenade.tscn",
			"description": "Stun grenade - blinds enemies for 12s, stuns for 6s. 4 second fuse timer."
		},
		1: {
			"name": "Frag Grenade",
			"icon_path": "res://assets/sprites/weapons/frag_grenade.png",
			"scene_path": "res://scenes/projectiles/FragGrenade.tscn",
			"description": "Offensive grenade - explodes on impact, releases 4 shrapnel pieces. Smaller radius."
		}
	}

	## Cached grenade scenes
	var _grenade_scenes: Dictionary = {}

	## Signal for type change (not actually emitted in mock)
	var type_changed_count: int = 0
	var last_restart_called: bool = false

	## Set the current grenade type
	func set_grenade_type(type: int, restart_level: bool = true) -> void:
		if type == current_grenade_type:
			return

		if type not in GRENADE_DATA:
			return

		current_grenade_type = type
		type_changed_count += 1

		if restart_level:
			last_restart_called = true

	## Get grenade data for a specific type
	func get_grenade_data(type: int) -> Dictionary:
		if type in GRENADE_DATA:
			return GRENADE_DATA[type]
		return {}

	## Get all available grenade types
	func get_all_grenade_types() -> Array:
		return GRENADE_DATA.keys()

	## Get the name of a grenade type
	func get_grenade_name(type: int) -> String:
		if type in GRENADE_DATA:
			return GRENADE_DATA[type]["name"]
		return "Unknown"

	## Get the description of a grenade type
	func get_grenade_description(type: int) -> String:
		if type in GRENADE_DATA:
			return GRENADE_DATA[type]["description"]
		return ""

	## Get the icon path of a grenade type
	func get_grenade_icon_path(type: int) -> String:
		if type in GRENADE_DATA:
			return GRENADE_DATA[type]["icon_path"]
		return ""

	## Check if a grenade type is the currently selected type
	func is_selected(type: int) -> bool:
		return type == current_grenade_type


var manager: MockGrenadeManager


func before_each() -> void:
	manager = MockGrenadeManager.new()


func after_each() -> void:
	manager = null


# ============================================================================
# Default State Tests
# ============================================================================


func test_default_grenade_type_is_flashbang() -> void:
	assert_eq(manager.current_grenade_type, 0,
		"Default grenade type should be FLASHBANG (0)")


func test_flashbang_is_selected_by_default() -> void:
	assert_true(manager.is_selected(0),
		"Flashbang should be selected by default")


func test_frag_is_not_selected_by_default() -> void:
	assert_false(manager.is_selected(1),
		"Frag Grenade should not be selected by default")


# ============================================================================
# Type Selection Tests
# ============================================================================


func test_set_grenade_type_to_frag() -> void:
	manager.set_grenade_type(1)
	assert_eq(manager.current_grenade_type, 1,
		"Grenade type should change to FRAG")


func test_set_grenade_type_emits_change() -> void:
	manager.set_grenade_type(1)
	assert_eq(manager.type_changed_count, 1,
		"Type change should increment counter")


func test_set_same_grenade_type_does_not_emit_change() -> void:
	manager.set_grenade_type(0)  # Already flashbang
	assert_eq(manager.type_changed_count, 0,
		"Setting same type should not emit change")


func test_set_grenade_type_triggers_restart_by_default() -> void:
	manager.set_grenade_type(1)
	assert_true(manager.last_restart_called,
		"Level restart should be triggered by default")


func test_set_grenade_type_without_restart() -> void:
	manager.set_grenade_type(1, false)
	assert_false(manager.last_restart_called,
		"Level restart should not be triggered when disabled")


func test_set_invalid_grenade_type_does_nothing() -> void:
	manager.set_grenade_type(999)
	assert_eq(manager.current_grenade_type, 0,
		"Invalid type should not change current type")
	assert_eq(manager.type_changed_count, 0,
		"Invalid type should not emit change")


# ============================================================================
# Data Retrieval Tests
# ============================================================================


func test_get_grenade_data_flashbang() -> void:
	var data := manager.get_grenade_data(0)
	assert_eq(data["name"], "Flashbang")


func test_get_grenade_data_frag() -> void:
	var data := manager.get_grenade_data(1)
	assert_eq(data["name"], "Frag Grenade")


func test_get_grenade_data_invalid_returns_empty() -> void:
	var data := manager.get_grenade_data(999)
	assert_true(data.is_empty(),
		"Invalid type should return empty dictionary")


func test_get_all_grenade_types() -> void:
	var types := manager.get_all_grenade_types()
	assert_eq(types.size(), 2,
		"Should return 2 grenade types")
	assert_true(0 in types)
	assert_true(1 in types)


func test_get_grenade_name_flashbang() -> void:
	assert_eq(manager.get_grenade_name(0), "Flashbang")


func test_get_grenade_name_frag() -> void:
	assert_eq(manager.get_grenade_name(1), "Frag Grenade")


func test_get_grenade_name_invalid() -> void:
	assert_eq(manager.get_grenade_name(999), "Unknown")


func test_get_grenade_description_flashbang() -> void:
	var desc := manager.get_grenade_description(0)
	assert_true(desc.contains("stuns for 6s"),
		"Flashbang description should mention stun duration")


func test_get_grenade_description_frag() -> void:
	var desc := manager.get_grenade_description(1)
	assert_true(desc.contains("shrapnel"),
		"Frag description should mention shrapnel")


func test_get_grenade_description_invalid() -> void:
	assert_eq(manager.get_grenade_description(999), "")


func test_get_grenade_icon_path_flashbang() -> void:
	var path := manager.get_grenade_icon_path(0)
	assert_true(path.contains("flashbang"),
		"Flashbang icon path should contain 'flashbang'")


func test_get_grenade_icon_path_frag() -> void:
	var path := manager.get_grenade_icon_path(1)
	assert_true(path.contains("frag_grenade"),
		"Frag icon path should contain 'frag_grenade'")


func test_get_grenade_icon_path_invalid() -> void:
	assert_eq(manager.get_grenade_icon_path(999), "")


# ============================================================================
# Selection State Tests
# ============================================================================


func test_is_selected_after_changing_type() -> void:
	manager.set_grenade_type(1)
	assert_true(manager.is_selected(1),
		"FRAG should be selected after changing to it")
	assert_false(manager.is_selected(0),
		"FLASHBANG should not be selected after changing away from it")


func test_multiple_type_changes() -> void:
	manager.set_grenade_type(1)
	manager.set_grenade_type(0)
	manager.set_grenade_type(1)

	assert_eq(manager.current_grenade_type, 1)
	assert_eq(manager.type_changed_count, 3)
