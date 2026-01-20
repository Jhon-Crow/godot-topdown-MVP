extends GutTest
## Unit tests for the ricochet system.
##
## Tests caliber data configuration and ricochet calculations.
## Uses mock data to test logic without requiring full scene setup.


# ============================================================================
# CaliberData Tests
# ============================================================================


func test_caliber_data_exists() -> void:
	var caliber_data_script := load("res://scripts/data/caliber_data.gd")
	assert_not_null(caliber_data_script, "CaliberData script should exist")


func test_caliber_data_default_values() -> void:
	var CaliberDataClass := load("res://scripts/data/caliber_data.gd")
	var caliber := CaliberDataClass.new()

	assert_eq(caliber.caliber_name, "5.45x39mm", "Default caliber name")
	assert_eq(caliber.diameter_mm, 5.45, "Default diameter")
	assert_almost_eq(caliber.mass_grams, 3.4, 0.01, "Default mass")
	assert_true(caliber.can_ricochet, "Default can_ricochet should be true")
	assert_eq(caliber.max_ricochets, 2, "Default max ricochets")


func test_caliber_data_ricochet_probability_at_zero_angle() -> void:
	var CaliberDataClass := load("res://scripts/data/caliber_data.gd")
	var caliber := CaliberDataClass.new()

	# At 0 degrees (parallel to surface), probability should be at maximum
	var probability := caliber.calculate_ricochet_probability(0.0)
	assert_almost_eq(probability, caliber.base_ricochet_probability, 0.01, "At 0 degrees, should have base probability")


func test_caliber_data_ricochet_probability_at_max_angle() -> void:
	var CaliberDataClass := load("res://scripts/data/caliber_data.gd")
	var caliber := CaliberDataClass.new()

	# At max angle, probability should be 0
	var probability := caliber.calculate_ricochet_probability(caliber.max_ricochet_angle)
	assert_almost_eq(probability, 0.0, 0.01, "At max angle, probability should be 0")


func test_caliber_data_ricochet_probability_beyond_max_angle() -> void:
	var CaliberDataClass := load("res://scripts/data/caliber_data.gd")
	var caliber := CaliberDataClass.new()

	# Beyond max angle, probability should be 0
	var probability := caliber.calculate_ricochet_probability(caliber.max_ricochet_angle + 10.0)
	assert_eq(probability, 0.0, "Beyond max angle, probability should be 0")


func test_caliber_data_ricochet_probability_interpolation() -> void:
	var CaliberDataClass := load("res://scripts/data/caliber_data.gd")
	var caliber := CaliberDataClass.new()

	# At half the max angle, probability should be half the base
	var half_angle := caliber.max_ricochet_angle / 2.0
	var probability := caliber.calculate_ricochet_probability(half_angle)
	var expected := caliber.base_ricochet_probability * 0.5
	assert_almost_eq(probability, expected, 0.01, "At half angle, should have half base probability")


func test_caliber_data_can_ricochet_false_returns_zero() -> void:
	var CaliberDataClass := load("res://scripts/data/caliber_data.gd")
	var caliber := CaliberDataClass.new()
	caliber.can_ricochet = false

	var probability := caliber.calculate_ricochet_probability(0.0)
	assert_eq(probability, 0.0, "When can_ricochet is false, probability should be 0")


func test_caliber_data_post_ricochet_velocity() -> void:
	var CaliberDataClass := load("res://scripts/data/caliber_data.gd")
	var caliber := CaliberDataClass.new()

	var initial_velocity := 2500.0
	var new_velocity := caliber.calculate_post_ricochet_velocity(initial_velocity)
	var expected := initial_velocity * caliber.velocity_retention

	assert_almost_eq(new_velocity, expected, 0.1, "Post-ricochet velocity should be reduced by retention factor")


func test_caliber_data_ricochet_deviation_range() -> void:
	var CaliberDataClass := load("res://scripts/data/caliber_data.gd")
	var caliber := CaliberDataClass.new()

	# Test multiple random deviations to ensure they're within range
	var max_deviation_rad := deg_to_rad(caliber.ricochet_angle_deviation)

	for i in range(100):
		var deviation := caliber.get_random_ricochet_deviation()
		assert_true(deviation >= -max_deviation_rad and deviation <= max_deviation_rad,
			"Deviation should be within configured range")


# ============================================================================
# Caliber Resource File Tests
# ============================================================================


func test_545x39_caliber_resource_exists() -> void:
	var caliber := load("res://resources/calibers/caliber_545x39.tres")
	assert_not_null(caliber, "5.45x39mm caliber resource should exist")


func test_545x39_caliber_resource_properties() -> void:
	var caliber := load("res://resources/calibers/caliber_545x39.tres")
	if caliber == null:
		pending("Caliber resource not found")
		return

	assert_eq(caliber.caliber_name, "5.45x39mm", "Caliber name should be 5.45x39mm")
	assert_true(caliber.can_ricochet, "5.45x39mm should be able to ricochet")
	assert_eq(caliber.max_ricochets, 2, "Max ricochets should be 2")


