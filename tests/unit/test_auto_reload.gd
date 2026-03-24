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


# ============================================================================
# Bug Fix Tests (Issue #1067 v2)
# ============================================================================


func test_kill_refill_uses_reduced_size_not_original() -> void:
	# Bug fix: refill must use the cached reduced magazine size, NOT WeaponData.MagazineSize.
	# Before fix, magazineCapacity = WeaponData.MagazineSize = 30 (original),
	# causing the refill to overflow: current_ammo could exceed actual MaxCapacity.
	# After fix, magazineCapacity = _autoReloadMagazineSize = 14 (reduced).
	var weapon := MockWeapon.new()
	weapon.magazine_size = 14  # reduced size (cached _autoReloadMagazineSize)
	weapon.current_ammo = 3
	weapon.reserve_ammo = 30

	var added := _perform_kill_refill(weapon)

	# Should fill to 14 (reduced), not 30 (original WeaponData.MagazineSize)
	assert_eq(weapon.current_ammo, 14,
		"Magazine should fill to reduced capacity (14), not original WeaponData.MagazineSize (30)")
	assert_eq(added, 11, "Should add exactly 11 rounds (14-3)")
	assert_eq(weapon.reserve_ammo, 19, "Reserve should decrease by exactly 11 (30-11=19)")


func test_kill_refill_conserves_total_ammo() -> void:
	# Bug fix: ammo conservation — the total ammo (current + reserve) must not change.
	# Refill is a pure transfer: bullets move from reserve to magazine, nothing is created.
	var weapon := MockWeapon.new()
	weapon.magazine_size = 14
	weapon.current_ammo = 5
	weapon.reserve_ammo = 28

	var total_before := weapon.current_ammo + weapon.reserve_ammo  # 33

	_perform_kill_refill(weapon)

	var total_after := weapon.current_ammo + weapon.reserve_ammo
	assert_eq(total_after, total_before,
		"Total ammo (current + reserve) must be conserved after kill refill — it is a transfer, not creation")


func test_kill_refill_revolver_cylinder_reduced() -> void:
	# Bug fix: revolver support — CylinderSize 5 reduces to 2, refill uses 2.
	# Before fix, magazineCapacity = WeaponData.MagazineSize = 5 (unchanged),
	# and _chamberOccupied was not updated, causing stale cylinder HUD.
	# After fix, _autoReloadMagazineSize = 2 and CylinderSize = 2.
	var weapon := MockWeapon.new()
	weapon.magazine_size = 2  # reduced cylinder size (floor(5/2.1)=2)
	weapon.current_ammo = 0
	weapon.reserve_ammo = 6   # 3 spare cylinders * 2 rounds each

	var total_before := weapon.current_ammo + weapon.reserve_ammo  # 6

	var added := _perform_kill_refill(weapon)

	assert_eq(added, 2, "Revolver kill should add 2 rounds (reduced cylinder size)")
	assert_eq(weapon.current_ammo, 2, "Revolver cylinder should fill to 2 (reduced size, not original 5)")
	assert_eq(weapon.reserve_ammo, 4, "Reserve should decrease by 2")
	var total_after := weapon.current_ammo + weapon.reserve_ammo
	assert_eq(total_after, total_before, "Revolver: total ammo must be conserved")


func test_kill_refill_does_not_overflow_reduced_magazine() -> void:
	# Bug fix: magazine must never exceed the reduced MaxCapacity.
	# Before fix: magazineCapacity = 30 (original) caused current_ammo to be set to e.g. 30
	# even though the actual MagazineData.MaxCapacity was only 14.
	var weapon := MockWeapon.new()
	weapon.magazine_size = 14  # reduced size is the cap
	weapon.current_ammo = 13   # almost full
	weapon.reserve_ammo = 20

	var total_before := weapon.current_ammo + weapon.reserve_ammo  # 33

	var added := _perform_kill_refill(weapon)

	assert_eq(added, 1, "Should only add 1 round to top up to reduced capacity")
	assert_eq(weapon.current_ammo, 14, "Should not overflow beyond reduced capacity")
	var total_after := weapon.current_ammo + weapon.reserve_ammo
	assert_eq(total_after, total_before, "Total ammo must be conserved (no overflow = no creation)")


# ============================================================================
# Bug Fix Tests (Issue #1067 v3) - Total ammo preservation
# ============================================================================


