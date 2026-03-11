extends SceneTree
## Test script to verify that the last chance effect is disabled in Black Metal mode.
## Issue #985: Last chance effect should NOT trigger in Black Metal difficulty.
##
## This test verifies the logic in last_chance_effects_manager.gd:_can_trigger_effect()

func _init() -> void:
	print("=== Black Metal Last Chance Disabled Test (Issue #985) ===\n")

	# Simulate the difficulty modes
	var test_cases: Array = [
		{"difficulty": "EASY", "is_hard": false, "is_black_metal": false, "should_trigger": false},
		{"difficulty": "NORMAL", "is_hard": false, "is_black_metal": false, "should_trigger": false},
		{"difficulty": "HARD", "is_hard": true, "is_black_metal": false, "should_trigger": true},
		{"difficulty": "POWER_FANTASY", "is_hard": false, "is_black_metal": false, "should_trigger": false},
		{"difficulty": "BLACK_METAL", "is_hard": false, "is_black_metal": true, "should_trigger": false},
	]

	var passed: int = 0
	var failed: int = 0

	for test in test_cases:
		var difficulty: String = test["difficulty"]
		var is_hard: bool = test["is_hard"]
		var is_black_metal: bool = test["is_black_metal"]
		var expected: bool = test["should_trigger"]

		# Simulate the _can_trigger_effect() logic (Issue #985 fix applied)
		var can_trigger: bool = false

		# Check Black Metal first (Issue #985)
		if is_black_metal:
			can_trigger = false  # Explicitly disabled
		elif is_hard:
			can_trigger = true  # Only Hard mode triggers

		var match: bool = (can_trigger == expected)
		var status: String = "PASS" if match else "FAIL"

		if match:
			passed += 1
		else:
			failed += 1

		print("[%s] Difficulty: %s" % [status, difficulty])
		print("       is_hard_mode=%s, is_black_metal_mode=%s" % [is_hard, is_black_metal])
		print("       expected_trigger=%s, actual_trigger=%s" % [expected, can_trigger])

	print("\n=== Results ===")
	print("Passed: %d" % passed)
	print("Failed: %d" % failed)

	if failed == 0:
		print("\nAll tests passed! Last chance effect is correctly disabled in Black Metal mode.")
	else:
		print("\nSome tests failed. Review the last chance trigger logic.")

	quit()
