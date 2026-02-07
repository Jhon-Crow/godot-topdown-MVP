extends CanvasLayer
## Armory menu for selecting weapons, grenades, and active items by category.
##
## Layout: left sidebar with stats/description, right area with weapon/grenade/active item grids.
## Items fit on screen without scrolling. An accordion toggle expands the grid
## if there are too many items. An "Apply" button confirms the selection
## and restarts the level (no immediate restart on click).

## Signal emitted when the back button is pressed.
signal back_pressed

## Signal emitted when a weapon is selected.
signal weapon_selected(weapon_id: String)

## Firearms data — weapons the player can equip.
## Keys: weapon_id, Values: dictionary with name, icon_path, unlocked, description
const FIREARMS: Dictionary = {
	"m16": {
		"name": "M16",
		"icon_path": "res://assets/sprites/weapons/m16_rifle.png",
		"unlocked": true,
		"description": "Standard assault rifle with auto/burst modes, red laser sight"
	},
	"shotgun": {
		"name": "Shotgun",
		"icon_path": "res://assets/sprites/weapons/shotgun_icon.png",
		"unlocked": true,
		"description": "Pump-action shotgun — shell-by-shell loading, multi-pellet spread"
	},
	"mini_uzi": {
		"name": "Mini UZI",
		"icon_path": "res://assets/sprites/weapons/mini_uzi_icon.png",
		"unlocked": true,
		"description": "High fire rate SMG — progressive spread, ricochets at shallow angles"
	},
	"silenced_pistol": {
		"name": "Silenced Pistol",
		"icon_path": "res://assets/sprites/weapons/silenced_pistol_icon.png",
		"unlocked": true,
		"description": "Beretta M9 with suppressor — silent, stuns enemies on hit"
	},
	"sniper": {
		"name": "ASVK",
		"icon_path": "res://assets/sprites/weapons/asvk_topdown.png",
		"unlocked": true,
		"description": "ASVK anti-materiel sniper rifle - 12.7x108mm, 50 damage, penetrates 2 walls and enemies, bolt-action (Down→Left→Down→Up). 5-round magazine. RMB to scope (mouse wheel to zoom)."
	},
	"ak47": {
		"name": "???",
		"icon_path": "",
		"unlocked": false,
		"description": "Coming soon"
	},
	"smg": {
		"name": "???",
		"icon_path": "",
		"unlocked": false,
		"description": "Coming soon"
	},
	"pistol": {
		"name": "???",
		"icon_path": "",
		"unlocked": false,
		"description": "Coming soon"
	}
}

## Mapping from weapon_id to .tres resource path for loading stats.
const WEAPON_RESOURCE_PATHS: Dictionary = {
	"m16": "res://resources/weapons/AssaultRifleData.tres",
	"shotgun": "res://resources/weapons/ShotgunData.tres",
	"mini_uzi": "res://resources/weapons/MiniUziData.tres",
	"silenced_pistol": "res://resources/weapons/SilencedPistolData.tres",
	"sniper": "res://resources/weapons/SniperRifleData.tres"
}

## Maximum number of visible weapon rows before accordion hides the rest.
const MAX_WEAPON_ROWS_COLLAPSED: int = 2

## Maximum number of visible grenade rows before accordion hides the rest.
const MAX_GRENADE_ROWS_COLLAPSED: int = 1

## Number of columns in the weapon/grenade grids.
const GRID_COLUMNS: int = 4

## Maximum number of visible active item rows before accordion hides the rest.
const MAX_ACTIVE_ITEM_ROWS_COLLAPSED: int = 1

## Reference to UI elements — created in code.
var _weapon_grid: GridContainer
var _grenade_grid: GridContainer
var _active_item_grid: GridContainer
var _weapon_stats_label: RichTextLabel
var _grenade_stats_label: RichTextLabel
var _active_item_stats_label: RichTextLabel
var _back_button: Button
var _apply_button: Button
var _weapon_accordion_button: Button
var _grenade_accordion_button: Button
var _active_item_accordion_button: Button

## Currently pending weapon selection (not yet applied).
var _pending_weapon_id: String = ""

## Currently pending grenade selection (not yet applied).
var _pending_grenade_type: int = -1

## Currently pending active item selection (not yet applied).
var _pending_active_item_type: int = -1

## Whether the weapon grid is expanded (accordion open).
var _weapons_expanded: bool = false

## Whether the grenade grid is expanded (accordion open).
var _grenades_expanded: bool = false

## Whether the active item grid is expanded (accordion open).
var _active_items_expanded: bool = false

## Map of weapon slots by weapon ID.
var _weapon_slots: Dictionary = {}