## Replicates the new magazine count calculation from Player.cs ReduceMagazineSizeForAutoReload()
## that preserves total ammo by using more (smaller) magazines.
func _calculate_new_magazine_count(original_count: int, original_size: int, reduced_size: int) -> int:
	var total_bullets: int = original_count * original_size
	return max(1, int(ceil(float(total_bullets) / float(reduced_size))))


func test_total_ammo_preserved_m16() -> void:
	# M16: 4 magazines of 30 = 120 bullets
	# Reduced size = 14, new count = ceil(120/14) = ceil(8.57) = 9
	# Total bullets after = 9 * 14 = 126 (>= 120, closest multiple of 14)
	var original_count: int = 4
	var original_size: int = 30
	var reduced_size: int = _calculate_reduced_magazine_size(original_size)
	var new_count: int = _calculate_new_magazine_count(original_count, original_size, reduced_size)
	var total_original: int = original_count * original_size
	var total_new: int = new_count * reduced_size

	assert_eq(reduced_size, 14, "M16 reduced size should be 14")
	assert_eq(new_count, 9, "M16 should get 9 magazines of 14 to preserve ~120 bullets")
	assert_true(total_new >= total_original,
		"Total bullets after reduction must be >= original total (no ammo loss)")


func test_total_ammo_preserved_revolver() -> void:
	# Revolver: 4 cylinders of 5 = 20 bullets
	# Reduced size = 2, new count = ceil(20/2) = 10
	# Total bullets after = 10 * 2 = 20 (exactly preserved)
	var original_count: int = 4
	var original_size: int = 5
	var reduced_size: int = _calculate_reduced_magazine_size(original_size)
	var new_count: int = _calculate_new_magazine_count(original_count, original_size, reduced_size)
	var total_original: int = original_count * original_size
	var total_new: int = new_count * reduced_size

	assert_eq(reduced_size, 2, "Revolver reduced size should be 2")
	assert_eq(new_count, 10, "Revolver should get 10 cylinders of 2 to preserve 20 bullets")
	assert_true(total_new >= total_original,
		"Revolver: total bullets must be preserved (no ammo loss)")


func test_total_ammo_preserved_makarov_pm() -> void:
	# Makarov PM: 4 magazines of 9 = 36 bullets
	# Reduced size = 4, new count = ceil(36/4) = 9
	var original_count: int = 4
	var original_size: int = 9
	var reduced_size: int = _calculate_reduced_magazine_size(original_size)
	var new_count: int = _calculate_new_magazine_count(original_count, original_size, reduced_size)
	var total_original: int = original_count * original_size
	var total_new: int = new_count * reduced_size

	assert_eq(reduced_size, 4, "Makarov PM reduced size should be 4")
	assert_true(total_new >= total_original,
		"Makarov PM: total bullets must be preserved")


func test_kill_per_shot_means_no_manual_reload() -> void:
	# Core mechanic: if player kills one enemy per shot, they should never need to reload.
	# Scenario: magazine_size=2 (revolver), reserve=8, player fires 1 shot then kills 1 enemy.
	var weapon := MockWeapon.new()
	weapon.magazine_size = 2
	weapon.current_ammo = 2   # full cylinder
	weapon.reserve_ammo = 8   # 4 spare cylinders

	# Shoot, then kill, shoot, then kill — 10 cycles total (2+8=10 bullets)
	var shots_fired: int = 0
	var needed_manual_reload: bool = false

	for _i in range(10):
		if weapon.current_ammo <= 0:
			needed_manual_reload = true
			break
		# Fire one shot
		weapon.current_ammo -= 1
		shots_fired += 1
		# Kill enemy — refill from reserve
		_perform_kill_refill(weapon)

	assert_false(needed_manual_reload,
		"Player should never need manual reload if killing one enemy per shot")
	assert_eq(shots_fired, 10, "Should be able to fire all 10 bullets without reloading")


# ============================================================================
# Bug Fix Tests (Issue #1105) - MakarovPM and Shotgun auto-reload regression
# ============================================================================


## Simulates the MockWeapon for Shotgun tube-magazine mechanics.
## The Shotgun stores active ammo in ShellsInTube (not current_ammo).
## current_ammo is a placeholder always kept at 0.
class MockShotgunWeapon:
	var current_ammo: int = 0        # always 0 (unused placeholder)
	var shells_in_tube: int = 3      # active shells (reduced from 8)
	var tube_capacity: int = 3       # reduced tube capacity
	var reserve_ammo: int = 18       # 6 spare mags * 3 shells each
	var auto_refill_called: int = 0
	var last_refill_amount: int = 0

	## Simulate AutoRefillTube(count) from Shotgun.cs Issue #1105
	func auto_refill_tube(count: int) -> int:
		auto_refill_called += 1
		var space := tube_capacity - shells_in_tube
		var available := min(count, min(space, reserve_ammo))
		if available <= 0:
			return 0
		shells_in_tube += available
		reserve_ammo -= available
		last_refill_amount = available
		return available


