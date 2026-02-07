extends GutTest
## Unit tests for blood_decal.gd and blood_footprint.gd effects.
##
## Tests blood decal fade timing, alpha calculations, group membership,
## puddle configuration, and blood footprint alpha/color/texture logic.


# ============================================================================
# Mock BloodDecal for Logic Tests
# ============================================================================


class MockBloodDecal:
	## Time in seconds before the decal starts fading.
	var fade_delay: float = 30.0

	## Time in seconds for the fade-out animation.
	var fade_duration: float = 5.0

	## Whether the decal should fade out over time.
	var auto_fade: bool = false

	## Whether this decal can be stepped in (creates bloody footprints).
	var is_puddle: bool = true

	## Initial alpha value.
	var _initial_alpha: float = 0.85

	## Current modulate values.
	var modulate_a: float = 0.85

	## Track if removed.
	var removed: bool = false

	## Track if fade timer started.
	var fade_timer_started: bool = false

	## Track if quick fade started.
	var quick_fade_started: bool = false

	## Groups the decal belongs to.
	var _groups: Array[String] = []

	## Whether puddle area was set up.
	var puddle_area_setup: bool = false

	## Simulated tween target alpha for fade timer.
	var _tween_target_alpha: float = -1.0

	## Simulated tween duration for fade timer.
	var _tween_duration: float = -1.0

	## Simulate _ready.
	func ready() -> void:
		_initial_alpha = modulate_a

		if is_puddle:
			_groups.append("blood_puddle")
			_setup_puddle_area()

		if auto_fade:
			_start_fade_timer()

	## Check group membership.
	func is_in_group(group_name: String) -> bool:
		return group_name in _groups

	## Setup the puddle detection area.
	func _setup_puddle_area() -> void:
		puddle_area_setup = true

	## Start the fade timer (simulates await + tween).
	func _start_fade_timer() -> void:
		fade_timer_started = true
		# Simulate what the real code does after delay:
		# tween to alpha 0.0 over fade_duration, then queue_free
		_tween_target_alpha = 0.0
		_tween_duration = fade_duration

	## Immediately removes the decal.
	func remove() -> void:
		removed = true

	## Fades out the decal quickly (0.5s).
	func fade_out_quick() -> void:
		quick_fade_started = true
		_tween_target_alpha = 0.0
		_tween_duration = 0.5

	## Simulate tween progress for fade-out.
	## Returns the interpolated alpha at a given progress (0.0 to 1.0).
	func get_alpha_at_fade_progress(progress: float) -> float:
		progress = clampf(progress, 0.0, 1.0)
		return lerpf(_initial_alpha, 0.0, progress)


# ============================================================================
# Mock BloodFootprint for Logic Tests
# ============================================================================


class MockBloodFootprint:
	## Initial alpha value (set by spawner based on step count).
	var _initial_alpha: float = 0.8

	## Blood color from the puddle (RGB, alpha is handled separately).
	var _blood_color: Color = Color(0.545, 0.0, 0.0, 1.0)

	## Current modulate values.
	var modulate: Color = Color(1.0, 1.0, 1.0, 1.0)

	## Z-index for rendering order.
	var z_index: int = 0

	## Current texture name (for tracking which foot).
	var texture_name: String = ""

	## Track if removed.
	var removed: bool = false

	## Simulate _ready.
	func ready() -> void:
		z_index = 1

	## Sets the footprint's alpha value.
	func set_alpha(alpha: float) -> void:
		_initial_alpha = alpha
		modulate.a = alpha

	## Sets the blood color from the puddle.
	func set_blood_color(puddle_color: Color) -> void:
		_blood_color = puddle_color
		modulate.r = puddle_color.r
		modulate.g = puddle_color.g
		modulate.b = puddle_color.b

	## Sets which foot this print is for.
	func set_foot(is_left: bool) -> void:
		if is_left:
			texture_name = "left"
		else:
			texture_name = "right"

	## Immediately removes the footprint.
	func remove() -> void:
		removed = true

	## Calculate the alpha for a footprint based on step count.
	## This mirrors the formula used by BloodyFeetComponent when spawning.
	## step_count: current step number (0-based), max_steps: total steps, alpha_min: minimum alpha.
	static func calculate_alpha(step_count: int, max_steps: int, alpha_min: float = 0.05) -> float:
		if max_steps <= 0:
			return alpha_min
		return lerpf(1.0, alpha_min, float(step_count) / float(max_steps))