# ============================================================================
# Bullet Ricochet Integration Tests
# ============================================================================


func test_bullet_default_ricochet_constants() -> void:
	var BulletScript := load("res://scripts/projectiles/bullet.gd")
	var bullet := Area2D.new()
	bullet.set_script(BulletScript)
	add_child_autoqfree(bullet)

	# Test default constants
	assert_eq(bullet.DEFAULT_MAX_RICOCHETS, 2, "Default max ricochets")
	assert_almost_eq(bullet.DEFAULT_MAX_RICOCHET_ANGLE, 30.0, 0.1, "Default max ricochet angle")
	assert_almost_eq(bullet.DEFAULT_BASE_RICOCHET_PROBABILITY, 0.7, 0.01, "Default base probability")
	assert_almost_eq(bullet.DEFAULT_VELOCITY_RETENTION, 0.6, 0.01, "Default velocity retention")
	assert_almost_eq(bullet.DEFAULT_RICOCHET_DAMAGE_MULTIPLIER, 0.5, 0.01, "Default damage multiplier")


func test_bullet_ricochet_count_starts_at_zero() -> void:
	var BulletScript := load("res://scripts/projectiles/bullet.gd")
	var bullet := Area2D.new()
	bullet.set_script(BulletScript)
	add_child_autoqfree(bullet)

	assert_eq(bullet.get_ricochet_count(), 0, "Ricochet count should start at 0")


func test_bullet_damage_multiplier_starts_at_one() -> void:
	var BulletScript := load("res://scripts/projectiles/bullet.gd")
	var bullet := Area2D.new()
	bullet.set_script(BulletScript)
	add_child_autoqfree(bullet)

	assert_almost_eq(bullet.get_damage_multiplier(), 1.0, 0.01, "Damage multiplier should start at 1.0")


func test_bullet_can_ricochet_default() -> void:
	var BulletScript := load("res://scripts/projectiles/bullet.gd")
	var bullet := Area2D.new()
	bullet.set_script(BulletScript)
	add_child_autoqfree(bullet)

	assert_true(bullet.can_ricochet(), "Bullet should be able to ricochet by default")


func test_bullet_calculate_ricochet_probability_steep_angle() -> void:
	var BulletScript := load("res://scripts/projectiles/bullet.gd")
	var bullet := Area2D.new()
	bullet.set_script(BulletScript)
	add_child_autoqfree(bullet)

	# At steep angle (beyond max), probability should be 0
	var probability := bullet._calculate_ricochet_probability(45.0)
	assert_eq(probability, 0.0, "At steep angle (45 degrees), probability should be 0")


func test_bullet_calculate_ricochet_probability_shallow_angle() -> void:
	var BulletScript := load("res://scripts/projectiles/bullet.gd")
	var bullet := Area2D.new()
	bullet.set_script(BulletScript)
	add_child_autoqfree(bullet)

	# At shallow angle (0 degrees), probability should be high
	var probability := bullet._calculate_ricochet_probability(0.0)
	assert_gt(probability, 0.5, "At shallow angle (0 degrees), probability should be high")


func test_bullet_calculate_impact_angle_perpendicular() -> void:
	var BulletScript := load("res://scripts/projectiles/bullet.gd")
	var bullet := Area2D.new()
	bullet.set_script(BulletScript)
	add_child_autoqfree(bullet)

	# Bullet traveling right, hitting a wall facing left (perpendicular)
	bullet.direction = Vector2.RIGHT
	var surface_normal := Vector2.LEFT

	var angle := bullet._calculate_impact_angle(surface_normal)
	# Perpendicular hit should be ~0 degrees (bullet direction opposite to normal)
	assert_almost_eq(angle, 0.0, 0.01, "Perpendicular hit should be 0 degrees")


func test_bullet_calculate_impact_angle_parallel() -> void:
	var BulletScript := load("res://scripts/projectiles/bullet.gd")
	var bullet := Area2D.new()
	bullet.set_script(BulletScript)
	add_child_autoqfree(bullet)

	# Bullet traveling right, grazing a wall facing up (parallel)
	bullet.direction = Vector2.RIGHT
	var surface_normal := Vector2.UP

	var angle := bullet._calculate_impact_angle(surface_normal)
	# Parallel/grazing hit should be ~90 degrees
	assert_almost_eq(angle, PI / 2.0, 0.01, "Parallel/grazing hit should be ~90 degrees")


func test_bullet_get_max_ricochets_default() -> void:
	var BulletScript := load("res://scripts/projectiles/bullet.gd")
	var bullet := Area2D.new()
	bullet.set_script(BulletScript)
	bullet.caliber_data = null
	add_child_autoqfree(bullet)

	var max_ric := bullet._get_max_ricochets()
	assert_eq(max_ric, bullet.DEFAULT_MAX_RICOCHETS, "Should use default max ricochets when no caliber data")


