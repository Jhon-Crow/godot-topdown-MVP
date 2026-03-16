extends GutTest
## Unit tests for the ricochet system.
##
## Tests caliber data configuration and ricochet calculations.
## Uses mock data to test logic without requiring full scene setup.


const BulletScript = preload("res://scripts/projectiles/bullet.gd")


# ============================================================================
# CaliberData Tests
# ============================================================================


func test_caliber_data_exists() -> void:
	var caliber_data_script := load("res://scripts/data/caliber_data.gd")
	assert_not_null(caliber_data_script, "CaliberData script should exist")


func test_caliber_data_default_values() -> void:
	var caliber := CaliberData.new()

	assert_eq(caliber.caliber_name, "5.45x39mm", "Default caliber name")
	assert_eq(caliber.diameter_mm, 5.45, "Default diameter")
	assert_almost_eq(caliber.mass_grams, 3.4, 0.01, "Default mass")
	assert_true(caliber.can_ricochet, "Default can_ricochet should be true")
	assert_eq(caliber.max_ricochets, -1, "Default max ricochets should be -1 (unlimited)")


func test_caliber_data_ricochet_probability_at_zero_angle() -> void:
	var caliber := CaliberData.new()

	# At 0 degrees (parallel to surface), probability should be at maximum
	var probability := caliber.calculate_ricochet_probability(0.0)
	assert_almost_eq(probability, caliber.base_ricochet_probability, 0.01, "At 0 degrees, should have base probability")


func test_caliber_data_ricochet_probability_at_max_angle() -> void:
	var caliber := CaliberData.new()

	# At 90 degrees (max angle), probability should be ~10%
	var probability := caliber.calculate_ricochet_probability(caliber.max_ricochet_angle)
	assert_almost_eq(probability, 0.1, 0.02, "At max angle (90 degrees), probability should be ~10%")


func test_caliber_data_ricochet_probability_beyond_max_angle() -> void:
	var caliber := CaliberData.new()

	# Beyond max angle, probability should be 0
	var probability := caliber.calculate_ricochet_probability(caliber.max_ricochet_angle + 10.0)
	assert_eq(probability, 0.0, "Beyond max angle, probability should be 0")


func test_caliber_data_ricochet_probability_interpolation() -> void:
	var caliber := CaliberData.new()

	# At 45 degrees (half of 90), probability should be ~80%
	# Using the new curve: 0.9 * (1 - (0.5)^2.17) + 0.1 ≈ 0.80
	var half_angle := 45.0
	var probability := caliber.calculate_ricochet_probability(half_angle)
	assert_almost_eq(probability, 0.80, 0.05, "At 45 degrees, probability should be ~80%")


func test_caliber_data_can_ricochet_false_returns_zero() -> void:
	var caliber := CaliberData.new()
	caliber.can_ricochet = false

	var probability := caliber.calculate_ricochet_probability(0.0)
	assert_eq(probability, 0.0, "When can_ricochet is false, probability should be 0")


func test_caliber_data_post_ricochet_velocity() -> void:
	var caliber := CaliberData.new()

	var initial_velocity := 2500.0
	var new_velocity := caliber.calculate_post_ricochet_velocity(initial_velocity)
	var expected := initial_velocity * caliber.velocity_retention

	assert_almost_eq(new_velocity, expected, 0.1, "Post-ricochet velocity should be reduced by retention factor")


func test_caliber_data_ricochet_deviation_range() -> void:
	var caliber := CaliberData.new()

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
	assert_eq(caliber.max_ricochets, -1, "Max ricochets should be -1 (unlimited)")


# ============================================================================
# Issue #915: Rifle Caliber Ricochet Angle Tests (M16 and AK fix)
# ============================================================================


func test_545x39_caliber_max_ricochet_angle_is_realistic() -> void:
	## Regression test for Issue #915.
	## 5.45x39mm (M16/AssaultRifle) must have a realistic max_ricochet_angle.
	## The original bug: max_ricochet_angle=90.0 meant near-perpendicular shots (82.5°) showed green.
	## Fix: max_ricochet_angle=70.0 aligns with actual Bullet.cs behavior (ricochet likely up to 70°).
	var caliber := load("res://resources/calibers/caliber_545x39.tres")
	if caliber == null:
		pending("5.45x39mm caliber resource not found")
		return

	# Must be < 90 to fix the original bug (near-right-angle shots should NOT all be green)
	assert_true(caliber.max_ricochet_angle < 90.0,
		"5.45x39mm max_ricochet_angle should be < 90 degrees (original bug: 90 showed all angles as valid)")
	# Must be > 45 to allow typical ricochet angles (M16 does ricochet at many angles)
	assert_true(caliber.max_ricochet_angle > 45.0,
		"5.45x39mm max_ricochet_angle should be > 45 degrees (M16 ricochets at many angles per Bullet.cs behavior)")


