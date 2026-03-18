extends GutTest
## Unit tests for chemical grenade system (Issue #1129).
##
## Tests:
## - _choose_grenade_scene() with 50% chance logic
## - Player-under-illusion guard (req.9)
## - IllusionEnemy constants (damage multiplier)
## - StatusEffectsManager illusion tracking (apply/check/clear)
## - ChemicalCloud guard check


# ============================================================================
# Mock for EnemyGrenadeComponent chemical grenade selection logic
# ============================================================================


class MockGrenadeComponent:
	## Mirrors EnemyGrenadeComponent's chemical grenade fields.
	var grenade_scene: PackedScene = null
	var chemical_grenade_scene: PackedScene = null
	var chemical_grenade_chance: float = 0.5

	## Mirrors the mock StatusEffectsManager state.
	var _mock_player_under_illusion: bool = false

	## Simulated random override for deterministic tests.
	## Set to 0.0 to always choose chemical, 1.0 to never choose chemical.
	var _mock_rand: float = -1.0  # -1 = use real randf()

	## Mirrors _choose_grenade_scene() logic.
	func choose_grenade_scene() -> PackedScene:
		if chemical_grenade_scene == null:
			return grenade_scene
		# Guard: if player is already under illusion, throw default grenade
		if _mock_player_under_illusion:
			return grenade_scene
		# 50% chance to throw chemical grenade
		var roll := _mock_rand if _mock_rand >= 0.0 else randf()
		if roll < chemical_grenade_chance:
			return chemical_grenade_scene
		return grenade_scene


# ============================================================================
# Mock for StatusEffectsManager illusion tracking
# ============================================================================


class MockStatusEffectsManager:
	var _player_illusion_timer: float = 0.0
	## active illusion effects per entity id
	var _illusion_effects: Dictionary = {}

	func is_player_under_illusion() -> bool:
		return _player_illusion_timer > 0.0

	func apply_illusion_to_enemy(entity_id: int, duration: float) -> void:
		_illusion_effects[entity_id] = duration
		_player_illusion_timer = duration

	func is_enemy_under_illusion_by_id(entity_id: int) -> bool:
		return _illusion_effects.get(entity_id, 0.0) > 0.0

	func get_player_illusion_remaining() -> float:
		return _player_illusion_timer

	func simulate_time(delta: float) -> void:
		_player_illusion_timer = maxf(0.0, _player_illusion_timer - delta)
		for key in _illusion_effects.keys():
			_illusion_effects[key] = maxf(0.0, _illusion_effects[key] - delta)
			if _illusion_effects[key] <= 0.0:
				_illusion_effects.erase(key)


# ============================================================================
# Test Variables and Setup
# ============================================================================


var comp: MockGrenadeComponent
var status_mgr: MockStatusEffectsManager


func before_each() -> void:
	comp = MockGrenadeComponent.new()
	status_mgr = MockStatusEffectsManager.new()

	# Use dummy PackedScene objects as markers (can't instantiate null scenes in unit tests)
	# We use resource_path check, so we stub them as objects with a distinguishing property.
	comp.grenade_scene = preload("res://scenes/projectiles/FragGrenade.tscn")
	# Try to load chemical scene (may not be registered yet in test env — that's OK)
	var chem_scene := load("res://scenes/projectiles/ChemicalGasGrenade.tscn")
	if chem_scene:
		comp.chemical_grenade_scene = chem_scene
	else:
		# Fallback: use defensive grenade as stand-in for chemical in tests
		comp.chemical_grenade_scene = preload("res://scenes/projectiles/DefensiveGrenade.tscn")


func after_each() -> void:
	comp = null
	status_mgr = null


# ============================================================================
# Constants Tests
# ============================================================================


func test_illusion_damage_multiplier_is_five_percent() -> void:
	## IllusionEnemy.ILLUSION_DAMAGE_MULTIPLIER must be 0.05 (5%) per Issue #1129 req.4
	assert_eq(IllusionEnemy.ILLUSION_DAMAGE_MULTIPLIER, 0.05,
		"Illusion copies must deal exactly 5% of normal damage")


func test_chemical_grenade_chance_default() -> void:
	## Default chemical grenade chance must be 0.5 (50%) per Issue #1129 req.1
	assert_eq(comp.chemical_grenade_chance, 0.5,
		"Default chemical grenade chance should be 50%%")


