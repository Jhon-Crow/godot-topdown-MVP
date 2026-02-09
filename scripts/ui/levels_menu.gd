extends CanvasLayer
## Card-based level selection menu.
##
## Displays available levels as visual cards with preview colors, descriptions,
## enemy counts, and progress results (stars) for each difficulty mode.
## Replaces the simple button list with a more informative card layout.

## Signal emitted when the back button is pressed.
signal back_pressed

## Level metadata: name, scene path, description, preview color, enemy count.
const LEVELS: Array[Dictionary] = [
	{
		"name": "Labyrinth",
		"name_ru": "Лабиринт",
		"path": "res://scenes/levels/LabyrinthLevel.tscn",
		"description": "Labyrinth of technical rooms with narrow corridors and enclosed spaces.",
		"preview_color": Color(0.15, 0.15, 0.18, 1.0),
		"preview_accent": Color(0.3, 0.35, 0.4, 1.0),
		"enemy_count": 5,
		"map_size": "1920x1080"
	},
	{
		"name": "Building Level",
		"name_ru": "Здание",
		"path": "res://scenes/levels/BuildingLevel.tscn",
		"description": "Hotline Miami style building with interconnected rooms and corridors. Features a grenadier enemy.",
		"preview_color": Color(0.35, 0.25, 0.2, 1.0),
		"preview_accent": Color(0.6, 0.4, 0.3, 1.0),
		"enemy_count": 10,
		"map_size": "2400x2000"
	},
	{
		"name": "Polygon",
		"name_ru": "Полигон",
		"path": "res://scenes/levels/TestTier.tscn",
		"description": "Open training ground for testing weapons and practicing combat skills.",
		"preview_color": Color(0.2, 0.3, 0.2, 1.0),
		"preview_accent": Color(0.35, 0.5, 0.35, 1.0),
		"enemy_count": 5,
		"map_size": "1280x720"
	},
	{
		"name": "Castle",
		"name_ru": "Замок",
		"path": "res://scenes/levels/CastleLevel.tscn",
		"description": "Medieval fortress assault across a massive oval-shaped courtyard.",
		"preview_color": Color(0.25, 0.25, 0.35, 1.0),
		"preview_accent": Color(0.4, 0.4, 0.55, 1.0),
		"enemy_count": 15,
		"map_size": "6000x2560"
	},
	{
		"name": "Tutorial",
		"name_ru": "Обучение",
		"path": "res://scenes/levels/csharp/TestTier.tscn",
		"description": "Step-by-step training: movement, shooting, bolt-action, scope, grenades.",
		"preview_color": Color(0.2, 0.25, 0.3, 1.0),
		"preview_accent": Color(0.3, 0.45, 0.55, 1.0),
		"enemy_count": 4,
		"map_size": "1280x720"
	},
	{
		"name": "Beach",
		"name_ru": "Пляж",
		"path": "res://scenes/levels/BeachLevel.tscn",
		"description": "Outdoor beach environment with machete-wielding enemies and scattered cover.",
		"preview_color": Color(0.2, 0.6, 0.9, 1.0),
		"preview_accent": Color(0.85, 0.75, 0.55, 1.0),
		"enemy_count": 8,
		"map_size": "2400x2000"
	},
	{
		"name": "City",
		"name_ru": "Город",
		"path": "res://scenes/levels/CityLevel.tscn",
		"description": "Urban warfare with sniper enemies. Watch out for red laser sights!",
		"preview_color": Color(0.25, 0.22, 0.2, 1.0),
		"preview_accent": Color(0.4, 0.35, 0.3, 1.0),
		"enemy_count": 10,
		"map_size": "6000x5000"
	}
]

## Difficulty names in display order.
const DIFFICULTY_NAMES: Array[String] = ["Easy", "Normal", "Hard", "Power Fantasy"]

## Card dimensions.
const CARD_WIDTH: float = 220.0
const CARD_HEIGHT: float = 290.0

## Number of columns in the level grid (4 cards wide).
const GRID_COLUMNS: int = 4

## Reference to the back button.
var _back_button: Button

## Reference to the card container.
var _card_container: GridContainer

## Map of level cards by path for styling.
var _level_cards: Dictionary = {}


func _ready() -> void:
	# Build the entire UI programmatically (same approach as ArmoryMenu)
	_build_ui()

	# Set process mode to allow input while paused
	process_mode = Node.PROCESS_MODE_ALWAYS


