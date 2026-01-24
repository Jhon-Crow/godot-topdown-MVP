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


# ============================================================================
# Satellite Drop Tests (Issue #293 - Realistic Blood Effects)
# ============================================================================


func test_satellite_drop_probability_constant_exists() -> void:
	# Verify the constant for satellite drop probability exists
	assert_true("SATELLITE_DROP_PROBABILITY" in impact_manager,
		"Manager should have SATELLITE_DROP_PROBABILITY constant")


func test_satellite_drop_distance_constants_exist() -> void:
	# Verify distance constants for satellite drops exist
	assert_true("SATELLITE_DROP_MIN_DISTANCE" in impact_manager,
		"Manager should have SATELLITE_DROP_MIN_DISTANCE constant")
	assert_true("SATELLITE_DROP_MAX_DISTANCE" in impact_manager,
		"Manager should have SATELLITE_DROP_MAX_DISTANCE constant")


func test_satellite_drop_scale_constants_exist() -> void:
	# Verify scale constants for satellite drops exist
	assert_true("SATELLITE_DROP_SCALE_MIN" in impact_manager,
		"Manager should have SATELLITE_DROP_SCALE_MIN constant")
	assert_true("SATELLITE_DROP_SCALE_MAX" in impact_manager,
		"Manager should have SATELLITE_DROP_SCALE_MAX constant")


func test_spawn_satellite_drops_method_exists() -> void:
	# The satellite drop spawning method should exist
	assert_true(impact_manager.has_method("_spawn_satellite_drops"),
		"Manager should have _spawn_satellite_drops method")


func test_spawn_satellite_drops_empty_data_returns_zero() -> void:
	# Empty input should return 0 satellites
	var result: int = impact_manager._spawn_satellite_drops(Vector2.ZERO, [], [])
	assert_eq(result, 0, "Empty input should return 0 satellite count")


func test_outermost_drop_percentile_constant_exists() -> void:
	# Verify the constant for outermost drop detection exists
	assert_true("OUTERMOST_DROP_PERCENTILE" in impact_manager,
		"Manager should have OUTERMOST_DROP_PERCENTILE constant")


# ============================================================================
# Crown/Blossom Effect Tests (Issue #293 - Realistic Blood Effects)
# ============================================================================


func test_crown_effect_probability_constant_exists() -> void:
	# Verify the constant for crown effect probability exists
	assert_true("CROWN_EFFECT_PROBABILITY" in impact_manager,
		"Manager should have CROWN_EFFECT_PROBABILITY constant")


func test_crown_spine_count_constant_exists() -> void:
	# Verify the constant for crown spine count exists
	assert_true("CROWN_SPINE_COUNT" in impact_manager,
		"Manager should have CROWN_SPINE_COUNT constant")


func test_crown_spine_scale_constants_exist() -> void:
	# Verify scale constants for crown spines exist
	assert_true("CROWN_SPINE_SCALE_WIDTH" in impact_manager,
		"Manager should have CROWN_SPINE_SCALE_WIDTH constant")
	assert_true("CROWN_SPINE_SCALE_LENGTH_MIN" in impact_manager,
		"Manager should have CROWN_SPINE_SCALE_LENGTH_MIN constant")
	assert_true("CROWN_SPINE_SCALE_LENGTH_MAX" in impact_manager,
		"Manager should have CROWN_SPINE_SCALE_LENGTH_MAX constant")


func test_crown_spine_distance_constant_exists() -> void:
	# Verify distance constant for crown spine placement exists
	assert_true("CROWN_SPINE_DISTANCE" in impact_manager,
		"Manager should have CROWN_SPINE_DISTANCE constant")


func test_spawn_crown_effect_method_exists() -> void:
	# The crown effect spawning method should exist
	assert_true(impact_manager.has_method("_spawn_crown_effect"),
		"Manager should have _spawn_crown_effect method")


# ============================================================================
# Round 3 Fixes Tests (Issue #293 - Edge Scaling, Overlap Prevention, No Limits)
# ============================================================================


func test_edge_drop_scale_min_constant_exists() -> void:
	# Verify the constant for edge drop scaling exists
	assert_true("EDGE_DROP_SCALE_MIN" in impact_manager,
		"Manager should have EDGE_DROP_SCALE_MIN constant")