var blood_decal: MockBloodDecal
var blood_footprint: MockBloodFootprint


func before_each() -> void:
	blood_decal = MockBloodDecal.new()
	blood_footprint = MockBloodFootprint.new()


func after_each() -> void:
	blood_decal = null
	blood_footprint = null


# ============================================================================
# BloodDecal Default Configuration Tests
# ============================================================================


func test_blood_decal_default_fade_delay() -> void:
	assert_eq(blood_decal.fade_delay, 30.0,
		"Blood decal default fade delay should be 30 seconds")


func test_blood_decal_default_fade_duration() -> void:
	assert_eq(blood_decal.fade_duration, 5.0,
		"Blood decal default fade duration should be 5 seconds")


func test_blood_decal_default_auto_fade_disabled() -> void:
	assert_false(blood_decal.auto_fade,
		"Blood decal auto_fade should be false by default")


func test_blood_decal_default_is_puddle() -> void:
	assert_true(blood_decal.is_puddle,
		"Blood decal is_puddle should be true by default")


func test_blood_decal_default_initial_alpha() -> void:
	assert_eq(blood_decal._initial_alpha, 0.85,
		"Blood decal default initial alpha should be 0.85")


# ============================================================================
# BloodDecal Ready / Initialization Tests
# ============================================================================


func test_blood_decal_ready_sets_initial_alpha_from_modulate() -> void:
	blood_decal.modulate_a = 0.7
	blood_decal.ready()

	assert_eq(blood_decal._initial_alpha, 0.7,
		"Initial alpha should be set from current modulate alpha on ready")


func test_blood_decal_ready_adds_to_blood_puddle_group_when_puddle() -> void:
	blood_decal.is_puddle = true
	blood_decal.ready()

	assert_true(blood_decal.is_in_group("blood_puddle"),
		"Blood decal should be in 'blood_puddle' group when is_puddle is true")


func test_blood_decal_ready_not_in_group_when_not_puddle() -> void:
	blood_decal.is_puddle = false
	blood_decal.ready()

	assert_false(blood_decal.is_in_group("blood_puddle"),
		"Blood decal should NOT be in 'blood_puddle' group when is_puddle is false")


func test_blood_decal_ready_sets_up_puddle_area_when_puddle() -> void:
	blood_decal.is_puddle = true
	blood_decal.ready()

	assert_true(blood_decal.puddle_area_setup,
		"Puddle area should be set up when is_puddle is true")


func test_blood_decal_ready_no_puddle_area_when_not_puddle() -> void:
	blood_decal.is_puddle = false
	blood_decal.ready()

	assert_false(blood_decal.puddle_area_setup,
		"Puddle area should NOT be set up when is_puddle is false")


func test_blood_decal_ready_starts_fade_when_auto_fade_true() -> void:
	blood_decal.auto_fade = true
	blood_decal.ready()

	assert_true(blood_decal.fade_timer_started,
		"Fade timer should start when auto_fade is true")


func test_blood_decal_ready_no_fade_when_auto_fade_false() -> void:
	blood_decal.auto_fade = false
	blood_decal.ready()

	assert_false(blood_decal.fade_timer_started,
		"Fade timer should NOT start when auto_fade is false")


# ============================================================================
# BloodDecal Fade Timing Tests
# ============================================================================


func test_blood_decal_fade_timer_targets_zero_alpha() -> void:
	blood_decal.auto_fade = true
	blood_decal.ready()

	assert_eq(blood_decal._tween_target_alpha, 0.0,
		"Fade timer tween should target alpha 0.0")


func test_blood_decal_fade_timer_uses_fade_duration() -> void:
	blood_decal.auto_fade = true
	blood_decal.fade_duration = 7.0
	blood_decal.ready()

	assert_eq(blood_decal._tween_duration, 7.0,
		"Fade timer tween should use the configured fade_duration")


func test_blood_decal_quick_fade_uses_half_second() -> void:
	blood_decal.fade_out_quick()

	assert_eq(blood_decal._tween_duration, 0.5,
		"Quick fade should use 0.5 second duration")


func test_blood_decal_quick_fade_targets_zero_alpha() -> void:
	blood_decal.fade_out_quick()

	assert_eq(blood_decal._tween_target_alpha, 0.0,
		"Quick fade should target alpha 0.0")


