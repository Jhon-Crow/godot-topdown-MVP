extends GutTest
## Unit tests for AnimatedScoreScreen Gothic font integration.
##
## Tests that the Gothic font is properly loaded and applied to score screen labels.
## Issue #525: Add a font for ratings/grades.


## Path to the Gothic font resource.
const GOTHIC_FONT_PATH: String = "res://assets/fonts/UnifrakturMaguntia-Book.ttf"


func test_gothic_font_file_exists() -> void:
	var font = load(GOTHIC_FONT_PATH)
	assert_not_null(font, "Gothic font file should exist at %s" % GOTHIC_FONT_PATH)


func test_gothic_font_is_font_file() -> void:
	var font = load(GOTHIC_FONT_PATH)
	assert_true(font is FontFile, "Loaded resource should be a FontFile")


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
	assert_not_null(font, "Gothic font should be loadable via _get_gothic_font()")
	assert_true(font is FontFile, "Returned font should be a FontFile")


func test_animated_score_screen_font_caching() -> void:
	var script = load("res://scripts/ui/animated_score_screen.gd")
	var instance = script.new()
	add_child_autofree(instance)
	var font1 = instance._get_gothic_font()
	var font2 = instance._get_gothic_font()
	assert_same(font1, font2, "Font should be cached and return same instance")


func test_apply_gothic_font_to_label() -> void:
	var script = load("res://scripts/ui/animated_score_screen.gd")
	var instance = script.new()
	add_child_autofree(instance)
	var label = Label.new()
	add_child_autofree(label)
	instance._apply_gothic_font(label)
	var applied_font = label.get_theme_font("font")
	assert_not_null(applied_font, "Label should have a font override after _apply_gothic_font()")