## Map of grenade slots by grenade type.
var _grenade_slots: Dictionary = {}

## Map of active item slots by active item type.
var _active_item_slots: Dictionary = {}

## Reference to GrenadeManager autoload.
var _grenade_manager: Node = null

## Reference to ActiveItemManager autoload.
var _active_item_manager: Node = null

## Cached weapon resource data.
var _weapon_resources: Dictionary = {}

## Overflow weapon slots (hidden when collapsed).
var _weapon_overflow_slots: Array = []

## Overflow grenade slots (hidden when collapsed).
var _grenade_overflow_slots: Array = []

## Overflow active item slots (hidden when collapsed).
var _active_item_overflow_slots: Array = []


func _ready() -> void:
	# Get GrenadeManager reference
	_grenade_manager = get_node_or_null("/root/GrenadeManager")

	# Get ActiveItemManager reference
	_active_item_manager = get_node_or_null("/root/ActiveItemManager")

	# Load weapon resource data
	_load_weapon_resources()

	# Initialize pending selections from current state
	if GameManager:
		_pending_weapon_id = GameManager.get_selected_weapon()
	else:
		_pending_weapon_id = "m16"

	if _grenade_manager:
		_pending_grenade_type = _grenade_manager.current_grenade_type
	else:
		_pending_grenade_type = 0

	if _active_item_manager:
		_pending_active_item_type = _active_item_manager.current_active_item
	else:
		_pending_active_item_type = 0

	# Build the entire UI programmatically
	_build_ui()

	# Set process mode to allow input while paused
	process_mode = Node.PROCESS_MODE_ALWAYS


## Load weapon .tres resources for stats display.
func _load_weapon_resources() -> void:
	for weapon_id in WEAPON_RESOURCE_PATHS:
		var path: String = WEAPON_RESOURCE_PATHS[weapon_id]
		if ResourceLoader.exists(path):
			_weapon_resources[weapon_id] = load(path)


## Build the complete UI layout programmatically.
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

	# Main panel — wider to accommodate sidebar layout
	var panel := PanelContainer.new()
	panel.name = "MainPanel"
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -500
	panel.offset_top = -380
	panel.offset_right = 500
	panel.offset_bottom = 380
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

	# Main vertical layout (title + content + buttons)
	var main_vbox := VBoxContainer.new()
	main_vbox.layout_mode = 2
	main_vbox.add_theme_constant_override("separation", 8)
	margin.add_child(main_vbox)

	# Title
	var title := Label.new()
	title.text = "ARMORY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7, 1.0))
	main_vbox.add_child(title)

	# Separator below title
	var sep := HSeparator.new()
	main_vbox.add_child(sep)

	# --- HORIZONTAL LAYOUT: LEFT SIDEBAR + RIGHT GRIDS ---
	var content_hbox := HBoxContainer.new()
	content_hbox.layout_mode = 2
	content_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_hbox.add_theme_constant_override("separation", 12)
	main_vbox.add_child(content_hbox)

	# --- LEFT SIDEBAR: Loadout stats ---
	var sidebar := _build_sidebar()
	content_hbox.add_child(sidebar)

	# Vertical separator
	var vsep := VSeparator.new()
	content_hbox.add_child(vsep)

	# --- RIGHT AREA: Weapon and grenade grids ---
	var right_area := _build_right_area()
	content_hbox.add_child(right_area)

	# --- BOTTOM BUTTONS ---
	var bottom_sep := HSeparator.new()
	main_vbox.add_child(bottom_sep)

	var button_hbox := HBoxContainer.new()
	button_hbox.layout_mode = 2
	button_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	button_hbox.add_theme_constant_override("separation", 16)
	main_vbox.add_child(button_hbox)

	_back_button = Button.new()
	_back_button.text = "Back"
	_back_button.custom_minimum_size = Vector2(140, 36)
	_back_button.pressed.connect(_on_back_pressed)
	button_hbox.add_child(_back_button)

	_apply_button = Button.new()
	_apply_button.text = "Apply"
	_apply_button.custom_minimum_size = Vector2(140, 36)
	_apply_button.pressed.connect(_on_apply_pressed)
	_apply_button.disabled = true
	button_hbox.add_child(_apply_button)

	# Style Apply button to stand out
	var apply_style_normal := StyleBoxFlat.new()
	apply_style_normal.bg_color = Color(0.2, 0.45, 0.2, 0.9)
	apply_style_normal.corner_radius_top_left = 4
	apply_style_normal.corner_radius_top_right = 4
	apply_style_normal.corner_radius_bottom_left = 4
	apply_style_normal.corner_radius_bottom_right = 4
	_apply_button.add_theme_stylebox_override("normal", apply_style_normal)

	var apply_style_hover := StyleBoxFlat.new()
	apply_style_hover.bg_color = Color(0.25, 0.55, 0.25, 0.95)
	apply_style_hover.corner_radius_top_left = 4
	apply_style_hover.corner_radius_top_right = 4
	apply_style_hover.corner_radius_bottom_left = 4
	apply_style_hover.corner_radius_bottom_right = 4
	_apply_button.add_theme_stylebox_override("hover", apply_style_hover)

	var apply_style_disabled := StyleBoxFlat.new()
	apply_style_disabled.bg_color = Color(0.2, 0.2, 0.22, 0.6)
	apply_style_disabled.corner_radius_top_left = 4
	apply_style_disabled.corner_radius_top_right = 4
	apply_style_disabled.corner_radius_bottom_left = 4
	apply_style_disabled.corner_radius_bottom_right = 4
	_apply_button.add_theme_stylebox_override("disabled", apply_style_disabled)

	# Initial highlight and stats
	_highlight_selected_items()
	_update_loadout_panel()
	_update_apply_button_state()