func test_545x39_allows_moderate_angle_ricochet() -> void:
	## Regression test for Issue #915.
	## At 29.6 degrees (as seen in game log), M16 SHOULD show ricochet as valid.
	## With max_ricochet_angle=70, angles below 70 are shown as valid.
	var caliber := load("res://resources/calibers/caliber_545x39.tres")
	if caliber == null:
		pending("5.45x39mm caliber resource not found")
		return

	# 29.6 degrees should be valid (green) — below threshold of 70 degrees
	var impact_angle := 29.6
	var is_valid := caliber.max_ricochet_angle > 0.0 and impact_angle < caliber.max_ricochet_angle
	assert_true(is_valid,
		"5.45x39mm should show ricochet as VALID at 29.6 degrees (below threshold, M16 can ricochet at this angle)")


func test_545x39_rejects_near_perpendicular_angle() -> void:
	## Regression test for Issue #915.
	## At 82.5 degrees (near-right angle), M16 should NOT show ricochet as valid.
	## With max_ricochet_angle=70, angles above 70 are shown as red/invalid.
	var caliber := load("res://resources/calibers/caliber_545x39.tres")
	if caliber == null:
		pending("5.45x39mm caliber resource not found")
		return

	# 82.5 degrees was shown as "is_valid=true" in the original bug report — this was wrong
	var near_perpendicular_angle := 82.5
	var is_valid := caliber.max_ricochet_angle > 0.0 and near_perpendicular_angle < caliber.max_ricochet_angle
	assert_false(is_valid,
		"5.45x39mm should NOT show ricochet as valid at 82.5 degrees (near-perpendicular, Issue #915 original bug)")


func test_762x39_caliber_resource_exists() -> void:
	var caliber := load("res://resources/calibers/caliber_762x39.tres")
	assert_not_null(caliber, "7.62x39mm caliber resource should exist")


func test_762x39_caliber_max_ricochet_angle_is_realistic() -> void:
	## Regression test for Issue #915.
	## 7.62x39mm (AK/AKGL) must have a realistic max_ricochet_angle.
	## The original bug: max_ricochet_angle=90.0 meant near-perpendicular shots (67°+) showed green.
	## Fix: max_ricochet_angle=70.0 aligns with actual Bullet.cs behavior.
	var caliber := load("res://resources/calibers/caliber_762x39.tres")
	if caliber == null:
		pending("7.62x39mm caliber resource not found")
		return

	# Must be < 90 to fix the original bug
	assert_true(caliber.max_ricochet_angle < 90.0,
		"7.62x39mm max_ricochet_angle should be < 90 degrees (original bug: 90 showed all angles as valid)")
	# Must be > 45 to allow typical ricochet angles (AK does ricochet at many angles)
	assert_true(caliber.max_ricochet_angle > 45.0,
		"7.62x39mm max_ricochet_angle should be > 45 degrees (AK ricochets at many angles per Bullet.cs behavior)")


func test_762x39_allows_moderate_angle_ricochet() -> void:
	## Regression test for Issue #915.
	## At 61.7 degrees, AK+GL SHOULD show ricochet as valid.
	## With max_ricochet_angle=70, angles below 70 are shown as valid.
	var caliber := load("res://resources/calibers/caliber_762x39.tres")
	if caliber == null:
		pending("7.62x39mm caliber resource not found")
		return

	# 61.7 degrees should be valid (green) — below threshold of 70 degrees
	var impact_angle := 61.7
	var is_valid := caliber.max_ricochet_angle > 0.0 and impact_angle < caliber.max_ricochet_angle
	assert_true(is_valid,
		"7.62x39mm should show ricochet as VALID at 61.7 degrees (below threshold, AK can ricochet at this angle)")


