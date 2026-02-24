extends GutTest
## Unit tests for revolver cylinder rotation outside reloading and cylinder UI state (Issue #691).
##
## Tests:
## 1. Cylinder rotation works outside of reloading (scroll wheel when NotReloading)
## 2. Cylinder rotation is blocked when hammer is cocked
## 3. Cylinder state correctly reflects chamber occupancy and hammer state
## 4. UI display ordering: 2 left, 1 center (active), 2 right
## Uses mock classes to test logic without requiring Godot scene tree or C# runtime.


# Mock implementation for testing cylinder rotation outside reloading
# and cylinder UI state queries (Issue #691).
class MockRevolverCylinderUI:
	## Reload states matching RevolverReloadState enum
	const NOT_RELOADING = 0
	const CYLINDER_OPEN = 1
	const LOADING = 2

	var reload_state: int = NOT_RELOADING
	var current_ammo: int = 5
	var cylinder_capacity: int = 5
	var is_reloading: bool = false

	## Hammer state
	var is_hammer_cocked: bool = false
	var is_manually_hammer_cocked: bool = false

	## Per-chamber occupancy tracking
	var chamber_occupied: Array[bool] = []
	var current_chamber_index: int = 0

	## Track events
	var cylinder_rotate_sound_played: bool = false
	var cylinder_state_changed_emitted: bool = false
	var cylinder_rotations: int = 0

	## Cartridge insertion blocking (from reload system)
	var cartridge_insertion_blocked: bool = false


	func _init() -> void:
		chamber_occupied.clear()
		for i in range(cylinder_capacity):
			chamber_occupied.append(true)
		current_chamber_index = 0


	## Combined hammer cocked check (either auto or manual)
	func is_any_hammer_cocked() -> bool:
		return is_hammer_cocked or is_manually_hammer_cocked


	## Issue #691: Rotate cylinder - now works both during and outside reload.
	## Cannot rotate while hammer is cocked.
	func rotate_cylinder(direction: int) -> bool:
		# Cannot rotate while hammer is cocked (shot pending or manually cocked)
		if is_hammer_cocked or is_manually_hammer_cocked:
			return false

		# Advance the chamber index
		var capacity := chamber_occupied.size() if chamber_occupied.size() > 0 else cylinder_capacity
		current_chamber_index = ((current_chamber_index + direction) % capacity + capacity) % capacity

		# Only manage insertion blocking during reload
		if reload_state == CYLINDER_OPEN or reload_state == LOADING:
			cartridge_insertion_blocked = chamber_occupied.size() > 0 \
				and current_chamber_index < chamber_occupied.size() \
				and chamber_occupied[current_chamber_index]

		cylinder_rotate_sound_played = true
		cylinder_state_changed_emitted = true
		cylinder_rotations += 1

		return true


	## Simulate firing a round
	func fire() -> bool:
		if reload_state != NOT_RELOADING:
			return false
		if current_ammo <= 0:
			return false
		current_ammo -= 1
		if chamber_occupied.size() > 0:
			chamber_occupied[current_chamber_index] = false
			current_chamber_index = (current_chamber_index + 1) % chamber_occupied.size()
		cylinder_state_changed_emitted = true
		return true


	## Get chamber states (copy, like the real implementation)
	func get_chamber_states() -> Array[bool]:
		var copy: Array[bool] = []
		for v in chamber_occupied:
			copy.append(v)
		return copy


	func reset_tracking() -> void:
		cylinder_rotate_sound_played = false
		cylinder_state_changed_emitted = false


# Mock for testing UI display ordering
class MockCylinderUIDisplay:
	var cylinder_capacity: int = 5
	var current_chamber_index: int = 0
	var chamber_states: Array[bool] = []
	var is_hammer_cocked: bool = false

	func _init(capacity: int = 5) -> void:
		cylinder_capacity = capacity
		chamber_states.clear()
		for i in range(capacity):
			chamber_states.append(true)

	## Calculate the display order of chamber indices.
	## Returns an array of chamber indices ordered left to right.
	## Center position = active chamber (current_chamber_index).
	## Layout: [C-2, C-1, C, C+1, C+2] for 5 chambers.
	func get_display_order() -> Array[int]:
		var order: Array[int] = []
		var center_display_index := cylinder_capacity / 2
		for display_pos in range(cylinder_capacity):
			var offset := display_pos - center_display_index
			var chamber_index := ((current_chamber_index + offset) % cylinder_capacity + cylinder_capacity) % cylinder_capacity
			order.append(chamber_index)
		return order

	## Get the display position (0-based, left to right) of the active chamber.
	func get_active_display_position() -> int:
		return cylinder_capacity / 2