## Build the left sidebar with weapon and grenade stats.
func _build_sidebar() -> VBoxContainer:
	var sidebar := VBoxContainer.new()
	sidebar.layout_mode = 2
	sidebar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sidebar.size_flags_stretch_ratio = 0.45
	sidebar.add_theme_constant_override("separation", 8)

	# Sidebar styled panel
	var sidebar_panel := PanelContainer.new()
	sidebar_panel.layout_mode = 2
	sidebar_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var sidebar_style := StyleBoxFlat.new()
	sidebar_style.bg_color = Color(0.15, 0.18, 0.2, 0.9)
	sidebar_style.corner_radius_top_left = 6
	sidebar_style.corner_radius_top_right = 6
	sidebar_style.corner_radius_bottom_left = 6
	sidebar_style.corner_radius_bottom_right = 6
	sidebar_style.border_color = Color(0.3, 0.4, 0.35, 0.8)
	sidebar_style.border_width_left = 1
	sidebar_style.border_width_right = 1
	sidebar_style.border_width_top = 1
	sidebar_style.border_width_bottom = 1
	sidebar_panel.add_theme_stylebox_override("panel", sidebar_style)
	sidebar.add_child(sidebar_panel)

	var sidebar_margin := MarginContainer.new()
	sidebar_margin.layout_mode = 2
	sidebar_margin.add_theme_constant_override("margin_left", 10)
	sidebar_margin.add_theme_constant_override("margin_top", 8)
	sidebar_margin.add_theme_constant_override("margin_right", 10)
	sidebar_margin.add_theme_constant_override("margin_bottom", 8)
	sidebar_panel.add_child(sidebar_margin)

	var stats_vbox := VBoxContainer.new()
	stats_vbox.layout_mode = 2
	stats_vbox.add_theme_constant_override("separation", 6)
	sidebar_margin.add_child(stats_vbox)

	# Header
	var loadout_header := Label.new()
	loadout_header.text = "CURRENT LOADOUT"
	loadout_header.add_theme_font_size_override("font_size", 14)
	loadout_header.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8, 1.0))
	stats_vbox.add_child(loadout_header)

	var stats_sep := HSeparator.new()
	stats_vbox.add_child(stats_sep)

	# Weapon stats
	_weapon_stats_label = RichTextLabel.new()
	_weapon_stats_label.layout_mode = 2
	_weapon_stats_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_weapon_stats_label.bbcode_enabled = true
	_weapon_stats_label.fit_content = true
	_weapon_stats_label.scroll_active = false
	_weapon_stats_label.add_theme_font_size_override("normal_font_size", 12)
	stats_vbox.add_child(_weapon_stats_label)

	var mid_sep := HSeparator.new()
	stats_vbox.add_child(mid_sep)

	# Grenade stats
	_grenade_stats_label = RichTextLabel.new()
	_grenade_stats_label.layout_mode = 2
	_grenade_stats_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_grenade_stats_label.bbcode_enabled = true
	_grenade_stats_label.fit_content = true
	_grenade_stats_label.scroll_active = false
	_grenade_stats_label.add_theme_font_size_override("normal_font_size", 12)
	stats_vbox.add_child(_grenade_stats_label)

	var active_sep := HSeparator.new()
	stats_vbox.add_child(active_sep)

	# Active item stats
	_active_item_stats_label = RichTextLabel.new()
	_active_item_stats_label.layout_mode = 2
	_active_item_stats_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_active_item_stats_label.bbcode_enabled = true
	_active_item_stats_label.fit_content = true
	_active_item_stats_label.scroll_active = false
	_active_item_stats_label.add_theme_font_size_override("normal_font_size", 12)
	stats_vbox.add_child(_active_item_stats_label)

	return sidebar


