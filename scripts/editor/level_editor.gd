extends Node2D
## Grid-based level editor inspired by Hotline Miami 2's editor.
##
## Features:
## - Grid-based placement of walls, enemies, cover objects, trees, lights,
##   decorations, and player spawn
## - Tools: Wall, Enemy, Cover, Player Spawn, Eraser, Tree, Light, Decoration
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
	TREE,
	LIGHT,
	DECORATION,
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

## Tree type names for display.
const TREE_TYPE_NAMES: Array[String] = ["oak", "pine", "birch", "dead"]

## Tree type properties: trunk_size, crown_radius, trunk_color, crown_color.
const TREE_TYPE_PROPS: Dictionary = {
	"oak": {
		"trunk_w": 40.0, "trunk_h": 40.0,
		"crown_radius": 56.0,
		"trunk_color": Color(0.35, 0.25, 0.18, 1.0),
		"crown_color": Color(0.2, 0.35, 0.2, 0.55),
	},
	"pine": {
		"trunk_w": 32.0, "trunk_h": 32.0,
		"crown_radius": 44.0,
		"trunk_color": Color(0.33, 0.23, 0.16, 1.0),
		"crown_color": Color(0.15, 0.32, 0.15, 0.6),
	},
	"birch": {
		"trunk_w": 24.0, "trunk_h": 36.0,
		"crown_radius": 48.0,
		"trunk_color": Color(0.85, 0.82, 0.75, 1.0),
		"crown_color": Color(0.3, 0.45, 0.2, 0.5),
	},
	"dead": {
		"trunk_w": 36.0, "trunk_h": 36.0,
		"crown_radius": 0.0,
		"trunk_color": Color(0.3, 0.25, 0.2, 1.0),
		"crown_color": Color(0.0, 0.0, 0.0, 0.0),
	},
}

## Light type names for display.
const LIGHT_TYPE_NAMES: Array[String] = [
	"street_lamp", "campfire", "spotlight", "ambient", "neon"
]

## Light type default properties.
const LIGHT_TYPE_PROPS: Dictionary = {
	"street_lamp": {
		"color": Color(1.0, 0.95, 0.8, 1.0),
		"energy": 1.5,
		"radius": 256.0,
		"shadow": true,
	},
	"campfire": {
		"color": Color(1.0, 0.6, 0.2, 1.0),
		"energy": 2.0,
		"radius": 192.0,
		"shadow": true,
	},
	"spotlight": {
		"color": Color(1.0, 1.0, 0.95, 1.0),
		"energy": 3.0,
		"radius": 320.0,
		"shadow": true,
	},
	"ambient": {
		"color": Color(0.7, 0.75, 0.9, 1.0),
		"energy": 0.8,
		"radius": 400.0,
		"shadow": false,
	},
	"neon": {
		"color": Color(0.9, 0.2, 0.8, 1.0),
		"energy": 2.5,
		"radius": 200.0,
		"shadow": false,
	},
}

## Decoration type names for display.
const DECORATION_TYPE_NAMES: Array[String] = [
	"rock", "stump", "log", "bush", "crate_small", "trash"
]

## Decoration type properties: size, color, has_collision.
const DECORATION_TYPE_PROPS: Dictionary = {
	"rock": {
		"w": 40.0, "h": 32.0,
		"color": Color(0.5, 0.48, 0.45, 1.0),
		"collision": true,
	},
	"stump": {
		"w": 32.0, "h": 32.0,
		"color": Color(0.4, 0.3, 0.2, 1.0),
		"collision": true,
	},
	"log": {
		"w": 80.0, "h": 24.0,
		"color": Color(0.45, 0.33, 0.2, 1.0),
		"collision": true,
	},
	"bush": {
		"w": 48.0, "h": 40.0,
		"color": Color(0.25, 0.4, 0.2, 0.7),
		"collision": false,
	},
	"crate_small": {
		"w": 32.0, "h": 32.0,
		"color": Color(0.55, 0.48, 0.3, 1.0),
		"collision": true,
	},
	"trash": {
		"w": 24.0, "h": 24.0,
		"color": Color(0.35, 0.35, 0.3, 0.8),
		"collision": false,
	},
}

