extends CanvasLayer
## Unlock Table Menu — shows which items are unlocked on which map and at what rank.
##
## Displays a read-only table with columns: Map, Min Rank, Unlockable Items.
## Items without conditions are shown in an "Unallocated" row at the bottom.
## Follows the same programmatic UI pattern as LevelsMenu and ArmoryMenu.
##
## Issue #1002: добавь в experimental таблицу анлоков

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
	"res://scenes/levels/TestTier.tscn": "Polygon",
	"res://scenes/levels/CastleLevel.tscn": "Castle",
	"res://scenes/levels/RevolverLevel.tscn": "Double Corridor",
	"res://scenes/levels/BeachLevel.tscn": "Beach",
	"res://scenes/levels/DocksLevel.tscn": "Docks",
	"res://scenes/levels/CityLevel.tscn": "City",
	"res://scenes/levels/DecadenceLevel.tscn": "Decadence",
	"res://scenes/levels/FactoryLevel.tscn": "Factory",
	"res://scenes/levels/Labyrinth2Level.tscn": "Labyrinth Complex",
	"res://scenes/levels/SewerLevel.tscn": "Sewer",
	"res://scenes/levels/RailwayStationLevel.tscn": "Railway Station",
	"res://scenes/levels/WinterForestLevel.tscn": "Winter Forest"
}

## Weapon ID to display name mapping.
const WEAPON_NAMES: Dictionary = {
	"makarov_pm": "PM",
	"m16": "M16",
	"shotgun": "Shotgun",
	"mini_uzi": "Mini UZI",
	"silenced_pistol": "Silenced Pistol",
	"sniper": "ASVK",
	"revolver": "RSh-12",
	"ak_gl": "AK + GL"
}

## Active item type to display name mapping.
const ACTIVE_ITEM_NAMES: Dictionary = {
	0: "None",
	1: "Flashlight",
	2: "Homing Bullets",
	3: "Teleport Bracers",
	4: "BFF Pendant",
	5: "Invisibility Suit",
	6: "Breaker Bullets",
	7: "Force Field",
	8: "Trajectory Glasses",
	9: "Laser Sight",
	10: "Extended Magazine",
	11: "Loudspeaker",
	12: "Breaching Charges",
	13: "Armored Skin",
	14: "Auto-Reload",
	15: "Drilling Bullets",
	16: "Recoil Compensator",
	17: "Combat Disposition",
	18: "Experimental Sample",
	19: "Fine Motor Skills",
	20: "Dash",
	21: "Grenade Bag"
}

## Grenade type to display name mapping.
const GRENADE_NAMES: Dictionary = {
	0: "Flashbang",
	1: "Frag Grenade",
	2: "F-1 Grenade",
	3: "Aggression Gas",
	4: "Drone"
}


func _ready() -> void:
	# Build the entire UI programmatically
	_build_ui()

	# Set process mode to allow input while paused
	process_mode = Node.PROCESS_MODE_ALWAYS

	_log("UnlockTableMenu ready")


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
	panel.offset_left = -450
	panel.offset_top = -300
	panel.offset_right = 450
	panel.offset_bottom = 300
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
	title.text = "UNLOCK TABLE"
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
	desc.text = "Items are unlocked by completing levels at the required rank or better, or by meeting kill milestones."
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


