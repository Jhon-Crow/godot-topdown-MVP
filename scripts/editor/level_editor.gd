extends Node2D
## Grid-based level editor inspired by Hotline Miami 2's editor.
##
## Features:
## - Grid-based placement of walls, enemies, cover objects, and player spawn
## - Mouse cursor preview showing selected object
## - Right-click context menu for editing placed objects
## - All enemy types from the game spawner (9 weapons + special flags)
## - Undo support (Ctrl+Z)
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

## Enemy type definitions matching the game's spawner.
## weapon_type: 0=RIFLE, 1=SHOTGUN, 2=UZI, 3=MACHETE, 4=RPG, 5=PM,
##   6=MACHINE_GUN, 7=SNIPER_RIFLE, 8=REVOLVER
const ENEMY_TYPES: Array[Dictionary] = [
	{"name": "Rifle (M16)", "weapon_type": 0, "behavior": 1, "color": Color(0.8, 0.2, 0.2, 0.8)},
	{"name": "Shotgun", "weapon_type": 1, "behavior": 1, "color": Color(0.8, 0.5, 0.2, 0.8)},
	{"name": "UZI (SMG)", "weapon_type": 2, "behavior": 1, "color": Color(0.8, 0.8, 0.2, 0.8)},
	{"name": "Machete (melee)", "weapon_type": 3, "behavior": 1, "color": Color(0.9, 0.1, 0.1, 0.8)},
	{"name": "RPG + PM pistol", "weapon_type": 4, "behavior": 1, "color": Color(0.6, 0.2, 0.8, 0.8)},
	{"name": "PM (Makarov)", "weapon_type": 5, "behavior": 1, "color": Color(0.5, 0.5, 0.7, 0.8)},
	{"name": "Machine Gunner (PKM)", "weapon_type": 6, "behavior": 1, "color": Color(0.3, 0.6, 0.3, 0.8)},
	{"name": "Sniper (ASVK)", "weapon_type": 7, "behavior": 1, "color": Color(0.2, 0.4, 0.8, 0.8)},
	{"name": "SWAT Shieldbearer", "weapon_type": 8, "behavior": 1, "color": Color(0.4, 0.4, 0.6, 0.8),
		"has_swat_shield": true, "scene": "res://scenes/objects/EnemySwatShield.tscn"},
	{"name": "Patrol Rifle", "weapon_type": 0, "behavior": 0, "color": Color(0.7, 0.3, 0.3, 0.8)},
	{"name": "Teleporter", "weapon_type": 0, "behavior": 1, "color": Color(0.2, 0.8, 0.8, 0.8),
		"is_teleporter": true},
	{"name": "Armored Skin", "weapon_type": 0, "behavior": 1, "color": Color(0.6, 0.6, 0.2, 0.8),
		"has_armored_skin": true},
	{"name": "Force Field", "weapon_type": 0, "behavior": 1, "color": Color(0.2, 0.6, 0.8, 0.8),
		"has_force_field": true},
	{"name": "Grenadier", "weapon_type": 0, "behavior": 1, "color": Color(0.8, 0.4, 0.1, 0.8),
		"is_grenadier": true},
	{"name": "Invisible", "weapon_type": 0, "behavior": 1, "color": Color(0.5, 0.5, 0.5, 0.4),
		"start_invisible": true},
	{"name": "Gas Mask", "weapon_type": 0, "behavior": 1, "color": Color(0.4, 0.5, 0.3, 0.8),
		"is_gas_mask": true},
	{"name": "Drone Operator", "weapon_type": 0, "behavior": 1, "color": Color(0.3, 0.3, 0.7, 0.8),
		"is_drone_operator": true, "scene": "res://scenes/objects/EnemyDroneOperator.tscn"},
]