## Current level data being edited.
var level_data: LevelData = null

## Current active tool.
var current_tool: Tool = Tool.WALL

## Current enemy weapon selection.
var current_enemy_weapon: String = "m16"

## Current cover type selection.
var current_cover_type: String = "desk"

## Current tree type selection.
var current_tree_type: String = "oak"

## Current light type selection.
var current_light_type: String = "street_lamp"

## Current decoration type selection.
var current_decoration_type: String = "rock"

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

## Subtype options container (swapped per tool).
var _subtype_container: VBoxContainer = null


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
	_ui_panel.offset_bottom = 720

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

	# Scroll container for long toolbar
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_ui_panel.add_child(scroll)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	scroll.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	margin.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "LEVEL EDITOR"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7, 1.0))
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	# Level name input
	var name_label := Label.new()
	name_label.text = "Level Name:"
	name_label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(name_label)

	_name_input = LineEdit.new()
	_name_input.text = level_data.level_name
	_name_input.placeholder_text = "Enter level name..."
	_name_input.text_changed.connect(_on_name_changed)
	vbox.add_child(_name_input)

	vbox.add_child(HSeparator.new())

	# Tools section
	var tools_label := Label.new()
	tools_label.text = "Tools"
	tools_label.add_theme_font_size_override("font_size", 12)
	tools_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85, 1.0))
	vbox.add_child(tools_label)

	# Tool buttons
	var tool_names: Array[String] = [
		"Wall [1]", "Enemy [2]", "Cover [3]", "Spawn [4]",
		"Eraser [5]", "Tree [6]", "Light [7]", "Decor [8]",
	]
	for i in range(tool_names.size()):
		var btn := Button.new()
		btn.text = tool_names[i]
		btn.custom_minimum_size = Vector2(0, 26)
		btn.pressed.connect(_on_tool_selected.bind(i))
		btn.name = "ToolBtn_%d" % i
		vbox.add_child(btn)

	vbox.add_child(HSeparator.new())

	# Subtype options container (dynamically populated per tool)
	_subtype_container = VBoxContainer.new()
	_subtype_container.name = "SubtypeContainer"
	_subtype_container.add_theme_constant_override("separation", 4)
	vbox.add_child(_subtype_container)

	# Build initial subtype options
	_rebuild_subtype_options()

	vbox.add_child(HSeparator.new())

	# Action buttons
	var actions_label := Label.new()
	actions_label.text = "Actions"
	actions_label.add_theme_font_size_override("font_size", 12)
	actions_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85, 1.0))
	vbox.add_child(actions_label)

	var action_buttons: Array[Dictionary] = [
		{"text": "Save Level", "callback": _on_save_pressed},
		{"text": "Load Level", "callback": _on_load_pressed},
		{"text": "Play Level", "callback": _on_play_pressed},
		{"text": "Export (Copy)", "callback": _on_export_pressed},
		{"text": "Import (Paste)", "callback": _on_import_pressed},
		{"text": "Back to Menu", "callback": _on_back_pressed},
	]
	for action in action_buttons:
		var btn := Button.new()
		btn.text = action["text"]
		btn.custom_minimum_size = Vector2(0, 26)
		btn.pressed.connect(action["callback"])
		vbox.add_child(btn)

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


## Rebuild the subtype options panel for the current tool.
func _rebuild_subtype_options() -> void:
	for child in _subtype_container.get_children():
		child.queue_free()

	match current_tool:
		Tool.ENEMY:
			_build_enemy_options()
		Tool.COVER:
			_build_option_selector("Cover Type:", COVER_TYPE_NAMES, _on_cover_type_selected)
		Tool.TREE:
			_build_option_selector("Tree Type:", TREE_TYPE_NAMES, _on_tree_type_selected)
		Tool.LIGHT:
			_build_option_selector("Light Type:", LIGHT_TYPE_NAMES, _on_light_type_selected)
		Tool.DECORATION:
			_build_option_selector("Decoration:", DECORATION_TYPE_NAMES, _on_decoration_type_selected)


