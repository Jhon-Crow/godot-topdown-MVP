extends GutTest
## Unit tests for ImpactEffectsManager autoload.
##
## Tests that the ImpactEffectsManager properly spawns visual effects
## for different hit types (dust, blood, sparks) with caliber-based scaling.


const ImpactEffectsScript = preload("res://scripts/autoload/impact_effects_manager.gd")
const CaliberDataScript = preload("res://scripts/data/caliber_data.gd")


var impact_manager: Node


# ============================================================================
# Setup
# ============================================================================


func before_each() -> void:
	impact_manager = Node.new()
	impact_manager.set_script(ImpactEffectsScript)
	add_child_autoqfree(impact_manager)


func after_each() -> void:
	impact_manager = null


# ============================================================================
# Initialization Tests
# ============================================================================


func test_manager_initializes_without_error() -> void:
	# Test that manager initializes properly
	assert_not_null(impact_manager, "Impact manager should be created")
	pass_test("Manager initialized without error")


func test_manager_has_spawn_dust_effect_method() -> void:
	assert_true(impact_manager.has_method("spawn_dust_effect"),
		"Manager should have spawn_dust_effect method")


func test_manager_has_spawn_blood_effect_method() -> void:
	assert_true(impact_manager.has_method("spawn_blood_effect"),
		"Manager should have spawn_blood_effect method")


func test_manager_has_spawn_sparks_effect_method() -> void:
	assert_true(impact_manager.has_method("spawn_sparks_effect"),
		"Manager should have spawn_sparks_effect method")


# ============================================================================
# Effect Scale Calculation Tests
# ============================================================================


func test_default_effect_scale_is_used_without_caliber_data() -> void:
	# Call private method via duck typing - the result should be 1.0
	var scale: float = impact_manager._get_effect_scale(null)
	assert_eq(scale, 1.0, "Default effect scale should be 1.0")


func test_effect_scale_uses_caliber_data_when_provided() -> void:
	var caliber := CaliberDataScript.new()
	caliber.effect_scale = 1.5

	var scale: float = impact_manager._get_effect_scale(caliber)
	assert_eq(scale, 1.5, "Effect scale should match caliber data")


func test_effect_scale_is_clamped_to_minimum() -> void:
	var caliber := CaliberDataScript.new()
	caliber.effect_scale = 0.1  # Below minimum of 0.3

	var scale: float = impact_manager._get_effect_scale(caliber)
	assert_eq(scale, 0.3, "Effect scale should be clamped to minimum 0.3")


func test_effect_scale_is_clamped_to_maximum() -> void:
	var caliber := CaliberDataScript.new()
	caliber.effect_scale = 3.0  # Above maximum of 2.0

	var scale: float = impact_manager._get_effect_scale(caliber)
	assert_eq(scale, 2.0, "Effect scale should be clamped to maximum 2.0")


# ============================================================================
# Method Signature Tests
# ============================================================================


func test_spawn_dust_effect_accepts_position_and_normal() -> void:
	# Should not crash when called with valid parameters
	impact_manager.spawn_dust_effect(Vector2(100, 100), Vector2(0, -1), null)
	pass_test("spawn_dust_effect accepts position and normal without error")


func test_spawn_blood_effect_accepts_position_and_direction() -> void:
	# Should not crash when called with valid parameters
	impact_manager.spawn_blood_effect(Vector2(100, 100), Vector2(1, 0), null)
	pass_test("spawn_blood_effect accepts position and direction without error")


func test_spawn_sparks_effect_accepts_position_and_direction() -> void:
	# Should not crash when called with valid parameters
	impact_manager.spawn_sparks_effect(Vector2(100, 100), Vector2(1, 0), null)
	pass_test("spawn_sparks_effect accepts position and direction without error")


func test_spawn_dust_effect_accepts_caliber_data() -> void:
	var caliber := CaliberDataScript.new()
	caliber.effect_scale = 1.2

	# Should not crash when called with caliber data
	impact_manager.spawn_dust_effect(Vector2(100, 100), Vector2(0, -1), caliber)
	pass_test("spawn_dust_effect accepts caliber data without error")


func test_spawn_blood_effect_accepts_caliber_data() -> void:
	var caliber := CaliberDataScript.new()
	caliber.effect_scale = 1.5

	# Should not crash when called with caliber data
	impact_manager.spawn_blood_effect(Vector2(100, 100), Vector2(1, 0), caliber)
	pass_test("spawn_blood_effect accepts caliber data without error")


func test_spawn_sparks_effect_accepts_caliber_data() -> void:
	var caliber := CaliberDataScript.new()
	caliber.effect_scale = 0.8

	# Should not crash when called with caliber data
	impact_manager.spawn_sparks_effect(Vector2(100, 100), Vector2(1, 0), caliber)
	pass_test("spawn_sparks_effect accepts caliber data without error")


# ============================================================================
# Edge Cases
# ============================================================================


