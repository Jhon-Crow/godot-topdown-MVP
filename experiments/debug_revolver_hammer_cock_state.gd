extends Node

# Debug script to trace revolver hammer cock state during firing sequence
# This script simulates the revolver behavior and logs state changes

class_name RevolverHammerCockDebug

var revolver_script = load("res://Scripts/Weapons/Revolver.cs")

func _ready():
	print("=== Revolver Hammer Cock State Debug ===")
	run_debug_tests()

func run_debug_tests():
	# Test 1: Manual cock hammer scenario
	print("\n--- Test 1: Manual Cock Hammer ---")
	test_manual_cock_sequence()
	
	# Test 2: Normal fire scenario  
	print("\n--- Test 2: Normal Fire Sequence ---")
	test_normal_fire_sequence()
	
	# Test 3: Empty chamber scenarios
	print("\n--- Test 3: Empty Chamber Scenarios ---")
	test_empty_chamber_scenarios()

func test_manual_cock_sequence():
	print("1.1: Creating revolver instance...")
	var revolver = revolver_script.new()
	if revolver == null:
		print("❌ Failed to create revolver")
		return
	
	revolver.WeaponData = load("res://resources/weapons/RevolverData.tres")
	revolver.BulletScene = load("res://scenes/projectiles/csharp/Bullet.tscn")
	revolver.CurrentAmmo = 3
	
	print("1.2: Initial state - IsHammerCocked: ", revolver.IsHammerCocked)
	print("1.3: IsManuallyHammerCocked: ", revolver.IsManuallyHammerCocked)
	
	print("\n1.4: Manually cocking hammer...")
	var cock_result = revolver.ManualCockHammer()
	print("     Cock result: ", cock_result)
	print("     IsHammerCocked: ", revolver.IsHammerCocked)
	print("     IsManuallyHammerCocked: ", revolver.IsManuallyHammerCocked)
	
	print("\n1.5: Firing with cocked hammer...")
	var fire_result = revolver.Fire(Vector2.RIGHT)
	print("     Fire result: ", fire_result)
	print("     IsHammerCocked: ", revolver.IsHammerCocked)
	print("     IsManuallyHammerCocked: ", revolver.IsManuallyHammerCocked)
	
	print("1.6: Waiting a bit for delayed effects...")
	await get_tree().create_timer(0.2).timeout
	print("     After delay - IsHammerCocked: ", revolver.IsHammerCocked)
	print("     After delay - IsManuallyHammerCocked: ", revolver.IsManuallyHammerCocked)

func test_normal_fire_sequence():
	print("2.1: Creating revolver instance...")
	var revolver = revolver_script.new()
	if revolver == null:
		print("❌ Failed to create revolver")
		return
	
	revolver.WeaponData = load("res://resources/weapons/RevolverData.tres")
	revolver.BulletScene = load("res://scenes/projectiles/csharp/Bullet.tscn")
	revolver.CurrentAmmo = 2
	
	print("2.2: Initial state - IsHammerCocked: ", revolver.IsHammerCocked)
	print("2.3: IsManuallyHammerCocked: ", revolver.IsManuallyHammerCocked)
	
	print("\n2.4: Normal fire (LMB without manual cock)...")
	var fire_result = revolver.Fire(Vector2.RIGHT)
	print("     Fire result: ", fire_result)
	print("     IsHammerCocked: ", revolver.IsHammerCocked)
	print("     IsManuallyHammerCocked: ", revolver.IsManuallyHammerCocked)
	
	print("2.5: Waiting for hammer cock delay (0.15s)...")
	await get_tree().create_timer(0.2).timeout
	print("     After delay - IsHammerCocked: ", revolver.IsHammerCocked)
	print("     After delay - IsManuallyHammerCocked: ", revolver.IsManuallyHammerCocked)

func test_empty_chamber_scenarios():
	print("3.1: Creating revolver with empty cylinder...")
	var revolver = revolver_script.new()
	if revolver == null:
		print("❌ Failed to create revolver")
		return
	
	revolver.WeaponData = load("res://resources/weapons/RevolverData.tres")
	revolver.BulletScene = load("res://scenes/projectiles/csharp/Bullet.tscn")
	revolver.CurrentAmmo = 0  # Empty cylinder
	
	print("3.2: Initial state - IsHammerCocked: ", revolver.IsHammerCocked)
	
	print("\n3.3: Manual cock on empty cylinder...")
	var cock_result = revolver.ManualCockHammer()
	print("     Cock result: ", cock_result)
	print("     IsHammerCocked: ", revolver.IsHammerCocked)
	print("     IsManuallyHammerCocked: ", revolver.IsManuallyHammerCocked)
	
	print("\n3.4: Fire with cocked hammer on empty chamber...")
	var fire_result = revolver.Fire(Vector2.RIGHT)
	print("     Fire result: ", fire_result)
	print("     IsHammerCocked: ", revolver.IsHammerCocked)
	print("     IsManuallyHammerCocked: ", revolver.IsManuallyHammerCocked)
	
	await get_tree().create_timer(0.2).timeout
	print("     After delay - IsHammerCocked: ", revolver.IsHammerCocked)
	print("     After delay - IsManuallyHammerCocked: ", revolver.IsManuallyHammerCocked)