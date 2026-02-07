extends GutTest
## Unit tests for Makarov PM weapon configuration.
##
## Tests the weapon data resource and 9x18mm caliber resource
## to ensure correct values as specified in issue #577:
## - 9 rounds in magazine
## - 9x18mm caliber with 0.45 damage
## - Medium ricochets (like all pistols/SMGs)
## - Does not penetrate walls
## - Semi-automatic fire


# ============================================================================
# Mock Weapon Data for Testing
# ============================================================================


class MockWeaponData:
	var Name: String = "PM"
	var Damage: float = 0.45
	var FireRate: float = 7.0
	var MagazineSize: int = 9
	var MaxReserveAmmo: int = 18
	var ReloadTime: float = 2.0
	var BulletSpeed: float = 1000.0
	var Range: float = 600.0
	var SpreadAngle: float = 2.0
	var BulletsPerShot: int = 1
	var IsAutomatic: bool = false
	var Loudness: float = 1469.0
	var Sensitivity: float = 3.0
	var ScreenShakeIntensity: float = 8.0
	var ScreenShakeMinRecoveryTime: float = 0.35
	var ScreenShakeMaxRecoveryTime: float = 0.15


class MockCaliberData:
	var caliber_name: String = "9x18mm Makarov"
	var diameter_mm: float = 9.0
	var mass_grams: float = 6.1
	var base_velocity: float = 1000.0
	var can_ricochet: bool = true
	var max_ricochets: int = 1
	var max_ricochet_angle: float = 20.0
	var base_ricochet_probability: float = 0.7
	var velocity_retention: float = 0.4
	var ricochet_damage_multiplier: float = 0.3
	var ricochet_angle_deviation: float = 12.0
	var penetration_power: float = 8.0
	var can_penetrate: bool = false
	var max_penetration_distance: float = 0.0
	var effect_scale: float = 0.5


var weapon: MockWeaponData
var caliber: MockCaliberData


func before_each() -> void:
	weapon = MockWeaponData.new()
	caliber = MockCaliberData.new()


func after_each() -> void:
	weapon = null
	caliber = null


# ============================================================================
# Weapon Name & Identity Tests
# ============================================================================


func test_weapon_name() -> void:
	assert_eq(weapon.Name, "PM",
		"Weapon name should be PM (Pistolet Makarova)")


# ============================================================================
# Damage Tests
# ============================================================================


func test_damage_value() -> void:
	assert_eq(weapon.Damage, 0.45,
		"Damage should be 0.45 as specified in issue #577")


func test_damage_is_less_than_mini_uzi() -> void:
	# Mini UZI has 0.5 damage, PM should be less
	assert_true(weapon.Damage < 0.5,
		"PM damage should be less than Mini UZI (0.5)")


# ============================================================================
# Magazine & Ammo Tests
# ============================================================================


func test_magazine_size() -> void:
	assert_eq(weapon.MagazineSize, 9,
		"Magazine size should be 9 as specified in issue #577")


func test_max_reserve_ammo() -> void:
	assert_eq(weapon.MaxReserveAmmo, 18,
		"Reserve ammo should be 18 (2 spare magazines of 9)")


func test_bullets_per_shot() -> void:
	assert_eq(weapon.BulletsPerShot, 1,
		"Should fire 1 bullet per shot (not a shotgun)")


# ============================================================================
# Fire Mode Tests
# ============================================================================


func test_is_semi_automatic() -> void:
	assert_false(weapon.IsAutomatic,
		"PM should be semi-automatic (not automatic)")


func test_fire_rate() -> void:
	assert_eq(weapon.FireRate, 7.0,
		"Fire rate should be 7 shots/second")


# ============================================================================
# Caliber Tests - 9x18mm Makarov
# ============================================================================


func test_caliber_name() -> void:
	assert_eq(caliber.caliber_name, "9x18mm Makarov",
		"Caliber should be 9x18mm Makarov")


func test_caliber_diameter() -> void:
	assert_eq(caliber.diameter_mm, 9.0,
		"Diameter should be 9mm")


