extends GutTest
## Unit tests for EnemyArmoredSkinComponent.
##
## Tests HP_THRESHOLD, SHARD_COUNT constants, apply_hp_bonus logic,
## and trigger threshold behavior for the armored skin effect.


# ============================================================================
# Mock EnemyArmoredSkinComponent for Logic Tests
# ============================================================================


class MockEnemyArmoredSkinComponent:
	const HP_THRESHOLD: int = 2
	const SHARD_COUNT: int = 20
	const SHARD_SCENE_PATH: String = "res://scenes/projectiles/ArmoredSkinShard.tscn"
	const ARMOR_SHADER_PATH: String = "res://scripts/shaders/armored_skin.gdshader"

	var _has_triggered: bool = false
	var _trigger_frame: int = -1
	var shards_spawned: int = 0
	var armor_visual_removed: bool = false

	## Simulated physics frame counter (replaces Engine.get_physics_frames()).
	var _current_frame: int = 0

	func apply_hp_bonus(current_health: int, max_health: int) -> Array[int]:
		var new_max: int = max_health + 1
		var new_current: int = current_health + 1
		return [new_current, new_max]

	func try_spawn_shards(current_health: int, incoming_damage: int = 1) -> bool:
		if _has_triggered and _current_frame == _trigger_frame:
			return true
		if _has_triggered:
			return false
		if current_health > HP_THRESHOLD and current_health - incoming_damage > 0:
			return false
		_has_triggered = true
		_trigger_frame = _current_frame
		shards_spawned += SHARD_COUNT
		armor_visual_removed = true
		return true

	func has_triggered() -> bool:
		return _has_triggered

	func advance_frame() -> void:
		_current_frame += 1


var comp: MockEnemyArmoredSkinComponent


func before_each() -> void:
	comp = MockEnemyArmoredSkinComponent.new()


func after_each() -> void:
	comp = null


# ============================================================================
# Constants Tests
# ============================================================================


func test_hp_threshold_value() -> void:
	assert_eq(MockEnemyArmoredSkinComponent.HP_THRESHOLD, 2,
		"HP_THRESHOLD should be 2")


func test_shard_count_value() -> void:
	assert_eq(MockEnemyArmoredSkinComponent.SHARD_COUNT, 20,
		"SHARD_COUNT should be 20")


func test_shard_scene_path() -> void:
	assert_eq(MockEnemyArmoredSkinComponent.SHARD_SCENE_PATH,
		"res://scenes/projectiles/ArmoredSkinShard.tscn")


func test_armor_shader_path() -> void:
	assert_eq(MockEnemyArmoredSkinComponent.ARMOR_SHADER_PATH,
		"res://scripts/shaders/armored_skin.gdshader")


# ============================================================================
# Apply HP Bonus Tests
# ============================================================================


func test_apply_hp_bonus_adds_one_to_current() -> void:
	var result := comp.apply_hp_bonus(3, 4)

	assert_eq(result[0], 4,
		"Current health should increase by 1")


func test_apply_hp_bonus_adds_one_to_max() -> void:
	var result := comp.apply_hp_bonus(3, 4)

	assert_eq(result[1], 5,
		"Max health should increase by 1")


func test_apply_hp_bonus_returns_array_of_two() -> void:
	var result := comp.apply_hp_bonus(1, 2)

	assert_eq(result.size(), 2,
		"Should return array of [new_current, new_max]")


func test_apply_hp_bonus_with_full_health() -> void:
	var result := comp.apply_hp_bonus(5, 5)

	assert_eq(result[0], 6)
	assert_eq(result[1], 6)


func test_apply_hp_bonus_with_one_hp() -> void:
	var result := comp.apply_hp_bonus(1, 3)

	assert_eq(result[0], 2)
	assert_eq(result[1], 4)


# ============================================================================
# Trigger Threshold Tests
# ============================================================================


func test_no_trigger_when_health_above_threshold() -> void:
	var result := comp.try_spawn_shards(5)

	assert_false(result,
		"Should not trigger when health is above HP_THRESHOLD")
	assert_false(comp.has_triggered())


func test_trigger_at_threshold() -> void:
	var result := comp.try_spawn_shards(2)

	assert_true(result,
		"Should trigger when health equals HP_THRESHOLD")
	assert_true(comp.has_triggered())


func test_trigger_below_threshold() -> void:
	var result := comp.try_spawn_shards(1)

	assert_true(result,
		"Should trigger when health is below HP_THRESHOLD")


func test_trigger_spawns_shards() -> void:
	comp.try_spawn_shards(2)

	assert_eq(comp.shards_spawned, 20,
		"Should spawn SHARD_COUNT (20) shards on trigger")


func test_trigger_removes_armor_visual() -> void:
	comp.try_spawn_shards(2)

	assert_true(comp.armor_visual_removed,
		"Should remove armor visual on trigger")


func test_no_retrigger_after_first_trigger() -> void:
	comp.try_spawn_shards(2)  # First trigger
	comp.advance_frame()

	var result := comp.try_spawn_shards(1)  # Second attempt

	assert_false(result,
		"Should not trigger again after already triggered")
	assert_eq(comp.shards_spawned, 20,
		"Shard count should not increase after re-trigger attempt")


func test_same_frame_hits_absorbed() -> void:
	comp.try_spawn_shards(2)  # Trigger on frame 0

	# Same frame — should absorb
	var result := comp.try_spawn_shards(1)

	assert_true(result,
		"Same-frame hits after trigger should be absorbed")


func test_different_frame_hits_not_absorbed() -> void:
	comp.try_spawn_shards(2)  # Trigger on frame 0
	comp.advance_frame()  # Move to frame 1

	var result := comp.try_spawn_shards(1)

	assert_false(result,
		"Hits on different frames should not be absorbed after trigger")


func test_lethal_hit_triggers_above_threshold() -> void:
	# current_health=5, incoming_damage=10 → lethal hit (5-10 <= 0)
	var result := comp.try_spawn_shards(5, 10)

	assert_true(result,
		"Lethal hit should trigger even when health > HP_THRESHOLD")


func test_non_lethal_high_damage_above_threshold_no_trigger() -> void:
	# current_health=5, incoming_damage=2 → 5-2=3 > 0, still above threshold
	var result := comp.try_spawn_shards(5, 2)

	assert_false(result,
		"Non-lethal hit above HP_THRESHOLD should not trigger")


func test_not_triggered_by_default() -> void:
	assert_false(comp.has_triggered(),
		"Should not be triggered by default")
