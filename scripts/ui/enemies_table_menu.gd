extends CanvasLayer
## Enemies Table Menu — shows which unique enemy types appear on each map.
##
## Displays a read-only table with columns: Map, Rifle, Shotgun, UZI, Machete, Machine Gun.
## Follows the same programmatic UI pattern as UnlockTableMenu.
##
## Issue #1111: добавь таблицу уникальных врагов в experimental

## Signal emitted when the back button is pressed.
signal back_pressed

## Reference to the back button.
var _back_button: Button

## Reference to the table container.
var _table_container: VBoxContainer

## Level name mapping (scene path -> display name).
const LEVEL_NAMES: Dictionary = {
	"res://scenes/levels/LabyrinthLevel.tscn": "Labyrinth",
	"res://scenes/levels/BuildingLevel.tscn": "Building",
	"res://scenes/levels/CastleLevel.tscn": "Castle",
	"res://scenes/levels/BeachLevel.tscn": "Beach",
	"res://scenes/levels/DocksLevel.tscn": "Docks",
	"res://scenes/levels/Labyrinth2Level.tscn": "Labyrinth 2",
	"res://scenes/levels/CityLevel.tscn": "City",
	"res://scenes/levels/DecadenceLevel.tscn": "Decadence",
	"res://scenes/levels/TestTier.tscn": "Polygon",
	"res://scenes/levels/RevolverLevel.tscn": "Double Corridor",
	"res://scenes/levels/FactoryLevel.tscn": "Factory",
}

## Enemy counts per level: [Rifle, Shotgun, UZI, Machete, Machine Gun]
## Enemies without explicit weapon_type default to RIFLE (0).
const ENEMY_COUNTS: Dictionary = {
	"res://scenes/levels/LabyrinthLevel.tscn": [4, 1, 0, 0, 0],
	"res://scenes/levels/BuildingLevel.tscn": [9, 0, 1, 0, 0],
	"res://scenes/levels/CastleLevel.tscn": [2, 3, 8, 0, 0],
	"res://scenes/levels/BeachLevel.tscn": [2, 1, 0, 5, 0],
	"res://scenes/levels/DocksLevel.tscn": [9, 3, 6, 2, 0],
	"res://scenes/levels/Labyrinth2Level.tscn": [10, 2, 2, 0, 1],
	"res://scenes/levels/CityLevel.tscn": [5, 2, 2, 0, 0],
	"res://scenes/levels/DecadenceLevel.tscn": [7, 2, 0, 3, 0],
	"res://scenes/levels/TestTier.tscn": [10, 0, 0, 0, 0],
	"res://scenes/levels/RevolverLevel.tscn": [13, 0, 0, 0, 0],
	"res://scenes/levels/FactoryLevel.tscn": [13, 0, 0, 0, 0],
}


func _ready() -> void:
	# Build the entire UI programmatically
	_build_ui()

	# Set process mode to allow input while paused
	process_mode = Node.PROCESS_MODE_ALWAYS

	_log("EnemiesTableMenu ready")


## Build the complete UI layout.
func _build_ui() -> void:
	# Root container that fills the screen
	var root_control := Control.new()
	root_control.name = "MenuContainer"
	root_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root_control)

	# Semi-transparent background
	var bg := ColorRect.new()
	bg.name = "Background"
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.0, 0.0, 0.0, 0.75)
	root_control.add_child(bg)

	# Main panel
	var panel := PanelContainer.new()
	panel.name = "MainPanel"
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -480
	panel.offset_top = -320
	panel.offset_right = 480
	panel.offset_bottom = 320
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.12, 0.12, 0.15, 0.95)
	panel_style.corner_radius_top_left = 8
	panel_style.corner_radius_top_right = 8
	panel_style.corner_radius_bottom_left = 8
	panel_style.corner_radius_bottom_right = 8
	panel_style.border_color = Color(0.3, 0.3, 0.35, 1.0)
	panel_style.border_width_left = 1
	panel_style.border_width_right = 1
	panel_style.border_width_top = 1
	panel_style.border_width_bottom = 1
	panel.add_theme_stylebox_override("panel", panel_style)
	root_control.add_child(panel)

	# Margin inside panel
	var margin := MarginContainer.new()
	margin.layout_mode = 2
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)

	# Main vertical layout
	var main_vbox := VBoxContainer.new()
	main_vbox.layout_mode = 2
	main_vbox.add_theme_constant_override("separation", 12)
	margin.add_child(main_vbox)

	# Title with neon styling
	var title := Label.new()
	title.text = "ENEMIES TABLE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var neon_label_settings = load("res://resources/themes/neon_label_settings.tres")
	if neon_label_settings:
		title.label_settings = neon_label_settings
	else:
		title.add_theme_font_size_override("font_size", 22)
		title.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7, 1.0))
	main_vbox.add_child(title)

	# Description
	var desc := Label.new()
	desc.text = "Enemy types present on each map."
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.add_theme_font_size_override("font_size", 12)
	desc.add_theme_color_override("font_color", Color(0.6, 0.65, 0.7, 1.0))
	main_vbox.add_child(desc)

	# Separator
	var sep := HSeparator.new()
	main_vbox.add_child(sep)

	# Scroll container for table
	var scroll := ScrollContainer.new()
	scroll.layout_mode = 2
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	main_vbox.add_child(scroll)

	# Table container
	_table_container = VBoxContainer.new()
	_table_container.layout_mode = 2
	_table_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_table_container.add_theme_constant_override("separation", 0)
	scroll.add_child(_table_container)

	# Build table
	_populate_table()

	# Bottom separator
	var bottom_sep := HSeparator.new()
	main_vbox.add_child(bottom_sep)

	# Back button
	var button_hbox := HBoxContainer.new()
	button_hbox.layout_mode = 2
	button_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	main_vbox.add_child(button_hbox)

	_back_button = Button.new()
	_back_button.text = "Back"
	_back_button.custom_minimum_size = Vector2(140, 36)
	_back_button.pressed.connect(_on_back_pressed)
	button_hbox.add_child(_back_button)


