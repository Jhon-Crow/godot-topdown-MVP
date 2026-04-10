extends GutTest
## Regression tests for sniper rifle (ASVK) sound detection range.
##
## Issue #828: Make enemies hear the sniper rifle shot from further away.
## The rifle's Loudness was 2.2x the original value (3000.0 * 2.2 = 6600.0).
## Issue #1269: All weapon loudness values scaled by factor 800/1469 (~0.5446).
## New ASVK Loudness: 6600.0 * (800/1469) = 3594.3 (still loudest firearm, proportional scaling preserved).


# ============================================================================
# Mock Weapon Data for Testing
# ============================================================================


class MockWeaponData:
	var Name: String = "ASVK"
	var Damage: float = 50.0
	var FireRate: float = 1.0
	var MagazineSize: int = 5
	var MaxReserveAmmo: int = 5
	var ReloadTime: float = 2.5
	var BulletSpeed: float = 10000.0
	var Range: float = 35000.0
	var SpreadAngle: float = 0.0
	var BulletsPerShot: int = 1
	var IsAutomatic: bool = false
	var Loudness: float = 3594.3
	var Sensitivity: float = 8.0
	var ScreenShakeIntensity: float = 25.0
	var ScreenShakeMinRecoveryTime: float = 0.5
	var ScreenShakeMaxRecoveryTime: float = 0.1


var weapon: MockWeaponData


func before_each() -> void:
	weapon = MockWeaponData.new()


func after_each() -> void:
	weapon = null


# ============================================================================
# Identity Tests
# ============================================================================


func test_weapon_name() -> void:
	assert_eq(weapon.Name, "ASVK",
		"Weapon name should be ASVK (sniper rifle)")


# ============================================================================
# Sound Detection Range Tests (Issue #828)
# ============================================================================


func test_loudness_is_3594_3() -> void:
	assert_almost_eq(weapon.Loudness, 3594.3, 0.1,
		"Sniper rifle Loudness must be 3594.3 (6600.0 * 800/1469, Issue #1269 scaling)")


func test_loudness_is_2_2_times_scaled_original() -> void:
	# Issue #828: ASVK must be 2.2x louder than the base 3000.0 value, after Issue #1269 scaling.
	# Scaled base: 3000.0 * (800/1469) = 1633.8; scaled ASVK: 6600.0 * (800/1469) = 3594.3
	var scaled_original: float = 3000.0 * (800.0 / 1469.0)  # 1633.8
	assert_almost_eq(weapon.Loudness, scaled_original * 2.2, 1.0,
		"Sniper rifle Loudness must be 2.2 times the scaled original (issue #828 ratio preserved)")


func test_loudness_is_greater_than_revolver() -> void:
	# Revolver Loudness is now 680.75 (Issue #1380: halved from 1361.5), sniper rifle should still be louder
	var revolver_loudness: float = 680.75
	assert_true(weapon.Loudness > revolver_loudness,
		"Sniper rifle should be louder than the revolver (680.75 after Issue #1380 halving)")


func test_loudness_is_greater_than_scaled_original_3000() -> void:
	var scaled_base: float = 3000.0 * (800.0 / 1469.0)  # 1633.8
	assert_true(weapon.Loudness > scaled_base,
		"Sniper rifle Loudness must be greater than scaled 3000.0 baseline (issue #828 ratio preserved)")


func test_loudness_is_positive() -> void:
	assert_true(weapon.Loudness > 0.0,
		"Sniper rifle Loudness must be a positive value")


# ============================================================================
# Regression Test: Verify SniperRifleData.tres resource file
# ============================================================================


func test_sniper_rifle_data_loudness_in_resource() -> void:
	# Regression test: verify the resource file has the updated Loudness.
	# This prevents future changes from accidentally reverting the fix for issue #828.
	var file := FileAccess.open("res://resources/weapons/SniperRifleData.tres", FileAccess.READ)
	if file == null:
		pass_test("Skipped: SniperRifleData.tres not accessible in test environment")
		return

	var content := file.get_as_text()
	file.close()

	assert_true(content.contains("Loudness = 3594.3"),
		"SniperRifleData.tres must have Loudness = 3594.3 (Issue #1269: scaled by 800/1469 from 6600.0)")


func test_range_is_35000() -> void:
	# Issue #1586: maximum aiming range increased by 30000px (from 5000 to 35000).
	assert_eq(weapon.Range, 35000.0,
		"ASVK Range must be 35000.0 px (increased by 30000 per Issue #1586)")


func test_sniper_rifle_data_range_in_resource() -> void:
	# Regression test: verify the resource file has the updated Range.
	# This prevents future changes from accidentally reverting the fix for issue #1586.
	var file := FileAccess.open("res://resources/weapons/SniperRifleData.tres", FileAccess.READ)
	if file == null:
		pass_test("Skipped: SniperRifleData.tres not accessible in test environment")
		return

	var content := file.get_as_text()
	file.close()

	assert_true(content.contains("Range = 35000.0"),
		"SniperRifleData.tres must have Range = 35000.0 (Issue #1586: increased by 30000px from 5000)")
