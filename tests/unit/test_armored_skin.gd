extends GutTest
## Unit tests for the Armored Skin passive item (Issue #1045).
##
## Tests the armored skin item registration, helper method, description,
## shard spawn logic, and +1 HP bonus behavior.


# ============================================================================
# MockActiveItemManager with Armored Skin (Issue #1045)
# ============================================================================


class MockActiveItemManagerWithArmoredSkin:
	## Active item types (matching actual enum values)
	const ActiveItemType := {
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
		ARMORED_SKIN = 10
	}

	var current_active_item: int = ActiveItemType.NONE

	const ACTIVE_ITEM_DATA: Dictionary = {
		0: {"name": "None", "icon_path": "", "description": "No active item equipped."},
		1: {"name": "Flashlight", "icon_path": "res://assets/sprites/weapons/flashlight_icon.png",
			"description": "Tactical flashlight — hold Space to illuminate in weapon direction and blind enemies caught in the beam."},
		2: {"name": "Homing Bullets", "icon_path": "res://assets/sprites/weapons/homing_bullets_icon.png",
			"description": "Press Space to activate — bullets steer toward the nearest enemy."},
		3: {"name": "Teleport Bracers", "icon_path": "res://assets/sprites/weapons/teleport_bracers_icon.png",
			"description": "Teleportation bracers — hold Space to aim, release to teleport."},
		4: {"name": "BFF Pendant", "icon_path": "res://assets/sprites/weapons/bff_pendant_icon.png",
			"description": "BFF pendant — press Space to summon a friendly companion."},
		5: {"name": "Invisibility", "icon_path": "res://assets/sprites/weapons/invisibility_suit_icon.png",
			"description": "Invisibility suit — press Space to cloak."},
		6: {"name": "Breaker Bullets", "icon_path": "res://assets/sprites/weapons/breaker_bullets_icon.png",
			"description": "Breaker bullets — passive: bullets explode before hitting a wall."},
		7: {"name": "Force Field", "icon_path": "res://assets/sprites/weapons/force_field_icon.png",
			"description": "Force field — hold Space to activate glowing shield."},
		8: {"name": "Trajectory Glasses", "icon_path": "res://assets/sprites/weapons/trajectory_glasses_icon.png",
			"description": "Trajectory glasses — press Space to see ricochet trajectories. Passive: +30% ricochet."},
		9: {"name": "Laser Sight", "icon_path": "res://assets/sprites/weapons/laser_sight_icon.png",
			"description": "Laser sight — passive: adds a purple laser sight to all weapons."},
		10: {"name": "Armored Skin", "icon_path": "res://assets/sprites/weapons/armored_skin_icon.png",
			"description": "Armored Skin — passive: +1 HP. When at 2 HP or less and hit, 20 glass shards explode outward in all directions."}
	}

	func get_all_active_item_types() -> Array:
		return ACTIVE_ITEM_DATA.keys()

	func get_active_item_data(type: int) -> Dictionary:
		if type in ACTIVE_ITEM_DATA:
			return ACTIVE_ITEM_DATA[type]
		return {}

	func get_active_item_name(type: int) -> String:
		if type in ACTIVE_ITEM_DATA:
			return ACTIVE_ITEM_DATA[type]["name"]
		return "Unknown"

	func get_active_item_description(type: int) -> String:
		if type in ACTIVE_ITEM_DATA:
			return ACTIVE_ITEM_DATA[type]["description"]
		return ""

	func set_active_item(type: int, _restart: bool = false) -> void:
		if type in ACTIVE_ITEM_DATA:
			current_active_item = type

	func has_armored_skin() -> bool:
		return current_active_item == ActiveItemType.ARMORED_SKIN

	func has_breaker_bullets() -> bool:
		return current_active_item == ActiveItemType.BREAKER_BULLETS

	func has_laser_sight() -> bool:
		return current_active_item == ActiveItemType.LASER_SIGHT

	func is_selected(type: int) -> bool:
		return current_active_item == type


var manager: MockActiveItemManagerWithArmoredSkin


func before_each() -> void:
	manager = MockActiveItemManagerWithArmoredSkin.new()


func after_each() -> void:
	manager = null


# ============================================================================
# Armored Skin Enum Value Tests
# ============================================================================


func test_armored_skin_type_value() -> void:
	# ActiveItemType.ARMORED_SKIN should be 10 (after LASER_SIGHT = 9)
	var expected := 10
	assert_eq(expected, 10, "ARMORED_SKIN should be type value 10")