## Weapon type short labels for display on enemy markers.
const WEAPON_LABELS: Array[String] = [
	"RIF", "SHG", "UZI", "MCH", "RPG", "PM", "PKM", "SNP", "REV"
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

## Current enemy type index (into ENEMY_TYPES).
var current_enemy_type_idx: int = 0

## Current cover type selection.
var current_cover_type: String = "desk"

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

## Current mouse world position for cursor preview.
var _mouse_world_pos: Vector2 = Vector2.ZERO

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

## Enemy type selector reference.
var _enemy_type_option: OptionButton = null

## Cover type selector reference.
var _cover_type_option: OptionButton = null

## Context menu popup reference.
var _context_menu: PopupMenu = null

## Index of the object targeted by the context menu.
var _context_target_idx: int = -1

## Type of the object targeted by the context menu ("enemy", "cover", "wall").
var _context_target_type: String = ""

## The CanvasLayer for UI elements.
var _ui_layer: CanvasLayer = null

## UI panel width in pixels.
const UI_PANEL_WIDTH: int = 240


func _ready() -> void:
	if level_data == null:
		level_data = LevelData.new()

	_setup_camera()
	_setup_elements_node()
	_build_ui()
	_build_context_menu()
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
	_ui_layer = CanvasLayer.new()
	_ui_layer.name = "EditorUI"
	_ui_layer.layer = 10
	add_child(_ui_layer)

	# Left toolbar panel — use ScrollContainer for many controls
	_ui_panel = PanelContainer.new()
	_ui_panel.name = "ToolbarPanel"
	_ui_panel.offset_left = 0
	_ui_panel.offset_top = 0
	_ui_panel.offset_right = UI_PANEL_WIDTH
	_ui_panel.anchor_bottom = 1.0
	_ui_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.1, 0.1, 0.12, 0.94)
	panel_style.border_color = Color(0.3, 0.3, 0.35, 1.0)
	panel_style.border_width_right = 1
	_ui_panel.add_theme_stylebox_override("panel", panel_style)
	_ui_layer.add_child(_ui_panel)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_ui_panel.add_child(scroll)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "LEVEL EDITOR"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7, 1.0))
	vbox.add_child(title)

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

	vbox.add_child(HSeparator.new())

	# Tools section
	var tools_label := Label.new()
	tools_label.text = "Tools"
	tools_label.add_theme_font_size_override("font_size", 13)
	tools_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85, 1.0))
	vbox.add_child(tools_label)

	var tool_names: Array[String] = [
		"Wall [1]", "Enemy [2]", "Cover [3]", "Spawn [4]", "Eraser [5]", "Select [6]"
	]
	for i in range(tool_names.size()):
		var btn := Button.new()
		btn.text = tool_names[i]
		btn.custom_minimum_size = Vector2(0, 26)
		btn.pressed.connect(_on_tool_selected.bind(i))
		btn.name = "ToolBtn_%d" % i
		vbox.add_child(btn)

	vbox.add_child(HSeparator.new())

	# Enemy type selector
	var enemy_label := Label.new()
	enemy_label.text = "Enemy Type:"
	enemy_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(enemy_label)

	_enemy_type_option = OptionButton.new()
	_enemy_type_option.name = "EnemyTypeOption"
	for etype in ENEMY_TYPES:
		_enemy_type_option.add_item(etype["name"])
	_enemy_type_option.item_selected.connect(_on_enemy_type_selected)
	vbox.add_child(_enemy_type_option)

	# Cover type selector
	var cover_label := Label.new()
	cover_label.text = "Cover Type:"
	cover_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(cover_label)

	_cover_type_option = OptionButton.new()
	_cover_type_option.name = "CoverOption"
	for ctype in COVER_TYPE_NAMES:
		_cover_type_option.add_item(ctype.capitalize())
	_cover_type_option.item_selected.connect(_on_cover_type_selected)
	vbox.add_child(_cover_type_option)

	vbox.add_child(HSeparator.new())

	# Action buttons
	var actions_label := Label.new()
	actions_label.text = "Actions"
	actions_label.add_theme_font_size_override("font_size", 13)
	actions_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85, 1.0))
	vbox.add_child(actions_label)

	var action_btns: Array[Dictionary] = [
		{"text": "Undo [Ctrl+Z]", "callback": "_on_undo_pressed"},
		{"text": "Clear All", "callback": "_on_clear_pressed"},
		{"text": "Save Level", "callback": "_on_save_pressed"},
		{"text": "Load Level", "callback": "_on_load_pressed"},
		{"text": "Play Level", "callback": "_on_play_pressed"},
		{"text": "Export (Copy)", "callback": "_on_export_pressed"},
		{"text": "Import (Paste)", "callback": "_on_import_pressed"},
		{"text": "Back to Menu", "callback": "_on_back_pressed"},
	]
	for action in action_btns:
		var btn := Button.new()
		btn.text = action["text"]
		btn.custom_minimum_size = Vector2(0, 26)
		btn.pressed.connect(Callable(self, action["callback"]))
		vbox.add_child(btn)

	# Status bar at bottom-right
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
	_status_label.offset_left = UI_PANEL_WIDTH + 8
	_status_label.offset_bottom = -4
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_layer.add_child(_status_label)

	_update_status()


