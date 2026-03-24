extends Node2D
## Grid-based level editor inspired by Hotline Miami 2's editor.
##
## Features:
## - Grid-based placement of walls, enemies, cover objects, and player spawn
## - Tools: Wall tool, Enemy tool, Cover tool, Player Spawn tool, Eraser
## - Pan and zoom for large maps
## - Save/load levels as JSON
## - Export levels for sharing
## - Play/test custom levels directly from the editor

## Tool types available in the editor.
enum Tool {
	WALL,
	ENEMY,
	COVER,
	PLAYER_SPAWN,
	ERASER,
	SELECT,
}

## Cover object subtypes.
enum CoverType {
	DESK,
	CRATE,
	BARREL,
	TABLE,
}

## Available enemy weapon types.
const ENEMY_WEAPONS: Array[String] = [
	"m16", "shotgun", "makarov_pm", "mini_uzi", "sniper"
]

## Cover type names for display.
const COVER_TYPE_NAMES: Array[String] = ["desk", "crate", "barrel", "table"]

## Cover type sizes in pixels (width, height).
const COVER_TYPE_SIZES: Dictionary = {
	"desk": Vector2(96, 32),
	"crate": Vector2(64, 64),
	"barrel": Vector2(48, 48),
	"table": Vector2(128, 64),
}

## Cover type colors for display.
const COVER_TYPE_COLORS: Dictionary = {
	"desk": Color(0.55, 0.4, 0.25, 1.0),
	"crate": Color(0.5, 0.45, 0.3, 1.0),
	"barrel": Color(0.4, 0.45, 0.5, 1.0),
	"table": Color(0.45, 0.35, 0.25, 1.0),
}

## Current level data being edited.
var level_data: LevelData = null

## Current active tool.
var current_tool: Tool = Tool.WALL

## Current enemy weapon selection.
var current_enemy_weapon: String = "m16"

## Current cover type selection.
var current_cover_type: String = "desk"

## Whether enemies patrol by default.
var enemy_patrol_enabled: bool = true

## Camera zoom level.
var _zoom_level: float = 1.0

## Camera position (pan offset).
var _camera_offset: Vector2 = Vector2.ZERO

## Whether the user is currently dragging to draw a wall.
var _is_drawing_wall: bool = false

## Wall draw start position (grid-snapped).
var _wall_start: Vector2 = Vector2.ZERO

## Current mouse position (grid-snapped).
var _wall_current: Vector2 = Vector2.ZERO

## Whether the user is panning the camera (middle mouse button).
var _is_panning: bool = false

## Pan start position.
var _pan_start: Vector2 = Vector2.ZERO

## Whether the grid is visible.
var _show_grid: bool = true

## UI panel reference.
var _ui_panel: Control = null

## Status label reference.
var _status_label: Label = null

## Name input reference.
var _name_input: LineEdit = null

## Camera2D reference.
var _camera: Camera2D = null

## Node holding all visual representations.
var _elements_node: Node2D = null


func _ready() -> void:
	# Create a new level if none loaded
	if level_data == null:
		level_data = LevelData.new()

	_setup_camera()
	_setup_elements_node()
	_build_ui()
	_redraw_level()


## Setup the camera for panning and zooming.
func _setup_camera() -> void:
	_camera = Camera2D.new()
	_camera.name = "EditorCamera"
	_camera.position = Vector2(level_data.map_width / 2.0, level_data.map_height / 2.0)
	_camera.zoom = Vector2(_zoom_level, _zoom_level)
	_camera.enabled = true
	add_child(_camera)


## Setup the node that holds all visual elements.
func _setup_elements_node() -> void:
	_elements_node = Node2D.new()
	_elements_node.name = "Elements"
	add_child(_elements_node)


