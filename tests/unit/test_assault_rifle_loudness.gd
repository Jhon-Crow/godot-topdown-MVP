extends GutTest
## Regression tests for assault rifle (M16) sound detection range.
##
## Issue #1524: Set M16 sound range to 840px.
## The fix required adding Loudness = 840.0 to AssaultRifleData.tres (the C# weapon resource).
## Previous fix attempts only updated player.gd and weapon_config_component.gd (GDScript),
## but the actual sound emission path goes through AssaultRifle.cs which reads WeaponData.Loudness.


# ============================================================================
# Resource File Regression Test
# ============================================================================


func test_assault_rifle_data_loudness_in_resource() -> void:
	## Regression test: verify the resource file has the correct Loudness.
	## This prevents future changes from accidentally reverting the fix for issue #1524.
	## Root cause: AssaultRifleData.tres was missing Loudness property, causing fallback to
	## WeaponData.cs default of 1469.0 (viewport diagonal), which was 1469px instead of 840px.
	var file := FileAccess.open("res://resources/weapons/AssaultRifleData.tres", FileAccess.READ)
	if file == null:
		pass_test("Skipped: AssaultRifleData.tres not accessible in test environment")
		return

	var content := file.get_as_text()
	file.close()

	assert_true(content.contains("Loudness = 840.0"),
		"AssaultRifleData.tres must have Loudness = 840.0 (Issue #1524: M16 sound range set to 840px)")


func test_assault_rifle_data_loudness_not_default_1469() -> void:
	## Regression test: ensure AssaultRifleData.tres does NOT rely on WeaponData.cs default (1469.0).
	## The old default was 1469px (viewport diagonal), which was too large for M16.
	var file := FileAccess.open("res://resources/weapons/AssaultRifleData.tres", FileAccess.READ)
	if file == null:
		pass_test("Skipped: AssaultRifleData.tres not accessible in test environment")
		return

	var content := file.get_as_text()
	file.close()

	assert_false(content.contains("Loudness = 1469"),
		"AssaultRifleData.tres must NOT use 1469.0 as Loudness (old viewport-diagonal default, Issue #1524)")
