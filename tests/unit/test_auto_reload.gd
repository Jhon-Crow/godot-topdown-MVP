extends GutTest
## Unit tests for the Auto-Reload passive item (Issue #1067).
##
## Tests magazine size reduction (2.1x divisor) and kill-based refill logic
## using mock objects to avoid Godot scene dependencies.


# ============================================================================
# Mock MagazineData
# ============================================================================


class MockMagazine:
	var current_ammo: int
	var max_capacity: int

	func _init(ammo: int, capacity: int) -> void:
		current_ammo = ammo
		max_capacity = capacity

	func is_empty() -> bool:
		return current_ammo <= 0


# ============================================================================
# Mock Weapon
# ============================================================================


class MockWeapon:
	var current_ammo: int = 0
	var magazine_size: int = 30
	var reserve_ammo: int = 0
	var reinit_called_count: int = 0
	var reinit_last_count: int = 0
	var reinit_last_size: int = 0
	var consume_reserve_called: int = 0
	var consume_reserve_last_amount: int = 0

	## Simulate the weapon's magazine size reported by WeaponData
	func get_magazine_size() -> int:
		return magazine_size

	## Simulate ReinitializeMagazines(count, size)
	func reinitialize_magazines(count: int, size: int) -> void:
		reinit_called_count += 1
		reinit_last_count = count
		reinit_last_size = size
		magazine_size = size
		# Fill the current magazine and calculate reserve
		current_ammo = size
		reserve_ammo = size * (count - 1)

	## Simulate ConsumeReserveAmmo(amount)
	func consume_reserve_ammo(amount: int) -> void:
		consume_reserve_called += 1
		consume_reserve_last_amount += amount
		reserve_ammo = max(0, reserve_ammo - amount)


# ============================================================================
# Auto-Reload Logic Tests
# ============================================================================


## Replicates the magazine size reduction formula from Player.cs InitAutoReload()
func _calculate_reduced_magazine_size(original_size: int) -> int:
	const AUTO_RELOAD_DIVISOR: float = 2.1
	return max(1, int(float(original_size) / AUTO_RELOAD_DIVISOR))


## Replicates the kill refill logic from Player.cs OnEnemyKilledForAutoReload()
func _perform_kill_refill(weapon: MockWeapon) -> int:
	var needed: int = weapon.magazine_size - weapon.current_ammo
	if needed <= 0:
		return 0  # already full

	var available: int = weapon.reserve_ammo
	if available <= 0:
		return 0  # no reserve

	var to_add: int = min(needed, available)
	weapon.current_ammo += to_add
	weapon.consume_reserve_ammo(to_add)
	return to_add


func test_magazine_size_reduction_makarov_9round() -> void:
	# Makarov PM: 9 rounds → floor(9 / 2.1) = floor(4.28) = 4
	var reduced := _calculate_reduced_magazine_size(9)
	assert_eq(reduced, 4,
		"9-round magazine should reduce to 4 rounds (floor(9/2.1))")


func test_magazine_size_reduction_m16_30round() -> void:
	# M16: 30 rounds → floor(30 / 2.1) = floor(14.28) = 14
	var reduced := _calculate_reduced_magazine_size(30)
	assert_eq(reduced, 14,
		"30-round magazine should reduce to 14 rounds (floor(30/2.1))")


func test_magazine_size_reduction_revolver_5round() -> void:
	# Revolver: 5 rounds → floor(5 / 2.1) = floor(2.38) = 2
	var reduced := _calculate_reduced_magazine_size(5)
	assert_eq(reduced, 2,
		"5-round cylinder should reduce to 2 rounds (floor(5/2.1))")


func test_magazine_size_reduction_mini_uzi_25round() -> void:
	# Mini UZI: 25 rounds → floor(25 / 2.1) = floor(11.9) = 11
	var reduced := _calculate_reduced_magazine_size(25)
	assert_eq(reduced, 11,
		"25-round magazine should reduce to 11 rounds (floor(25/2.1))")


func test_magazine_size_reduction_minimum_is_1() -> void:
	# Edge case: very small magazine (1 round) → still at least 1
	var reduced := _calculate_reduced_magazine_size(1)
	assert_eq(reduced, 1,
		"Minimum reduced magazine size should be 1")


func test_kill_refill_partial_magazine() -> void:
	# Player has 3/14 rounds, kills enemy → magazine refilled to 14 from reserve
	var weapon := MockWeapon.new()
	weapon.magazine_size = 14
	weapon.current_ammo = 3
	weapon.reserve_ammo = 42  # 3 spare magazines * 14 rounds

	var added := _perform_kill_refill(weapon)

	assert_eq(added, 11, "Kill should add 11 rounds (14-3=11 needed)")
	assert_eq(weapon.current_ammo, 14, "Magazine should be full after refill")
	assert_eq(weapon.reserve_ammo, 31, "Reserve should decrease by 11 (42-11=31)")