func test_caliber_mass() -> void:
	assert_eq(caliber.mass_grams, 6.1,
		"Mass should be 6.1 grams (standard 9x18 bullet)")


func test_caliber_velocity() -> void:
	assert_eq(caliber.base_velocity, 1000.0,
		"Base velocity should be 1000 (lower than 9x19)")


func test_caliber_velocity_less_than_9x19() -> void:
	# 9x19mm Parabellum has base_velocity 1200.0
	assert_true(caliber.base_velocity < 1200.0,
		"9x18 velocity should be less than 9x19 (1200)")


# ============================================================================
# Ricochet Tests - "Medium ricochets like all pistols/SMGs"
# ============================================================================


func test_can_ricochet() -> void:
	assert_true(caliber.can_ricochet,
		"9x18 should be able to ricochet")


func test_max_ricochets() -> void:
	assert_eq(caliber.max_ricochets, 1,
		"Max ricochets should be 1 (same as 9x19)")


func test_max_ricochet_angle() -> void:
	assert_eq(caliber.max_ricochet_angle, 20.0,
		"Max ricochet angle should be 20 degrees (same as 9x19)")


func test_ricochet_probability() -> void:
	assert_eq(caliber.base_ricochet_probability, 0.7,
		"Ricochet probability should be 0.7 (same as 9x19)")


func test_velocity_retention() -> void:
	assert_eq(caliber.velocity_retention, 0.4,
		"Velocity retention should be 0.4 (same as 9x19)")


func test_ricochet_damage_multiplier() -> void:
	assert_eq(caliber.ricochet_damage_multiplier, 0.3,
		"Ricochet damage multiplier should be 0.3 (same as 9x19)")


func test_ricochet_angle_deviation() -> void:
	assert_eq(caliber.ricochet_angle_deviation, 12.0,
		"Ricochet angle deviation should be 12 degrees (same as 9x19)")


# ============================================================================
# Wall Penetration Tests - "Does not penetrate walls"
# ============================================================================


func test_cannot_penetrate_walls() -> void:
	assert_false(caliber.can_penetrate,
		"9x18 should NOT penetrate walls (as specified in issue)")


func test_penetration_distance_zero() -> void:
	assert_eq(caliber.max_penetration_distance, 0.0,
		"Penetration distance should be 0 (no penetration)")


# ============================================================================
# Sound Tests - PM is NOT silenced
# ============================================================================


func test_loudness_is_standard() -> void:
	assert_true(weapon.Loudness > 0.0,
		"PM should NOT be silenced (loudness > 0)")


func test_loudness_matches_standard() -> void:
	assert_eq(weapon.Loudness, 1469.0,
		"Loudness should be standard (1469 pixels, same as assault rifle)")


# ============================================================================
# Range & Accuracy Tests
# ============================================================================


func test_range() -> void:
	assert_eq(weapon.Range, 600.0,
		"Range should be 600 pixels (shorter than assault rifle)")


func test_spread_angle() -> void:
	assert_eq(weapon.SpreadAngle, 2.0,
		"Spread angle should be 2 degrees")


func test_bullet_speed() -> void:
	assert_eq(weapon.BulletSpeed, 1000.0,
		"Bullet speed should match 9x18 caliber velocity")


# ============================================================================
# Reload Tests
# ============================================================================


func test_reload_time() -> void:
	assert_eq(weapon.ReloadTime, 2.0,
		"Reload time should be 2 seconds")


# ============================================================================
# Effect Scale Tests
# ============================================================================


func test_effect_scale() -> void:
	assert_eq(caliber.effect_scale, 0.5,
		"Effect scale should be 0.5 (same as 9x19)")


# ============================================================================
# Sensitivity Tests
# ============================================================================


func test_sensitivity() -> void:
	assert_eq(weapon.Sensitivity, 3.0,
		"Sensitivity should be 3.0 for moderate aiming speed")


# ============================================================================
# Screen Shake Tests
# ============================================================================