# ============================================================================
# BloodDecal Alpha Fade Progress Tests
# ============================================================================


func test_blood_decal_alpha_at_start_of_fade() -> void:
	blood_decal.ready()
	var alpha := blood_decal.get_alpha_at_fade_progress(0.0)

	assert_almost_eq(alpha, 0.85, 0.001,
		"Alpha at fade start should equal initial alpha (0.85)")


func test_blood_decal_alpha_at_midpoint_of_fade() -> void:
	blood_decal.ready()
	var alpha := blood_decal.get_alpha_at_fade_progress(0.5)

	assert_almost_eq(alpha, 0.425, 0.001,
		"Alpha at 50% fade should be 0.425 (midpoint of 0.85 to 0.0)")


func test_blood_decal_alpha_at_end_of_fade() -> void:
	blood_decal.ready()
	var alpha := blood_decal.get_alpha_at_fade_progress(1.0)

	assert_almost_eq(alpha, 0.0, 0.001,
		"Alpha at end of fade should be 0.0")


func test_blood_decal_alpha_at_quarter_fade() -> void:
	blood_decal.ready()
	var alpha := blood_decal.get_alpha_at_fade_progress(0.25)

	# lerpf(0.85, 0.0, 0.25) = 0.85 * 0.75 = 0.6375
	assert_almost_eq(alpha, 0.6375, 0.001,
		"Alpha at 25% fade should be 0.6375")


func test_blood_decal_alpha_at_three_quarter_fade() -> void:
	blood_decal.ready()
	var alpha := blood_decal.get_alpha_at_fade_progress(0.75)

	# lerpf(0.85, 0.0, 0.75) = 0.85 * 0.25 = 0.2125
	assert_almost_eq(alpha, 0.2125, 0.001,
		"Alpha at 75% fade should be 0.2125")


func test_blood_decal_alpha_clamped_below_zero_progress() -> void:
	blood_decal.ready()
	var alpha := blood_decal.get_alpha_at_fade_progress(-0.5)

	assert_almost_eq(alpha, 0.85, 0.001,
		"Alpha should clamp to initial value for negative progress")


func test_blood_decal_alpha_clamped_above_one_progress() -> void:
	blood_decal.ready()
	var alpha := blood_decal.get_alpha_at_fade_progress(2.0)

	assert_almost_eq(alpha, 0.0, 0.001,
		"Alpha should clamp to 0.0 for progress > 1.0")


func test_blood_decal_fade_progress_monotonically_decreasing() -> void:
	blood_decal.ready()

	var prev_alpha := blood_decal.get_alpha_at_fade_progress(0.0)
	for i in range(1, 11):
		var progress := float(i) / 10.0
		var alpha := blood_decal.get_alpha_at_fade_progress(progress)
		assert_true(alpha <= prev_alpha,
			"Alpha should monotonically decrease during fade (progress=%.1f)" % progress)
		prev_alpha = alpha


# ============================================================================
# BloodDecal Remove / Cleanup Tests
# ============================================================================


func test_blood_decal_remove() -> void:
	blood_decal.remove()

	assert_true(blood_decal.removed,
		"Blood decal should be marked as removed after remove()")


func test_blood_decal_quick_fade_sets_flag() -> void:
	blood_decal.fade_out_quick()

	assert_true(blood_decal.quick_fade_started,
		"Quick fade flag should be set")


# ============================================================================
# BloodDecal Custom Configuration Tests
# ============================================================================


func test_blood_decal_custom_fade_delay() -> void:
	blood_decal.fade_delay = 60.0
	blood_decal.auto_fade = true
	blood_decal.ready()

	assert_eq(blood_decal.fade_delay, 60.0,
		"Custom fade delay should be configurable")
	assert_true(blood_decal.fade_timer_started,
		"Fade timer should start with custom delay")


func test_blood_decal_custom_fade_duration() -> void:
	blood_decal.fade_duration = 15.0
	blood_decal.auto_fade = true
	blood_decal.ready()

	assert_eq(blood_decal._tween_duration, 15.0,
		"Tween duration should match custom fade_duration")


func test_blood_decal_custom_initial_alpha() -> void:
	blood_decal.modulate_a = 0.5
	blood_decal.ready()

	assert_eq(blood_decal._initial_alpha, 0.5,
		"Initial alpha should reflect custom modulate")


# ============================================================================
# BloodFootprint Default Configuration Tests
# ============================================================================


