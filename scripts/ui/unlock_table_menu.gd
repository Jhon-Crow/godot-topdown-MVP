extends CanvasLayer
## Unlock table menu for viewing item unlock conditions.
##
## Displays a table showing under what conditions each item is unlocked:
## (map, completion rank, unlockable items). A bottom row shows items
## that are available from the start with no unlock condition.
##
## Issue #1002: добавь в experimental таблицу анлоков

## Signal emitted when the back button is pressed.
signal back_pressed

## Reference to the table content container (populated in _build_ui).
var _table_vbox: VBoxContainer = null

## Level display names mapped from scene paths.
## Must stay in sync with LevelsMenu.LEVELS and UnlockManager.UNLOCK_CONDITIONS.
const LEVEL_NAMES: Dictionary = {
	"res://scenes/levels/LabyrinthLevel.tscn": "Labyrinth",
	"res://scenes/levels/BuildingLevel.tscn": "Building",
	"res://scenes/levels/TestTier.tscn": "Polygon",
	"res://scenes/levels/CastleLevel.tscn": "Castle",
	"res://scenes/levels/RevolverLevel.tscn": "Double Corridor",
	"res://scenes/levels/CityLevel.tscn": "City",
	"res://scenes/levels/BeachLevel.tscn": "Beach",
	"res://scenes/levels/DocksLevel.tscn": "Docks"
}

## Rank display colors (same scheme as LevelsMenu._get_rank_color).
const RANK_COLORS: Dictionary = {
	"S":  Color(1.0, 0.85, 0.0, 1.0),
	"A+": Color(0.3, 1.0, 0.3, 1.0),
	"A":  Color(0.4, 0.9, 0.4, 1.0),
	"B":  Color(0.5, 0.8, 1.0, 1.0),
	"C":  Color(0.8, 0.8, 0.8, 1.0),
	"D":  Color(0.8, 0.5, 0.3, 1.0),
	"F":  Color(0.8, 0.3, 0.3, 1.0)
}


func _ready() -> void:
	_build_ui()
	process_mode = Node.PROCESS_MODE_ALWAYS


## Rebuild the table to reflect the latest unlock state.
## Call this each time the menu is shown so data stays current.
func refresh() -> void:
	if _table_vbox == null:
		return
	for child in _table_vbox.get_children():
		child.queue_free()
	# Wait one frame for queue_free to process, then rebuild
	await get_tree().process_frame
	_build_table(_table_vbox)


## Build the complete UI layout programmatically.
func _build_ui() -> void:
	# Root container
	var root_control := Control.new()
	root_control.name = "MenuContainer"
	root_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root_control)

	# Semi-transparent background
	var bg := ColorRect.new()
	bg.name = "Background"
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.0, 0.0, 0.0, 0.7)
	root_control.add_child(bg)

	# Main panel
	var panel := PanelContainer.new()
	panel.name = "MainPanel"
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -480
	panel.offset_top = -360
	panel.offset_right = 480
	panel.offset_bottom = 360
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

	var main_vbox := VBoxContainer.new()
	main_vbox.layout_mode = 2
	main_vbox.add_theme_constant_override("separation", 8)
	margin.add_child(main_vbox)

	# Title
	var title := Label.new()
	title.text = "UNLOCK TABLE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7, 1.0))
	main_vbox.add_child(title)

	var desc := Label.new()
	desc.text = "Items unlocked by completing levels at a minimum rank"
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.add_theme_font_size_override("font_size", 11)
	desc.add_theme_color_override("font_color", Color(0.5, 0.55, 0.6, 1.0))
	main_vbox.add_child(desc)

	var sep := HSeparator.new()
	main_vbox.add_child(sep)

	# Scrollable table area
	var scroll := ScrollContainer.new()
	scroll.layout_mode = 2
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	main_vbox.add_child(scroll)

	_table_vbox = VBoxContainer.new()
	_table_vbox.layout_mode = 2
	_table_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_table_vbox.add_theme_constant_override("separation", 4)
	scroll.add_child(_table_vbox)

	_build_table(_table_vbox)

	# Bottom buttons
	var bottom_sep := HSeparator.new()
	main_vbox.add_child(bottom_sep)

	var btn_hbox := HBoxContainer.new()
	btn_hbox.layout_mode = 2
	btn_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	main_vbox.add_child(btn_hbox)

	var back_button := Button.new()
	back_button.text = "Back"
	back_button.custom_minimum_size = Vector2(140, 36)
	back_button.pressed.connect(_on_back_pressed)
	btn_hbox.add_child(back_button)


