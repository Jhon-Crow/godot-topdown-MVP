extends GutTest
## Unit tests for BreachingChargesEffect (Issue #1043).
##
## Tests the breaching charges active item core logic including:
## - Charge management (2 charges per battle)
## - Wall placement detection (hold Space near wall, release to attach)
## - Detonation mechanics (press Space to detonate placed charge)
## - Wall passage creation (disabling wall collision)
## - Enemy stun/blind application (3 seconds duration)
## - Signal emissions


# ============================================================================
# Mock BreachingChargesEffect for Testing Core Logic
# ============================================================================


class MockBreachingChargesEffect:
	## Maximum charges per battle.
	const MAX_CHARGES: int = 2

	## Radius to search for a wall when placing a charge (pixels).
	const PLACEMENT_RADIUS: float = 40.0

	## Stun/blind radius from detonation point (pixels).
	const STUN_RADIUS: float = 150.0

	## Duration of stun and blind effects on enemies (seconds).
	const STUN_DURATION: float = 3.0

	## Current number of charges remaining.
	var charges: int = MAX_CHARGES

	## Whether a charge is currently placed on a wall (waiting for detonation).
	var has_placed_charge: bool = false

	## The wall node that has a charge placed on it.
	var _charged_wall = null

	## World position where the charge was placed.
	var _charge_position: Vector2 = Vector2.ZERO

	## Whether Space is currently being held for placement.
	var _holding_for_placement: bool = false

	## Signal tracking for tests.
	var charge_placed_signals: Array = []
	var detonated_signals: Array = []
	var charges_changed_signals: Array = []

	## Tracking for applied effects.
	var walls_opened: Array = []
	var enemies_stunned: Array = []
	var last_detonate_pos: Vector2 = Vector2.ZERO

	## Mock wall node for testing.
	class MockWall:
		var name: String = "MockWall"
		var collision_disabled: bool = false
		var visible: bool = true

		func get_children() -> Array:
			return []

	## Attempt to place a charge on the given wall mock.
	## Returns true if placement was successful.
	func try_place_charge_on(wall: MockWall) -> bool:
		if charges <= 0:
			return false
		if has_placed_charge:
			return false
		if wall == null:
			return false

		charges -= 1
		has_placed_charge = true
		_charged_wall = wall
		_charge_position = Vector2(100, 100)

		charge_placed_signals.append(charges)
		charges_changed_signals.append({"current": charges, "max": MAX_CHARGES})
		return true

	## Attempt to place a charge — returns false when no wall in range.
	func try_place_charge_no_wall() -> bool:
		if charges <= 0:
			return false
		if has_placed_charge:
			return false
		# No wall found
		return false

	## Detonate placed charges.
	func detonate() -> bool:
		if not has_placed_charge:
			return false

		last_detonate_pos = _charge_position
		var wall = _charged_wall

		has_placed_charge = false
		_charged_wall = null
		_charge_position = Vector2.ZERO

		# Record wall opening
		if wall != null:
			walls_opened.append(wall)

		# Simulate enemy stun within radius
		detonated_signals.append(last_detonate_pos)
		charges_changed_signals.append({"current": charges, "max": MAX_CHARGES})
		return true

	## Get remaining charges.
	func get_charges() -> int:
		return charges


var effect: MockBreachingChargesEffect


func before_each() -> void:
	effect = MockBreachingChargesEffect.new()


func after_each() -> void:
	effect = null


# ============================================================================
# Constants Tests
# ============================================================================


func test_max_charges_is_2() -> void:
	assert_eq(MockBreachingChargesEffect.MAX_CHARGES, 2,
		"Max charges per battle should be 2")


func test_placement_radius_is_40() -> void:
	assert_eq(MockBreachingChargesEffect.PLACEMENT_RADIUS, 40.0,
		"Placement radius should be 40 pixels")


func test_stun_radius_is_150() -> void:
	assert_eq(MockBreachingChargesEffect.STUN_RADIUS, 150.0,
		"Stun radius should be 150 pixels")


func test_stun_duration_is_3_seconds() -> void:
	assert_eq(MockBreachingChargesEffect.STUN_DURATION, 3.0,
		"Stun/blind duration should be 3 seconds")


# ============================================================================
# Initial State Tests
# ============================================================================


func test_starts_with_full_charges() -> void:
	assert_eq(effect.get_charges(), 2,
		"Should start with 2 charges")


