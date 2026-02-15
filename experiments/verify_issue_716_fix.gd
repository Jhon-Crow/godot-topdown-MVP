#!/usr/bin/env godot --script

# Simple verification script to test Issue #716 fix
# This demonstrates that the CanFire override allows empty drum firing

extends SceneTree

func _ready():
	print("=== Issue #716 Fix Verification ===")
	
	# Test 1: CanFire with empty drum
	print("\n🔫 Test 1: CanFire with CurrentAmmo = 0")
	var revolver = preload("res://Scripts/Weapons/Revolver.cs").new()
	revolver.CurrentAmmo = 0
	revolver.WeaponData = preload("res://resources/weapons/RevolverData.tres")
	
	# Before fix: CanFire would return false due to CurrentAmmo > 0 check
	# After fix: CanFire should return true for empty drum
	var can_fire_empty = revolver.CanFire
	print("CanFire with empty drum: ", "✅ TRUE (Fixed)" if can_fire_empty else "❌ FALSE (Broken)")
	
	# Test 2: CanFire with ammo
	print("\n🔫 Test 2: CanFire with CurrentAmmo > 0")
	revolver.CurrentAmmo = 3
	var can_fire_with_ammo = revolver.CanFire
	print("CanFire with ammo: ", "✅ TRUE" if can_fire_with_ammo else "❌ FALSE")
	
	# Test 3: CanFire during reload
	print("\n🔄 Test 3: CanFire during reload (should be false)")
	revolver.IsReloading = true
	var can_fire_reloading = revolver.CanFire
	print("CanFire while reloading: ", "✅ FALSE (Correct)" if not can_fire_reloading else "❌ TRUE (Wrong)")
	
	print("\n=== Verification Complete ===")
	if can_fire_empty and can_fire_with_ammo and not can_fire_reloading:
		print("🎉 Issue #716 fix VERIFIED - CanFire override works correctly!")
	else:
		print("❌ Issue #716 fix FAILED - something is wrong")
	
	quit()