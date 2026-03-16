extends Node
## Test script to verify armory unlock functionality.
##
## This script tests:
## 1. Default lock state (only PM and flashbang unlocked)
## 2. Unlock methods work correctly
## 3. Unlock state persists during session

func _ready() -> void:
	print("\n=== Testing Armory Unlock Functionality ===\n")

	# Test 1: Verify default weapon unlock state
	print("Test 1: Default weapon unlock state")
	_test_default_weapon_state()

	# Test 2: Verify default grenade unlock state
	print("\nTest 2: Default grenade unlock state")
	_test_default_grenade_state()

	# Test 3: Verify default active item unlock state
	print("\nTest 3: Default active item unlock state")
	_test_default_active_item_state()

	# Test 4: Test weapon unlock
	print("\nTest 4: Weapon unlock functionality")
	_test_weapon_unlock()

	# Test 5: Test grenade unlock
	print("\nTest 5: Grenade unlock functionality")
	_test_grenade_unlock()

	# Test 6: Test active item unlock
	print("\nTest 6: Active item unlock functionality")
	_test_active_item_unlock()

	print("\n=== All tests completed ===\n")
	get_tree().quit()


func _test_default_weapon_state() -> void:
	var game_manager = get_node_or_null("/root/GameManager")
	if not game_manager:
		print("  ❌ GameManager not found")
		return

	# Only PM should be unlocked by default
	var pm_unlocked: bool = game_manager.is_weapon_unlocked("makarov_pm")
	var m16_unlocked: bool = game_manager.is_weapon_unlocked("m16")
	var shotgun_unlocked: bool = game_manager.is_weapon_unlocked("shotgun")

	if pm_unlocked and not m16_unlocked and not shotgun_unlocked:
		print("  ✓ Default weapon state correct (only PM unlocked)")
	else:
		print("  ❌ Default weapon state incorrect")
		print("    PM: %s, M16: %s, Shotgun: %s" % [pm_unlocked, m16_unlocked, shotgun_unlocked])


func _test_default_grenade_state() -> void:
	var grenade_manager = get_node_or_null("/root/GrenadeManager")
	if not grenade_manager:
		print("  ❌ GrenadeManager not found")
		return

	# Only flashbang should be unlocked by default
	var flashbang_unlocked: bool = grenade_manager.is_grenade_unlocked(0)  # FLASHBANG
	var frag_unlocked: bool = grenade_manager.is_grenade_unlocked(1)  # FRAG
	var defensive_unlocked: bool = grenade_manager.is_grenade_unlocked(2)  # DEFENSIVE

	if flashbang_unlocked and not frag_unlocked and not defensive_unlocked:
		print("  ✓ Default grenade state correct (only Flashbang unlocked)")
	else:
		print("  ❌ Default grenade state incorrect")
		print("    Flashbang: %s, Frag: %s, Defensive: %s" % [flashbang_unlocked, frag_unlocked, defensive_unlocked])


func _test_default_active_item_state() -> void:
	var active_item_manager = get_node_or_null("/root/ActiveItemManager")
	if not active_item_manager:
		print("  ❌ ActiveItemManager not found")
		return

	# Only NONE should be unlocked by default
	var none_unlocked: bool = active_item_manager.is_active_item_unlocked(0)  # NONE
	var flashlight_unlocked: bool = active_item_manager.is_active_item_unlocked(1)  # FLASHLIGHT
	var homing_unlocked: bool = active_item_manager.is_active_item_unlocked(2)  # HOMING_BULLETS

	if none_unlocked and not flashlight_unlocked and not homing_unlocked:
		print("  ✓ Default active item state correct (only None unlocked)")
	else:
		print("  ❌ Default active item state incorrect")
		print("    None: %s, Flashlight: %s, Homing: %s" % [none_unlocked, flashlight_unlocked, homing_unlocked])


func _test_weapon_unlock() -> void:
	var game_manager = get_node_or_null("/root/GameManager")
	if not game_manager:
		print("  ❌ GameManager not found")
		return

	# Test unlocking M16
	var before_unlock: bool = game_manager.is_weapon_unlocked("m16")
	game_manager.unlock_weapon("m16")
	var after_unlock: bool = game_manager.is_weapon_unlocked("m16")

	if not before_unlock and after_unlock:
		print("  ✓ Weapon unlock works correctly")
	else:
		print("  ❌ Weapon unlock failed")
		print("    Before: %s, After: %s" % [before_unlock, after_unlock])


func _test_grenade_unlock() -> void:
	var grenade_manager = get_node_or_null("/root/GrenadeManager")
	if not grenade_manager:
		print("  ❌ GrenadeManager not found")
		return

	# Test unlocking frag grenade
	var before_unlock: bool = grenade_manager.is_grenade_unlocked(1)  # FRAG
	grenade_manager.unlock_grenade(1)
	var after_unlock: bool = grenade_manager.is_grenade_unlocked(1)

	if not before_unlock and after_unlock:
		print("  ✓ Grenade unlock works correctly")
	else:
		print("  ❌ Grenade unlock failed")
		print("    Before: %s, After: %s" % [before_unlock, after_unlock])


func _test_active_item_unlock() -> void:
	var active_item_manager = get_node_or_null("/root/ActiveItemManager")
	if not active_item_manager:
		print("  ❌ ActiveItemManager not found")
		return

	# Test unlocking flashlight
	var before_unlock: bool = active_item_manager.is_active_item_unlocked(1)  # FLASHLIGHT
	active_item_manager.unlock_active_item(1)
	var after_unlock: bool = active_item_manager.is_active_item_unlocked(1)

	if not before_unlock and after_unlock:
		print("  ✓ Active item unlock works correctly")
	else:
		print("  ❌ Active item unlock failed")
		print("    Before: %s, After: %s" % [before_unlock, after_unlock])