## Build the right area with weapon and grenade grids.
func _build_right_area() -> VBoxContainer:
	var right_vbox := VBoxContainer.new()
	right_vbox.layout_mode = 2
	right_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_vbox.size_flags_stretch_ratio = 0.55
	right_vbox.add_theme_constant_override("separation", 6)

	# --- WEAPONS SECTION ---
	_add_category_header(right_vbox, "WEAPONS")
	_weapon_grid = GridContainer.new()
	_weapon_grid.columns = GRID_COLUMNS
	_weapon_grid.layout_mode = 2
	_weapon_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_weapon_grid.add_theme_constant_override("h_separation", 6)
	_weapon_grid.add_theme_constant_override("v_separation", 6)
	right_vbox.add_child(_weapon_grid)

	# Populate weapon grid
	var weapon_index: int = 0
	var max_visible_weapons: int = MAX_WEAPON_ROWS_COLLAPSED * GRID_COLUMNS
	for weapon_id in FIREARMS:
		var weapon_data: Dictionary = FIREARMS[weapon_id]
		var slot := _create_item_slot(weapon_id, weapon_data, false)
		_weapon_grid.add_child(slot)
		_weapon_slots[weapon_id] = slot
		if weapon_index >= max_visible_weapons:
			_weapon_overflow_slots.append(slot)
		weapon_index += 1

	# Weapon accordion button (only shown if items overflow)
	_weapon_accordion_button = Button.new()
	_weapon_accordion_button.text = "Show all ▼"
	_weapon_accordion_button.add_theme_font_size_override("font_size", 11)
	_weapon_accordion_button.pressed.connect(_toggle_weapon_accordion)
	right_vbox.add_child(_weapon_accordion_button)

	if _weapon_overflow_slots.size() == 0:
		_weapon_accordion_button.visible = false
	else:
		_apply_accordion_collapsed_weapons()

	# Separator
	var grenade_sep := HSeparator.new()
	grenade_sep.add_theme_constant_override("separation", 4)
	right_vbox.add_child(grenade_sep)

	# --- GRENADES SECTION ---
	_add_category_header(right_vbox, "GRENADES")
	_grenade_grid = GridContainer.new()
	_grenade_grid.columns = GRID_COLUMNS
	_grenade_grid.layout_mode = 2
	_grenade_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grenade_grid.add_theme_constant_override("h_separation", 6)
	_grenade_grid.add_theme_constant_override("v_separation", 6)
	right_vbox.add_child(_grenade_grid)

	# Populate grenade grid from GrenadeManager
	var grenade_index: int = 0
	var max_visible_grenades: int = MAX_GRENADE_ROWS_COLLAPSED * GRID_COLUMNS
	if _grenade_manager:
		for grenade_type in _grenade_manager.get_all_grenade_types():
			var gdata: Dictionary = _grenade_manager.get_grenade_data(grenade_type)
			var grenade_info := {
				"name": gdata.get("name", "Unknown"),
				"icon_path": gdata.get("icon_path", ""),
				"unlocked": true,
				"description": gdata.get("description", ""),
				"grenade_type": grenade_type
			}
			var slot := _create_item_slot(str(grenade_type), grenade_info, true)
			_grenade_grid.add_child(slot)
			_grenade_slots[grenade_type] = slot
			if grenade_index >= max_visible_grenades:
				_grenade_overflow_slots.append(slot)
			grenade_index += 1

	# Grenade accordion button (only shown if items overflow)
	_grenade_accordion_button = Button.new()
	_grenade_accordion_button.text = "Show all ▼"
	_grenade_accordion_button.add_theme_font_size_override("font_size", 11)
	_grenade_accordion_button.pressed.connect(_toggle_grenade_accordion)
	right_vbox.add_child(_grenade_accordion_button)

	if _grenade_overflow_slots.size() == 0:
		_grenade_accordion_button.visible = false
	else:
		_apply_accordion_collapsed_grenades()

	# Separator
	var active_sep := HSeparator.new()
	active_sep.add_theme_constant_override("separation", 4)
	right_vbox.add_child(active_sep)

	# --- ACTIVE ITEMS SECTION ---
	_add_category_header(right_vbox, "ACTIVE ITEMS")
	_active_item_grid = GridContainer.new()
	_active_item_grid.columns = GRID_COLUMNS
	_active_item_grid.layout_mode = 2
	_active_item_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_active_item_grid.add_theme_constant_override("h_separation", 6)
	_active_item_grid.add_theme_constant_override("v_separation", 6)
	right_vbox.add_child(_active_item_grid)

	# Populate active item grid from ActiveItemManager
	var active_item_index: int = 0
	var max_visible_active_items: int = MAX_ACTIVE_ITEM_ROWS_COLLAPSED * GRID_COLUMNS
	if _active_item_manager:
		for item_type in _active_item_manager.get_all_active_item_types():
			var adata: Dictionary = _active_item_manager.get_active_item_data(item_type)
			var item_info := {
				"name": adata.get("name", "Unknown"),
				"icon_path": adata.get("icon_path", ""),
				"unlocked": true,
				"description": adata.get("description", ""),
				"active_item_type": item_type
			}
			var slot := _create_active_item_slot(str(item_type), item_info, item_type)
			_active_item_grid.add_child(slot)
			_active_item_slots[item_type] = slot
			if active_item_index >= max_visible_active_items:
				_active_item_overflow_slots.append(slot)
			active_item_index += 1

	# Active item accordion button (only shown if items overflow)
	_active_item_accordion_button = Button.new()
	_active_item_accordion_button.text = "Show all ▼"
	_active_item_accordion_button.add_theme_font_size_override("font_size", 11)
	_active_item_accordion_button.pressed.connect(_toggle_active_item_accordion)
	right_vbox.add_child(_active_item_accordion_button)

	if _active_item_overflow_slots.size() == 0:
		_active_item_accordion_button.visible = false
	else:
		_apply_accordion_collapsed_active_items()

	return right_vbox


