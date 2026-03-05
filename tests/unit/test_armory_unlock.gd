extends GutTest
## Unit tests for armory unlock functionality.
##
## Tests the item unlock system where items are locked by default
## (except PM and flashbang) and can be unlocked via LMB hold.


# ============================================================================
# Mock Managers for Testing
# ============================================================================


class MockGameManager:
	var unlocked_weapons: Dictionary = {
		"makarov_pm": true,
		"m16": false,
		"shotgun": false,
		"mini_uzi": false,
		"silenced_pistol": false,
		"sniper": false,
		"revolver": false,
		"ak_gl": false,
		"smg": false
	}

	var unlock_signals: Array = []

	func is_weapon_unlocked(weapon_id: String) -> bool:
		return unlocked_weapons.get(weapon_id, false)

	func unlock_weapon(weapon_id: String) -> void:
		if weapon_id in unlocked_weapons:
			if not unlocked_weapons[weapon_id]:
				unlocked_weapons[weapon_id] = true
				unlock_signals.append(weapon_id)

	func get_unlocked_weapons() -> Dictionary:
		return unlocked_weapons


class MockGrenadeManager:
	enum GrenadeType {
		FLASHBANG,
		FRAG,
		DEFENSIVE,
		AGGRESSION_GAS
	}

	var unlocked_grenades: Dictionary = {
		GrenadeType.FLASHBANG: true,
		GrenadeType.FRAG: false,
		GrenadeType.DEFENSIVE: false,
		GrenadeType.AGGRESSION_GAS: false
	}

	var unlock_signals: Array = []

	func is_grenade_unlocked(grenade_type: int) -> bool:
		return unlocked_grenades.get(grenade_type, false)

	func unlock_grenade(grenade_type: int) -> void:
		if grenade_type in unlocked_grenades:
			if not unlocked_grenades[grenade_type]:
				unlocked_grenades[grenade_type] = true
				unlock_signals.append(grenade_type)

	func get_unlocked_grenades() -> Dictionary:
		return unlocked_grenades


class MockActiveItemManager:
	enum ActiveItemType {
		NONE,
		FLASHLIGHT,
		HOMING_BULLETS,
		TELEPORT_BRACERS,
		INVISIBILITY_SUIT,
		BREAKER_BULLETS,
		FORCE_FIELD,
		TRAJECTORY_GLASSES  # Issue #744
	}

	var unlocked_active_items: Dictionary = {
		ActiveItemType.NONE: true,
		ActiveItemType.FLASHLIGHT: false,
		ActiveItemType.HOMING_BULLETS: false,
		ActiveItemType.TELEPORT_BRACERS: false,
		ActiveItemType.INVISIBILITY_SUIT: false,
		ActiveItemType.BREAKER_BULLETS: false,
		ActiveItemType.FORCE_FIELD: false,
		ActiveItemType.TRAJECTORY_GLASSES: false  # Issue #744
	}

	var unlock_signals: Array = []

	func is_active_item_unlocked(item_type: int) -> bool:
		return unlocked_active_items.get(item_type, false)

	func unlock_active_item(item_type: int) -> void:
		if item_type in unlocked_active_items:
			if not unlocked_active_items[item_type]:
				unlocked_active_items[item_type] = true
				unlock_signals.append(item_type)

	func get_unlocked_active_items() -> Dictionary:
		return unlocked_active_items


var game_manager: MockGameManager
var grenade_manager: MockGrenadeManager
var active_item_manager: MockActiveItemManager


func before_each() -> void:
	game_manager = MockGameManager.new()
	grenade_manager = MockGrenadeManager.new()
	active_item_manager = MockActiveItemManager.new()


func after_each() -> void:
	game_manager = null
	grenade_manager = null
	active_item_manager = null


# ============================================================================
# GameManager Weapon Unlock Tests
# ============================================================================


func test_default_weapon_unlock_state() -> void:
	# Only PM should be unlocked by default
	assert_true(game_manager.is_weapon_unlocked("makarov_pm"),
		"PM should be unlocked by default")
	assert_false(game_manager.is_weapon_unlocked("m16"),
		"M16 should be locked by default")
	assert_false(game_manager.is_weapon_unlocked("shotgun"),
		"Shotgun should be locked by default")
	assert_false(game_manager.is_weapon_unlocked("sniper"),
		"Sniper should be locked by default")


func test_unlock_weapon() -> void:
	# M16 should start locked
	assert_false(game_manager.is_weapon_unlocked("m16"),
		"M16 should be locked before unlock")

	# Unlock M16
	game_manager.unlock_weapon("m16")

	# M16 should now be unlocked
	assert_true(game_manager.is_weapon_unlocked("m16"),
		"M16 should be unlocked after unlock")

	# Unlock signal should be emitted
	assert_eq(game_manager.unlock_signals.size(), 1,
		"One unlock signal should be emitted")
	assert_eq(game_manager.unlock_signals[0], "m16",
		"Unlock signal should be for M16")


func test_unlock_already_unlocked_weapon() -> void:
	# PM is already unlocked
	game_manager.unlock_weapon("makarov_pm")

	# Should not emit duplicate signal
	assert_eq(game_manager.unlock_signals.size(), 0,
		"Should not emit signal for already unlocked weapon")


func test_unlock_multiple_weapons() -> void:
	game_manager.unlock_weapon("m16")
	game_manager.unlock_weapon("shotgun")
	game_manager.unlock_weapon("sniper")

	assert_true(game_manager.is_weapon_unlocked("m16"), "M16 should be unlocked")
	assert_true(game_manager.is_weapon_unlocked("shotgun"), "Shotgun should be unlocked")
	assert_true(game_manager.is_weapon_unlocked("sniper"), "Sniper should be unlocked")
	assert_eq(game_manager.unlock_signals.size(), 3,
		"Three unlock signals should be emitted")