## Populate the table with enemy data.
func _populate_table() -> void:
	# Clear existing rows
	for child in _table_container.get_children():
		child.queue_free()

	# Add header row
	_add_table_row("MAP", "Rifle", "Shotgun", "UZI", "Machete", "PKM", true)

	# Add a row for each level
	for scene_path in ENEMY_COUNTS:
		var level_name: String = LEVEL_NAMES.get(scene_path, _extract_level_name(scene_path))
		var counts: Array = ENEMY_COUNTS[scene_path]
		var rifle: int = counts[0]
		var shotgun: int = counts[1]
		var uzi: int = counts[2]
		var machete: int = counts[3]
		var machine_gun: int = counts[4]
		_add_table_row(level_name, _count_text(rifle), _count_text(shotgun), _count_text(uzi), _count_text(machete), _count_text(machine_gun))


## Convert count to display text: show count if > 0, dash otherwise.
func _count_text(count: int) -> String:
	if count > 0:
		return str(count)
	return "—"


## Add a row to the table.
func _add_table_row(map_text: String, rifle_text: String, shotgun_text: String, uzi_text: String, machete_text: String, pkm_text: String, is_header: bool = false) -> void:
	var row_panel := PanelContainer.new()
	row_panel.layout_mode = 2
	row_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var row_style := StyleBoxFlat.new()
	if is_header:
		row_style.bg_color = Color(0.2, 0.2, 0.25, 0.9)
	else:
		row_style.bg_color = Color(0.15, 0.15, 0.18, 0.7)
	row_style.content_margin_left = 12
	row_style.content_margin_right = 12
	row_style.content_margin_top = 8
	row_style.content_margin_bottom = 8
	row_panel.add_theme_stylebox_override("panel", row_style)
	_table_container.add_child(row_panel)

	var row_hbox := HBoxContainer.new()
	row_hbox.layout_mode = 2
	row_hbox.add_theme_constant_override("separation", 8)
	row_panel.add_child(row_hbox)

	# Map column
	var map_label := Label.new()
	map_label.text = map_text
	map_label.custom_minimum_size.x = 130
	map_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if is_header:
		map_label.add_theme_font_size_override("font_size", 14)
		map_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7, 1.0))
	else:
		map_label.add_theme_font_size_override("font_size", 13)
		map_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85, 1.0))
	row_hbox.add_child(map_label)

	# Enemy type columns
	var col_defs: Array[Dictionary] = [
		{"text": rifle_text, "color": Color(0.4, 0.7, 1.0, 1.0)},   # Rifle - blue
		{"text": shotgun_text, "color": Color(1.0, 0.6, 0.2, 1.0)}, # Shotgun - orange
		{"text": uzi_text, "color": Color(0.4, 1.0, 0.6, 1.0)},     # UZI - green
		{"text": machete_text, "color": Color(1.0, 0.3, 0.3, 1.0)}, # Machete - red
		{"text": pkm_text, "color": Color(1.0, 0.9, 0.2, 1.0)},     # PKM - gold
	]

	for col in col_defs:
		var label := Label.new()
		label.text = col["text"]
		label.custom_minimum_size.x = 64
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if is_header:
			label.add_theme_font_size_override("font_size", 14)
			label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7, 1.0))
		else:
			label.add_theme_font_size_override("font_size", 13)
			if col["text"] == "—":
				label.add_theme_color_override("font_color", Color(0.4, 0.4, 0.45, 1.0))
			else:
				label.add_theme_color_override("font_color", col["color"])
		row_hbox.add_child(label)


## Extract level name from scene path.
func _extract_level_name(path: String) -> String:
	var filename: String = path.get_file().get_basename()
	return filename.replace("Level", "").replace("_", " ")


## Refresh the table (called when menu is reopened).
func refresh() -> void:
	_populate_table()
	_log("EnemiesTableMenu refreshed")


func _on_back_pressed() -> void:
	back_pressed.emit()


## Log a message to the file logger if available.
func _log(message: String) -> void:
	var file_logger: Node = get_node_or_null("/root/FileLogger")
	if file_logger and file_logger.has_method("log_info"):
		file_logger.log_info("[EnemiesTableMenu] " + message)
	else:
		print("[EnemiesTableMenu] " + message)