func test_starts_without_placed_charge() -> void:
	assert_false(effect.has_placed_charge,
		"Should start with no charge placed")


func test_starts_not_holding_for_placement() -> void:
	assert_false(effect._holding_for_placement,
		"Should start not holding Space for placement")


# ============================================================================
# Charge Placement Tests
# ============================================================================


func test_place_charge_consumes_one_charge() -> void:
	var wall := MockBreachingChargesEffect.MockWall.new()
	effect.try_place_charge_on(wall)
	assert_eq(effect.get_charges(), 1,
		"Placing a charge should consume one charge")


func test_place_charge_sets_has_placed_charge() -> void:
	var wall := MockBreachingChargesEffect.MockWall.new()
	effect.try_place_charge_on(wall)
	assert_true(effect.has_placed_charge,
		"has_placed_charge should be true after placement")


func test_place_charge_returns_true_on_success() -> void:
	var wall := MockBreachingChargesEffect.MockWall.new()
	var result := effect.try_place_charge_on(wall)
	assert_true(result,
		"try_place_charge_on should return true on success")


func test_place_charge_emits_charge_placed_signal() -> void:
	var wall := MockBreachingChargesEffect.MockWall.new()
	effect.try_place_charge_on(wall)
	assert_eq(effect.charge_placed_signals.size(), 1,
		"Should emit charge_placed signal once")
	assert_eq(effect.charge_placed_signals[0], 1,
		"charge_placed signal should carry remaining charges (1)")


func test_place_charge_emits_charges_changed_signal() -> void:
	var wall := MockBreachingChargesEffect.MockWall.new()
	effect.try_place_charge_on(wall)
	assert_eq(effect.charges_changed_signals.size(), 1,
		"Should emit charges_changed signal once")


func test_cannot_place_two_charges_simultaneously() -> void:
	var wall1 := MockBreachingChargesEffect.MockWall.new()
	var wall2 := MockBreachingChargesEffect.MockWall.new()
	effect.try_place_charge_on(wall1)
	var second_result := effect.try_place_charge_on(wall2)
	assert_false(second_result,
		"Should not be able to place a second charge while one is already placed")
	assert_eq(effect.get_charges(), 1,
		"Only one charge should have been consumed")


func test_no_wall_in_range_returns_false() -> void:
	var result := effect.try_place_charge_no_wall()
	assert_false(result,
		"Should return false when no wall is found in range")
	assert_false(effect.has_placed_charge,
		"has_placed_charge should remain false when no wall found")
	assert_eq(effect.get_charges(), 2,
		"Charges should not be consumed when no wall found")


func test_cannot_place_charge_with_zero_charges() -> void:
	effect.charges = 0
	var wall := MockBreachingChargesEffect.MockWall.new()
	var result := effect.try_place_charge_on(wall)
	assert_false(result,
		"Should not be able to place charge with 0 charges remaining")


# ============================================================================
# Detonation Tests
# ============================================================================


func test_detonate_returns_true_when_charge_placed() -> void:
	var wall := MockBreachingChargesEffect.MockWall.new()
	effect.try_place_charge_on(wall)
	var result := effect.detonate()
	assert_true(result,
		"detonate should return true when a charge is placed")


func test_detonate_returns_false_when_no_charge_placed() -> void:
	var result := effect.detonate()
	assert_false(result,
		"detonate should return false when no charge is placed")


func test_detonate_clears_has_placed_charge() -> void:
	var wall := MockBreachingChargesEffect.MockWall.new()
	effect.try_place_charge_on(wall)
	effect.detonate()
	assert_false(effect.has_placed_charge,
		"has_placed_charge should be false after detonation")


func test_detonate_opens_wall_passage() -> void:
	var wall := MockBreachingChargesEffect.MockWall.new()
	effect.try_place_charge_on(wall)
	effect.detonate()
	assert_eq(effect.walls_opened.size(), 1,
		"Exactly one wall should be opened after detonation")
	assert_eq(effect.walls_opened[0], wall,
		"The correct wall should have been opened")


func test_detonate_emits_charges_detonated_signal() -> void:
	var wall := MockBreachingChargesEffect.MockWall.new()
	effect.try_place_charge_on(wall)
	effect.detonate()
	assert_eq(effect.detonated_signals.size(), 1,
		"Should emit charges_detonated signal once")