## Build enemy-specific options (weapon + patrol toggle).
func _build_enemy_options() -> void:
	var weapon_label := Label.new()
	weapon_label.text = "Enemy Weapon:"
	weapon_label.add_theme_font_size_override("font_size", 11)
	_subtype_container.add_child(weapon_label)

	var weapon_option := OptionButton.new()
	weapon_option.name = "WeaponOption"
	for weapon in ENEMY_WEAPONS:
		weapon_option.add_item(weapon.replace("_", " ").capitalize())
	weapon_option.item_selected.connect(_on_weapon_selected)
	_subtype_container.add_child(weapon_option)

	var patrol_check := CheckButton.new()
	patrol_check.text = "Enemy Patrol"
	patrol_check.button_pressed = enemy_patrol_enabled
	patrol_check.toggled.connect(_on_patrol_toggled)
	_subtype_container.add_child(patrol_check)


## Build a generic option selector for subtype tools.
func _build_option_selector(label_text: String, names: Array[String], callback: Callable) -> void:
	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 11)
	_subtype_container.add_child(label)

	var option := OptionButton.new()
	for n in names:
		option.add_item(n.replace("_", " ").capitalize())
	option.item_selected.connect(callback)
	_subtype_container.add_child(option)


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
				_set_tool(Tool.TREE)
			KEY_7:
				_set_tool(Tool.LIGHT)
			KEY_8:
				_set_tool(Tool.DECORATION)
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
		if event.position.x < 236 and event.position.y < 730:
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
			Tool.TREE:
				_place_tree(grid_pos)
			Tool.LIGHT:
				_place_light(grid_pos)
			Tool.DECORATION:
				_place_decoration(grid_pos)

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
	_rebuild_subtype_options()
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


## Place a tree at the given grid position.
func _place_tree(pos: Vector2) -> void:
	level_data.trees.append({
		"x": pos.x,
		"y": pos.y,
		"type": current_tree_type,
	})
	_redraw_level()


## Place a light source at the given grid position.
func _place_light(pos: Vector2) -> void:
	var props: Dictionary = LIGHT_TYPE_PROPS.get(current_light_type, {})
	var c: Color = props.get("color", Color.WHITE)
	level_data.lights.append({
		"x": pos.x,
		"y": pos.y,
		"type": current_light_type,
		"color": {"r": c.r, "g": c.g, "b": c.b, "a": c.a},
		"energy": props.get("energy", 1.5),
		"radius": props.get("radius", 256.0),
	})
	_redraw_level()


## Place a decoration at the given grid position.
func _place_decoration(pos: Vector2) -> void:
	level_data.decorations.append({
		"x": pos.x,
		"y": pos.y,
		"type": current_decoration_type,
	})
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

	# Check trees
	for i in range(level_data.trees.size() - 1, -1, -1):
		var t: Dictionary = level_data.trees[i]
		if pos.distance_to(Vector2(t["x"], t["y"])) < erase_radius + 20.0:
			level_data.trees.remove_at(i)
			_redraw_level()
			return

	# Check lights
	for i in range(level_data.lights.size() - 1, -1, -1):
		var l: Dictionary = level_data.lights[i]
		if pos.distance_to(Vector2(l["x"], l["y"])) < erase_radius:
			level_data.lights.remove_at(i)
			_redraw_level()
			return

	# Check decorations
	for i in range(level_data.decorations.size() - 1, -1, -1):
		var d: Dictionary = level_data.decorations[i]
		if pos.distance_to(Vector2(d["x"], d["y"])) < erase_radius:
			level_data.decorations.remove_at(i)
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

		var label := Label.new()
		label.text = ctype.substr(0, 1).to_upper()
		label.position = Vector2(c["x"] + 4, c["y"] + 2)
		label.add_theme_font_size_override("font_size", 10)
		label.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
		_elements_node.add_child(label)

	# Draw decorations (below trees)
	for d in level_data.decorations:
		var marker := _create_decoration_marker(d)
		_elements_node.add_child(marker)

	# Draw tree trunks (z_index 0, collision layer)
	for t in level_data.trees:
		var trunk_marker := _create_tree_trunk_marker(t)
		_elements_node.add_child(trunk_marker)

	# Draw tree crowns (z_index 10, overlay)
	for t in level_data.trees:
		var crown_marker := _create_tree_crown_marker(t)
		if crown_marker:
			_elements_node.add_child(crown_marker)

	# Draw light source markers
	for l in level_data.lights:
		var light_marker := _create_light_marker(l)
		_elements_node.add_child(light_marker)

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