## Build the editor UI overlay.
func _build_ui() -> void:
	var ui_layer := CanvasLayer.new()
	ui_layer.name = "EditorUI"
	ui_layer.layer = 10
	add_child(ui_layer)

	# Left toolbar panel
	_ui_panel = PanelContainer.new()
	_ui_panel.name = "ToolbarPanel"
	_ui_panel.offset_left = 8
	_ui_panel.offset_top = 8
	_ui_panel.offset_right = 228
	_ui_panel.offset_bottom = 600

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.1, 0.1, 0.12, 0.92)
	panel_style.corner_radius_top_left = 6
	panel_style.corner_radius_top_right = 6
	panel_style.corner_radius_bottom_left = 6
	panel_style.corner_radius_bottom_right = 6
	panel_style.border_color = Color(0.3, 0.3, 0.35, 1.0)
	panel_style.border_width_left = 1
	panel_style.border_width_right = 1
	panel_style.border_width_top = 1
	panel_style.border_width_bottom = 1
	_ui_panel.add_theme_stylebox_override("panel", panel_style)
	ui_layer.add_child(_ui_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	_ui_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "LEVEL EDITOR"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7, 1.0))
	vbox.add_child(title)

	# Separator
	vbox.add_child(HSeparator.new())

	# Level name input
	var name_label := Label.new()
	name_label.text = "Level Name:"
	name_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(name_label)

	_name_input = LineEdit.new()
	_name_input.text = level_data.level_name
	_name_input.placeholder_text = "Enter level name..."
	_name_input.text_changed.connect(_on_name_changed)
	vbox.add_child(_name_input)

	# Separator
	vbox.add_child(HSeparator.new())

	# Tools section
	var tools_label := Label.new()
	tools_label.text = "Tools"
	tools_label.add_theme_font_size_override("font_size", 13)
	tools_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85, 1.0))
	vbox.add_child(tools_label)

	# Tool buttons
	var tool_names: Array[String] = ["Wall [1]", "Enemy [2]", "Cover [3]", "Spawn [4]", "Eraser [5]", "Select [6]"]
	for i in range(tool_names.size()):
		var btn := Button.new()
		btn.text = tool_names[i]
		btn.custom_minimum_size = Vector2(0, 28)
		btn.pressed.connect(_on_tool_selected.bind(i))
		btn.name = "ToolBtn_%d" % i
		vbox.add_child(btn)

	# Separator
	vbox.add_child(HSeparator.new())

	# Enemy weapon selector
	var weapon_label := Label.new()
	weapon_label.text = "Enemy Weapon:"
	weapon_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(weapon_label)

	var weapon_option := OptionButton.new()
	weapon_option.name = "WeaponOption"
	for weapon in ENEMY_WEAPONS:
		weapon_option.add_item(weapon.replace("_", " ").capitalize())
	weapon_option.item_selected.connect(_on_weapon_selected)
	vbox.add_child(weapon_option)

	# Cover type selector
	var cover_label := Label.new()
	cover_label.text = "Cover Type:"
	cover_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(cover_label)

	var cover_option := OptionButton.new()
	cover_option.name = "CoverOption"
	for ctype in COVER_TYPE_NAMES:
		cover_option.add_item(ctype.capitalize())
	cover_option.item_selected.connect(_on_cover_type_selected)
	vbox.add_child(cover_option)

	# Patrol toggle
	var patrol_check := CheckButton.new()
	patrol_check.text = "Enemy Patrol"
	patrol_check.button_pressed = enemy_patrol_enabled
	patrol_check.toggled.connect(_on_patrol_toggled)
	vbox.add_child(patrol_check)

	# Separator
	vbox.add_child(HSeparator.new())

	# Action buttons
	var actions_label := Label.new()
	actions_label.text = "Actions"
	actions_label.add_theme_font_size_override("font_size", 13)
	actions_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85, 1.0))
	vbox.add_child(actions_label)

	var save_btn := Button.new()
	save_btn.text = "Save Level"
	save_btn.custom_minimum_size = Vector2(0, 28)
	save_btn.pressed.connect(_on_save_pressed)
	vbox.add_child(save_btn)

	var load_btn := Button.new()
	load_btn.text = "Load Level"
	load_btn.custom_minimum_size = Vector2(0, 28)
	load_btn.pressed.connect(_on_load_pressed)
	vbox.add_child(load_btn)

	var play_btn := Button.new()
	play_btn.text = "Play Level"
	play_btn.custom_minimum_size = Vector2(0, 28)
	play_btn.pressed.connect(_on_play_pressed)
	vbox.add_child(play_btn)

	var export_btn := Button.new()
	export_btn.text = "Export (Copy)"
	export_btn.custom_minimum_size = Vector2(0, 28)
	export_btn.pressed.connect(_on_export_pressed)
	vbox.add_child(export_btn)

	var import_btn := Button.new()
	import_btn.text = "Import (Paste)"
	import_btn.custom_minimum_size = Vector2(0, 28)
	import_btn.pressed.connect(_on_import_pressed)
	vbox.add_child(import_btn)

	var back_btn := Button.new()
	back_btn.text = "Back to Menu"
	back_btn.custom_minimum_size = Vector2(0, 28)
	back_btn.pressed.connect(_on_back_pressed)
	vbox.add_child(back_btn)

	# Status bar at bottom
	_status_label = Label.new()
	_status_label.name = "StatusLabel"
	_status_label.text = "Tool: Wall | Grid: ON"
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_status_label.add_theme_font_size_override("font_size", 11)
	_status_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75, 1.0))
	_status_label.anchor_left = 0.0
	_status_label.anchor_top = 1.0
	_status_label.anchor_right = 1.0
	_status_label.anchor_bottom = 1.0
	_status_label.offset_top = -28
	_status_label.offset_left = 240
	_status_label.offset_bottom = -4
	ui_layer.add_child(_status_label)

	_update_status()


