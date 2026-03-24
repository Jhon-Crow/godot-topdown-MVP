extends GutTest
## Unit tests for the Laser Sight kill-based unlock condition (Issue #1196).
##
## Tests that:
## - LASER_SIGHT starts locked (no longer freely available from start)
## - kills_without_laser_sight counter increments only for player kills without laser sight
## - Non-player kills (enemy-vs-enemy) do NOT increment the counter
## - The kill condition requires exactly 1000 kills without laser sight
## - is_kill_condition_met returns correct values based on kill count
## - KILL_UNLOCK_CONDITIONS contains the correct entry for Laser Sight


# ============================================================================
# Mock Classes
# ============================================================================


class MockActiveItemManager:
	enum ActiveItemType {
		NONE = 0,
		FLASHLIGHT = 1,
		HOMING_BULLETS = 2,
		TELEPORT_BRACERS = 3,
		BFF_PENDANT = 4,
		INVISIBILITY_SUIT = 5,
		BREAKER_BULLETS = 6,
		FORCE_FIELD = 7,
		TRAJECTORY_GLASSES = 8,
		LASER_SIGHT = 9,
		EXTENDED_MAGAZINE = 10
	}

	var current_active_item: int = ActiveItemType.NONE

	var unlocked_active_items: Dictionary = {
		ActiveItemType.NONE: true,
		ActiveItemType.LASER_SIGHT: false,  # Condition: 1000 kills without laser sight (Issue #1196)
	}

	func has_laser_sight() -> bool:
		return current_active_item == ActiveItemType.LASER_SIGHT

	func is_active_item_unlocked(item_type: int) -> bool:
		return unlocked_active_items.get(item_type, false)

	func set_active_item(type: int, _restart_level: bool = true) -> void:
		current_active_item = type


class MockGameManager:
	var kills: int = 0
	var kills_without_laser_sight: int = 0
	var _active_item_manager: MockActiveItemManager = null

	func set_active_item_manager(aim: MockActiveItemManager) -> void:
		_active_item_manager = aim

	func register_kill(is_player_kill: bool = true) -> void:
		kills += 1
		# Only count player kills (Issue #1196: enemy-vs-enemy kills don't count)
		if not is_player_kill:
			return
		if _active_item_manager == null or not _active_item_manager.has_laser_sight():
			kills_without_laser_sight += 1


class MockUnlockManager:
	## Kill-based unlock conditions (mirrors the real KILL_UNLOCK_CONDITIONS).
	const KILL_UNLOCK_CONDITIONS: Array = [
		{
			"stat": "kills_without_laser_sight",
			"min_kills": 1000,
			"weapons": [],
			"grenades": [],
			"active_items": [9]  # LASER_SIGHT = 9
		}
	]

	var _game_manager: MockGameManager = null

	func set_game_manager(gm: MockGameManager) -> void:
		_game_manager = gm

	func is_kill_condition_met(kill_condition: Dictionary) -> bool:
		if _game_manager == null:
			return false
		var stat: String = kill_condition.get("stat", "")
		var min_kills: int = kill_condition.get("min_kills", 0)
		if stat.is_empty():
			return false
		var current_kills: int = _game_manager.get(stat) if _game_manager.get(stat) != null else 0
		return current_kills >= min_kills

	func is_active_item_condition_met(item_type: int) -> bool:
		for kill_condition in KILL_UNLOCK_CONDITIONS:
			if item_type in kill_condition.get("active_items", []):
				if is_kill_condition_met(kill_condition):
					return true
		return false


var active_item_manager: MockActiveItemManager
var game_manager: MockGameManager
var unlock_manager: MockUnlockManager


func before_each() -> void:
	active_item_manager = MockActiveItemManager.new()
	game_manager = MockGameManager.new()
	game_manager.set_active_item_manager(active_item_manager)
	unlock_manager = MockUnlockManager.new()
	unlock_manager.set_game_manager(game_manager)


func after_each() -> void:
	active_item_manager = null
	game_manager = null
	unlock_manager = null


# ============================================================================
# Laser Sight Locked By Default Tests
# ============================================================================


func test_laser_sight_starts_locked() -> void:
	assert_false(active_item_manager.is_active_item_unlocked(
			active_item_manager.ActiveItemType.LASER_SIGHT),
		"LASER_SIGHT should start locked (not freely available) — Issue #1196")


func test_laser_sight_not_equipped_by_default() -> void:
	assert_false(active_item_manager.has_laser_sight(),
		"Laser sight should not be equipped by default")


# ============================================================================
# kills_without_laser_sight Counter Tests
# ============================================================================


func test_kills_without_laser_sight_starts_at_zero() -> void:
	assert_eq(game_manager.kills_without_laser_sight, 0,
		"kills_without_laser_sight should start at 0")


func test_kill_increments_counter_when_laser_sight_not_equipped() -> void:
	# Default: NONE equipped — no laser sight
	game_manager.register_kill()
	assert_eq(game_manager.kills_without_laser_sight, 1,
		"kills_without_laser_sight should increment when laser sight is NOT equipped")


func test_kill_does_not_increment_counter_when_laser_sight_equipped() -> void:
	active_item_manager.set_active_item(active_item_manager.ActiveItemType.LASER_SIGHT)
	game_manager.register_kill()
	assert_eq(game_manager.kills_without_laser_sight, 0,
		"kills_without_laser_sight should NOT increment when laser sight IS equipped")


func test_kills_accumulate_correctly_without_laser_sight() -> void:
	for i in range(500):
		game_manager.register_kill()
	assert_eq(game_manager.kills_without_laser_sight, 500,
		"kills_without_laser_sight should accumulate correctly")


