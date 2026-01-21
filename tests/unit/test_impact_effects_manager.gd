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
# Blood Particle System Tests
# ============================================================================


func test_manager_has_spawn_blood_decal_at_method() -> void:
	assert_true(impact_manager.has_method("spawn_blood_decal_at"),
		"Manager should have spawn_blood_decal_at method")


func test_spawn_blood_decal_at_accepts_position_and_size() -> void:
	# Should not crash when called with valid parameters
	impact_manager.spawn_blood_decal_at(Vector2(100, 100), 1.0)
	pass_test("spawn_blood_decal_at accepts position and size without error")


func test_spawn_blood_decal_at_handles_small_multiplier() -> void:
	# Should not crash with small multiplier
	impact_manager.spawn_blood_decal_at(Vector2(100, 100), 0.1)
	pass_test("spawn_blood_decal_at handles small multiplier without error")


func test_spawn_blood_decal_at_handles_large_multiplier() -> void:
	# Should not crash with large multiplier
	impact_manager.spawn_blood_decal_at(Vector2(100, 100), 3.0)
	pass_test("spawn_blood_decal_at handles large multiplier without error")


# ============================================================================
# Constants Tests
# ============================================================================


func test_base_blood_particle_count_constant() -> void:
	# Verify the constant is accessible and reasonable
	var count: int = impact_manager.BASE_BLOOD_PARTICLE_COUNT
	assert_gt(count, 0, "Base blood particle count should be positive")
	assert_lt(count, 100, "Base blood particle count should be reasonable")


func test_lethal_blood_particle_count_constant() -> void:
	# Verify the constant is accessible and reasonable
	var count: int = impact_manager.LETHAL_BLOOD_PARTICLE_COUNT
	assert_gt(count, impact_manager.BASE_BLOOD_PARTICLE_COUNT,
		"Lethal blood particle count should be greater than base count")


func test_max_blood_particle_count_constant() -> void:
	# Verify the constant is accessible and reasonable
	var max_count: int = impact_manager.MAX_BLOOD_PARTICLE_COUNT
	assert_gt(max_count, impact_manager.LETHAL_BLOOD_PARTICLE_COUNT,
		"Max particle count should be greater than lethal count")


func test_blood_spread_angle_constant() -> void:
	# Verify the constant is accessible and reasonable
	var angle: float = impact_manager.BLOOD_SPREAD_ANGLE
	assert_gt(angle, 0.0, "Blood spread angle should be positive")
	assert_lt(angle, PI, "Blood spread angle should be less than PI")


func test_blood_spread_angle_is_tight_for_realistic_spray() -> void:
	# Verify the spread angle is tight for realistic directional spray
	var angle: float = impact_manager.BLOOD_SPREAD_ANGLE
	assert_true(angle <= 0.5, "Blood spread angle should be <= 0.5 for tight spray")


# ============================================================================
# Contextual Blood Effect Tests
# ============================================================================


func test_spawn_blood_effect_accepts_target_velocity() -> void:
	# Should not crash when called with target_velocity parameter
	var target_velocity := Vector2(50, -30)
	impact_manager.spawn_blood_effect(Vector2(100, 100), Vector2(1, 0), null, true, target_velocity)
	pass_test("spawn_blood_effect accepts target_velocity parameter without error")


func test_spawn_blood_effect_accepts_distance() -> void:
	# Should not crash when called with distance parameter
	impact_manager.spawn_blood_effect(Vector2(100, 100), Vector2(1, 0), null, true, Vector2.ZERO, 150.0)
	pass_test("spawn_blood_effect accepts distance parameter without error")


func test_spawn_blood_effect_accepts_impact_angle() -> void:
	# Should not crash when called with impact_angle parameter
	impact_manager.spawn_blood_effect(Vector2(100, 100), Vector2(1, 0), null, true, Vector2.ZERO, 0.0, 0.5)
	pass_test("spawn_blood_effect accepts impact_angle parameter without error")


func test_spawn_blood_effect_accepts_all_contextual_parameters() -> void:
	# Should not crash when called with all contextual parameters
	var target_velocity := Vector2(100, -50)
	var distance := 250.0
	var impact_angle := 0.7
	impact_manager.spawn_blood_effect(
		Vector2(100, 100),
		Vector2(1, 0),
		null,
		true,
		target_velocity,
		distance,
		impact_angle
	)
	pass_test("spawn_blood_effect accepts all contextual parameters without error")


func test_spawn_blood_effect_with_close_distance() -> void:
	# Close range shots should work
	impact_manager.spawn_blood_effect(Vector2(100, 100), Vector2(1, 0), null, true, Vector2.ZERO, 50.0)
	pass_test("spawn_blood_effect works with close distance")


func test_spawn_blood_effect_with_long_distance() -> void:
	# Long range shots should work
	impact_manager.spawn_blood_effect(Vector2(100, 100), Vector2(1, 0), null, true, Vector2.ZERO, 500.0)
	pass_test("spawn_blood_effect works with long distance")


func test_spawn_blood_effect_with_moving_target() -> void:
	# Moving targets should create different patterns
	var fast_target := Vector2(200, -100)
	impact_manager.spawn_blood_effect(Vector2(100, 100), Vector2(1, 0), null, true, fast_target)
	pass_test("spawn_blood_effect works with moving target")
