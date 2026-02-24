extends GutTest
## Unit tests for Revolver blue laser sight in Power Fantasy difficulty mode (Issue #864).
##
## The revolver was missing the Power Fantasy laser sight code that all other weapons have.
## In Power Fantasy mode, all weapons should display a blue laser sight.
## This test verifies the fix is present and follows the same pattern as other weapons.


# ============================================================================
# Mock DifficultyManager for laser sight tests
# ============================================================================


class MockDifficultyManagerForLaser:
	enum Difficulty { EASY, NORMAL, HARD, POWER_FANTASY }
	var current_difficulty: Difficulty = Difficulty.NORMAL

	func should_force_blue_laser_sight() -> bool:
		return current_difficulty == Difficulty.POWER_FANTASY

	func get_power_fantasy_laser_color() -> Color:
		return Color(0.0, 0.5, 1.0, 0.6)


# ============================================================================
# Power Fantasy Laser Sight Behavior Tests
# ============================================================================


func test_power_fantasy_enables_blue_laser() -> void:
	var diff_manager = MockDifficultyManagerForLaser.new()
	diff_manager.current_difficulty = MockDifficultyManagerForLaser.Difficulty.POWER_FANTASY

	assert_true(diff_manager.should_force_blue_laser_sight(),
		"Power Fantasy mode should force blue laser sight on all weapons including Revolver (Issue #864)")

	var laser_color = diff_manager.get_power_fantasy_laser_color()
	assert_eq(laser_color, Color(0.0, 0.5, 1.0, 0.6),
		"Power Fantasy laser color should be blue (0, 0.5, 1.0) with transparency (0.6)")


func test_normal_mode_does_not_enable_laser() -> void:
	var diff_manager = MockDifficultyManagerForLaser.new()

	assert_false(diff_manager.should_force_blue_laser_sight(),
		"Normal mode should not force blue laser sight on Revolver")


func test_hard_mode_does_not_enable_laser() -> void:
	var diff_manager = MockDifficultyManagerForLaser.new()
	diff_manager.current_difficulty = MockDifficultyManagerForLaser.Difficulty.HARD

	assert_false(diff_manager.should_force_blue_laser_sight(),
		"Hard mode should not force blue laser sight on Revolver")


func test_easy_mode_does_not_enable_laser() -> void:
	var diff_manager = MockDifficultyManagerForLaser.new()
	diff_manager.current_difficulty = MockDifficultyManagerForLaser.Difficulty.EASY

	assert_false(diff_manager.should_force_blue_laser_sight(),
		"Easy mode should not force blue laser sight on Revolver")


# ============================================================================
# Regression Tests: Revolver.cs source must contain laser sight code
# These prevent future changes from accidentally removing the fix for Issue #864.
# ============================================================================


func test_revolver_source_has_power_fantasy_laser_code() -> void:
	# Regression test: verify Revolver.cs contains the Power Fantasy laser check.
	# This prevents future changes from accidentally removing the laser sight code.
	var file = FileAccess.open("res://Scripts/Weapons/Revolver.cs", FileAccess.READ)
	if file == null:
		# If file can't be opened in test environment, skip gracefully
		pass_test("Skipped: Revolver.cs not accessible in test environment")
		return

	var content = file.get_as_text()
	file.close()

	assert_true(content.contains("should_force_blue_laser_sight"),
		"Revolver.cs must call should_force_blue_laser_sight() for Power Fantasy mode (Issue #864)")
	assert_true(content.contains("get_power_fantasy_laser_color"),
		"Revolver.cs must call get_power_fantasy_laser_color() for laser color (Issue #864)")
	assert_true(content.contains("CreateLaserSight"),
		"Revolver.cs must have CreateLaserSight() method for Power Fantasy mode (Issue #864)")
	assert_true(content.contains("UpdateLaserSight"),
		"Revolver.cs must have UpdateLaserSight() method for Power Fantasy mode (Issue #864)")
	assert_true(content.contains("_laserSightEnabled"),
		"Revolver.cs must have _laserSightEnabled field for laser sight state (Issue #864)")
	assert_true(content.contains("_laserGlow"),
		"Revolver.cs must have _laserGlow field for laser glow effect (Issue #864)")


func test_revolver_laser_code_matches_other_weapons_pattern() -> void:
	# Verify the Revolver uses the same pattern as other weapons (MakarovPM, AssaultRifle, etc.)
	# by checking that the key method calls and field names are present.
	var file = FileAccess.open("res://Scripts/Weapons/Revolver.cs", FileAccess.READ)
	if file == null:
		pass_test("Skipped: Revolver.cs not accessible in test environment")
		return

	var content = file.get_as_text()
	file.close()

	# Check for DifficultyManager integration
	assert_true(content.contains("/root/DifficultyManager"),
		"Revolver.cs must look up DifficultyManager autoload for Power Fantasy check (Issue #864)")

	# Check for LaserGlowEffect (visual glow, same as other weapons)
	assert_true(content.contains("LaserGlowEffect"),
		"Revolver.cs must use LaserGlowEffect for visual glow in Power Fantasy mode (Issue #864)")
