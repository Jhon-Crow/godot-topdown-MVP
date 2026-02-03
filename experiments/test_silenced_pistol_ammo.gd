extends Node
## Test script to verify silenced pistol ammo calculation logic.
## This script validates that the ammo distribution matches the requirements:
## - Total ammo equals enemy count
## - Ammo is distributed across magazines correctly
##
## Run this script to verify the calculations without launching the full game.

func _ready() -> void:
	print("=== Silenced Pistol Ammo Calculation Test ===\n")

	# Test cases based on issue requirements
	var test_cases := [
		{"enemies": 10, "expected_loaded": 10, "expected_spare": 0, "expected_total": 10},
		{"enemies": 26, "expected_loaded": 13, "expected_spare": 13, "expected_total": 26},
		{"enemies": 13, "expected_loaded": 13, "expected_spare": 0, "expected_total": 13},
		{"enemies": 27, "expected_loaded": 1, "expected_spare": 26, "expected_total": 27},
		{"enemies": 39, "expected_loaded": 13, "expected_spare": 26, "expected_total": 39},
		{"enemies": 0, "expected_loaded": 0, "expected_spare": 0, "expected_total": 0},
		{"enemies": 5, "expected_loaded": 5, "expected_spare": 0, "expected_total": 5},
		{"enemies": 52, "expected_loaded": 13, "expected_spare": 39, "expected_total": 52},
	]

	var magazine_capacity := 13
	var passed := 0
	var failed := 0

	for test in test_cases:
		var enemy_count: int = test["enemies"]
		var result := calculate_ammo_distribution(enemy_count, magazine_capacity)

		var loaded := result["loaded"]
		var spare := result["spare"]
		var total := result["total"]

		var expected_loaded: int = test["expected_loaded"]
		var expected_spare: int = test["expected_spare"]
		var expected_total: int = test["expected_total"]

		var test_passed := (loaded == expected_loaded and spare == expected_spare and total == expected_total)

		if test_passed:
			passed += 1
			print("✓ PASS: %d enemies -> loaded: %d, spare: %d, total: %d" % [enemy_count, loaded, spare, total])
		else:
			failed += 1
			print("✗ FAIL: %d enemies -> got loaded: %d, spare: %d, total: %d | expected loaded: %d, spare: %d, total: %d" % [
				enemy_count, loaded, spare, total, expected_loaded, expected_spare, expected_total
			])

	print("\n=== Test Results ===")
	print("Passed: %d/%d" % [passed, passed + failed])
	print("Failed: %d/%d" % [failed, passed + failed])

	if failed == 0:
		print("\n✓ All tests passed! The ammo calculation logic is correct.")
	else:
		print("\n✗ Some tests failed. Please review the calculation logic.")

	# Exit after tests
	get_tree().quit()


## Simulates the ammo distribution logic from SilencedPistol.ConfigureAmmoForEnemyCount
func calculate_ammo_distribution(enemy_count: int, magazine_capacity: int) -> Dictionary:
	var full_magazines := enemy_count / magazine_capacity
	var remaining_bullets := enemy_count % magazine_capacity

	var loaded := 0
	var spare := 0

	if remaining_bullets > 0:
		# Current magazine has the remaining bullets
		loaded = remaining_bullets
		# Add full magazines as spares
		spare = full_magazines * magazine_capacity
	elif full_magazines > 0:
		# No remaining bullets, so current magazine is a full one
		loaded = magazine_capacity
		# Add remaining full magazines as spares
		spare = (full_magazines - 1) * magazine_capacity
	else:
		# No enemies or edge case
		loaded = 0
		spare = 0

	return {
		"loaded": loaded,
		"spare": spare,
		"total": loaded + spare
	}