## Toggle weapon accordion (expand/collapse overflow items).
func _toggle_weapon_accordion() -> void:
	_weapons_expanded = not _weapons_expanded
	if _weapons_expanded:
		_weapon_accordion_button.text = "Collapse ▲"
		for slot in _weapon_overflow_slots:
			slot.visible = true
	else:
		_apply_accordion_collapsed_weapons()


## Collapse weapon overflow slots.
func _apply_accordion_collapsed_weapons() -> void:
	_weapon_accordion_button.text = "Show all ▼"
	for slot in _weapon_overflow_slots:
		slot.visible = false


## Toggle grenade accordion (expand/collapse overflow items).
func _toggle_grenade_accordion() -> void:
	_grenades_expanded = not _grenades_expanded
	if _grenades_expanded:
		_grenade_accordion_button.text = "Collapse ▲"
		for slot in _grenade_overflow_slots:
			slot.visible = true
	else:
		_apply_accordion_collapsed_grenades()


## Collapse grenade overflow slots.
func _apply_accordion_collapsed_grenades() -> void:
	_grenade_accordion_button.text = "Show all ▼"
	for slot in _grenade_overflow_slots:
		slot.visible = false


## Toggle active item accordion (expand/collapse overflow items).
func _toggle_active_item_accordion() -> void:
	_active_items_expanded = not _active_items_expanded
	if _active_items_expanded:
		_active_item_accordion_button.text = "Collapse ▲"
		for slot in _active_item_overflow_slots:
			slot.visible = true
	else:
		_apply_accordion_collapsed_active_items()


## Collapse active item overflow slots.
func _apply_accordion_collapsed_active_items() -> void:
	_active_item_accordion_button.text = "Show all ▼"
	for slot in _active_item_overflow_slots:
		slot.visible = false


## Add a styled category header label.
func _add_category_header(parent: VBoxContainer, text: String) -> void:
	var header := Label.new()
	header.text = text
	header.add_theme_font_size_override("font_size", 14)
	header.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8, 1.0))
	parent.add_child(header)


## Create an item slot (used for both weapons and grenades).
func _create_item_slot(item_id: String, item_data: Dictionary, is_grenade: bool) -> PanelContainer:
	var slot := PanelContainer.new()
	slot.name = item_id + "_slot"
	slot.custom_minimum_size = Vector2(90, 80)

	# Store metadata for click handling
	slot.set_meta("item_id", item_id)
	slot.set_meta("is_grenade", is_grenade)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 3)
	slot.add_child(vbox)

	# Item icon or lock placeholder
	var icon_container := CenterContainer.new()
	icon_container.custom_minimum_size = Vector2(48, 48)
	vbox.add_child(icon_container)

	var is_unlocked: bool = item_data.get("unlocked", false)

	if is_unlocked and item_data.get("icon_path", "") != "":
		var texture_rect := TextureRect.new()
		texture_rect.custom_minimum_size = Vector2(48, 48)
		texture_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

		var texture: Texture2D = load(item_data["icon_path"])
		if texture:
			texture_rect.texture = texture
		icon_container.add_child(texture_rect)
	else:
		var lock_label := Label.new()
		lock_label.text = "?"
		lock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lock_label.add_theme_font_size_override("font_size", 24)
		lock_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 0.8))
		icon_container.add_child(lock_label)

	# Item name
	var name_label := Label.new()
	name_label.text = item_data.get("name", "???")
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 11)
	if not is_unlocked:
		name_label.modulate = Color(0.5, 0.5, 0.5)
	vbox.add_child(name_label)

	# Tooltip
	slot.tooltip_text = item_data.get("description", "")

	# Make unlocked items clickable
	if is_unlocked:
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		slot.gui_input.connect(_on_slot_gui_input.bind(slot, item_id, is_grenade, item_data))
		slot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	else:
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Default style
	_apply_default_style(slot)

	return slot


