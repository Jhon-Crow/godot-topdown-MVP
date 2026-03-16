extends GutTest
## Unit tests for Revolver multi-step cylinder reload mechanics (Issue #626).
##
## Tests the revolver reload sequence:
## R (open cylinder) → RMB drag up (insert cartridge) → scroll wheel (rotate cylinder)
## → repeat insert+rotate → R (close cylinder).
## Uses mock classes to test logic without requiring Godot scene tree or C# runtime.


# Mock implementation that mirrors the Revolver reload behavior
class MockRevolverReload:
	## Reload states matching RevolverReloadState enum
	const NOT_RELOADING = 0
	const CYLINDER_OPEN = 1
	const LOADING = 2
	const CLOSING = 3

	var reload_state: int = NOT_RELOADING
	var current_ammo: int = 5
	var cylinder_capacity: int = 5
	var cartridges_loaded_this_reload: int = 0
	var is_reloading: bool = false

	## Spare ammo stored as individual rounds (simplified from magazine system)
	var reserve_ammo: int = 10

	## Issue #659: Tracks rounds actually fired since last casing ejection.
	## Only these rounds produce casings when the cylinder is opened.
	var rounds_fired_since_last_eject: int = 0

	## Issue #659: Whether cartridge insertion is blocked until cylinder rotation.
	## After inserting a cartridge, the player must scroll (rotate) to the next
	## empty chamber before inserting another.
	var cartridge_insertion_blocked: bool = false

	## Issue #668: Per-chamber occupancy tracking.
	## Each element indicates whether the corresponding chamber has a live round.
	var chamber_occupied: Array[bool] = []

	## Issue #668: Current chamber index the cylinder is pointing at.
	var current_chamber_index: int = 0

	## Callbacks for signal simulation
	var on_reload_state_changed: Callable
	var on_cartridge_inserted: Callable
	var on_casings_ejected: Callable
	var on_reload_started: Callable
	var on_reload_finished: Callable
	var on_ammo_changed: Callable

	## Track events for assertions
	var casings_ejected_count: int = 0
	var reload_started_emitted: bool = false
	var reload_finished_emitted: bool = false
	var cylinder_rotations: int = 0


	func _init() -> void:
		# Issue #668: Initialize per-chamber tracking.
		# All chambers start as occupied (full cylinder at game start).
		chamber_occupied.clear()
		for i in range(cylinder_capacity):
			chamber_occupied.append(true)
		current_chamber_index = 0


	## Issue #668: Check if the current chamber is empty.
	func is_current_chamber_empty() -> bool:
		if chamber_occupied.size() == 0:
			return true
		if current_chamber_index >= chamber_occupied.size():
			return true
		return not chamber_occupied[current_chamber_index]


	func can_open_cylinder() -> bool:
		return reload_state == NOT_RELOADING and not is_reloading


	func can_insert_cartridge() -> bool:
		return (reload_state == CYLINDER_OPEN or reload_state == LOADING) \
			and current_ammo < cylinder_capacity \
			and reserve_ammo > 0 \
			and is_current_chamber_empty()


	func can_close_cylinder() -> bool:
		return reload_state == CYLINDER_OPEN or reload_state == LOADING


	## Simulates firing a round (decrements ammo, tracks fired count).
	func fire() -> bool:
		if reload_state != NOT_RELOADING:
			return false
		if current_ammo <= 0:
			return false
		current_ammo -= 1
		rounds_fired_since_last_eject += 1
		# Issue #668: Mark the current chamber as empty and advance.
		if chamber_occupied.size() > 0:
			chamber_occupied[current_chamber_index] = false
			current_chamber_index = (current_chamber_index + 1) % chamber_occupied.size()
		return true


	func open_cylinder() -> bool:
		if not can_open_cylinder():
			return false

		# Issue #659: Only eject casings for rounds actually fired since last ejection.
		# This prevents duplicate casing ejection when cylinder is opened/closed
		# repeatedly without firing in between.
		casings_ejected_count = rounds_fired_since_last_eject

		# Live rounds stay in the cylinder - only spent casings fall out.
		# CurrentAmmo is NOT reset to 0 - the player only needs to reload empty chambers.
		cartridges_loaded_this_reload = 0

		# Issue #668: Ensure chamber array is properly sized.
		if chamber_occupied.size() != cylinder_capacity:
			chamber_occupied.clear()
			for i in range(cylinder_capacity):
				chamber_occupied.append(i < current_ammo)

		# Issue #668: Set insertion block based on whether current chamber is occupied.
		cartridge_insertion_blocked = chamber_occupied.size() > 0 \
			and current_chamber_index < chamber_occupied.size() \
			and chamber_occupied[current_chamber_index]

		# Update state
		reload_state = CYLINDER_OPEN
		reload_started_emitted = true

		if casings_ejected_count > 0:
			# Reset fired counter after ejecting casings
			rounds_fired_since_last_eject = 0
			if on_casings_ejected:
				on_casings_ejected.call(casings_ejected_count)
		if on_reload_state_changed:
			on_reload_state_changed.call(reload_state)
		if on_reload_started:
			on_reload_started.call()
		if on_ammo_changed:
			on_ammo_changed.call(current_ammo, reserve_ammo)

		return true


	func insert_cartridge() -> bool:
		if not can_insert_cartridge():
			return false

		# Consume one round from reserve
		reserve_ammo -= 1

		# Add one round to cylinder
		current_ammo += 1
		cartridges_loaded_this_reload += 1

		# Issue #668: Mark the current chamber as occupied.
		if chamber_occupied.size() > 0 and current_chamber_index < chamber_occupied.size():
			chamber_occupied[current_chamber_index] = true

		# Update state to Loading
		reload_state = LOADING

		if on_cartridge_inserted:
			on_cartridge_inserted.call(cartridges_loaded_this_reload, cylinder_capacity)
		if on_reload_state_changed:
			on_reload_state_changed.call(reload_state)
		if on_ammo_changed:
			on_ammo_changed.call(current_ammo, reserve_ammo)

		return true


	func close_cylinder() -> bool:
		if not can_close_cylinder():
			return false

		reload_state = NOT_RELOADING
		is_reloading = false
		reload_finished_emitted = true

		if on_reload_state_changed:
			on_reload_state_changed.call(reload_state)
		if on_reload_finished:
			on_reload_finished.call()
		if on_ammo_changed:
			on_ammo_changed.call(current_ammo, reserve_ammo)

		return true


	func can_rotate_cylinder() -> bool:
		return reload_state == CYLINDER_OPEN or reload_state == LOADING


	func rotate_cylinder(direction: int) -> bool:
		if not can_rotate_cylinder():
			return false
		cylinder_rotations += 1
		# Issue #668: Advance the chamber index in the rotation direction.
		var capacity := chamber_occupied.size() if chamber_occupied.size() > 0 else cylinder_capacity
		current_chamber_index = ((current_chamber_index + direction) % capacity + capacity) % capacity
		# Issue #668: Only unblock insertion if the destination chamber is empty.
		# Issue #659: Rotating moves to the next chamber for insertion.
		cartridge_insertion_blocked = chamber_occupied.size() > 0 \
			and current_chamber_index < chamber_occupied.size() \
			and chamber_occupied[current_chamber_index]
		return true


