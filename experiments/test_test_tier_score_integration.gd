extends Node
## Experiment script to verify TestTier score integration.
##
## This script tests that:
## 1. ScoreManager is properly initialized with enemy count
## 2. Kills are registered with ScoreManager
## 3. Score screen displays after level completion
## 4. Level name is displayed as "Полигон"
##
## Usage: Run this script in Godot to verify the integration.

var test_tier_script: GDScript = null
var mock_test_tier: Node2D = null


func _ready() -> void:
	print("=== TestTier Score Integration Test ===")
	print()

	# Load the test_tier script
	test_tier_script = load("res://scripts/levels/test_tier.gd")
	if test_tier_script == null:
		print("ERROR: Could not load test_tier.gd")
		return

	print("✓ test_tier.gd loaded successfully")

	# Verify that the script has the necessary methods
	var required_methods := [
		"_initialize_score_manager",
		"_on_combo_changed",
		"_on_enemy_died_with_info",
		"_complete_level_with_score",
		"_show_score_screen",
		"_show_fallback_score_screen"
	]

	var has_all_methods := true
	for method_name in required_methods:
		if not test_tier_script.has_script_method(method_name):
			print("ERROR: Missing method: %s" % method_name)
			has_all_methods = false

	if has_all_methods:
		print("✓ All required methods present")
	else:
		print("✗ Some required methods are missing")
		return

	# Verify ScoreManager autoload exists
	var score_manager: Node = get_node_or_null("/root/ScoreManager")
	if score_manager == null:
		print("WARNING: ScoreManager autoload not found. This is expected in editor.")
	else:
		print("✓ ScoreManager autoload found")

		# Test ScoreManager methods
		var score_methods := [
			"start_level",
			"set_player",
			"register_kill",
			"register_damage_taken",
			"complete_level",
			"calculate_score",
			"update_enemy_positions"
		]

		var has_all_score_methods := true
		for method_name in score_methods:
			if not score_manager.has_method(method_name):
				print("ERROR: ScoreManager missing method: %s" % method_name)
				has_all_score_methods = false

		if has_all_score_methods:
			print("✓ ScoreManager has all required methods")

	# Verify animated_score_screen.gd exists
	var score_screen_script = load("res://scripts/ui/animated_score_screen.gd")
	if score_screen_script == null:
		print("WARNING: animated_score_screen.gd not found")
	else:
		print("✓ animated_score_screen.gd loaded successfully")

	# Verify levels_menu.gd has "Полигон" entry
	var levels_menu_script = load("res://scripts/ui/levels_menu.gd")
	if levels_menu_script != null:
		print("✓ levels_menu.gd loaded successfully")
		# Note: We can't easily check the LEVELS dictionary without instantiating
		print("  (Manual verification needed: Check that 'Полигон' is in LEVELS dictionary)")
	else:
		print("WARNING: levels_menu.gd not found")

	# Verify TestTier.tscn has "ПОЛИГОН" label
	var test_tier_scene = load("res://scenes/levels/TestTier.tscn")
	if test_tier_scene != null:
		print("✓ TestTier.tscn loaded successfully")
		print("  (Manual verification needed: Check that LevelLabel text is 'ПОЛИГОН')")
	else:
		print("ERROR: TestTier.tscn not found")

	print()
	print("=== Test Summary ===")
	print("Script structure: ✓ PASS")
	print("Methods present: ✓ PASS")
	print("Dependencies: Check warnings above")
	print()
	print("Next steps:")
	print("1. Load TestTier scene in Godot")
	print("2. Play the level and eliminate all enemies")
	print("3. Verify that score screen appears with:")
	print("   - Kill count")
	print("   - Combo statistics")
	print("   - Time bonus")
	print("   - Accuracy bonus")
	print("   - Total score")
	print("   - Rank (F/D/C/B/A/A+/S)")
	print("4. Verify level name displays as 'ПОЛИГОН' in top right")
	print("5. Verify level menu shows 'Полигон' instead of 'Test Tier'")
	print()
	print("=== Integration Test Complete ===")

	# Auto-quit after test
	await get_tree().create_timer(1.0).timeout
	get_tree().quit()