## Create an active item slot (separate handler for active item clicks).
func _create_active_item_slot(item_id: String, item_data: Dictionary, item_type: int) -> PanelContainer:
	var slot := PanelContainer.new()
	slot.name = "active_" + item_id + "_slot"
	slot.custom_minimum_size = Vector2(90, 80)

	# Store metadata
	slot.set_meta("item_id", item_id)
	slot.set_meta("is_active_item", true)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 3)
	slot.add_child(vbox)

	# Item icon or placeholder
	var icon_container := CenterContainer.new()
	icon_container.custom_minimum_size = Vector2(48, 48)
	vbox.add_child(icon_container)

	var icon_path: String = item_data.get("icon_path", "")
	if icon_path != "" and ResourceLoader.exists(icon_path):
		var texture_rect := TextureRect.new()
		texture_rect.custom_minimum_size = Vector2(48, 48)
		texture_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

		var texture: Texture2D = load(icon_path)
		if texture:
			texture_rect.texture = texture
		icon_container.add_child(texture_rect)
	else:
		# "None" item or missing icon — show dash
		var none_label := Label.new()
		none_label.text = "-" if item_data.get("name", "") == "None" else "?"
		none_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		none_label.add_theme_font_size_override("font_size", 24)
		none_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 0.8))
		icon_container.add_child(none_label)

	# Item name
	var name_label := Label.new()
	name_label.text = item_data.get("name", "???")
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(name_label)

	# Tooltip
	slot.tooltip_text = item_data.get("description", "")

	# Make clickable
	slot.mouse_filter = Control.MOUSE_FILTER_STOP
	slot.gui_input.connect(_on_active_item_slot_gui_input.bind(slot, item_type))
	slot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	# Default style
	_apply_default_style(slot)

	return slot


## Handle click on an active item slot.
func _on_active_item_slot_gui_input(event: InputEvent, slot: PanelContainer, item_type: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_pending_active_item_type = item_type

		# Play click sound via AudioManager
		var audio_manager = get_node_or_null("/root/AudioManager")
		if audio_manager and audio_manager.has_method("play_ui_click"):
			audio_manager.play_ui_click()

		# Update visuals to show pending selection
		_highlight_selected_items()
		_update_loadout_panel()
		_update_apply_button_state()


## Apply default (unselected) style to a slot.
func _apply_default_style(slot: PanelContainer) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.2, 0.22, 0.6)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	slot.add_theme_stylebox_override("panel", style)


## Apply selected (highlighted) style to a slot.
func _apply_selected_style(slot: PanelContainer) -> void:
	var selected_style := StyleBoxFlat.new()
	selected_style.bg_color = Color(0.25, 0.4, 0.25, 0.8)
	selected_style.border_color = Color(0.4, 0.8, 0.4, 1.0)
	selected_style.border_width_left = 2
	selected_style.border_width_right = 2
	selected_style.border_width_top = 2
	selected_style.border_width_bottom = 2
	selected_style.corner_radius_top_left = 4
	selected_style.corner_radius_top_right = 4
	selected_style.corner_radius_bottom_left = 4
	selected_style.corner_radius_bottom_right = 4
	slot.add_theme_stylebox_override("panel", selected_style)


## Handle click on an item slot.
## Sets the pending selection (does NOT restart — user must press Apply).
func _on_slot_gui_input(event: InputEvent, slot: PanelContainer, item_id: String, is_grenade: bool, item_data: Dictionary) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if is_grenade:
			var grenade_type: int = item_data.get("grenade_type", 0)
			_pending_grenade_type = grenade_type
		else:
			_pending_weapon_id = item_id

		# Play click sound via AudioManager
		var audio_manager = get_node_or_null("/root/AudioManager")
		if audio_manager and audio_manager.has_method("play_ui_click"):
			audio_manager.play_ui_click()

		# Update visuals to show pending selection
		_highlight_selected_items()
		_update_loadout_panel()
		_update_apply_button_state()