var revolver: MockRevolverReload


func before_each() -> void:
	revolver = MockRevolverReload.new()


func after_each() -> void:
	revolver = null


# ============================================================================
# Open Cylinder Tests
# ============================================================================


func test_can_open_cylinder_when_not_reloading() -> void:
	assert_true(revolver.can_open_cylinder(), "Should be able to open cylinder when not reloading")


func test_cannot_open_cylinder_when_already_open() -> void:
	revolver.open_cylinder()

	assert_false(revolver.can_open_cylinder(), "Should not be able to open cylinder when already open")


func test_open_cylinder_sets_state_to_cylinder_open() -> void:
	revolver.open_cylinder()

	assert_eq(revolver.reload_state, MockRevolverReload.CYLINDER_OPEN,
		"Reload state should be CylinderOpen after opening")


func test_open_cylinder_preserves_live_ammo() -> void:
	revolver.current_ammo = 3  # 3 live rounds, 2 spent
	revolver.rounds_fired_since_last_eject = 2
	revolver.open_cylinder()

	assert_eq(revolver.current_ammo, 3, "Live rounds should stay in cylinder after opening")


func test_open_cylinder_ejects_correct_number_of_casings() -> void:
	revolver.current_ammo = 2  # 2 live rounds, 3 fired
	revolver.rounds_fired_since_last_eject = 3
	revolver.open_cylinder()

	assert_eq(revolver.casings_ejected_count, 3, "Should eject 3 casings (3 rounds fired)")


func test_open_cylinder_with_no_rounds_fired_ejects_zero_casings() -> void:
	revolver.current_ammo = 5  # Full cylinder, nothing fired
	revolver.rounds_fired_since_last_eject = 0
	revolver.open_cylinder()

	assert_eq(revolver.casings_ejected_count, 0, "Should eject 0 casings when nothing was fired")


func test_open_cylinder_after_firing_all_ejects_all_casings() -> void:
	revolver.current_ammo = 0  # All 5 fired
	revolver.rounds_fired_since_last_eject = 5
	revolver.open_cylinder()

	assert_eq(revolver.casings_ejected_count, 5, "Should eject 5 casings (all 5 fired)")


func test_open_cylinder_emits_reload_started() -> void:
	revolver.open_cylinder()

	assert_true(revolver.reload_started_emitted, "Should emit reload started signal")


func test_open_cylinder_resets_cartridges_loaded_counter() -> void:
	revolver.open_cylinder()

	assert_eq(revolver.cartridges_loaded_this_reload, 0,
		"Cartridges loaded counter should be 0 after opening")


# ============================================================================
# Insert Cartridge Tests
# ============================================================================


func test_can_insert_cartridge_when_cylinder_open() -> void:
	revolver.current_ammo = 3  # 3 live rounds, 2 empty chambers
	revolver.rounds_fired_since_last_eject = 2
	# Issue #668: Mark first 2 chambers as fired (empty), rest occupied
	# After firing 2 shots, chambers 0 and 1 are empty, current_chamber_index is at 2
	revolver.chamber_occupied[0] = false
	revolver.chamber_occupied[1] = false
	revolver.current_chamber_index = 2
	revolver.open_cylinder()
	# Current chamber (2) is occupied, need to rotate to an empty one
	revolver.rotate_cylinder(-1)  # Go to chamber 1 (empty)

	assert_true(revolver.can_insert_cartridge(), "Should be able to insert when cylinder is open and current chamber is empty")


func test_cannot_insert_cartridge_when_not_reloading() -> void:
	assert_false(revolver.can_insert_cartridge(), "Should not insert cartridge when not reloading")


func test_insert_cartridge_adds_one_round() -> void:
	revolver.current_ammo = 0  # Empty cylinder
	revolver.rounds_fired_since_last_eject = 5
	# Issue #668: Set all chambers to empty to match fired state
	for i in range(revolver.cylinder_capacity):
		revolver.chamber_occupied[i] = false
	revolver.open_cylinder()
	revolver.insert_cartridge()

	assert_eq(revolver.current_ammo, 1, "Should have 1 round after inserting one cartridge")


func test_insert_cartridge_consumes_reserve_ammo() -> void:
	revolver.current_ammo = 0
	revolver.rounds_fired_since_last_eject = 5
	revolver.reserve_ammo = 10
	# Issue #668: Set all chambers to empty to match fired state
	for i in range(revolver.cylinder_capacity):
		revolver.chamber_occupied[i] = false
	revolver.open_cylinder()
	revolver.insert_cartridge()

	assert_eq(revolver.reserve_ammo, 9, "Reserve ammo should decrease by 1")


func test_insert_cartridge_increments_loaded_counter() -> void:
	revolver.current_ammo = 0
	revolver.rounds_fired_since_last_eject = 5
	# Issue #668: Set all chambers to empty to match fired state
	for i in range(revolver.cylinder_capacity):
		revolver.chamber_occupied[i] = false
	revolver.open_cylinder()
	revolver.insert_cartridge()

	assert_eq(revolver.cartridges_loaded_this_reload, 1,
		"Cartridges loaded counter should be 1")