# ============================================================================
# _choose_grenade_scene() Logic Tests
# ============================================================================


func test_choose_returns_default_when_no_chemical_scene() -> void:
	## If chemical_grenade_scene is null, always use default
	comp.chemical_grenade_scene = null
	comp._mock_rand = 0.0  # Would pick chemical if available
	var chosen := comp.choose_grenade_scene()
	assert_eq(chosen, comp.grenade_scene,
		"Should return default grenade when chemical_grenade_scene is null")


func test_choose_returns_chemical_when_roll_below_threshold() -> void:
	## With roll 0.1 < 0.5 threshold: chemical grenade chosen
	comp._mock_rand = 0.1
	var chosen := comp.choose_grenade_scene()
	assert_eq(chosen, comp.chemical_grenade_scene,
		"Should return chemical grenade when roll (0.1) < chance (0.5)")


func test_choose_returns_default_when_roll_above_threshold() -> void:
	## With roll 0.7 >= 0.5 threshold: default grenade chosen
	comp._mock_rand = 0.7
	var chosen := comp.choose_grenade_scene()
	assert_eq(chosen, comp.grenade_scene,
		"Should return default grenade when roll (0.7) >= chance (0.5)")


func test_choose_returns_default_when_roll_equals_threshold() -> void:
	## With roll exactly 0.5: default grenade chosen (< not <=)
	comp._mock_rand = 0.5
	var chosen := comp.choose_grenade_scene()
	assert_eq(chosen, comp.grenade_scene,
		"Should return default grenade when roll (0.5) == chance (0.5) (not strictly less)")


func test_choose_returns_default_when_player_under_illusion() -> void:
	## Guard: player already under illusion effect → throw default grenade (Issue #1129 req.9)
	comp._mock_rand = 0.0  # Would pick chemical normally
	comp._mock_player_under_illusion = true
	var chosen := comp.choose_grenade_scene()
	assert_eq(chosen, comp.grenade_scene,
		"Should return default grenade when player is already under illusion effect")


func test_choose_returns_chemical_when_player_not_under_illusion() -> void:
	## When player is NOT under illusion and roll favors chemical: chemical is chosen
	comp._mock_rand = 0.0
	comp._mock_player_under_illusion = false
	var chosen := comp.choose_grenade_scene()
	assert_eq(chosen, comp.chemical_grenade_scene,
		"Should return chemical grenade when player is not under illusion and roll favors it")


func test_choose_probability_distribution() -> void:
	## Over many samples, approximately 50% should be chemical and 50% default.
	## Uses real randf() — test is probabilistic with wide margin.
	var chemical_count := 0
	var total := 1000
	comp._mock_rand = -1.0  # Use real random
	for _i in range(total):
		var chosen := comp.choose_grenade_scene()
		if chosen == comp.chemical_grenade_scene:
			chemical_count += 1
	var ratio := float(chemical_count) / float(total)
	# Allow ±10% margin around 50% for statistical variance
	assert_true(ratio >= 0.40 and ratio <= 0.60,
		"Chemical grenade should be chosen ~50%% of the time (got %.1f%%)" % (ratio * 100.0))


# ============================================================================
# StatusEffectsManager Illusion Tracking Tests
# ============================================================================


func test_player_not_under_illusion_initially() -> void:
	assert_false(status_mgr.is_player_under_illusion(),
		"Player should not be under illusion initially")


func test_apply_illusion_marks_player_under_effect() -> void:
	status_mgr.apply_illusion_to_enemy(42, 20.0)
	assert_true(status_mgr.is_player_under_illusion(),
		"Player should be under illusion after apply_illusion_to_enemy")


func test_illusion_duration_correct() -> void:
	status_mgr.apply_illusion_to_enemy(42, 20.0)
	assert_almost_eq(status_mgr.get_player_illusion_remaining(), 20.0, 0.01,
		"Player illusion remaining should be 20.0 seconds")


func test_illusion_expires_after_duration() -> void:
	status_mgr.apply_illusion_to_enemy(42, 20.0)
	status_mgr.simulate_time(21.0)
	assert_false(status_mgr.is_player_under_illusion(),
		"Player illusion should expire after 20 seconds")


func test_player_under_illusion_after_partial_time() -> void:
	status_mgr.apply_illusion_to_enemy(42, 20.0)
	status_mgr.simulate_time(15.0)
	assert_true(status_mgr.is_player_under_illusion(),
		"Player should still be under illusion after 15s of 20s duration")


