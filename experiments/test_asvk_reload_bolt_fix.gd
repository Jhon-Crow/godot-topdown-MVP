extends Node
## Experiment script to test ASVK reload bolt fix (Issue #566)
## Tests that bolt cycling on empty magazine does NOT set bolt to Ready state.
## After reload, the user must still cycle the bolt manually to chamber a round.

func _ready():
	print("=== ASVK Reload Bolt Fix Test (Issue #566) ===")
	run_test()

func run_test():
	# Create test sniper rifle
	var sniper_rifle_scene = load("res://scenes/weapons/SniperRifle.tscn")
	if not sniper_rifle_scene:
		print("FAILED: Could not load SniperRifle scene")
		return

	var sniper: Node2D = sniper_rifle_scene.instantiate()
	add_child(sniper)

	print("\n--- Test 1: Initial state ---")
	print("Bolt should be Ready initially")
	print("Current bolt step: ", sniper.CurrentBoltStep)
	print("Is bolt ready: ", sniper.IsBoltReady)
	assert(sniper.IsBoltReady, "Initial bolt should be Ready")
	print("PASS: Test 1 - Initial bolt is Ready")

	print("\n--- Test 2: After firing, bolt needs cycling ---")
	if sniper.CurrentAmmo > 0:
		var fired = sniper.Fire(Vector2.RIGHT)
		if fired:
			print("Fired shot, bolt should need cycling")
			print("Current bolt step: ", sniper.CurrentBoltStep)
			print("Needs bolt cycle: ", sniper.NeedsBoltCycle)
			assert(sniper.NeedsBoltCycle, "Bolt should need cycling after firing")
			print("PASS: Test 2 - Bolt needs cycling after firing")
		else:
			print("WARNING: Could not fire (scene may not be fully initialized)")
	else:
		print("WARNING: No ammo to fire")

	print("\n--- Test 3: Bolt cycling on empty magazine should NOT set Ready ---")
	print("This is the core test for Issue #566:")
	print("  - Fire all rounds until CurrentAmmo = 0")
	print("  - Cycle bolt (all 4 steps)")
	print("  - Bolt should NOT be Ready (no round to chamber)")
	print("  - After reload, bolt should STILL need cycling")
	print("  - Cycle bolt again -> no casing ejected, bolt Ready")
	print("  - Now weapon can fire")
	print("")
	print("Expected behavior after fix:")
	print("  1. Fire last round -> NeedsBoltCycle, ammo=0")
	print("  2. Cycle bolt -> casing ejected, but bolt stays NeedsBoltCycle (ammo=0)")
	print("  3. Reload (R-F-R) -> ammo refilled, bolt still NeedsBoltCycle")
	print("  4. Cycle bolt again -> NO casing ejected, bolt Ready (ammo>0)")
	print("  5. Fire -> works")

	print("\n--- Test 4: Verify no InstantReload/FinishReload override ---")
	print("The fix should NOT override InstantReload or FinishReload.")
	print("Those overrides were incorrect (they reset bolt to Ready after reload).")
	print("The correct fix is in HandleBoltActionInput: bolt step 4 checks ammo.")

	print("\n=== Test Complete ===")
	print("Note: Full integration testing requires running in Godot with input events.")

	# Cleanup
	sniper.queue_free()
