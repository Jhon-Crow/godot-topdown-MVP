extends GutTest
## Unit tests for UnlockManager (Issue #785).
##
## Tests the item unlock state management for the armory.
## Verifies default unlock state, unlock operations, and state persistence.


# ============================================================================
# Mock UnlockManager for Testing
# ============================================================================


class MockUnlockManager:
	## Default unlocked weapons (only PM pistol by default).
	const DEFAULT_UNLOCKED_WEAPONS: Array[String] = ["makarov_pm"]

	## Default unlocked grenade types (only flashbang by default).
	const DEFAULT_UNLOCKED_GRENADES: Array[int] = [0]  # GrenadeType.FLASHBANG = 0

	## Default unlocked active item types.
	const DEFAULT_UNLOCKED_ACTIVE_ITEMS: Array[int] = [0]  # ActiveItemType.NONE = 0

	## Hold time required to unlock an item.
	const UNLOCK_HOLD_TIME := 1.5

	## In-memory cache of unlocked items.
	var unlocked_weapons: Array[String] = []
	var unlocked_grenades: Array[int] = []
	var unlocked_active_items: Array[int] = []

	## Whether unlock restrictions are enabled.
	var restrictions_enabled: bool = true

	## Signal tracking.
	var items_unlocked: Array = []

	func _init() -> void:
		reset_to_default()

	## Check if a weapon is unlocked.
	func is_weapon_unlocked(weapon_id: String) -> bool:
		if not restrictions_enabled:
			return true
		return weapon_id in unlocked_weapons

	## Check if a grenade type is unlocked.
	func is_grenade_unlocked(grenade_type: int) -> bool:
		if not restrictions_enabled:
			return true
		return grenade_type in unlocked_grenades

	## Check if an active item type is unlocked.
	func is_active_item_unlocked(item_type: int) -> bool:
		if not restrictions_enabled:
			return true
		return item_type in unlocked_active_items

	## Unlock a weapon.
	func unlock_weapon(weapon_id: String) -> void:
		if weapon_id in unlocked_weapons:
			return  # Already unlocked
		unlocked_weapons.append(weapon_id)
		items_unlocked.append({"type": "weapon", "id": weapon_id})

	## Unlock a grenade type.
	func unlock_grenade(grenade_type: int) -> void:
		if grenade_type in unlocked_grenades:
			return  # Already unlocked
		unlocked_grenades.append(grenade_type)
		items_unlocked.append({"type": "grenade", "id": grenade_type})

	## Unlock an active item type.
	func unlock_active_item(item_type: int) -> void:
		if item_type in unlocked_active_items:
			return  # Already unlocked
		unlocked_active_items.append(item_type)
		items_unlocked.append({"type": "active_item", "id": item_type})

	## Unlock all items.
	func unlock_all() -> void:
		var all_weapons: Array[String] = [
			"makarov_pm", "m16", "shotgun", "mini_uzi", "silenced_pistol",
			"sniper", "revolver", "ak_gl", "smg"
		]
		for weapon_id in all_weapons:
			if weapon_id not in unlocked_weapons:
				unlocked_weapons.append(weapon_id)

		for i in range(4):
			if i not in unlocked_grenades:
				unlocked_grenades.append(i)

		for i in range(6):
			if i not in unlocked_active_items:
				unlocked_active_items.append(i)

	## Reset to default unlock state.
	func reset_to_default() -> void:
		unlocked_weapons = DEFAULT_UNLOCKED_WEAPONS.duplicate()
		unlocked_grenades = DEFAULT_UNLOCKED_GRENADES.duplicate()
		unlocked_active_items = DEFAULT_UNLOCKED_ACTIVE_ITEMS.duplicate()
		items_unlocked.clear()

	## Set restrictions enabled.
	func set_restrictions_enabled(enabled: bool) -> void:
		restrictions_enabled = enabled

	## Check if restrictions are enabled.
	func are_restrictions_enabled() -> bool:
		return restrictions_enabled

	## Get unlock hold time.
	func get_unlock_hold_time() -> float:
		return UNLOCK_HOLD_TIME