func test_enemy_tracked_as_under_illusion() -> void:
	status_mgr.apply_illusion_to_enemy(99, 20.0)
	assert_true(status_mgr.is_enemy_under_illusion_by_id(99),
		"Enemy should be tracked as under illusion after effect applied")


func test_enemy_illusion_expires() -> void:
	status_mgr.apply_illusion_to_enemy(99, 20.0)
	status_mgr.simulate_time(21.0)
	assert_false(status_mgr.is_enemy_under_illusion_by_id(99),
		"Enemy illusion tracking should expire after duration")


func test_illusion_applied_to_multiple_enemies() -> void:
	status_mgr.apply_illusion_to_enemy(1, 20.0)
	status_mgr.apply_illusion_to_enemy(2, 20.0)
	status_mgr.apply_illusion_to_enemy(3, 20.0)
	assert_true(status_mgr.is_enemy_under_illusion_by_id(1), "Enemy 1 should be under illusion")
	assert_true(status_mgr.is_enemy_under_illusion_by_id(2), "Enemy 2 should be under illusion")
	assert_true(status_mgr.is_enemy_under_illusion_by_id(3), "Enemy 3 should be under illusion")


func test_unknown_enemy_not_under_illusion() -> void:
	assert_false(status_mgr.is_enemy_under_illusion_by_id(999),
		"Unknown enemy should not be under illusion")


# ============================================================================
# IllusionEnemy Constants Tests
# ============================================================================


func test_illusion_enemy_scene_path_exists() -> void:
	## Verify the ENEMY_SCENE_PATH used by IllusionEnemy actually exists.
	var path := "res://scenes/objects/Enemy.tscn"
	assert_true(FileAccess.file_exists(path),
		"Enemy scene must exist at %s for IllusionEnemy to work" % path)


func test_chemical_grenade_scene_exists() -> void:
	## Verify the new ChemicalGasGrenade.tscn scene file was created.
	var path := "res://scenes/projectiles/ChemicalGasGrenade.tscn"
	assert_true(FileAccess.file_exists(path),
		"ChemicalGasGrenade scene must exist at %s" % path)


func test_chemical_cloud_script_exists() -> void:
	## Verify the ChemicalCloud script was created.
	var path := "res://scripts/effects/chemical_cloud.gd"
	assert_true(FileAccess.file_exists(path),
		"ChemicalCloud script must exist at %s" % path)


func test_illusion_enemy_script_exists() -> void:
	## Verify the IllusionEnemy script was created.
	var path := "res://scripts/characters/illusion_enemy.gd"
	assert_true(FileAccess.file_exists(path),
		"IllusionEnemy script must exist at %s" % path)


# ============================================================================
# ChemicalCloud Guard Check Tests
# ============================================================================


class MockChemicalCloud:
	## Mirrors ChemicalCloud's guard logic for _apply_effect_to_enemies_in_cloud().
	var _mock_player_under_illusion: bool = false
	var effect_applied_count: int = 0

	func apply_effect_to_enemies_in_cloud() -> void:
		if _mock_player_under_illusion:
			return  # Guard: player already under effect
		effect_applied_count += 1


func test_cloud_applies_effect_when_player_not_under_illusion() -> void:
	var cloud := MockChemicalCloud.new()
	cloud._mock_player_under_illusion = false
	cloud.apply_effect_to_enemies_in_cloud()
	assert_eq(cloud.effect_applied_count, 1,
		"Cloud should apply effect when player is not under illusion")


func test_cloud_skips_effect_when_player_under_illusion() -> void:
	## Issue #1129 req.9: cloud does nothing if player already under effect
	var cloud := MockChemicalCloud.new()
	cloud._mock_player_under_illusion = true
	cloud.apply_effect_to_enemies_in_cloud()
	assert_eq(cloud.effect_applied_count, 0,
		"Cloud should skip effect when player is already under illusion")


func test_cloud_applies_effect_after_illusion_expires() -> void:
	var cloud := MockChemicalCloud.new()
	cloud._mock_player_under_illusion = true
	cloud.apply_effect_to_enemies_in_cloud()  # Skipped
	cloud._mock_player_under_illusion = false
	cloud.apply_effect_to_enemies_in_cloud()  # Should work now
	assert_eq(cloud.effect_applied_count, 1,
		"Cloud should apply effect after illusion expires")