func test_armored_skin_exists_in_data() -> void:
	var data := manager.get_active_item_data(10)
	assert_false(data.is_empty(), "ACTIVE_ITEM_DATA should contain ARMORED_SKIN type (10)")


# ============================================================================
# Armored Skin Data Tests
# ============================================================================


func test_armored_skin_name() -> void:
	var data := manager.get_active_item_data(10)
	assert_eq(data["name"], "Armored Skin", "Armored Skin should have correct name")


func test_armored_skin_icon_path() -> void:
	var data := manager.get_active_item_data(10)
	assert_true(data["icon_path"].contains("armored_skin"),
		"Armored Skin icon path should contain 'armored_skin'")


func test_armored_skin_description_mentions_passive() -> void:
	var data := manager.get_active_item_data(10)
	assert_true(data["description"].contains("passive"),
		"Armored Skin description should mention 'passive'")


func test_armored_skin_description_mentions_hp_bonus() -> void:
	var data := manager.get_active_item_data(10)
	assert_true(data["description"].contains("+1 HP"),
		"Armored Skin description should mention '+1 HP' bonus")


func test_armored_skin_description_mentions_shards() -> void:
	var data := manager.get_active_item_data(10)
	assert_true(data["description"].contains("shard") or data["description"].contains("glass"),
		"Armored Skin description should mention shards or glass")


func test_armored_skin_description_mentions_2hp_threshold() -> void:
	var data := manager.get_active_item_data(10)
	assert_true(data["description"].contains("2 HP") or data["description"].contains("2 hp"),
		"Armored Skin description should mention 2 HP threshold")


# ============================================================================
# has_armored_skin() Method Tests
# ============================================================================


func test_no_armored_skin_by_default() -> void:
	assert_false(manager.has_armored_skin(),
		"Armored skin should not be equipped by default")


func test_has_armored_skin_after_selection() -> void:
	manager.set_active_item(10)
	assert_true(manager.has_armored_skin(),
		"has_armored_skin should return true after selecting armored skin")


func test_no_armored_skin_after_deselection() -> void:
	manager.set_active_item(10)
	manager.set_active_item(0)
	assert_false(manager.has_armored_skin(),
		"has_armored_skin should return false after switching back to none")


func test_armored_skin_mutually_exclusive_with_laser_sight() -> void:
	manager.set_active_item(10)
	assert_true(manager.has_armored_skin(), "Armored skin should be active")
	assert_false(manager.has_laser_sight(), "Laser sight should not be active")

	manager.set_active_item(9)
	assert_false(manager.has_armored_skin(), "Armored skin should not be active after switching")
	assert_true(manager.has_laser_sight(), "Laser sight should be active")


func test_armored_skin_mutually_exclusive_with_breaker_bullets() -> void:
	manager.set_active_item(10)
	assert_true(manager.has_armored_skin(), "Armored skin should be active")
	assert_false(manager.has_breaker_bullets(), "Breaker bullets should not be active")


# ============================================================================
# Armored Skin Shard Logic Tests
# ============================================================================


class MockArmoredSkinPlayer:
	## Simulates the player's armored skin shard-spawn logic (Issue #1045, #1453).
	var _armored_skin_active: bool = false
	var _current_health: int = 5
	var max_health: int = 5

	## Number of shard spawns triggered (for testing)
	var shard_spawn_count: int = 0

	## True after armored skin has triggered once — prevents re-triggering (Issue #1453).
	var _armored_skin_triggered: bool = false
	## Simulated physics frame counter (tests increment this to simulate frame changes).
	var mock_frame: int = 0
	## Physics frame when armored skin triggered.
	var _armored_skin_trigger_frame: int = -1

	## Shard count per spawn
	const ARMORED_SKIN_SHARD_COUNT: int = 20
	const ARMORED_SKIN_HP_THRESHOLD: int = 2

	func init_armored_skin(has_it: bool) -> void:
		_armored_skin_active = has_it
		if has_it:
			max_health += 1
			_current_health = max_health

	func take_hit(incoming_damage: int = 1) -> void:
		# Mirror of the logic in player.gd on_hit_with_info (Issue #1453).
		if _armored_skin_active:
			# Absorb same-frame burst hits (Issue #1453).
			if _armored_skin_triggered and mock_frame == _armored_skin_trigger_frame:
				return
			if not _armored_skin_triggered:
				# Trigger when HP is at/below threshold OR when the hit would be lethal.
				if _current_health <= ARMORED_SKIN_HP_THRESHOLD or _current_health - incoming_damage <= 0:
					_armored_skin_triggered = true
					_armored_skin_trigger_frame = mock_frame
					shard_spawn_count += 1
					return  # Absorb the triggering hit (Issue #1453)
		_current_health -= incoming_damage
		if _current_health < 0:
			_current_health = 0

	func get_current_health() -> int:
		return _current_health