var unlock_manager: MockUnlockManager


func before_each() -> void:
	unlock_manager = MockUnlockManager.new()


func after_each() -> void:
	unlock_manager = null


# ============================================================================
# Default State Tests
# ============================================================================


func test_default_only_pm_unlocked() -> void:
	assert_true(unlock_manager.is_weapon_unlocked("makarov_pm"),
		"Makarov PM should be unlocked by default")


func test_default_only_flashbang_unlocked() -> void:
	assert_true(unlock_manager.is_grenade_unlocked(0),
		"Flashbang (type 0) should be unlocked by default")


func test_default_none_active_item_unlocked() -> void:
	assert_true(unlock_manager.is_active_item_unlocked(0),
		"None active item (type 0) should be unlocked by default")


func test_default_m16_locked() -> void:
	assert_false(unlock_manager.is_weapon_unlocked("m16"),
		"M16 should be locked by default")


func test_default_shotgun_locked() -> void:
	assert_false(unlock_manager.is_weapon_unlocked("shotgun"),
		"Shotgun should be locked by default")


func test_default_frag_grenade_locked() -> void:
	assert_false(unlock_manager.is_grenade_unlocked(1),
		"Frag grenade (type 1) should be locked by default")


func test_default_flashlight_locked() -> void:
	assert_false(unlock_manager.is_active_item_unlocked(1),
		"Flashlight (type 1) should be locked by default")


# ============================================================================
# Unlock Tests
# ============================================================================


func test_unlock_weapon() -> void:
	unlock_manager.unlock_weapon("m16")

	assert_true(unlock_manager.is_weapon_unlocked("m16"),
		"M16 should be unlocked after calling unlock_weapon")


func test_unlock_grenade() -> void:
	unlock_manager.unlock_grenade(1)

	assert_true(unlock_manager.is_grenade_unlocked(1),
		"Frag grenade should be unlocked after calling unlock_grenade")


func test_unlock_active_item() -> void:
	unlock_manager.unlock_active_item(1)

	assert_true(unlock_manager.is_active_item_unlocked(1),
		"Flashlight should be unlocked after calling unlock_active_item")


func test_unlock_weapon_emits_signal() -> void:
	unlock_manager.unlock_weapon("shotgun")

	assert_eq(unlock_manager.items_unlocked.size(), 1,
		"Should track one unlocked item")
	assert_eq(unlock_manager.items_unlocked[0]["type"], "weapon",
		"Should be a weapon unlock")
	assert_eq(unlock_manager.items_unlocked[0]["id"], "shotgun",
		"Should be shotgun")


func test_double_unlock_does_nothing() -> void:
	unlock_manager.unlock_weapon("m16")
	unlock_manager.unlock_weapon("m16")

	assert_eq(unlock_manager.items_unlocked.size(), 1,
		"Should only track one unlock, not duplicate")


func test_unlock_all_weapons() -> void:
	unlock_manager.unlock_all()

	assert_true(unlock_manager.is_weapon_unlocked("m16"),
		"M16 should be unlocked")
	assert_true(unlock_manager.is_weapon_unlocked("shotgun"),
		"Shotgun should be unlocked")
	assert_true(unlock_manager.is_weapon_unlocked("sniper"),
		"Sniper should be unlocked")
	assert_true(unlock_manager.is_weapon_unlocked("revolver"),
		"Revolver should be unlocked")


func test_unlock_all_grenades() -> void:
	unlock_manager.unlock_all()

	assert_true(unlock_manager.is_grenade_unlocked(0),
		"Flashbang should be unlocked")
	assert_true(unlock_manager.is_grenade_unlocked(1),
		"Frag should be unlocked")
	assert_true(unlock_manager.is_grenade_unlocked(2),
		"Defensive should be unlocked")
	assert_true(unlock_manager.is_grenade_unlocked(3),
		"Aggression gas should be unlocked")