## Check if the pending selection differs from the current applied selection.
func _has_pending_changes() -> bool:
	var current_weapon_id: String = "m16"
	if GameManager:
		current_weapon_id = GameManager.get_selected_weapon()

	var current_grenade_type: int = 0
	if _grenade_manager:
		current_grenade_type = _grenade_manager.current_grenade_type

	var current_active_item_type: int = 0
	if _active_item_manager:
		current_active_item_type = _active_item_manager.current_active_item

	return _pending_weapon_id != current_weapon_id or _pending_grenade_type != current_grenade_type or _pending_active_item_type != current_active_item_type


## Update the Apply button enabled state.
func _update_apply_button_state() -> void:
	if _apply_button:
		_apply_button.disabled = not _has_pending_changes()


## Apply the pending selection: update GameManager/GrenadeManager/ActiveItemManager and restart.
func _on_apply_pressed() -> void:
	if not _has_pending_changes():
		return

	var weapon_changed: bool = false
	var grenade_changed: bool = false
	var active_item_changed: bool = false

	# Apply weapon change
	var current_weapon_id: String = "m16"
	if GameManager:
		current_weapon_id = GameManager.get_selected_weapon()

	if _pending_weapon_id != current_weapon_id:
		if GameManager:
			GameManager.set_selected_weapon(_pending_weapon_id)
		weapon_selected.emit(_pending_weapon_id)
		weapon_changed = true

	# Apply grenade change
	var current_grenade_type: int = 0
	if _grenade_manager:
		current_grenade_type = _grenade_manager.current_grenade_type

	if _pending_grenade_type != current_grenade_type:
		if _grenade_manager:
			# Pass false for restart_level — we handle restart ourselves
			_grenade_manager.set_grenade_type(_pending_grenade_type, false)
		grenade_changed = true

	# Apply active item change
	var current_active_item_type: int = 0
	if _active_item_manager:
		current_active_item_type = _active_item_manager.current_active_item

	if _pending_active_item_type != current_active_item_type:
		if _active_item_manager:
			# Pass false for restart_level — we handle restart ourselves
			_active_item_manager.set_active_item(_pending_active_item_type, false)
		active_item_changed = true

	# Restart the level to apply changes
	if weapon_changed or grenade_changed or active_item_changed:
		if GameManager:
			get_tree().paused = false
			Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED_HIDDEN)
			GameManager.restart_scene()


## Highlight the currently selected (pending) weapon, grenade, and active item slots.
func _highlight_selected_items() -> void:
	# Reset all weapon slots to default
	for wid in _weapon_slots:
		_apply_default_style(_weapon_slots[wid])

	# Reset all grenade slots to default
	for gtype in _grenade_slots:
		_apply_default_style(_grenade_slots[gtype])

	# Reset all active item slots to default
	for atype in _active_item_slots:
		_apply_default_style(_active_item_slots[atype])

	# Highlight pending weapon
	if _pending_weapon_id in _weapon_slots:
		_apply_selected_style(_weapon_slots[_pending_weapon_id])

	# Highlight pending grenade
	if _pending_grenade_type in _grenade_slots:
		_apply_selected_style(_grenade_slots[_pending_grenade_type])

	# Highlight pending active item
	if _pending_active_item_type in _active_item_slots:
		_apply_selected_style(_active_item_slots[_pending_active_item_type])


## Update the Current Loadout panel with stats for pending weapon, grenade, and active item.
func _update_loadout_panel() -> void:
	_update_weapon_stats()
	_update_grenade_stats()
	_update_active_item_stats()