## Build the right-click context menu.
func _build_context_menu() -> void:
	_context_menu = PopupMenu.new()
	_context_menu.name = "ContextMenu"
	_context_menu.id_pressed.connect(_on_context_menu_id_pressed)
	add_child(_context_menu)


## Use _input instead of _unhandled_input to ensure editor receives mouse events
## even when autoloads or other systems might consume them first.
func _input(event: InputEvent) -> void:
	# Keyboard shortcuts
	if event is InputEventKey and event.pressed:
		# Ctrl+Z for undo
		if event.keycode == KEY_Z and event.ctrl_pressed:
			_on_undo_pressed()
			get_viewport().set_input_as_handled()
			return

		match event.keycode:
			KEY_1:
				_set_tool(Tool.WALL)
				get_viewport().set_input_as_handled()
			KEY_2:
				_set_tool(Tool.ENEMY)
				get_viewport().set_input_as_handled()
			KEY_3:
				_set_tool(Tool.COVER)
				get_viewport().set_input_as_handled()
			KEY_4:
				_set_tool(Tool.PLAYER_SPAWN)
				get_viewport().set_input_as_handled()
			KEY_5:
				_set_tool(Tool.ERASER)
				get_viewport().set_input_as_handled()
			KEY_6:
				_set_tool(Tool.SELECT)
				get_viewport().set_input_as_handled()
			KEY_G:
				_show_grid = not _show_grid
				_redraw_level()
				_update_status()
				get_viewport().set_input_as_handled()
			KEY_ESCAPE:
				if _is_drawing_wall:
					_is_drawing_wall = false
					queue_redraw()
				else:
					_on_back_pressed()
				get_viewport().set_input_as_handled()

	# Mouse input for placement
	if event is InputEventMouseButton:
		if _is_mouse_over_ui(event.position):
			return
		_handle_mouse_button(event)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)


## Check if a screen position is over the UI panel.
func _is_mouse_over_ui(screen_pos: Vector2) -> bool:
	return screen_pos.x < UI_PANEL_WIDTH


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
		match current_tool:
			Tool.WALL:
				if not _is_drawing_wall:
					_is_drawing_wall = true
					_wall_start = grid_pos
					_wall_current = grid_pos
				else:
					level_data.push_undo()
					_finish_wall()
			Tool.ENEMY:
				level_data.push_undo()
				_place_enemy(grid_pos)
			Tool.COVER:
				level_data.push_undo()
				_place_cover(grid_pos)
			Tool.PLAYER_SPAWN:
				level_data.push_undo()
				_place_player_spawn(grid_pos)
			Tool.ERASER:
				level_data.push_undo()
				_erase_at(world_pos)
			Tool.SELECT:
				pass

	# Right mouse button: cancel wall drawing or show context menu
	if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if _is_drawing_wall:
			_is_drawing_wall = false
			queue_redraw()
		else:
			_show_context_menu(event.position, world_pos)