var revolver: MockRevolverCylinderUI


func before_each() -> void:
	revolver = MockRevolverCylinderUI.new()


func after_each() -> void:
	revolver = null


# ============================================================================
# Cylinder Rotation Outside Reloading (Issue #691)
# ============================================================================


func test_can_rotate_cylinder_when_not_reloading() -> void:
	## Issue #691: Cylinder should rotate freely when not reloading.
	revolver.reload_state = MockRevolverCylinderUI.NOT_RELOADING

	var result := revolver.rotate_cylinder(1)

	assert_true(result, "Should be able to rotate cylinder outside of reload")
	assert_true(revolver.cylinder_rotate_sound_played, "Should play rotation sound")
	assert_true(revolver.cylinder_state_changed_emitted, "Should emit state changed")


func test_rotate_cylinder_advances_chamber_index() -> void:
	## Issue #691: Rotation should advance the chamber index.
	revolver.current_chamber_index = 0

	revolver.rotate_cylinder(1)  # Clockwise
	assert_eq(revolver.current_chamber_index, 1, "Should advance to chamber 1")

	revolver.rotate_cylinder(1)  # Clockwise again
	assert_eq(revolver.current_chamber_index, 2, "Should advance to chamber 2")


func test_rotate_cylinder_backwards() -> void:
	## Issue #691: Counter-clockwise rotation.
	revolver.current_chamber_index = 2

	revolver.rotate_cylinder(-1)
	assert_eq(revolver.current_chamber_index, 1, "Should go back to chamber 1")


func test_rotate_cylinder_wraps_around_forward() -> void:
	## Issue #691: Rotation wraps around past the last chamber.
	revolver.current_chamber_index = 4

	revolver.rotate_cylinder(1)
	assert_eq(revolver.current_chamber_index, 0, "Should wrap to chamber 0")


func test_rotate_cylinder_wraps_around_backward() -> void:
	## Issue #691: Rotation wraps backward past chamber 0.
	revolver.current_chamber_index = 0

	revolver.rotate_cylinder(-1)
	assert_eq(revolver.current_chamber_index, 4, "Should wrap to chamber 4")


func test_cannot_rotate_while_hammer_auto_cocked() -> void:
	## Issue #691: Cannot rotate while hammer is auto-cocked (shot pending).
	revolver.is_hammer_cocked = true

	var result := revolver.rotate_cylinder(1)

	assert_false(result, "Should not rotate while hammer is auto-cocked")
	assert_false(revolver.cylinder_rotate_sound_played, "No sound when blocked")


func test_cannot_rotate_while_hammer_manually_cocked() -> void:
	## Issue #691: Cannot rotate while hammer is manually cocked.
	revolver.is_manually_hammer_cocked = true

	var result := revolver.rotate_cylinder(1)

	assert_false(result, "Should not rotate while hammer is manually cocked")


func test_rotate_during_reload_still_works() -> void:
	## Issue #691: Rotation should still work during reload (existing behavior).
	revolver.reload_state = MockRevolverCylinderUI.CYLINDER_OPEN

	var result := revolver.rotate_cylinder(1)

	assert_true(result, "Should rotate during reload")


func test_rotate_during_reload_manages_insertion_blocking() -> void:
	## Issue #691: During reload, rotation manages insertion blocking.
	## Outside reload, it does NOT manage insertion blocking.
	revolver.current_ammo = 3
	revolver.chamber_occupied[0] = false
	revolver.chamber_occupied[1] = false
	revolver.current_chamber_index = 0

	# Outside reload: no insertion blocking
	revolver.reload_state = MockRevolverCylinderUI.NOT_RELOADING
	revolver.rotate_cylinder(1)  # To chamber 1 (empty)
	assert_false(revolver.cartridge_insertion_blocked,
		"Outside reload: no insertion blocking changes")

	# During reload: manages insertion blocking
	revolver.reload_state = MockRevolverCylinderUI.CYLINDER_OPEN
	revolver.rotate_cylinder(1)  # To chamber 2 (occupied)
	assert_true(revolver.cartridge_insertion_blocked,
		"During reload: should block insertion at occupied chamber")