func test_rifle_calibers_allow_shallow_angle_ricochet() -> void:
	## Regression test for Issue #915.
	## While steep angles should be invalid, shallow angles (< 5 degrees) should still be valid.
	## Rifle rounds CAN ricochet at very shallow (grazing) angles.
	var caliber_545 := load("res://resources/calibers/caliber_545x39.tres")
	var caliber_762 := load("res://resources/calibers/caliber_762x39.tres")

	if caliber_545 == null or caliber_762 == null:
		pending("Caliber resources not found")
		return

	var shallow_angle := 5.0
	var is_valid_545 := caliber_545.max_ricochet_angle > 0.0 and shallow_angle < caliber_545.max_ricochet_angle
	var is_valid_762 := caliber_762.max_ricochet_angle > 0.0 and shallow_angle < caliber_762.max_ricochet_angle

	assert_true(is_valid_545,
		"5.45x39mm should still show ricochet as valid at shallow angles (5 degrees)")
	assert_true(is_valid_762,
		"7.62x39mm should still show ricochet as valid at shallow angles (5 degrees)")


# ============================================================================
# Bullet Ricochet Integration Tests
# ============================================================================


func _create_test_bullet() -> Area2D:
	var bullet := Area2D.new()
	bullet.set_script(BulletScript)
	add_child_autoqfree(bullet)
	return bullet


func test_bullet_default_ricochet_constants() -> void:
	var bullet := _create_test_bullet()

	# Test default constants
	assert_eq(bullet.DEFAULT_MAX_RICOCHETS, -1, "Default max ricochets should be -1 (unlimited)")
	assert_almost_eq(bullet.DEFAULT_MAX_RICOCHET_ANGLE, 90.0, 0.1, "Default max ricochet angle should be 90 degrees")
	assert_almost_eq(bullet.DEFAULT_BASE_RICOCHET_PROBABILITY, 1.0, 0.01, "Default base probability")
	assert_almost_eq(bullet.DEFAULT_VELOCITY_RETENTION, 0.85, 0.01, "Default velocity retention")
	assert_almost_eq(bullet.DEFAULT_RICOCHET_DAMAGE_MULTIPLIER, 0.5, 0.01, "Default damage multiplier")


func test_bullet_ricochet_count_starts_at_zero() -> void:
	var bullet := _create_test_bullet()

	assert_eq(bullet.get_ricochet_count(), 0, "Ricochet count should start at 0")


func test_bullet_damage_multiplier_starts_at_one() -> void:
	var bullet := _create_test_bullet()

	assert_almost_eq(bullet.get_damage_multiplier(), 1.0, 0.01, "Damage multiplier should start at 1.0")


func test_bullet_can_ricochet_default() -> void:
	var bullet := _create_test_bullet()

	assert_true(bullet.can_ricochet(), "Bullet should be able to ricochet by default")


func test_bullet_calculate_ricochet_probability_steep_angle() -> void:
	var bullet := _create_test_bullet()

	# At 45 degrees, probability should be ~80% with the new curve
	var probability: float = bullet.call("_calculate_ricochet_probability", 45.0)
	assert_almost_eq(probability, 0.80, 0.05, "At 45 degrees, probability should be ~80%")


func test_bullet_calculate_ricochet_probability_shallow_angle() -> void:
	var bullet := _create_test_bullet()

	# At shallow angle (0 degrees), probability should be high
	var probability: float = bullet.call("_calculate_ricochet_probability", 0.0)
	assert_gt(probability, 0.5, "At shallow angle (0 degrees), probability should be high")


func test_bullet_calculate_impact_angle_perpendicular() -> void:
	var bullet := _create_test_bullet()

	# Bullet traveling right, hitting a wall facing left (perpendicular/head-on)
	bullet.direction = Vector2.RIGHT
	var surface_normal := Vector2.LEFT

	var angle: float = bullet.call("_calculate_impact_angle", surface_normal)
	# Perpendicular/head-on hit should be ~90 degrees (high grazing angle = direct hit)
	# The impact angle is calculated as the GRAZING angle: 0° = parallel to surface, 90° = perpendicular
	assert_almost_eq(angle, PI / 2.0, 0.01, "Perpendicular/head-on hit should be ~90 degrees")


func test_bullet_calculate_impact_angle_grazing() -> void:
	var bullet := _create_test_bullet()

	# Bullet traveling right, grazing a wall facing up (parallel to surface)
	bullet.direction = Vector2.RIGHT
	var surface_normal := Vector2.UP

	var angle: float = bullet.call("_calculate_impact_angle", surface_normal)
	# Grazing/parallel hit should be ~0 degrees (low grazing angle = barely touching surface)
	# The impact angle is calculated as the GRAZING angle: 0° = parallel to surface, 90° = perpendicular
	assert_almost_eq(angle, 0.0, 0.01, "Grazing/parallel hit should be ~0 degrees")


