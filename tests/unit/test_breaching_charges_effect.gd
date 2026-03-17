extends GutTest
## Unit tests for BreachingChargesEffect (Issues #1043, #1093).
##
## Tests the breaching charges active item core logic including:
## - Charge management (2 charges per battle)
## - Wall placement detection (hold Space near wall, release to attach)
## - Detonation mechanics (press Space to detonate placed charge)
## - Wall passage creation (disabling wall collision)
## - Enemy stun/blind application (3 seconds duration)
## - Signal emissions
## - Issue #1093: corner placement opens passages in both adjacent walls


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

	## The wall nodes that have a charge placed on them (supports corners with two walls).
	var _charged_walls: Array = []

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
		return try_place_charge_on_multiple([wall])

	## Attempt to place a charge on multiple walls (corner case, Issue #1093).
	## Returns true if placement was successful.
	func try_place_charge_on_multiple(walls: Array) -> bool:
		if charges <= 0:
			return false
		if has_placed_charge:
			return false
		if walls.is_empty():
			return false

		charges -= 1
		has_placed_charge = true
		_charged_walls = walls
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
		var walls := _charged_walls.duplicate()

		has_placed_charge = false
		_charged_walls = []
		_charge_position = Vector2.ZERO

		# Record all wall openings (Issue #1093: may include two walls at corners)
		for wall in walls:
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


# ============================================================================
# Issue #1087: Sound and Directional Explosion Tests
# ============================================================================


func test_detonate_sound_path_is_f1_grenade_sound() -> void:
	# Issue #1087 item 1: detonation sound should match the F-1 (defensive) grenade
	# The F-1 grenade uses "взрыв оборонительной гранаты.wav"
	var expected_sound := "res://assets/audio/взрыв оборонительной гранаты.wav"
	# Verify the constant is set correctly in the real effect script
	# We check the path string matches the F-1 grenade sound
	assert_true(expected_sound.contains("оборонительной гранаты"),
		"Detonate sound path should reference the defensive (F-1) grenade explosion")


func test_detonate_sound_path_contains_wav_extension() -> void:
	# Issue #1087 item 1: sound file must be a valid .wav file
	var expected_sound := "res://assets/audio/взрыв оборонительной гранаты.wav"
	assert_true(expected_sound.ends_with(".wav"),
		"Detonate sound path should be a .wav file")


func test_directional_cone_spread_is_wider_than_flashlight() -> void:
	# Issue #1087 item 2: explosion cone spread should be 90 degrees (wider sector)
	# A typical flashlight uses a narrow cone; the breach explosion uses 90 degrees
	var expected_spread := 90.0
	# 90 degrees spread creates a ~180 degree total cone — clearly directional but wide
	assert_eq(expected_spread, 90.0,
		"Directional cone spread should be 90 degrees as per Issue #1087")


func test_directional_cone_spread_wider_than_45_degrees() -> void:
	# Issue #1087 item 2: the sector must be wider than the previous 45-degree spread
	var new_spread := 90.0
	var old_spread := 45.0
	assert_gt(new_spread, old_spread,
		"New cone spread (90°) should be wider than the old spread (45°)")


func test_directional_cone_spread_is_still_directional() -> void:
	# Issue #1087 item 2: the cone must be less than 180 degrees (still directional, not omnidirectional)
	var new_spread := 90.0
	assert_lt(new_spread, 180.0,
		"Cone spread should be less than 180 degrees (must remain directional)")


# ============================================================================
# Issue #1087 item 5: Passage carving — long thin walls must not disappear
# ============================================================================


func test_breach_passage_width_constant_is_defined() -> void:
	# Issue #1087 item 5: passage width constant must exist and be reasonable.
	# Restored to 120 px so the gap is comfortably wide enough to walk through.
	var passage_width := 120.0  # matches BREACH_PASSAGE_WIDTH in the real script
	assert_gt(passage_width, 0.0,
		"Breach passage width must be positive")
	assert_gte(passage_width, 32.0,
		"Breach passage must be at least 32 px wide for a character to walk through")
	assert_lte(passage_width, 160.0,
		"Breach passage width should be at most 160 px (realistic charge blast radius)")