func _unhandled_input(event: InputEvent) -> void:
	# Tool hotkeys
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1:
				_set_tool(Tool.WALL)
			KEY_2:
				_set_tool(Tool.ENEMY)
			KEY_3:
				_set_tool(Tool.COVER)
			KEY_4:
				_set_tool(Tool.PLAYER_SPAWN)
			KEY_5:
				_set_tool(Tool.ERASER)
			KEY_6:
				_set_tool(Tool.SELECT)
			KEY_G:
				_show_grid = not _show_grid
				_redraw_level()
				_update_status()
			KEY_ESCAPE:
				if _is_drawing_wall:
					_is_drawing_wall = false
					queue_redraw()
				else:
					_on_back_pressed()

	# Mouse input for placement
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)


## Handle mouse button events.
func _handle_mouse_button(event: InputEventMouseButton) -> void:
	var world_pos: Vector2 = _screen_to_world(event.position)
	var grid_pos: Vector2 = LevelData.snap_to_grid(world_pos)

	# Middle mouse button for panning
	if event.button_index == MOUSE_BUTTON_MIDDLE:
		if event.pressed:
			_is_panning = true
			_pan_start = event.position
		else:
			_is_panning = false
		return

	# Scroll for zoom
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		_zoom_level = clampf(_zoom_level * 1.1, 0.25, 4.0)
		_camera.zoom = Vector2(_zoom_level, _zoom_level)
		return
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_zoom_level = clampf(_zoom_level / 1.1, 0.25, 4.0)
		_camera.zoom = Vector2(_zoom_level, _zoom_level)
		return

	# Left mouse button for tool actions
	if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		# Ignore clicks on UI panel area
		if event.position.x < 236 and event.position.y < 610:
			return

		match current_tool:
			Tool.WALL:
				if not _is_drawing_wall:
					_is_drawing_wall = true
					_wall_start = grid_pos
					_wall_current = grid_pos
				else:
					_finish_wall()
			Tool.ENEMY:
				_place_enemy(grid_pos)
			Tool.COVER:
				_place_cover(grid_pos)
			Tool.PLAYER_SPAWN:
				_place_player_spawn(grid_pos)
			Tool.ERASER:
				_erase_at(world_pos)
			Tool.SELECT:
				pass  # Future: select and move objects

	# Right mouse button to cancel wall drawing
	if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if _is_drawing_wall:
			_is_drawing_wall = false
			queue_redraw()


## Handle mouse motion events.
func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if _is_panning:
		_camera.position -= event.relative / _zoom_level
		return

	if _is_drawing_wall:
		_wall_current = LevelData.snap_to_grid(_screen_to_world(event.position))
		queue_redraw()


## Convert screen position to world position.
func _screen_to_world(screen_pos: Vector2) -> Vector2:
	return _camera.position + (screen_pos - get_viewport_rect().size / 2.0) / _zoom_level


## Set the current tool.
func _set_tool(tool_type: Tool) -> void:
	if _is_drawing_wall and tool_type != Tool.WALL:
		_is_drawing_wall = false
	current_tool = tool_type
	_update_status()