func test_insert_multiple_cartridges() -> void:
	revolver.current_ammo = 0
	revolver.rounds_fired_since_last_eject = 5
	revolver.reserve_ammo = 10
	# Issue #668: Set all chambers to empty to match fired state
	for i in range(revolver.cylinder_capacity):
		revolver.chamber_occupied[i] = false
	revolver.open_cylinder()

	for i in range(3):
		revolver.insert_cartridge()
		if i < 2:
			revolver.rotate_cylinder(1)  # Rotate to next empty chamber

	assert_eq(revolver.current_ammo, 3, "Should have 3 rounds after 3 insertions")
	assert_eq(revolver.cartridges_loaded_this_reload, 3, "Should have loaded 3 cartridges")
	assert_eq(revolver.reserve_ammo, 7, "Reserve should be 7 (10 - 3)")


func test_insert_all_five_cartridges() -> void:
	revolver.current_ammo = 0
	revolver.rounds_fired_since_last_eject = 5
	revolver.reserve_ammo = 10
	# Issue #668: Set all chambers to empty to match fired state
	for i in range(revolver.cylinder_capacity):
		revolver.chamber_occupied[i] = false
	revolver.open_cylinder()

	for i in range(5):
		assert_true(revolver.insert_cartridge(), "Should insert cartridge %d" % (i + 1))
		if i < 4:
			revolver.rotate_cylinder(1)  # Rotate to next empty chamber

	assert_eq(revolver.current_ammo, 5, "Cylinder should be full (5 rounds)")
	assert_eq(revolver.cartridges_loaded_this_reload, 5, "Should have loaded 5 cartridges")


func test_cannot_insert_more_than_cylinder_capacity() -> void:
	revolver.current_ammo = 0
	revolver.rounds_fired_since_last_eject = 5
	revolver.reserve_ammo = 10
	# Issue #668: Set all chambers to empty to match fired state
	for i in range(revolver.cylinder_capacity):
		revolver.chamber_occupied[i] = false
	revolver.open_cylinder()

	for i in range(5):
		revolver.insert_cartridge()
		if i < 4:
			revolver.rotate_cylinder(1)

	# All chambers are now full, try inserting into any
	revolver.rotate_cylinder(1)
	assert_false(revolver.insert_cartridge(), "Should not insert 6th cartridge (cylinder full)")
	assert_eq(revolver.current_ammo, 5, "Should still have 5 rounds")


func test_cannot_insert_when_no_reserve_ammo() -> void:
	revolver.current_ammo = 0
	revolver.rounds_fired_since_last_eject = 5
	revolver.reserve_ammo = 2
	# Issue #668: Set all chambers to empty to match fired state
	for i in range(revolver.cylinder_capacity):
		revolver.chamber_occupied[i] = false
	revolver.open_cylinder()

	revolver.insert_cartridge()
	revolver.rotate_cylinder(1)
	revolver.insert_cartridge()
	revolver.rotate_cylinder(1)

	assert_false(revolver.insert_cartridge(), "Should not insert with no reserve ammo")
	assert_eq(revolver.current_ammo, 2, "Should have 2 rounds")
	assert_eq(revolver.reserve_ammo, 0, "Reserve should be 0")


func test_insert_cartridge_sets_state_to_loading() -> void:
	revolver.current_ammo = 0
	revolver.rounds_fired_since_last_eject = 5
	# Issue #668: Set all chambers to empty to match fired state
	for i in range(revolver.cylinder_capacity):
		revolver.chamber_occupied[i] = false
	revolver.open_cylinder()
	revolver.insert_cartridge()

	assert_eq(revolver.reload_state, MockRevolverReload.LOADING,
		"State should be Loading after inserting cartridge")


# ============================================================================
# Close Cylinder Tests
# ============================================================================


func test_can_close_cylinder_when_open() -> void:
	revolver.open_cylinder()

	assert_true(revolver.can_close_cylinder(), "Should be able to close when cylinder is open")


func test_can_close_cylinder_when_loading() -> void:
	revolver.current_ammo = 0
	revolver.rounds_fired_since_last_eject = 5
	# Issue #668: Set all chambers to empty to match fired state
	for i in range(revolver.cylinder_capacity):
		revolver.chamber_occupied[i] = false
	revolver.open_cylinder()
	revolver.insert_cartridge()

	assert_true(revolver.can_close_cylinder(), "Should be able to close during loading")


func test_cannot_close_cylinder_when_not_reloading() -> void:
	assert_false(revolver.can_close_cylinder(), "Should not close when not reloading")


func test_close_cylinder_sets_state_to_not_reloading() -> void:
	revolver.current_ammo = 0
	revolver.rounds_fired_since_last_eject = 5
	# Issue #668: Set all chambers to empty to match fired state
	for i in range(revolver.cylinder_capacity):
		revolver.chamber_occupied[i] = false
	revolver.open_cylinder()
	revolver.insert_cartridge()
	revolver.close_cylinder()

	assert_eq(revolver.reload_state, MockRevolverReload.NOT_RELOADING,
		"State should be NotReloading after closing")


func test_close_cylinder_preserves_loaded_ammo() -> void:
	revolver.current_ammo = 0
	revolver.rounds_fired_since_last_eject = 5
	revolver.reserve_ammo = 10
	# Issue #668: Set all chambers to empty to match fired state
	for i in range(revolver.cylinder_capacity):
		revolver.chamber_occupied[i] = false
	revolver.open_cylinder()

	revolver.insert_cartridge()
	revolver.rotate_cylinder(1)
	revolver.insert_cartridge()
	revolver.rotate_cylinder(1)
	revolver.insert_cartridge()

	revolver.close_cylinder()

	assert_eq(revolver.current_ammo, 3, "Should preserve 3 loaded rounds after closing")


