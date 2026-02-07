extends GutTest
## Unit tests for StatusEffectAnimationComponent (Issue #602).
##
## Tests the status effect animation visual indicators:
## - Stun: Orbiting stars (dizziness animation)
## - Blindness: X marks over eyes (eye covering animation)
## - Component state management (active/inactive, visibility)
## - Animation constants and drawing logic


# ============================================================================
# Mock StatusEffectAnimationComponent for Logic Tests
# ============================================================================


class MockStatusEffectAnimationComponent:
	## Number of orbiting stars for stun animation.
	const STAR_COUNT: int = 3
	## Orbit radius for stars (pixels from center).
	const STAR_ORBIT_RADIUS: float = 14.0
	## Star size (radius of each star circle).
	const STAR_SIZE: float = 2.5
	## Orbit speed (radians per second).
	const STAR_ORBIT_SPEED: float = 3.0
	## Star color (gold/yellow - classic stun indicator).
	const STAR_COLOR: Color = Color(1.0, 0.9, 0.2, 0.9)
	## Star highlight color (brighter center).
	const STAR_HIGHLIGHT_COLOR: Color = Color(1.0, 1.0, 0.6, 1.0)

	## Size of the X marks for blindness.
	const BLIND_X_SIZE: float = 3.5
	## Gap between two X marks (horizontal offset from center).
	const BLIND_X_SPACING: float = 4.0
	## Blindness X mark color.
	const BLIND_X_COLOR: Color = Color(1.0, 1.0, 0.7, 0.9)
	## Line width for X marks.
	const BLIND_X_WIDTH: float = 1.5
	## Pulse speed for blindness animation.
	const BLIND_PULSE_SPEED: float = 4.0

	## Vertical offset from parent origin to position effects near the head.
	var head_offset: Vector2 = Vector2(-6.0, -2.0)

	## Whether stun animation is active.
	var _is_stunned: bool = false
	## Whether blindness animation is active.
	var _is_blinded: bool = false
	## Animation time accumulator.
	var _anim_time: float = 0.0
	## Visibility state.
	var visible: bool = false

	## Track draw calls for testing.
	var stun_stars_drawn: int = 0
	var blind_x_marks_drawn: int = 0


	func set_stunned(stunned: bool) -> void:
		_is_stunned = stunned
		if not _is_stunned and not _is_blinded:
			visible = false
			_anim_time = 0.0

	func set_blinded(blinded: bool) -> void:
		_is_blinded = blinded
		if not _is_stunned and not _is_blinded:
			visible = false
			_anim_time = 0.0

	func is_active() -> bool:
		return _is_stunned or _is_blinded

	## Simulate process (animation update).
	func simulate_process(delta: float) -> void:
		if not _is_stunned and not _is_blinded:
			if visible:
				visible = false
			return

		_anim_time += delta
		visible = true

	## Simulate draw to check what would be drawn.
	func simulate_draw() -> void:
		stun_stars_drawn = 0
		blind_x_marks_drawn = 0

		if _is_stunned:
			_draw_stun_stars()
		if _is_blinded:
			_draw_blind_x_marks()

	func _draw_stun_stars() -> void:
		var center := head_offset + Vector2(0, -12.0)
		for i in range(STAR_COUNT):
			var angle_offset := (TAU / STAR_COUNT) * i
			var angle := _anim_time * STAR_ORBIT_SPEED + angle_offset
			var star_pos := center + Vector2(cos(angle), sin(angle)) * STAR_ORBIT_RADIUS
			stun_stars_drawn += 1

	func _draw_blind_x_marks() -> void:
		var center := head_offset
		for side in [-1.0, 1.0]:
			var _eye_center := center + Vector2(BLIND_X_SPACING * side, 0)
			blind_x_marks_drawn += 1

	## Get star positions at a given time for orbit testing.
	func get_star_positions(time: float) -> Array[Vector2]:
		var positions: Array[Vector2] = []
		var center := head_offset + Vector2(0, -12.0)
		for i in range(STAR_COUNT):
			var angle_offset := (TAU / STAR_COUNT) * i
			var angle := time * STAR_ORBIT_SPEED + angle_offset
			positions.append(center + Vector2(cos(angle), sin(angle)) * STAR_ORBIT_RADIUS)
		return positions

	## Get X mark eye positions for testing.
	func get_blind_x_positions() -> Array[Vector2]:
		var positions: Array[Vector2] = []
		var center := head_offset
		for side in [-1.0, 1.0]:
			positions.append(center + Vector2(BLIND_X_SPACING * side, 0))
		return positions

	## Calculate pulse alpha for blindness at a given time.
	func get_blind_pulse_alpha(time: float) -> float:
		return 0.7 + 0.3 * sin(time * BLIND_PULSE_SPEED)