## Create a visual marker for an enemy.
func _create_enemy_marker(data: Dictionary) -> Node2D:
	var marker := Node2D.new()
	marker.position = Vector2(data["x"], data["y"])

	var circle := _create_circle(16.0, Color(0.8, 0.2, 0.2, 0.8))
	marker.add_child(circle)

	var label := Label.new()
	var weapon: String = data.get("weapon", "m16")
	label.text = weapon.substr(0, 3).to_upper()
	label.position = Vector2(-12, -24)
	label.add_theme_font_size_override("font_size", 9)
	label.add_theme_color_override("font_color", Color(1, 0.8, 0.8, 1.0))
	marker.add_child(label)

	if data.get("patrol", false):
		var patrol_circle := _create_circle(4.0, Color(1.0, 1.0, 0.0, 0.6))
		patrol_circle.position = Vector2(12, -12)
		marker.add_child(patrol_circle)

	return marker


## Create the player spawn marker.
func _create_spawn_marker(pos: Vector2) -> Node2D:
	var marker := Node2D.new()
	marker.position = pos

	var circle := _create_circle(18.0, Color(0.2, 0.8, 0.3, 0.8))
	marker.add_child(circle)

	var label := Label.new()
	label.text = "P"
	label.position = Vector2(-6, -8)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 1.0))
	marker.add_child(label)

	return marker


## Create a tree trunk marker (brown rectangle, represents collision area).
func _create_tree_trunk_marker(data: Dictionary) -> Node2D:
	var ttype: String = data.get("type", "oak")
	var props: Dictionary = TREE_TYPE_PROPS.get(ttype, TREE_TYPE_PROPS["oak"])
	var tw: float = props["trunk_w"]
	var th: float = props["trunk_h"]

	var marker := Node2D.new()
	marker.position = Vector2(data["x"], data["y"])

	# Trunk rectangle
	var trunk := ColorRect.new()
	trunk.position = Vector2(-tw / 2.0, -th / 2.0)
	trunk.size = Vector2(tw, th)
	trunk.color = props["trunk_color"]
	marker.add_child(trunk)

	# Label
	var label := Label.new()
	label.text = ttype.substr(0, 1).to_upper()
	label.position = Vector2(-6, -8)
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	marker.add_child(label)

	return marker


## Create a tree crown marker (semi-transparent circle at z_index 10).
func _create_tree_crown_marker(data: Dictionary) -> Node2D:
	var ttype: String = data.get("type", "oak")
	var props: Dictionary = TREE_TYPE_PROPS.get(ttype, TREE_TYPE_PROPS["oak"])
	var radius: float = props["crown_radius"]

	if radius <= 0.0:
		return null  # Dead trees have no crown

	var marker := Node2D.new()
	marker.position = Vector2(data["x"], data["y"])
	marker.z_index = 10

	var crown := _create_circle(radius, props["crown_color"])
	marker.add_child(crown)

	return marker


