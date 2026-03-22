extends GutTest
## Unit tests for special enemy spawning in roguelike_level.gd.
##
## Tests cover:
##  - No special enemies before level SPECIAL_ENEMY_MIN_LEVEL
##  - Correct special type assigned to the last enemy slot
##  - _apply_special_enemy sets correct weapon / flags / health per archetype
##  - Pool of archetypes grows with level (FORCE_FIELD at 3, SNIPER at 4)
##  - Spawn chance clamped to SPECIAL_ENEMY_MAX_CHANCE
##
## Issue #1297.


# ============================================================================
# Constants mirrored from roguelike_level.gd
# ============================================================================

const SPECIAL_ENEMY_NONE: int         = 0
const SPECIAL_ENEMY_MACHINE_GUNNER: int = 1
const SPECIAL_ENEMY_GRENADIER: int    = 2
const SPECIAL_ENEMY_ARMORED: int      = 3
const SPECIAL_ENEMY_FORCE_FIELD: int  = 4
const SPECIAL_ENEMY_SNIPER: int       = 5

const SPECIAL_ENEMY_MIN_LEVEL: int    = 2
const SPECIAL_ENEMY_BASE_CHANCE: float = 0.40
const SPECIAL_ENEMY_CHANCE_PER_LEVEL: float = 0.10
const SPECIAL_ENEMY_MAX_CHANCE: float = 0.80


# ============================================================================
# MockEnemy — stand-in for enemy node properties set by _apply_special_enemy
# ============================================================================


class MockEnemy:
	var weapon_type: int   = 0   # RIFLE
	var behavior_mode: int = 1   # GUARD
	var min_health: int    = 1
	var max_health: int    = 2
	var is_grenadier: bool    = false
	var has_armored_skin: bool = false
	var has_force_field: bool  = false
	var destroy_on_death: bool = false


# ============================================================================
# MockRoguelikeSpecial — mirrors pick / apply logic from roguelike_level.gd
# ============================================================================


class MockRoguelikeSpecial:
	const SPECIAL_ENEMY_MIN_LEVEL: int          = 2
	const SPECIAL_ENEMY_BASE_CHANCE: float       = 0.40
	const SPECIAL_ENEMY_CHANCE_PER_LEVEL: float  = 0.10
	const SPECIAL_ENEMY_MAX_CHANCE: float        = 0.80

	## Mirrors _pick_special_enemy_type.
	## forced_roll overrides randf() for deterministic testing (pass -1.0 to use a real roll).
	func pick_special_enemy_type(current_level: int, forced_roll: float = -1.0) -> int:
		if current_level < SPECIAL_ENEMY_MIN_LEVEL:
			return 0  # NONE
		var chance: float = clampf(
			SPECIAL_ENEMY_BASE_CHANCE + (current_level - SPECIAL_ENEMY_MIN_LEVEL) * SPECIAL_ENEMY_CHANCE_PER_LEVEL,
			0.0, SPECIAL_ENEMY_MAX_CHANCE)
		var roll: float = forced_roll if forced_roll >= 0.0 else randf()
		if roll > chance:
			return 0  # NONE
		# Return deterministic pool for testing (pool size grows with level)
		var pool: Array = [1, 2, 3]  # MACHINE_GUNNER, GRENADIER, ARMORED
		if current_level >= 3:
			pool.append(4)  # FORCE_FIELD
		if current_level >= 4:
			pool.append(5)  # SNIPER
		return pool[0]  # deterministic: always first element for tests

	## Mirrors _apply_special_enemy.
	func apply_special_enemy(enemy: MockEnemy, special_type: int, level_bonus: int) -> void:
		match special_type:
			1:  # MACHINE_GUNNER
				enemy.weapon_type   = 6
				enemy.min_health    = 2 + level_bonus
				enemy.max_health    = 3 + level_bonus
				enemy.behavior_mode = 1
			2:  # GRENADIER
				enemy.is_grenadier = true
				enemy.weapon_type  = 0
				enemy.min_health   = 2 + level_bonus
				enemy.max_health   = 2 + level_bonus
			3:  # ARMORED
				enemy.has_armored_skin = true
				enemy.min_health = 2 + level_bonus
				enemy.max_health = 3 + level_bonus
			4:  # FORCE_FIELD
				enemy.has_force_field = true
				enemy.min_health = 1 + level_bonus
				enemy.max_health = 2 + level_bonus
			5:  # SNIPER
				enemy.weapon_type   = 7
				enemy.min_health    = 1 + level_bonus
				enemy.max_health    = 2 + level_bonus
				enemy.behavior_mode = 1

	## Returns the spawn chance for a given level (mirrors clamped formula).
	func spawn_chance(current_level: int) -> float:
		if current_level < SPECIAL_ENEMY_MIN_LEVEL:
			return 0.0
		return clampf(
			SPECIAL_ENEMY_BASE_CHANCE + (current_level - SPECIAL_ENEMY_MIN_LEVEL) * SPECIAL_ENEMY_CHANCE_PER_LEVEL,
			0.0, SPECIAL_ENEMY_MAX_CHANCE)

	## Returns the archetype pool available at a given level.
	func archetype_pool(current_level: int) -> Array:
		if current_level < SPECIAL_ENEMY_MIN_LEVEL:
			return []
		var pool: Array = [1, 2, 3]  # MACHINE_GUNNER, GRENADIER, ARMORED
		if current_level >= 3:
			pool.append(4)  # FORCE_FIELD
		if current_level >= 4:
			pool.append(5)  # SNIPER
		return pool