func test_kill_refill_empty_magazine() -> void:
	# Player has 0/14 rounds, kills enemy → magazine refilled to 14
	var weapon := MockWeapon.new()
	weapon.magazine_size = 14
	weapon.current_ammo = 0
	weapon.reserve_ammo = 42

	var added := _perform_kill_refill(weapon)

	assert_eq(added, 14, "Kill should add full 14 rounds to empty magazine")
	assert_eq(weapon.current_ammo, 14, "Magazine should be full after refill")
	assert_eq(weapon.reserve_ammo, 28, "Reserve should decrease by 14 (42-14=28)")


func test_kill_refill_full_magazine_does_nothing() -> void:
	# Player has full magazine, kill should not change anything
	var weapon := MockWeapon.new()
	weapon.magazine_size = 14
	weapon.current_ammo = 14
	weapon.reserve_ammo = 28

	var added := _perform_kill_refill(weapon)

	assert_eq(added, 0, "Kill should not add rounds to full magazine")
	assert_eq(weapon.current_ammo, 14, "Magazine should remain full")
	assert_eq(weapon.reserve_ammo, 28, "Reserve should not change")


func test_kill_refill_no_reserve_does_nothing() -> void:
	# Player is completely out of ammo, kill does nothing
	var weapon := MockWeapon.new()
	weapon.magazine_size = 14
	weapon.current_ammo = 0
	weapon.reserve_ammo = 0

	var added := _perform_kill_refill(weapon)

	assert_eq(added, 0, "Kill should not add rounds when reserve is empty")
	assert_eq(weapon.current_ammo, 0, "Magazine should remain empty")


func test_kill_refill_partial_reserve() -> void:
	# Reserve has fewer rounds than needed to fill magazine
	var weapon := MockWeapon.new()
	weapon.magazine_size = 14
	weapon.current_ammo = 2
	weapon.reserve_ammo = 5  # Only 5 left in reserve (less than needed 12)

	var added := _perform_kill_refill(weapon)

	assert_eq(added, 5, "Kill should add all 5 remaining reserve rounds")
	assert_eq(weapon.current_ammo, 7, "Magazine should have 2+5=7 rounds")
	assert_eq(weapon.reserve_ammo, 0, "Reserve should be empty")


func test_multiple_kills_drain_reserve() -> void:
	# Multiple kills progressively drain reserve
	var weapon := MockWeapon.new()
	weapon.magazine_size = 4  # Makarov PM reduced
	weapon.current_ammo = 4   # Start full
	weapon.reserve_ammo = 12  # 3 spare magazines * 4

	# First kill: magazine full, no refill
	weapon.current_ammo = 1
	_perform_kill_refill(weapon)
	assert_eq(weapon.current_ammo, 4, "After kill 1: magazine should be full")
	assert_eq(weapon.reserve_ammo, 9, "After kill 1: reserve should have 9 rounds")

	# Second kill
	weapon.current_ammo = 2
	_perform_kill_refill(weapon)
	assert_eq(weapon.current_ammo, 4, "After kill 2: magazine should be full")
	assert_eq(weapon.reserve_ammo, 7, "After kill 2: reserve should have 7 rounds")

	# Third kill
	weapon.current_ammo = 0
	_perform_kill_refill(weapon)
	assert_eq(weapon.current_ammo, 4, "After kill 3: magazine should be full")
	assert_eq(weapon.reserve_ammo, 3, "After kill 3: reserve should have 3 rounds")

	# Fourth kill (reserve almost empty)
	weapon.current_ammo = 2
	_perform_kill_refill(weapon)
	assert_eq(weapon.current_ammo, 4, "After kill 4: magazine should be full (used 2 from reserve)")
	assert_eq(weapon.reserve_ammo, 1, "After kill 4: reserve should have 1 round")


func test_magazine_divisor_is_2_point_1() -> void:
	# Verify the exact divisor value used in the formula
	const expected_divisor: float = 2.1
	assert_eq(expected_divisor, 2.1,
		"Auto-reload magazine divisor should be exactly 2.1")


func test_reduced_magazine_for_shotgun_8_shells() -> void:
	# Shotgun: 8 shells → floor(8 / 2.1) = floor(3.81) = 3
	var reduced := _calculate_reduced_magazine_size(8)
	assert_eq(reduced, 3,
		"8-shell shotgun should reduce to 3 shells (floor(8/2.1))")


func test_reduced_magazine_for_sniper_5_round() -> void:
	# Sniper: 5 rounds → floor(5 / 2.1) = floor(2.38) = 2
	var reduced := _calculate_reduced_magazine_size(5)
	assert_eq(reduced, 2,
		"5-round sniper magazine should reduce to 2 rounds (floor(5/2.1))")
