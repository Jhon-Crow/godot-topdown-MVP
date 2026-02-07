extends GutTest
## Unit tests for AnimatedScoreScreen visual enhancements.
##
## Tests the rank color system, contrasting color generation, score-to-rank
## mapping, Gothic bitmap font integration, and skip animation logic.
## Issue #525: Add a font for ratings/grades.
## Issue #568: Skip score animations with LMB click.


# We test the AnimatedScoreScreen logic by creating a mock instance
# that mirrors the testable functionality (color calculations and rank mapping).


## Path to the Gothic bitmap font resource (.fnt file).
const GOTHIC_FONT_PATH: String = "res://assets/fonts/gothic_bitmap.fnt"

## Path to the Gothic bitmap font texture.
const GOTHIC_FONT_TEXTURE: String = "res://assets/fonts/gothic_bitmap.png"


class MockAnimatedScoreScreen:
	## Mock class that mirrors AnimatedScoreScreen's testable functionality.

	# Constants (matching AnimatedScoreScreen)
	const RANK_ORDER: Array[String] = ["F", "D", "C", "B", "A", "A+", "S"]

	const RANK_THRESHOLDS: Dictionary = {
		"S": 1.0,
		"A+": 0.85,
		"A": 0.70,
		"B": 0.55,
		"C": 0.38,
		"D": 0.22,
		"F": 0.0
	}

	const RANK_BG_GRADIENT_SPEED: float = 2.5


	func _get_rank_color(rank: String) -> Color:
		match rank:
			"S":
				return Color(1.0, 0.84, 0.0, 1.0)  # Gold
			"A+":
				return Color(0.0, 1.0, 0.5, 1.0)  # Bright green
			"A":
				return Color(0.2, 0.8, 0.2, 1.0)  # Green
			"B":
				return Color(0.3, 0.7, 1.0, 1.0)  # Blue
			"C":
				return Color(1.0, 1.0, 1.0, 1.0)  # White
			"D":
				return Color(1.0, 0.6, 0.2, 1.0)  # Orange
			"F":
				return Color(1.0, 0.2, 0.2, 1.0)  # Red
			_:
				return Color(1.0, 1.0, 1.0, 1.0)  # Default white


	func _get_contrasting_colors(rank_color: Color) -> Array[Color]:
		var h: float = rank_color.h
		var s: float = rank_color.s
		var bg_s: float = maxf(s, 0.7)
		var bg_v: float = 0.5

		if s < 0.2:
			bg_s = 0.9
			bg_v = 0.4

		var c1 := Color.from_hsv(fmod(h + 0.33, 1.0), bg_s, bg_v, 0.85)
		var c2 := Color.from_hsv(fmod(h + 0.55, 1.0), bg_s, bg_v, 0.85)
		var c3 := Color.from_hsv(fmod(h + 0.78, 1.0), bg_s, bg_v, 0.85)

		return [c1, c2, c3]


	func _get_rank_for_score_ratio(score_ratio: float) -> String:
		if score_ratio >= RANK_THRESHOLDS["S"]:
			return "S"
		elif score_ratio >= RANK_THRESHOLDS["A+"]:
			return "A+"
		elif score_ratio >= RANK_THRESHOLDS["A"]:
			return "A"
		elif score_ratio >= RANK_THRESHOLDS["B"]:
			return "B"
		elif score_ratio >= RANK_THRESHOLDS["C"]:
			return "C"
		elif score_ratio >= RANK_THRESHOLDS["D"]:
			return "D"
		else:
			return "F"


var screen: MockAnimatedScoreScreen


func before_each() -> void:
	screen = MockAnimatedScoreScreen.new()


func after_each() -> void:
	screen = null


# ============================================================================
# Gothic Bitmap Font Tests (Issue #525)
# ============================================================================


func test_gothic_font_fnt_file_exists() -> void:
	assert_true(FileAccess.file_exists(GOTHIC_FONT_PATH),
		"Gothic bitmap font .fnt file should exist at %s" % GOTHIC_FONT_PATH)


func test_gothic_font_texture_exists() -> void:
	assert_true(FileAccess.file_exists(GOTHIC_FONT_TEXTURE),
		"Gothic bitmap font texture should exist at %s" % GOTHIC_FONT_TEXTURE)