var component: MockStatusEffectAnimationComponent


func before_each() -> void:
	component = MockStatusEffectAnimationComponent.new()


func after_each() -> void:
	component = null


# ============================================================================
# Initial State Tests
# ============================================================================


func test_not_stunned_initially() -> void:
	assert_false(component._is_stunned,
		"Should not be stunned initially")


func test_not_blinded_initially() -> void:
	assert_false(component._is_blinded,
		"Should not be blinded initially")


func test_not_visible_initially() -> void:
	assert_false(component.visible,
		"Should not be visible initially")


func test_not_active_initially() -> void:
	assert_false(component.is_active(),
		"Should not be active initially")


func test_anim_time_zero_initially() -> void:
	assert_eq(component._anim_time, 0.0,
		"Animation time should be zero initially")


# ============================================================================
# Constants Tests
# ============================================================================


func test_star_count_is_three() -> void:
	assert_eq(component.STAR_COUNT, 3,
		"Should have 3 orbiting stars")


func test_star_orbit_radius() -> void:
	assert_eq(component.STAR_ORBIT_RADIUS, 14.0,
		"Star orbit radius should be 14 pixels")


func test_star_orbit_speed() -> void:
	assert_eq(component.STAR_ORBIT_SPEED, 3.0,
		"Star orbit speed should be 3.0 radians/second")


func test_star_color_is_gold() -> void:
	assert_eq(component.STAR_COLOR, Color(1.0, 0.9, 0.2, 0.9),
		"Star color should be gold/yellow")


func test_star_highlight_color_is_bright() -> void:
	assert_true(component.STAR_HIGHLIGHT_COLOR.r >= 1.0,
		"Star highlight should be bright")


func test_blind_x_size() -> void:
	assert_eq(component.BLIND_X_SIZE, 3.5,
		"Blind X mark size should be 3.5")


func test_blind_x_spacing() -> void:
	assert_eq(component.BLIND_X_SPACING, 4.0,
		"Blind X spacing should be 4.0 for two eyes")


func test_blind_x_width() -> void:
	assert_eq(component.BLIND_X_WIDTH, 1.5,
		"Blind X line width should be 1.5")


func test_blind_pulse_speed() -> void:
	assert_eq(component.BLIND_PULSE_SPEED, 4.0,
		"Blind pulse speed should be 4.0 radians/second")


func test_default_head_offset() -> void:
	assert_eq(component.head_offset, Vector2(-6.0, -2.0),
		"Default head offset should match enemy head position")


# ============================================================================
# Set Stunned Tests
# ============================================================================


func test_set_stunned_true() -> void:
	component.set_stunned(true)

	assert_true(component._is_stunned,
		"Should be stunned after set_stunned(true)")


func test_set_stunned_false() -> void:
	component.set_stunned(true)
	component.set_stunned(false)

	assert_false(component._is_stunned,
		"Should not be stunned after set_stunned(false)")


func test_set_stunned_true_makes_active() -> void:
	component.set_stunned(true)

	assert_true(component.is_active(),
		"Should be active when stunned")


