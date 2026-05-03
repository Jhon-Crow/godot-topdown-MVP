extends GutTest
## Unit tests for PauseMenu and SettingsMenu (Issue #1222).
##
## Regression tests to ensure that:
## 1. settings_menu.gd can be parsed without errors (no stale variable references).
## 2. SettingsMenu.tscn can be instantiated without crashing.
## 3. pause_menu.gd can be parsed (i.e., its preload of SettingsMenu.tscn succeeds).
## 4. PauseMenu.tscn can be instantiated without crashing.
## 5. All expected buttons exist and their signals are connected after instantiation.
##
## The root bug (Issue #1222) was that PR #1201 added
##   optimization_button.tooltip_text = "Optimization"
## to settings_menu.gd, but PR #1190 had already renamed that variable to
##   performance_button.
## In GDScript 4 this causes a parse/compile error in settings_menu.gd,
## which in turn causes preload("res://scenes/ui/SettingsMenu.tscn") in
## pause_menu.gd to fail, which causes pause_menu.gd itself to fail to parse,
## leaving PauseMenu with no script and all buttons unresponsive.


# ============================================================================
# Helpers
# ============================================================================


## Try to load a resource; return null (not a test failure) if it cannot be
## loaded so individual tests can report a clear failure message.
func _try_load(path: String) -> Resource:
	return load(path)


# ============================================================================
# SettingsMenu script parse check
# ============================================================================


func test_settings_menu_script_parses() -> void:
	var script: GDScript = _try_load("res://scripts/ui/settings_menu.gd") as GDScript
	assert_not_null(script, "settings_menu.gd must be loadable (parse error = null)")


func test_settings_menu_scene_loads() -> void:
	var scene: PackedScene = _try_load("res://scenes/ui/SettingsMenu.tscn") as PackedScene
	assert_not_null(scene, "SettingsMenu.tscn must be loadable")


func test_settings_menu_instantiates() -> void:
	var scene: PackedScene = _try_load("res://scenes/ui/SettingsMenu.tscn") as PackedScene
	if scene == null:
		fail_test("SettingsMenu.tscn could not be loaded — skipping instantiation check")
		return

	var instance: Node = scene.instantiate()
	assert_not_null(instance, "SettingsMenu.tscn must instantiate without error")
	if instance:
		instance.queue_free()


# ============================================================================
# PauseMenu script parse check
# ============================================================================


func test_pause_menu_script_parses() -> void:
	## If settings_menu.gd has a parse error, preload inside pause_menu.gd
	## fails at compile time, causing pause_menu.gd itself to fail to parse.
	var script: GDScript = _try_load("res://scripts/ui/pause_menu.gd") as GDScript
	assert_not_null(script, "pause_menu.gd must be loadable (preload of SettingsMenu.tscn may have failed)")


func test_pause_menu_scene_loads() -> void:
	var scene: PackedScene = _try_load("res://scenes/ui/PauseMenu.tscn") as PackedScene
	assert_not_null(scene, "PauseMenu.tscn must be loadable")


func test_pause_menu_instantiates() -> void:
	var scene: PackedScene = _try_load("res://scenes/ui/PauseMenu.tscn") as PackedScene
	if scene == null:
		fail_test("PauseMenu.tscn could not be loaded — skipping instantiation check")
		return

	var instance: Node = scene.instantiate()
	assert_not_null(instance, "PauseMenu.tscn must instantiate without error")
	if instance:
		instance.queue_free()


func test_pause_menu_background_uses_cracked_glass_shader() -> void:
	var scene: PackedScene = _try_load("res://scenes/ui/PauseMenu.tscn") as PackedScene
	if scene == null:
		fail_test("PauseMenu.tscn could not be loaded")
		return

	var instance: Node = scene.instantiate()
	add_child_autofree(instance)

	var background: ColorRect = instance.get_node_or_null("ColorRect") as ColorRect
	assert_not_null(background, "PauseMenu must keep a full-screen background ColorRect")
	if background == null:
		return

	var material := background.material as ShaderMaterial
	assert_not_null(material, "PauseMenu background must use a shader material")
	if material == null:
		return

	assert_not_null(material.shader, "PauseMenu background shader material must have a shader")
	if material.shader == null:
		return

	assert_eq(
		material.shader.resource_path,
		"res://scripts/shaders/pause_cracked_glass.gdshader",
		"PauseMenu background must use the cracked glass pause shader")
	assert_lte(
		float(material.get_shader_parameter("crack_opacity")),
		0.15,
		"PauseMenu cracks must remain a subtle glass overlay")
	assert_lte(
		float(material.get_shader_parameter("crack_coverage")),
		0.15,
		"PauseMenu cracks must not uniformly cover the full screen")
	assert_lte(
		float(material.get_shader_parameter("crack_scale")),
		1.5,
		"PauseMenu cracks must stay sparse instead of filling the screen with small cells")


# ============================================================================
# PauseMenu button presence
# ============================================================================


