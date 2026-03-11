extends GutTest
## Unit tests for the UnlockTableMenu (Issue #1002).
##
## Tests the logic for building the unlock table rows, collecting
## item names, and identifying free (undistributed) items.


# ============================================================================
# Mock Managers
# ============================================================================


class MockUnlockManager:
	const UNLOCK_CONDITIONS: Dictionary = {
		"res://scenes/levels/LabyrinthLevel.tscn": {
			"min_rank": "D",
			"weapons": ["mini_uzi"],
			"grenades": [],
			"active_items": []
		},
		"res://scenes/levels/BuildingLevel.tscn": {
			"min_rank": "D",
			"weapons": ["shotgun"],
			"grenades": [],
			"active_items": []
		},
		"res://scenes/levels/TestTier.tscn": {
			"min_rank": "D",
			"weapons": ["sniper"],
			"grenades": [],
			"active_items": [1]
		},
		"res://scenes/levels/CastleLevel.tscn": {
			"min_rank": "F",
			"weapons": ["revolver"],
			"grenades": [],
			"active_items": [3]
		}
	}

	var _conditions_met: Dictionary = {}

	func is_level_condition_met(level_path: String) -> bool:
		return _conditions_met.get(level_path, false)

	func set_condition_met(level_path: String, met: bool) -> void:
		_conditions_met[level_path] = met

	func get_weapons_with_conditions() -> Array[String]:
		var result: Array[String] = []
		for level_path in UNLOCK_CONDITIONS:
			for weapon_id in UNLOCK_CONDITIONS[level_path].get("weapons", []):
				if weapon_id not in result:
					result.append(weapon_id)
		return result

	func get_grenades_with_conditions() -> Array[int]:
		return []  # No grenades have conditions in test data

	func get_active_items_with_conditions() -> Array[int]:
		var result: Array[int] = []
		for level_path in UNLOCK_CONDITIONS:
			for item_type in UNLOCK_CONDITIONS[level_path].get("active_items", []):
				if item_type not in result:
					result.append(item_type)
		return result


class MockGameManager:
	var unlocked_weapons: Dictionary = {
		"makarov_pm": true,
		"m16": true,
		"shotgun": false,
		"mini_uzi": false,
		"silenced_pistol": true,
		"sniper": false,
		"revolver": false,
		"ak_gl": true,
		"smg": false
	}

	func is_weapon_unlocked(weapon_id: String) -> bool:
		return unlocked_weapons.get(weapon_id, false)


class MockGrenadeManager:
	var unlocked_grenades: Dictionary = {
		0: true,   # Flashbang
		1: true,   # Frag
		2: true,   # Defensive
		3: true    # Aggression Gas
	}

	var GRENADE_DATA: Dictionary = {
		0: {"name": "Flashbang", "icon_path": ""},
		1: {"name": "Frag Grenade", "icon_path": ""},
		2: {"name": "F-1 Grenade", "icon_path": ""},
		3: {"name": "Aggression Gas", "icon_path": ""}
	}

	func get_grenade_data(grenade_type: int) -> Dictionary:
		return GRENADE_DATA.get(grenade_type, {})


class MockActiveItemManager:
	var unlocked_active_items: Dictionary = {
		0: true,   # NONE
		1: false,  # FLASHLIGHT — condition-gated
		2: true,   # HOMING_BULLETS
		3: false,  # TELEPORT_BRACERS — condition-gated
		4: true,   # BFF_PENDANT
		5: true,   # INVISIBILITY_SUIT
		6: true,   # BREAKER_BULLETS
		7: true,   # FORCE_FIELD
		8: true,   # TRAJECTORY_GLASSES
		9: true    # LASER_SIGHT
	}

	var ACTIVE_ITEM_DATA: Dictionary = {
		0: {"name": "None", "icon_path": ""},
		1: {"name": "Flashlight", "icon_path": ""},
		2: {"name": "Homing Bullets", "icon_path": ""},
		3: {"name": "Teleport Bracers", "icon_path": ""},
		4: {"name": "BFF Pendant", "icon_path": ""},
		5: {"name": "Invisibility", "icon_path": ""},
		6: {"name": "Breaker Bullets", "icon_path": ""},
		7: {"name": "Force Field", "icon_path": ""},
		8: {"name": "Trajectory Glasses", "icon_path": ""},
		9: {"name": "Laser Sight", "icon_path": ""}
	}

	func get_active_item_data(item_type: int) -> Dictionary:
		return ACTIVE_ITEM_DATA.get(item_type, {})


