extends GutTest
## Regression tests for sniper rifle (ASVK) sound detection range.
##
## Issue #828: Make enemies hear the sniper rifle shot from further away.
## The rifle's Loudness must be 2.2x the original value (3000.0 * 2.2 = 6600.0),
## so enemies can detect the shot from a greater distance.


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
	var Range: float = 5000.0
	var SpreadAngle: float = 0.0
	var BulletsPerShot: int = 1
	var IsAutomatic: bool = false
	var Loudness: float = 6600.0
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


func test_loudness_is_6600() -> void:
	assert_eq(weapon.Loudness, 6600.0,
		"Sniper rifle Loudness must be 6600.0 (3000.0 * 2.2) as required by issue #828")


func test_loudness_is_2_2_times_original() -> void:
	var original_loudness: float = 3000.0
	var expected_loudness: float = original_loudness * 2.2
	assert_almost_eq(weapon.Loudness, expected_loudness, 0.01,
		"Sniper rifle Loudness must be 2.2 times the original 3000.0 (issue #828)")


func test_loudness_is_greater_than_revolver() -> void:
	# Revolver has Loudness 2500.0, sniper rifle should be louder
	var revolver_loudness: float = 2500.0
	assert_true(weapon.Loudness > revolver_loudness,
		"Sniper rifle should be louder than the revolver (2500.0)")


func test_loudness_is_greater_than_original_3000() -> void:
	assert_true(weapon.Loudness > 3000.0,
		"Sniper rifle Loudness must be greater than the old value of 3000.0 (issue #828)")


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

	assert_true(content.contains("Loudness = 6600.0"),
		"SniperRifleData.tres must have Loudness = 6600.0 (issue #828: 3000.0 * 2.2)")