func test_pause_menu_has_resume_button() -> void:
	var scene: PackedScene = _try_load("res://scenes/ui/PauseMenu.tscn") as PackedScene
	if scene == null:
		fail_test("PauseMenu.tscn could not be loaded")
		return

	var instance: Node = scene.instantiate()
	add_child_autofree(instance)

	var btn: Button = instance.get_node_or_null("MenuContainer/VBoxContainer/ResumeButton") as Button
	assert_not_null(btn, "PauseMenu must have a ResumeButton")


func test_pause_menu_has_quit_button() -> void:
	var scene: PackedScene = _try_load("res://scenes/ui/PauseMenu.tscn") as PackedScene
	if scene == null:
		fail_test("PauseMenu.tscn could not be loaded")
		return

	var instance: Node = scene.instantiate()
	add_child_autofree(instance)

	var btn: Button = instance.get_node_or_null("MenuContainer/VBoxContainer/QuitButton") as Button
	assert_not_null(btn, "PauseMenu must have a QuitButton")


func test_pause_menu_has_settings_button() -> void:
	var scene: PackedScene = _try_load("res://scenes/ui/PauseMenu.tscn") as PackedScene
	if scene == null:
		fail_test("PauseMenu.tscn could not be loaded")
		return

	var instance: Node = scene.instantiate()
	add_child_autofree(instance)

	var btn: Button = instance.get_node_or_null("MenuContainer/VBoxContainer/SettingsButton") as Button
	assert_not_null(btn, "PauseMenu must have a SettingsButton")


# ============================================================================
# PauseMenu button signal connectivity
# ============================================================================


func test_pause_menu_resume_button_has_connections() -> void:
	## After script _ready() runs, the Resume button must have at least one
	## signal connection.  If pause_menu.gd failed to parse, _ready() never
	## ran and no connections exist — this test would fail.
	var scene: PackedScene = _try_load("res://scenes/ui/PauseMenu.tscn") as PackedScene
	if scene == null:
		fail_test("PauseMenu.tscn could not be loaded")
		return

	var instance: Node = scene.instantiate()
	add_child_autofree(instance)
	await get_tree().process_frame  # let _ready() execute

	var btn: Button = instance.get_node_or_null("MenuContainer/VBoxContainer/ResumeButton") as Button
	if btn == null:
		fail_test("ResumeButton not found")
		return

	var connections: Array = btn.get_signal_connection_list("pressed")
	assert_gt(connections.size(), 0,
		"ResumeButton.pressed must have at least one connection after _ready()")


func test_pause_menu_quit_button_has_connections() -> void:
	var scene: PackedScene = _try_load("res://scenes/ui/PauseMenu.tscn") as PackedScene
	if scene == null:
		fail_test("PauseMenu.tscn could not be loaded")
		return

	var instance: Node = scene.instantiate()
	add_child_autofree(instance)
	await get_tree().process_frame

	var btn: Button = instance.get_node_or_null("MenuContainer/VBoxContainer/QuitButton") as Button
	if btn == null:
		fail_test("QuitButton not found")
		return

	var connections: Array = btn.get_signal_connection_list("pressed")
	assert_gt(connections.size(), 0,
		"QuitButton.pressed must have at least one connection after _ready()")


func test_pause_menu_settings_button_has_connections() -> void:
	var scene: PackedScene = _try_load("res://scenes/ui/PauseMenu.tscn") as PackedScene
	if scene == null:
		fail_test("PauseMenu.tscn could not be loaded")
		return

	var instance: Node = scene.instantiate()
	add_child_autofree(instance)
	await get_tree().process_frame

	var btn: Button = instance.get_node_or_null("MenuContainer/VBoxContainer/SettingsButton") as Button
	if btn == null:
		fail_test("SettingsButton not found")
		return

	var connections: Array = btn.get_signal_connection_list("pressed")
	assert_gt(connections.size(), 0,
		"SettingsButton.pressed must have at least one connection after _ready()")


# ============================================================================
# SettingsMenu has no reference to old 'optimization_button' (regression guard)
# ============================================================================


func test_settings_menu_script_has_no_optimization_button_reference() -> void:
	## Directly reads the source text to guard against future PRs re-introducing
	## the stale 'optimization_button' identifier (root cause of Issue #1222).
	var file := FileAccess.open(
		"res://scripts/ui/settings_menu.gd", FileAccess.READ)
	if file == null:
		fail_test("Could not open settings_menu.gd for reading")
		return

	var source: String = file.get_as_text()
	file.close()

	assert_false(
		"optimization_button" in source,
		"settings_menu.gd must NOT reference 'optimization_button' (renamed to 'performance_button' in PR #1190)")


func test_settings_menu_script_has_performance_button_reference() -> void:
	## Counter-check: the correct variable name must be present.
	var file := FileAccess.open(
		"res://scripts/ui/settings_menu.gd", FileAccess.READ)
	if file == null:
		fail_test("Could not open settings_menu.gd for reading")
		return

	var source: String = file.get_as_text()
	file.close()

	assert_true(
		"performance_button" in source,
		"settings_menu.gd must reference 'performance_button' (the correct name after PR #1190)")