## Handle mouse motion events.
func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	_mouse_world_pos = _screen_to_world(event.position)

	if _is_panning:
		_camera.position -= event.relative / _zoom_level
		return

	if _is_drawing_wall:
		_wall_current = LevelData.snap_to_grid(_mouse_world_pos)

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
	queue_redraw()


## Finish drawing a wall rectangle.
func _finish_wall() -> void:
	_is_drawing_wall = false
	var rect := _get_wall_rect(_wall_start, _wall_current)
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
	var etype: Dictionary = ENEMY_TYPES[current_enemy_type_idx]
	var enemy_data: Dictionary = {
		"x": pos.x,
		"y": pos.y,
		"weapon_type": etype["weapon_type"],
		"behavior": etype["behavior"],
	}
	# Copy special flags
	for key in ["is_teleporter", "has_armored_skin", "has_force_field",
			"is_grenadier", "start_invisible", "is_gas_mask",
			"is_drone_operator", "has_swat_shield", "scene"]:
		if etype.has(key):
			enemy_data[key] = etype[key]

	level_data.enemies.append(enemy_data)
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


## Show right-click context menu for the object under the cursor.
func _show_context_menu(screen_pos: Vector2, world_pos: Vector2) -> void:
	_context_menu.clear()
	_context_target_idx = -1
	_context_target_type = ""

	var hit_radius: float = 32.0

	# Check enemies first
	for i in range(level_data.enemies.size() - 1, -1, -1):
		var e: Dictionary = level_data.enemies[i]
		if world_pos.distance_to(Vector2(e["x"], e["y"])) < hit_radius:
			_context_target_idx = i
			_context_target_type = "enemy"
			var wt: int = e.get("weapon_type", 0)
			var wlabel: String = WEAPON_LABELS[wt] if wt < WEAPON_LABELS.size() else "?"
			_context_menu.add_item("Enemy: %s" % wlabel, -1)
			_context_menu.set_item_disabled(0, true)
			_context_menu.add_separator()
			# Add weapon type change submenu items
			for j in range(ENEMY_TYPES.size()):
				_context_menu.add_item("Change to: %s" % ENEMY_TYPES[j]["name"], 100 + j)
			_context_menu.add_separator()
			_context_menu.add_item("Delete", 1)
			_context_menu.position = Vector2i(int(screen_pos.x), int(screen_pos.y))
			_context_menu.popup()
			return

	# Check cover
	for i in range(level_data.cover_objects.size() - 1, -1, -1):
		var c: Dictionary = level_data.cover_objects[i]
		var center := Vector2(c["x"] + c["w"] / 2.0, c["y"] + c["h"] / 2.0)
		if world_pos.distance_to(center) < hit_radius + 16.0:
			_context_target_idx = i
			_context_target_type = "cover"
			var ctype: String = c.get("type", "crate")
			_context_menu.add_item("Cover: %s" % ctype.capitalize(), -1)
			_context_menu.set_item_disabled(0, true)
			_context_menu.add_separator()
			for j in range(COVER_TYPE_NAMES.size()):
				_context_menu.add_item("Change to: %s" % COVER_TYPE_NAMES[j].capitalize(), 200 + j)
			_context_menu.add_separator()
			_context_menu.add_item("Delete", 1)
			_context_menu.position = Vector2i(int(screen_pos.x), int(screen_pos.y))
			_context_menu.popup()
			return

	# Check walls
	for i in range(level_data.walls.size() - 1, -1, -1):
		var w: Dictionary = level_data.walls[i]
		var rect := Rect2(w["x"], w["y"], w["w"], w["h"])
		if rect.has_point(world_pos):
			_context_target_idx = i
			_context_target_type = "wall"
			_context_menu.add_item("Wall (%dx%d)" % [int(w["w"]), int(w["h"])], -1)
			_context_menu.set_item_disabled(0, true)
			_context_menu.add_separator()
			_context_menu.add_item("Delete", 1)
			_context_menu.position = Vector2i(int(screen_pos.x), int(screen_pos.y))
			_context_menu.popup()
			return


