extends GutTest
## Unit tests for Revolver initialization fix (Issue #950).
##
## Verifies that the Revolver initializes with the correct cylinder capacity (5)
## rather than falling back to the C# WeaponData default (30).
##
## Root cause: In Godot 4.3 release builds, C# [GlobalClass] resource properties
## from .tres files may not deserialize correctly, causing WeaponData.MagazineSize
## to return the C# default (30) instead of the .tres value (5).
##
## Fix: Added a dedicated [Export] CylinderSize property to Revolver.cs that is
## set directly in Revolver.tscn (bypassing WeaponData deserialization).


# Mock implementation of the Revolver initialization logic that mirrors
# how CylinderSize is now used instead of WeaponData.MagazineSize.
class MockRevolverInit:
	## The cylinder size exported as a Godot [Export] property.
	## Set directly in the .tscn file to 5 — does not depend on WeaponData.
	var cylinder_size: int = 5

	## Number of starting cylinders (magazines in the revolver sense).
	var starting_magazine_count: int = 4

	## Simulated ammo multiplier from DifficultyManager (1 = Hard, 3 = Power Fantasy).
	var ammo_multiplier: int = 1

	## Whether WeaponData deserialized correctly (simulates the broken state).
	var weapon_data_magazine_size: int = 30  # Wrong value from C# default

	## Current ammo (in the loaded cylinder).
	var current_ammo: int = 0

	## Reserve ammo (in spare cylinders).
	var reserve_ammo: int = 0

	## Whether initialization used CylinderSize (correct) or WeaponData.MagazineSize (buggy).
	var initialized_with_cylinder_size: bool = false


	## Buggy initialization: uses WeaponData.MagazineSize (pre-fix behavior).
	func initialize_buggy() -> void:
		var magazine_count := starting_magazine_count * ammo_multiplier
		var size := weapon_data_magazine_size  # Bug: may return 30 instead of 5
		current_ammo = size
		reserve_ammo = (magazine_count - 1) * size
		initialized_with_cylinder_size = false


	## Fixed initialization: uses CylinderSize export property (Issue #950 fix).
	func initialize_fixed() -> void:
		var magazine_count := starting_magazine_count * ammo_multiplier
		var size := cylinder_size  # Fix: always uses the exported [Export] property
		current_ammo = size
		reserve_ammo = (magazine_count - 1) * size
		initialized_with_cylinder_size = true


	## Gets the cylinder capacity — should always return cylinder_size in fixed version.
	func get_cylinder_capacity() -> int:
		return cylinder_size


	## Total ammo count.
	func get_total_ammo() -> int:
		return current_ammo + reserve_ammo


var revolver: MockRevolverInit


func before_each() -> void:
	revolver = MockRevolverInit.new()


func after_each() -> void:
	revolver = null


# ============================================================================
# Bug Reproduction Tests — confirm the pre-fix behavior was wrong
# ============================================================================


func test_buggy_initialization_uses_weapon_data_size_30() -> void:
	## Before the fix, WeaponData.MagazineSize defaulting to 30 caused wrong init.
	revolver.weapon_data_magazine_size = 30
	revolver.initialize_buggy()

	assert_eq(revolver.current_ammo, 30,
		"BUGGY: Revolver should wrongly get 30 rounds (C# WeaponData default)")
	assert_false(revolver.initialized_with_cylinder_size,
		"BUGGY: Should not use cylinder_size")


func test_buggy_initialization_total_ammo_is_120() -> void:
	## Pre-fix: 4 starting cylinders × 30 rounds = 120 total (should be 20).
	revolver.weapon_data_magazine_size = 30
	revolver.initialize_buggy()

	assert_eq(revolver.get_total_ammo(), 4 * 30,
		"BUGGY: Total ammo should be 120 (4 × 30), not the correct 20")


# ============================================================================
# Fix Verification Tests — confirm the fixed behavior is correct
# ============================================================================


func test_fixed_initialization_uses_cylinder_size_5() -> void:
	## After the fix, CylinderSize=[Export]=5 is always used.
	revolver.cylinder_size = 5
	revolver.initialize_fixed()

	assert_eq(revolver.current_ammo, 5,
		"FIXED: Revolver should have 5 rounds in the cylinder")
	assert_true(revolver.initialized_with_cylinder_size,
		"FIXED: Should use cylinder_size, not WeaponData.MagazineSize")


func test_fixed_initialization_reserve_ammo_correct() -> void:
	## 4 starting cylinders - 1 loaded = 3 spare cylinders × 5 = 15 reserve.
	revolver.cylinder_size = 5
	revolver.starting_magazine_count = 4
	revolver.initialize_fixed()

	assert_eq(revolver.reserve_ammo, 15,
		"FIXED: Reserve should be 15 (3 spare cylinders × 5 rounds)")