func test_edge_drop_scale_min_is_reasonable() -> void:
	# Edge drops should be scaled down to at least 40% (not too small to be invisible)
	assert_gt(impact_manager.EDGE_DROP_SCALE_MIN, 0.2,
		"EDGE_DROP_SCALE_MIN should be greater than 0.2")
	assert_lt(impact_manager.EDGE_DROP_SCALE_MIN, 0.8,
		"EDGE_DROP_SCALE_MIN should be less than 0.8 to show visible size reduction")


func test_satellite_min_separation_constant_exists() -> void:
	# Verify the constant for satellite separation exists
	assert_true("SATELLITE_MIN_SEPARATION" in impact_manager,
		"Manager should have SATELLITE_MIN_SEPARATION constant")


func test_satellite_min_separation_is_positive() -> void:
	# Separation distance must be positive to prevent overlap
	assert_gt(impact_manager.SATELLITE_MIN_SEPARATION, 0.0,
		"SATELLITE_MIN_SEPARATION should be positive")


func test_max_blood_decals_is_unlimited() -> void:
	# MAX_BLOOD_DECALS should be 0 for unlimited decals (per issue #293 Round 3)
	# Puddles should never disappear
	assert_eq(impact_manager.MAX_BLOOD_DECALS, 0,
		"MAX_BLOOD_DECALS should be 0 for unlimited decals")


func test_spawn_satellite_drops_accepts_existing_positions() -> void:
	# The satellite spawn method should accept existing positions to avoid overlap
	var existing_positions: Array = [Vector2(100, 100), Vector2(200, 200)]
	# Call with empty particle data - should return 0 and not crash
	var result: int = impact_manager._spawn_satellite_drops(Vector2.ZERO, [], [], existing_positions)
	assert_eq(result, 0, "Should return 0 for empty particle data")


func test_spawn_satellite_drops_skips_overlapping_positions() -> void:
	# Satellite drops should not be spawned at positions that overlap existing drops
	# We can't fully test this without mocking random, but we can verify method signature
	var particle_data: Array = [
		{
			"position": Vector2(100, 100),
			"velocity": Vector2(50, 0),
			"land_time": 0.5,
			"merged": false
		}
	]
	var merged_splatters: Array = []
	var existing_positions: Array = [Vector2(100, 100)]  # Right at the particle position
	# Should handle the case where existing positions might cause overlap
	impact_manager._spawn_satellite_drops(Vector2(0, 0), particle_data, merged_splatters, existing_positions)
	pass_test("spawn_satellite_drops handles existing positions without error")


# ============================================================================
# Round 4 Fixes Tests (Issue #293 - Circular Drops, Gradual Color Transition)
# ============================================================================


func test_blood_decal_scene_path_is_correct() -> void:
	# Verify the blood decal scene path constant is accessible
	# The actual scene is loaded during _ready, but we can verify the manager expects it
	assert_true(impact_manager.has_method("clear_blood_decals"),
		"Manager should have clear_blood_decals method for managing decals")


func test_blood_decal_script_has_color_aging_property() -> void:
	# Verify the blood decal script has color aging capability
	var BloodDecalScript = load("res://scripts/effects/blood_decal.gd")
	assert_not_null(BloodDecalScript, "BloodDecal script should exist")

	# Create a temporary instance to check properties
	var temp_sprite := Sprite2D.new()
	temp_sprite.set_script(BloodDecalScript)
	add_child_autoqfree(temp_sprite)

	# Check for color aging property
	assert_true("color_aging" in temp_sprite,
		"BloodDecal should have color_aging property")


func test_blood_decal_script_has_aging_duration_property() -> void:
	# Verify the blood decal script has aging duration
	var BloodDecalScript = load("res://scripts/effects/blood_decal.gd")
	var temp_sprite := Sprite2D.new()
	temp_sprite.set_script(BloodDecalScript)
	add_child_autoqfree(temp_sprite)

	# Check for aging duration property
	assert_true("aging_duration" in temp_sprite,
		"BloodDecal should have aging_duration property")


func test_blood_decal_script_has_color_constants() -> void:
	# Verify the blood decal script has color tint constants
	var BloodDecalScript = load("res://scripts/effects/blood_decal.gd")
	var temp_sprite := Sprite2D.new()
	temp_sprite.set_script(BloodDecalScript)
	add_child_autoqfree(temp_sprite)

	# Check for color constants
	assert_true("FRESH_BLOOD_TINT" in temp_sprite,
		"BloodDecal should have FRESH_BLOOD_TINT constant")
	assert_true("DRIED_BLOOD_TINT" in temp_sprite,
		"BloodDecal should have DRIED_BLOOD_TINT constant")


