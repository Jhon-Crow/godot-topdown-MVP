extends GutTest
## Unit tests for Gothic bitmap font integration and combo color system.
##
## Tests that the Gothic bitmap font is properly loaded and applied to rank labels
## and combo counter. Also tests the combo color progression.
## Issue #525: Add a font for ratings/grades.


## Path to the Gothic bitmap font resource (.fnt file).
const GOTHIC_FONT_PATH: String = "res://assets/fonts/gothic_bitmap.fnt"

## Path to the Gothic bitmap font texture.
const GOTHIC_FONT_TEXTURE: String = "res://assets/fonts/gothic_bitmap.png"


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