## Create a light source marker in the editor.
func _create_light_marker(data: Dictionary) -> Node2D:
	var ltype: String = data.get("type", "street_lamp")
	var props: Dictionary = LIGHT_TYPE_PROPS.get(ltype, LIGHT_TYPE_PROPS["street_lamp"])
	var c_data: Dictionary = data.get("color", {})
	var light_color: Color
	if c_data.is_empty():
		light_color = props.get("color", Color.WHITE)
	else:
		light_color = Color(
			c_data.get("r", 1.0), c_data.get("g", 1.0),
			c_data.get("b", 1.0), c_data.get("a", 1.0)
		)
	var radius: float = data.get("radius", props.get("radius", 256.0))

	var marker := Node2D.new()
	marker.position = Vector2(data["x"], data["y"])

	# Radius preview circle (faint)
	var radius_circle := _create_circle(radius, Color(light_color.r, light_color.g, light_color.b, 0.08))
	marker.add_child(radius_circle)

	# Center icon circle
	var center_circle := _create_circle(12.0, Color(light_color.r, light_color.g, light_color.b, 0.9))
	marker.add_child(center_circle)

	# Inner glow
	var glow := _create_circle(6.0, Color(1, 1, 0.9, 0.8))
	marker.add_child(glow)

	# Label
	var label := Label.new()
	label.text = ltype.substr(0, 2).to_upper()
	label.position = Vector2(-8, -24)
	label.add_theme_font_size_override("font_size", 9)
	label.add_theme_color_override("font_color", Color(light_color.r, light_color.g, light_color.b, 1.0))
	marker.add_child(label)

	return marker


## Create a decoration marker in the editor.
func _create_decoration_marker(data: Dictionary) -> Node2D:
	var dtype: String = data.get("type", "rock")
	var props: Dictionary = DECORATION_TYPE_PROPS.get(dtype, DECORATION_TYPE_PROPS["rock"])
	var dw: float = props["w"]
	var dh: float = props["h"]

	var marker := Node2D.new()
	marker.position = Vector2(data["x"], data["y"])

	var visual := ColorRect.new()
	visual.position = Vector2(-dw / 2.0, -dh / 2.0)
	visual.size = Vector2(dw, dh)
	visual.color = props["color"]
	marker.add_child(visual)

	# Collision indicator (small border)
	if props.get("collision", false):
		var border := ColorRect.new()
		border.position = Vector2(-dw / 2.0 - 1, -dh / 2.0 - 1)
		border.size = Vector2(dw + 2, dh + 2)
		border.color = Color(1, 1, 1, 0.15)
		border.z_index = -1
		marker.add_child(border)

	# Label
	var label := Label.new()
	label.text = dtype.substr(0, 2).to_upper()
	label.position = Vector2(-8, -dh / 2.0 - 14)
	label.add_theme_font_size_override("font_size", 8)
	label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 0.6))
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
		Tool.TREE:
			tool_name = "Tree (%s)" % current_tree_type
		Tool.LIGHT:
			tool_name = "Light (%s)" % current_light_type
		Tool.DECORATION:
			tool_name = "Decor (%s)" % current_decoration_type

	var grid_str: String = "ON" if _show_grid else "OFF"
	var obj_count: int = (
		level_data.walls.size() + level_data.enemies.size() +
		level_data.cover_objects.size() + level_data.trees.size() +
		level_data.lights.size() + level_data.decorations.size()
	)
	_status_label.text = "Tool: %s | Grid: %s | Objects: %d" % [
		tool_name, grid_str, obj_count,
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


func _on_tree_type_selected(index: int) -> void:
	if index >= 0 and index < TREE_TYPE_NAMES.size():
		current_tree_type = TREE_TYPE_NAMES[index]
		_update_status()


func _on_light_type_selected(index: int) -> void:
	if index >= 0 and index < LIGHT_TYPE_NAMES.size():
		current_light_type = LIGHT_TYPE_NAMES[index]
		_update_status()


func _on_decoration_type_selected(index: int) -> void:
	if index >= 0 and index < DECORATION_TYPE_NAMES.size():
		current_decoration_type = DECORATION_TYPE_NAMES[index]
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