# ============================================================================
# GrenadeManager Unlock Tests
# ============================================================================


func test_default_grenade_unlock_state() -> void:
	# Only Flashbang should be unlocked by default
	assert_true(grenade_manager.is_grenade_unlocked(0),
		"Flashbang should be unlocked by default")
	assert_false(grenade_manager.is_grenade_unlocked(1),
		"Frag should be locked by default")
	assert_false(grenade_manager.is_grenade_unlocked(2),
		"Defensive should be locked by default")
	assert_false(grenade_manager.is_grenade_unlocked(3),
		"Aggression Gas should be locked by default")


func test_unlock_grenade() -> void:
	# Frag should start locked
	assert_false(grenade_manager.is_grenade_unlocked(1),
		"Frag should be locked before unlock")

	# Unlock Frag
	grenade_manager.unlock_grenade(1)

	# Frag should now be unlocked
	assert_true(grenade_manager.is_grenade_unlocked(1),
		"Frag should be unlocked after unlock")

	# Unlock signal should be emitted
	assert_eq(grenade_manager.unlock_signals.size(), 1,
		"One unlock signal should be emitted")


func test_unlock_already_unlocked_grenade() -> void:
	# Flashbang is already unlocked
	grenade_manager.unlock_grenade(0)

	# Should not emit duplicate signal
	assert_eq(grenade_manager.unlock_signals.size(), 0,
		"Should not emit signal for already unlocked grenade")


func test_unlock_multiple_grenades() -> void:
	grenade_manager.unlock_grenade(1)
	grenade_manager.unlock_grenade(2)

	assert_true(grenade_manager.is_grenade_unlocked(1), "Frag should be unlocked")
	assert_true(grenade_manager.is_grenade_unlocked(2), "Defensive should be unlocked")
	assert_eq(grenade_manager.unlock_signals.size(), 2,
		"Two unlock signals should be emitted")


# ============================================================================
# ActiveItemManager Unlock Tests
# ============================================================================


func test_default_active_item_unlock_state() -> void:
	# Only NONE should be unlocked by default
	assert_true(active_item_manager.is_active_item_unlocked(0),
		"NONE should be unlocked by default")
	assert_false(active_item_manager.is_active_item_unlocked(1),
		"Flashlight should be locked by default")
	assert_false(active_item_manager.is_active_item_unlocked(2),
		"Homing Bullets should be locked by default")
	assert_false(active_item_manager.is_active_item_unlocked(3),
		"Teleport Bracers should be locked by default")


func test_unlock_active_item() -> void:
	# Flashlight should start locked
	assert_false(active_item_manager.is_active_item_unlocked(1),
		"Flashlight should be locked before unlock")

	# Unlock Flashlight
	active_item_manager.unlock_active_item(1)

	# Flashlight should now be unlocked
	assert_true(active_item_manager.is_active_item_unlocked(1),
		"Flashlight should be unlocked after unlock")

	# Unlock signal should be emitted
	assert_eq(active_item_manager.unlock_signals.size(), 1,
		"One unlock signal should be emitted")


func test_unlock_already_unlocked_active_item() -> void:
	# NONE is already unlocked
	active_item_manager.unlock_active_item(0)

	# Should not emit duplicate signal
	assert_eq(active_item_manager.unlock_signals.size(), 0,
		"Should not emit signal for already unlocked active item")


func test_unlock_multiple_active_items() -> void:
	active_item_manager.unlock_active_item(1)
	active_item_manager.unlock_active_item(2)
	active_item_manager.unlock_active_item(3)

	assert_true(active_item_manager.is_active_item_unlocked(1), "Flashlight should be unlocked")
	assert_true(active_item_manager.is_active_item_unlocked(2), "Homing Bullets should be unlocked")
	assert_true(active_item_manager.is_active_item_unlocked(3), "Teleport Bracers should be unlocked")
	assert_eq(active_item_manager.unlock_signals.size(), 3,
		"Three unlock signals should be emitted")


# ============================================================================
# Integration Tests
# ============================================================================


func test_unlock_state_persists() -> void:
	# Unlock items
	game_manager.unlock_weapon("m16")
	grenade_manager.unlock_grenade(1)
	active_item_manager.unlock_active_item(1)

	# Verify state persists (within session)
	assert_true(game_manager.is_weapon_unlocked("m16"),
		"Weapon unlock should persist")
	assert_true(grenade_manager.is_grenade_unlocked(1),
		"Grenade unlock should persist")
	assert_true(active_item_manager.is_active_item_unlocked(1),
		"Active item unlock should persist")


func test_get_unlocked_weapons() -> void:
	var unlocked := game_manager.get_unlocked_weapons()

	assert_true(unlocked.has("makarov_pm"), "Should have PM in unlocked weapons")
	assert_true(unlocked["makarov_pm"], "PM should be unlocked")
	assert_false(unlocked["m16"], "M16 should be locked")


func test_get_unlocked_grenades() -> void:
	var unlocked := grenade_manager.get_unlocked_grenades()

	assert_true(unlocked.has(0), "Should have Flashbang in unlocked grenades")
	assert_true(unlocked[0], "Flashbang should be unlocked")
	assert_false(unlocked[1], "Frag should be locked")


func test_get_unlocked_active_items() -> void:
	var unlocked := active_item_manager.get_unlocked_active_items()

	assert_true(unlocked.has(0), "Should have NONE in unlocked active items")
	assert_true(unlocked[0], "NONE should be unlocked")
	assert_false(unlocked[1], "Flashlight should be locked")