## Finish drawing a wall rectangle.
func _finish_wall() -> void:
	_is_drawing_wall = false
	var rect := _get_wall_rect(_wall_start, _wall_current)
	# Minimum wall size is one cell
	if rect.size.x < LevelData.CELL_SIZE:
		rect.size.x = LevelData.CELL_SIZE
	if rect.size.y < LevelData.CELL_SIZE:
		rect.size.y = LevelData.CELL_SIZE

	level_data.walls.append({
		"x": rect.position.x,
		"y": rect.position.y,
		"w": rect.size.x,
		"h": rect.size.y,
	})
	_redraw_level()


## Get the rectangle from two corner points.
func _get_wall_rect(start: Vector2, end: Vector2) -> Rect2:
	var top_left := Vector2(min(start.x, end.x), min(start.y, end.y))
	var bottom_right := Vector2(max(start.x, end.x), max(start.y, end.y))
	return Rect2(top_left, bottom_right - top_left)


## Place an enemy at the given grid position.
func _place_enemy(pos: Vector2) -> void:
	level_data.enemies.append({
		"x": pos.x,
		"y": pos.y,
		"weapon": current_enemy_weapon,
		"patrol": enemy_patrol_enabled,
	})
	_redraw_level()


## Place a cover object at the given grid position.
func _place_cover(pos: Vector2) -> void:
	var cover_size: Vector2 = COVER_TYPE_SIZES.get(current_cover_type, Vector2(64, 64))
	level_data.cover_objects.append({
		"x": pos.x,
		"y": pos.y,
		"w": cover_size.x,
		"h": cover_size.y,
		"type": current_cover_type,
	})
	_redraw_level()


## Place the player spawn at the given grid position.
func _place_player_spawn(pos: Vector2) -> void:
	level_data.player_spawn = pos
	_redraw_level()


## Erase element nearest to the given world position.
func _erase_at(pos: Vector2) -> void:
	var erase_radius: float = 32.0

	# Check enemies
	for i in range(level_data.enemies.size() - 1, -1, -1):
		var e: Dictionary = level_data.enemies[i]
		if pos.distance_to(Vector2(e["x"], e["y"])) < erase_radius:
			level_data.enemies.remove_at(i)
			_redraw_level()
			return

	# Check cover
	for i in range(level_data.cover_objects.size() - 1, -1, -1):
		var c: Dictionary = level_data.cover_objects[i]
		var center := Vector2(c["x"] + c["w"] / 2.0, c["y"] + c["h"] / 2.0)
		if pos.distance_to(center) < erase_radius + 16.0:
			level_data.cover_objects.remove_at(i)
			_redraw_level()
			return

	# Check walls
	for i in range(level_data.walls.size() - 1, -1, -1):
		var w: Dictionary = level_data.walls[i]
		var rect := Rect2(w["x"], w["y"], w["w"], w["h"])
		if rect.has_point(pos):
			level_data.walls.remove_at(i)
			_redraw_level()
			return


## Redraw all level elements.
func _redraw_level() -> void:
	# Clear existing visual elements
	for child in _elements_node.get_children():
		child.queue_free()

	# Draw floor background
	var floor_rect := ColorRect.new()
	floor_rect.position = Vector2.ZERO
	floor_rect.size = Vector2(level_data.map_width, level_data.map_height)
	floor_rect.color = level_data.floor_color
	_elements_node.add_child(floor_rect)

	# Draw grid
	if _show_grid:
		_draw_grid()

	# Draw walls
	for w in level_data.walls:
		var wall_rect := ColorRect.new()
		wall_rect.position = Vector2(w["x"], w["y"])
		wall_rect.size = Vector2(w["w"], w["h"])
		wall_rect.color = level_data.wall_color
		_elements_node.add_child(wall_rect)

	# Draw cover objects
	for c in level_data.cover_objects:
		var cover_rect := ColorRect.new()
		cover_rect.position = Vector2(c["x"], c["y"])
		cover_rect.size = Vector2(c["w"], c["h"])
		var ctype: String = c.get("type", "crate")
		cover_rect.color = COVER_TYPE_COLORS.get(ctype, Color(0.5, 0.45, 0.3, 1.0))
		_elements_node.add_child(cover_rect)

		# Label for cover type
		var label := Label.new()
		label.text = ctype.substr(0, 1).to_upper()
		label.position = Vector2(c["x"] + 4, c["y"] + 2)
		label.add_theme_font_size_override("font_size", 10)
		label.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
		_elements_node.add_child(label)

	# Draw enemies
	for e in level_data.enemies:
		var enemy_marker := _create_enemy_marker(e)
		_elements_node.add_child(enemy_marker)

	# Draw player spawn
	var spawn_marker := _create_spawn_marker(level_data.player_spawn)
	_elements_node.add_child(spawn_marker)

	queue_redraw()