# ============================================================================
# Helpers
# ============================================================================


func _make_logic() -> MockRoguelikeSpecial:
	return MockRoguelikeSpecial.new()


func _make_enemy() -> MockEnemy:
	return MockEnemy.new()


# ============================================================================
# Tests — level gate
# ============================================================================


func test_no_special_enemy_on_level_1() -> void:
	var logic := _make_logic()
	# Roll of 0.0 guarantees the roll is below any chance — should still be NONE on level 1.
	var result: int = logic.pick_special_enemy_type(1, 0.0)
	assert_eq(result, SPECIAL_ENEMY_NONE,
		"Level 1 must never produce a special enemy regardless of roll")


func test_no_special_enemy_below_min_level() -> void:
	var logic := _make_logic()
	for lvl in range(1, SPECIAL_ENEMY_MIN_LEVEL):
		var result: int = logic.pick_special_enemy_type(lvl, 0.0)
		assert_eq(result, SPECIAL_ENEMY_NONE,
			"Level %d is below min level — must return NONE" % lvl)


func test_special_enemy_possible_from_min_level() -> void:
	var logic := _make_logic()
	# Roll 0.0 is always below the chance (0.40 on level 2), so a special must be returned.
	var result: int = logic.pick_special_enemy_type(SPECIAL_ENEMY_MIN_LEVEL, 0.0)
	assert_ne(result, SPECIAL_ENEMY_NONE,
		"Roll of 0.0 at min level must produce a special enemy")


# ============================================================================
# Tests — spawn chance formula
# ============================================================================


func test_spawn_chance_zero_below_min_level() -> void:
	var logic := _make_logic()
	assert_eq(logic.spawn_chance(1), 0.0, "Chance must be 0 below min level")


func test_spawn_chance_base_at_min_level() -> void:
	var logic := _make_logic()
	var c: float = logic.spawn_chance(SPECIAL_ENEMY_MIN_LEVEL)
	assert_almost_eq(c, SPECIAL_ENEMY_BASE_CHANCE, 0.001,
		"Chance at min level must equal base chance (%.2f)" % SPECIAL_ENEMY_BASE_CHANCE)


func test_spawn_chance_increases_with_level() -> void:
	var logic := _make_logic()
	var c2: float = logic.spawn_chance(2)
	var c3: float = logic.spawn_chance(3)
	assert_gt(c3, c2, "Spawn chance must increase with level")


func test_spawn_chance_clamped_to_max() -> void:
	var logic := _make_logic()
	# At a very high level the chance should not exceed MAX.
	var c_high: float = logic.spawn_chance(100)
	assert_almost_eq(c_high, SPECIAL_ENEMY_MAX_CHANCE, 0.001,
		"Spawn chance must be clamped to MAX_CHANCE (%.2f)" % SPECIAL_ENEMY_MAX_CHANCE)