## Handle context menu selections.
func _on_context_menu_id_pressed(id: int) -> void:
	if _context_target_idx < 0:
		return

	level_data.push_undo()

	if id == 1:
		# Delete
		match _context_target_type:
			"enemy":
				if _context_target_idx < level_data.enemies.size():
					level_data.enemies.remove_at(_context_target_idx)
			"cover":
				if _context_target_idx < level_data.cover_objects.size():
					level_data.cover_objects.remove_at(_context_target_idx)
			"wall":
				if _context_target_idx < level_data.walls.size():
					level_data.walls.remove_at(_context_target_idx)
		_redraw_level()
		return

	# Change enemy type (IDs 100+)
	if id >= 100 and id < 200 and _context_target_type == "enemy":
		var new_type_idx: int = id - 100
		if new_type_idx < ENEMY_TYPES.size() and _context_target_idx < level_data.enemies.size():
			var e: Dictionary = level_data.enemies[_context_target_idx]
			var etype: Dictionary = ENEMY_TYPES[new_type_idx]
			e["weapon_type"] = etype["weapon_type"]
			e["behavior"] = etype["behavior"]
			# Clear old flags
			for key in ["is_teleporter", "has_armored_skin", "has_force_field",
					"is_grenadier", "start_invisible", "is_gas_mask",
					"is_drone_operator", "has_swat_shield", "scene"]:
				e.erase(key)
			# Set new flags
			for key in ["is_teleporter", "has_armored_skin", "has_force_field",
					"is_grenadier", "start_invisible", "is_gas_mask",
					"is_drone_operator", "has_swat_shield", "scene"]:
				if etype.has(key):
					e[key] = etype[key]
			_redraw_level()
		return

	# Change cover type (IDs 200+)
	if id >= 200 and id < 300 and _context_target_type == "cover":
		var new_type_idx: int = id - 200
		if new_type_idx < COVER_TYPE_NAMES.size() and _context_target_idx < level_data.cover_objects.size():
			var c: Dictionary = level_data.cover_objects[_context_target_idx]
			var new_type: String = COVER_TYPE_NAMES[new_type_idx]
			var new_size: Vector2 = COVER_TYPE_SIZES.get(new_type, Vector2(64, 64))
			c["type"] = new_type
			c["w"] = new_size.x
			c["h"] = new_size.y
			_redraw_level()
		return