## Build the table rows: header, one row per unlock condition, and an undistributed row.
func _build_table(parent: VBoxContainer) -> void:
	var unlock_manager: Node = get_node_or_null("/root/UnlockManager")

	# Header row
	_add_header_row(parent)

	# Rows for each level with unlock conditions
	var conditions: Dictionary = {}
	if unlock_manager and unlock_manager.get("UNLOCK_CONDITIONS") != null:
		conditions = unlock_manager.UNLOCK_CONDITIONS

	for level_path in conditions:
		var condition: Dictionary = conditions[level_path]
		var level_name: String = LEVEL_NAMES.get(level_path, level_path.get_file().get_basename())
		var min_rank: String = condition.get("min_rank", "D")

		var item_names: Array[String] = []
		item_names.append_array(_get_weapon_names(condition.get("weapons", [])))
		item_names.append_array(_get_grenade_names(condition.get("grenades", [])))
		item_names.append_array(_get_active_item_names(condition.get("active_items", [])))

		var condition_met: bool = false
		if unlock_manager and unlock_manager.has_method("is_level_condition_met"):
			condition_met = unlock_manager.is_level_condition_met(level_path)

		_add_condition_row(parent, level_name, min_rank, item_names, condition_met)

	# Separator before undistributed row
	var sep := HSeparator.new()
	parent.add_child(sep)

	# Undistributed row (items freely available from the start)
	_add_undistributed_row(parent)


## Add the column header row.
func _add_header_row(parent: VBoxContainer) -> void:
	var row := _make_row(Color(0.18, 0.2, 0.25, 0.9))
	parent.add_child(row)
	_add_cell(row, "MAP", 180, true, Color(0.7, 0.75, 0.8, 1.0))
	_add_cell(row, "MIN RANK", 90, true, Color(0.7, 0.75, 0.8, 1.0))
	_add_cell(row, "UNLOCKABLE ITEMS", 0, true, Color(0.7, 0.75, 0.8, 1.0), true)


## Add a row for a specific level's unlock condition.
func _add_condition_row(
		parent: VBoxContainer,
		level_name: String,
		min_rank: String,
		item_names: Array[String],
		condition_met: bool) -> void:
	var row_bg_color: Color = Color(0.15, 0.15, 0.18, 0.7) if not condition_met else Color(0.14, 0.2, 0.14, 0.8)
	var row := _make_row(row_bg_color)
	parent.add_child(row)

	var map_color: Color = Color(0.85, 0.85, 0.9, 1.0) if not condition_met else Color(0.55, 1.0, 0.55, 1.0)
	var map_text: String = level_name + (" ✓" if condition_met else "")
	_add_cell(row, map_text, 180, false, map_color)

	var rank_color: Color = RANK_COLORS.get(min_rank, Color(0.7, 0.7, 0.7, 1.0))
	_add_cell(row, min_rank, 90, false, rank_color)

	var items_text: String = ", ".join(item_names) if not item_names.is_empty() else "—"
	_add_cell(row, items_text, 0, false, Color(0.85, 0.85, 0.9, 1.0), true)


## Add the undistributed row showing items available from the start.
func _add_undistributed_row(parent: VBoxContainer) -> void:
	var row := _make_row(Color(0.12, 0.12, 0.15, 0.8))
	parent.add_child(row)

	_add_cell(row, "— (no condition)", 180, false, Color(0.45, 0.5, 0.55, 1.0))
	_add_cell(row, "Any", 90, false, Color(0.45, 0.5, 0.55, 1.0))

	var free_items: Array[String] = _get_free_items()
	var items_text: String = ", ".join(free_items) if not free_items.is_empty() else "—"
	_add_cell(row, items_text, 0, false, Color(0.55, 0.6, 0.65, 1.0), true)


## Create a styled row (HBoxContainer with margin and background panel).
## Returns the inner HBoxContainer to which cells are added.
## The returned node should be added directly to the parent VBoxContainer.
func _make_row(bg_color: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.layout_mode = 2
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 0)

	# Background panel
	var bg_panel := PanelContainer.new()
	bg_panel.layout_mode = 2
	bg_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	bg_panel.add_theme_stylebox_override("panel", style)
	row.add_child(bg_panel)

	# Inner HBoxContainer for cells (inside a margin)
	var inner_margin := MarginContainer.new()
	inner_margin.layout_mode = 2
	inner_margin.add_theme_constant_override("margin_left", 10)
	inner_margin.add_theme_constant_override("margin_top", 7)
	inner_margin.add_theme_constant_override("margin_right", 10)
	inner_margin.add_theme_constant_override("margin_bottom", 7)
	bg_panel.add_child(inner_margin)

	var inner := HBoxContainer.new()
	inner.name = "Cells"
	inner.layout_mode = 2
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 12)
	inner_margin.add_child(inner)

	# Store reference to inner container on the row so _add_cell can find it.
	row.set_meta("cells", inner)
	return row


## Add a label cell to a row.
## @param row: The HBoxContainer returned by _make_row.
## @param text: Cell text.
## @param min_width: Minimum width (0 = no minimum).
## @param bold: Whether to show as bold (larger font size).
## @param color: Font color.
## @param expand: Whether the cell should expand to fill remaining width.
func _add_cell(row: HBoxContainer, text: String, min_width: float, bold: bool, color: Color, expand: bool = false) -> void:
	var cells: HBoxContainer = row.get_meta("cells")

	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11 if bold else 12)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_ONLY
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if min_width > 0:
		label.custom_minimum_size.x = min_width
		label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	if expand:
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	cells.add_child(label)