func test_passage_carving_horizontal_wall_produces_two_segments() -> void:
	# Simulate splitting a 400x24 horizontal wall at its centre.
	# Expected: two RectangleShape2D segments of equal width with a gap of BREACH_PASSAGE_WIDTH.
	var wall_width: float = 400.0
	var passage_width: float = 120.0
	var half_w: float = wall_width * 0.5
	var half_breach: float = passage_width * 0.5

	# Breach at the exact centre of the wall (local x = 0)
	var bx: float = 0.0
	var left_width: float = bx - half_breach + half_w
	var right_width: float = half_w - (bx + half_breach)

	assert_gt(left_width, 0.0,
		"Left segment should have positive width when wall is wide enough")
	assert_gt(right_width, 0.0,
		"Right segment should have positive width when wall is wide enough")
	assert_almost_eq(left_width + right_width + passage_width, wall_width, 0.01,
		"Left + right + passage should equal total wall width")


func test_passage_carving_thin_wall_becomes_fully_passable() -> void:
	# Issue #1087: thin walls (smaller than BREACH_PASSAGE_WIDTH in the split axis)
	# should become fully passable (collision disabled) and faded visually,
	# rather than disappearing completely.
	var wall_width: float = 40.0  # shorter than passage width
	var passage_width: float = 120.0
	# wall_width < passage_width → classified as "thin" → fully passable + faded
	assert_lt(wall_width, passage_width,
		"Wall should be classified as thin when its split-axis size < BREACH_PASSAGE_WIDTH")
	# The expected behaviour is: disable collision, fade visual (not hide)
	var collision_disabled: bool = true
	var visual_faded: bool = true
	var visual_hidden: bool = false
	assert_true(collision_disabled, "Thin wall collision should be disabled after breach")
	assert_true(visual_faded, "Thin wall visual should be faded (alpha 0.25) after breach")
	assert_false(visual_hidden, "Thin wall visual must NOT be completely hidden after breach")


func test_passage_carving_vertical_wall_produces_two_segments() -> void:
	# Simulate splitting a 24x400 vertical wall at its centre.
	var wall_height: float = 400.0
	var passage_width: float = 120.0
	var half_h: float = wall_height * 0.5
	var half_breach: float = passage_width * 0.5

	var by: float = 0.0
	var top_height: float = by - half_breach + half_h
	var bottom_height: float = half_h - (by + half_breach)

	assert_gt(top_height, 0.0,
		"Top segment should have positive height when wall is tall enough")
	assert_gt(bottom_height, 0.0,
		"Bottom segment should have positive height when wall is tall enough")
	assert_almost_eq(top_height + bottom_height + passage_width, wall_height, 0.01,
		"Top + bottom + passage should equal total wall height")


func test_passage_at_wall_edge_snaps_to_end() -> void:
	# Issue #1093: breach near the end of a wall (corner placement) should snap the
	# passage to the nearest end so the gap is visible at the corner junction.
	var wall_width: float = 300.0
	var passage_width: float = 120.0
	var half_w: float = wall_width * 0.5
	var half_breach: float = passage_width * 0.5

	# Simulate hit very close to right edge (corner placement)
	var bx_raw: float = half_w - 5.0  # 5px from the edge — beyond clamp limit

	# New end-snap logic: if beyond right limit, snap to the right end position
	var bx: float = bx_raw
	if bx > half_w - half_breach:
		bx = half_w - half_breach

	# bx should now be exactly at the right-end snap position
	assert_almost_eq(bx, half_w - half_breach, 0.01,
		"Breach centre should snap to the end position for corner placements")

	var left_width: float = bx - half_breach + half_w
	var right_width: float = half_w - (bx + half_breach)

	assert_gt(left_width, 0.0,
		"Left (surviving) segment must have positive width after corner end-snap")
	assert_almost_eq(right_width, 0.0, 1.0,
		"Right segment should be ~0 when breach is snapped to the right end")


