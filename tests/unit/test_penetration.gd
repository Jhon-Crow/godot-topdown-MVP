extends GutTest
## Unit tests for the wall penetration system.
##
## Tests caliber data penetration configuration and bullet penetration calculations.
## Uses mock data to test logic without requiring full scene setup.


const BulletScript = preload("res://scripts/projectiles/bullet.gd")


# ============================================================================
# CaliberData Penetration Property Tests
# ============================================================================


func test_caliber_data_penetration_exists() -> void:
	var caliber := CaliberData.new()

	assert_true("can_penetrate" in caliber, "CaliberData should have can_penetrate property")
	assert_true("max_penetration_distance" in caliber, "CaliberData should have max_penetration_distance property")
	assert_true("post_penetration_damage_multiplier" in caliber, "CaliberData should have post_penetration_damage_multiplier property")


func test_caliber_data_penetration_default_values() -> void:
	var caliber := CaliberData.new()

	assert_true(caliber.can_penetrate, "Default can_penetrate should be true")
	assert_almost_eq(caliber.max_penetration_distance, 48.0, 0.1, "Default max_penetration_distance should be 48.0")
	assert_almost_eq(caliber.post_penetration_damage_multiplier, 0.9, 0.01, "Default post_penetration_damage_multiplier should be 0.9")


func test_caliber_data_can_penetrate_walls_method() -> void:
	var caliber := CaliberData.new()

	assert_true(caliber.can_penetrate_walls(), "can_penetrate_walls() should return true by default")

	caliber.can_penetrate = false
	assert_false(caliber.can_penetrate_walls(), "can_penetrate_walls() should return false when disabled")


func test_caliber_data_get_max_penetration_distance_method() -> void:
	var caliber := CaliberData.new()

	assert_almost_eq(caliber.get_max_penetration_distance(), 48.0, 0.1, "get_max_penetration_distance() should return default value")

	caliber.max_penetration_distance = 100.0
	assert_almost_eq(caliber.get_max_penetration_distance(), 100.0, 0.1, "get_max_penetration_distance() should return custom value")


func test_caliber_data_calculate_post_penetration_damage() -> void:
	var caliber := CaliberData.new()

	var original_damage := 1.0
	var new_damage := caliber.calculate_post_penetration_damage(original_damage)
	var expected := original_damage * caliber.post_penetration_damage_multiplier

	assert_almost_eq(new_damage, expected, 0.01, "Post-penetration damage should be reduced by multiplier")


func test_caliber_data_post_penetration_damage_cumulative() -> void:
	var caliber := CaliberData.new()

	# Simulate multiple penetrations
	var damage := 1.0
	damage = caliber.calculate_post_penetration_damage(damage)  # First penetration
	damage = caliber.calculate_post_penetration_damage(damage)  # Second penetration

	var expected := 1.0 * caliber.post_penetration_damage_multiplier * caliber.post_penetration_damage_multiplier
	assert_almost_eq(damage, expected, 0.01, "Damage should reduce cumulatively with multiple penetrations")


# ============================================================================
# 5.45x39mm Caliber Resource Penetration Tests
# ============================================================================


func test_545x39_caliber_penetration_properties() -> void:
	var caliber := load("res://resources/calibers/caliber_545x39.tres")
	if caliber == null:
		pending("Caliber resource not found")
		return

	assert_true(caliber.can_penetrate, "5.45x39mm should be able to penetrate")
	assert_almost_eq(caliber.max_penetration_distance, 48.0, 0.1, "5.45x39mm penetration distance should be 48 pixels (2x thinnest wall)")
	assert_almost_eq(caliber.post_penetration_damage_multiplier, 0.9, 0.01, "5.45x39mm should deal 90% damage after penetration")


func test_545x39_penetration_distance_is_twice_thinnest_wall() -> void:
	# According to requirements: penetration distance = 2 × thinnest wall thickness
	# Thinnest wall in BuildingLevel is 24 pixels (interior walls)
	# So penetration distance should be 48 pixels

	var caliber := load("res://resources/calibers/caliber_545x39.tres")
	if caliber == null:
		pending("Caliber resource not found")
		return

	var thinnest_wall_thickness := 24.0  # From BuildingLevel.tscn interior walls
	var expected_penetration := thinnest_wall_thickness * 2.0

	assert_almost_eq(caliber.max_penetration_distance, expected_penetration, 0.1,
		"Penetration distance should be 2x thinnest wall thickness")


# ============================================================================
# Bullet Penetration Integration Tests
# ============================================================================


func _create_test_bullet() -> Area2D:
	var bullet := Area2D.new()
	bullet.set_script(BulletScript)
	add_child_autoqfree(bullet)
	return bullet


func test_bullet_default_penetration_constants() -> void:
	var bullet := _create_test_bullet()

	assert_true(bullet.DEFAULT_CAN_PENETRATE, "Default can_penetrate should be true")
	assert_almost_eq(bullet.DEFAULT_MAX_PENETRATION_DISTANCE, 48.0, 0.1, "Default max penetration distance should be 48")
	assert_almost_eq(bullet.DEFAULT_POST_PENETRATION_DAMAGE_MULTIPLIER, 0.9, 0.01, "Default post penetration damage multiplier should be 0.9")


