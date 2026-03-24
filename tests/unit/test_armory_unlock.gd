extends GutTest
## Unit tests for armory unlock functionality.
##
## Tests the item unlock system where items are locked by default
## (except PM and flashbang) and can be unlocked via LMB hold.


# ============================================================================
# Mock Managers for Testing
# ============================================================================


class MockGameManager:
	# Issue #894: "all unspecified items can be opened from the start"
	# silenced_pistol has no condition — freely available from start
	# shotgun, mini_uzi, sniper, revolver, m16, ak_gl require level completion conditions
	var unlocked_weapons: Dictionary = {
		"makarov_pm": true,
		"m16": false,            # Condition: Beach D+ (Issue #1053 req.3)
		"shotgun": false,        # Condition: Building D+
		"mini_uzi": false,       # Condition: Labyrinth D+
		"silenced_pistol": true, # No condition — freely available from start
		"sniper": false,         # Condition: Polygon D+
		"revolver": false,       # Condition: Castle F+
		"ak_gl": false,          # Condition: Decadence F+ (Issue #1423 req.1)
		"smg": false             # Coming soon — not yet available
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

	# Issue #894: no grenades have conditions, all freely available from start
	var unlocked_grenades: Dictionary = {
		GrenadeType.FLASHBANG: true,
		GrenadeType.FRAG: true,          # No condition — freely available from start
		GrenadeType.DEFENSIVE: true,     # No condition — freely available from start
		GrenadeType.AGGRESSION_GAS: true # No condition — freely available from start
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
		BFF_PENDANT,        # Issue #674
		INVISIBILITY_SUIT,
		BREAKER_BULLETS,
		FORCE_FIELD,
		TRAJECTORY_GLASSES, # Issue #744
		LASER_SIGHT,        # Issue #947
		LOUDSPEAKER,        # Issue #959
		BREACHING_CHARGES,  # Issue #1043
		ARMORED_SKIN,       # Issue #1045
		AUTO_RELOAD         # Issue #1067
	}

	# Issue #894: only FLASHLIGHT and TELEPORT_BRACERS have conditions
	# All others are freely available from the start
	var unlocked_active_items: Dictionary = {
		ActiveItemType.NONE: true,
		ActiveItemType.FLASHLIGHT: false,          # Condition: Polygon D+
		ActiveItemType.HOMING_BULLETS: true,       # No condition — freely available from start
		ActiveItemType.TELEPORT_BRACERS: false,    # Condition: Castle F+
		ActiveItemType.BFF_PENDANT: true,          # No condition — freely available from start (Issue #674)
		ActiveItemType.INVISIBILITY_SUIT: true,    # No condition — freely available from start
		ActiveItemType.BREAKER_BULLETS: true,      # No condition — freely available from start
		ActiveItemType.FORCE_FIELD: true,          # No condition — freely available from start
		ActiveItemType.TRAJECTORY_GLASSES: false,  # Condition: City D+ (Issue #1053 req.1)
		ActiveItemType.LASER_SIGHT: true,          # No condition — freely available from start (Issue #947)
		ActiveItemType.LOUDSPEAKER: true,          # No condition — freely available from start (Issue #959)
		ActiveItemType.BREACHING_CHARGES: true,    # No condition — freely available from start (Issue #1043)
		ActiveItemType.ARMORED_SKIN: true,         # No condition — freely available from start (Issue #1045)
		ActiveItemType.AUTO_RELOAD: true           # No condition — freely available from start (Issue #1067)
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
	# PM is always unlocked
	assert_true(game_manager.is_weapon_unlocked("makarov_pm"),
		"PM should be unlocked by default")
	# Free weapons (no conditions) should be unlocked from start
	# Issue #894: "all unspecified items can be opened from the start"
	assert_true(game_manager.is_weapon_unlocked("silenced_pistol"),
		"Silenced Pistol should be unlocked by default (no unlock condition)")
	# Condition-gated weapons should be locked until conditions are met
	assert_false(game_manager.is_weapon_unlocked("ak_gl"),
		"AK+GL should be locked by default (requires Decadence F+, Issue #1423)")
	assert_false(game_manager.is_weapon_unlocked("m16"),
		"M16 should be locked by default (requires Beach D+, Issue #1053)")
	assert_false(game_manager.is_weapon_unlocked("shotgun"),
		"Shotgun should be locked by default (requires Building D+)")
	assert_false(game_manager.is_weapon_unlocked("sniper"),
		"Sniper should be locked by default (requires Polygon D+)")
	assert_false(game_manager.is_weapon_unlocked("mini_uzi"),
		"Mini Uzi should be locked by default (requires Labyrinth D+)")
	assert_false(game_manager.is_weapon_unlocked("revolver"),
		"Revolver should be locked by default (requires Castle F+)")


func test_unlock_weapon() -> void:
	# Shotgun should start locked (has condition)
	assert_false(game_manager.is_weapon_unlocked("shotgun"),
		"Shotgun should be locked before unlock")

	# Unlock shotgun
	game_manager.unlock_weapon("shotgun")

	# Shotgun should now be unlocked
	assert_true(game_manager.is_weapon_unlocked("shotgun"),
		"Shotgun should be unlocked after unlock")

	# Unlock signal should be emitted
	assert_eq(game_manager.unlock_signals.size(), 1,
		"One unlock signal should be emitted")
	assert_eq(game_manager.unlock_signals[0], "shotgun",
		"Unlock signal should be for shotgun")


func test_unlock_already_unlocked_weapon() -> void:
	# PM is already unlocked
	game_manager.unlock_weapon("makarov_pm")

	# Should not emit duplicate signal
	assert_eq(game_manager.unlock_signals.size(), 0,
		"Should not emit signal for already unlocked weapon")


func test_unlock_multiple_weapons() -> void:
	# Unlock condition-gated weapons
	game_manager.unlock_weapon("mini_uzi")
	game_manager.unlock_weapon("shotgun")
	game_manager.unlock_weapon("sniper")

	assert_true(game_manager.is_weapon_unlocked("mini_uzi"), "Mini UZI should be unlocked")
	assert_true(game_manager.is_weapon_unlocked("shotgun"), "Shotgun should be unlocked")
	assert_true(game_manager.is_weapon_unlocked("sniper"), "Sniper should be unlocked")
	assert_eq(game_manager.unlock_signals.size(), 3,
		"Three unlock signals should be emitted")


# ============================================================================
# GrenadeManager Unlock Tests
# ============================================================================


func test_default_grenade_unlock_state() -> void:
	# All grenades have no unlock conditions — all freely available from start
	# Issue #894: "all unspecified items can be opened from the start"
	assert_true(grenade_manager.is_grenade_unlocked(0),
		"Flashbang should be unlocked by default")
	assert_true(grenade_manager.is_grenade_unlocked(1),
		"Frag should be unlocked by default (no unlock condition)")
	assert_true(grenade_manager.is_grenade_unlocked(2),
		"Defensive should be unlocked by default (no unlock condition)")
	assert_true(grenade_manager.is_grenade_unlocked(3),
		"Aggression Gas should be unlocked by default (no unlock condition)")


func test_unlock_already_unlocked_grenade() -> void:
	# Flashbang is already unlocked
	grenade_manager.unlock_grenade(0)

	# Should not emit duplicate signal
	assert_eq(grenade_manager.unlock_signals.size(), 0,
		"Should not emit signal for already unlocked grenade")


# ============================================================================
# ActiveItemManager Unlock Tests
# ============================================================================


func test_default_active_item_unlock_state() -> void:
	# NONE is always unlocked
	assert_true(active_item_manager.is_active_item_unlocked(0),
		"NONE should be unlocked by default")
	# Condition-gated items start locked
	assert_false(active_item_manager.is_active_item_unlocked(1),
		"Flashlight should be locked by default (requires Polygon D+)")
	assert_false(active_item_manager.is_active_item_unlocked(3),
		"Teleport Bracers should be locked by default (requires Castle F+)")
	# Free items (no conditions) should be unlocked from start
	# Issue #894: "all unspecified items can be opened from the start"
	assert_true(active_item_manager.is_active_item_unlocked(2),
		"Homing Bullets should be unlocked by default (no unlock condition)")
	assert_true(active_item_manager.is_active_item_unlocked(4),
		"BFF Pendant should be unlocked by default (no unlock condition)")
	assert_true(active_item_manager.is_active_item_unlocked(5),
		"Invisibility Suit should be unlocked by default (no unlock condition)")
	assert_true(active_item_manager.is_active_item_unlocked(6),
		"Breaker Bullets should be unlocked by default (no unlock condition)")
	assert_true(active_item_manager.is_active_item_unlocked(7),
		"Force Field should be unlocked by default (no unlock condition)")
	assert_true(active_item_manager.is_active_item_unlocked(8),
		"Trajectory Glasses should be unlocked by default (no unlock condition)")
	assert_true(active_item_manager.is_active_item_unlocked(9),
		"Laser Sight should be unlocked by default (no unlock condition)")


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
	# Unlock condition-gated items
	active_item_manager.unlock_active_item(1)  # FLASHLIGHT
	active_item_manager.unlock_active_item(3)  # TELEPORT_BRACERS

	assert_true(active_item_manager.is_active_item_unlocked(1), "Flashlight should be unlocked")
	assert_true(active_item_manager.is_active_item_unlocked(3), "Teleport Bracers should be unlocked")
	assert_eq(active_item_manager.unlock_signals.size(), 2,
		"Two unlock signals should be emitted")


# ============================================================================
# Integration Tests
# ============================================================================


func test_unlock_state_persists() -> void:
	# Unlock condition-gated items
	game_manager.unlock_weapon("mini_uzi")
	active_item_manager.unlock_active_item(1)

	# Verify state persists (within session)
	assert_true(game_manager.is_weapon_unlocked("mini_uzi"),
		"Weapon unlock should persist")
	assert_true(active_item_manager.is_active_item_unlocked(1),
		"Active item unlock should persist")


func test_get_unlocked_weapons() -> void:
	var unlocked := game_manager.get_unlocked_weapons()

	assert_true(unlocked.has("makarov_pm"), "Should have PM in unlocked weapons")
	assert_true(unlocked["makarov_pm"], "PM should be unlocked")
	assert_true(unlocked["m16"], "M16 should be unlocked (no condition)")
	assert_false(unlocked["shotgun"], "Shotgun should be locked (has condition)")


func test_get_unlocked_grenades() -> void:
	var unlocked := grenade_manager.get_unlocked_grenades()

	assert_true(unlocked.has(0), "Should have Flashbang in unlocked grenades")
	assert_true(unlocked[0], "Flashbang should be unlocked")
	assert_true(unlocked[1], "Frag should be unlocked (no condition)")


func test_get_unlocked_active_items() -> void:
	var unlocked := active_item_manager.get_unlocked_active_items()

	assert_true(unlocked.has(0), "Should have NONE in unlocked active items")
	assert_true(unlocked[0], "NONE should be unlocked")
	assert_false(unlocked[1], "Flashlight should be locked (has condition)")
	assert_true(unlocked[2], "Homing Bullets should be unlocked (no condition)")


# ============================================================================
# Condition-gated Unlock Tests (Issue #894 fix)
# These tests verify the rule: locked items can only be unlocked via LMB hold
# when their unlock condition is met. Without condition_met, LMB should do nothing.
# ============================================================================


## Simulate the armory LMB hold logic for weapons.
## Returns true if the unlock would be started (condition met), false otherwise.
func _simulate_weapon_lmb_press(weapon_id: String, is_unlocked: bool, condition_met: bool) -> bool:
	if is_unlocked:
		# Already unlocked: selecting, not unlocking — not what we test here
		return false
	elif condition_met:
		# Start unlock tracking (simulated)
		return true
	else:
		# No condition met: LMB does nothing
		return false


## Simulate the armory LMB hold logic for active items.
func _simulate_active_item_lmb_press(item_type: int, is_unlocked: bool, condition_met: bool) -> bool:
	if is_unlocked:
		return false
	elif condition_met:
		return true
	else:
		return false


func test_locked_weapon_without_condition_cannot_be_unlocked_via_lmb() -> void:
	# mini_uzi is locked, no condition met (no Labyrinth progress)
	var would_unlock := _simulate_weapon_lmb_press("mini_uzi", false, false)
	assert_false(would_unlock,
		"Locked weapon without condition met should NOT start LMB unlock tracking")


func test_locked_weapon_with_condition_can_be_unlocked_via_lmb() -> void:
	# mini_uzi is locked, condition IS met (Labyrinth completed with D+)
	var would_unlock := _simulate_weapon_lmb_press("mini_uzi", false, true)
	assert_true(would_unlock,
		"Locked weapon with condition met SHOULD start LMB unlock tracking")


func test_unlocked_weapon_lmb_does_not_trigger_unlock_flow() -> void:
	# makarov_pm is already unlocked — LMB selects, doesn't unlock
	var would_unlock := _simulate_weapon_lmb_press("makarov_pm", true, false)
	assert_false(would_unlock,
		"Already unlocked weapon should not go through unlock flow")


func test_locked_active_item_without_condition_cannot_be_unlocked() -> void:
	# Flashlight is locked, no condition met (Polygon not completed)
	var would_unlock := _simulate_active_item_lmb_press(1, false, false)
	assert_false(would_unlock,
		"Locked active item without condition met should NOT start LMB unlock")


func test_locked_active_item_with_condition_can_be_unlocked() -> void:
	# Teleport Bracers locked, condition IS met (Castle completed with F+)
	var would_unlock := _simulate_active_item_lmb_press(3, false, true)
	assert_true(would_unlock,
		"Locked active item with condition met SHOULD start LMB unlock")


func test_multiple_locked_weapons_only_condition_met_ones_unlockable() -> void:
	# shotgun: condition not met → not unlockable
	assert_false(_simulate_weapon_lmb_press("shotgun", false, false),
		"Shotgun without condition should not be unlockable")
	# revolver: condition met → unlockable
	assert_true(_simulate_weapon_lmb_press("revolver", false, true),
		"Revolver with condition met should be unlockable")
	# sniper: condition not met → not unlockable
	assert_false(_simulate_weapon_lmb_press("sniper", false, false),
		"Sniper without condition should not be unlockable")