## Build the complete card-based UI layout.
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
	bg.color = Color(0.0, 0.0, 0.0, 0.6)
	root_control.add_child(bg)

	# Main panel
	var panel := PanelContainer.new()
	panel.name = "MainPanel"
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -520
	panel.offset_top = -340
	panel.offset_right = 520
	panel.offset_bottom = 340
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
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	# Main vertical layout
	var main_vbox := VBoxContainer.new()
	main_vbox.layout_mode = 2
	main_vbox.add_theme_constant_override("separation", 8)
	margin.add_child(main_vbox)

	# Title
	var title := Label.new()
	title.text = "SELECT LEVEL"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7, 1.0))
	main_vbox.add_child(title)

	# Separator
	var sep := HSeparator.new()
	main_vbox.add_child(sep)

	# Scroll container for cards (vertical scrolling for grid layout)
	var scroll := ScrollContainer.new()
	scroll.layout_mode = 2
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	main_vbox.add_child(scroll)

	# Card container (grid layout, 4 columns)
	_card_container = GridContainer.new()
	_card_container.columns = GRID_COLUMNS
	_card_container.layout_mode = 2
	_card_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_card_container.add_theme_constant_override("h_separation", 12)
	_card_container.add_theme_constant_override("v_separation", 12)
	scroll.add_child(_card_container)

	# Populate cards
	_populate_level_cards()

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


## Populate the level cards.
func _populate_level_cards() -> void:
	# Clear existing cards
	for child in _card_container.get_children():
		child.queue_free()
	_level_cards.clear()

	# Get current scene path to highlight it
	var current_scene_path: String = ""
	var current_scene: Node = get_tree().current_scene
	if current_scene and current_scene.scene_file_path:
		current_scene_path = current_scene.scene_file_path

	# Create a card for each level
	for level_data in LEVELS:
		var level_path: String = level_data["path"]
		var is_current: bool = (level_path == current_scene_path)
		var card := _create_level_card(level_data, is_current)
		_card_container.add_child(card)
		_level_cards[level_path] = card


