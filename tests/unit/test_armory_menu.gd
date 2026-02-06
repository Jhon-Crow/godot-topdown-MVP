extends GutTest
## Unit tests for ArmoryMenu.
##
## Tests the weapon/grenade selection menu logic.
## The armory menu separates firearms and grenades into distinct categories
## and shows a loadout panel with detailed weapon stats.


# ============================================================================
# Mock ArmoryMenu for Testing
# ============================================================================


class MockArmoryMenu:
	## Dictionary of firearms (non-grenade weapons).
	const FIREARMS: Dictionary = {
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
		},
		"smg": {
			"name": "???",
			"icon_path": "",
			"unlocked": false,
			"description": "Coming soon"
		},
		"pistol": {
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

	## Currently selected weapon ID.
	var selected_weapon: String = "m16"

	## Currently selected grenade type.
	var selected_grenade_type: int = 0

	## Signal tracking.
	var back_pressed_emitted: int = 0
	var weapon_selected_emitted: Array = []
	var grenade_selected_emitted: Array = []

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

	## Check if weapon is unlocked.
	func is_weapon_unlocked(weapon_id: String) -> bool:
		if not weapon_id in FIREARMS:
			return false
		return FIREARMS[weapon_id]["unlocked"]

	## Select a weapon (firearm only).
	func select_weapon(weapon_id: String) -> bool:
		if not is_weapon_unlocked(weapon_id):
			return false

		if weapon_id == selected_weapon:
			return false  # Already selected

		selected_weapon = weapon_id
		weapon_selected_emitted.append(weapon_id)
		return true

	## Select a grenade by type.
	func select_grenade(grenade_type: int) -> bool:
		if grenade_type not in GRENADES:
			return false

		if grenade_type == selected_grenade_type:
			return false  # Already selected

		selected_grenade_type = grenade_type
		grenade_selected_emitted.append(grenade_type)
		return true

	## Handle back button press.
	func press_back() -> void:
		back_pressed_emitted += 1


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

	# M16, Shotgun, Mini UZI, Silenced Pistol, ASVK (5 unlocked)
	assert_eq(count, 5,
		"Should count correct number of unlocked firearms")


func test_count_total_firearms() -> void:
	var count := menu.count_total_firearms()

	assert_eq(count, 8,
		"Should count total firearms correctly (5 unlocked + 3 locked)")


func test_count_total_grenades() -> void:
	var count := menu.count_total_grenades()

	assert_eq(count, 3,
		"Should count total grenades correctly (flashbang, frag, defensive)")


# ============================================================================
# Weapon Selection Tests
# ============================================================================


func test_select_weapon_success() -> void:
	var result := menu.select_weapon("shotgun")

	assert_true(result,
		"Should successfully select unlocked weapon")
	assert_eq(menu.selected_weapon, "shotgun",
		"Selected weapon should be updated")


func test_select_weapon_emits_signal() -> void:
	menu.select_weapon("shotgun")

	assert_eq(menu.weapon_selected_emitted.size(), 1,
		"Should emit weapon_selected signal")
	assert_eq(menu.weapon_selected_emitted[0], "shotgun",
		"Signal should contain weapon ID")


func test_select_same_weapon_no_signal() -> void:
	menu.selected_weapon = "m16"
	var result := menu.select_weapon("m16")

	assert_false(result,
		"Should return false for same weapon")
	assert_eq(menu.weapon_selected_emitted.size(), 0,
		"Should not emit signal for same weapon")


func test_select_locked_weapon() -> void:
	var result := menu.select_weapon("ak47")

	assert_false(result,
		"Should not select locked weapon")
	assert_eq(menu.selected_weapon, "m16",
		"Selected weapon should remain unchanged")


# ============================================================================
# Grenade Selection Tests
# ============================================================================


func test_select_grenade_success() -> void:
	menu.selected_grenade_type = 0  # Flashbang
	var result := menu.select_grenade(1)  # Frag

	assert_true(result,
		"Should successfully select different grenade")
	assert_eq(menu.selected_grenade_type, 1,
		"Selected grenade type should be updated")


func test_select_grenade_emits_signal() -> void:
	menu.selected_grenade_type = 0
	menu.select_grenade(1)

	assert_eq(menu.grenade_selected_emitted.size(), 1,
		"Should emit grenade selection signal")
	assert_eq(menu.grenade_selected_emitted[0], 1,
		"Signal should contain grenade type")


func test_select_same_grenade_no_signal() -> void:
	menu.selected_grenade_type = 0
	var result := menu.select_grenade(0)

	assert_false(result,
		"Should return false for same grenade")
	assert_eq(menu.grenade_selected_emitted.size(), 0,
		"Should not emit signal for same grenade")


func test_select_defensive_grenade() -> void:
	menu.selected_grenade_type = 0
	var result := menu.select_grenade(2)  # Defensive

	assert_true(result,
		"Should successfully select defensive grenade")
	assert_eq(menu.selected_grenade_type, 2,
		"Should select defensive grenade type")


func test_select_invalid_grenade_type() -> void:
	var result := menu.select_grenade(99)

	assert_false(result,
		"Should not select invalid grenade type")
	assert_eq(menu.selected_grenade_type, 0,
		"Grenade type should remain unchanged")


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


func test_switch_weapons() -> void:
	menu.select_weapon("shotgun")
	menu.select_weapon("m16")

	assert_eq(menu.selected_weapon, "m16",
		"Should switch back to m16")
	assert_eq(menu.weapon_selected_emitted.size(), 2,
		"Should emit signal for each switch")


func test_switch_grenades() -> void:
	menu.selected_grenade_type = 0
	menu.select_grenade(1)
	menu.select_grenade(0)

	assert_eq(menu.selected_grenade_type, 0,
		"Should switch back to flashbang")
	assert_eq(menu.grenade_selected_emitted.size(), 2,
		"Should emit signal for each switch")


func test_select_weapon_and_grenade() -> void:
	menu.select_weapon("shotgun")
	menu.select_grenade(1)

	assert_eq(menu.selected_weapon, "shotgun",
		"Weapon should be updated")
	assert_eq(menu.selected_grenade_type, 1,
		"Grenade should be updated")


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
	var lower := menu.is_weapon_unlocked("m16")
	var upper := menu.is_weapon_unlocked("M16")

	assert_true(lower,
		"Lowercase should work")
	assert_false(upper,
		"Uppercase should not work (case sensitive)")


func test_all_unlocked_weapons_selectable() -> void:
	var unlocked_weapons := ["m16", "shotgun", "mini_uzi", "silenced_pistol", "sniper"]

	for weapon_id in unlocked_weapons:
		menu.selected_weapon = ""  # Reset
		var result := menu.select_weapon(weapon_id)
		assert_true(result,
			"Should be able to select %s" % weapon_id)


func test_all_grenades_selectable() -> void:
	for grenade_type in [0, 1, 2]:
		# Start with a different grenade selected
		menu.selected_grenade_type = (grenade_type + 1) % 3
		var result := menu.select_grenade(grenade_type)
		assert_true(result,
			"Should be able to select grenade type %d" % grenade_type)


func test_cycle_all_weapons() -> void:
	var weapons := ["shotgun", "mini_uzi", "silenced_pistol", "sniper", "m16"]
	for weapon_id in weapons:
		menu.select_weapon(weapon_id)
	assert_eq(menu.selected_weapon, "m16",
		"Should end on M16 after cycling all weapons")
	assert_eq(menu.weapon_selected_emitted.size(), 5,
		"Should emit signal for each selection")