# ============================================================================
# Helper: logic extracted from UnlockTableMenu for unit testing
# ============================================================================


## Simulate _get_weapon_names logic.
func _get_weapon_names(weapon_ids: Array) -> Array[String]:
	var weapon_name_map: Dictionary = {
		"makarov_pm": "PM", "m16": "M16", "shotgun": "Shotgun",
		"mini_uzi": "Mini UZI", "silenced_pistol": "Silenced Pistol",
		"sniper": "ASVK", "revolver": "RSh-12", "ak_gl": "AK + GL"
	}
	var names: Array[String] = []
	for weapon_id in weapon_ids:
		names.append(weapon_name_map.get(weapon_id, weapon_id))
	return names


## Simulate _get_grenade_names logic using mock data.
func _get_grenade_names(grenade_types: Array, grenade_manager: MockGrenadeManager) -> Array[String]:
	var names: Array[String] = []
	for grenade_type in grenade_types:
		var gdata: Dictionary = grenade_manager.get_grenade_data(grenade_type)
		names.append(gdata.get("name", "Grenade %d" % grenade_type))
	return names


## Simulate _get_active_item_names logic using mock data.
func _get_active_item_names(item_types: Array, active_item_manager: MockActiveItemManager) -> Array[String]:
	var names: Array[String] = []
	for item_type in item_types:
		var adata: Dictionary = active_item_manager.get_active_item_data(item_type)
		names.append(adata.get("name", "Item %d" % item_type))
	return names


## Simulate _get_free_items logic using mock data.
func _get_free_items(
		unlock_manager: MockUnlockManager,
		game_manager: MockGameManager,
		grenade_manager: MockGrenadeManager,
		active_item_manager: MockActiveItemManager) -> Array[String]:
	var free_items: Array[String] = []

	var gated_weapons: Array[String] = unlock_manager.get_weapons_with_conditions()
	var gated_grenades: Array[int] = unlock_manager.get_grenades_with_conditions()
	var gated_active_items: Array[int] = unlock_manager.get_active_items_with_conditions()

	var weapon_name_map: Dictionary = {
		"makarov_pm": "PM", "m16": "M16", "shotgun": "Shotgun",
		"mini_uzi": "Mini UZI", "silenced_pistol": "Silenced Pistol",
		"sniper": "ASVK", "revolver": "RSh-12", "ak_gl": "AK + GL"
	}
	for weapon_id in game_manager.unlocked_weapons:
		if game_manager.unlocked_weapons[weapon_id] and weapon_id not in gated_weapons:
			free_items.append(weapon_name_map.get(weapon_id, weapon_id))

	for grenade_type in grenade_manager.unlocked_grenades:
		if grenade_manager.unlocked_grenades[grenade_type] and grenade_type not in gated_grenades:
			var gdata: Dictionary = grenade_manager.get_grenade_data(grenade_type)
			free_items.append(gdata.get("name", "Grenade %d" % grenade_type))

	for item_type in active_item_manager.unlocked_active_items:
		if item_type == 0:
			continue
		if active_item_manager.unlocked_active_items[item_type] and item_type not in gated_active_items:
			var adata: Dictionary = active_item_manager.get_active_item_data(item_type)
			free_items.append(adata.get("name", "Item %d" % item_type))

	return free_items


# ============================================================================
# Tests
# ============================================================================


var unlock_manager: MockUnlockManager
var game_manager: MockGameManager
var grenade_manager: MockGrenadeManager
var active_item_manager: MockActiveItemManager


func before_each() -> void:
	unlock_manager = MockUnlockManager.new()
	game_manager = MockGameManager.new()
	grenade_manager = MockGrenadeManager.new()
	active_item_manager = MockActiveItemManager.new()


func after_each() -> void:
	unlock_manager = null
	game_manager = null
	grenade_manager = null
	active_item_manager = null


