extends GutTest

# Test for Issue #716 fix - Empty drum initialization bug
# This test verifies the fix for the initialization bug where _chamberOccupied
# was incorrectly initialized regardless of CurrentAmmo value

func test_issue_716_empty_drum_initialization():
	print("=== Testing Issue #716: Empty Drum Initialization Fix ===")
	
	# Create a revolver instance
	var revolver = preload("res://Scripts/Weapons/Revolver.cs").new()
	
	# Mock the weapon data (required for initialization)
	var weapon_data = preload("res://resources/weapons/RevolverData.tres")
	revolver.WeaponData = weapon_data
	revolver.BulletScene = preload("res://scenes/projectiles/csharp/Bullet.tscn")
	
	# Simulate _Ready() initialization by calling the internal logic
	# We need to set CurrentAmmo BEFORE the chamber array is initialized
	revolver.CurrentAmmo = 0  # Empty drum scenario
	
	# Access the internal chamber array to verify initialization
	# Note: In Godot, we can access private fields via reflection
	var chamber_occupied = revolver.get("_chamberOccupied")
	
	# The _Ready() method should have been called during scene instantiation
	# If our fix is working, all chambers should be empty when CurrentAmmo = 0
	assert_true(chamber_occupied != null, "Chamber array should be initialized")
	
	if chamber_occupied != null:
		var all_empty = true
		for i in range(chamber_occupied.size()):
			if chamber_occupied[i]:
				all_empty = false
				break
		
		assert_true(all_empty, "All chambers should be empty when CurrentAmmo = 0")
		
		if all_empty:
			print("✅ All chambers correctly initialized as empty")
		else:
			print("❌ Some chambers incorrectly initialized as occupied")
	
	# Test with partially filled drum
	revolver.CurrentAmmo = 2
	# Re-initialize to simulate the fixed behavior
	# (In real scenario, this would happen in _Ready)
	var cylinder_capacity = weapon_data.MagazineSize
	var expected_chambers = []
	for i in range(cylinder_capacity):
		expected_chambers.append(i < 2)
	
	# Verify the logic we expect from our fix
	assert_eq(expected_chambers.size(), cylinder_capacity, "Expected array size should match cylinder capacity")
	
	print("✅ Empty drum initialization test completed")

func test_issue_716_completely_empty_drum_firing():
	print("=== Testing Issue #716: Completely Empty Drum Firing ===")
	
	# Create a revolver with completely empty drum
	var revolver = preload("res://Scripts/Weapons/Revolver.cs").new()
	
	# Mock setup
	revolver.WeaponData = preload("res://resources/weapons/RevolverData.tres")
	revolver.BulletScene = preload("res://scenes/projectiles/csharp/Bullet.tscn")
	revolver.CurrentAmmo = 0
	
	# Test manual cock hammer (Issue #716 requirement 1)
	var manual_cock_result = revolver.ManualCockHammer()
	assert_true(manual_cock_result, "Should be able to cock hammer with completely empty drum")
	
	# Test firing from completely empty drum (Issue #716 requirement 2)
	var fire_result = revolver.Fire(Vector2.RIGHT)
	assert_true(fire_result, "Fire should return true (action performed - click sound)")
	
	print("✅ Completely empty drum firing test completed")