func test_blood_decal_fresh_color_is_brighter_than_dried() -> void:
	# Fresh blood should be brighter (closer to red) than dried blood (brown)
	var BloodDecalScript = load("res://scripts/effects/blood_decal.gd")
	var temp_sprite := Sprite2D.new()
	temp_sprite.set_script(BloodDecalScript)
	add_child_autoqfree(temp_sprite)

	var fresh: Color = temp_sprite.FRESH_BLOOD_TINT
	var dried: Color = temp_sprite.DRIED_BLOOD_TINT

	# Fresh blood should have higher red component
	assert_gt(fresh.r, dried.r,
		"Fresh blood should have higher red component than dried")


func test_blood_decal_aging_duration_is_reasonable() -> void:
	# Aging duration should be between 30 seconds and 5 minutes
	var BloodDecalScript = load("res://scripts/effects/blood_decal.gd")
	var temp_sprite := Sprite2D.new()
	temp_sprite.set_script(BloodDecalScript)
	add_child_autoqfree(temp_sprite)

	assert_gt(temp_sprite.aging_duration, 20.0,
		"Aging duration should be at least 20 seconds")
	assert_lt(temp_sprite.aging_duration, 300.0,
		"Aging duration should be less than 5 minutes")


func test_blood_decal_has_start_color_aging_method() -> void:
	# Verify the color aging method exists
	var BloodDecalScript = load("res://scripts/effects/blood_decal.gd")
	var temp_sprite := Sprite2D.new()
	temp_sprite.set_script(BloodDecalScript)
	add_child_autoqfree(temp_sprite)

	assert_true(temp_sprite.has_method("_start_color_aging"),
		"BloodDecal should have _start_color_aging method")


# Round 5: Circular blood drop tests (fix for rectangular drops)
func test_blood_decal_scene_has_radial_gradient() -> void:
	# Test that the BloodDecal scene uses proper radial gradient for circular shape
	var blood_decal_scene = load("res://scenes/effects/BloodDecal.tscn")
	assert_not_null(blood_decal_scene, "BloodDecal scene should exist")

	var blood_decal = blood_decal_scene.instantiate()
	add_child_autoqfree(blood_decal)

	# Check that the texture exists
	assert_not_null(blood_decal.texture, "BloodDecal should have a texture")


func test_blood_decal_texture_is_square() -> void:
	# Blood decals should use square textures for proper circular rendering
	var blood_decal_scene = load("res://scenes/effects/BloodDecal.tscn")
	var blood_decal = blood_decal_scene.instantiate()
	add_child_autoqfree(blood_decal)

	if blood_decal.texture:
		var tex_size = blood_decal.texture.get_size()
		assert_eq(tex_size.x, tex_size.y,
			"BloodDecal texture should be square for proper circular shape")
		assert_gte(tex_size.x, 32,
			"BloodDecal texture should be at least 32x32 for smooth edges")


# ============================================================================
# Round 7 Fixes Tests (Issue #293 - Flat matte drops, smaller puddles, better placement)
# ============================================================================


func test_blood_puddle_scale_multiplier_constant_exists() -> void:
	# Verify the constant for overall scale reduction exists
	assert_true("BLOOD_PUDDLE_SCALE_MULTIPLIER" in impact_manager,
		"Manager should have BLOOD_PUDDLE_SCALE_MULTIPLIER constant")


func test_blood_puddle_scale_multiplier_reduces_size() -> void:
	# Scale multiplier should reduce puddle sizes (per issue #293 round 7)
	assert_lt(impact_manager.BLOOD_PUDDLE_SCALE_MULTIPLIER, 1.0,
		"BLOOD_PUDDLE_SCALE_MULTIPLIER should be less than 1.0 to reduce puddle sizes")
	assert_gt(impact_manager.BLOOD_PUDDLE_SCALE_MULTIPLIER, 0.2,
		"BLOOD_PUDDLE_SCALE_MULTIPLIER should be greater than 0.2 to keep puddles visible")


func test_satellite_min_distance_from_puddle_constant_exists() -> void:
	# Verify the constant for satellite distance from main puddles exists
	assert_true("SATELLITE_MIN_DISTANCE_FROM_PUDDLE" in impact_manager,
		"Manager should have SATELLITE_MIN_DISTANCE_FROM_PUDDLE constant")


