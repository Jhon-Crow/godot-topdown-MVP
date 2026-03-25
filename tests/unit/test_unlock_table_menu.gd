extends GutTest
## Unit tests for UnlockTableMenu.
##
## Tests the LEVEL_NAMES, WEAPON_NAMES, ACTIVE_ITEM_NAMES, and GRENADE_NAMES
## dictionaries, as well as rank color mapping using a mock class.


# ============================================================================
# Mock UnlockTableMenu for Testing
# ============================================================================


class MockUnlockTableMenu:
	## Level name mapping (scene path -> display name).
	const LEVEL_NAMES: Dictionary = {
		"res://scenes/levels/LabyrinthLevel.tscn": "Labyrinth",
		"res://scenes/levels/BuildingLevel.tscn": "Building",
		"res://scenes/levels/TestTier.tscn": "Polygon",
		"res://scenes/levels/CastleLevel.tscn": "Castle",
		"res://scenes/levels/RevolverLevel.tscn": "Double Corridor",
		"res://scenes/levels/BeachLevel.tscn": "Beach",
		"res://scenes/levels/DocksLevel.tscn": "Docks",
		"res://scenes/levels/CityLevel.tscn": "City",
		"res://scenes/levels/DecadenceLevel.tscn": "Decadence",
	}

	## Weapon ID to display name mapping.
	const WEAPON_NAMES: Dictionary = {
		"makarov_pm": "PM",
		"m16": "M16",
		"shotgun": "Shotgun",
		"mini_uzi": "Mini UZI",
		"silenced_pistol": "Silenced Pistol",
		"sniper": "ASVK",
		"revolver": "RSh-12",
		"ak_gl": "AK + GL",
	}

	## Active item type to display name mapping.
	const ACTIVE_ITEM_NAMES: Dictionary = {
		0: "None",
		1: "Flashlight",
		2: "Homing Bullets",
		3: "Teleport Bracers",
		4: "BFF Pendant",
		5: "Invisibility Suit",
		6: "Breaker Bullets",
		7: "Force Field",
		8: "Trajectory Glasses",
		9: "Laser Sight",
		10: "Extended Magazine",
		11: "Loudspeaker",
		12: "Breaching Charges",
		13: "Armored Skin",
		14: "Auto-Reload",
		15: "Drilling Bullets",
		16: "Recoil Compensator",
		17: "Combat Disposition",
		18: "Experimental Sample",
		19: "Fine Motor Skills",
	}

	## Grenade type to display name mapping.
	const GRENADE_NAMES: Dictionary = {
		0: "Flashbang",
		1: "Frag Grenade",
		2: "F-1 Grenade",
		3: "Aggression Gas",
	}

	## Get color for a rank display.
	func get_rank_color(rank: String) -> Color:
		match rank:
			"S":
				return Color(1.0, 0.85, 0.0, 1.0)
			"A+":
				return Color(0.3, 1.0, 0.3, 1.0)
			"A":
				return Color(0.4, 0.9, 0.4, 1.0)
			"B":
				return Color(0.5, 0.8, 1.0, 1.0)
			"C":
				return Color(0.8, 0.8, 0.8, 1.0)
			"D":
				return Color(0.8, 0.5, 0.3, 1.0)
			"F":
				return Color(0.8, 0.3, 0.3, 1.0)
			"Any":
				return Color(0.5, 0.8, 0.5, 1.0)
			_:
				return Color(0.7, 0.7, 0.7, 1.0)

	## Extract level name from scene path.
	func extract_level_name(path: String) -> String:
		var filename: String = path.get_file().get_basename()
		return filename.replace("Level", "").replace("_", " ")


var menu: MockUnlockTableMenu


func before_each() -> void:
	menu = MockUnlockTableMenu.new()


func after_each() -> void:
	menu = null


# ============================================================================
# LEVEL_NAMES Tests
# ============================================================================


func test_level_names_count() -> void:
	assert_eq(menu.LEVEL_NAMES.size(), 9,
		"LEVEL_NAMES should have 9 entries")


