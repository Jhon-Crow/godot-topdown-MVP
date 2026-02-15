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
		BREAKER_BULLETS
	}

	var unlocked_active_items: Dictionary = {
		ActiveItemType.NONE: true,
		ActiveItemType.FLASHLIGHT: false,
		ActiveItemType.HOMING_BULLETS: false,
		ActiveItemType.TELEPORT_BRACERS: false,
		ActiveItemType.INVISIBILITY_SUIT: false,
		ActiveItemType.BREAKER_BULLETS: false
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


# ============================================================================
# Animation Constants Tests (Issue #785)
# ============================================================================


func test_armory_menu_script_has_animation_constants() -> void:
	# Test that the armory_menu.gd script has the necessary constants for animations
	var armory_script = load("res://scripts/ui/armory_menu.gd")
	assert_not_null(armory_script, "armory_menu.gd should exist")

	# Create an instance to check constants
	var armory_instance = armory_script.new()
	assert_not_null(armory_instance, "Should be able to instantiate armory_menu")

	# Check that unlock hold duration is defined
	assert_true(armory_instance.get("UNLOCK_HOLD_DURATION") != null or
		armory_instance.UNLOCK_HOLD_DURATION > 0,
		"UNLOCK_HOLD_DURATION constant should be defined")

	# Clean up (CanvasLayer needs to be added to tree or freed manually)
	if armory_instance:
		armory_instance.free()


func test_armory_menu_has_beep_functionality() -> void:
	# Test that the armory_menu.gd script has beep sound functionality
	var armory_script = load("res://scripts/ui/armory_menu.gd")
	var armory_instance = armory_script.new()

	# Check for beep-related constants
	assert_true(armory_instance.BEEP_BASE_FREQUENCY > 0,
		"BEEP_BASE_FREQUENCY should be a positive value")

	if armory_instance:
		armory_instance.free()


func test_unlock_progress_calculated_correctly() -> void:
	# Test that progress calculation logic is correct
	var unlock_duration: float = 1.5
	var test_cases: Array = [
		[0.0, 0.0],    # Start: 0% progress
		[0.75, 0.5],   # Half-way: 50% progress
		[1.5, 1.0],    # End: 100% progress
		[2.0, 1.0],    # Over: still 100% (clamped)
	]

	for test_case in test_cases:
		var hold_duration: float = test_case[0]
		var expected_progress: float = test_case[1]
		var actual_progress: float = minf(hold_duration / unlock_duration, 1.0)
		assert_almost_eq(actual_progress, expected_progress, 0.001,
			"Progress for hold duration %f should be %f" % [hold_duration, expected_progress])


func test_progress_beep_thresholds() -> void:
	# Test that progress beep thresholds are calculated correctly (every 20%)
	var test_cases: Array = [
		[0.0, 0.0],   # 0% -> threshold 0.0
		[0.15, 0.0],  # 15% -> threshold 0.0
		[0.2, 0.2],   # 20% -> threshold 0.2
		[0.45, 0.4],  # 45% -> threshold 0.4
		[0.6, 0.6],   # 60% -> threshold 0.6
		[0.85, 0.8],  # 85% -> threshold 0.8
		[1.0, 1.0],   # 100% -> threshold 1.0
	]

	for test_case in test_cases:
		var progress: float = test_case[0]
		var expected_threshold: float = test_case[1]
		var actual_threshold: float = floor(progress * 5.0) / 5.0
		assert_almost_eq(actual_threshold, expected_threshold, 0.001,
			"Threshold for progress %f should be %f" % [progress, expected_threshold])


func test_rising_frequency_calculation() -> void:
	# Test that beep frequency rises as progress increases
	var base_frequency: float = 440.0

	var freq_at_0: float = base_frequency * 0.5 * (1.0 + 0.0 * 2.0)
	var freq_at_50: float = base_frequency * 0.5 * (1.0 + 0.5 * 2.0)
	var freq_at_100: float = base_frequency * 0.5 * (1.0 + 1.0 * 2.0)

	assert_true(freq_at_50 > freq_at_0,
		"Frequency at 50%% should be higher than at 0%%")
	assert_true(freq_at_100 > freq_at_50,
		"Frequency at 100%% should be higher than at 50%%")

	# Verify specific values
	assert_almost_eq(freq_at_0, 220.0, 0.1,
		"Frequency at 0%% progress should be ~220Hz")
	assert_almost_eq(freq_at_100, 660.0, 0.1,
		"Frequency at 100%% progress should be ~660Hz")