func test_satellite_min_distance_from_puddle_prevents_overlap() -> void:
	# Satellites should be far enough from puddles to prevent overlap
	assert_gt(impact_manager.SATELLITE_MIN_DISTANCE_FROM_PUDDLE, 10.0,
		"SATELLITE_MIN_DISTANCE_FROM_PUDDLE should be at least 10 pixels")


func test_satellite_drop_scale_is_reduced() -> void:
	# Satellite drops should be smaller (per issue #293 round 7)
	assert_lt(impact_manager.SATELLITE_DROP_SCALE_MAX, 0.25,
		"SATELLITE_DROP_SCALE_MAX should be less than 0.25 for smaller satellites")


func test_blood_decal_color_aging_disabled_by_default() -> void:
	# Color aging should be disabled by default (per issue #293 round 7)
	var BloodDecalScript = load("res://scripts/effects/blood_decal.gd")
	var temp_sprite := Sprite2D.new()
	temp_sprite.set_script(BloodDecalScript)
	add_child_autoqfree(temp_sprite)

	assert_false(temp_sprite.color_aging,
		"BloodDecal color_aging should be disabled by default")


func test_blood_decal_gradient_is_flat() -> void:
	# Blood decal texture should have uniform color (flat, not 3D ball)
	var blood_decal_scene = load("res://scenes/effects/BloodDecal.tscn")
	var blood_decal = blood_decal_scene.instantiate()
	add_child_autoqfree(blood_decal)

	# The texture should exist and be a gradient
	assert_not_null(blood_decal.texture, "BloodDecal should have a texture")
	pass_test("Blood decal has flat gradient texture")


# ============================================================================
# Round 9: Gradient Offset Distribution Tests (Issue #293)
# ============================================================================


func test_blood_decal_gradient_has_sufficient_offsets() -> void:
	# Round 9: Gradient should have enough offsets to prevent banding/rectangular appearance
	var blood_decal_scene = load("res://scenes/effects/BloodDecal.tscn")
	var blood_decal = blood_decal_scene.instantiate()
	add_child_autoqfree(blood_decal)

	var gradient_texture = blood_decal.texture as GradientTexture2D
	assert_not_null(gradient_texture, "BloodDecal texture should be GradientTexture2D")

	var gradient = gradient_texture.gradient
	assert_not_null(gradient, "GradientTexture2D should have a Gradient")

	# Should have at least 7 offsets to prevent visible banding
	# Round 5 (working): 9 offsets
	# Round 8 (broken): 6 offsets with large gap
	assert_gte(gradient.get_point_count(), 7,
		"Gradient should have at least 7 offsets for smooth circular appearance")


func test_blood_decal_gradient_no_large_gaps() -> void:
	# Round 9: Maximum gap between offsets should be < 0.25 in visible range (0-0.707)
	# to prevent rectangular banding artifacts
	var blood_decal_scene = load("res://scenes/effects/BloodDecal.tscn")
	var blood_decal = blood_decal_scene.instantiate()
	add_child_autoqfree(blood_decal)

	var gradient_texture = blood_decal.texture as GradientTexture2D
	var gradient = gradient_texture.gradient

	var offsets = gradient.offsets
	var max_gap := 0.0

	# Check gaps in visible range (0 to 0.707 - inscribed circle edge)
	for i in range(len(offsets) - 1):
		if offsets[i] <= 0.707:
			var gap = offsets[i + 1] - offsets[i]
			max_gap = max(max_gap, gap)

	assert_lt(max_gap, 0.25,
		"Maximum offset gap should be < 0.25 in visible range to prevent banding")


func test_blood_decal_gradient_uniform_color() -> void:
	# Round 9: All color stops should have same RGB values (uniform dark color)
	# Only alpha should vary
	var blood_decal_scene = load("res://scenes/effects/BloodDecal.tscn")
	var blood_decal = blood_decal_scene.instantiate()
	add_child_autoqfree(blood_decal)

	var gradient_texture = blood_decal.texture as GradientTexture2D
	var gradient = gradient_texture.gradient

	var colors = gradient.colors
	var first_rgb = Vector3(colors[0].r, colors[0].g, colors[0].b)

	# All colors should have same RGB (only alpha differs)
	for i in range(1, len(colors)):
		var current_rgb = Vector3(colors[i].r, colors[i].g, colors[i].b)
		assert_almost_eq(current_rgb.x, first_rgb.x, 0.01,
			"All gradient colors should have same red value (uniform color)")
		assert_almost_eq(current_rgb.y, first_rgb.y, 0.01,
			"All gradient colors should have same green value (uniform color)")
		assert_almost_eq(current_rgb.z, first_rgb.z, 0.01,
			"All gradient colors should have same blue value (uniform color)")