func test_bullet_get_velocity_retention_default() -> void:
	var BulletScript := load("res://scripts/projectiles/bullet.gd")
	var bullet := Area2D.new()
	bullet.set_script(BulletScript)
	bullet.caliber_data = null
	add_child_autoqfree(bullet)

	var retention := bullet._get_velocity_retention()
	assert_almost_eq(retention, bullet.DEFAULT_VELOCITY_RETENTION, 0.01, "Should use default velocity retention when no caliber data")


func test_bullet_get_ricochet_damage_multiplier_default() -> void:
	var BulletScript := load("res://scripts/projectiles/bullet.gd")
	var bullet := Area2D.new()
	bullet.set_script(BulletScript)
	bullet.caliber_data = null
	add_child_autoqfree(bullet)

	var mult := bullet._get_ricochet_damage_multiplier()
	assert_almost_eq(mult, bullet.DEFAULT_RICOCHET_DAMAGE_MULTIPLIER, 0.01, "Should use default damage multiplier when no caliber data")


# ============================================================================
# Ricochet Calculation Logic Tests
# ============================================================================


func test_ricochet_reflection_calculation() -> void:
	# Test the reflection formula: r = d - 2(d·n)n
	# Bullet going right, hitting wall facing left
	var direction := Vector2.RIGHT.normalized()
	var normal := Vector2.LEFT.normalized()

	var reflected := direction - 2.0 * direction.dot(normal) * normal
	reflected = reflected.normalized()

	# Should reflect back to the left
	assert_almost_eq(reflected.x, -1.0, 0.01, "Reflected X should be -1")
	assert_almost_eq(reflected.y, 0.0, 0.01, "Reflected Y should be 0")


func test_ricochet_reflection_at_45_degrees() -> void:
	# Bullet going diagonally, hitting horizontal surface
	var direction := Vector2(1, 1).normalized()
	var normal := Vector2.UP.normalized()

	var reflected := direction - 2.0 * direction.dot(normal) * normal
	reflected = reflected.normalized()

	# Should reflect to go diagonally upward
	assert_almost_eq(reflected.x, direction.x, 0.01, "X component should be preserved")
	assert_almost_eq(reflected.y, -direction.y, 0.01, "Y component should be inverted")


# ============================================================================
# AudioManager Ricochet Sound Tests
# ============================================================================


func test_audio_manager_has_ricochet_constant() -> void:
	var AudioManagerScript := load("res://scripts/autoload/audio_manager.gd")
	var audio_manager := Node.new()
	audio_manager.set_script(AudioManagerScript)

	assert_true("BULLET_RICOCHET" in audio_manager, "AudioManager should have BULLET_RICOCHET constant")
	assert_true("VOLUME_RICOCHET" in audio_manager, "AudioManager should have VOLUME_RICOCHET constant")


func test_audio_manager_has_ricochet_method() -> void:
	var AudioManagerScript := load("res://scripts/autoload/audio_manager.gd")
	var audio_manager := Node.new()
	audio_manager.set_script(AudioManagerScript)

	assert_true(audio_manager.has_method("play_bullet_ricochet"), "AudioManager should have play_bullet_ricochet method")


# ============================================================================
# Edge Cases
# ============================================================================


func test_bullet_ricochet_with_zero_speed() -> void:
	var BulletScript := load("res://scripts/projectiles/bullet.gd")
	var bullet := Area2D.new()
	bullet.set_script(BulletScript)
	bullet.speed = 0.0
	add_child_autoqfree(bullet)

	# Even with zero speed, ricochet calculations should not crash
	var probability := bullet._calculate_ricochet_probability(15.0)
	assert_true(probability >= 0.0, "Probability should be valid even with zero speed")


func test_bullet_ricochet_with_zero_length_direction() -> void:
	var BulletScript := load("res://scripts/projectiles/bullet.gd")
	var bullet := Area2D.new()
	bullet.set_script(BulletScript)
	bullet.direction = Vector2.ZERO
	add_child_autoqfree(bullet)

	# Should handle zero direction gracefully
	var angle := bullet._calculate_impact_angle(Vector2.UP)
	assert_true(is_finite(angle), "Angle calculation should handle zero direction")


func test_caliber_data_with_custom_values() -> void:
	var CaliberDataClass := load("res://scripts/data/caliber_data.gd")
	var caliber := CaliberDataClass.new()

	# Set custom values
	caliber.max_ricochet_angle = 45.0
	caliber.base_ricochet_probability = 0.9
	caliber.velocity_retention = 0.8

	# At 22.5 degrees (half of 45), should be 0.45 probability (half of 0.9)
	var probability := caliber.calculate_ricochet_probability(22.5)
	var expected := 0.9 * 0.5
	assert_almost_eq(probability, expected, 0.01, "Custom values should be respected")