func test_close_cylinder_emits_reload_finished() -> void:
	revolver.current_ammo = 0
	revolver.rounds_fired_since_last_eject = 5
	# Issue #668: Set all chambers to empty to match fired state
	for i in range(revolver.cylinder_capacity):
		revolver.chamber_occupied[i] = false
	revolver.open_cylinder()
	revolver.insert_cartridge()
	revolver.close_cylinder()

	assert_true(revolver.reload_finished_emitted, "Should emit reload finished signal")


func test_close_cylinder_without_loading_any() -> void:
	revolver.current_ammo = 3
	revolver.rounds_fired_since_last_eject = 2
	revolver.open_cylinder()
	revolver.close_cylinder()

	assert_eq(revolver.current_ammo, 3,
		"Should preserve live rounds when closed without loading any new ones")
	assert_eq(revolver.reload_state, MockRevolverReload.NOT_RELOADING, "Should be NotReloading")


# ============================================================================
# Full Reload Sequence Tests
# ============================================================================


func test_full_reload_sequence_5_cartridges() -> void:
	## Test the complete issue #626 sequence:
	## 1. Fire all 5 rounds
	## 2. R key: Open cylinder (casings fall out)
	## 3. RMB drag up: Insert cartridge, then scroll wheel: rotate cylinder (5 times)
	## 4. R key: Close cylinder

	revolver.current_ammo = 5
	revolver.reserve_ammo = 10

	# Fire all 5 rounds
	for i in range(5):
		revolver.fire()
	assert_eq(revolver.current_ammo, 0, "Should have 0 ammo after firing 5")
	assert_eq(revolver.rounds_fired_since_last_eject, 5, "Should track 5 fired rounds")

	# Step 1: Open cylinder (R key)
	assert_true(revolver.open_cylinder(), "Should open cylinder")
	assert_eq(revolver.reload_state, MockRevolverReload.CYLINDER_OPEN, "Should be CylinderOpen")
	assert_eq(revolver.casings_ejected_count, 5, "Should eject 5 spent casings")
	assert_eq(revolver.rounds_fired_since_last_eject, 0, "Fired counter should reset after ejection")

	# Step 2: Insert 5 cartridges (one per RMB drag up) with cylinder rotation (scroll wheel)
	for i in range(5):
		assert_true(revolver.insert_cartridge(), "Should insert cartridge %d" % (i + 1))
		assert_eq(revolver.current_ammo, i + 1, "Ammo should be %d" % (i + 1))
		if i < 4:  # Rotate after each insert except the last
			assert_true(revolver.rotate_cylinder(1), "Should rotate cylinder")

	assert_eq(revolver.reload_state, MockRevolverReload.LOADING, "Should be Loading")
	assert_eq(revolver.cartridges_loaded_this_reload, 5, "Should have loaded 5 cartridges")

	# Step 3: Close cylinder (R key)
	assert_true(revolver.close_cylinder(), "Should close cylinder")
	assert_eq(revolver.reload_state, MockRevolverReload.NOT_RELOADING, "Should be NotReloading")
	assert_eq(revolver.current_ammo, 5, "Should have full cylinder (5 rounds)")
	assert_eq(revolver.reserve_ammo, 5, "Reserve should be 5 (10 - 5)")


func test_partial_reload_3_cartridges() -> void:
	## Test partial reload: only insert 3 cartridges instead of 5

	revolver.current_ammo = 5
	revolver.reserve_ammo = 10

	# Fire all 5 rounds
	for i in range(5):
		revolver.fire()

	revolver.open_cylinder()

	# Insert only 3 cartridges (with rotation between each)
	for i in range(3):
		revolver.insert_cartridge()
		if i < 2:
			revolver.rotate_cylinder(1)

	revolver.close_cylinder()

	assert_eq(revolver.current_ammo, 3, "Should have 3 rounds after partial reload")
	assert_eq(revolver.reserve_ammo, 7, "Reserve should be 7 (10 - 3)")


func test_reload_with_partially_spent_cylinder() -> void:
	## Test reload when only 2 of 5 rounds were fired

	revolver.current_ammo = 5
	revolver.reserve_ammo = 10

	# Fire 2 rounds (3 live remain)
	revolver.fire()
	revolver.fire()
	assert_eq(revolver.current_ammo, 3, "Should have 3 live rounds after firing 2")

	revolver.open_cylinder()
	assert_eq(revolver.casings_ejected_count, 2, "Should eject 2 spent casings")
	assert_eq(revolver.current_ammo, 3, "Live rounds should stay in cylinder")

	# Issue #668: Navigate to the empty chambers to insert cartridges.
	# After firing 2 rounds, chambers 0 and 1 are empty, current_chamber_index is at 2 (occupied).
	# Need to rotate to find empty chambers.
	# Rotate backwards to find the first empty chamber (chamber 1)
	revolver.rotate_cylinder(-1)
	revolver.insert_cartridge()
	# Rotate backwards again to find the second empty chamber (chamber 0)
	revolver.rotate_cylinder(-1)
	revolver.insert_cartridge()

	revolver.close_cylinder()

	assert_eq(revolver.current_ammo, 5, "Should have full cylinder")
	assert_eq(revolver.reserve_ammo, 8, "Reserve should be 8 (10 - 2)")


func test_reload_with_limited_reserve() -> void:
	## Test reload when reserve ammo is less than cylinder capacity

	revolver.current_ammo = 5
	revolver.reserve_ammo = 3

	# Fire all 5
	for i in range(5):
		revolver.fire()

	revolver.open_cylinder()

	# Try to insert 5 but only 3 available (rotate between inserts)
	var inserted := 0
	for i in range(5):
		if revolver.insert_cartridge():
			inserted += 1
		revolver.rotate_cylinder(1)

	assert_eq(inserted, 3, "Should only insert 3 (limited by reserve)")
	assert_eq(revolver.current_ammo, 3, "Should have 3 rounds")
	assert_eq(revolver.reserve_ammo, 0, "Reserve should be 0")

	revolver.close_cylinder()
	assert_eq(revolver.current_ammo, 3, "Should preserve 3 rounds after closing")


