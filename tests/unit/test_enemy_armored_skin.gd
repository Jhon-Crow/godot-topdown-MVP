extends GutTest
## Unit tests for the enemy Armored Skin passive item (Issue #1123).
##
## Tests the EnemyArmoredSkinComponent logic:
## - +1 HP bonus applied at spawn
## - Glass shards spawn when hit at ≤2 HP (exactly once — Issue #1143)
## - Shards do NOT spawn above the threshold
## - Armor visual is removed when shards spawn (Issue #1143)


# ============================================================================
# Mock EnemyArmoredSkinComponent (mirrors the real component logic)
# ============================================================================


class MockEnemyArmoredSkinComponent:
	const HP_THRESHOLD: int = 2
	const SHARD_COUNT: int = 20

	## Number of shard spawns triggered during the test.
	var shard_spawn_count: int = 0
	## Whether armor visual was removed (simulates _remove_armor_visual).
	var armor_visual_removed: bool = false
	## True after shards have been spawned — prevents re-triggering (Issue #1143).
	var _has_triggered: bool = false

	func apply_hp_bonus(current_health: int, max_health: int) -> Array[int]:
		return [current_health + 1, max_health + 1]

	func try_spawn_shards(current_health: int) -> bool:
		if _has_triggered:
			return false
		if current_health <= HP_THRESHOLD:
			_has_triggered = true
			shard_spawn_count += 1
			armor_visual_removed = true
			return true
		return false


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
			# Issue #1143: absorb the triggering hit when shards spawn
			if _component.try_spawn_shards(_current_health):
				return
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


func test_shards_spawn_only_once_at_low_hp() -> void:
	# Issue #1143: Armored Skin triggers exactly once — enemy is not immortal.
	_component.try_spawn_shards(2)
	_component.try_spawn_shards(1)
	assert_eq(_component.shard_spawn_count, 1,
		"Shards should spawn only once — re-triggering must be prevented (Issue #1143)")


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


# ============================================================================
# Damage absorption tests (Issue #1143)
# ============================================================================


func test_try_spawn_shards_returns_true_at_threshold() -> void:
	var absorbed := _component.try_spawn_shards(2)
	assert_true(absorbed,
		"try_spawn_shards should return true (damage absorbed) when HP <= threshold")


func test_try_spawn_shards_returns_true_at_1hp() -> void:
	var absorbed := _component.try_spawn_shards(1)
	assert_true(absorbed,
		"try_spawn_shards should return true (damage absorbed) when HP is 1")


func test_try_spawn_shards_returns_false_above_threshold() -> void:
	var absorbed := _component.try_spawn_shards(3)
	assert_false(absorbed,
		"try_spawn_shards should return false (damage applied) when HP > threshold")


func test_triggering_hit_damage_absorbed_at_2hp() -> void:
	# Issue #1143: the hit that triggers shards must not reduce enemy HP.
	var enemy := MockArmoredSkinEnemy.new()
	enemy.setup(3, 3)
	enemy.add_armored_skin()
	enemy._current_health = 2
	enemy.take_hit()
	assert_eq(enemy._current_health, 2,
		"Enemy HP must NOT decrease when the triggering hit is absorbed by Armored Skin")


func test_triggering_hit_damage_absorbed_at_1hp() -> void:
	# Issue #1143: even at 1 HP the triggering hit is absorbed.
	var enemy := MockArmoredSkinEnemy.new()
	enemy.setup(3, 3)
	enemy.add_armored_skin()
	enemy._current_health = 1
	enemy.take_hit()
	assert_eq(enemy._current_health, 1,
		"Enemy HP must NOT decrease when armored skin absorbs the triggering hit at 1 HP")


func test_damage_applied_above_threshold() -> void:
	# Hits above the threshold are NOT absorbed.
	var enemy := MockArmoredSkinEnemy.new()
	enemy.setup(4, 4)
	enemy.add_armored_skin()
	# Enemy has 5 HP. Hit at 5 HP (above threshold of 2).
	var hp_before := enemy._current_health
	enemy.take_hit()
	assert_eq(enemy._current_health, hp_before - 1,
		"Enemy HP should decrease normally when hit above armored skin threshold")


func test_damage_applied_without_armored_skin() -> void:
	# No component → damage always applied.
	var enemy := MockArmoredSkinEnemy.new()
	enemy.setup(3, 3)
	enemy._current_health = 2
	enemy.take_hit()
	assert_eq(enemy._current_health, 1,
		"Enemy HP should decrease normally when armored skin is not equipped")


# ============================================================================
# Re-trigger prevention tests (Issue #1143)
# ============================================================================


func test_second_hit_at_low_hp_applies_damage() -> void:
	# After Armored Skin triggers once, subsequent hits must reduce HP normally.
	var enemy := MockArmoredSkinEnemy.new()
	enemy.setup(3, 3)
	enemy.add_armored_skin()
	enemy._current_health = 2
	enemy.take_hit()  # First hit: triggers shards, absorbs damage → HP stays 2
	assert_eq(enemy._current_health, 2, "HP should be 2 after first (absorbed) hit")
	enemy.take_hit()  # Second hit: no re-trigger, damage applied → HP goes to 1
	assert_eq(enemy._current_health, 1,
		"HP should decrease on second hit — Armored Skin must not re-trigger")


func test_shards_spawn_exactly_once_on_repeated_hits() -> void:
	# The component must never fire shards more than once.
	_component.try_spawn_shards(2)  # triggers
	_component.try_spawn_shards(1)  # must be blocked
	_component.try_spawn_shards(1)  # must be blocked
	assert_eq(_component.shard_spawn_count, 1,
		"Shards must spawn exactly once regardless of how many low-HP hits follow")


func test_armor_visual_removed_on_trigger() -> void:
	# When shards spawn the armor shader overlay must be removed (Issue #1143).
	_component.try_spawn_shards(2)
	assert_true(_component.armor_visual_removed,
		"Armor visual should be removed when Armored Skin shards are spawned")


func test_armor_visual_not_removed_above_threshold() -> void:
	# Armor shader stays if the hit does not trigger the effect.
	_component.try_spawn_shards(3)
	assert_false(_component.armor_visual_removed,
		"Armor visual should remain when HP is above threshold (effect not triggered)")


func test_armor_visual_not_removed_on_second_trigger_attempt() -> void:
	# Shader was already removed on first trigger — second attempt should be a no-op.
	_component.try_spawn_shards(2)  # first trigger: removes visual
	_component.armor_visual_removed = false  # reset flag to detect spurious removal
	_component.try_spawn_shards(1)  # should do nothing
	assert_false(_component.armor_visual_removed,
		"Armor visual removal must not fire again after Armored Skin already triggered")