func test_blood_footprint_default_initial_alpha() -> void:
	assert_eq(blood_footprint._initial_alpha, 0.8,
		"Blood footprint default initial alpha should be 0.8")


func test_blood_footprint_default_blood_color() -> void:
	assert_almost_eq(blood_footprint._blood_color.r, 0.545, 0.001,
		"Default blood color red component should be 0.545")
	assert_almost_eq(blood_footprint._blood_color.g, 0.0, 0.001,
		"Default blood color green component should be 0.0")
	assert_almost_eq(blood_footprint._blood_color.b, 0.0, 0.001,
		"Default blood color blue component should be 0.0")


func test_blood_footprint_default_z_index() -> void:
	assert_eq(blood_footprint.z_index, 0,
		"Z-index should be 0 before _ready")


# ============================================================================
# BloodFootprint Ready Tests
# ============================================================================


func test_blood_footprint_ready_sets_z_index() -> void:
	blood_footprint.ready()

	assert_eq(blood_footprint.z_index, 1,
		"Z-index should be set to 1 after _ready (above floor, below characters)")


# ============================================================================
# BloodFootprint Alpha Tests
# ============================================================================


func test_blood_footprint_set_alpha() -> void:
	blood_footprint.set_alpha(0.6)

	assert_eq(blood_footprint._initial_alpha, 0.6,
		"set_alpha should update _initial_alpha")
	assert_almost_eq(blood_footprint.modulate.a, 0.6, 0.001,
		"set_alpha should update modulate.a")


func test_blood_footprint_set_alpha_full_opacity() -> void:
	blood_footprint.set_alpha(1.0)

	assert_almost_eq(blood_footprint.modulate.a, 1.0, 0.001,
		"Full opacity alpha should be 1.0")


func test_blood_footprint_set_alpha_near_zero() -> void:
	blood_footprint.set_alpha(0.05)

	assert_almost_eq(blood_footprint.modulate.a, 0.05, 0.001,
		"Near-zero alpha should be preserved")


func test_blood_footprint_set_alpha_zero() -> void:
	blood_footprint.set_alpha(0.0)

	assert_almost_eq(blood_footprint.modulate.a, 0.0, 0.001,
		"Zero alpha should be handled")


# ============================================================================
# BloodFootprint Alpha Calculation Formula Tests
# ============================================================================


func test_footprint_alpha_first_step() -> void:
	# step_count=0, max_steps=20, alpha_min=0.05
	# lerpf(1.0, 0.05, 0/20) = lerpf(1.0, 0.05, 0.0) = 1.0
	var alpha := MockBloodFootprint.calculate_alpha(0, 20, 0.05)

	assert_almost_eq(alpha, 1.0, 0.001,
		"First step (step_count=0) should have alpha 1.0")


func test_footprint_alpha_last_step() -> void:
	# step_count=20, max_steps=20, alpha_min=0.05
	# lerpf(1.0, 0.05, 20/20) = lerpf(1.0, 0.05, 1.0) = 0.05
	var alpha := MockBloodFootprint.calculate_alpha(20, 20, 0.05)

	assert_almost_eq(alpha, 0.05, 0.001,
		"Last step (step_count=max_steps) should have alpha equal to alpha_min")


func test_footprint_alpha_midpoint() -> void:
	# step_count=10, max_steps=20, alpha_min=0.05
	# lerpf(1.0, 0.05, 10/20) = lerpf(1.0, 0.05, 0.5) = 0.525
	var alpha := MockBloodFootprint.calculate_alpha(10, 20, 0.05)

	assert_almost_eq(alpha, 0.525, 0.001,
		"Midpoint step should have alpha 0.525")


func test_footprint_alpha_quarter() -> void:
	# step_count=5, max_steps=20, alpha_min=0.05
	# lerpf(1.0, 0.05, 5/20) = lerpf(1.0, 0.05, 0.25) = 0.7625
	var alpha := MockBloodFootprint.calculate_alpha(5, 20, 0.05)

	assert_almost_eq(alpha, 0.7625, 0.001,
		"Quarter step should have alpha 0.7625")


func test_footprint_alpha_three_quarters() -> void:
	# step_count=15, max_steps=20, alpha_min=0.05
	# lerpf(1.0, 0.05, 15/20) = lerpf(1.0, 0.05, 0.75) = 0.2875
	var alpha := MockBloodFootprint.calculate_alpha(15, 20, 0.05)

	assert_almost_eq(alpha, 0.2875, 0.001,
		"Three-quarter step should have alpha 0.2875")