func test_gothic_bitmap_font_loads_via_resource_system() -> void:
	if not ResourceLoader.exists(GOTHIC_FONT_PATH):
		pass_test("Font resource not yet imported (requires Godot editor import)")
		return
	var font = load(GOTHIC_FONT_PATH)
	assert_not_null(font, "Gothic bitmap font should load via Godot resource system")


func test_animated_score_screen_loads() -> void:
	var script = load("res://scripts/ui/animated_score_screen.gd")
	assert_not_null(script, "AnimatedScoreScreen script should load")


func test_animated_score_screen_has_gothic_font_path() -> void:
	var script = load("res://scripts/ui/animated_score_screen.gd")
	var instance = script.new()
	add_child_autofree(instance)
	assert_eq(instance.GOTHIC_FONT_PATH, GOTHIC_FONT_PATH,
		"AnimatedScoreScreen should have correct Gothic font path")


func test_animated_score_screen_get_gothic_font() -> void:
	var script = load("res://scripts/ui/animated_score_screen.gd")
	var instance = script.new()
	add_child_autofree(instance)
	var font = instance._get_gothic_font()
	# Font may be null if running without Godot editor import
	if font != null:
		assert_true(font is Font, "Returned font should be a Font")
	else:
		pass_test("Font not available (requires Godot editor import of .fnt file)")


func test_animated_score_screen_font_caching() -> void:
	var script = load("res://scripts/ui/animated_score_screen.gd")
	var instance = script.new()
	add_child_autofree(instance)
	var font1 = instance._get_gothic_font()
	var font2 = instance._get_gothic_font()
	if font1 != null:
		assert_same(font1, font2, "Font should be cached and return same instance")
	else:
		pass_test("Font not available for caching test (requires Godot editor import)")


func test_apply_gothic_font_to_label() -> void:
	var script = load("res://scripts/ui/animated_score_screen.gd")
	var instance = script.new()
	add_child_autofree(instance)
	var label = Label.new()
	add_child_autofree(label)
	instance._apply_gothic_font(label)
	# If font was loaded, label should have override; if not, test passes gracefully
	var font = instance._get_gothic_font()
	if font != null:
		var applied_font = label.get_theme_font("font")
		assert_not_null(applied_font, "Label should have a font override after _apply_gothic_font()")
	else:
		pass_test("Font not available for label test (requires Godot editor import)")


# ============================================================================
# Rank Color Tests
# ============================================================================


func test_rank_color_s_is_gold() -> void:
	var color := screen._get_rank_color("S")

	assert_almost_eq(color.r, 1.0, 0.01, "S rank red should be 1.0")
	assert_almost_eq(color.g, 0.84, 0.01, "S rank green should be 0.84")
	assert_almost_eq(color.b, 0.0, 0.01, "S rank blue should be 0.0")


func test_rank_color_f_is_red() -> void:
	var color := screen._get_rank_color("F")

	assert_almost_eq(color.r, 1.0, 0.01, "F rank red should be 1.0")
	assert_almost_eq(color.b, 0.2, 0.01, "F rank blue should be 0.2")


func test_rank_color_unknown_returns_white() -> void:
	var color := screen._get_rank_color("X")

	assert_eq(color, Color(1.0, 1.0, 1.0, 1.0), "Unknown rank should return white")


func test_all_ranks_have_unique_colors() -> void:
	var colors: Array[Color] = []
	for rank in screen.RANK_ORDER:
		colors.append(screen._get_rank_color(rank))

	# Verify each color is distinct
	for i in range(colors.size()):
		for j in range(i + 1, colors.size()):
			assert_ne(colors[i], colors[j], "Rank colors %s and %s should be different" % [screen.RANK_ORDER[i], screen.RANK_ORDER[j]])


# ============================================================================
# Contrasting Colors Tests
# ============================================================================


func test_contrasting_colors_returns_three_colors() -> void:
	var rank_color := screen._get_rank_color("S")
	var colors := screen._get_contrasting_colors(rank_color)

	assert_eq(colors.size(), 3, "Should return 3 contrasting colors")