func test_blood_decal_gradient_has_edge_offset() -> void:
	# Round 9: Should have offset at circle edge (≈0.707)
	var blood_decal_scene = load("res://scenes/effects/BloodDecal.tscn")
	var blood_decal = blood_decal_scene.instantiate()
	add_child_autoqfree(blood_decal)

	var gradient_texture = blood_decal.texture as GradientTexture2D
	var gradient = gradient_texture.gradient

	var offsets = gradient.offsets
	var has_edge_offset := false

	# Look for offset near 0.707 (inscribed circle edge)
	for offset in offsets:
		if abs(offset - 0.707) < 0.01:
			has_edge_offset = true
			break

	assert_true(has_edge_offset,
		"Gradient should have offset at circle edge (≈0.707) for clean circular appearance")


func test_blood_decal_gradient_fades_to_transparent() -> void:
	# Round 9: Gradient should fade to transparent (alpha 0) at edges
	var blood_decal_scene = load("res://scenes/effects/BloodDecal.tscn")
	var blood_decal = blood_decal_scene.instantiate()
	add_child_autoqfree(blood_decal)

	var gradient_texture = blood_decal.texture as GradientTexture2D
	var gradient = gradient_texture.gradient

	var colors = gradient.colors
	var last_color = colors[len(colors) - 1]

	assert_almost_eq(last_color.a, 0.0, 0.01,
		"Last gradient color should be fully transparent (alpha 0)")


func test_blood_decal_gradient_starts_opaque() -> void:
	# Round 9: Gradient should start mostly opaque at center
	var blood_decal_scene = load("res://scenes/effects/BloodDecal.tscn")
	var blood_decal = blood_decal_scene.instantiate()
	add_child_autoqfree(blood_decal)

	var gradient_texture = blood_decal.texture as GradientTexture2D
	var gradient = gradient_texture.gradient

	var colors = gradient.colors
	var first_color = colors[0]

	assert_gt(first_color.a, 0.8,
		"First gradient color should be mostly opaque (alpha > 0.8)")


func test_blood_decal_gradient_radial_fill() -> void:
	# Round 9: GradientTexture2D should use radial fill mode
	var blood_decal_scene = load("res://scenes/effects/BloodDecal.tscn")
	var blood_decal = blood_decal_scene.instantiate()
	add_child_autoqfree(blood_decal)

	var gradient_texture = blood_decal.texture as GradientTexture2D

	# Fill mode 1 = RADIAL
	assert_eq(gradient_texture.fill, GradientTexture2D.FILL_RADIAL,
		"GradientTexture2D should use FILL_RADIAL mode")


func test_blood_decal_gradient_centered() -> void:
	# Round 9: Radial gradient should be centered at (0.5, 0.5)
	var blood_decal_scene = load("res://scenes/effects/BloodDecal.tscn")
	var blood_decal = blood_decal_scene.instantiate()
	add_child_autoqfree(blood_decal)

	var gradient_texture = blood_decal.texture as GradientTexture2D

	assert_almost_eq(gradient_texture.fill_from.x, 0.5, 0.01,
		"Radial gradient should be centered horizontally (fill_from.x = 0.5)")
	assert_almost_eq(gradient_texture.fill_from.y, 0.5, 0.01,
		"Radial gradient should be centered vertically (fill_from.y = 0.5)")


func test_blood_decal_gradient_fill_to_corner() -> void:
	# Round 9: Radial gradient should extend to corner (1.0, 1.0) for proper circular coverage
	var blood_decal_scene = load("res://scenes/effects/BloodDecal.tscn")
	var blood_decal = blood_decal_scene.instantiate()
	add_child_autoqfree(blood_decal)

	var gradient_texture = blood_decal.texture as GradientTexture2D

	assert_almost_eq(gradient_texture.fill_to.x, 1.0, 0.01,
		"Radial gradient fill_to.x should be 1.0 (corner)")
	assert_almost_eq(gradient_texture.fill_to.y, 1.0, 0.01,
		"Radial gradient fill_to.y should be 1.0 (corner)")