func test_footprint_alpha_decreases_monotonically() -> void:
	var max_steps := 20
	var prev_alpha := MockBloodFootprint.calculate_alpha(0, max_steps, 0.05)

	for step in range(1, max_steps + 1):
		var alpha := MockBloodFootprint.calculate_alpha(step, max_steps, 0.05)
		assert_true(alpha <= prev_alpha,
			"Alpha should monotonically decrease (step=%d)" % step)
		prev_alpha = alpha


func test_footprint_alpha_with_different_max_steps() -> void:
	# With max_steps=10, step_count=5 (midpoint)
	# lerpf(1.0, 0.05, 5/10) = lerpf(1.0, 0.05, 0.5) = 0.525
	var alpha := MockBloodFootprint.calculate_alpha(5, 10, 0.05)

	assert_almost_eq(alpha, 0.525, 0.001,
		"Alpha calculation should work with different max_steps")


func test_footprint_alpha_with_different_alpha_min() -> void:
	# With alpha_min=0.1, step_count=20, max_steps=20
	# lerpf(1.0, 0.1, 1.0) = 0.1
	var alpha := MockBloodFootprint.calculate_alpha(20, 20, 0.1)

	assert_almost_eq(alpha, 0.1, 0.001,
		"Alpha calculation should respect custom alpha_min")


func test_footprint_alpha_beyond_max_steps() -> void:
	# step_count=25, max_steps=20 -> ratio = 25/20 = 1.25
	# lerpf(1.0, 0.05, 1.25) = 1.0 + 1.25*(0.05-1.0) = 1.0 - 1.1875 = -0.1875
	# NOTE: This can go below alpha_min if step_count > max_steps (no clamping in formula)
	var alpha := MockBloodFootprint.calculate_alpha(25, 20, 0.05)

	assert_true(alpha < 0.05,
		"Alpha beyond max_steps may go below alpha_min (no explicit clamp)")


func test_footprint_alpha_zero_max_steps() -> void:
	# Should return alpha_min to avoid division by zero
	var alpha := MockBloodFootprint.calculate_alpha(5, 0, 0.05)

	assert_almost_eq(alpha, 0.05, 0.001,
		"Zero max_steps should return alpha_min (safe fallback)")


# ============================================================================
# BloodFootprint Color Tests
# ============================================================================


func test_blood_footprint_set_blood_color() -> void:
	var puddle_color := Color(0.8, 0.1, 0.1, 1.0)
	blood_footprint.set_blood_color(puddle_color)

	assert_almost_eq(blood_footprint.modulate.r, 0.8, 0.001,
		"Modulate red should match puddle color")
	assert_almost_eq(blood_footprint.modulate.g, 0.1, 0.001,
		"Modulate green should match puddle color")
	assert_almost_eq(blood_footprint.modulate.b, 0.1, 0.001,
		"Modulate blue should match puddle color")


func test_blood_footprint_color_preserves_alpha() -> void:
	blood_footprint.set_alpha(0.6)
	blood_footprint.set_blood_color(Color(0.5, 0.0, 0.0, 1.0))

	# Alpha should remain as set by set_alpha, not overwritten by set_blood_color
	assert_almost_eq(blood_footprint.modulate.a, 0.6, 0.001,
		"set_blood_color should not overwrite alpha set by set_alpha")


func test_blood_footprint_stores_blood_color() -> void:
	var puddle_color := Color(0.7, 0.05, 0.05, 1.0)
	blood_footprint.set_blood_color(puddle_color)

	assert_almost_eq(blood_footprint._blood_color.r, 0.7, 0.001,
		"Stored blood color red should match")
	assert_almost_eq(blood_footprint._blood_color.g, 0.05, 0.001,
		"Stored blood color green should match")
	assert_almost_eq(blood_footprint._blood_color.b, 0.05, 0.001,
		"Stored blood color blue should match")


# ============================================================================
# BloodFootprint Foot Texture Tests
# ============================================================================


func test_blood_footprint_set_left_foot() -> void:
	blood_footprint.set_foot(true)

	assert_eq(blood_footprint.texture_name, "left",
		"Left foot should set left texture")


func test_blood_footprint_set_right_foot() -> void:
	blood_footprint.set_foot(false)

	assert_eq(blood_footprint.texture_name, "right",
		"Right foot should set right texture")


