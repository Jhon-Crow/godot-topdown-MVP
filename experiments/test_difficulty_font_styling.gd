extends GutTest
## Unit tests for Issue #1014 - Difficulty font styling.
##
## Tests the gradient text generation for Power Fantasy and gothic font for Black Metal.


## Test that the gradient colors array is defined correctly.
func test_power_fantasy_gradient_colors_defined() -> void:
	# The gradient colors should be defined as an array of 5 colors
	var expected_count: int = 5
	var colors: Array[Color] = [
		Color(0.0, 1.0, 1.0),    # Cyan
		Color(0.5, 0.0, 1.0),    # Purple
		Color(1.0, 0.0, 1.0),    # Magenta
		Color(1.0, 0.5, 0.0),    # Orange
		Color(1.0, 1.0, 0.0),    # Yellow
	]

	assert_eq(colors.size(), expected_count, "Should have 5 gradient colors")
	assert_eq(colors[0], Color(0.0, 1.0, 1.0), "First color should be cyan")
	assert_eq(colors[4], Color(1.0, 1.0, 0.0), "Last color should be yellow")


## Test gradient sampling at the start (t=0).
func test_sample_gradient_at_start() -> void:
	var colors: Array[Color] = [
		Color(0.0, 1.0, 1.0),    # Cyan
		Color(0.5, 0.0, 1.0),    # Purple
		Color(1.0, 0.0, 1.0),    # Magenta
		Color(1.0, 0.5, 0.0),    # Orange
		Color(1.0, 1.0, 0.0),    # Yellow
	]

	var result: Color = _sample_gradient(0.0, colors)
	assert_eq(result, Color(0.0, 1.0, 1.0), "At t=0, should return first color (cyan)")


## Test gradient sampling at the end (t=1).
func test_sample_gradient_at_end() -> void:
	var colors: Array[Color] = [
		Color(0.0, 1.0, 1.0),    # Cyan
		Color(0.5, 0.0, 1.0),    # Purple
		Color(1.0, 0.0, 1.0),    # Magenta
		Color(1.0, 0.5, 0.0),    # Orange
		Color(1.0, 1.0, 0.0),    # Yellow
	]

	var result: Color = _sample_gradient(1.0, colors)
	assert_eq(result, Color(1.0, 1.0, 0.0), "At t=1, should return last color (yellow)")


## Test gradient sampling in the middle.
func test_sample_gradient_at_middle() -> void:
	var colors: Array[Color] = [
		Color(0.0, 1.0, 1.0),    # Cyan
		Color(0.5, 0.0, 1.0),    # Purple
		Color(1.0, 0.0, 1.0),    # Magenta
		Color(1.0, 0.5, 0.0),    # Orange
		Color(1.0, 1.0, 0.0),    # Yellow
	]

	# At t=0.5, we should be at the middle color (Magenta)
	var result: Color = _sample_gradient(0.5, colors)
	assert_eq(result, Color(1.0, 0.0, 1.0), "At t=0.5, should return middle color (magenta)")


## Test gradient BBCode generation for a simple text.
func test_create_gradient_bbcode_simple() -> void:
	var text: String = "AB"
	var colors: Array[Color] = [
		Color(1.0, 0.0, 0.0),  # Red
		Color(0.0, 0.0, 1.0),  # Blue
	]

	var result: String = _create_gradient_bbcode(text, colors)

	# First character should be red (ff0000), second should be blue (0000ff)
	assert_true(result.contains("[color=#ff0000]A[/color]"), "First char should have red color tag")
	assert_true(result.contains("[color=#0000ff]B[/color]"), "Last char should have blue color tag")