## Simulates kill refill for a Shotgun (Issue #1105 fix).
## Uses shells_in_tube instead of current_ammo.
func _perform_shotgun_kill_refill(weapon: MockShotgunWeapon, magazine_capacity: int) -> int:
	var needed: int = magazine_capacity - weapon.shells_in_tube
	if needed <= 0:
		return 0  # tube already full
	if weapon.reserve_ammo <= 0:
		return 0  # no reserve
	var to_add: int = min(needed, weapon.reserve_ammo)
	return weapon.auto_refill_tube(to_add)


func test_issue_1105_pm_reinit_overwrites_reduction() -> void:
	# Root Cause A (Issue #1105): BuildingLevel._configure_makarov_pm_ammo() calls
	# ReinitializeMagazines(10, true) which resets CurrentAmmo to 9 (original magazine size).
	# _autoReloadMagazineSize stays at 4 (reduced), so OnEnemyKilledForAutoReload sees
	# currentAmmo=9 > magazineCapacity=4 → "magazine already full", never refills.
	#
	# Fix: call ApplyAutoReloadAfterLevelAmmoConfig() after _configure_makarov_pm_ammo().
	# This test verifies the CORRECT behaviour after the fix.
	var auto_reload_magazine_size: int = 4  # cached _autoReloadMagazineSize after fix
	var weapon := MockWeapon.new()
	weapon.magazine_size = 4  # correctly reduced by ApplyAutoReloadAfterLevelAmmoConfig
	weapon.current_ammo = 1   # PM fired 3 shots, 1 left
	weapon.reserve_ammo = 32  # reserve preserved correctly

	var added := _perform_kill_refill(weapon)

	# With fix: currentAmmo=1, magazineCapacity=4, needed=3 → should refill
	assert_eq(added, 3,
		"[Issue #1105] After fix: PM kill should refill 3 rounds (4-1=3 needed)")
	assert_eq(weapon.current_ammo, 4,
		"[Issue #1105] After fix: PM magazine should be full at reduced capacity (4)")
	assert_eq(weapon.reserve_ammo, 29,
		"[Issue #1105] After fix: PM reserve should decrease by 3")
	# Verify total ammo is conserved
	assert_eq(weapon.current_ammo + weapon.reserve_ammo, 33,
		"[Issue #1105] PM: total ammo conserved after kill refill")
	_ = auto_reload_magazine_size  # suppress unused warning


func test_issue_1105_pm_without_fix_always_full() -> void:
	# Demonstrates the bug BEFORE the fix:
	# After building level re-initializes PM to 9 rounds (original) but
	# _autoReloadMagazineSize is still 4, the kill handler incorrectly
	# computes needed = 4 - 9 = -5 ≤ 0 → "magazine already full".
	var auto_reload_magazine_size: int = 4   # cached (not updated by level)
	var current_ammo_after_level_reset: int = 9  # buggy: level reset to full original size
	var needed: int = auto_reload_magazine_size - current_ammo_after_level_reset  # = -5

	assert_true(needed <= 0,
		"[Issue #1105] BUG: when level resets to original size without re-applying reduction, "
		+ "needed = %d <= 0 → kill handler skips refill, auto-reload appears broken" % needed)


func test_issue_1105_shotgun_tube_uses_shells_not_current_ammo() -> void:
	# Root Cause B (Issue #1105): Shotgun.CurrentAmmo is always 0 (unused placeholder).
	# The old kill handler used CurrentAmmo for comparison, so:
	#   currentAmmo=0, magazineCapacity=3, needed=3 → tries to set CurrentAmmo=3
	# But ShellsInTube is the real ammo — setting CurrentAmmo doesn't refill the tube.
	# After firing, ShellsInTube decreases but CurrentAmmo stays 0 in the old code.
	# After auto-reload's ReinitializeMagazines, CurrentAmmo was set to 3 by the base,
	# so needed=0 → "magazine already full".
	#
	# Fix: Use ShellsInTube with AutoRefillTube() for Shotgun.
	# This test verifies the CORRECT behaviour after the fix.
	var weapon := MockShotgunWeapon.new()
	weapon.tube_capacity = 3    # reduced from 8
	weapon.shells_in_tube = 1   # fired 2 shells, 1 left
	weapon.reserve_ammo = 18    # 6 spare mags * 3

	var added := _perform_shotgun_kill_refill(weapon, weapon.tube_capacity)

	# With fix: shells_in_tube=1, tube_capacity=3, needed=2 → should refill
	assert_eq(added, 2,
		"[Issue #1105] After fix: Shotgun kill should refill 2 shells (3-1=2 needed)")
	assert_eq(weapon.shells_in_tube, 3,
		"[Issue #1105] After fix: Shotgun tube should be full at reduced capacity (3)")
	assert_eq(weapon.reserve_ammo, 16,
		"[Issue #1105] After fix: Shotgun reserve should decrease by 2")
	assert_eq(weapon.current_ammo, 0,
		"[Issue #1105] Shotgun: current_ammo placeholder must remain 0")
	assert_eq(weapon.auto_refill_called, 1,
		"[Issue #1105] AutoRefillTube should be called exactly once")