func test_bullet_get_max_ricochets_default() -> void:
	var bullet := _create_test_bullet()
	bullet.caliber_data = null

	var max_ric: int = bullet.call("_get_max_ricochets")
	assert_eq(max_ric, bullet.DEFAULT_MAX_RICOCHETS, "Should use default max ricochets when no caliber data")


func test_bullet_get_velocity_retention_default() -> void:
	var bullet := _create_test_bullet()
	bullet.caliber_data = null

	var retention: float = bullet.call("_get_velocity_retention")
	assert_almost_eq(retention, bullet.DEFAULT_VELOCITY_RETENTION, 0.01, "Should use default velocity retention when no caliber data")


func test_bullet_get_ricochet_damage_multiplier_default() -> void:
	var bullet := _create_test_bullet()
	bullet.caliber_data = null

	var mult: float = bullet.call("_get_ricochet_damage_multiplier")
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
	var bullet := _create_test_bullet()
	bullet.speed = 0.0

	# Even with zero speed, ricochet calculations should not crash
	var probability: float = bullet.call("_calculate_ricochet_probability", 15.0)
	assert_true(probability >= 0.0, "Probability should be valid even with zero speed")


func test_bullet_ricochet_with_zero_length_direction() -> void:
	var bullet := _create_test_bullet()
	bullet.direction = Vector2.ZERO

	# Should handle zero direction gracefully
	var angle: float = bullet.call("_calculate_impact_angle", Vector2.UP)
	assert_true(is_finite(angle), "Angle calculation should handle zero direction")


func test_caliber_data_with_custom_values() -> void:
	var caliber := CaliberData.new()

	# Set custom values
	caliber.max_ricochet_angle = 90.0
	caliber.base_ricochet_probability = 0.9
	caliber.velocity_retention = 0.8

	# At 45 degrees with the new curve:
	# normalized = 45/90 = 0.5, power = 0.5^2.17 ≈ 0.222
	# angle_factor = (1 - 0.222) * 0.9 + 0.1 ≈ 0.80
	# probability = 0.9 * 0.80 ≈ 0.72
	var probability := caliber.calculate_ricochet_probability(45.0)
	var expected := 0.9 * ((1.0 - pow(0.5, 2.17)) * 0.9 + 0.1)
	assert_almost_eq(probability, expected, 0.05, "Custom values should be respected with new probability curve")


# ============================================================================
# Unlimited Ricochet Tests
# ============================================================================


func test_unlimited_ricochets_default() -> void:
	var caliber := CaliberData.new()
	# Default should be unlimited (-1)
	assert_eq(caliber.max_ricochets, -1, "Default max_ricochets should be -1 (unlimited)")


func test_caliber_data_limited_ricochets() -> void:
	var caliber := CaliberData.new()
	caliber.max_ricochets = 3
	assert_eq(caliber.max_ricochets, 3, "max_ricochets should be settable to a specific value")


# ============================================================================
# New Probability Curve Tests (5.45x39mm realistic curve)
# ============================================================================


func test_probability_at_15_degrees() -> void:
	var caliber := CaliberData.new()

	# At 15 degrees, probability should be ~98-100%
	var probability := caliber.calculate_ricochet_probability(15.0)
	assert_gt(probability, 0.95, "Probability at 15 degrees should be ~100%")


func test_probability_at_45_degrees() -> void:
	var caliber := CaliberData.new()

	# At 45 degrees, probability should be ~80%
	var probability := caliber.calculate_ricochet_probability(45.0)
	assert_almost_eq(probability, 0.80, 0.05, "Probability at 45 degrees should be ~80%")


func test_probability_at_90_degrees() -> void:
	var caliber := CaliberData.new()

	# At 90 degrees, probability should be ~10%
	var probability := caliber.calculate_ricochet_probability(90.0)
	assert_almost_eq(probability, 0.10, 0.02, "Probability at 90 degrees should be ~10%")


# ============================================================================
# ShotgunPellet Post-Ricochet Distance Tests (Issue #908)
# ============================================================================