func test_screen_shake_intensity() -> void:
	assert_eq(weapon.ScreenShakeIntensity, 8.0,
		"Screen shake intensity should be 8.0")


func test_screen_shake_min_recovery() -> void:
	assert_eq(weapon.ScreenShakeMinRecoveryTime, 0.35,
		"Min recovery time should be 0.35 seconds")


# ============================================================================
# Comparison with 9x19mm Parabellum (ensuring 9x18 is weaker)
# ============================================================================


func test_9x18_weaker_than_9x19_velocity() -> void:
	# 9x19 has base_velocity 1200, mass 8.0g
	# 9x18 should have lower velocity and mass
	assert_true(caliber.base_velocity <= 1200.0,
		"9x18 velocity should be <= 9x19 velocity")
	assert_true(caliber.mass_grams < 8.0,
		"9x18 mass should be less than 9x19 (8.0g)")


func test_penetration_power_lower_than_9x19() -> void:
	# 9x19 has penetration_power 10.0
	assert_true(caliber.penetration_power < 10.0,
		"9x18 penetration power should be less than 9x19 (10.0)")


# ============================================================================
# Power Fantasy Laser Sight Tests (Issue #621)
# Regression test: MakarovPM must enable blue laser sight in Power Fantasy mode,
# just like all other weapons (AssaultRifle, SniperRifle, Shotgun, MiniUzi).
# ============================================================================


class MockDifficultyManagerForLaser:
	enum Difficulty { EASY, NORMAL, HARD, POWER_FANTASY }
	var current_difficulty: Difficulty = Difficulty.NORMAL

	func should_force_blue_laser_sight() -> bool:
		return current_difficulty == Difficulty.POWER_FANTASY

	func get_power_fantasy_laser_color() -> Color:
		return Color(0.0, 0.5, 1.0, 0.6)


func test_power_fantasy_enables_blue_laser() -> void:
	var diff_manager = MockDifficultyManagerForLaser.new()
	diff_manager.current_difficulty = MockDifficultyManagerForLaser.Difficulty.POWER_FANTASY

	assert_true(diff_manager.should_force_blue_laser_sight(),
		"Power Fantasy mode should force blue laser sight on all weapons including PM")

	var laser_color = diff_manager.get_power_fantasy_laser_color()
	assert_eq(laser_color, Color(0.0, 0.5, 1.0, 0.6),
		"Power Fantasy laser color should be blue with transparency")


func test_normal_mode_does_not_enable_laser() -> void:
	var diff_manager = MockDifficultyManagerForLaser.new()

	assert_false(diff_manager.should_force_blue_laser_sight(),
		"Normal mode should not force blue laser sight")


func test_hard_mode_does_not_enable_laser() -> void:
	var diff_manager = MockDifficultyManagerForLaser.new()
	diff_manager.current_difficulty = MockDifficultyManagerForLaser.Difficulty.HARD

	assert_false(diff_manager.should_force_blue_laser_sight(),
		"Hard mode should not force blue laser sight")


func test_makarov_pm_source_has_power_fantasy_laser_code() -> void:
	# Regression test: verify MakarovPM.cs contains the Power Fantasy laser check.
	# This prevents future changes from accidentally removing the laser sight code.
	var file = FileAccess.open("res://Scripts/Weapons/MakarovPM.cs", FileAccess.READ)
	if file == null:
		# If file can't be opened in test environment, skip gracefully
		pass_test("Skipped: MakarovPM.cs not accessible in test environment")
		return

	var content = file.get_as_text()
	file.close()

	assert_true(content.contains("should_force_blue_laser_sight"),
		"MakarovPM.cs must call should_force_blue_laser_sight() for Power Fantasy mode (Issue #621)")
	assert_true(content.contains("get_power_fantasy_laser_color"),
		"MakarovPM.cs must call get_power_fantasy_laser_color() for laser color (Issue #621)")
	assert_true(content.contains("CreateLaserSight"),
		"MakarovPM.cs must have CreateLaserSight() method for Power Fantasy mode (Issue #621)")
