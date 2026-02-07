extends Node
## Experiment script to test ASVK reload bolt fix (Issue #566)
## Tests that after reloading a new magazine, the bolt is automatically chambered (Ready state)

func _ready():
	print("=== ASVK Reload Bolt Fix Test (Issue #566) ===")
	run_test()

func run_test():
	# Create test sniper rifle
	var sniper_rifle_scene = load("res://scenes/weapons/SniperRifle.tscn")
	if not sniper_rifle_scene:
		print("❌ FAILED: Could not load SniperRifle scene")
		return

	var sniper: Node2D = sniper_rifle_scene.instantiate()
	add_child(sniper)

	print("\n--- Test 1: Initial state ---")
	print("Bolt should be Ready initially")
	print("Current bolt step: ", sniper.CurrentBoltStep)
	print("Is bolt ready: ", sniper.IsBoltReady)
	assert(sniper.IsBoltReady, "Initial bolt should be Ready")
	print("✓ Test 1 passed")

	print("\n--- Test 2: After firing (simulated) ---")
	# Simulate firing by setting bolt to NeedsBoltCycle
	# We can't directly set _boltStep, so we'll fire if possible
	if sniper.CurrentAmmo > 0:
		var fired = sniper.Fire(Vector2.RIGHT)
		if fired:
			print("Fired shot, bolt should need cycling")
			print("Current bolt step: ", sniper.CurrentBoltStep)
			print("Needs bolt cycle: ", sniper.NeedsBoltCycle)
			assert(sniper.NeedsBoltCycle, "Bolt should need cycling after firing")
			print("✓ Test 2 passed")
		else:
			print("⚠ Warning: Could not fire (this is OK for the test)")
	else:
		print("⚠ Warning: No ammo to fire (simulating bolt needs cycle state)")

	print("\n--- Test 3: Reload and check bolt state ---")
	print("Before reload - Bolt step: ", sniper.CurrentBoltStep)
	print("Before reload - Is bolt ready: ", sniper.IsBoltReady)
	print("Current ammo: ", sniper.CurrentAmmo)
	print("Reserve ammo: ", sniper.ReserveAmmo)

	if sniper.ReserveAmmo > 0:
		# Perform instant reload (R-F-R sequence)
		sniper.InstantReload()

		print("\nAfter reload - Current ammo: ", sniper.CurrentAmmo)
		print("After reload - Bolt step: ", sniper.CurrentBoltStep)
		print("After reload - Is bolt ready: ", sniper.IsBoltReady)

		# The fix should make the bolt Ready after reload
		if sniper.IsBoltReady:
			print("✓ Test 3 passed: Bolt is Ready after reload (Issue #566 FIXED)")
		else:
			print("❌ Test 3 FAILED: Bolt is NOT ready after reload (Issue #566 NOT FIXED)")
			print("   Expected: Bolt should be Ready")
			print("   Actual: Bolt needs cycling")
	else:
		print("⚠ Warning: No reserve ammo to test reload")

	print("\n--- Test 4: Verify weapon can fire after reload ---")
	if sniper.IsBoltReady and sniper.CurrentAmmo > 0:
		var can_fire_after_reload = sniper.Fire(Vector2.RIGHT)
		if can_fire_after_reload:
			print("✓ Test 4 passed: Weapon can fire immediately after reload")
		else:
			print("❌ Test 4 FAILED: Weapon cannot fire after reload")
	else:
		print("⚠ Skipping Test 4: Bolt not ready or no ammo")

	print("\n=== Test Complete ===")

	# Cleanup
	sniper.queue_free()