## Redraw all level elements.
func _redraw_level() -> void:
	for child in _elements_node.get_children():
		child.queue_free()

	# Floor background
	var floor_rect := ColorRect.new()
	floor_rect.position = Vector2.ZERO
	floor_rect.size = Vector2(level_data.map_width, level_data.map_height)
	floor_rect.color = level_data.floor_color
	_elements_node.add_child(floor_rect)

	# Grid
	if _show_grid:
		_draw_grid()

	# Walls
	for w in level_data.walls:
		var wall_rect := ColorRect.new()
		wall_rect.position = Vector2(w["x"], w["y"])
		wall_rect.size = Vector2(w["w"], w["h"])
		wall_rect.color = level_data.wall_color
		_elements_node.add_child(wall_rect)

	# Cover objects
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
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_elements_node.add_child(label)

	# Enemies
	for e in level_data.enemies:
		var enemy_marker := _create_enemy_marker(e)
		_elements_node.add_child(enemy_marker)

	# Player spawn
	var spawn_marker := _create_spawn_marker(level_data.player_spawn)
	_elements_node.add_child(spawn_marker)

	_update_status()
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

	# Determine color from enemy type
	var wt: int = data.get("weapon_type", 0)
	var marker_color := Color(0.8, 0.2, 0.2, 0.8)
	for etype in ENEMY_TYPES:
		if etype["weapon_type"] == wt:
			# Match by flags too for special types
			var flags_match := true
			for flag in ["is_teleporter", "has_armored_skin", "has_force_field",
					"is_grenadier", "start_invisible", "is_gas_mask",
					"is_drone_operator", "has_swat_shield"]:
				if etype.has(flag) != data.has(flag):
					flags_match = false
					break
			if flags_match:
				marker_color = etype["color"]
				break

	var circle := _create_circle(16.0, marker_color)
	marker.add_child(circle)

	# Weapon label
	var label := Label.new()
	var wlabel: String = WEAPON_LABELS[wt] if wt < WEAPON_LABELS.size() else "?"
	label.text = wlabel
	label.position = Vector2(-12, -24)
	label.add_theme_font_size_override("font_size", 9)
	label.add_theme_color_override("font_color", Color(1, 0.8, 0.8, 1.0))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker.add_child(label)

	# Special flag indicators
	var flags_text := ""
	if data.get("is_teleporter", false):
		flags_text += "T"
	if data.get("has_armored_skin", false):
		flags_text += "A"
	if data.get("has_force_field", false):
		flags_text += "F"
	if data.get("is_grenadier", false):
		flags_text += "G"
	if data.get("start_invisible", false):
		flags_text += "I"
	if data.get("has_swat_shield", false):
		flags_text += "S"
	if data.get("is_gas_mask", false):
		flags_text += "M"
	if data.get("is_drone_operator", false):
		flags_text += "D"

	if not flags_text.is_empty():
		var flags_label := Label.new()
		flags_label.text = flags_text
		flags_label.position = Vector2(-12, 10)
		flags_label.add_theme_font_size_override("font_size", 8)
		flags_label.add_theme_color_override("font_color", Color(1, 1, 0.5, 0.8))
		flags_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		marker.add_child(flags_label)

	# Behavior indicator (patrol = yellow dot)
	if data.get("behavior", 1) == 0:
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
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
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


## Custom draw for grid, wall preview, and cursor preview.
func _draw() -> void:
	# Grid lines
	if _show_grid:
		var grid_color := Color(0.3, 0.3, 0.35, 0.15)
		var cell := LevelData.CELL_SIZE
		for x in range(0, level_data.map_width + 1, cell):
			draw_line(Vector2(x, 0), Vector2(x, level_data.map_height), grid_color, 1.0)
		for y in range(0, level_data.map_height + 1, cell):
			draw_line(Vector2(0, y), Vector2(level_data.map_width, y), grid_color, 1.0)

	# Map border
	var border_color := Color(0.6, 0.6, 0.65, 0.8)
	draw_rect(Rect2(0, 0, level_data.map_width, level_data.map_height), border_color, false, 2.0)

	# Wall preview while drawing
	if _is_drawing_wall:
		var rect := _get_wall_rect(_wall_start, _wall_current)
		draw_rect(rect, Color(0.5, 0.5, 0.6, 0.4), true)
		draw_rect(rect, Color(0.7, 0.7, 0.8, 0.8), false, 1.0)

	# Cursor preview — show what will be placed
	_draw_cursor_preview()


## Draw a preview of the selected tool at the mouse position.
func _draw_cursor_preview() -> void:
	var grid_pos := LevelData.snap_to_grid(_mouse_world_pos)
	var preview_alpha: float = 0.45

	match current_tool:
		Tool.WALL:
			if not _is_drawing_wall:
				var cell := LevelData.CELL_SIZE
				draw_rect(Rect2(grid_pos, Vector2(cell, cell)),
					Color(0.5, 0.5, 0.6, preview_alpha), true)
		Tool.ENEMY:
			var etype: Dictionary = ENEMY_TYPES[current_enemy_type_idx]
			var c: Color = etype.get("color", Color(0.8, 0.2, 0.2, 0.8))
			c.a = preview_alpha
			_draw_circle_at(grid_pos, 16.0, c)
			# Show weapon label
			var wt: int = etype.get("weapon_type", 0)
			var wlabel: String = WEAPON_LABELS[wt] if wt < WEAPON_LABELS.size() else "?"
			draw_string(ThemeDB.fallback_font, grid_pos + Vector2(-10, -18),
				wlabel, HORIZONTAL_ALIGNMENT_LEFT, -1, 9,
				Color(1, 0.8, 0.8, preview_alpha))
		Tool.COVER:
			var cover_size: Vector2 = COVER_TYPE_SIZES.get(current_cover_type, Vector2(64, 64))
			var c: Color = COVER_TYPE_COLORS.get(current_cover_type, Color(0.5, 0.45, 0.3, 1.0))
			c.a = preview_alpha
			draw_rect(Rect2(grid_pos, cover_size), c, true)
		Tool.PLAYER_SPAWN:
			_draw_circle_at(grid_pos, 18.0, Color(0.2, 0.8, 0.3, preview_alpha))
			draw_string(ThemeDB.fallback_font, grid_pos + Vector2(-4, 5),
				"P", HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
				Color(1, 1, 1, preview_alpha))
		Tool.ERASER:
			_draw_circle_at(_mouse_world_pos, 32.0, Color(1.0, 0.2, 0.2, 0.15))
			draw_arc(_mouse_world_pos, 32.0, 0, TAU, 24, Color(1, 0.3, 0.3, 0.5), 1.0)


