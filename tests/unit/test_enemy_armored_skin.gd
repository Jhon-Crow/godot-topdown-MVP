extends GutTest
## Unit tests for the enemy Armored Skin passive item (Issue #1123).
##
## Tests the EnemyArmoredSkinComponent logic:
## - +1 HP bonus applied at spawn
## - Glass shards spawn when hit at ≤2 HP
## - Shards do NOT spawn above the threshold


# ============================================================================
# Mock EnemyArmoredSkinComponent (mirrors the real component logic)
# ============================================================================


class MockEnemyArmoredSkinComponent:
	const HP_THRESHOLD: int = 2
	const SHARD_COUNT: int = 20

	## Number of shard spawns triggered during the test.
	var shard_spawn_count: int = 0

	func apply_hp_bonus(current_health: int, max_health: int) -> Array[int]:
		return [current_health + 1, max_health + 1]

	func try_spawn_shards(current_health: int) -> void:
		if current_health <= HP_THRESHOLD:
			shard_spawn_count += 1


# ============================================================================
# Mock enemy using the component
# ============================================================================


class MockArmoredSkinEnemy:
	var _current_health: int = 0
	var _max_health: int = 0
	var _component: MockEnemyArmoredSkinComponent = null

	func setup(base_min_hp: int, base_max_hp: int) -> void:
		_max_health = randi_range(base_min_hp, base_max_hp)
		_current_health = _max_health

	func add_armored_skin() -> void:
		_component = MockEnemyArmoredSkinComponent.new()
		var result: Array[int] = _component.apply_hp_bonus(_current_health, _max_health)
		_current_health = result[0]
		_max_health = result[1]

	func take_hit() -> void:
		if _component:
			_component.try_spawn_shards(_current_health)
		_current_health -= 1
		if _current_health < 0:
			_current_health = 0

	func get_shard_spawn_count() -> int:
		if _component:
			return _component.shard_spawn_count
		return 0


var _component: MockEnemyArmoredSkinComponent


func before_each() -> void:
	_component = MockEnemyArmoredSkinComponent.new()


func after_each() -> void:
	_component = null


# ============================================================================
# HP Bonus Tests
# ============================================================================


func test_hp_bonus_increases_max_health_by_1() -> void:
	var result := _component.apply_hp_bonus(3, 3)
	assert_eq(result[1], 4, "max_health should increase by 1")


func test_hp_bonus_increases_current_health_by_1() -> void:
	var result := _component.apply_hp_bonus(3, 3)
	assert_eq(result[0], 4, "current_health should increase by 1")


func test_hp_bonus_at_minimum_health() -> void:
	var result := _component.apply_hp_bonus(2, 2)
	assert_eq(result[0], 3, "current_health should be 3 after bonus at base 2 HP")
	assert_eq(result[1], 3, "max_health should be 3 after bonus at base 2 HP")


func test_hp_bonus_applied_to_enemy() -> void:
	var enemy := MockArmoredSkinEnemy.new()
	enemy.setup(3, 3)
	var base_max := enemy._max_health
	enemy.add_armored_skin()
	assert_eq(enemy._max_health, base_max + 1,
		"Enemy max_health should increase by 1 when armored skin is added")


func test_hp_current_equals_max_after_bonus() -> void:
	var enemy := MockArmoredSkinEnemy.new()
	enemy.setup(4, 4)
	enemy.add_armored_skin()
	assert_eq(enemy._current_health, enemy._max_health,
		"current_health should equal max_health after bonus")


# ============================================================================
# Shard Spawn Threshold Tests
# ============================================================================


func test_shards_spawn_at_exactly_2hp() -> void:
	_component.try_spawn_shards(2)
	assert_eq(_component.shard_spawn_count, 1, "Shards should spawn at 2 HP")


func test_shards_spawn_at_1hp() -> void:
	_component.try_spawn_shards(1)
	assert_eq(_component.shard_spawn_count, 1, "Shards should spawn at 1 HP")


func test_shards_do_not_spawn_at_3hp() -> void:
	_component.try_spawn_shards(3)
	assert_eq(_component.shard_spawn_count, 0, "Shards should NOT spawn at 3 HP")


func test_shards_do_not_spawn_at_5hp() -> void:
	_component.try_spawn_shards(5)
	assert_eq(_component.shard_spawn_count, 0, "Shards should NOT spawn at 5 HP")


func test_shards_spawn_multiple_times_at_low_hp() -> void:
	_component.try_spawn_shards(2)
	_component.try_spawn_shards(1)
	assert_eq(_component.shard_spawn_count, 2,
		"Shards should spawn on each hit at or below threshold")


func test_shard_count_constant_is_20() -> void:
	assert_eq(_component.SHARD_COUNT, 20,
		"Armored skin enemy should spawn exactly 20 shards")


func test_hp_threshold_constant_is_2() -> void:
	assert_eq(_component.HP_THRESHOLD, 2,
		"HP threshold for shard spawn should be 2")


# ============================================================================
# Integration-style mock: enemy uses component on each hit
# ============================================================================


func test_enemy_shards_triggered_when_hit_at_2hp() -> void:
	var enemy := MockArmoredSkinEnemy.new()
	enemy.setup(3, 3)
	enemy.add_armored_skin()
	# Enemy now has 4 HP due to bonus. Manually lower to 2 HP.
	enemy._current_health = 2
	enemy.take_hit()
	assert_eq(enemy.get_shard_spawn_count(), 1,
		"Shards should spawn when armored-skin enemy is hit at 2 HP")


func test_enemy_no_shards_triggered_when_hit_at_4hp() -> void:
	var enemy := MockArmoredSkinEnemy.new()
	enemy.setup(4, 4)
	enemy.add_armored_skin()
	# Enemy now has 5 HP due to bonus.
	enemy.take_hit()  # HP goes from 5 → 4 (above threshold)
	assert_eq(enemy.get_shard_spawn_count(), 0,
		"Shards should NOT spawn when armored-skin enemy is hit above threshold")


func test_enemy_no_shards_without_component() -> void:
	var enemy := MockArmoredSkinEnemy.new()
	enemy.setup(3, 3)
	# No armored skin added.
	enemy._current_health = 2
	enemy.take_hit()
	assert_eq(enemy.get_shard_spawn_count(), 0,
		"Shards should NOT spawn when armored skin is not equipped")