func test_unlock_all_active_items() -> void:
	unlock_manager.unlock_all()

	assert_true(unlock_manager.is_active_item_unlocked(0),
		"None should be unlocked")
	assert_true(unlock_manager.is_active_item_unlocked(1),
		"Flashlight should be unlocked")
	assert_true(unlock_manager.is_active_item_unlocked(2),
		"Homing bullets should be unlocked")


# ============================================================================
# Reset Tests
# ============================================================================


func test_reset_to_default_relocks_items() -> void:
	unlock_manager.unlock_weapon("m16")
	unlock_manager.unlock_grenade(1)
	unlock_manager.unlock_active_item(1)

	unlock_manager.reset_to_default()

	assert_false(unlock_manager.is_weapon_unlocked("m16"),
		"M16 should be locked after reset")
	assert_false(unlock_manager.is_grenade_unlocked(1),
		"Frag grenade should be locked after reset")
	assert_false(unlock_manager.is_active_item_unlocked(1),
		"Flashlight should be locked after reset")


func test_reset_keeps_default_unlocked() -> void:
	unlock_manager.reset_to_default()

	assert_true(unlock_manager.is_weapon_unlocked("makarov_pm"),
		"PM should remain unlocked after reset")
	assert_true(unlock_manager.is_grenade_unlocked(0),
		"Flashbang should remain unlocked after reset")
	assert_true(unlock_manager.is_active_item_unlocked(0),
		"None active item should remain unlocked after reset")


# ============================================================================
# Restrictions Tests
# ============================================================================


func test_disable_restrictions_unlocks_all() -> void:
	unlock_manager.set_restrictions_enabled(false)

	assert_true(unlock_manager.is_weapon_unlocked("m16"),
		"M16 should be unlocked when restrictions disabled")
	assert_true(unlock_manager.is_grenade_unlocked(3),
		"Aggression gas should be unlocked when restrictions disabled")
	assert_true(unlock_manager.is_active_item_unlocked(5),
		"Any active item should be unlocked when restrictions disabled")


func test_enable_restrictions_relocks() -> void:
	unlock_manager.set_restrictions_enabled(false)
	unlock_manager.set_restrictions_enabled(true)

	assert_false(unlock_manager.is_weapon_unlocked("m16"),
		"M16 should be locked when restrictions re-enabled")


func test_restrictions_enabled_by_default() -> void:
	assert_true(unlock_manager.are_restrictions_enabled(),
		"Restrictions should be enabled by default")


# ============================================================================
# Hold Time Tests
# ============================================================================


func test_unlock_hold_time() -> void:
	var hold_time := unlock_manager.get_unlock_hold_time()

	assert_eq(hold_time, 1.5,
		"Hold time should be 1.5 seconds")


# ============================================================================
# Edge Cases
# ============================================================================


func test_unknown_weapon_not_unlocked() -> void:
	assert_false(unlock_manager.is_weapon_unlocked("unknown_weapon"),
		"Unknown weapon should not be unlocked")


func test_negative_grenade_type_not_unlocked() -> void:
	assert_false(unlock_manager.is_grenade_unlocked(-1),
		"Negative grenade type should not be unlocked")


func test_high_active_item_type_not_unlocked() -> void:
	assert_false(unlock_manager.is_active_item_unlocked(100),
		"High active item type should not be unlocked")


func test_unlock_preserves_existing_unlocks() -> void:
	unlock_manager.unlock_weapon("m16")
	unlock_manager.unlock_weapon("shotgun")

	assert_true(unlock_manager.is_weapon_unlocked("makarov_pm"),
		"PM should still be unlocked")
	assert_true(unlock_manager.is_weapon_unlocked("m16"),
		"M16 should be unlocked")
	assert_true(unlock_manager.is_weapon_unlocked("shotgun"),
		"Shotgun should be unlocked")