func test_kills_do_not_accumulate_when_laser_sight_equipped() -> void:
	active_item_manager.set_active_item(active_item_manager.ActiveItemType.LASER_SIGHT)
	for i in range(500):
		game_manager.register_kill()
	assert_eq(game_manager.kills_without_laser_sight, 0,
		"No kills_without_laser_sight should accumulate while laser sight is equipped")


func test_kills_only_count_when_laser_sight_not_equipped() -> void:
	# 300 kills without laser sight
	for i in range(300):
		game_manager.register_kill()
	# Switch to laser sight
	active_item_manager.set_active_item(active_item_manager.ActiveItemType.LASER_SIGHT)
	# 200 kills WITH laser sight (should not count)
	for i in range(200):
		game_manager.register_kill()
	assert_eq(game_manager.kills_without_laser_sight, 300,
		"Only kills made without laser sight should count toward the unlock condition")


# ============================================================================
# Player-Kill-Only Tests (Issue #1196 requirement)
# ============================================================================


func test_non_player_kill_does_not_increment_counter() -> void:
	# Enemy-vs-enemy or ally-vs-enemy kills must NOT count (Issue #1196)
	game_manager.register_kill(false)  # is_player_kill = false
	assert_eq(game_manager.kills_without_laser_sight, 0,
		"Non-player kills should NOT increment kills_without_laser_sight")


func test_non_player_kill_still_increments_total_kills() -> void:
	game_manager.register_kill(false)
	assert_eq(game_manager.kills, 1,
		"Total kills counter should still increment for non-player kills")


func test_player_kill_increments_counter() -> void:
	game_manager.register_kill(true)  # is_player_kill = true
	assert_eq(game_manager.kills_without_laser_sight, 1,
		"Player kills without laser sight should increment kills_without_laser_sight")


func test_mixed_player_and_non_player_kills() -> void:
	# 300 player kills (no laser sight)
	for i in range(300):
		game_manager.register_kill(true)
	# 200 enemy-vs-enemy kills (should not count)
	for i in range(200):
		game_manager.register_kill(false)
	assert_eq(game_manager.kills_without_laser_sight, 300,
		"Mixed kills: only player kills should count toward unlock condition")
	assert_eq(game_manager.kills, 500,
		"Mixed kills: total kills counter should include all kills")


# ============================================================================
# Kill Condition Met / Not Met Tests
# ============================================================================


func test_kill_condition_not_met_at_zero_kills() -> void:
	assert_false(unlock_manager.is_kill_condition_met(
			unlock_manager.KILL_UNLOCK_CONDITIONS[0]),
		"Kill condition should not be met at 0 kills")


func test_kill_condition_not_met_at_999_kills() -> void:
	game_manager.kills_without_laser_sight = 999
	assert_false(unlock_manager.is_kill_condition_met(
			unlock_manager.KILL_UNLOCK_CONDITIONS[0]),
		"Kill condition should not be met at 999 kills (needs exactly 1000)")


func test_kill_condition_met_at_1000_kills() -> void:
	game_manager.kills_without_laser_sight = 1000
	assert_true(unlock_manager.is_kill_condition_met(
			unlock_manager.KILL_UNLOCK_CONDITIONS[0]),
		"Kill condition should be met at exactly 1000 kills without laser sight")


func test_kill_condition_met_above_1000_kills() -> void:
	game_manager.kills_without_laser_sight = 1500
	assert_true(unlock_manager.is_kill_condition_met(
			unlock_manager.KILL_UNLOCK_CONDITIONS[0]),
		"Kill condition should remain met above 1000 kills")


# ============================================================================
# KILL_UNLOCK_CONDITIONS Structure Tests
# ============================================================================


func test_kill_unlock_conditions_has_laser_sight_entry() -> void:
	var found: bool = false
	for cond in unlock_manager.KILL_UNLOCK_CONDITIONS:
		if 9 in cond.get("active_items", []):  # LASER_SIGHT = 9
			found = true
			break
	assert_true(found,
		"KILL_UNLOCK_CONDITIONS should contain an entry for LASER_SIGHT (type 9)")


func test_kill_unlock_condition_requires_1000_kills() -> void:
	for cond in unlock_manager.KILL_UNLOCK_CONDITIONS:
		if 9 in cond.get("active_items", []):
			assert_eq(cond.get("min_kills", 0), 1000,
				"Laser Sight unlock should require 1000 kills without laser sight")
			assert_eq(cond.get("stat", ""), "kills_without_laser_sight",
				"Laser Sight unlock should track 'kills_without_laser_sight' stat")
			return
	fail_test("No kill condition entry found for Laser Sight in KILL_UNLOCK_CONDITIONS")


func test_kill_unlock_condition_has_no_weapons_or_grenades() -> void:
	for cond in unlock_manager.KILL_UNLOCK_CONDITIONS:
		if 9 in cond.get("active_items", []):
			assert_true(cond.get("weapons", []).is_empty(),
				"Laser Sight kill condition should not unlock any weapons")
			assert_true(cond.get("grenades", []).is_empty(),
				"Laser Sight kill condition should not unlock any grenades")
			return


# ============================================================================
# is_active_item_condition_met Integration Tests
# ============================================================================


func test_active_item_condition_not_met_below_threshold() -> void:
	game_manager.kills_without_laser_sight = 999
	assert_false(unlock_manager.is_active_item_condition_met(
			active_item_manager.ActiveItemType.LASER_SIGHT),
		"Laser Sight condition should not be met at 999 kills")


func test_active_item_condition_met_at_threshold() -> void:
	game_manager.kills_without_laser_sight = 1000
	assert_true(unlock_manager.is_active_item_condition_met(
			active_item_manager.ActiveItemType.LASER_SIGHT),
		"Laser Sight condition should be met at 1000 kills")
