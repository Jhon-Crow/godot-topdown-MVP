extends Node
## Experiment script to verify the grenade transfer efficiency fix for issue #281
##
## This script simulates various throw scenarios and compares the old behavior
## (with strict timing) to the new behavior (with minimum transfer efficiency).
##
## Run in Godot editor to see output in the Output panel.

func _ready() -> void:
	print("=" .repeat(70))
	print("Issue #281 Fix Verification: Grenade Throw Transfer Efficiency")
	print("=" .repeat(70))
	print("")

	# Old parameters (before fix)
	var old_min_swing := 200.0
	var old_min_transfer := 0.0  # No minimum transfer in old system

	# New parameters (after fix)
	var new_min_swing := 80.0
	var new_min_transfer := 0.35  # 35% minimum transfer

	# Test scenarios from actual game logs
	var test_cases := [
		# {"name": description, "velocity": magnitude in px/s, "swing": distance in px}
		{"name": "Quick flick (problematic)", "velocity": 874.2, "swing": 83.7},
		{"name": "Very short swing", "velocity": 473.8, "swing": 141.1},
		{"name": "Almost no swing", "velocity": 48.6, "swing": 4.0},
		{"name": "Short fast flick", "velocity": 1349.1, "swing": 114.5},
		{"name": "Medium swing", "velocity": 1927.0, "swing": 1327.0},
		{"name": "Good throw", "velocity": 3336.2, "swing": 686.1},
		{"name": "High velocity short swing", "velocity": 2467.0, "swing": 414.4},
	]

	print("Comparison of OLD vs NEW transfer efficiency:")
	print("-" .repeat(70))
	print("%-30s | %10s | %10s | %12s" % ["Scenario", "Old Trans", "New Trans", "Improvement"])
	print("-" .repeat(70))

	for test in test_cases:
		var name: String = test["name"]
		var velocity: float = test["velocity"]
		var swing: float = test["swing"]

		# Old calculation
		var old_transfer := clampf(swing / old_min_swing, 0.0, 1.0)

		# New calculation
		var new_swing_transfer := clampf(swing / new_min_swing, 0.0, 1.0 - new_min_transfer)
		var new_transfer := clampf(new_min_transfer + new_swing_transfer, 0.0, 1.0)

		# Improvement factor
		var improvement := 0.0
		if old_transfer > 0.001:
			improvement = new_transfer / old_transfer
		else:
			improvement = INF

		var improvement_str := "%.2fx" % improvement if improvement < 100 else "huge!"

		print("%-30s | %10.2f | %10.2f | %12s" % [name, old_transfer, new_transfer, improvement_str])

	print("-" .repeat(70))
	print("")
	print("Analysis:")
	print("- OLD system: Requires 200px swing for full transfer, no minimum")
	print("- NEW system: Requires 80px swing for full transfer, 35% minimum")
	print("")
	print("Key improvements:")
	print("1. Quick flicks now get at least 35% transfer (was as low as 2%)")
	print("2. Short swings now reach full transfer at 80px instead of 200px")
	print("3. The problem scenario (83.7px swing) goes from 0.42 to 1.00 transfer!")
	print("")
	print("This fixes the issue where grenades were falling at player's feet")
	print("during short fast mouse movements.")
	print("=" .repeat(70))
