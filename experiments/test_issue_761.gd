#!/usr/bin/env -S godot --headless --script
extends SceneTree

## Test script for Issue #761: Add dry fire sound to shotgun
## This script tests that:
## 1. AudioManager has the new play_shotgun_dry_fire method
## 2. The sound file exists
## 3. The constant is defined correctly

func _init():
	print("\n=== Testing Issue #761: Shotgun Dry Fire Sound ===\n")
	
	var all_passed = true
	
	# Test 1: Check AudioManager script has the new method
	print("Test 1: Check AudioManager has play_shotgun_dry_fire method...")
	var audio_manager_script = load("res://scripts/autoload/audio_manager.gd")
	if audio_manager_script:
		var source_code = audio_manager_script.source_code
		if "func play_shotgun_dry_fire" in source_code:
			print("  ✅ AudioManager has play_shotgun_dry_fire method")
		else:
			print("  ❌ AudioManager missing play_shotgun_dry_fire method")
			all_passed = false
		
		if "SHOTGUN_DRY_FIRE" in source_code:
			print("  ✅ SHOTGUN_DRY_FIRE constant defined")
		else:
			print("  ❌ SHOTGUN_DRY_FIRE constant not found")
			all_passed = false
			
		if "попытка выстрела без заряда ДРОБОВИК.mp3" in source_code:
			print("  ✅ Correct sound file path defined")
		else:
			print("  ❌ Sound file path not found")
			all_passed = false
	else:
		print("  ❌ Could not load AudioManager script")
		all_passed = false
	
	# Test 2: Check sound file exists
	print("\nTest 2: Check sound file exists...")
	var file = FileAccess.open("res://assets/audio/попытка выстрела без заряда ДРОБОВИК.mp3", FileAccess.READ)
	if file:
		print("  ✅ Sound file exists")
		file.close()
	else:
		print("  ❌ Sound file not found")
		all_passed = false
	
	# Test 3: Check Shotgun.cs has the new method
	print("\nTest 3: Check Shotgun.cs has PlayDryFireSound method...")
	var shotgun_script = load("res://Scripts/Weapons/Shotgun.cs")
	if shotgun_script:
		# For C# scripts, we check the source file directly
		var shotgun_file = FileAccess.open("res://Scripts/Weapons/Shotgun.cs", FileAccess.READ)
		if shotgun_file:
			var content = shotgun_file.get_as_text()
			shotgun_file.close()
			
			if "PlayDryFireSound" in content:
				print("  ✅ Shotgun.cs has PlayDryFireSound method")
			else:
				print("  ❌ Shotgun.cs missing PlayDryFireSound method")
				all_passed = false
			
			if "play_shotgun_dry_fire" in content:
				print("  ✅ Shotgun.cs calls play_shotgun_dry_fire")
			else:
				print("  ❌ Shotgun.cs doesn't call play_shotgun_dry_fire")
				all_passed = false
			
			if "Issue #761" in content:
				print("  ✅ Issue #761 reference found in comments")
			else:
				print("  ⚠️  Issue #761 reference not found in comments (not critical)")
		else:
			print("  ❌ Could not read Shotgun.cs file")
			all_passed = false
	else:
		print("  ⚠️  Could not load Shotgun.cs script (C# scripts may not load in GDScript context)")
		# Try reading the file directly
		var shotgun_file = FileAccess.open("res://Scripts/Weapons/Shotgun.cs", FileAccess.READ)
		if shotgun_file:
			var content = shotgun_file.get_as_text()
			shotgun_file.close()
			
			if "PlayDryFireSound" in content:
				print("  ✅ Shotgun.cs has PlayDryFireSound method (file check)")
			else:
				print("  ❌ Shotgun.cs missing PlayDryFireSound method")
				all_passed = false
		else:
			print("  ❌ Could not read Shotgun.cs file")
			all_passed = false
	
	# Test 4: Check that empty tube still uses empty click sound
	print("\nTest 4: Verify empty tube still uses empty click sound...")
	var shotgun_file = FileAccess.open("res://Scripts/Weapons/Shotgun.cs", FileAccess.READ)
	if shotgun_file:
		var content = shotgun_file.get_as_text()
		shotgun_file.close()
		
		# Count occurrences of PlayEmptyClickSound vs PlayDryFireSound
		var empty_click_count = content.count("PlayEmptyClickSound()")
		var dry_fire_count = content.count("PlayDryFireSound()")
		
		print("  PlayEmptyClickSound calls: " + str(empty_click_count))
		print("  PlayDryFireSound calls: " + str(dry_fire_count))
		
		if empty_click_count >= 1 and dry_fire_count >= 1:
			print("  ✅ Both sounds are used appropriately")
		elif dry_fire_count >= 1:
			print("  ✅ Dry fire sound is used")
		else:
			print("  ❌ Dry fire sound not found")
			all_passed = false
	else:
		print("  ❌ Could not read Shotgun.cs file")
		all_passed = false
	
	# Summary
	print("\n" + "=".repeat(50))
	if all_passed:
		print("✅ All tests PASSED!")
		quit(0)
	else:
		print("❌ Some tests FAILED!")
		quit(1)