## Draw the grid overlay.
func _draw_grid() -> void:
	var grid_node := Node2D.new()
	grid_node.name = "Grid"
	grid_node.z_index = -1
	_elements_node.add_child(grid_node)
	# Grid is drawn in _draw() using queue_redraw()


## Create a visual marker for an enemy.
func _create_enemy_marker(data: Dictionary) -> Node2D:
	var marker := Node2D.new()
	marker.position = Vector2(data["x"], data["y"])

	# Enemy circle
	var circle := _create_circle(16.0, Color(0.8, 0.2, 0.2, 0.8))
	marker.add_child(circle)

	# Weapon label
	var label := Label.new()
	var weapon: String = data.get("weapon", "m16")
	label.text = weapon.substr(0, 3).to_upper()
	label.position = Vector2(-12, -24)
	label.add_theme_font_size_override("font_size", 9)
	label.add_theme_color_override("font_color", Color(1, 0.8, 0.8, 1.0))
	marker.add_child(label)

	# Patrol indicator
	if data.get("patrol", false):
		var patrol_circle := _create_circle(4.0, Color(1.0, 1.0, 0.0, 0.6))
		patrol_circle.position = Vector2(12, -12)
		marker.add_child(patrol_circle)

	return marker


## Create the player spawn marker.
func _create_spawn_marker(pos: Vector2) -> Node2D:
	var marker := Node2D.new()
	marker.position = pos

	# Player circle (green)
	var circle := _create_circle(18.0, Color(0.2, 0.8, 0.3, 0.8))
	marker.add_child(circle)

	# "P" label
	var label := Label.new()
	label.text = "P"
	label.position = Vector2(-6, -8)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 1.0))
	marker.add_child(label)

	return marker


## Create a colored circle using a Polygon2D.
func _create_circle(radius: float, color: Color) -> Polygon2D:
	var polygon := Polygon2D.new()
	var points: PackedVector2Array = PackedVector2Array()
	var segments: int = 16
	for i in range(segments):
		var angle: float = TAU * i / segments
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	polygon.polygon = points
	polygon.color = color
	return polygon


## Custom draw for grid and wall preview.
func _draw() -> void:
	# Draw grid lines
	if _show_grid:
		var grid_color := Color(0.3, 0.3, 0.35, 0.15)
		var cell := LevelData.CELL_SIZE
		for x in range(0, level_data.map_width + 1, cell):
			draw_line(Vector2(x, 0), Vector2(x, level_data.map_height), grid_color, 1.0)
		for y in range(0, level_data.map_height + 1, cell):
			draw_line(Vector2(0, y), Vector2(level_data.map_width, y), grid_color, 1.0)

	# Draw map border
	var border_color := Color(0.6, 0.6, 0.65, 0.8)
	draw_rect(Rect2(0, 0, level_data.map_width, level_data.map_height), border_color, false, 2.0)

	# Draw wall preview while drawing
	if _is_drawing_wall:
		var rect := _get_wall_rect(_wall_start, _wall_current)
		draw_rect(rect, Color(0.5, 0.5, 0.6, 0.4), true)
		draw_rect(rect, Color(0.7, 0.7, 0.8, 0.8), false, 1.0)


## Update the status bar text.
func _update_status() -> void:
	if _status_label == null:
		return
	var tool_name: String = ""
	match current_tool:
		Tool.WALL:
			tool_name = "Wall"
		Tool.ENEMY:
			tool_name = "Enemy (%s)" % current_enemy_weapon
		Tool.COVER:
			tool_name = "Cover (%s)" % current_cover_type
		Tool.PLAYER_SPAWN:
			tool_name = "Player Spawn"
		Tool.ERASER:
			tool_name = "Eraser"
		Tool.SELECT:
			tool_name = "Select"

	var grid_str: String = "ON" if _show_grid else "OFF"
	_status_label.text = "Tool: %s | Grid: %s | Walls: %d | Enemies: %d | Cover: %d" % [
		tool_name, grid_str,
		level_data.walls.size(),
		level_data.enemies.size(),
		level_data.cover_objects.size(),
	]