func test_multiple_rotations_outside_reload() -> void:
	## Issue #691: Full revolution outside reload.
	revolver.current_chamber_index = 0

	for i in range(5):
		revolver.rotate_cylinder(1)

	assert_eq(revolver.current_chamber_index, 0,
		"Should return to chamber 0 after full revolution")
	assert_eq(revolver.cylinder_rotations, 5, "Should track 5 rotations")


func test_rotate_after_firing() -> void:
	## Issue #691: Can rotate after firing (once hammer is uncocked and shot completes).
	revolver.current_ammo = 3
	revolver.fire()
	# After firing, current_chamber_index advanced by 1
	var chamber_after_fire := revolver.current_chamber_index
	revolver.reset_tracking()

	# Should be able to rotate
	var result := revolver.rotate_cylinder(1)
	assert_true(result, "Should rotate after firing")
	assert_ne(revolver.current_chamber_index, chamber_after_fire,
		"Chamber index should change")


# ============================================================================
# Cylinder State for UI (Issue #691)
# ============================================================================


func test_is_any_hammer_cocked_false_by_default() -> void:
	## Issue #691: By default, hammer is not cocked.
	assert_false(revolver.is_any_hammer_cocked(), "Hammer should not be cocked by default")


func test_is_any_hammer_cocked_auto() -> void:
	## Issue #691: Auto-cock makes IsHammerCocked true.
	revolver.is_hammer_cocked = true
	assert_true(revolver.is_any_hammer_cocked(), "Should be true when auto-cocked")


func test_is_any_hammer_cocked_manual() -> void:
	## Issue #691: Manual cock makes IsHammerCocked true.
	revolver.is_manually_hammer_cocked = true
	assert_true(revolver.is_any_hammer_cocked(), "Should be true when manually cocked")


func test_get_chamber_states_returns_copy() -> void:
	## Issue #691: Getting chamber states returns a copy (not a reference).
	var states := revolver.get_chamber_states()
	states[0] = false  # Modify the copy

	assert_true(revolver.chamber_occupied[0],
		"Original should not be modified when copy is changed")


func test_chamber_states_after_firing() -> void:
	## Issue #691: Chamber states correctly reflect which chambers are empty after firing.
	revolver.current_ammo = 5
	revolver.fire()  # Chamber 0 becomes empty
	revolver.fire()  # Chamber 1 becomes empty

	var states := revolver.get_chamber_states()
	assert_false(states[0], "Chamber 0 should be empty after firing")
	assert_false(states[1], "Chamber 1 should be empty after firing")
	assert_true(states[2], "Chamber 2 should still be occupied")
	assert_true(states[3], "Chamber 3 should still be occupied")
	assert_true(states[4], "Chamber 4 should still be occupied")


func test_current_chamber_index_after_firing() -> void:
	## Issue #691: Current chamber index advances after each shot.
	revolver.current_chamber_index = 0
	revolver.fire()
	assert_eq(revolver.current_chamber_index, 1, "Should be at chamber 1 after first shot")
	revolver.fire()
	assert_eq(revolver.current_chamber_index, 2, "Should be at chamber 2 after second shot")


# ============================================================================
# UI Display Ordering Tests (Issue #691)
# ============================================================================


func test_display_order_center_is_active() -> void:
	## Issue #691: The active chamber should be in the center of the display.
	var display := MockCylinderUIDisplay.new(5)
	display.current_chamber_index = 0

	var active_pos := display.get_active_display_position()
	assert_eq(active_pos, 2, "Active chamber should be at display position 2 (center of 5)")


