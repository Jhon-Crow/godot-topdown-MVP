#!/usr/bin/env godot --script

# Test script to reproduce the empty drum issue reported by owner
# This simulates the scenario where CurrentAmmo = 0 and tries to fire

extends SceneTree

func _ready():
	print("=== Testing Issue #716: Empty Drum Firing ===")
	
	# Load revolver script
	var revolver_script = load("res://Scripts/Weapons/Revolver.cs")
	if revolver_script == null:
		print("❌ Could not load Revolver.cs")
		quit()
		return
	
	# Create revolver instance
	var revolver = revolver_script.new()
	if revolver == null:
		print("❌ Could not create revolver instance")
		quit()
		return
	
	# Mock basic setup
	revolver.WeaponData = load("res://resources/weapons/RevolverData.tres")
	revolver.BulletScene = load("res://scenes/projectiles/csharp/Bullet.tscn")
	
	print("✅ Revolver created and basic setup complete")
	
	# Simulate empty drum scenario
	revolver.CurrentAmmo = 0
	print("🔫 Set CurrentAmmo to 0 (empty drum)")
	
	# Check if chamber array is properly initialized
	print("📊 Checking chamber state...")
	var chamber_occupied = revolver.get("_chamberOccupied")
	if chamber_occupied == null:
		print("❌ _chamberOccupied is null")
		quit()
		return
	
	print("📊 Chamber array length: ", chamber_occupied.size())
	for i in range(chamber_occupied.size()):
		print("  Chamber ", i, ": ", "occupied" if chamber_occupied[i] else "empty")
	
	# Test 1: Manual cock hammer (should work according to Issue #716)
	print("\n🔨 Test 1: Manual cock hammer with empty drum...")
	var can_manual_cock = revolver.ManualCockHammer()
	print("Result: ", "SUCCESS" if can_manual_cock else "FAILED")
	
	# Test 2: Try to fire from completely empty drum
	print("\n🔫 Test 2: Fire from completely empty drum...")
	var fire_result = revolver.Fire(Vector2.RIGHT)
	print("Fire result: ", fire_result)
	
	# Test 3: Try to fire after manual cock
	if can_manual_cock:
		print("\n🔫 Test 3: Fire after manual cock...")
		var fire_after_cock = revolver.Fire(Vector2.RIGHT)
		print("Fire after cock result: ", fire_after_cock)
	
	print("\n=== Test Complete ===")
	quit()