## UI callbacks.
func _on_tool_selected(index: int) -> void:
	_set_tool(index as Tool)


func _on_weapon_selected(index: int) -> void:
	if index >= 0 and index < ENEMY_WEAPONS.size():
		current_enemy_weapon = ENEMY_WEAPONS[index]
		_update_status()


func _on_cover_type_selected(index: int) -> void:
	if index >= 0 and index < COVER_TYPE_NAMES.size():
		current_cover_type = COVER_TYPE_NAMES[index]
		_update_status()


func _on_patrol_toggled(pressed: bool) -> void:
	enemy_patrol_enabled = pressed


func _on_name_changed(new_text: String) -> void:
	level_data.level_name = new_text


func _on_save_pressed() -> void:
	if _name_input:
		level_data.level_name = _name_input.text

	var manager: Node = get_node_or_null("/root/LevelEditorManager")
	if manager and manager.has_method("save_level"):
		var success: bool = manager.save_level(level_data)
		if success:
			_show_notification("Level saved: %s" % level_data.level_name)
		else:
			_show_notification("Failed to save level!")
	else:
		_show_notification("LevelEditorManager not available!")


func _on_load_pressed() -> void:
	var manager: Node = get_node_or_null("/root/LevelEditorManager")
	if manager == null or not manager.has_method("list_levels"):
		_show_notification("LevelEditorManager not available!")
		return

	var levels: Array = manager.list_levels()
	if levels.is_empty():
		_show_notification("No saved levels found.")
		return

	# Load the most recent level (simple approach)
	var loaded: LevelData = manager.load_level(levels[-1])
	if loaded:
		level_data = loaded
		if _name_input:
			_name_input.text = level_data.level_name
		_redraw_level()
		_update_status()
		_show_notification("Loaded: %s" % level_data.level_name)
	else:
		_show_notification("Failed to load level!")


func _on_play_pressed() -> void:
	# Save current level first
	_on_save_pressed()

	# Load the custom level scene
	var scene_loader: Node = get_node_or_null("/root/SceneLoader")
	var custom_level_path := "res://scenes/editor/CustomLevel.tscn"

	# Store level data in autoload for the custom level scene to read
	var manager: Node = get_node_or_null("/root/LevelEditorManager")
	if manager:
		manager.set("_pending_level_data", level_data)

	if scene_loader and scene_loader.has_method("load_level"):
		scene_loader.load_level(custom_level_path)
	else:
		get_tree().change_scene_to_file(custom_level_path)


func _on_export_pressed() -> void:
	if _name_input:
		level_data.level_name = _name_input.text

	var json_str: String = level_data.to_json()
	DisplayServer.clipboard_set(json_str)
	_show_notification("Level JSON copied to clipboard! Share it with friends.")


func _on_import_pressed() -> void:
	var clipboard_text: String = DisplayServer.clipboard_get()
	if clipboard_text.is_empty():
		_show_notification("Clipboard is empty!")
		return

	var imported := LevelData.new()
	if imported.from_json(clipboard_text):
		level_data = imported
		if _name_input:
			_name_input.text = level_data.level_name
		_redraw_level()
		_update_status()
		_show_notification("Imported: %s" % level_data.level_name)
	else:
		_show_notification("Invalid level data in clipboard!")


func _on_back_pressed() -> void:
	var scene_loader: Node = get_node_or_null("/root/SceneLoader")
	var main_scene: String = ProjectSettings.get_setting("application/run/main_scene", "")
	if scene_loader and scene_loader.has_method("load_level") and not main_scene.is_empty():
		scene_loader.load_level(main_scene)
	else:
		get_tree().change_scene_to_file("res://scenes/levels/LabyrinthLevel.tscn")


## Show a temporary notification message.
func _show_notification(text: String) -> void:
	if _status_label:
		_status_label.text = text
		# Reset status after 3 seconds
		get_tree().create_timer(3.0).timeout.connect(_update_status)