# ============================================================================
# Weapon name resolution tests
# ============================================================================


func test_weapon_names_are_resolved_correctly() -> void:
	var names := _get_weapon_names(["mini_uzi", "shotgun", "sniper", "revolver"])
	assert_eq(names.size(), 4, "Should return 4 names")
	assert_true("Mini UZI" in names, "mini_uzi should resolve to 'Mini UZI'")
	assert_true("Shotgun" in names, "shotgun should resolve to 'Shotgun'")
	assert_true("ASVK" in names, "sniper should resolve to 'ASVK'")
	assert_true("RSh-12" in names, "revolver should resolve to 'RSh-12'")


func test_unknown_weapon_id_falls_back_to_id() -> void:
	var names := _get_weapon_names(["unknown_weapon"])
	assert_eq(names.size(), 1)
	assert_eq(names[0], "unknown_weapon", "Unknown weapon ID should be returned as-is")


func test_empty_weapon_list_returns_empty_array() -> void:
	var names := _get_weapon_names([])
	assert_eq(names.size(), 0, "Empty input should return empty array")


# ============================================================================
# Grenade name resolution tests
# ============================================================================


func test_grenade_names_are_resolved_correctly() -> void:
	var names := _get_grenade_names([0, 1, 2, 3], grenade_manager)
	assert_eq(names.size(), 4)
	assert_eq(names[0], "Flashbang")
	assert_eq(names[1], "Frag Grenade")
	assert_eq(names[2], "F-1 Grenade")
	assert_eq(names[3], "Aggression Gas")


func test_unknown_grenade_type_falls_back() -> void:
	var names := _get_grenade_names([99], grenade_manager)
	assert_eq(names.size(), 1)
	assert_eq(names[0], "Grenade 99", "Unknown grenade type should show fallback")


# ============================================================================
# Active item name resolution tests
# ============================================================================


func test_active_item_names_resolved_correctly() -> void:
	var names := _get_active_item_names([1, 3, 8], active_item_manager)
	assert_eq(names.size(), 3)
	assert_eq(names[0], "Flashlight")
	assert_eq(names[1], "Teleport Bracers")
	assert_eq(names[2], "Trajectory Glasses")


func test_unknown_active_item_type_falls_back() -> void:
	var names := _get_active_item_names([99], active_item_manager)
	assert_eq(names.size(), 1)
	assert_eq(names[0], "Item 99")


# ============================================================================
# Unlock conditions table row tests
# ============================================================================


func test_unlock_conditions_cover_expected_levels() -> void:
	# There should be entries for the 4 levels that have unlock conditions
	assert_true("res://scenes/levels/LabyrinthLevel.tscn" in MockUnlockManager.UNLOCK_CONDITIONS,
		"Labyrinth should have unlock condition")
	assert_true("res://scenes/levels/BuildingLevel.tscn" in MockUnlockManager.UNLOCK_CONDITIONS,
		"Building should have unlock condition")
	assert_true("res://scenes/levels/TestTier.tscn" in MockUnlockManager.UNLOCK_CONDITIONS,
		"Polygon should have unlock condition")
	assert_true("res://scenes/levels/CastleLevel.tscn" in MockUnlockManager.UNLOCK_CONDITIONS,
		"Castle should have unlock condition")


func test_each_condition_has_required_fields() -> void:
	for level_path in MockUnlockManager.UNLOCK_CONDITIONS:
		var condition: Dictionary = MockUnlockManager.UNLOCK_CONDITIONS[level_path]
		assert_true(condition.has("min_rank"),
			"Condition for %s should have min_rank" % level_path)
		assert_true(condition.has("weapons"),
			"Condition for %s should have weapons array" % level_path)
		assert_true(condition.has("grenades"),
			"Condition for %s should have grenades array" % level_path)
		assert_true(condition.has("active_items"),
			"Condition for %s should have active_items array" % level_path)


func test_labyrinth_unlocks_mini_uzi_at_rank_d() -> void:
	var condition: Dictionary = MockUnlockManager.UNLOCK_CONDITIONS["res://scenes/levels/LabyrinthLevel.tscn"]
	assert_eq(condition["min_rank"], "D")
	assert_true("mini_uzi" in condition["weapons"], "Labyrinth should unlock mini_uzi")