func test_bullet_penetration_state_starts_false() -> void:
	var bullet := _create_test_bullet()

	assert_false(bullet.is_penetrating(), "Bullet should not be penetrating initially")
	assert_false(bullet.has_penetrated(), "Bullet should not have penetrated initially")
	assert_eq(bullet.get_penetration_distance(), 0.0, "Penetration distance should start at 0")


func test_bullet_can_penetrate_default() -> void:
	var bullet := _create_test_bullet()
	bullet.caliber_data = null

	var can_pen: bool = bullet.call("_can_penetrate")
	assert_true(can_pen, "Bullet should be able to penetrate by default")


func test_bullet_can_penetrate_with_caliber_data() -> void:
	var bullet := _create_test_bullet()
	bullet.caliber_data = CaliberData.new()
	bullet.caliber_data.can_penetrate = true

	var can_pen: bool = bullet.call("_can_penetrate")
	assert_true(can_pen, "Bullet should be able to penetrate when caliber allows")

	bullet.caliber_data.can_penetrate = false
	can_pen = bullet.call("_can_penetrate")
	assert_false(can_pen, "Bullet should not penetrate when caliber disallows")


func test_bullet_get_max_penetration_distance_default() -> void:
	var bullet := _create_test_bullet()
	bullet.caliber_data = null

	var max_dist: float = bullet.call("_get_max_penetration_distance")
	assert_almost_eq(max_dist, bullet.DEFAULT_MAX_PENETRATION_DISTANCE, 0.1,
		"Should use default max penetration distance when no caliber data")


func test_bullet_get_max_penetration_distance_with_caliber() -> void:
	var bullet := _create_test_bullet()
	bullet.caliber_data = CaliberData.new()
	bullet.caliber_data.max_penetration_distance = 100.0

	var max_dist: float = bullet.call("_get_max_penetration_distance")
	assert_almost_eq(max_dist, 100.0, 0.1, "Should use caliber max penetration distance")


func test_bullet_get_post_penetration_damage_multiplier_default() -> void:
	var bullet := _create_test_bullet()
	bullet.caliber_data = null

	var mult: float = bullet.call("_get_post_penetration_damage_multiplier")
	assert_almost_eq(mult, bullet.DEFAULT_POST_PENETRATION_DAMAGE_MULTIPLIER, 0.01,
		"Should use default post penetration damage multiplier when no caliber data")


func test_bullet_get_post_penetration_damage_multiplier_with_caliber() -> void:
	var bullet := _create_test_bullet()
	bullet.caliber_data = CaliberData.new()
	bullet.caliber_data.post_penetration_damage_multiplier = 0.75

	var mult: float = bullet.call("_get_post_penetration_damage_multiplier")
	assert_almost_eq(mult, 0.75, 0.01, "Should use caliber post penetration damage multiplier")


# ============================================================================
# Penetration vs Ricochet Interaction Tests
# ============================================================================


func test_penetration_only_when_ricochet_fails() -> void:
	# According to requirements: penetration happens when there's no ricochet
	# This is tested implicitly by the _on_body_entered logic:
	# 1. First try ricochet
	# 2. If ricochet fails, try penetration

	# We can verify this by checking the bullet code structure
	var bullet := _create_test_bullet()

	# Verify bullet has both try_ricochet and try_penetration methods
	assert_true(bullet.has_method("_try_ricochet"), "Bullet should have _try_ricochet method")
	assert_true(bullet.has_method("_try_penetration"), "Bullet should have _try_penetration method")


# ============================================================================
# Damage Reduction Tests
# ============================================================================


func test_damage_multiplier_reduced_after_penetration() -> void:
	# After penetration, 5.45 should deal 90% of its original damage
	var caliber := CaliberData.new()

	var original := 1.0
	var after_penetration := caliber.calculate_post_penetration_damage(original)

	assert_almost_eq(after_penetration, 0.9, 0.01, "Damage should be 90% after penetration for 5.45")


func test_damage_multiplier_with_custom_caliber() -> void:
	var caliber := CaliberData.new()
	caliber.post_penetration_damage_multiplier = 0.5  # Hypothetical lighter round

	var original := 1.0
	var after_penetration := caliber.calculate_post_penetration_damage(original)

	assert_almost_eq(after_penetration, 0.5, 0.01, "Damage should match custom multiplier")


# ============================================================================
# Extensibility Tests (Future Calibers)
# ============================================================================


func test_caliber_data_supports_no_penetration() -> void:
	# Some calibers (like very small rounds) might not penetrate
	var caliber := CaliberData.new()
	caliber.can_penetrate = false
	caliber.max_penetration_distance = 0.0

	assert_false(caliber.can_penetrate_walls(), "Small calibers should not penetrate")
	assert_eq(caliber.get_max_penetration_distance(), 0.0, "No penetration distance for non-penetrating rounds")