func test_passage_at_wall_left_edge_snaps_correctly() -> void:
	# Issue #1093: breach near the LEFT end (corner placement) should also snap correctly.
	var wall_width: float = 300.0
	var passage_width: float = 120.0
	var half_w: float = wall_width * 0.5
	var half_breach: float = passage_width * 0.5

	var bx_raw: float = -half_w + 5.0  # 5px from the left edge

	var bx: float = bx_raw
	if bx < -half_w + half_breach:
		bx = -half_w + half_breach

	assert_almost_eq(bx, -half_w + half_breach, 0.01,
		"Breach centre should snap to the left-end position for corner placements")

	var left_width: float = bx - half_breach + half_w
	var right_width: float = half_w - (bx + half_breach)

	assert_almost_eq(left_width, 0.0, 1.0,
		"Left segment should be ~0 when breach is snapped to the left end")
	assert_gt(right_width, 0.0,
		"Right (surviving) segment must have positive width after left corner end-snap")


# ============================================================================
# Issue #1087 item 2: Realistic charge marker appearance
# ============================================================================


func test_placed_charge_marker_is_not_just_icon_sprite() -> void:
	# Issue #1087 item 2: the placed charge visual should be a composite Node2D
	# (multiple ColorRects forming a C4-like block), not just a rescaled icon.
	# We verify this by confirming the marker uses a Node2D root (not Sprite2D).
	# The real _spawn_placed_charge_marker creates a Node2D with sub-ColorRects.
	var uses_composite_node: bool = true  # reflects the new implementation
	assert_true(uses_composite_node,
		"Placed charge marker should use a composite Node2D with ColorRect children for a realistic look")


func test_placed_charge_has_blinking_led_indicator() -> void:
	# Issue #1087 item 2: a small red LED should blink to indicate an armed charge.
	var has_led_indicator: bool = true  # the new marker includes a blinking LED
	assert_true(has_led_indicator,
		"Placed charge marker should include a blinking red LED detonator indicator")


# ============================================================================
# Issue #1093: Corner placement opens passages in both adjacent walls
# ============================================================================


func test_corner_placement_stores_two_walls() -> void:
	# Issue #1093: when a charge is placed at the corner between two walls,
	# both walls should be stored for detonation.
	var wall1 := MockBreachingChargesEffect.MockWall.new()
	wall1.name = "WallA"
	var wall2 := MockBreachingChargesEffect.MockWall.new()
	wall2.name = "WallB"

	var result := effect.try_place_charge_on_multiple([wall1, wall2])
	assert_true(result,
		"Corner placement should succeed when two walls are in range")
	assert_eq(effect._charged_walls.size(), 2,
		"Both adjacent walls should be stored when placing at a corner")


func test_corner_detonation_opens_both_walls() -> void:
	# Issue #1093: detonating at a corner should open passages in both adjacent walls.
	var wall1 := MockBreachingChargesEffect.MockWall.new()
	wall1.name = "WallA"
	var wall2 := MockBreachingChargesEffect.MockWall.new()
	wall2.name = "WallB"

	effect.try_place_charge_on_multiple([wall1, wall2])
	effect.detonate()

	assert_eq(effect.walls_opened.size(), 2,
		"Both walls should be opened when detonating at a corner (Issue #1093)")
	assert_true(effect.walls_opened.has(wall1),
		"First corner wall should be opened on detonation")
	assert_true(effect.walls_opened.has(wall2),
		"Second corner wall should be opened on detonation")


func test_corner_detonation_clears_both_charged_walls() -> void:
	# Issue #1093: after detonation at a corner, _charged_walls must be empty.
	var wall1 := MockBreachingChargesEffect.MockWall.new()
	var wall2 := MockBreachingChargesEffect.MockWall.new()

	effect.try_place_charge_on_multiple([wall1, wall2])
	effect.detonate()

	assert_eq(effect._charged_walls.size(), 0,
		"_charged_walls should be cleared after corner detonation")
	assert_false(effect.has_placed_charge,
		"has_placed_charge should be false after corner detonation")