## Get display names for weapon IDs.
func _get_weapon_names(weapon_ids: Array) -> Array[String]:
	var weapon_name_map: Dictionary = {
		"makarov_pm": "PM",
		"m16": "M16",
		"shotgun": "Shotgun",
		"mini_uzi": "Mini UZI",
		"silenced_pistol": "Silenced Pistol",
		"sniper": "ASVK",
		"revolver": "RSh-12",
		"ak_gl": "AK + GL"
	}
	var names: Array[String] = []
	for weapon_id in weapon_ids:
		names.append(weapon_name_map.get(weapon_id, weapon_id))
	return names


## Get display names for grenade type ints.
func _get_grenade_names(grenade_types: Array) -> Array[String]:
	var names: Array[String] = []
	var grenade_manager: Node = get_node_or_null("/root/GrenadeManager")
	for grenade_type in grenade_types:
		if grenade_manager and grenade_manager.has_method("get_grenade_data"):
			var gdata: Dictionary = grenade_manager.get_grenade_data(grenade_type)
			names.append(gdata.get("name", "Grenade %d" % grenade_type))
		else:
			var fallback: Dictionary = {0: "Flashbang", 1: "Frag", 2: "F-1", 3: "Aggression Gas"}
			names.append(fallback.get(grenade_type, "Grenade %d" % grenade_type))
	return names


## Get display names for active item type ints.
func _get_active_item_names(item_types: Array) -> Array[String]:
	var names: Array[String] = []
	var active_item_manager: Node = get_node_or_null("/root/ActiveItemManager")
	for item_type in item_types:
		if active_item_manager and active_item_manager.has_method("get_active_item_data"):
			var adata: Dictionary = active_item_manager.get_active_item_data(item_type)
			names.append(adata.get("name", "Item %d" % item_type))
		else:
			var fallback: Dictionary = {
				0: "None", 1: "Flashlight", 2: "Homing Bullets", 3: "Teleport Bracers",
				4: "BFF Pendant", 5: "Invisibility", 6: "Breaker Bullets",
				7: "Force Field", 8: "Trajectory Glasses", 9: "Laser Sight"
			}
			names.append(fallback.get(item_type, "Item %d" % item_type))
	return names


## Collect items that are freely available (no unlock condition).
## These are items that are unlocked by default and NOT listed in any unlock condition.
func _get_free_items() -> Array[String]:
	var free_items: Array[String] = []
	var unlock_manager: Node = get_node_or_null("/root/UnlockManager")

	# Collect condition-gated item IDs/types
	var gated_weapons: Array[String] = []
	var gated_grenades: Array[int] = []
	var gated_active_items: Array[int] = []
	if unlock_manager:
		if unlock_manager.has_method("get_weapons_with_conditions"):
			gated_weapons = unlock_manager.get_weapons_with_conditions()
		if unlock_manager.has_method("get_grenades_with_conditions"):
			gated_grenades = unlock_manager.get_grenades_with_conditions()
		if unlock_manager.has_method("get_active_items_with_conditions"):
			gated_active_items = unlock_manager.get_active_items_with_conditions()

	# Free weapons: default-unlocked and not condition-gated
	var weapon_name_map: Dictionary = {
		"makarov_pm": "PM", "m16": "M16", "shotgun": "Shotgun",
		"mini_uzi": "Mini UZI", "silenced_pistol": "Silenced Pistol",
		"sniper": "ASVK", "revolver": "RSh-12", "ak_gl": "AK + GL"
	}
	var game_manager: Node = get_node_or_null("/root/GameManager")
	if game_manager and game_manager.get("unlocked_weapons") != null:
		for weapon_id in game_manager.unlocked_weapons:
			if game_manager.unlocked_weapons[weapon_id] and weapon_id not in gated_weapons:
				free_items.append(weapon_name_map.get(weapon_id, weapon_id))

	# Free grenades: default-unlocked and not condition-gated
	var grenade_manager: Node = get_node_or_null("/root/GrenadeManager")
	if grenade_manager and grenade_manager.get("unlocked_grenades") != null:
		for grenade_type in grenade_manager.unlocked_grenades:
			if grenade_manager.unlocked_grenades[grenade_type] and grenade_type not in gated_grenades:
				if grenade_manager.has_method("get_grenade_data"):
					var gdata: Dictionary = grenade_manager.get_grenade_data(grenade_type)
					free_items.append(gdata.get("name", "Grenade %d" % grenade_type))

	# Free active items: default-unlocked, not condition-gated, and not NONE (type 0)
	var active_item_manager: Node = get_node_or_null("/root/ActiveItemManager")
	if active_item_manager and active_item_manager.get("unlocked_active_items") != null:
		for item_type in active_item_manager.unlocked_active_items:
			if item_type == 0:
				continue  # Skip NONE
			if active_item_manager.unlocked_active_items[item_type] and item_type not in gated_active_items:
				if active_item_manager.has_method("get_active_item_data"):
					var adata: Dictionary = active_item_manager.get_active_item_data(item_type)
					free_items.append(adata.get("name", "Item %d" % item_type))

	return free_items


func _on_back_pressed() -> void:
	back_pressed.emit()