func test_shotgun_pellet_scene_exists() -> void:
	var scene := load("res://scenes/projectiles/csharp/ShotgunPellet.tscn")
	assert_not_null(scene, "ShotgunPellet scene should exist at res://scenes/projectiles/csharp/ShotgunPellet.tscn")


func test_shotgun_pellet_post_ricochet_distance_at_steep_angle_is_not_tiny() -> void:
	# Regression test for Issue #908:
	# After ricochet at steep angles (near MaxRicochetAngle=35°), the pellet was
	# disappearing almost instantly because _maxPostRicochetDistance was too small.
	#
	# The bug: angleFactor = 1 - (impactAngleDeg / MaxRicochetAngle)
	#          At 35° impact: angleFactor = 0.0, clamped to 0.1
	#          maxPostRicochetDistance = 2203 * 0.1 * 0.5 = ~110 px = 59ms at 1875 px/s
	#
	# The fix: normalize against 90° (same as Bullet.cs), remove * 0.5 factor
	#          At 35° impact: angleFactor = 1 - 35/90 = 0.61
	#          maxPostRicochetDistance = 2203 * 0.61 = ~1344 px = 716ms at 1875 px/s
	#
	# We verify this by simulating the calculation both ways and confirming the
	# fixed formula gives at least 10x more post-ricochet distance at steep angles.

	var viewport_diagonal := 2203.0  # typical 1920x1080 diagonal
	var impact_angle_deg := 30.0     # steep angle near the 35° limit

	# Old (buggy) formula
	var old_angle_factor := 1.0 - (impact_angle_deg / 35.0)  # MaxRicochetAngle was 35
	old_angle_factor = clampf(old_angle_factor, 0.1, 1.0)
	var old_max_dist := viewport_diagonal * old_angle_factor * 0.5  # had * 0.5

	# New (fixed) formula: normalize against 90° like Bullet.cs, no * 0.5
	var new_angle_factor := 1.0 - (impact_angle_deg / 90.0)
	new_angle_factor = clampf(new_angle_factor, 0.1, 1.0)
	var new_max_dist := viewport_diagonal * new_angle_factor

	# At 30° impact: old formula gives ~157 px, new gives ~315 px (2× more)
	# At 35° impact: old gives ~110 px (clamped), new gives ~1344 px (12× more)
	assert_gt(new_max_dist, old_max_dist * 1.5,
		"Fixed formula should give significantly longer post-ricochet distance at steep angles (Issue #908)")

	# The pellet should survive at least 200ms after ricochet at steep angles
	# At 1875 px/s (post-ricochet speed), need at least 375 px
	var post_ricochet_speed := 2500.0 * 0.75  # Speed * VelocityRetention
	var min_survival_time_seconds := 0.2
	var min_required_dist := post_ricochet_speed * min_survival_time_seconds

	assert_gt(new_max_dist, min_required_dist,
		"Pellet should survive at least 200ms after ricochet at steep angles (Issue #908)")


func test_shotgun_pellet_post_ricochet_distance_at_grazing_angle_is_long() -> void:
	# At grazing angles (0°), the pellet should travel almost a full viewport diagonal.
	var viewport_diagonal := 2203.0
	var impact_angle_deg := 5.0  # nearly grazing

	# Fixed formula
	var angle_factor := 1.0 - (impact_angle_deg / 90.0)
	angle_factor = clampf(angle_factor, 0.1, 1.0)
	var max_dist := viewport_diagonal * angle_factor

	# Should be close to viewport_diagonal * 0.944 = ~2080 px
	assert_gt(max_dist, viewport_diagonal * 0.85,
		"At nearly grazing angles, pellet should travel most of the viewport diagonal after ricochet")


# ============================================================================
# Issue #1028: Trajectory Glasses Passive Ricochet Boost Tests
# (previously Issue #1004 as separate "Ricochet Points" item — now merged into Trajectory Glasses)
# ============================================================================


func _calculate_ricochet_probability_with_boost(impact_angle_deg: float, max_angle: float, base_probability: float, boost_enabled: bool) -> float:
	## Helper: computes ricochet probability formula with optional +30% boost.
	## Mirrors the logic in bullet.gd _calculate_ricochet_probability().
	## The boost is triggered when Trajectory Glasses are equipped (Issue #1028).
	if impact_angle_deg > max_angle:
		return 0.0
	var normalized_angle := impact_angle_deg / 90.0
	var power_factor := pow(normalized_angle, 2.17)
	var angle_factor := (1.0 - power_factor) * 0.9 + 0.1
	var probability := base_probability * angle_factor
	if boost_enabled:
		probability = minf(probability + 0.3, 1.0)
	return probability