func test_set_stunned_false_hides_when_not_blinded() -> void:
	component.set_stunned(true)
	component.visible = true
	component.set_stunned(false)

	assert_false(component.visible,
		"Should hide when no effects are active")


func test_set_stunned_false_resets_anim_time() -> void:
	component.set_stunned(true)
	component._anim_time = 5.0
	component.set_stunned(false)

	assert_eq(component._anim_time, 0.0,
		"Should reset animation time when no effects active")


func test_set_stunned_false_stays_visible_if_blinded() -> void:
	component.set_blinded(true)
	component.set_stunned(true)
	component.visible = true
	component.set_stunned(false)

	assert_true(component.visible,
		"Should stay visible when still blinded")


# ============================================================================
# Set Blinded Tests
# ============================================================================


func test_set_blinded_true() -> void:
	component.set_blinded(true)

	assert_true(component._is_blinded,
		"Should be blinded after set_blinded(true)")


func test_set_blinded_false() -> void:
	component.set_blinded(true)
	component.set_blinded(false)

	assert_false(component._is_blinded,
		"Should not be blinded after set_blinded(false)")


func test_set_blinded_true_makes_active() -> void:
	component.set_blinded(true)

	assert_true(component.is_active(),
		"Should be active when blinded")


func test_set_blinded_false_hides_when_not_stunned() -> void:
	component.set_blinded(true)
	component.visible = true
	component.set_blinded(false)

	assert_false(component.visible,
		"Should hide when no effects are active")


func test_set_blinded_false_stays_visible_if_stunned() -> void:
	component.set_stunned(true)
	component.set_blinded(true)
	component.visible = true
	component.set_blinded(false)

	assert_true(component.visible,
		"Should stay visible when still stunned")


# ============================================================================
# Combined Effects Tests
# ============================================================================


func test_both_effects_active() -> void:
	component.set_stunned(true)
	component.set_blinded(true)

	assert_true(component._is_stunned)
	assert_true(component._is_blinded)
	assert_true(component.is_active())


func test_removing_one_effect_keeps_other_active() -> void:
	component.set_stunned(true)
	component.set_blinded(true)
	component.set_stunned(false)

	assert_false(component._is_stunned)
	assert_true(component._is_blinded)
	assert_true(component.is_active())


func test_removing_all_effects_deactivates() -> void:
	component.set_stunned(true)
	component.set_blinded(true)
	component.set_stunned(false)
	component.set_blinded(false)

	assert_false(component.is_active())


# ============================================================================
# Process / Animation Update Tests
# ============================================================================


func test_process_no_effects_stays_invisible() -> void:
	component.simulate_process(1.0)

	assert_false(component.visible,
		"Should stay invisible when no effects active")


func test_process_stunned_becomes_visible() -> void:
	component.set_stunned(true)
	component.simulate_process(0.1)

	assert_true(component.visible,
		"Should become visible when stunned")


func test_process_blinded_becomes_visible() -> void:
	component.set_blinded(true)
	component.simulate_process(0.1)

	assert_true(component.visible,
		"Should become visible when blinded")


func test_process_accumulates_anim_time() -> void:
	component.set_stunned(true)
	component.simulate_process(0.5)
	component.simulate_process(0.3)

	assert_almost_eq(component._anim_time, 0.8, 0.001,
		"Animation time should accumulate across frames")


func test_process_hides_when_effects_removed() -> void:
	component.set_stunned(true)
	component.simulate_process(0.1)
	assert_true(component.visible)

	component.set_stunned(false)
	component.simulate_process(0.1)

	assert_false(component.visible,
		"Should hide after effects removed")


# ============================================================================
# Star Drawing Tests (Stun)
# ============================================================================


func test_draw_stun_draws_correct_star_count() -> void:
	component.set_stunned(true)
	component.simulate_draw()

	assert_eq(component.stun_stars_drawn, 3,
		"Should draw exactly 3 stars")