# ============================================================================
# BloodFootprint Remove Tests
# ============================================================================


func test_blood_footprint_remove() -> void:
	blood_footprint.remove()

	assert_true(blood_footprint.removed,
		"Blood footprint should be marked as removed after remove()")


# ============================================================================
# Cross-Effect Comparison Tests
# ============================================================================


func test_decal_initial_alpha_higher_than_footprint_default() -> void:
	# Blood decal: 0.85, Blood footprint: 0.8
	assert_gt(blood_decal._initial_alpha, blood_footprint._initial_alpha,
		"Blood decal initial alpha (0.85) should be higher than footprint (0.8)")


func test_decal_auto_fade_default_differs_from_manual_fade() -> void:
	# auto_fade is false by default, but manual fade/remove always works
	assert_false(blood_decal.auto_fade,
		"Auto fade defaults to false (decals persist by default)")

	blood_decal.remove()
	assert_true(blood_decal.removed,
		"Manual removal should always work regardless of auto_fade setting")


# ============================================================================
# Edge Case Tests
# ============================================================================


func test_blood_decal_zero_fade_delay() -> void:
	blood_decal.fade_delay = 0.0
	blood_decal.auto_fade = true
	blood_decal.ready()

	assert_true(blood_decal.fade_timer_started,
		"Zero fade delay should still start the fade timer")


func test_blood_decal_zero_fade_duration() -> void:
	blood_decal.fade_duration = 0.0
	blood_decal.auto_fade = true
	blood_decal.ready()

	assert_eq(blood_decal._tween_duration, 0.0,
		"Zero fade duration should be passed to tween")


func test_blood_decal_very_large_fade_delay() -> void:
	blood_decal.fade_delay = 999999.0
	blood_decal.auto_fade = true
	blood_decal.ready()

	assert_true(blood_decal.fade_timer_started,
		"Very large fade delay should still start the fade timer")


func test_blood_decal_alpha_values_in_valid_range() -> void:
	assert_gte(blood_decal._initial_alpha, 0.0,
		"Initial alpha should be >= 0.0")
	assert_lte(blood_decal._initial_alpha, 1.0,
		"Initial alpha should be <= 1.0")


func test_blood_footprint_alpha_values_in_valid_range() -> void:
	assert_gte(blood_footprint._initial_alpha, 0.0,
		"Initial alpha should be >= 0.0")
	assert_lte(blood_footprint._initial_alpha, 1.0,
		"Initial alpha should be <= 1.0")


func test_blood_footprint_alpha_formula_all_steps_positive_within_max() -> void:
	var max_steps := 20
	var alpha_min := 0.05

	for step in range(max_steps + 1):
		var alpha := MockBloodFootprint.calculate_alpha(step, max_steps, alpha_min)
		assert_gte(alpha, alpha_min,
			"Alpha at step %d should be >= alpha_min (%.2f)" % [step, alpha_min])


func test_blood_footprint_set_alpha_multiple_times() -> void:
	blood_footprint.set_alpha(0.9)
	assert_almost_eq(blood_footprint.modulate.a, 0.9, 0.001)

	blood_footprint.set_alpha(0.5)
	assert_almost_eq(blood_footprint.modulate.a, 0.5, 0.001)

	blood_footprint.set_alpha(0.1)
	assert_almost_eq(blood_footprint.modulate.a, 0.1, 0.001,
		"Multiple set_alpha calls should each update the modulate")


func test_blood_decal_both_puddle_and_auto_fade() -> void:
	blood_decal.is_puddle = true
	blood_decal.auto_fade = true
	blood_decal.ready()

	assert_true(blood_decal.is_in_group("blood_puddle"),
		"Should be in blood_puddle group")
	assert_true(blood_decal.puddle_area_setup,
		"Puddle area should be set up")
	assert_true(blood_decal.fade_timer_started,
		"Fade timer should be started")


func test_blood_decal_neither_puddle_nor_auto_fade() -> void:
	blood_decal.is_puddle = false
	blood_decal.auto_fade = false
	blood_decal.ready()

	assert_false(blood_decal.is_in_group("blood_puddle"),
		"Should NOT be in blood_puddle group")
	assert_false(blood_decal.puddle_area_setup,
		"Puddle area should NOT be set up")
	assert_false(blood_decal.fade_timer_started,
		"Fade timer should NOT be started")