func test_fixed_initialization_total_ammo_is_20() -> void:
	## 5 current + 15 reserve = 20 total (matches game log expectation).
	revolver.cylinder_size = 5
	revolver.starting_magazine_count = 4
	revolver.initialize_fixed()

	assert_eq(revolver.get_total_ammo(), 20,
		"FIXED: Total ammo should be 20 (4 × 5)")


func test_fixed_ignores_weapon_data_magazine_size() -> void:
	## Even if WeaponData returns 30, the fix uses cylinder_size (5).
	revolver.cylinder_size = 5
	revolver.weapon_data_magazine_size = 30  # Simulate broken deserialization
	revolver.initialize_fixed()

	assert_eq(revolver.current_ammo, 5,
		"FIXED: Should use cylinder_size=5, not WeaponData.MagazineSize=30")
	assert_neq(revolver.current_ammo, 30,
		"FIXED: Should NOT have 30 rounds from WeaponData default")


# ============================================================================
# CylinderCapacity Property Tests
# ============================================================================


func test_cylinder_capacity_equals_cylinder_size() -> void:
	## CylinderCapacity should always return CylinderSize.
	revolver.cylinder_size = 5

	assert_eq(revolver.get_cylinder_capacity(), 5,
		"CylinderCapacity should equal CylinderSize")


func test_cylinder_capacity_not_weapon_data_size() -> void:
	## CylinderCapacity must not fallback to WeaponData.MagazineSize.
	revolver.cylinder_size = 5
	revolver.weapon_data_magazine_size = 30

	assert_eq(revolver.get_cylinder_capacity(), 5,
		"CylinderCapacity should be 5, not 30 from WeaponData")
	assert_neq(revolver.get_cylinder_capacity(), 30,
		"CylinderCapacity must not return WeaponData default 30")


# ============================================================================
# Power Fantasy Mode Tests (ammo multiplier)
# ============================================================================


func test_fixed_power_fantasy_multiplies_magazines_not_cylinder_size() -> void:
	## In Power Fantasy mode (ammo_multiplier=3), the magazine count is multiplied
	## but cylinder_size stays at 5 per cylinder.
	revolver.cylinder_size = 5
	revolver.starting_magazine_count = 4
	revolver.ammo_multiplier = 3  # Power Fantasy mode
	revolver.initialize_fixed()

	assert_eq(revolver.current_ammo, 5,
		"FIXED Power Fantasy: Each cylinder still holds 5 rounds")
	assert_eq(revolver.reserve_ammo, (4 * 3 - 1) * 5,
		"FIXED Power Fantasy: Reserve should be 11 spare cylinders × 5 rounds")
	assert_eq(revolver.get_total_ammo(), 4 * 3 * 5,
		"FIXED Power Fantasy: Total should be 12 cylinders × 5 rounds = 60")


func test_buggy_power_fantasy_is_even_more_wrong() -> void:
	## Pre-fix in Power Fantasy mode: 12 × 30 = 360 total (should be 60).
	revolver.weapon_data_magazine_size = 30
	revolver.starting_magazine_count = 4
	revolver.ammo_multiplier = 3
	revolver.initialize_buggy()

	assert_eq(revolver.get_total_ammo(), 4 * 3 * 30,
		"BUGGY Power Fantasy: Should wrongly produce 360 total ammo")


# ============================================================================
# Edge Case Tests
# ============================================================================


func test_single_cylinder_revolver_reserve_is_zero() -> void:
	revolver.cylinder_size = 5
	revolver.starting_magazine_count = 1
	revolver.initialize_fixed()

	assert_eq(revolver.current_ammo, 5,
		"Single cylinder: should have 5 rounds loaded")
	assert_eq(revolver.reserve_ammo, 0,
		"Single cylinder: no reserve")


func test_rsh12_revolver_5_cylinder_4_magazines() -> void:
	## The actual RSh-12 revolver data: MagazineSize=5, StartingMagazineCount=4.
	## Expected from game log: ammo should be 5/15 not 30/30.
	revolver.cylinder_size = 5       # CylinderSize [Export] in scene file
	revolver.starting_magazine_count = 4
	revolver.ammo_multiplier = 1     # Hard difficulty
	revolver.initialize_fixed()

	assert_eq(revolver.current_ammo, 5,
		"RSh-12: Should load 5 rounds (not 30)")
	assert_eq(revolver.reserve_ammo, 15,
		"RSh-12: Should have 15 reserve rounds (not 90)")
	assert_eq(revolver.get_total_ammo(), 20,
		"RSh-12: Should have 20 total rounds (not 120)")