## Draw a filled circle at a world position (for _draw).
func _draw_circle_at(pos: Vector2, radius: float, color: Color) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	var segments: int = 16
	for i in range(segments):
		var angle: float = TAU * i / segments
		points.append(pos + Vector2(cos(angle), sin(angle)) * radius)
	draw_colored_polygon(points, color)


## Update the status bar text.
func _update_status() -> void:
	if _status_label == null:
		return
	var tool_name: String = ""
	match current_tool:
		Tool.WALL:
			tool_name = "Wall"
		Tool.ENEMY:
			tool_name = "Enemy (%s)" % ENEMY_TYPES[current_enemy_type_idx]["name"]
		Tool.COVER:
			tool_name = "Cover (%s)" % current_cover_type
		Tool.PLAYER_SPAWN:
			tool_name = "Player Spawn"
		Tool.ERASER:
			tool_name = "Eraser"
		Tool.SELECT:
			tool_name = "Select"

	var grid_str: String = "ON" if _show_grid else "OFF"
	var undo_str: String = " | Undo: %d" % level_data._undo_stack.size() if level_data.can_undo() else ""
	_status_label.text = "Tool: %s | Grid: %s | W:%d E:%d C:%d%s" % [
		tool_name, grid_str,
		level_data.walls.size(),
		level_data.enemies.size(),
		level_data.cover_objects.size(),
		undo_str,
	]


## UI callbacks.
func _on_tool_selected(index: int) -> void:
	_set_tool(index as Tool)


func _on_enemy_type_selected(index: int) -> void:
	if index >= 0 and index < ENEMY_TYPES.size():
		current_enemy_type_idx = index
		_update_status()
		queue_redraw()


func _on_cover_type_selected(index: int) -> void:
	if index >= 0 and index < COVER_TYPE_NAMES.size():
		current_cover_type = COVER_TYPE_NAMES[index]
		_update_status()
		queue_redraw()


func _on_name_changed(new_text: String) -> void:
	level_data.level_name = new_text


func _on_undo_pressed() -> void:
	if level_data.pop_undo():
		if _name_input:
			_name_input.text = level_data.level_name
		_redraw_level()
		_show_notification("Undo")
	else:
		_show_notification("Nothing to undo")


func _on_clear_pressed() -> void:
	if level_data.walls.is_empty() and level_data.enemies.is_empty() and level_data.cover_objects.is_empty():
		_show_notification("Level is already empty")
		return
	level_data.push_undo()
	level_data.walls.clear()
	level_data.enemies.clear()
	level_data.cover_objects.clear()
	_redraw_level()
	_show_notification("Level cleared (Ctrl+Z to undo)")


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
	_on_save_pressed()

	var scene_loader: Node = get_node_or_null("/root/SceneLoader")
	var custom_level_path := "res://scenes/editor/CustomLevel.tscn"

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
		get_tree().create_timer(3.0).timeout.connect(_update_status)
