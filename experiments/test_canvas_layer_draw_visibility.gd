extends Node
## Experiment: Test CanvasLayer + Node2D._draw() visibility in exported builds.
##
## This script creates multiple test overlays to determine which rendering
## approach works in Godot 4.3 gl_compatibility exported builds:
##
## Test 1: CanvasLayer (follow_viewport=false) + Node2D._draw() + manual canvas_transform
## Test 2: CanvasLayer (follow_viewport=true) + Node2D._draw() (original approach)
## Test 3: CanvasLayer + Control._draw() (screen-space, no transform needed)
## Test 4: Direct Node2D._draw() on scene root (default canvas layer)
##
## Expected: If Test 3 works but Tests 1-2 don't, the issue is specifically
## with Node2D._draw() inside CanvasLayers in exported builds.
##
## Usage: Add as autoload and check which colored rectangles are visible:
##   - Red rectangle (100x100 at screen 50,200): Test 1 (Node2D + canvas_transform)
##   - Green rectangle (100x100 at screen 200,200): Test 2 (Node2D + follow_viewport)
##   - Blue rectangle (100x100 at screen 350,200): Test 3 (Control._draw())
##   - Yellow rectangle (100x100 at screen 500,200): Test 4 (Direct Node2D)

var _results_label: Label = null


func _ready() -> void:
	# Test 1: CanvasLayer (follow_viewport=false) + Node2D + canvas_transform sync
	var cl1 := CanvasLayer.new()
	cl1.name = "Test1_Node2D_ManualSync"
	cl1.layer = 190
	cl1.follow_viewport_enabled = false
	var dn1 := _TestDrawNode2D.new()
	dn1.test_color = Color.RED
	dn1.draw_pos = Vector2(50, 200)
	dn1.label_text = "T1:Node2D+sync"
	cl1.add_child(dn1)
	add_child(cl1)

	# Test 2: CanvasLayer (follow_viewport=true) + Node2D
	var cl2 := CanvasLayer.new()
	cl2.name = "Test2_Node2D_FollowVP"
	cl2.layer = 191
	cl2.follow_viewport_enabled = true
	var dn2 := _TestDrawNode2D.new()
	dn2.test_color = Color.GREEN
	dn2.draw_pos = Vector2(200, 200)
	dn2.label_text = "T2:Node2D+followVP"
	dn2.use_canvas_sync = false
	cl2.add_child(dn2)
	add_child(cl2)

	# Test 3: CanvasLayer + Control._draw()
	var cl3 := CanvasLayer.new()
	cl3.name = "Test3_Control_Draw"
	cl3.layer = 192
	var dc3 := _TestDrawControl.new()
	dc3.test_color = Color.BLUE
	dc3.draw_pos = Vector2(350, 200)
	dc3.label_text = "T3:Control._draw()"
	cl3.add_child(dc3)
	add_child(cl3)

	# Test 4: Direct Node2D on scene root (no CanvasLayer)
	# This won't be above effects but tests if _draw() works at all
	var dn4 := _TestDrawNode2D.new()
	dn4.test_color = Color.YELLOW
	dn4.draw_pos = Vector2(500, 200)
	dn4.label_text = "T4:Direct"
	dn4.use_canvas_sync = false
	dn4.z_index = 4096  # Max z_index
	add_child(dn4)

	# Results label
	var cl_label := CanvasLayer.new()
	cl_label.layer = 198
	_results_label = Label.new()
	_results_label.text = "Canvas Draw Test — visible rects show working approaches"
	_results_label.position = Vector2(10, 170)
	_results_label.add_theme_color_override("font_color", Color.WHITE)
	_results_label.add_theme_font_size_override("font_size", 14)
	cl_label.add_child(_results_label)
	add_child(cl_label)


func _process(_delta: float) -> void:
	# Sync Test 1 canvas layer transform
	var cl1: Node = get_node_or_null("Test1_Node2D_ManualSync")
	if cl1 and cl1 is CanvasLayer:
		var vp := get_viewport()
		if vp:
			# For screen-space drawing, we DON'T want canvas_transform
			# (that would move the rect with the camera).
			# Test 1 draws in screen-space coords, so leave transform as identity.
			pass


## Inner class: Node2D that draws a colored rectangle via _draw().
class _TestDrawNode2D extends Node2D:
	var test_color: Color = Color.RED
	var draw_pos: Vector2 = Vector2.ZERO
	var label_text: String = ""
	var use_canvas_sync: bool = true

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var rect := Rect2(draw_pos, Vector2(100, 100))
		draw_rect(rect, test_color)
		var font: Font = ThemeDB.fallback_font
		if font:
			draw_string(font, draw_pos + Vector2(5, 115), label_text,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)


## Inner class: Control that draws a colored rectangle via _draw().
class _TestDrawControl extends Control:
	var test_color: Color = Color.BLUE
	var draw_pos: Vector2 = Vector2.ZERO
	var label_text: String = ""

	func _ready() -> void:
		# Make sure this Control covers the full screen so _draw() can
		# paint anywhere
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var rect := Rect2(draw_pos, Vector2(100, 100))
		draw_rect(rect, test_color)
		var font: Font = ThemeDB.fallback_font
		if font:
			draw_string(font, draw_pos + Vector2(5, 115), label_text,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)