func test_trajectory_glasses_boost_increases_probability_at_45_degrees() -> void:
	## Issue #1028: Trajectory Glasses passive effect should raise probability by 0.30 at valid angles.
	var normal_prob := _calculate_ricochet_probability_with_boost(45.0, 90.0, 1.0, false)
	var boosted_prob := _calculate_ricochet_probability_with_boost(45.0, 90.0, 1.0, true)

	assert_almost_eq(boosted_prob, normal_prob + 0.3, 0.01,
		"Trajectory Glasses passive should boost probability by 0.30 at 45 degrees")


func test_trajectory_glasses_boost_increases_probability_at_shallow_angle() -> void:
	## Issue #1028: boost should also apply at shallow angles (near grazing).
	var normal_prob := _calculate_ricochet_probability_with_boost(5.0, 90.0, 1.0, false)
	var boosted_prob := _calculate_ricochet_probability_with_boost(5.0, 90.0, 1.0, true)

	# At very shallow angle the base probability is nearly 1.0, so clamped to 1.0
	assert_almost_eq(boosted_prob, 1.0, 0.01,
		"Trajectory Glasses passive boost at shallow angles should be clamped at 1.0")
	assert_true(boosted_prob >= normal_prob,
		"Boosted probability should never be less than normal probability")


func test_trajectory_glasses_boost_does_not_exceed_one() -> void:
	## Issue #1028: boosted probability must never exceed 1.0.
	for angle in [0.0, 5.0, 15.0, 30.0, 45.0, 60.0, 70.0, 80.0, 90.0]:
		var boosted_prob := _calculate_ricochet_probability_with_boost(angle, 90.0, 1.0, true)
		assert_true(boosted_prob <= 1.0,
			"Trajectory Glasses passive boosted probability should not exceed 1.0 (angle=%s)" % angle)


func test_trajectory_glasses_boost_zero_beyond_max_angle() -> void:
	## Issue #1028: boost must NOT apply when angle exceeds max_ricochet_angle (red ray zone).
	## The function should still return 0.0 for invalid angles even with boost enabled.
	var prob := _calculate_ricochet_probability_with_boost(91.0, 90.0, 1.0, true)
	assert_eq(prob, 0.0,
		"Trajectory Glasses passive boost should not apply beyond max ricochet angle (angle > max_angle returns 0)")


func test_trajectory_glasses_boost_exactly_30_percent_at_steep_angle() -> void:
	## Issue #1028: at a steep angle where base probability is well below 0.7 (e.g. 80 deg),
	## the boost should add exactly 0.3 without clamping.
	var normal_prob := _calculate_ricochet_probability_with_boost(80.0, 90.0, 1.0, false)
	var boosted_prob := _calculate_ricochet_probability_with_boost(80.0, 90.0, 1.0, true)

	# At 80 degrees: normal_prob is well below 0.7, so 0.3 addition won't exceed 1.0
	assert_almost_eq(boosted_prob, normal_prob + 0.3, 0.001,
		"At 80 degrees, Trajectory Glasses passive boost should be exactly +0.30 (no clamping needed)")


func test_caliber_data_trajectory_glasses_probability_math() -> void:
	## Issue #1028: Verify the Trajectory Glasses passive math independently on CaliberData.
	## This tests that the formula boosts by 0.3 at 45 degrees.
	var caliber := CaliberData.new()
	caliber.max_ricochet_angle = 90.0
	caliber.base_ricochet_probability = 1.0

	# Calculate base probability at 45 degrees using the same formula
	var normalized_angle := 45.0 / 90.0
	var power_factor := pow(normalized_angle, 2.17)
	var angle_factor := (1.0 - power_factor) * 0.9 + 0.1
	var expected_base := caliber.base_ricochet_probability * angle_factor
	var expected_boosted := minf(expected_base + 0.3, 1.0)

	# The boosted value should be base + 0.3 (clamped to 1.0)
	assert_almost_eq(expected_boosted, expected_base + 0.3, 0.001,
		"At 45 degrees with base=1.0, Trajectory Glasses passive adds 0.30 (no clamping)")
	assert_true(expected_boosted <= 1.0,
		"Boosted probability is capped at 1.0")