func test_spawn_effects_handle_zero_vector_direction() -> void:
	# Should not crash with zero direction vector
	impact_manager.spawn_dust_effect(Vector2.ZERO, Vector2.ZERO, null)
	impact_manager.spawn_blood_effect(Vector2.ZERO, Vector2.ZERO, null)
	impact_manager.spawn_sparks_effect(Vector2.ZERO, Vector2.ZERO, null)
	pass_test("Spawn methods handle zero vectors without error")


func test_spawn_effects_handle_negative_positions() -> void:
	# Should not crash with negative positions
	impact_manager.spawn_dust_effect(Vector2(-100, -200), Vector2(1, 0), null)
	impact_manager.spawn_blood_effect(Vector2(-100, -200), Vector2(1, 0), null)
	impact_manager.spawn_sparks_effect(Vector2(-100, -200), Vector2(1, 0), null)
	pass_test("Spawn methods handle negative positions without error")


func test_spawn_blood_effect_accepts_is_lethal_parameter() -> void:
	# Should not crash when called with is_lethal parameter
	impact_manager.spawn_blood_effect(Vector2(100, 100), Vector2(1, 0), null, true)
	impact_manager.spawn_blood_effect(Vector2(100, 100), Vector2(1, 0), null, false)
	pass_test("spawn_blood_effect accepts is_lethal parameter without error")


func test_clear_blood_decals_method_exists() -> void:
	assert_true(impact_manager.has_method("clear_blood_decals"),
		"Manager should have clear_blood_decals method")


func test_clear_blood_decals_runs_without_error() -> void:
	# Should not crash when clearing decals (even when empty)
	impact_manager.clear_blood_decals()
	pass_test("clear_blood_decals runs without error")


# ============================================================================
# Wall Blood Splatter Tests (Issue #257)
# ============================================================================


func test_wall_splatter_check_distance_constant_exists() -> void:
	# Verify the constant for wall splatter check distance exists
	assert_true("WALL_SPLATTER_CHECK_DISTANCE" in impact_manager,
		"Manager should have WALL_SPLATTER_CHECK_DISTANCE constant")


func test_wall_collision_layer_constant_exists() -> void:
	# Verify the constant for wall collision layer exists
	assert_true("WALL_COLLISION_LAYER" in impact_manager,
		"Manager should have WALL_COLLISION_LAYER constant")


func test_wall_collision_layer_is_correct_bitmask() -> void:
	# WALL_COLLISION_LAYER should be 4 (bitmask for layer 3 = obstacles)
	# Layer mapping: 1=player(1), 2=enemies(2), 3=obstacles(4), etc.
	assert_eq(impact_manager.WALL_COLLISION_LAYER, 4,
		"WALL_COLLISION_LAYER should be 4 (layer 3 = obstacles)")


func test_spawn_wall_blood_splatter_method_exists() -> void:
	# The wall splatter spawning method should exist
	assert_true(impact_manager.has_method("_spawn_wall_blood_splatter"),
		"Manager should have _spawn_wall_blood_splatter method")


func test_spawn_wall_blood_splatter_accepts_parameters() -> void:
	# Should not crash when called with valid parameters (no scene, so no actual raycast)
	# Note: Without a proper scene tree and world_2d, this will silently return early
	impact_manager._spawn_wall_blood_splatter(Vector2(100, 100), Vector2(1, 0), 1.0, true)
	impact_manager._spawn_wall_blood_splatter(Vector2(100, 100), Vector2(1, 0), 1.0, false)
	pass_test("_spawn_wall_blood_splatter accepts parameters without error")


func test_spawn_blood_effect_spawns_floor_decal_on_non_lethal_hit() -> void:
	# Non-lethal hits should now also spawn floor decals (smaller ones)
	# This tests that the code path doesn't crash - actual decal spawning
	# requires scene resources which aren't loaded in unit tests
	impact_manager.spawn_blood_effect(Vector2(100, 100), Vector2(1, 0), null, false)
	pass_test("spawn_blood_effect handles non-lethal hits with floor decals")


func test_spawn_blood_effect_spawns_floor_decal_on_lethal_hit() -> void:
	# Lethal hits should spawn larger floor decals
	impact_manager.spawn_blood_effect(Vector2(100, 100), Vector2(1, 0), null, true)
	pass_test("spawn_blood_effect handles lethal hits with floor decals")


func test_spawn_blood_decals_at_particle_landing_method_exists() -> void:
	# The new particle-based decal spawning method should exist
	assert_true(impact_manager.has_method("_spawn_blood_decals_at_particle_landing"),
		"Manager should have _spawn_blood_decals_at_particle_landing method")


func test_schedule_delayed_decal_method_exists() -> void:
	# The delayed decal spawning method for syncing with particle landing should exist
	assert_true(impact_manager.has_method("_schedule_delayed_decal"),
		"Manager should have _schedule_delayed_decal method")