func test_draw_stun_no_stars_when_not_stunned() -> void:
	component.simulate_draw()

	assert_eq(component.stun_stars_drawn, 0,
		"Should draw no stars when not stunned")


func test_star_positions_are_evenly_spaced() -> void:
	var positions := component.get_star_positions(0.0)

	assert_eq(positions.size(), 3,
		"Should have 3 star positions")

	# Stars should be evenly spaced (120 degrees apart)
	var angle_01 := (positions[1] - (component.head_offset + Vector2(0, -12))).angle()
	var angle_00 := (positions[0] - (component.head_offset + Vector2(0, -12))).angle()
	var expected_diff := TAU / 3.0
	var actual_diff := fmod(angle_01 - angle_00 + TAU, TAU)

	assert_almost_eq(actual_diff, expected_diff, 0.01,
		"Stars should be 120 degrees apart")


func test_star_positions_change_over_time() -> void:
	var positions_t0 := component.get_star_positions(0.0)
	var positions_t1 := component.get_star_positions(1.0)

	# At least one star should have moved
	var moved := false
	for i in range(3):
		if positions_t0[i].distance_to(positions_t1[i]) > 0.01:
			moved = true
			break

	assert_true(moved,
		"Star positions should change over time (orbit animation)")


func test_star_orbit_stays_within_radius() -> void:
	var center := component.head_offset + Vector2(0, -12.0)

	for t in [0.0, 0.5, 1.0, 2.0, 5.0]:
		var positions := component.get_star_positions(t)
		for pos in positions:
			var dist := pos.distance_to(center)
			assert_almost_eq(dist, component.STAR_ORBIT_RADIUS, 0.01,
				"Stars should orbit at exactly STAR_ORBIT_RADIUS distance")


# ============================================================================
# X Mark Drawing Tests (Blindness)
# ============================================================================


func test_draw_blind_draws_two_x_marks() -> void:
	component.set_blinded(true)
	component.simulate_draw()

	assert_eq(component.blind_x_marks_drawn, 2,
		"Should draw exactly 2 X marks (one per eye)")


func test_draw_blind_no_marks_when_not_blinded() -> void:
	component.simulate_draw()

	assert_eq(component.blind_x_marks_drawn, 0,
		"Should draw no X marks when not blinded")


func test_blind_x_positions_are_symmetric() -> void:
	var positions := component.get_blind_x_positions()

	assert_eq(positions.size(), 2,
		"Should have 2 eye positions")

	# Eyes should be symmetric around head center
	var center := component.head_offset
	var left_offset := positions[0].x - center.x
	var right_offset := positions[1].x - center.x

	assert_almost_eq(left_offset, -right_offset, 0.01,
		"Eye positions should be symmetric around head center")


func test_blind_x_positions_at_correct_y() -> void:
	var positions := component.get_blind_x_positions()

	for pos in positions:
		assert_eq(pos.y, component.head_offset.y,
			"X marks should be at head height")


func test_blind_pulse_alpha_oscillates() -> void:
	var alpha_0 := component.get_blind_pulse_alpha(0.0)
	var alpha_quarter := component.get_blind_pulse_alpha(PI / (2.0 * component.BLIND_PULSE_SPEED))

	assert_true(alpha_0 != alpha_quarter,
		"Pulse alpha should change over time")


func test_blind_pulse_alpha_within_range() -> void:
	# Test many time values to ensure alpha stays in valid range
	for i in range(100):
		var t := float(i) * 0.1
		var alpha := component.get_blind_pulse_alpha(t)
		assert_true(alpha >= 0.4 and alpha <= 1.0,
			"Pulse alpha at t=%.1f should be in range [0.4, 1.0], got %.3f" % [t, alpha])


# ============================================================================
# Combined Drawing Tests
# ============================================================================