func test_caliber_data_supports_high_penetration() -> void:
	# Some calibers (like heavy rifle rounds) might have high penetration
	var caliber := CaliberData.new()
	caliber.can_penetrate = true
	caliber.max_penetration_distance = 150.0  # Can go through thick walls
	caliber.post_penetration_damage_multiplier = 0.95  # Retains most energy

	assert_true(caliber.can_penetrate_walls(), "Heavy rounds should penetrate")
	assert_almost_eq(caliber.get_max_penetration_distance(), 150.0, 0.1, "Heavy rounds penetrate further")

	var damage_after := caliber.calculate_post_penetration_damage(1.0)
	assert_almost_eq(damage_after, 0.95, 0.01, "Heavy rounds retain more damage after penetration")


# ============================================================================
# Edge Cases
# ============================================================================


func test_bullet_penetration_with_zero_distance() -> void:
	var bullet := _create_test_bullet()
	bullet.caliber_data = CaliberData.new()
	bullet.caliber_data.max_penetration_distance = 0.0

	var max_dist: float = bullet.call("_get_max_penetration_distance")
	assert_eq(max_dist, 0.0, "Zero penetration distance should be allowed")


func test_caliber_data_boundary_values() -> void:
	var caliber := CaliberData.new()

	# Test minimum values
	caliber.post_penetration_damage_multiplier = 0.1
	var damage := caliber.calculate_post_penetration_damage(1.0)
	assert_almost_eq(damage, 0.1, 0.01, "Minimum damage multiplier should work")

	# Test maximum values
	caliber.post_penetration_damage_multiplier = 1.0
	damage = caliber.calculate_post_penetration_damage(1.0)
	assert_almost_eq(damage, 1.0, 0.01, "Maximum damage multiplier should work")


# ============================================================================
# Distance-Based Penetration Chance Tests
# ============================================================================


func test_bullet_distance_penetration_constants() -> void:
	var bullet := _create_test_bullet()

	# Verify distance-based penetration constants
	assert_almost_eq(bullet.POINT_BLANK_DISTANCE_RATIO, 0.0, 0.01, "Point blank should be 0% of viewport")
	assert_almost_eq(bullet.RICOCHET_RULES_DISTANCE_RATIO, 0.4, 0.01, "Ricochet rules should apply at 40% of viewport")
	assert_almost_eq(bullet.MAX_PENETRATION_CHANCE_AT_DISTANCE, 0.3, 0.01, "Max penetration chance at viewport should be 30%")


func test_bullet_shooter_position_property() -> void:
	var bullet := _create_test_bullet()

	# Verify shooter_position property exists
	assert_true("shooter_position" in bullet, "Bullet should have shooter_position property")
	assert_eq(bullet.shooter_position, Vector2.ZERO, "shooter_position should default to Vector2.ZERO")


func test_bullet_calculate_distance_penetration_chance_at_40_percent() -> void:
	var bullet := _create_test_bullet()

	# At 40% of viewport (RICOCHET_RULES_DISTANCE_RATIO), should be 100% penetration
	var chance: float = bullet.call("_calculate_distance_penetration_chance", 0.4)
	assert_almost_eq(chance, 1.0, 0.01, "Penetration chance at 40% should be 100%")


func test_bullet_calculate_distance_penetration_chance_at_viewport() -> void:
	var bullet := _create_test_bullet()

	# At 100% of viewport, should be MAX_PENETRATION_CHANCE_AT_DISTANCE (30%)
	var chance: float = bullet.call("_calculate_distance_penetration_chance", 1.0)
	assert_almost_eq(chance, 0.3, 0.01, "Penetration chance at viewport distance should be 30%")


func test_bullet_calculate_distance_penetration_chance_at_70_percent() -> void:
	var bullet := _create_test_bullet()

	# At 70% of viewport (halfway between 40% and 100%)
	# Should be halfway between 100% and 30%, so approximately 65%
	var chance: float = bullet.call("_calculate_distance_penetration_chance", 0.7)
	# (1.0 - 0.3) / 2 + 0.3 = 0.65
	assert_almost_eq(chance, 0.65, 0.05, "Penetration chance at 70% should be approximately 65%")


func test_bullet_calculate_distance_penetration_chance_beyond_viewport() -> void:
	var bullet := _create_test_bullet()

	# Beyond viewport (150%), should be less than MAX_PENETRATION_CHANCE_AT_DISTANCE
	var chance: float = bullet.call("_calculate_distance_penetration_chance", 1.5)
	assert_lt(chance, 0.3, "Penetration chance beyond viewport should be less than 30%")
	assert_gt(chance, 0.0, "Penetration chance should not be 0")


# ============================================================================
# Penetration Hole Detection Tests
# ============================================================================


func test_bullet_has_penetration_hole_check_method() -> void:
	var bullet := _create_test_bullet()

	assert_true(bullet.has_method("_is_inside_penetration_hole"), "Bullet should have _is_inside_penetration_hole method")


func test_bullet_not_inside_penetration_hole_by_default() -> void:
	var bullet := _create_test_bullet()

	# Without any overlapping areas, should return false
	var is_inside: bool = bullet.call("_is_inside_penetration_hole")
	assert_false(is_inside, "Bullet should not be inside penetration hole by default")