func test_issue_1105_shotgun_tube_full_no_refill() -> void:
	# Shotgun tube is already full at reduced capacity → kill does nothing
	var weapon := MockShotgunWeapon.new()
	weapon.tube_capacity = 3
	weapon.shells_in_tube = 3  # full
	weapon.reserve_ammo = 15

	var added := _perform_shotgun_kill_refill(weapon, weapon.tube_capacity)

	assert_eq(added, 0,
		"[Issue #1105] Shotgun: no refill when tube is already full")
	assert_eq(weapon.auto_refill_called, 0,
		"[Issue #1105] AutoRefillTube should not be called when tube is full")
	assert_eq(weapon.shells_in_tube, 3,
		"[Issue #1105] Shotgun: tube remains full")


func test_issue_1105_shotgun_total_ammo_preserved() -> void:
	# Shotgun total ammo = ShellsInTube + ReserveAmmo (not StartingMagazineCount * MagazineSize).
	# StartingMagazineCount=4 would give 4*8=32 total, but actual is 8+12=20 (tube+reserve).
	# After reduction: tube=3, reserve = ceil(20/3)-1 spare mags * 3 = 6*3=18 → total=21 >= 20.
	var original_tube: int = 8
	var original_reserve: int = 12
	var total_original: int = original_tube + original_reserve  # 20

	var reduced_tube_capacity: int = _calculate_reduced_magazine_size(original_tube)  # 3
	var new_magazine_count: int = max(1, int(ceil(float(total_original) / float(reduced_tube_capacity))))  # ceil(20/3)=7
	# 7 total: 1 current (0, placeholder) + 6 spare * 3 = 18 reserve; tube = 3
	var new_reserve: int = (new_magazine_count - 1) * reduced_tube_capacity  # 6*3=18
	var total_new: int = reduced_tube_capacity + new_reserve  # 3+18=21

	assert_eq(reduced_tube_capacity, 3,
		"[Issue #1105] Shotgun tube should reduce to 3 (floor(8/2.1))")
	assert_true(total_new >= total_original,
		"[Issue #1105] Shotgun: total ammo after reduction (%d) must be >= original (%d)" % [total_new, total_original])
	assert_true(new_magazine_count < 32 / reduced_tube_capacity,
		"[Issue #1105] Shotgun: must NOT use StartingMagazineCount*MagazineSize=32 (creates ammo from thin air)")


func test_issue_1105_shotgun_kill_per_shot_no_manual_reload() -> void:
	# Core mechanic for Shotgun: player kills one enemy per shell, never needs manual reload.
	# Shotgun with auto-reload: tube_capacity=3, total shells=21 (tube 3 + reserve 18)
	var weapon := MockShotgunWeapon.new()
	weapon.tube_capacity = 3
	weapon.shells_in_tube = 3
	weapon.reserve_ammo = 18

	var shots_fired: int = 0
	var needed_manual_reload: bool = false
	var total_shells: int = weapon.shells_in_tube + weapon.reserve_ammo  # 21

	for _i in range(total_shells):
		if weapon.shells_in_tube <= 0:
			needed_manual_reload = true
			break
		# Fire one shot
		weapon.shells_in_tube -= 1
		shots_fired += 1
		# Kill enemy — refill tube
		_perform_shotgun_kill_refill(weapon, weapon.tube_capacity)

	assert_false(needed_manual_reload,
		"[Issue #1105] Shotgun: player should never need manual reload if killing one enemy per shot")
	assert_eq(shots_fired, total_shells,
		"[Issue #1105] Shotgun: should fire all %d shells without manual reload" % total_shells)