## Create a single level card.
func _create_level_card(level_data: Dictionary, is_current: bool) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = level_data["name"].replace(" ", "") + "Card"
	card.custom_minimum_size = Vector2(CARD_WIDTH, CARD_HEIGHT)

	# Card style
	var card_style := StyleBoxFlat.new()
	if is_current:
		card_style.bg_color = Color(0.2, 0.3, 0.2, 0.8)
		card_style.border_color = Color(0.4, 0.8, 0.4, 1.0)
		card_style.border_width_left = 2
		card_style.border_width_right = 2
		card_style.border_width_top = 2
		card_style.border_width_bottom = 2
	else:
		card_style.bg_color = Color(0.18, 0.18, 0.2, 0.8)
		card_style.border_color = Color(0.3, 0.3, 0.35, 0.6)
		card_style.border_width_left = 1
		card_style.border_width_right = 1
		card_style.border_width_top = 1
		card_style.border_width_bottom = 1
	card_style.corner_radius_top_left = 6
	card_style.corner_radius_top_right = 6
	card_style.corner_radius_bottom_left = 6
	card_style.corner_radius_bottom_right = 6
	card.add_theme_stylebox_override("panel", card_style)

	# Card content
	var vbox := VBoxContainer.new()
	vbox.layout_mode = 2
	vbox.add_theme_constant_override("separation", 4)
	card.add_child(vbox)

	# Level preview (colored rectangle with map info overlay)
	var preview_container := PanelContainer.new()
	preview_container.custom_minimum_size = Vector2(0, 80)

	var preview_style := StyleBoxFlat.new()
	var base_color: Color = level_data.get("preview_color", Color(0.2, 0.2, 0.3, 1.0))
	var accent_color: Color = level_data.get("preview_accent", Color(0.4, 0.4, 0.5, 1.0))
	preview_style.bg_color = base_color
	preview_style.corner_radius_top_left = 4
	preview_style.corner_radius_top_right = 4
	preview_container.add_theme_stylebox_override("panel", preview_style)
	vbox.add_child(preview_container)

	# Preview overlay with map size and enemy count
	var preview_vbox := VBoxContainer.new()
	preview_vbox.layout_mode = 2
	preview_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	preview_vbox.add_theme_constant_override("separation", 2)
	preview_container.add_child(preview_vbox)

	var map_size_label := Label.new()
	map_size_label.text = level_data.get("map_size", "")
	map_size_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	map_size_label.add_theme_font_size_override("font_size", 11)
	map_size_label.add_theme_color_override("font_color", accent_color)
	preview_vbox.add_child(map_size_label)

	var enemy_label := Label.new()
	var enemy_count: int = level_data.get("enemy_count", 0)
	enemy_label.text = "%d enemies" % enemy_count if enemy_count > 0 else "Training"
	enemy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	enemy_label.add_theme_font_size_override("font_size", 13)
	enemy_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.8, 0.9))
	preview_vbox.add_child(enemy_label)

	# Current level badge
	if is_current:
		var badge := Label.new()
		badge.text = "PLAYING"
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.add_theme_font_size_override("font_size", 10)
		badge.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4, 1.0))
		preview_vbox.add_child(badge)

	# Level name
	var display_name: String = level_data.get("name_ru", level_data["name"])
	var name_label := Label.new()
	name_label.text = display_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 15)
	if is_current:
		name_label.add_theme_color_override("font_color", Color(0.7, 1.0, 0.7, 1.0))
	else:
		name_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 1.0))
	vbox.add_child(name_label)

	# Description (wrapped)
	var desc_label := Label.new()
	desc_label.text = level_data.get("description", "")
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_label.add_theme_font_size_override("font_size", 10)
	desc_label.add_theme_color_override("font_color", Color(0.6, 0.65, 0.7, 1.0))
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc_label.custom_minimum_size.x = CARD_WIDTH - 20
	vbox.add_child(desc_label)

	# Progress results for all difficulties (shown as letter grades)
	var progress_manager: Node = get_node_or_null("/root/ProgressManager")
	var progress_vbox := VBoxContainer.new()
	progress_vbox.layout_mode = 2
	progress_vbox.add_theme_constant_override("separation", 1)
	vbox.add_child(progress_vbox)

	# Load custom font for grade display
	var grade_font := _load_grade_font()

	for difficulty_name in DIFFICULTY_NAMES:
		var row := HBoxContainer.new()
		row.layout_mode = 2
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 4)
		progress_vbox.add_child(row)

		var difficulty_label := Label.new()
		difficulty_label.text = difficulty_name + ":"
		difficulty_label.add_theme_font_size_override("font_size", 9)
		difficulty_label.add_theme_color_override("font_color", Color(0.5, 0.55, 0.6, 1.0))
		difficulty_label.custom_minimum_size.x = 80
		row.add_child(difficulty_label)

		var best_rank: String = ""
		if progress_manager and progress_manager.has_method("get_best_rank"):
			best_rank = progress_manager.get_best_rank(level_data["path"], difficulty_name)

		var grade_label := Label.new()
		grade_label.text = best_rank if not best_rank.is_empty() else "—"
		grade_label.add_theme_font_size_override("font_size", 14)
		if grade_font:
			grade_label.add_theme_font_override("font", grade_font)
		if best_rank.is_empty():
			grade_label.add_theme_color_override("font_color", Color(0.35, 0.35, 0.4, 1.0))
		else:
			grade_label.add_theme_color_override("font_color", _get_rank_color(best_rank))
		grade_label.custom_minimum_size.x = 25
		row.add_child(grade_label)

	# Make card clickable (unless it's the current level)
	if not is_current:
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.gui_input.connect(_on_card_gui_input.bind(level_data["path"]))
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		card.tooltip_text = "Click to load %s" % display_name
	else:
		card.tooltip_text = "Currently playing this level"

	return card


## Load custom font for grade display.
func _load_grade_font() -> Font:
	var font_path := "res://addons/gut/fonts/LobsterTwo-Bold.ttf"
	if ResourceLoader.exists(font_path):
		var font_file := FontFile.new()
		font_file.data = FileAccess.get_file_as_bytes(font_path)
		return font_file
	return null


## Get color for a rank display.
func _get_rank_color(rank: String) -> Color:
	match rank:
		"S":
			return Color(1.0, 0.85, 0.0, 1.0)   # Gold
		"A+":
			return Color(0.3, 1.0, 0.3, 1.0)     # Bright green
		"A":
			return Color(0.4, 0.9, 0.4, 1.0)     # Green
		"B":
			return Color(0.5, 0.8, 1.0, 1.0)     # Light blue
		"C":
			return Color(0.8, 0.8, 0.8, 1.0)     # Light gray
		"D":
			return Color(0.8, 0.5, 0.3, 1.0)     # Orange
		"F":
			return Color(0.8, 0.3, 0.3, 1.0)     # Red
		_:
			return Color(0.7, 0.7, 0.7, 1.0)     # Gray


## Handle click on a level card.
func _on_card_gui_input(event: InputEvent, level_path: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_level_selected(level_path)


## Load the selected level.
func _on_level_selected(level_path: String) -> void:
	# Unpause the game before changing scene
	get_tree().paused = false

	# Restore hidden cursor for gameplay (confined and hidden)
	Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED_HIDDEN)

	# Change to the selected level
	var error := get_tree().change_scene_to_file(level_path)
	if error != OK:
		get_tree().paused = true
		# Show cursor again for menu interaction if error
		Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED)


func _on_back_pressed() -> void:
	back_pressed.emit()