## Populate the table with unlock data.
func _populate_table() -> void:
	# Clear existing rows
	for child in _table_container.get_children():
		child.queue_free()

	# Add header row
	_add_table_row("MAP", "MIN RANK", "UNLOCKABLE ITEMS", true)

	# Get unlock conditions from UnlockManager
	var unlock_manager: Node = get_node_or_null("/root/UnlockManager")
	if unlock_manager == null:
		_add_message_row("UnlockManager not found")
		return

	# Get UNLOCK_CONDITIONS from UnlockManager
	var unlock_conditions: Dictionary = {}
	if "UNLOCK_CONDITIONS" in unlock_manager:
		unlock_conditions = unlock_manager.UNLOCK_CONDITIONS

	if unlock_conditions.is_empty():
		_add_message_row("No unlock conditions defined")
		return

	# Track which items have conditions
	var weapons_with_conditions: Array[String] = []
	var grenades_with_conditions: Array[int] = []
	var active_items_with_conditions: Array[int] = []

	# Add a row for each condition key (may include rank-suffix keys like "Path:S")
	for condition_key in unlock_conditions:
		var condition: Dictionary = unlock_conditions[condition_key]
		# Extract the actual scene path (strip rank suffix if present)
		var scene_path: String = condition_key
		if unlock_manager.has_method("_extract_scene_path"):
			scene_path = unlock_manager._extract_scene_path(condition_key)
		var level_name: String = LEVEL_NAMES.get(scene_path, _extract_level_name(scene_path))
		var min_rank: String = condition.get("min_rank", "D")

		# Build items list
		var items_list: Array[String] = []

		# Weapons
		for weapon_id in condition.get("weapons", []):
			var weapon_name: String = WEAPON_NAMES.get(weapon_id, weapon_id)
			items_list.append(weapon_name)
			if weapon_id not in weapons_with_conditions:
				weapons_with_conditions.append(weapon_id)

		# Grenades
		for grenade_type in condition.get("grenades", []):
			var grenade_name: String = GRENADE_NAMES.get(grenade_type, "Grenade %d" % grenade_type)
			items_list.append(grenade_name)
			if grenade_type not in grenades_with_conditions:
				grenades_with_conditions.append(grenade_type)

		# Active items
		for item_type in condition.get("active_items", []):
			var item_name: String = ACTIVE_ITEM_NAMES.get(item_type, "Item %d" % item_type)
			items_list.append(item_name)
			if item_type not in active_items_with_conditions:
				active_items_with_conditions.append(item_type)

		# Check if condition is met (show green checkmark)
		var condition_met: bool = false
		if unlock_manager.has_method("is_condition_key_met"):
			condition_met = unlock_manager.is_condition_key_met(condition_key)

		var level_display: String = level_name
		if condition_met:
			level_display = level_name + " ✓"

		_add_table_row(level_display, min_rank, ", ".join(items_list), false, condition_met)

	# Add rows for multi-level conditions
	var multi_unlock_conditions: Array = []
	if "MULTI_UNLOCK_CONDITIONS" in unlock_manager:
		multi_unlock_conditions = unlock_manager.MULTI_UNLOCK_CONDITIONS

	for multi_condition in multi_unlock_conditions:
		var levels_list: Array[String] = []
		for level_entry in multi_condition.get("levels", []):
			var entry_path: String = level_entry.get("path", "")
			var entry_rank: String = level_entry.get("min_rank", "S")
			var entry_name: String = LEVEL_NAMES.get(entry_path, _extract_level_name(entry_path))
			levels_list.append(entry_name + " " + entry_rank)
		var map_display: String = " + ".join(levels_list)

		var items_list: Array[String] = []
		for weapon_id in multi_condition.get("weapons", []):
			var weapon_name: String = WEAPON_NAMES.get(weapon_id, weapon_id)
			items_list.append(weapon_name)
			if weapon_id not in weapons_with_conditions:
				weapons_with_conditions.append(weapon_id)
		for grenade_type in multi_condition.get("grenades", []):
			var grenade_name: String = GRENADE_NAMES.get(grenade_type, "Grenade %d" % grenade_type)
			items_list.append(grenade_name)
			if grenade_type not in grenades_with_conditions:
				grenades_with_conditions.append(grenade_type)
		for item_type in multi_condition.get("active_items", []):
			var item_name: String = ACTIVE_ITEM_NAMES.get(item_type, "Item %d" % item_type)
			items_list.append(item_name)
			if item_type not in active_items_with_conditions:
				active_items_with_conditions.append(item_type)

		var condition_met: bool = false
		if unlock_manager.has_method("is_multi_condition_met"):
			condition_met = unlock_manager.is_multi_condition_met(multi_condition)

		if condition_met:
			map_display = map_display + " ✓"

		_add_table_row(map_display, "All S", ", ".join(items_list), false, condition_met)

	# Add rows for kill-based conditions
	var kill_unlock_conditions: Array = []
	if "KILL_UNLOCK_CONDITIONS" in unlock_manager:
		kill_unlock_conditions = unlock_manager.KILL_UNLOCK_CONDITIONS

	for kill_condition in kill_unlock_conditions:
		var stat: String = kill_condition.get("stat", "")
		var min_kills: int = kill_condition.get("min_kills", 0)

		# Current progress from GameManager
		var game_manager: Node = get_node_or_null("/root/GameManager")
		var current_kills: int = 0
		if game_manager and stat != "":
			current_kills = game_manager.get(stat) if game_manager.get(stat) != null else 0

		var map_display: String
		if stat == "shots_fired_special_weapons":
			map_display = "%d / %d shots (shotgun/ASVK/revolver)" % [current_kills, min_kills]
		elif stat == "total_deaths":
			map_display = "%d / %d deaths" % [current_kills, min_kills]
		elif stat == "no_damage_levels_completed":
			map_display = "%d / %d levels without damage" % [current_kills, min_kills]
		elif stat == "levels_completed_rank_a_or_higher":
			map_display = "%d / %d levels at rank A or higher" % [current_kills, min_kills]
		elif stat == "levels_completed_rank_s":
			map_display = "%d / %d levels at rank S" % [current_kills, min_kills]
		elif stat == "kills_through_wall":
			map_display = "%d / %d kills through walls" % [current_kills, min_kills]
		else:
			map_display = "%d / %d kills (no Laser Sight)" % [current_kills, min_kills]

		var items_list: Array[String] = []
		for weapon_id in kill_condition.get("weapons", []):
			var weapon_name: String = WEAPON_NAMES.get(weapon_id, weapon_id)
			items_list.append(weapon_name)
			if weapon_id not in weapons_with_conditions:
				weapons_with_conditions.append(weapon_id)
		for grenade_type in kill_condition.get("grenades", []):
			var grenade_name: String = GRENADE_NAMES.get(grenade_type, "Grenade %d" % grenade_type)
			items_list.append(grenade_name)
			if grenade_type not in grenades_with_conditions:
				grenades_with_conditions.append(grenade_type)
		for item_type in kill_condition.get("active_items", []):
			var item_name: String = ACTIVE_ITEM_NAMES.get(item_type, "Item %d" % item_type)
			items_list.append(item_name)
			if item_type not in active_items_with_conditions:
				active_items_with_conditions.append(item_type)

		var condition_met: bool = false
		if unlock_manager.has_method("is_kill_condition_met"):
			condition_met = unlock_manager.is_kill_condition_met(kill_condition)

		if condition_met:
			map_display = map_display + " ✓"

		_add_table_row(map_display, "—", ", ".join(items_list), false, condition_met)

	# Add rows for all-difficulties conditions
	var all_diff_unlock_conditions: Array = []
	if "ALL_DIFFICULTIES_UNLOCK_CONDITIONS" in unlock_manager:
		all_diff_unlock_conditions = unlock_manager.ALL_DIFFICULTIES_UNLOCK_CONDITIONS

	for all_diff_condition in all_diff_unlock_conditions:
		var items_list: Array[String] = []
		for weapon_id in all_diff_condition.get("weapons", []):
			var weapon_name: String = WEAPON_NAMES.get(weapon_id, weapon_id)
			items_list.append(weapon_name)
			if weapon_id not in weapons_with_conditions:
				weapons_with_conditions.append(weapon_id)
		for grenade_type in all_diff_condition.get("grenades", []):
			var grenade_name: String = GRENADE_NAMES.get(grenade_type, "Grenade %d" % grenade_type)
			items_list.append(grenade_name)
			if grenade_type not in grenades_with_conditions:
				grenades_with_conditions.append(grenade_type)
		for item_type in all_diff_condition.get("active_items", []):
			var item_name: String = ACTIVE_ITEM_NAMES.get(item_type, "Item %d" % item_type)
			items_list.append(item_name)
			if item_type not in active_items_with_conditions:
				active_items_with_conditions.append(item_type)

		var condition_met: bool = false
		if unlock_manager.has_method("is_all_difficulties_condition_met"):
			condition_met = unlock_manager.is_all_difficulties_condition_met()

		var map_display: String = "1 level per difficulty"
		if condition_met:
			map_display = map_display + " ✓"

		_add_table_row(map_display, "Any", ", ".join(items_list), false, condition_met)

	# Add separator before unallocated items
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 8)
	_table_container.add_child(sep)

	# Add unallocated items row (items without unlock conditions - available from start)
	var unallocated_items: Array[String] = []

	# Find weapons without conditions
	for weapon_id in WEAPON_NAMES:
		if weapon_id not in weapons_with_conditions:
			unallocated_items.append(WEAPON_NAMES[weapon_id])

	# Find grenades without conditions (all grenades are available from start in this game)
	for grenade_type in GRENADE_NAMES:
		if grenade_type not in grenades_with_conditions:
			unallocated_items.append(GRENADE_NAMES[grenade_type])

	# Find active items without conditions (skip NONE = 0)
	for item_type in ACTIVE_ITEM_NAMES:
		if item_type == 0:
			continue  # Skip the "None" slot
		if item_type not in active_items_with_conditions:
			var item_name: String = ACTIVE_ITEM_NAMES[item_type]
			if item_name not in unallocated_items:
				unallocated_items.append(item_name)

	if not unallocated_items.is_empty():
		_add_table_row("— (no condition)", "Any", ", ".join(unallocated_items), false, true)