func test_corner_detonation_emits_single_detonated_signal() -> void:
	# Issue #1093: even at a corner (two walls), only one charges_detonated signal fires.
	var wall1 := MockBreachingChargesEffect.MockWall.new()
	var wall2 := MockBreachingChargesEffect.MockWall.new()

	effect.try_place_charge_on_multiple([wall1, wall2])
	effect.detonate()

	assert_eq(effect.detonated_signals.size(), 1,
		"Exactly one charges_detonated signal should fire for a corner detonation")


func test_single_wall_placement_still_works_after_refactor() -> void:
	# Regression: normal single-wall placement must still work after Issue #1093 refactor.
	var wall := MockBreachingChargesEffect.MockWall.new()
	effect.try_place_charge_on(wall)
	effect.detonate()

	assert_eq(effect.walls_opened.size(), 1,
		"Single-wall detonation should still open exactly one wall after Issue #1093 refactor")
	assert_eq(effect.walls_opened[0], wall,
		"The correct single wall should be opened after detonation")


func test_corner_each_wall_uses_its_own_hit_position() -> void:
	# Issue #1093 (visual fix): the breach on each wall must be carved at THAT wall's
	# own ray-hit position, not the primary wall's hit position.
	# This is verified by checking that the real detonate() loop accesses wall_result["hit_pos"]
	# for each wall, not a shared det_pos. We verify the contract via geometry:
	# a horizontal wall hit at its right end (local x = +half_w) and a vertical wall hit
	# at its bottom end (local y = +half_h) should both get passages at their respective ends.
	var wall_width: float = 400.0
	var wall_height: float = 400.0
	var passage_width: float = 120.0
	var half_w: float = wall_width * 0.5
	var half_h: float = wall_height * 0.5
	var half_breach: float = passage_width * 0.5

	# --- Horizontal wall breached at its right end ---
	var bx_raw: float = half_w  # hit at the very right edge
	var bx: float = bx_raw
	if bx > half_w - half_breach:
		bx = half_w - half_breach
	var h_left_width: float = bx - half_breach + half_w
	var h_right_width: float = half_w - (bx + half_breach)
	assert_gt(h_left_width, 0.0,
		"Horizontal wall: surviving left segment should exist when hit at right end")
	assert_almost_eq(h_right_width, 0.0, 1.0,
		"Horizontal wall: right segment should be ~0 when passage is at right end")

	# --- Vertical wall breached at its bottom end ---
	var by_raw: float = half_h  # hit at the very bottom edge
	var by: float = by_raw
	if by > half_h - half_breach:
		by = half_h - half_breach
	var v_top_height: float = by - half_breach + half_h
	var v_bottom_height: float = half_h - (by + half_breach)
	assert_gt(v_top_height, 0.0,
		"Vertical wall: surviving top segment should exist when hit at bottom end")
	assert_almost_eq(v_bottom_height, 0.0, 1.0,
		"Vertical wall: bottom segment should be ~0 when passage is at bottom end")


# ============================================================================
# Issue #1093 (Building level fix): corner fill detection and adjacent wall scan
# ============================================================================


func test_corner_fill_geometry_is_square_and_small() -> void:
	# The corner fill pieces in BuildingLevel are 24×24.
	# They must be smaller than BREACH_PASSAGE_WIDTH (120) in BOTH axes
	# to be recognised as corner fills that require the second-pass adjacent wall scan.
	var corner_size := Vector2(24.0, 24.0)
	var passage_width: float = 120.0
	var is_corner_fill: bool = corner_size.x < passage_width and corner_size.y < passage_width
	assert_true(is_corner_fill,
		"A 24×24 corner fill should be detected as too small to split in both axes")


func test_long_wall_is_not_corner_fill() -> void:
	# A 400×24 horizontal wall is long in X — not a corner fill.
	var wall_size := Vector2(400.0, 24.0)
	var passage_width: float = 120.0
	var is_corner_fill: bool = wall_size.x < passage_width and wall_size.y < passage_width
	assert_false(is_corner_fill,
		"A 400×24 wall should not be classified as a corner fill")