func test_multiple_reloads_preserve_ammo() -> void:
	## Test that ammo is properly tracked across multiple reload cycles

	revolver.current_ammo = 5
	revolver.reserve_ammo = 15  # 3 full reloads worth

	# First cycle: fire 3 rounds, reload to full
	for i in range(3):
		revolver.fire()
	assert_eq(revolver.current_ammo, 2, "Should have 2 after firing 3")
	revolver.open_cylinder()
	# Issue #668: Navigate to empty chambers. After firing 3, chambers 0,1,2 are empty.
	# current_chamber_index is at 3 (occupied). Rotate backward to find empties.
	revolver.rotate_cylinder(-1)  # to chamber 2 (empty)
	revolver.insert_cartridge()
	revolver.rotate_cylinder(-1)  # to chamber 1 (empty)
	revolver.insert_cartridge()
	revolver.rotate_cylinder(-1)  # to chamber 0 (empty)
	revolver.insert_cartridge()
	revolver.close_cylinder()
	assert_eq(revolver.current_ammo, 5, "Should be full after first reload")
	assert_eq(revolver.reserve_ammo, 12, "Reserve should be 12 (15 - 3)")

	# Second cycle: fire all 5, reload to full
	for i in range(5):
		revolver.fire()
	assert_eq(revolver.current_ammo, 0, "Should have 0 after firing 5")
	revolver.open_cylinder()
	for i in range(5):
		revolver.insert_cartridge()
		if i < 4:
			revolver.rotate_cylinder(1)
	revolver.close_cylinder()
	assert_eq(revolver.current_ammo, 5, "Should be full after second reload")
	assert_eq(revolver.reserve_ammo, 7, "Reserve should be 7 (12 - 5)")


func test_cannot_fire_during_reload() -> void:
	## Verify that the reload state blocks firing (state check)
	revolver.open_cylinder()

	assert_ne(revolver.reload_state, MockRevolverReload.NOT_RELOADING,
		"Reload state should not be NotReloading during reload")


# ============================================================================
# Edge Case Tests
# ============================================================================


func test_open_cylinder_with_zero_reserve_still_opens() -> void:
	## Player should be able to open cylinder even with no reserve
	## (to inspect or for tactical reasons)
	revolver.current_ammo = 3
	revolver.rounds_fired_since_last_eject = 2
	revolver.reserve_ammo = 0

	assert_true(revolver.open_cylinder(), "Should open cylinder even with no reserve")
	assert_eq(revolver.reload_state, MockRevolverReload.CYLINDER_OPEN, "Should be CylinderOpen")


func test_close_immediately_after_open() -> void:
	## Player opens cylinder then immediately closes without loading
	## Live rounds stay in the cylinder (they don't fall out)
	revolver.current_ammo = 3
	revolver.rounds_fired_since_last_eject = 2
	revolver.reserve_ammo = 10

	revolver.open_cylinder()
	revolver.close_cylinder()

	assert_eq(revolver.current_ammo, 3,
		"Should preserve 3 live rounds (spent casings ejected, live rounds stay)")
	assert_eq(revolver.reload_state, MockRevolverReload.NOT_RELOADING, "Should be NotReloading")


func test_callback_on_cartridge_insert() -> void:
	var insert_count := 0
	var insert_capacity := 0
	revolver.on_cartridge_inserted = func(loaded: int, capacity: int):
		insert_count = loaded
		insert_capacity = capacity

	revolver.current_ammo = 0
	revolver.rounds_fired_since_last_eject = 5
	# Issue #668: Set all chambers to empty to match fired state
	for i in range(revolver.cylinder_capacity):
		revolver.chamber_occupied[i] = false
	revolver.open_cylinder()
	revolver.insert_cartridge()

	assert_eq(insert_count, 1, "Callback should report 1 cartridge loaded")
	assert_eq(insert_capacity, 5, "Callback should report capacity of 5")


func test_callback_on_casings_ejected() -> void:
	var ejected := 0
	revolver.on_casings_ejected = func(count: int):
		ejected = count

	revolver.current_ammo = 1  # 1 live, 4 were fired
	revolver.rounds_fired_since_last_eject = 4
	revolver.open_cylinder()

	assert_eq(ejected, 4, "Callback should report 4 casings ejected")


# ============================================================================
# Cylinder Rotation Tests (scroll wheel)
# ============================================================================


func test_can_rotate_cylinder_when_open() -> void:
	revolver.open_cylinder()

	assert_true(revolver.can_rotate_cylinder(), "Should be able to rotate when cylinder is open")


func test_can_rotate_cylinder_when_loading() -> void:
	revolver.current_ammo = 0
	revolver.rounds_fired_since_last_eject = 5
	# Issue #668: Set all chambers to empty to match fired state
	for i in range(revolver.cylinder_capacity):
		revolver.chamber_occupied[i] = false
	revolver.open_cylinder()
	revolver.insert_cartridge()

	assert_true(revolver.can_rotate_cylinder(), "Should be able to rotate during loading")


func test_cannot_rotate_cylinder_when_not_reloading() -> void:
	assert_false(revolver.can_rotate_cylinder(), "Should not rotate when not reloading")


func test_rotate_cylinder_clockwise() -> void:
	revolver.open_cylinder()

	assert_true(revolver.rotate_cylinder(1), "Should rotate clockwise")
	assert_eq(revolver.cylinder_rotations, 1, "Should track 1 rotation")


func test_rotate_cylinder_counter_clockwise() -> void:
	revolver.open_cylinder()

	assert_true(revolver.rotate_cylinder(-1), "Should rotate counter-clockwise")
	assert_eq(revolver.cylinder_rotations, 1, "Should track 1 rotation")


func test_multiple_rotations() -> void:
	revolver.open_cylinder()

	for i in range(5):
		revolver.rotate_cylinder(1)

	assert_eq(revolver.cylinder_rotations, 5, "Should track 5 rotations")