## Add a row to the table.
func _add_table_row(map_text: String, rank_text: String, items_text: String, is_header: bool, condition_met: bool = false) -> void:
	var row := HBoxContainer.new()
	row.layout_mode = 2
	row.add_theme_constant_override("separation", 8)

	# Row background style
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
	row_hbox.add_theme_constant_override("separation", 16)
	row_panel.add_child(row_hbox)

	# Map column (width: 150)
	var map_label := Label.new()
	map_label.text = map_text
	map_label.custom_minimum_size.x = 150
	if is_header:
		map_label.add_theme_font_size_override("font_size", 14)
		map_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7, 1.0))
	else:
		map_label.add_theme_font_size_override("font_size", 13)
		if condition_met:
			map_label.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4, 1.0))
		else:
			map_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85, 1.0))
	row_hbox.add_child(map_label)

	# Min Rank column (width: 80)
	var rank_label := Label.new()
	rank_label.text = rank_text
	rank_label.custom_minimum_size.x = 80
	rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if is_header:
		rank_label.add_theme_font_size_override("font_size", 14)
		rank_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7, 1.0))
	else:
		rank_label.add_theme_font_size_override("font_size", 13)
		rank_label.add_theme_color_override("font_color", _get_rank_color(rank_text))
	row_hbox.add_child(rank_label)

	# Items column (fills remaining space)
	var items_label := Label.new()
	items_label.text = items_text
	items_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	items_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if is_header:
		items_label.add_theme_font_size_override("font_size", 14)
		items_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7, 1.0))
	else:
		items_label.add_theme_font_size_override("font_size", 12)
		items_label.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8, 1.0))
	row_hbox.add_child(items_label)


## Add a message row (for errors).
func _add_message_row(message: String) -> void:
	var label := Label.new()
	label.text = message
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color(0.8, 0.4, 0.4, 1.0))
	_table_container.add_child(label)


## Extract level name from scene path.
func _extract_level_name(path: String) -> String:
	var filename: String = path.get_file().get_basename()
	return filename.replace("Level", "").replace("_", " ")


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
		"Any":
			return Color(0.5, 0.8, 0.5, 1.0)     # Light green
		_:
			return Color(0.7, 0.7, 0.7, 1.0)     # Gray


## Refresh the table (called when menu is reopened).
func refresh() -> void:
	_populate_table()
	_log("UnlockTableMenu refreshed")


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause"):
		_on_back_pressed()
		get_viewport().set_input_as_handled()


func _on_back_pressed() -> void:
	back_pressed.emit()


## Log a message to the file logger if available.
func _log(message: String) -> void:
	var file_logger: Node = get_node_or_null("/root/FileLogger")
	if file_logger and file_logger.has_method("log_info"):
		file_logger.log_info("[UnlockTableMenu] " + message)
	else:
		print("[UnlockTableMenu] " + message)