## Update weapon stats in the sidebar.
func _update_weapon_stats() -> void:
	if _weapon_stats_label == null:
		return

	var weapon_info: Dictionary = FIREARMS.get(_pending_weapon_id, {})
	var weapon_name: String = weapon_info.get("name", "Unknown")

	# Try to load weapon resource for detailed stats
	var resource = _weapon_resources.get(_pending_weapon_id)

	var bbcode: String = ""
	bbcode += "[b][color=#d4c896]WEAPON: %s[/color][/b]\n" % weapon_name

	if resource:
		# Fire mode
		var fire_mode: String = "Auto" if resource.get("IsAutomatic") else "Semi-Auto"
		bbcode += "[color=#aab0b8]Fire Mode:[/color] %s\n" % fire_mode

		# Caliber
		var caliber = resource.get("Caliber")
		if caliber:
			bbcode += "[color=#aab0b8]Caliber:[/color] %s\n" % caliber.caliber_name

		# Damage & Fire rate
		var damage: float = resource.get("Damage")
		var fire_rate: float = resource.get("FireRate")
		var pellets: int = resource.get("BulletsPerShot")
		var damage_text: String = str(damage)
		if pellets > 1:
			damage_text += " x%d pellets" % pellets
		bbcode += "[color=#aab0b8]Damage:[/color] %s\n" % damage_text
		bbcode += "[color=#aab0b8]Rate:[/color] %.0f/s\n" % fire_rate

		# Magazine
		var mag_size: int = resource.get("MagazineSize")
		var reserve: int = resource.get("MaxReserveAmmo")
		bbcode += "[color=#aab0b8]Mag:[/color] %d rnd  [color=#aab0b8]Reserve:[/color] %d\n" % [mag_size, reserve]

		# Reload time
		var reload: float = resource.get("ReloadTime")
		bbcode += "[color=#aab0b8]Reload:[/color] %.1fs\n" % reload

		# Range & Spread
		var weapon_range: float = resource.get("Range")
		var spread: float = resource.get("SpreadAngle")
		bbcode += "[color=#aab0b8]Range:[/color] %.0fpx\n" % weapon_range
		bbcode += "[color=#aab0b8]Spread:[/color] %.1f°\n" % spread

		# Loudness
		var loudness: float = resource.get("Loudness")
		var loudness_text: String
		if loudness <= 0.0:
			loudness_text = "[color=#66bb6a]Silent[/color]"
		elif loudness < 1500.0:
			loudness_text = "[color=#ffa726]%.0fpx[/color]" % loudness
		else:
			loudness_text = "[color=#ef5350]%.0fpx[/color]" % loudness
		bbcode += "[color=#aab0b8]Loudness:[/color] %s\n" % loudness_text

		# Caliber properties (ricochet / penetration)
		if caliber:
			var features: Array[String] = []
			if caliber.can_ricochet:
				features.append("Ricochet")
			if caliber.can_penetrate:
				features.append("Wall Pen. (%dpx)" % int(caliber.max_penetration_distance))
			if features.size() > 0:
				bbcode += "[color=#aab0b8]Ballistics:[/color] %s" % ", ".join(features)
			else:
				bbcode += "[color=#aab0b8]Ballistics:[/color] Standard"
	else:
		bbcode += "[color=#888888]%s[/color]" % weapon_info.get("description", "No data available")

	_weapon_stats_label.text = bbcode


## Update grenade stats in the sidebar.
func _update_grenade_stats() -> void:
	if _grenade_stats_label == null:
		return

	var grenade_data: Dictionary = {}
	if _grenade_manager:
		grenade_data = _grenade_manager.get_grenade_data(_pending_grenade_type)

	var grenade_name: String = grenade_data.get("name", "Unknown")
	var grenade_desc: String = grenade_data.get("description", "No data available")

	var bbcode: String = ""
	bbcode += "[b][color=#d4c896]GRENADE: %s[/color][/b]\n" % grenade_name
	bbcode += "[color=#aab0b8]%s[/color]\n" % grenade_desc
	bbcode += "\n[color=#888888]Press G + RMB drag to throw[/color]"

	_grenade_stats_label.text = bbcode


## Update active item stats in the sidebar.
func _update_active_item_stats() -> void:
	if _active_item_stats_label == null:
		return

	var item_data: Dictionary = {}
	if _active_item_manager:
		item_data = _active_item_manager.get_active_item_data(_pending_active_item_type)

	var item_name: String = item_data.get("name", "None")
	var item_desc: String = item_data.get("description", "No active item equipped.")

	var bbcode: String = ""
	bbcode += "[b][color=#d4c896]ACTIVE: %s[/color][/b]\n" % item_name
	bbcode += "[color=#aab0b8]%s[/color]\n" % item_desc
	if _pending_active_item_type != 0:  # Not "None"
		bbcode += "\n[color=#888888]Hold Space to activate[/color]"

	_active_item_stats_label.text = bbcode


## Refresh the weapon grid (called when menu is reshown).
func _populate_weapon_grid() -> void:
	# Sync pending selections with current state
	if GameManager:
		_pending_weapon_id = GameManager.get_selected_weapon()
	if _grenade_manager:
		_pending_grenade_type = _grenade_manager.current_grenade_type
	if _active_item_manager:
		_pending_active_item_type = _active_item_manager.current_active_item

	_highlight_selected_items()
	_update_loadout_panel()
	_update_apply_button_state()


func _on_back_pressed() -> void:
	back_pressed.emit()