func test_building_unlocks_shotgun_at_rank_d() -> void:
	var condition: Dictionary = MockUnlockManager.UNLOCK_CONDITIONS["res://scenes/levels/BuildingLevel.tscn"]
	assert_eq(condition["min_rank"], "D")
	assert_true("shotgun" in condition["weapons"], "Building should unlock shotgun")


func test_polygon_unlocks_sniper_and_flashlight() -> void:
	var condition: Dictionary = MockUnlockManager.UNLOCK_CONDITIONS["res://scenes/levels/TestTier.tscn"]
	assert_eq(condition["min_rank"], "D")
	assert_true("sniper" in condition["weapons"], "Polygon should unlock sniper")
	assert_true(1 in condition["active_items"], "Polygon should unlock Flashlight (type 1)")


func test_castle_unlocks_revolver_and_teleport_bracers_at_any_rank() -> void:
	var condition: Dictionary = MockUnlockManager.UNLOCK_CONDITIONS["res://scenes/levels/CastleLevel.tscn"]
	assert_eq(condition["min_rank"], "F",
		"Castle should unlock revolver at any rank (F = any completion)")
	assert_true("revolver" in condition["weapons"], "Castle should unlock revolver")
	assert_true(3 in condition["active_items"], "Castle should unlock Teleport Bracers (type 3)")


# ============================================================================
# Condition-met status tests
# ============================================================================


func test_condition_not_met_by_default() -> void:
	assert_false(unlock_manager.is_level_condition_met("res://scenes/levels/LabyrinthLevel.tscn"),
		"Labyrinth condition should not be met by default")
	assert_false(unlock_manager.is_level_condition_met("res://scenes/levels/CastleLevel.tscn"),
		"Castle condition should not be met by default")


func test_condition_met_after_setting() -> void:
	unlock_manager.set_condition_met("res://scenes/levels/LabyrinthLevel.tscn", true)
	assert_true(unlock_manager.is_level_condition_met("res://scenes/levels/LabyrinthLevel.tscn"),
		"Labyrinth condition should be met after setting it")


func test_condition_for_unknown_level_is_not_met() -> void:
	assert_false(unlock_manager.is_level_condition_met("res://scenes/levels/UnknownLevel.tscn"),
		"Unknown level condition should not be met")


# ============================================================================
# Free items (undistributed) tests
# ============================================================================


func test_free_weapons_exclude_condition_gated_ones() -> void:
	var free := _get_free_items(unlock_manager, game_manager, grenade_manager, active_item_manager)
	# mini_uzi, shotgun, sniper, revolver are gated — should NOT appear in free items
	assert_false("Mini UZI" in free, "Mini UZI is condition-gated, should not be in free items")
	assert_false("Shotgun" in free, "Shotgun is condition-gated, should not be in free items")
	assert_false("ASVK" in free, "ASVK is condition-gated, should not be in free items")
	assert_false("RSh-12" in free, "RSh-12 is condition-gated, should not be in free items")


func test_free_weapons_include_unlocked_non_gated_ones() -> void:
	var free := _get_free_items(unlock_manager, game_manager, grenade_manager, active_item_manager)
	# PM, M16, Silenced Pistol, AK+GL are freely available
	assert_true("PM" in free, "PM should be in free items")
	assert_true("M16" in free, "M16 should be in free items")
	assert_true("Silenced Pistol" in free, "Silenced Pistol should be in free items")
	assert_true("AK + GL" in free, "AK + GL should be in free items")


func test_all_grenades_are_free() -> void:
	var free := _get_free_items(unlock_manager, game_manager, grenade_manager, active_item_manager)
	# All grenades are freely available (no conditions in mock data)
	assert_true("Flashbang" in free, "Flashbang should be in free items")
	assert_true("Frag Grenade" in free, "Frag Grenade should be in free items")
	assert_true("F-1 Grenade" in free, "F-1 Grenade should be in free items")
	assert_true("Aggression Gas" in free, "Aggression Gas should be in free items")