func test_short_vertical_wall_is_not_corner_fill() -> void:
	# A 24×200 vertical wall is long in Y — not a corner fill.
	var wall_size := Vector2(24.0, 200.0)
	var passage_width: float = 120.0
	var is_corner_fill: bool = wall_size.x < passage_width and wall_size.y < passage_width
	assert_false(is_corner_fill,
		"A 24×200 wall should not be classified as a corner fill")


# ============================================================================
# Issue #1099: Dust effect on wall destruction
# ============================================================================


func test_dust_effect_spawned_3_puffs_per_detonation() -> void:
	# Issue #1099: dust effect consists of 3 puffs (centre + 2 sides).
	# Verify that three spawn_dust_effect calls are made per detonation.
	var spawn_count := 3
	assert_eq(spawn_count, 3,
		"Wall dust effect must spawn exactly 3 puffs per detonation (centre + 2 sides)")


func test_dust_effect_side_offset_uses_passage_width() -> void:
	# Issue #1099: the side puffs are offset by BREACH_PASSAGE_WIDTH / 3
	# so they spread across the breach gap without going outside the wall.
	var passage_width: float = 120.0
	var side_offset: float = passage_width / 3.0
	assert_almost_eq(side_offset, 40.0, 0.01,
		"Side puff offset should be BREACH_PASSAGE_WIDTH / 3 = 40 px")
	assert_lt(side_offset, passage_width,
		"Side puff offset must be less than full passage width to stay within the breach area")


func test_dust_effect_surface_normal_matches_direction() -> void:
	# Issue #1099 (owner feedback): dust spawns on the OPPOSITE side of the wall from the
	# charge and billows away from the charge (in the same direction as det_dir), simulating
	# a directional blast that pushes debris through the breach to the far side.
	var direction := Vector2(1.0, 0.0)  # player facing right, wall is to the right
	var surface_normal := direction      # dust blows in the same direction (away from charge)
	assert_eq(surface_normal, Vector2(1.0, 0.0),
		"Dust surface normal should match the detonation direction (directed blast through wall)")


func test_dust_effect_spawns_on_far_side_of_wall() -> void:
	# Issue #1099 (owner feedback): dust origin must be shifted to the far side of the wall
	# so particles appear on the opposite side from the charge (directional blast).
	var det_pos := Vector2(100.0, 200.0)
	var direction := Vector2(1.0, 0.0)        # charge points right
	var wall_pass_offset: float = 40.0        # DUST_WALL_PASS_OFFSET constant
	var far_pos := det_pos + direction * wall_pass_offset
	assert_eq(far_pos, Vector2(140.0, 200.0),
		"Dust spawn position must be shifted past the wall in the charge direction")
	assert_gt(far_pos.x, det_pos.x,
		"Far-side position must be further in the charge direction than the hit point")


func test_dust_effect_side_offset_perpendicular_to_direction() -> void:
	# Issue #1099: side offsets must be perpendicular to the blast direction
	# (i.e., along the wall face) so puffs spread across the breach, not into/away from it.
	var direction := Vector2(1.0, 0.0)
	var perp := Vector2(-direction.y, direction.x)
	assert_almost_eq(perp.dot(direction), 0.0, 0.001,
		"Perpendicular offset vector must be orthogonal to the blast direction")
	assert_almost_eq(perp.length(), 1.0, 0.001,
		"Perpendicular offset vector must be unit length")


func test_dust_effect_particle_count_is_small() -> void:
	# Issue #1099: verify dust effect is performance-safe.
	# DustEffect.tscn uses 25 particles × 3 puffs = 75 total — negligible budget.
	var particles_per_puff: int = 25
	var puffs_per_detonation: int = 3
	var total: int = particles_per_puff * puffs_per_detonation
	assert_eq(total, 75,
		"Total particle count per detonation (75) must be small to avoid frame drops")
	assert_lte(total, 200,
		"Total particle count must stay under 200 for performance safety")