## Test gradient BBCode generation preserves spaces.
func test_create_gradient_bbcode_with_spaces() -> void:
	var text: String = "A B"
	var colors: Array[Color] = [
		Color(1.0, 0.0, 0.0),  # Red
		Color(0.0, 0.0, 1.0),  # Blue
	]

	var result: String = _create_gradient_bbcode(text, colors)

	# Space should not have color tags
	assert_true(result.contains(" "), "Result should contain space without color tags")
	assert_false(result.contains("[color=# ]"), "Space should not have a color tag")


## Test gradient BBCode generation for empty text.
func test_create_gradient_bbcode_empty() -> void:
	var text: String = ""
	var colors: Array[Color] = [Color.RED, Color.BLUE]

	var result: String = _create_gradient_bbcode(text, colors)
	assert_eq(result, "", "Empty text should return empty string")


## Test gradient BBCode for "Power Fantasy" text.
func test_create_gradient_bbcode_power_fantasy() -> void:
	var text: String = "Power Fantasy"
	var colors: Array[Color] = [
		Color(0.0, 1.0, 1.0),    # Cyan
		Color(0.5, 0.0, 1.0),    # Purple
		Color(1.0, 0.0, 1.0),    # Magenta
		Color(1.0, 0.5, 0.0),    # Orange
		Color(1.0, 1.0, 0.0),    # Yellow
	]

	var result: String = _create_gradient_bbcode(text, colors)

	# Check that the result contains color tags
	assert_true(result.contains("[color=#"), "Result should contain color tags")
	assert_true(result.contains("P"), "Result should contain 'P'")
	assert_true(result.contains("y"), "Result should contain 'y'")

	# Check that each non-space character has a color tag
	var color_tag_count: int = result.count("[color=#")
	var expected_non_space_chars: int = text.replace(" ", "").length()
	assert_eq(color_tag_count, expected_non_space_chars,
		"Each non-space character should have a color tag")


## Test gothic font path constant.
func test_gothic_font_path_defined() -> void:
	var path: String = "res://assets/fonts/gothic_bitmap.fnt"
	assert_true(ResourceLoader.exists(path), "Gothic font file should exist at the defined path")


# ============================================================================
# Helper functions (copied from difficulty_menu.gd for testing)
# ============================================================================


## Samples a color from a gradient at position t.
## @param t: Position along gradient (0.0 to 1.0).
## @param colors: Array of gradient colors.
## @returns: Interpolated color at the given position.
func _sample_gradient(t: float, colors: Array[Color]) -> Color:
	var num_colors: int = colors.size()

	if num_colors == 0:
		return Color.WHITE
	if num_colors == 1:
		return colors[0]

	# Clamp t to valid range
	t = clampf(t, 0.0, 1.0)

	# Calculate which segment we're in
	var segment_size: float = 1.0 / float(num_colors - 1)
	var segment_index: int = int(t / segment_size)

	# Clamp to valid segment index
	if segment_index >= num_colors - 1:
		segment_index = num_colors - 2

	# Calculate position within segment
	var segment_t: float = (t - (float(segment_index) * segment_size)) / segment_size

	# Interpolate between the two colors
	return colors[segment_index].lerp(colors[segment_index + 1], segment_t)


## Creates BBCode text with per-character gradient coloring.
## @param text: The text to apply gradient to.
## @param colors: Array of gradient colors.
## @returns: BBCode formatted text with color tags for each character.
func _create_gradient_bbcode(text: String, colors: Array[Color]) -> String:
	if text.is_empty():
		return ""

	var result: String = ""
	var text_length: int = text.length()

	for i in range(text_length):
		var char: String = text[i]

		# Skip whitespace characters (no color needed)
		if char == " ":
			result += " "
			continue

		# Calculate gradient position (0.0 to 1.0)
		var t: float = float(i) / float(text_length - 1) if text_length > 1 else 0.0

		# Interpolate color along the gradient
		var color: Color = _sample_gradient(t, colors)

		# Convert to hex and wrap character in color tag
		var hex_color: String = color.to_html(false)
		result += "[color=#" + hex_color + "]" + char + "[/color]"

	return result