func test_draw_both_effects_draws_stars_and_x_marks() -> void:
	component.set_stunned(true)
	component.set_blinded(true)
	component.simulate_draw()

	assert_eq(component.stun_stars_drawn, 3,
		"Should draw 3 stars when stunned")
	assert_eq(component.blind_x_marks_drawn, 2,
		"Should draw 2 X marks when blinded")


func test_draw_only_stun_no_x_marks() -> void:
	component.set_stunned(true)
	component.simulate_draw()

	assert_eq(component.stun_stars_drawn, 3)
	assert_eq(component.blind_x_marks_drawn, 0,
		"Should not draw X marks when only stunned")


func test_draw_only_blind_no_stars() -> void:
	component.set_blinded(true)
	component.simulate_draw()

	assert_eq(component.stun_stars_drawn, 0,
		"Should not draw stars when only blinded")
	assert_eq(component.blind_x_marks_drawn, 2)


# ============================================================================
# Head Offset Tests
# ============================================================================


func test_head_offset_configurable() -> void:
	component.head_offset = Vector2(10.0, -5.0)

	var star_positions := component.get_star_positions(0.0)
	var center := Vector2(10.0, -5.0) + Vector2(0, -12.0)

	for pos in star_positions:
		var dist := pos.distance_to(center)
		assert_almost_eq(dist, component.STAR_ORBIT_RADIUS, 0.01,
			"Stars should orbit around configured head offset")


func test_blind_x_follows_head_offset() -> void:
	component.head_offset = Vector2(5.0, -3.0)

	var positions := component.get_blind_x_positions()
	for pos in positions:
		assert_eq(pos.y, -3.0,
			"X marks should follow head offset Y position")


# ============================================================================
# Edge Cases Tests
# ============================================================================


func test_rapid_toggle_stun() -> void:
	component.set_stunned(true)
	component.set_stunned(false)
	component.set_stunned(true)
	component.set_stunned(false)

	assert_false(component.is_active(),
		"Should not be active after rapid toggle ending with false")
	assert_false(component.visible,
		"Should not be visible after rapid toggle ending with false")


func test_rapid_toggle_blind() -> void:
	component.set_blinded(true)
	component.set_blinded(false)
	component.set_blinded(true)
	component.set_blinded(false)

	assert_false(component.is_active())


func test_double_set_stunned_true() -> void:
	component.set_stunned(true)
	component.set_stunned(true)

	assert_true(component._is_stunned,
		"Double set_stunned(true) should still be stunned")


func test_double_set_blinded_true() -> void:
	component.set_blinded(true)
	component.set_blinded(true)

	assert_true(component._is_blinded,
		"Double set_blinded(true) should still be blinded")


func test_set_stunned_false_when_never_stunned() -> void:
	component.set_stunned(false)

	assert_false(component._is_stunned,
		"Should handle set_stunned(false) when never stunned")
	assert_false(component.visible)


func test_set_blinded_false_when_never_blinded() -> void:
	component.set_blinded(false)

	assert_false(component._is_blinded,
		"Should handle set_blinded(false) when never blinded")
	assert_false(component.visible)


func test_star_positions_at_large_time_values() -> void:
	# Test that orbiting works correctly even at very large time values
	var positions := component.get_star_positions(10000.0)
	var center := component.head_offset + Vector2(0, -12.0)

	for pos in positions:
		var dist := pos.distance_to(center)
		assert_almost_eq(dist, component.STAR_ORBIT_RADIUS, 0.01,
			"Stars should maintain orbit radius even at large time values")


func test_animation_time_accumulates_correctly_over_many_frames() -> void:
	component.set_stunned(true)

	var total := 0.0
	for i in range(100):
		component.simulate_process(0.016)  # ~60fps
		total += 0.016

	assert_almost_eq(component._anim_time, total, 0.01,
		"Animation time should accurately accumulate over many frames")