func test_full_sequence_with_rotation() -> void:
	## Test complete sequence: fire all → R → (RMB drag up + scroll) × 5 → R

	revolver.current_ammo = 5
	revolver.reserve_ammo = 10

	# Fire all 5
	for i in range(5):
		revolver.fire()

	# Open cylinder (R)
	revolver.open_cylinder()

	# Insert and rotate 5 times (RMB drag up + scroll wheel)
	for i in range(5):
		revolver.insert_cartridge()  # RMB drag up
		revolver.rotate_cylinder(1)  # Scroll wheel

	# Close cylinder (R)
	revolver.close_cylinder()

	assert_eq(revolver.current_ammo, 5, "Should have full cylinder")
	assert_eq(revolver.cylinder_rotations, 5, "Should have rotated 5 times")
	assert_eq(revolver.reserve_ammo, 5, "Reserve should be 5")


# ============================================================================
# Issue #659 Bug Fix Tests: One cartridge per drag gesture
# ============================================================================


## Mock drag gesture handler that mirrors the Revolver.HandleDragGestures() logic.
## Tests the Issue #659 fix: only one cartridge per chamber slot.
## After inserting a cartridge, further insertions are blocked until cylinder rotation.
class MockDragGestureHandler:
	var revolver_mock: MockRevolverReload
	var is_dragging: bool = false
	var drag_start_position: Vector2 = Vector2.ZERO
	var min_drag_distance: float = 30.0

	func _init(mock: MockRevolverReload) -> void:
		revolver_mock = mock

	## Simulates a frame of drag gesture processing.
	## @param rmb_pressed Whether RMB is currently held down.
	## @param mouse_position Current mouse position (screen coords).
	## @return True if a cartridge was inserted this frame.
	func process_frame(rmb_pressed: bool, mouse_position: Vector2) -> bool:
		# Only process while cylinder is open
		if revolver_mock.reload_state != MockRevolverReload.CYLINDER_OPEN \
			and revolver_mock.reload_state != MockRevolverReload.LOADING:
			is_dragging = false
			return false

		if rmb_pressed:
			if not is_dragging:
				drag_start_position = mouse_position
				is_dragging = true
				return false
			elif not revolver_mock.cartridge_insertion_blocked:
				var drag_vector := mouse_position - drag_start_position
				if _try_process_drag_gesture(drag_vector):
					# Issue #659: Block further insertions until cylinder is rotated.
					revolver_mock.cartridge_insertion_blocked = true
					return true
		elif is_dragging:
			# RMB released — reset drag state but keep insertion blocked until rotation
			is_dragging = false

		return false

	## Check if drag gesture meets criteria for cartridge insertion.
	func _try_process_drag_gesture(drag_vector: Vector2) -> bool:
		if drag_vector.length() < min_drag_distance:
			return false
		if abs(drag_vector.y) <= abs(drag_vector.x):
			return false
		if drag_vector.y >= 0:  # Must be drag UP (negative Y in screen coords)
			return false
		return revolver_mock.insert_cartridge()


func test_issue_659_single_cartridge_per_drag() -> void:
	## Issue #659: Verify that only one cartridge is loaded per chamber slot.
	## A continuous upward drag should only load one cartridge, and further
	## insertions are blocked until the cylinder is rotated (scrolled).

	revolver.current_ammo = 0
	revolver.rounds_fired_since_last_eject = 5
	revolver.reserve_ammo = 10
	# Issue #668: Set all chambers to empty to match fired state
	for i in range(revolver.cylinder_capacity):
		revolver.chamber_occupied[i] = false
	revolver.open_cylinder()

	var handler := MockDragGestureHandler.new(revolver)

	# Simulate: press RMB at (500, 500), drag continuously upward
	# Frame 1: RMB pressed — drag starts
	handler.process_frame(true, Vector2(500, 500))
	assert_true(handler.is_dragging, "Should start dragging")
	assert_eq(revolver.current_ammo, 0, "No cartridge yet (not enough drag)")

	# Frame 2-3: Moving up slightly, below threshold
	handler.process_frame(true, Vector2(500, 490))
	assert_eq(revolver.current_ammo, 0, "No cartridge yet (below min drag distance)")

	# Frame 4: Drag exceeds threshold (moved 40px up)
	var inserted := handler.process_frame(true, Vector2(500, 460))
	assert_true(inserted, "Should insert one cartridge")
	assert_eq(revolver.current_ammo, 1, "Should have exactly 1 round")

	# Frame 5-10: Continue dragging upward — should NOT insert more (blocked until rotation)
	for i in range(6):
		inserted = handler.process_frame(true, Vector2(500, 420 - i * 40))
		assert_false(inserted, "Should NOT insert more cartridges (blocked, frame %d)" % i)

	assert_eq(revolver.current_ammo, 1,
		"Issue #659: Should still have exactly 1 round after continuous drag")


func test_issue_659_rmb_release_does_not_unblock() -> void:
	## Issue #659: Releasing RMB should NOT unblock insertion.
	## Only cylinder rotation (scroll) unblocks.

	revolver.current_ammo = 0
	revolver.rounds_fired_since_last_eject = 5
	revolver.reserve_ammo = 10
	# Issue #668: Set all chambers to empty to match fired state
	for i in range(revolver.cylinder_capacity):
		revolver.chamber_occupied[i] = false
	revolver.open_cylinder()

	var handler := MockDragGestureHandler.new(revolver)

	# First drag: insert a cartridge
	handler.process_frame(true, Vector2(500, 500))
	handler.process_frame(true, Vector2(500, 460))
	assert_eq(revolver.current_ammo, 1, "Should insert first cartridge")
	assert_true(revolver.cartridge_insertion_blocked, "Should be blocked after insertion")

	# Release RMB — should NOT unblock
	handler.process_frame(false, Vector2(500, 460))
	assert_true(revolver.cartridge_insertion_blocked,
		"Should STILL be blocked after RMB release (need rotation)")

	# Try another drag without rotating — should NOT insert
	handler.process_frame(true, Vector2(500, 500))
	handler.process_frame(true, Vector2(500, 460))
	assert_eq(revolver.current_ammo, 1,
		"Should still have 1 round (blocked, no rotation)")