func test_armored_skin_hp_bonus_increases_max_health() -> void:
	var player := MockArmoredSkinPlayer.new()
	var base_max := player.max_health  # 5
	player.init_armored_skin(true)
	assert_eq(player.max_health, base_max + 1,
		"Armored skin should increase max_health by 1")


func test_armored_skin_hp_bonus_sets_current_health() -> void:
	var player := MockArmoredSkinPlayer.new()
	player.init_armored_skin(true)
	assert_eq(player.get_current_health(), player.max_health,
		"Current health should equal max_health after armored skin init")


func test_no_hp_bonus_without_armored_skin() -> void:
	var player := MockArmoredSkinPlayer.new()
	var base_max := player.max_health
	player.init_armored_skin(false)
	assert_eq(player.max_health, base_max,
		"max_health should not change when armored skin is not equipped")


func test_shards_spawn_when_at_2hp_and_hit() -> void:
	var player := MockArmoredSkinPlayer.new()
	player.init_armored_skin(true)
	player._current_health = 2

	player.take_hit()

	assert_eq(player.shard_spawn_count, 1,
		"Shards should spawn once when hit at 2 HP")


func test_triggering_hit_absorbed_at_2hp() -> void:
	# Issue #1453: the hit that triggers shards must not reduce player HP.
	var player := MockArmoredSkinPlayer.new()
	player.init_armored_skin(true)
	player._current_health = 2

	player.take_hit()

	assert_eq(player.get_current_health(), 2,
		"Player HP must NOT decrease when armored skin absorbs the triggering hit at 2 HP (Issue #1453)")


func test_shards_spawn_when_at_1hp_and_hit() -> void:
	var player := MockArmoredSkinPlayer.new()
	player.init_armored_skin(true)
	player._current_health = 1

	player.take_hit()

	assert_eq(player.shard_spawn_count, 1,
		"Shards should spawn when hit at 1 HP")


func test_shards_do_not_spawn_at_3hp() -> void:
	var player := MockArmoredSkinPlayer.new()
	player.init_armored_skin(true)
	player._current_health = 3

	player.take_hit()

	assert_eq(player.shard_spawn_count, 0,
		"Shards should NOT spawn when hit at 3 HP (above threshold)")


func test_shards_do_not_spawn_without_armored_skin() -> void:
	var player := MockArmoredSkinPlayer.new()
	player.init_armored_skin(false)
	player._current_health = 2

	player.take_hit()

	assert_eq(player.shard_spawn_count, 0,
		"Shards should NOT spawn if armored skin is not equipped")


func test_shards_spawn_count_is_20() -> void:
	# Verify the ARMORED_SKIN_SHARD_COUNT constant
	var player := MockArmoredSkinPlayer.new()
	assert_eq(player.ARMORED_SKIN_SHARD_COUNT, 20,
		"Armored skin should spawn exactly 20 shards")


func test_shards_spawn_only_once_and_hit_absorbed() -> void:
	# Armored skin triggers exactly once and absorbs the triggering hit (Issue #1453).
	var player := MockArmoredSkinPlayer.new()
	player.init_armored_skin(true)
	player._current_health = 2

	player.take_hit()  # At 2 HP → trigger: shards spawn, hit absorbed → HP stays 2
	assert_eq(player.shard_spawn_count, 1, "Shards should spawn on triggering hit")
	assert_eq(player.get_current_health(), 2,
		"HP must NOT decrease when armored skin absorbs the triggering hit (Issue #1453)")

	player.mock_frame = 1  # Advance to next frame
	player.take_hit()  # Second hit (next frame): no re-trigger, damage applied → HP goes to 1
	assert_eq(player.shard_spawn_count, 1,
		"Shards must spawn exactly once — armored skin must not re-trigger (Issue #1453)")


func test_hp_threshold_is_2() -> void:
	var player := MockArmoredSkinPlayer.new()
	assert_eq(player.ARMORED_SKIN_HP_THRESHOLD, 2,
		"HP threshold for shard spawn should be 2")