func test_on_tree_changed_method_exists() -> void:
	# The scene change handler should exist for clearing stale references
	assert_true(impact_manager.has_method("_on_tree_changed"),
		"Manager should have _on_tree_changed method for scene change handling")


# ============================================================================
# Blood Decal Merging and Directional Deformation Tests (Issue #293)
# ============================================================================


func test_decal_merge_distance_constant_exists() -> void:
	# Verify the constant for decal merge distance exists
	assert_true("DECAL_MERGE_DISTANCE" in impact_manager,
		"Manager should have DECAL_MERGE_DISTANCE constant")


func test_max_merged_splatters_constant_exists() -> void:
	# Verify the constant for maximum merged splatters exists
	assert_true("MAX_MERGED_SPLATTERS" in impact_manager,
		"Manager should have MAX_MERGED_SPLATTERS constant")


func test_cluster_drops_into_splatters_method_exists() -> void:
	# The method for clustering nearby drops should exist
	assert_true(impact_manager.has_method("_cluster_drops_into_splatters"),
		"Manager should have _cluster_drops_into_splatters method")


func test_schedule_delayed_decal_directional_method_exists() -> void:
	# The directional decal spawning method should exist
	assert_true(impact_manager.has_method("_schedule_delayed_decal_directional"),
		"Manager should have _schedule_delayed_decal_directional method")


func test_cluster_drops_empty_array_returns_empty() -> void:
	# Empty input should return empty array
	var result: Array = impact_manager._cluster_drops_into_splatters([])
	assert_eq(result.size(), 0, "Empty input should return empty array")


func test_cluster_drops_single_particle_not_merged() -> void:
	# Single particle should not create a merged splatter
	var particle_data: Array = [{
		"position": Vector2(100, 100),
		"velocity": Vector2(50, 0),
		"land_time": 0.5,
		"merged": false
	}]
	var result: Array = impact_manager._cluster_drops_into_splatters(particle_data)
	assert_eq(result.size(), 0, "Single particle should not create merged splatter")
	assert_false(particle_data[0]["merged"], "Single particle should not be marked as merged")


func test_cluster_drops_nearby_particles_merge() -> void:
	# Two particles close together should merge
	var particle_data: Array = [
		{
			"position": Vector2(100, 100),
			"velocity": Vector2(50, 0),
			"land_time": 0.5,
			"merged": false
		},
		{
			"position": Vector2(105, 100),  # Within DECAL_MERGE_DISTANCE (12.0)
			"velocity": Vector2(60, 0),
			"land_time": 0.4,
			"merged": false
		}
	]
	var result: Array = impact_manager._cluster_drops_into_splatters(particle_data)
	assert_eq(result.size(), 1, "Two nearby particles should create one merged splatter")
	assert_eq(result[0]["count"], 2, "Merged splatter should contain 2 drops")


func test_cluster_drops_distant_particles_not_merged() -> void:
	# Two particles far apart should not merge
	var particle_data: Array = [
		{
			"position": Vector2(100, 100),
			"velocity": Vector2(50, 0),
			"land_time": 0.5,
			"merged": false
		},
		{
			"position": Vector2(200, 100),  # Far beyond DECAL_MERGE_DISTANCE
			"velocity": Vector2(60, 0),
			"land_time": 0.4,
			"merged": false
		}
	]
	var result: Array = impact_manager._cluster_drops_into_splatters(particle_data)
	assert_eq(result.size(), 0, "Distant particles should not create merged splatter")


func test_cluster_drops_calculates_center_position() -> void:
	# Verify center position is calculated as average
	var particle_data: Array = [
		{
			"position": Vector2(100, 100),
			"velocity": Vector2(50, 0),
			"land_time": 0.5,
			"merged": false
		},
		{
			"position": Vector2(110, 100),
			"velocity": Vector2(60, 0),
			"land_time": 0.4,
			"merged": false
		}
	]
	var result: Array = impact_manager._cluster_drops_into_splatters(particle_data)
	assert_eq(result.size(), 1, "Should create one merged splatter")
	# Center should be average: (100+110)/2 = 105, (100+100)/2 = 100
	assert_eq(result[0]["center"], Vector2(105, 100), "Center should be average of positions")


func test_cluster_drops_uses_earliest_land_time() -> void:
	# Verify earliest land time is used for merged splatter
	var particle_data: Array = [
		{
			"position": Vector2(100, 100),
			"velocity": Vector2(50, 0),
			"land_time": 0.6,
			"merged": false
		},
		{
			"position": Vector2(108, 100),
			"velocity": Vector2(60, 0),
			"land_time": 0.3,
			"merged": false
		}
	]
	var result: Array = impact_manager._cluster_drops_into_splatters(particle_data)
	assert_eq(result.size(), 1, "Should create one merged splatter")
	assert_eq(result[0]["earliest_land_time"], 0.3, "Should use earliest land time")