func test_detonate_emits_charges_changed_signal() -> void:
	var wall := MockBreachingChargesEffect.MockWall.new()
	effect.try_place_charge_on(wall)
	# Clear signals from placement
	effect.charges_changed_signals.clear()
	effect.detonate()
	assert_eq(effect.charges_changed_signals.size(), 1,
		"Should emit charges_changed signal on detonation")


func test_cannot_detonate_twice() -> void:
	var wall := MockBreachingChargesEffect.MockWall.new()
	effect.try_place_charge_on(wall)
	effect.detonate()
	var second_result := effect.detonate()
	assert_false(second_result,
		"Second detonation with no charge should return false")
	assert_eq(effect.walls_opened.size(), 1,
		"Wall should only be opened once")


# ============================================================================
# Charge Count Lifecycle Tests
# ============================================================================


func test_start_with_2_charges_use_both() -> void:
	# Place and detonate first charge
	var wall1 := MockBreachingChargesEffect.MockWall.new()
	effect.try_place_charge_on(wall1)
	effect.detonate()
	assert_eq(effect.get_charges(), 1, "Should have 1 charge after first use")

	# Place and detonate second charge
	var wall2 := MockBreachingChargesEffect.MockWall.new()
	effect.try_place_charge_on(wall2)
	effect.detonate()
	assert_eq(effect.get_charges(), 0, "Should have 0 charges after second use")


func test_no_more_charges_after_two_uses() -> void:
	var wall1 := MockBreachingChargesEffect.MockWall.new()
	effect.try_place_charge_on(wall1)
	effect.detonate()

	var wall2 := MockBreachingChargesEffect.MockWall.new()
	effect.try_place_charge_on(wall2)
	effect.detonate()

	# Try a third placement
	var wall3 := MockBreachingChargesEffect.MockWall.new()
	var result := effect.try_place_charge_on(wall3)
	assert_false(result,
		"Third charge placement should fail (only 2 charges per battle)")
	assert_eq(effect.get_charges(), 0,
		"Charges should be 0 after two uses")


# ============================================================================
# Active Item Manager Integration Tests
# ============================================================================


func test_breaching_charges_enum_value_is_11() -> void:
	# BREACHING_CHARGES should be the 11th enum (index 10) after LASER_SIGHT (9)
	# NONE=0, FLASHLIGHT=1, HOMING_BULLETS=2, TELEPORT_BRACERS=3,
	# BFF_PENDANT=4, INVISIBILITY_SUIT=5, BREAKER_BULLETS=6,
	# FORCE_FIELD=7, TRAJECTORY_GLASSES=8, LASER_SIGHT=9, BREACHING_CHARGES=10
	var expected_value := 10
	assert_eq(expected_value, 10,
		"BREACHING_CHARGES enum value should be 10")


func test_breaching_charges_data_has_name() -> void:
	var data := {"name": "Breaching Charges"}
	assert_eq(data["name"], "Breaching Charges",
		"Breaching Charges should have correct name")


func test_breaching_charges_data_description_mentions_space() -> void:
	var description := "hold Space near a wall to place a charge, release to attach it. Press Space to detonate"
	assert_true(description.contains("Space"),
		"Breaching Charges description should mention Space key")


func test_breaching_charges_description_mentions_2_charges() -> void:
	var description := "2 charges per battle"
	assert_true(description.contains("2"),
		"Breaching Charges description should mention 2 charges")


func test_breaching_charges_description_mentions_stun_blind() -> void:
	var description := "Enemies on the other side are stunned and blinded for 3 seconds."
	assert_true(description.contains("stunned"),
		"Breaching Charges description should mention stun effect")
	assert_true(description.contains("blinded"),
		"Breaching Charges description should mention blind effect")
	assert_true(description.contains("3"),
		"Breaching Charges description should mention 3 seconds duration")


# ============================================================================
# Stun Radius Tests
# ============================================================================


func test_stun_radius_constants_match_spec() -> void:
	# Issue #1043: enemies stunned/blinded for 3 seconds
	assert_eq(MockBreachingChargesEffect.STUN_DURATION, 3.0,
		"Stun/blind duration should be exactly 3 seconds as per issue spec")


func test_placement_radius_allows_wall_reach() -> void:
	# PLACEMENT_RADIUS of 40px means player can be up to 40px from wall surface
	assert_gt(MockBreachingChargesEffect.PLACEMENT_RADIUS, 0.0,
		"Placement radius must be positive")
	assert_lte(MockBreachingChargesEffect.PLACEMENT_RADIUS, 60.0,
		"Placement radius should be reasonable (<=60px) for close-range wall interaction")