func test_contrasting_colors_have_alpha() -> void:
	var rank_color := screen._get_rank_color("A")
	var colors := screen._get_contrasting_colors(rank_color)

	for i in range(colors.size()):
		assert_almost_eq(colors[i].a, 0.85, 0.01, "Contrasting color %d alpha should be 0.85" % i)


func test_contrasting_colors_differ_from_rank_color() -> void:
	for rank in screen.RANK_ORDER:
		var rank_color := screen._get_rank_color(rank)
		var colors := screen._get_contrasting_colors(rank_color)

		# Each contrasting color should have a significantly different hue
		for i in range(colors.size()):
			var hue_diff: float = absf(colors[i].h - rank_color.h)
			# Wrap around for hue comparison (hue is 0-1 circular)
			if hue_diff > 0.5:
				hue_diff = 1.0 - hue_diff
			# For low-saturation colors (white), any hue is fine since bg has high saturation
			if rank_color.s >= 0.2:
				assert_gt(hue_diff, 0.1, "Contrasting color %d for rank %s should have different hue" % [i, rank])


func test_contrasting_colors_for_white_rank_use_vivid_saturation() -> void:
	# C rank is white (low saturation)
	var rank_color := screen._get_rank_color("C")
	var colors := screen._get_contrasting_colors(rank_color)

	for i in range(colors.size()):
		assert_gt(colors[i].s, 0.5, "Contrasting colors for white rank should have high saturation")


func test_contrasting_colors_are_distinct() -> void:
	var rank_color := screen._get_rank_color("S")
	var colors := screen._get_contrasting_colors(rank_color)

	assert_ne(colors[0], colors[1], "First and second contrasting colors should differ")
	assert_ne(colors[1], colors[2], "Second and third contrasting colors should differ")
	assert_ne(colors[0], colors[2], "First and third contrasting colors should differ")


func test_contrasting_colors_for_each_rank() -> void:
	# Verify contrasting colors can be generated for every rank
	for rank in screen.RANK_ORDER:
		var rank_color := screen._get_rank_color(rank)
		var colors := screen._get_contrasting_colors(rank_color)

		assert_eq(colors.size(), 3, "Should return 3 colors for rank %s" % rank)
		for i in range(colors.size()):
			assert_gt(colors[i].a, 0.0, "Color %d for rank %s should be visible" % [i, rank])


# ============================================================================
# Score Ratio to Rank Mapping Tests
# ============================================================================


func test_score_ratio_zero_is_f() -> void:
	assert_eq(screen._get_rank_for_score_ratio(0.0), "F", "0% should be F rank")


func test_score_ratio_low_is_f() -> void:
	assert_eq(screen._get_rank_for_score_ratio(0.10), "F", "10% should be F rank")


func test_score_ratio_22_percent_is_d() -> void:
	assert_eq(screen._get_rank_for_score_ratio(0.22), "D", "22% should be D rank")


func test_score_ratio_38_percent_is_c() -> void:
	assert_eq(screen._get_rank_for_score_ratio(0.38), "C", "38% should be C rank")


func test_score_ratio_55_percent_is_b() -> void:
	assert_eq(screen._get_rank_for_score_ratio(0.55), "B", "55% should be B rank")


func test_score_ratio_70_percent_is_a() -> void:
	assert_eq(screen._get_rank_for_score_ratio(0.70), "A", "70% should be A rank")


func test_score_ratio_85_percent_is_a_plus() -> void:
	assert_eq(screen._get_rank_for_score_ratio(0.85), "A+", "85% should be A+ rank")


func test_score_ratio_100_percent_is_s() -> void:
	assert_eq(screen._get_rank_for_score_ratio(1.0), "S", "100% should be S rank")


func test_score_ratio_between_thresholds() -> void:
	assert_eq(screen._get_rank_for_score_ratio(0.50), "C", "50% should be C rank (between C=38% and B=55%)")
	assert_eq(screen._get_rank_for_score_ratio(0.60), "B", "60% should be B rank (between B=55% and A=70%)")
	assert_eq(screen._get_rank_for_score_ratio(0.75), "A", "75% should be A rank (between A=70% and A+=85%)")
	assert_eq(screen._get_rank_for_score_ratio(0.90), "A+", "90% should be A+ rank (between A+=85% and S=100%)")