func test_issue_659_rotation_unblocks_insertion() -> void:
	## Issue #659: Rotating cylinder (scroll) should unblock insertion.

	revolver.current_ammo = 0
	revolver.rounds_fired_since_last_eject = 5
	revolver.reserve_ammo = 10
	# Issue #668: Set all chambers to empty to match fired state
	for i in range(revolver.cylinder_capacity):
		revolver.chamber_occupied[i] = false
	revolver.open_cylinder()

	var handler := MockDragGestureHandler.new(revolver)

	# Insert first cartridge
	handler.process_frame(true, Vector2(500, 500))
	handler.process_frame(true, Vector2(500, 460))
	assert_eq(revolver.current_ammo, 1, "Should insert first cartridge")
	assert_true(revolver.cartridge_insertion_blocked, "Should be blocked")

	# Release RMB
	handler.process_frame(false, Vector2(500, 460))

	# Rotate cylinder (scroll wheel) — should unblock
	revolver.rotate_cylinder(1)
	assert_false(revolver.cartridge_insertion_blocked,
		"Should be unblocked after rotation")

	# Now drag up again — should insert second cartridge
	handler.process_frame(true, Vector2(500, 500))
	handler.process_frame(true, Vector2(500, 460))
	assert_eq(revolver.current_ammo, 2, "Should insert second cartridge after rotation")


func test_issue_659_five_drags_with_rotations_for_full_reload() -> void:
	## Issue #659: Verify that 5 separate drag+rotation cycles load exactly 5 rounds.
	## Each cycle: drag up (insert) → scroll (rotate) → repeat.

	revolver.current_ammo = 0
	revolver.rounds_fired_since_last_eject = 5
	revolver.reserve_ammo = 10
	# Issue #668: Set all chambers to empty to match fired state
	for i in range(revolver.cylinder_capacity):
		revolver.chamber_occupied[i] = false
	revolver.open_cylinder()

	var handler := MockDragGestureHandler.new(revolver)

	for i in range(5):
		# Press RMB and drag up
		handler.process_frame(true, Vector2(500, 500))
		handler.process_frame(true, Vector2(500, 460))
		# Release RMB
		handler.process_frame(false, Vector2(500, 460))
		# Rotate cylinder to next chamber (except after last insert)
		if i < 4:
			revolver.rotate_cylinder(1)

	assert_eq(revolver.current_ammo, 5, "Should have 5 rounds after 5 drag+rotate cycles")
	assert_eq(revolver.reserve_ammo, 5, "Reserve should be 5 (10 - 5)")


# ============================================================================
# Issue #659 Bug Fix Tests: Casing ejection tracks fired rounds
# ============================================================================


func test_issue_659_no_casings_when_nothing_fired() -> void:
	## Issue #659: Opening cylinder without firing should eject 0 casings.

	revolver.current_ammo = 5
	revolver.rounds_fired_since_last_eject = 0

	revolver.open_cylinder()

	assert_eq(revolver.casings_ejected_count, 0,
		"Should eject 0 casings when nothing was fired")


func test_issue_659_no_duplicate_casings_on_repeated_open() -> void:
	## Issue #659: Opening cylinder repeatedly without firing in between
	## should not eject casings after the first time.

	revolver.current_ammo = 5

	# Fire 3 rounds
	for i in range(3):
		revolver.fire()
	assert_eq(revolver.rounds_fired_since_last_eject, 3, "Should track 3 fired")

	# First open — should eject 3 casings
	revolver.open_cylinder()
	assert_eq(revolver.casings_ejected_count, 3, "First open: should eject 3 casings")
	assert_eq(revolver.rounds_fired_since_last_eject, 0, "Fired counter should reset")

	# Close cylinder
	revolver.close_cylinder()

	# Second open without firing — should eject 0 casings
	revolver.open_cylinder()
	assert_eq(revolver.casings_ejected_count, 0,
		"Second open: should eject 0 casings (nothing fired between opens)")


func test_issue_659_fire_tracks_rounds() -> void:
	## Issue #659: fire() should properly track rounds fired.

	revolver.current_ammo = 5

	assert_true(revolver.fire(), "Should fire first round")
	assert_eq(revolver.current_ammo, 4, "Should have 4 ammo")
	assert_eq(revolver.rounds_fired_since_last_eject, 1, "Should track 1 fired")

	assert_true(revolver.fire(), "Should fire second round")
	assert_eq(revolver.rounds_fired_since_last_eject, 2, "Should track 2 fired")

	# Fire remaining 3
	for i in range(3):
		revolver.fire()
	assert_eq(revolver.current_ammo, 0, "Should be empty")
	assert_eq(revolver.rounds_fired_since_last_eject, 5, "Should track 5 fired")

	# Cannot fire when empty
	assert_false(revolver.fire(), "Should not fire when empty")
	assert_eq(revolver.rounds_fired_since_last_eject, 5,
		"Should not increment on failed fire")


# ============================================================================
# Issue #668 Bug Fix Tests: Per-chamber tracking prevents double-loading
# ============================================================================


func test_issue_668_cannot_insert_into_occupied_chamber() -> void:
	## Issue #668: Inserting a cartridge, rotating forward, then rotating back
	## to the same slot should NOT allow inserting another cartridge.
	## This is the primary bug scenario described in the issue.

	revolver.current_ammo = 0
	revolver.rounds_fired_since_last_eject = 5
	revolver.reserve_ammo = 10
	# Set all chambers empty
	for i in range(revolver.cylinder_capacity):
		revolver.chamber_occupied[i] = false
	revolver.open_cylinder()

	# Insert cartridge into chamber 0
	assert_true(revolver.insert_cartridge(), "Should insert into empty chamber 0")
	assert_eq(revolver.current_ammo, 1, "Should have 1 round")

	# Rotate forward (scroll up) to chamber 1
	revolver.rotate_cylinder(1)
	assert_eq(revolver.current_chamber_index, 1, "Should be at chamber 1")

	# Rotate backward (scroll down) back to chamber 0
	revolver.rotate_cylinder(-1)
	assert_eq(revolver.current_chamber_index, 0, "Should be back at chamber 0")

	# Try to insert into chamber 0 again — should FAIL (already occupied)
	assert_true(revolver.cartridge_insertion_blocked,
		"Insertion should be blocked for occupied chamber")
	assert_false(revolver.can_insert_cartridge(),
		"Issue #668: Should NOT be able to insert into occupied chamber")
	assert_false(revolver.insert_cartridge(),
		"Issue #668: Should NOT insert into occupied chamber 0")
	assert_eq(revolver.current_ammo, 1,
		"Issue #668: Should still have exactly 1 round (no double-loading)")