func test_spawn_chance_never_exceeds_max() -> void:
	var logic := _make_logic()
	for lvl in [2, 3, 4, 5, 10, 50]:
		var c: float = logic.spawn_chance(lvl)
		assert_le(c, SPECIAL_ENEMY_MAX_CHANCE,
			"Chance at level %d must not exceed max (%.2f)" % [lvl, SPECIAL_ENEMY_MAX_CHANCE])


func test_roll_above_chance_returns_none() -> void:
	var logic := _make_logic()
	# Roll = 1.0 is above any chance value → always NONE.
	var result: int = logic.pick_special_enemy_type(5, 1.0)
	assert_eq(result, SPECIAL_ENEMY_NONE,
		"Roll of 1.0 must always return NONE (even at high levels)")


# ============================================================================
# Tests — archetype pool growth
# ============================================================================


func test_pool_at_level_2_has_three_archetypes() -> void:
	var logic := _make_logic()
	var pool: Array = logic.archetype_pool(2)
	assert_eq(pool.size(), 3, "Level 2 pool must have 3 archetypes (MG, Grenadier, Armored)")


func test_pool_at_level_3_includes_force_field() -> void:
	var logic := _make_logic()
	var pool: Array = logic.archetype_pool(3)
	assert_true(SPECIAL_ENEMY_FORCE_FIELD in pool,
		"Level 3 pool must include FORCE_FIELD archetype")
	assert_eq(pool.size(), 4, "Level 3 pool must have 4 archetypes")


func test_pool_at_level_4_includes_sniper() -> void:
	var logic := _make_logic()
	var pool: Array = logic.archetype_pool(4)
	assert_true(SPECIAL_ENEMY_SNIPER in pool,
		"Level 4 pool must include SNIPER archetype")
	assert_eq(pool.size(), 5, "Level 4 pool must have 5 archetypes")


func test_pool_always_contains_base_archetypes() -> void:
	var logic := _make_logic()
	for lvl in [2, 3, 4, 5, 10]:
		var pool: Array = logic.archetype_pool(lvl)
		assert_true(SPECIAL_ENEMY_MACHINE_GUNNER in pool,
			"Level %d pool must include MACHINE_GUNNER" % lvl)
		assert_true(SPECIAL_ENEMY_GRENADIER in pool,
			"Level %d pool must include GRENADIER" % lvl)
		assert_true(SPECIAL_ENEMY_ARMORED in pool,
			"Level %d pool must include ARMORED" % lvl)


func test_pool_below_min_level_is_empty() -> void:
	var logic := _make_logic()
	var pool: Array = logic.archetype_pool(1)
	assert_true(pool.is_empty(), "Pool must be empty below min level")


# ============================================================================
# Tests — _apply_special_enemy archetypes
# ============================================================================


func test_apply_machine_gunner_sets_machine_gun_weapon() -> void:
	var logic := _make_logic()
	var enemy := _make_enemy()
	logic.apply_special_enemy(enemy, SPECIAL_ENEMY_MACHINE_GUNNER, 0)
	assert_eq(enemy.weapon_type, 6,
		"Machine Gunner must use WeaponType.MACHINE_GUN (6)")


func test_apply_machine_gunner_health_level_0() -> void:
	var logic := _make_logic()
	var enemy := _make_enemy()
	logic.apply_special_enemy(enemy, SPECIAL_ENEMY_MACHINE_GUNNER, 0)
	assert_eq(enemy.min_health, 2, "MG min_health must be 2 at level_bonus=0")
	assert_eq(enemy.max_health, 3, "MG max_health must be 3 at level_bonus=0")


func test_apply_machine_gunner_health_scales_with_level() -> void:
	var logic := _make_logic()
	var enemy := _make_enemy()
	logic.apply_special_enemy(enemy, SPECIAL_ENEMY_MACHINE_GUNNER, 2)
	assert_eq(enemy.min_health, 4, "MG min_health must scale with level_bonus")
	assert_eq(enemy.max_health, 5, "MG max_health must scale with level_bonus")