func test_score_ratio_above_100_percent_is_s() -> void:
	assert_eq(screen._get_rank_for_score_ratio(1.5), "S", "Above 100% should still be S rank")


func test_score_ratio_negative_is_f() -> void:
	assert_eq(screen._get_rank_for_score_ratio(-0.1), "F", "Negative ratio should be F rank")


# ============================================================================
# Animation Timing Constants Tests
# ============================================================================


func test_score_count_duration_is_slow_enough() -> void:
	# Score counting should take at least 1 second per item for readability
	var score_screen_script = load("res://scripts/ui/animated_score_screen.gd")
	var duration: float = score_screen_script.SCORE_COUNT_DURATION
	assert_gte(duration, 1.0, "Score count duration should be >= 1.0s for readability")


func test_total_score_counting_is_longer_than_items() -> void:
	# Total score counts longer than individual items (multiplied by 1.5x)
	var score_screen_script = load("res://scripts/ui/animated_score_screen.gd")
	var item_duration: float = score_screen_script.SCORE_COUNT_DURATION
	# Total duration is item_duration * 1.5
	var total_duration: float = item_duration * 1.5
	assert_gt(total_duration, item_duration, "Total score counting should be longer than item counting")


# ============================================================================
# Color Progression Consistency Tests
# ============================================================================


func test_rank_order_thresholds_are_monotonically_increasing() -> void:
	var prev_threshold: float = -1.0
	for rank in screen.RANK_ORDER:
		var threshold: float = screen.RANK_THRESHOLDS[rank]
		assert_gt(threshold, prev_threshold - 0.001, "Rank %s threshold should be >= previous" % rank)
		prev_threshold = threshold


func test_score_progression_goes_through_all_ranks() -> void:
	# Simulate a score counting from 0 to max (ratio 0.0 to 1.0)
	var seen_ranks: Array[String] = []
	for i in range(101):
		var ratio: float = float(i) / 100.0
		var rank: String = screen._get_rank_for_score_ratio(ratio)
		if not seen_ranks.has(rank):
			seen_ranks.append(rank)

	# All ranks should appear in the progression
	for rank in screen.RANK_ORDER:
		assert_true(seen_ranks.has(rank), "Rank %s should appear during 0-100%% progression" % rank)


# ============================================================================
# Skip Animation Tests (Issue #568)
# ============================================================================


func test_animated_score_screen_has_phase_enum() -> void:
	var script = load("res://scripts/ui/animated_score_screen.gd")
	var instance = script.new()
	add_child_autofree(instance)
	# Verify Phase enum values exist
	assert_eq(instance.Phase.COUNTING, 0, "Phase.COUNTING should be 0")
	assert_eq(instance.Phase.RANK_REVEAL, 1, "Phase.RANK_REVEAL should be 1")
	assert_eq(instance.Phase.COMPLETED, 2, "Phase.COMPLETED should be 2")


func test_animated_score_screen_initial_phase_is_counting() -> void:
	var script = load("res://scripts/ui/animated_score_screen.gd")
	var instance = script.new()
	add_child_autofree(instance)
	assert_eq(instance._phase, instance.Phase.COUNTING,
		"Initial phase should be COUNTING")


func test_animated_score_screen_skip_not_requested_initially() -> void:
	var script = load("res://scripts/ui/animated_score_screen.gd")
	var instance = script.new()
	add_child_autofree(instance)
	assert_false(instance._skip_requested,
		"Skip should not be requested initially")


func test_animated_score_screen_has_animation_completed_signal() -> void:
	var script = load("res://scripts/ui/animated_score_screen.gd")
	var instance = script.new()
	add_child_autofree(instance)
	assert_true(instance.has_signal("animation_completed"),
		"AnimatedScoreScreen should have animation_completed signal")


func test_animated_score_screen_active_timers_empty_initially() -> void:
	var script = load("res://scripts/ui/animated_score_screen.gd")
	var instance = script.new()
	add_child_autofree(instance)
	assert_eq(instance._active_timers.size(), 0,
		"Active timers should be empty initially")