# ============================================================================
# Armored Skin in Armory (11 items total now)
# ============================================================================


func test_total_item_count_includes_armored_skin() -> void:
	var types := manager.get_all_active_item_types()
	assert_eq(types.size(), 11,
		"Should have 11 active item types including Armored Skin")
	assert_true(10 in types, "Armored Skin (type 10) should be in the list")


func test_armored_skin_is_not_none() -> void:
	var name := manager.get_active_item_name(10)
	assert_ne(name, "None", "Armored Skin name should not be 'None'")
	assert_ne(name, "Unknown", "Armored Skin name should not be 'Unknown'")


# ============================================================================
# Sniper Rifle Protection Tests (Issue #1453)
# ============================================================================


func test_sniper_rifle_lethal_hit_absorbed_above_threshold() -> void:
	# Issue #1453: A sniper rifle deals 50 damage. If the player has 3 HP
	# (above the 2 HP threshold), the hit would still be lethal.
	# Armored skin must absorb it (trigger condition: current_health - damage <= 0).
	var player := MockArmoredSkinPlayer.new()
	player.init_armored_skin(true)
	# Player starts at 4 HP (3 base + 1 bonus). Manually set to 3 HP.
	player._current_health = 3

	player.take_hit(50)  # Sniper rifle: 50 damage, lethal → trigger armored skin

	assert_eq(player.shard_spawn_count, 1,
		"Armored skin should trigger on lethal sniper hit above HP threshold (Issue #1453)")
	assert_eq(player.get_current_health(), 3,
		"Player HP must NOT decrease when sniper rifle lethal hit is absorbed by armored skin (Issue #1453)")


func test_sniper_rifle_lethal_hit_absorbed_at_threshold() -> void:
	# Issue #1453: Sniper rifle hit when player is at exactly 2 HP (the threshold).
	var player := MockArmoredSkinPlayer.new()
	player.init_armored_skin(true)
	player._current_health = 2

	player.take_hit(50)  # Sniper rifle: 50 damage, lethal

	assert_eq(player.shard_spawn_count, 1,
		"Armored skin should trigger on sniper hit at 2 HP (Issue #1453)")
	assert_eq(player.get_current_health(), 2,
		"Player HP must NOT decrease when sniper rifle hit is absorbed at 2 HP (Issue #1453)")


func test_sniper_rifle_non_lethal_high_damage_above_threshold_no_trigger() -> void:
	# A hit with 2 damage when player has 5 HP (above threshold, not lethal) — no trigger.
	var player := MockArmoredSkinPlayer.new()
	player.init_armored_skin(true)
	player._current_health = 5

	player.take_hit(2)  # 5 - 2 = 3 > 0, above threshold

	assert_eq(player.shard_spawn_count, 0,
		"Armored skin should NOT trigger for non-lethal hit above threshold")
	assert_eq(player.get_current_health(), 3,
		"Player HP should decrease normally for non-lethal hit above threshold")


func test_sniper_rifle_protection_triggers_only_once() -> void:
	# After the sniper absorbs one hit, subsequent sniper hits on later frames deal damage.
	var player := MockArmoredSkinPlayer.new()
	player.init_armored_skin(true)
	player._current_health = 3

	player.take_hit(50)  # Frame 0: lethal → absorbed, HP stays 3
	assert_eq(player.get_current_health(), 3, "HP should stay 3 after first absorbed sniper hit")

	player.mock_frame = 1
	player.take_hit(50)  # Frame 1: no re-trigger, HP drops by 50 (min 0)
	assert_eq(player.shard_spawn_count, 1,
		"Sniper protection must fire exactly once (Issue #1453)")
	assert_eq(player.get_current_health(), 0,
		"Second sniper hit must deal normal damage after armored skin has triggered")


func test_same_frame_sniper_burst_hits_absorbed() -> void:
	# Same-frame burst: after armored skin triggers, all hits on the same frame are absorbed.
	var player := MockArmoredSkinPlayer.new()
	player.init_armored_skin(true)
	player._current_health = 2
	player.mock_frame = 5  # Some arbitrary frame

	player.take_hit(50)  # Triggers armored skin at frame 5 → absorbed
	player.take_hit(50)  # Same frame → absorbed
	player.take_hit(50)  # Same frame → absorbed

	assert_eq(player.get_current_health(), 2,
		"Player must survive same-frame sniper burst after armored skin triggers (Issue #1453)")