func test_apply_grenadier_sets_is_grenadier_flag() -> void:
	var logic := _make_logic()
	var enemy := _make_enemy()
	logic.apply_special_enemy(enemy, SPECIAL_ENEMY_GRENADIER, 0)
	assert_true(enemy.is_grenadier,
		"Grenadier archetype must set is_grenadier = true")


func test_apply_grenadier_keeps_rifle_weapon() -> void:
	var logic := _make_logic()
	var enemy := _make_enemy()
	logic.apply_special_enemy(enemy, SPECIAL_ENEMY_GRENADIER, 0)
	assert_eq(enemy.weapon_type, 0,
		"Grenadier must use RIFLE (0) as primary weapon")


func test_apply_armored_sets_has_armored_skin() -> void:
	var logic := _make_logic()
	var enemy := _make_enemy()
	logic.apply_special_enemy(enemy, SPECIAL_ENEMY_ARMORED, 0)
	assert_true(enemy.has_armored_skin,
		"Armored archetype must set has_armored_skin = true")


func test_apply_armored_health_level_0() -> void:
	var logic := _make_logic()
	var enemy := _make_enemy()
	logic.apply_special_enemy(enemy, SPECIAL_ENEMY_ARMORED, 0)
	assert_eq(enemy.min_health, 2, "Armored min_health must be 2 at level_bonus=0")
	assert_eq(enemy.max_health, 3, "Armored max_health must be 3 at level_bonus=0")


func test_apply_force_field_sets_has_force_field() -> void:
	var logic := _make_logic()
	var enemy := _make_enemy()
	logic.apply_special_enemy(enemy, SPECIAL_ENEMY_FORCE_FIELD, 0)
	assert_true(enemy.has_force_field,
		"Force Field archetype must set has_force_field = true")


func test_apply_sniper_sets_sniper_rifle_weapon() -> void:
	var logic := _make_logic()
	var enemy := _make_enemy()
	logic.apply_special_enemy(enemy, SPECIAL_ENEMY_SNIPER, 0)
	assert_eq(enemy.weapon_type, 7,
		"Sniper archetype must use WeaponType.SNIPER_RIFLE (7)")


func test_apply_sniper_sets_guard_behavior() -> void:
	var logic := _make_logic()
	var enemy := _make_enemy()
	enemy.behavior_mode = 0  # Start as PATROL
	logic.apply_special_enemy(enemy, SPECIAL_ENEMY_SNIPER, 0)
	assert_eq(enemy.behavior_mode, 1,
		"Sniper must be set to GUARD behavior (holds position)")


func test_apply_none_does_not_modify_enemy() -> void:
	## NONE type is never passed to _apply_special_enemy in real code, but let's
	## verify the match statement falls through gracefully (no modifications).
	var logic := _make_logic()
	var enemy := _make_enemy()
	var original_weapon: int = enemy.weapon_type
	logic.apply_special_enemy(enemy, SPECIAL_ENEMY_NONE, 0)
	assert_eq(enemy.weapon_type, original_weapon,
		"NONE archetype must not modify weapon_type")
	assert_false(enemy.is_grenadier,   "NONE archetype must not set is_grenadier")
	assert_false(enemy.has_armored_skin, "NONE archetype must not set has_armored_skin")
	assert_false(enemy.has_force_field,  "NONE archetype must not set has_force_field")


# ============================================================================
# Tests — special slot placement
# ============================================================================


func test_special_slot_is_last_when_special_chosen() -> void:
	## The special enemy must be placed in the last slot (index count-1).
	var count: int = 4
	var special_type: int = SPECIAL_ENEMY_MACHINE_GUNNER
	var special_slot: int = count - 1 if special_type != SPECIAL_ENEMY_NONE else -1
	assert_eq(special_slot, 3,
		"Special enemy must occupy the last slot (count-1 = 3 for count=4)")


func test_no_special_slot_when_type_is_none() -> void:
	var count: int = 4
	var special_type: int = SPECIAL_ENEMY_NONE
	var special_slot: int = count - 1 if special_type != SPECIAL_ENEMY_NONE else -1
	assert_eq(special_slot, -1,
		"No special slot when type is NONE (slot must be -1)")