func test_level_names_all_valid_paths() -> void:
	for path in menu.LEVEL_NAMES:
		assert_true(path.begins_with("res://"),
			"Path '%s' should start with res://" % path)
		assert_true(path.ends_with(".tscn"),
			"Path '%s' should end with .tscn" % path)


func test_level_names_contains_decadence() -> void:
	assert_eq(menu.LEVEL_NAMES["res://scenes/levels/DecadenceLevel.tscn"], "Decadence",
		"Decadence level display name should be Decadence (Issue #1423)")


# ============================================================================
# WEAPON_NAMES Tests
# ============================================================================


func test_weapon_names_count() -> void:
	assert_eq(menu.WEAPON_NAMES.size(), 8,
		"WEAPON_NAMES should have 8 entries")


func test_weapon_names_contains_pm() -> void:
	assert_eq(menu.WEAPON_NAMES["makarov_pm"], "PM",
		"makarov_pm display name should be PM")


func test_weapon_names_contains_asvk() -> void:
	assert_eq(menu.WEAPON_NAMES["sniper"], "ASVK",
		"sniper display name should be ASVK")


func test_weapon_names_contains_ak_gl() -> void:
	assert_eq(menu.WEAPON_NAMES["ak_gl"], "AK + GL",
		"ak_gl display name should be AK + GL")


# ============================================================================
# ACTIVE_ITEM_NAMES Tests
# ============================================================================


func test_active_item_names_count() -> void:
	assert_eq(menu.ACTIVE_ITEM_NAMES.size(), 20,
		"ACTIVE_ITEM_NAMES should have 20 entries (0-19)")


func test_active_item_none_is_zero() -> void:
	assert_eq(menu.ACTIVE_ITEM_NAMES[0], "None",
		"Item 0 should be None")


func test_active_item_flashlight() -> void:
	assert_eq(menu.ACTIVE_ITEM_NAMES[1], "Flashlight",
		"Item 1 should be Flashlight")


func test_active_item_last_entry() -> void:
	assert_eq(menu.ACTIVE_ITEM_NAMES[19], "Fine Motor Skills",
		"Item 19 should be Fine Motor Skills")


func test_active_item_names_sequential_keys() -> void:
	for i in range(20):
		assert_true(menu.ACTIVE_ITEM_NAMES.has(i),
			"Should have active item with key %d" % i)


# ============================================================================
# GRENADE_NAMES Tests
# ============================================================================


func test_grenade_names_count() -> void:
	assert_eq(menu.GRENADE_NAMES.size(), 4,
		"GRENADE_NAMES should have 4 entries")


func test_grenade_names_flashbang() -> void:
	assert_eq(menu.GRENADE_NAMES[0], "Flashbang",
		"Grenade 0 should be Flashbang")


func test_grenade_names_aggression_gas() -> void:
	assert_eq(menu.GRENADE_NAMES[3], "Aggression Gas",
		"Grenade 3 should be Aggression Gas")


# ============================================================================
# Rank Color Tests
# ============================================================================


func test_rank_s_is_gold() -> void:
	var color := menu.get_rank_color("S")
	assert_eq(color, Color(1.0, 0.85, 0.0, 1.0),
		"Rank S should be gold")


func test_rank_a_is_green() -> void:
	var color := menu.get_rank_color("A")
	assert_eq(color, Color(0.4, 0.9, 0.4, 1.0),
		"Rank A should be green")


func test_rank_f_is_red() -> void:
	var color := menu.get_rank_color("F")
	assert_eq(color, Color(0.8, 0.3, 0.3, 1.0),
		"Rank F should be red")


func test_rank_unknown_is_gray() -> void:
	var color := menu.get_rank_color("Z")
	assert_eq(color, Color(0.7, 0.7, 0.7, 1.0),
		"Unknown rank should be gray")


func test_rank_any_is_light_green() -> void:
	var color := menu.get_rank_color("Any")
	assert_eq(color, Color(0.5, 0.8, 0.5, 1.0),
		"Rank Any should be light green")