func test_issue_668_fire_one_then_reload_requires_rotation() -> void:
	## Issue #668: If one shot was fired from a full cylinder, the player
	## must rotate to the empty chamber slot to reload.

	revolver.current_ammo = 5
	revolver.reserve_ammo = 10

	# Fire one shot (chamber 0 becomes empty, current_chamber_index advances to 1)
	assert_true(revolver.fire(), "Should fire")
	assert_eq(revolver.current_ammo, 4, "Should have 4 rounds")
	assert_false(revolver.chamber_occupied[0], "Chamber 0 should be empty after firing")
	assert_eq(revolver.current_chamber_index, 1, "Chamber index should advance to 1")

	# Open cylinder — current chamber (1) is occupied, insertion blocked
	revolver.open_cylinder()
	assert_true(revolver.cartridge_insertion_blocked,
		"Insertion blocked because current chamber (1) is occupied")
	assert_false(revolver.can_insert_cartridge(),
		"Cannot insert into occupied chamber 1")

	# Rotate backward to the empty chamber (chamber 0)
	revolver.rotate_cylinder(-1)
	assert_eq(revolver.current_chamber_index, 0, "Should be at chamber 0")
	assert_false(revolver.cartridge_insertion_blocked,
		"Insertion should be unblocked at empty chamber 0")

	# Now insert the cartridge into the empty chamber
	assert_true(revolver.insert_cartridge(), "Should insert into empty chamber 0")
	assert_eq(revolver.current_ammo, 5, "Should have full cylinder again")

	revolver.close_cylinder()
	assert_eq(revolver.current_ammo, 5, "Full cylinder after closing")


func test_issue_668_chamber_tracking_through_full_cycle() -> void:
	## Issue #668: Verify chamber occupancy tracking through fire → reload → fire cycle.

	revolver.current_ammo = 5
	revolver.reserve_ammo = 10

	# Verify initial state: all chambers occupied
	for i in range(5):
		assert_true(revolver.chamber_occupied[i],
			"Chamber %d should be occupied initially" % i)

	# Fire 3 rounds: chambers 0, 1, 2 become empty
	for i in range(3):
		revolver.fire()

	assert_false(revolver.chamber_occupied[0], "Chamber 0 should be empty")
	assert_false(revolver.chamber_occupied[1], "Chamber 1 should be empty")
	assert_false(revolver.chamber_occupied[2], "Chamber 2 should be empty")
	assert_true(revolver.chamber_occupied[3], "Chamber 3 should still be occupied")
	assert_true(revolver.chamber_occupied[4], "Chamber 4 should still be occupied")
	assert_eq(revolver.current_chamber_index, 3, "Should be at chamber 3")

	# Open cylinder and reload the empty chambers
	revolver.open_cylinder()

	# Navigate to empty chambers and insert
	revolver.rotate_cylinder(-1)  # To chamber 2 (empty)
	assert_true(revolver.insert_cartridge(), "Should insert into chamber 2")
	revolver.rotate_cylinder(-1)  # To chamber 1 (empty)
	assert_true(revolver.insert_cartridge(), "Should insert into chamber 1")
	revolver.rotate_cylinder(-1)  # To chamber 0 (empty)
	assert_true(revolver.insert_cartridge(), "Should insert into chamber 0")

	# Try to rotate to an occupied chamber and insert — should fail
	revolver.rotate_cylinder(-1)  # To chamber 4 (occupied)
	assert_false(revolver.can_insert_cartridge(),
		"Should not insert into occupied chamber 4")

	revolver.close_cylinder()
	assert_eq(revolver.current_ammo, 5, "Should have full cylinder")

	# Verify all chambers are occupied
	for i in range(5):
		assert_true(revolver.chamber_occupied[i],
			"Chamber %d should be occupied after reload" % i)


func test_issue_668_rotation_wraps_around() -> void:
	## Issue #668: Cylinder rotation wraps around (chamber 4 → 0 and 0 → 4).

	revolver.current_ammo = 5
	revolver.open_cylinder()

	# Start at chamber 0, rotate forward 5 times (full revolution)
	revolver.current_chamber_index = 0
	for i in range(5):
		revolver.rotate_cylinder(1)
	assert_eq(revolver.current_chamber_index, 0,
		"Should wrap around back to chamber 0 after 5 forward rotations")

	# Rotate backward from chamber 0 should go to chamber 4
	revolver.rotate_cylinder(-1)
	assert_eq(revolver.current_chamber_index, 4,
		"Should wrap to chamber 4 when rotating backward from chamber 0")


func test_issue_668_open_cylinder_with_occupied_current_chamber_blocks() -> void:
	## Issue #668: When opening cylinder, if current chamber is occupied,
	## insertion should be immediately blocked.

	revolver.current_ammo = 5  # Full cylinder
	revolver.rounds_fired_since_last_eject = 0

	revolver.open_cylinder()

	# Current chamber (0) is occupied, so insertion should be blocked
	assert_true(revolver.cartridge_insertion_blocked,
		"Should block insertion when current chamber is occupied on open")
	assert_false(revolver.can_insert_cartridge(),
		"Cannot insert when all chambers are occupied")


func test_issue_668_open_cylinder_with_empty_current_chamber_allows() -> void:
	## Issue #668: When opening cylinder, if current chamber is empty,
	## insertion should be allowed.

	revolver.current_ammo = 5
	revolver.reserve_ammo = 10

	# Fire one round (chamber 0 is now empty, index at 1)
	revolver.fire()

	# Manually set index to 0 (the empty chamber) to simulate this scenario
	revolver.current_chamber_index = 0
	revolver.open_cylinder()

	# Current chamber (0) is empty, so insertion should NOT be blocked
	assert_false(revolver.cartridge_insertion_blocked,
		"Should allow insertion when current chamber is empty on open")
	assert_true(revolver.can_insert_cartridge(),
		"Can insert when current chamber is empty")