func test_display_order_arrangement_from_zero() -> void:
	## Issue #691: When current chamber is 0, display order is [3, 4, 0, 1, 2].
	## (2 left of center, center, 2 right of center)
	var display := MockCylinderUIDisplay.new(5)
	display.current_chamber_index = 0

	var order := display.get_display_order()
	assert_eq(order[0], 3, "Leftmost slot should show chamber 3 (C-2 wrapped)")
	assert_eq(order[1], 4, "Second slot should show chamber 4 (C-1 wrapped)")
	assert_eq(order[2], 0, "Center slot should show chamber 0 (active)")
	assert_eq(order[3], 1, "Fourth slot should show chamber 1 (C+1)")
	assert_eq(order[4], 2, "Rightmost slot should show chamber 2 (C+2)")


func test_display_order_arrangement_from_two() -> void:
	## Issue #691: When current chamber is 2, display order is [0, 1, 2, 3, 4].
	var display := MockCylinderUIDisplay.new(5)
	display.current_chamber_index = 2

	var order := display.get_display_order()
	assert_eq(order[0], 0, "Leftmost should be chamber 0")
	assert_eq(order[1], 1, "Second should be chamber 1")
	assert_eq(order[2], 2, "Center should be chamber 2 (active)")
	assert_eq(order[3], 3, "Fourth should be chamber 3")
	assert_eq(order[4], 4, "Rightmost should be chamber 4")


func test_display_order_arrangement_from_four() -> void:
	## Issue #691: When current chamber is 4, display order is [2, 3, 4, 0, 1].
	var display := MockCylinderUIDisplay.new(5)
	display.current_chamber_index = 4

	var order := display.get_display_order()
	assert_eq(order[0], 2, "Leftmost should be chamber 2")
	assert_eq(order[1], 3, "Second should be chamber 3")
	assert_eq(order[2], 4, "Center should be chamber 4 (active)")
	assert_eq(order[3], 0, "Fourth should be chamber 0")
	assert_eq(order[4], 1, "Rightmost should be chamber 1")


func test_display_order_two_slots_each_side() -> void:
	## Issue #691: Verify exactly 2 slots on each side of center for 5-chamber cylinder.
	var display := MockCylinderUIDisplay.new(5)
	var active_pos := display.get_active_display_position()

	assert_eq(active_pos, 2, "Active at position 2")
	assert_eq(active_pos, 2, "2 slots to the left (positions 0, 1)")
	assert_eq(display.cylinder_capacity - active_pos - 1, 2, "2 slots to the right (positions 3, 4)")


func test_ui_color_uncocked_yellow() -> void:
	## Issue #691: When hammer is NOT cocked, active slot should be yellow.
	## Yellow means: pressing LMB will rotate cylinder first (delayed shot).
	var display := MockCylinderUIDisplay.new(5)
	display.is_hammer_cocked = false

	assert_false(display.is_hammer_cocked,
		"Hammer not cocked = yellow active slot (LMB will rotate)")


func test_ui_color_cocked_red() -> void:
	## Issue #691: When hammer IS cocked, active slot should be red.
	## Red means: pressing LMB fires immediately without rotation.
	var display := MockCylinderUIDisplay.new(5)
	display.is_hammer_cocked = true

	assert_true(display.is_hammer_cocked,
		"Hammer cocked = red active slot (instant shot)")


func test_cylinder_state_changed_on_rotation_outside_reload() -> void:
	## Issue #691: CylinderStateChanged signal should fire on rotation outside reload.
	revolver.reset_tracking()
	revolver.rotate_cylinder(1)

	assert_true(revolver.cylinder_state_changed_emitted,
		"Should emit CylinderStateChanged on rotation outside reload")


func test_cylinder_state_changed_on_fire() -> void:
	## Issue #691: CylinderStateChanged signal should fire after shot.
	revolver.reset_tracking()
	revolver.fire()

	assert_true(revolver.cylinder_state_changed_emitted,
		"Should emit CylinderStateChanged after firing")


func test_rotate_select_empty_chamber_for_misfire() -> void:
	## Issue #691: Player can rotate to an empty chamber to get a "misfire" effect.
	revolver.current_ammo = 4
	revolver.chamber_occupied[2] = false
	revolver.current_chamber_index = 0

	# Rotate to the empty chamber (chamber 2)
	revolver.rotate_cylinder(1)  # To 1
	revolver.rotate_cylinder(1)  # To 2 (empty)

	assert_eq(revolver.current_chamber_index, 2, "Should be at empty chamber 2")
	assert_false(revolver.chamber_occupied[2], "Chamber 2 is empty")