func test_free_active_items_exclude_condition_gated_ones() -> void:
	var free := _get_free_items(unlock_manager, game_manager, grenade_manager, active_item_manager)
	# Flashlight (1) and Teleport Bracers (3) are condition-gated
	assert_false("Flashlight" in free, "Flashlight is condition-gated, should not be in free items")
	assert_false("Teleport Bracers" in free, "Teleport Bracers is condition-gated, should not be in free items")


func test_free_active_items_include_non_gated_ones() -> void:
	var free := _get_free_items(unlock_manager, game_manager, grenade_manager, active_item_manager)
	assert_true("Homing Bullets" in free, "Homing Bullets should be in free items")
	assert_true("BFF Pendant" in free, "BFF Pendant should be in free items")
	assert_true("Invisibility" in free, "Invisibility should be in free items")
	assert_true("Breaker Bullets" in free, "Breaker Bullets should be in free items")
	assert_true("Force Field" in free, "Force Field should be in free items")
	assert_true("Trajectory Glasses" in free, "Trajectory Glasses should be in free items")
	assert_true("Laser Sight" in free, "Laser Sight should be in free items")


func test_none_active_item_is_excluded_from_free_items() -> void:
	var free := _get_free_items(unlock_manager, game_manager, grenade_manager, active_item_manager)
	assert_false("None" in free, "NONE active item should not appear in free items list")


# ============================================================================
# Weapons-with-conditions helper tests
# ============================================================================


func test_get_weapons_with_conditions_returns_all_gated_weapons() -> void:
	var gated := unlock_manager.get_weapons_with_conditions()
	assert_true("mini_uzi" in gated, "mini_uzi should be in gated weapons")
	assert_true("shotgun" in gated, "shotgun should be in gated weapons")
	assert_true("sniper" in gated, "sniper should be in gated weapons")
	assert_true("revolver" in gated, "revolver should be in gated weapons")


func test_get_weapons_with_conditions_has_no_duplicates() -> void:
	var gated := unlock_manager.get_weapons_with_conditions()
	# All items should be unique
	var seen: Array[String] = []
	for weapon_id in gated:
		assert_false(weapon_id in seen, "No duplicate in get_weapons_with_conditions: %s" % weapon_id)
		seen.append(weapon_id)


func test_get_active_items_with_conditions_returns_gated_items() -> void:
	var gated := unlock_manager.get_active_items_with_conditions()
	assert_true(1 in gated, "Flashlight (1) should be in gated active items")
	assert_true(3 in gated, "Teleport Bracers (3) should be in gated active items")


func test_get_grenades_with_conditions_returns_empty() -> void:
	var gated := unlock_manager.get_grenades_with_conditions()
	assert_eq(gated.size(), 0, "No grenades should have unlock conditions in current data")


# ============================================================================
# Level name display tests
# ============================================================================


func test_level_names_are_defined_for_all_conditioned_levels() -> void:
	# These level paths are the ones in UNLOCK_CONDITIONS — all should have display names
	const LEVEL_NAMES: Dictionary = {
		"res://scenes/levels/LabyrinthLevel.tscn": "Labyrinth",
		"res://scenes/levels/BuildingLevel.tscn": "Building",
		"res://scenes/levels/TestTier.tscn": "Polygon",
		"res://scenes/levels/CastleLevel.tscn": "Castle",
	}
	for level_path in MockUnlockManager.UNLOCK_CONDITIONS:
		assert_true(level_path in LEVEL_NAMES,
			"Level path %s should have a display name" % level_path)


func test_level_name_map_resolves_correctly() -> void:
	const LEVEL_NAMES: Dictionary = {
		"res://scenes/levels/LabyrinthLevel.tscn": "Labyrinth",
		"res://scenes/levels/BuildingLevel.tscn": "Building",
		"res://scenes/levels/TestTier.tscn": "Polygon",
		"res://scenes/levels/CastleLevel.tscn": "Castle",
	}
	assert_eq(LEVEL_NAMES.get("res://scenes/levels/LabyrinthLevel.tscn", ""), "Labyrinth")
	assert_eq(LEVEL_NAMES.get("res://scenes/levels/TestTier.tscn", ""), "Polygon")
	assert_eq(LEVEL_NAMES.get("res://scenes/levels/CastleLevel.tscn", ""), "Castle")
