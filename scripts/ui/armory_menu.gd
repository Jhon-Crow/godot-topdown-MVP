extends CanvasLayer
## Armory menu for selecting weapons, grenades, and special items by category.
##
## Layout: left sidebar with stats/description, right area with weapon/grenade/special item grids.
## Items fit on screen without scrolling. An accordion toggle expands the grid
## if there are too many items. An "Apply" button confirms the selection
## and restarts the level (no immediate restart on click).

## Signal emitted when the back button is pressed.
signal back_pressed

## Signal emitted when a weapon is selected.
signal weapon_selected(weapon_id: String)

## Signal emitted when Apply is pressed from score screen context (Issue #1006).
## The armory should close without restarting the level.
signal apply_pressed_from_score_screen

## Path to weapon case icon used for locked/closed weapons.
const WEAPON_CASE_ICON_PATH: String = "res://assets/sprites/weapons/weapon_case_icon.png"

## Path to grenade case icon used for locked/closed grenades.
const GRENADE_CASE_ICON_PATH: String = "res://assets/sprites/weapons/grenade_case_icon.png"

## Path to item case icon used for locked/closed active items.
const ITEM_CASE_ICON_PATH: String = "res://assets/sprites/weapons/item_case_icon.png"

## Firearms data — weapons the player can equip.
## Keys: weapon_id, Values: dictionary with name, icon_path, description
## Note: 'unlocked' field is now read from GameManager.unlocked_weapons
const FIREARMS: Dictionary = {
	"makarov_pm": {
		"name": "PM",
		"icon_path": "res://assets/sprites/weapons/makarov_pm_icon.png",
		"description": "Makarov PM — 9x18mm starting pistol, 9-round magazine, medium ricochets"
	},
	"m16": {
		"name": "M16",
		"icon_path": "res://assets/sprites/weapons/m16_rifle.png",
		"description": "Standard assault rifle with auto/burst modes, red laser sight"
	},
	"shotgun": {
		"name": "Shotgun",
		"icon_path": "res://assets/sprites/weapons/shotgun_icon.png",
		"description": "Pump-action shotgun — shell-by-shell loading, multi-pellet spread"
	},
	"mini_uzi": {
		"name": "Mini UZI",
		"icon_path": "res://assets/sprites/weapons/mini_uzi_icon.png",
		"description": "High fire rate SMG — progressive spread, ricochets at shallow angles"
	},
	"silenced_pistol": {
		"name": "Silenced Pistol",
		"icon_path": "res://assets/sprites/weapons/silenced_pistol_icon.png",
		"description": "Beretta M9 with suppressor — silent, stuns enemies on hit"
	},
	"sniper": {
		"name": "ASVK",
		"icon_path": "res://assets/sprites/weapons/asvk_topdown.png",
		"description": "ASVK anti-materiel sniper rifle - 12.7x108mm, 50 damage, penetrates 2 walls and enemies, bolt-action (Down→Left→Down→Up). 5-round magazine. RMB to scope (mouse wheel to zoom)."
	},
	"revolver": {
		"name": "RSh-12",
		"icon_path": "res://assets/sprites/weapons/revolver_icon.png",
		"description": "RSh-12 heavy revolver - 12.7x55mm STs-130, 20 damage, penetrates walls (200px), weak ricochet, strong recoil. 5-round cylinder. Comfortable aiming like silenced pistol."
	},
	"ak_gl": {
		"name": "AK + GL",
		"icon_path": "res://assets/sprites/weapons/ak_gl_icon.png",
		"description": "AK with GP-25 underbarrel grenade launcher — 7.62x39mm, 30-round magazine, RMB fires VOG-25 grenade (1 shot)"
	},
	"smg": {
		"name": "???",
		"icon_path": "",
		"description": "Coming soon"
	}
}

## Mapping from weapon_id to .tres resource path for loading stats.
const WEAPON_RESOURCE_PATHS: Dictionary = {
	"makarov_pm": "res://resources/weapons/MakarovPMData.tres",
	"m16": "res://resources/weapons/AssaultRifleData.tres",
	"shotgun": "res://resources/weapons/ShotgunData.tres",
	"mini_uzi": "res://resources/weapons/MiniUziData.tres",
	"silenced_pistol": "res://resources/weapons/SilencedPistolData.tres",
	"sniper": "res://resources/weapons/SniperRifleData.tres",
	"revolver": "res://resources/weapons/RevolverData.tres",
	"ak_gl": "res://resources/weapons/AKGLData.tres"
}

## Maximum number of visible weapon rows before accordion hides the rest.
const MAX_WEAPON_ROWS_COLLAPSED: int = 2

## Maximum number of visible grenade rows before accordion hides the rest.
const MAX_GRENADE_ROWS_COLLAPSED: int = 1

## Number of columns in the weapon/grenade grids.
const GRID_COLUMNS: int = 4

## Number of columns in the special items grid.
const SPECIAL_GRID_COLUMNS: int = 7

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

## Reference to UnlockManager autoload.
var _unlock_manager: Node = null

## Whether the armory was opened from the score screen (Issue #1006).
## When true, pressing Apply should hide the armory and return to score screen
## instead of restarting the level.
var opened_from_score_screen: bool = false

## Cached weapon resource data.
var _weapon_resources: Dictionary = {}

## Overflow weapon slots (hidden when collapsed).
var _weapon_overflow_slots: Array = []

## Overflow grenade slots (hidden when collapsed).
var _grenade_overflow_slots: Array = []

## Overflow active item slots (hidden when collapsed).
var _active_item_overflow_slots: Array = []

## LMB hold tracking for unlocking items.
## Dictionary: slot -> {start_time: float, item_id: String, is_grenade: bool, is_active_item: bool}
var _lmb_hold_tracking: Dictionary = {}

## Duration (in seconds) to hold LMB to unlock an item.
const UNLOCK_HOLD_DURATION: float = 1.5

## Timer for processing LMB hold progress.
var _unlock_timer: Timer = null

## Audio player for unlock sound effects (generated beeps).
var _unlock_audio_player: AudioStreamPlayer = null

## Base frequency for unlock beeps (Hz).
const BEEP_BASE_FREQUENCY: float = 440.0

## Dictionary: slot -> progress_overlay (ColorRect for visual progress indicator)
var _slot_progress_overlays: Dictionary = {}

## Animation state tracking for reveal animations.
## Dictionary: slot -> tween reference
var _active_reveal_tweens: Dictionary = {}

## Animation state tracking for selection animations (shake + glint).
## Dictionary: slot -> tween reference — killed if the same slot is re-selected quickly.
var _active_selection_tweens: Dictionary = {}


func _ready() -> void:
	# Get GrenadeManager reference
	_grenade_manager = get_node_or_null("/root/GrenadeManager")

	# Get ActiveItemManager reference
	_active_item_manager = get_node_or_null("/root/ActiveItemManager")

	# Get UnlockManager reference
	_unlock_manager = get_node_or_null("/root/UnlockManager")

	# Load weapon resource data
	_load_weapon_resources()

	# Initialize pending selections from current state
	if GameManager:
		_pending_weapon_id = GameManager.get_selected_weapon()
	else:
		_pending_weapon_id = "makarov_pm"

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

	# Create timer for unlock progress tracking
	_unlock_timer = Timer.new()
	_unlock_timer.wait_time = 0.016  # ~60 FPS for smoother progress updates
	_unlock_timer.one_shot = false
	_unlock_timer.timeout.connect(_on_unlock_timer_timeout)
	add_child(_unlock_timer)

	# Create audio player for unlock sound effects
	_unlock_audio_player = AudioStreamPlayer.new()
	_unlock_audio_player.bus = "Master"
	add_child(_unlock_audio_player)


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
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)

	# Main vertical layout (title + content + buttons)
	var main_vbox := VBoxContainer.new()
	main_vbox.layout_mode = 2
	main_vbox.add_theme_constant_override("separation", 8)
	margin.add_child(main_vbox)

	# Title with neon styling
	var title := Label.new()
	title.text = "ARMORY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var neon_label_settings = load("res://resources/themes/neon_label_settings.tres")
	if neon_label_settings:
		title.label_settings = neon_label_settings
	else:
		title.add_theme_font_size_override("font_size", 22)
		title.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7, 1.0))
	main_vbox.add_child(title)

	# Separator below title
	var sep := HSeparator.new()
	main_vbox.add_child(sep)

	# --- SCROLLABLE CONTENT AREA ---
	# Wrap content in a ScrollContainer so buttons stay fixed at bottom
	var scroll_container := ScrollContainer.new()
	scroll_container.layout_mode = 2
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	main_vbox.add_child(scroll_container)

	# --- HORIZONTAL LAYOUT: LEFT SIDEBAR + RIGHT GRIDS ---
	var content_hbox := HBoxContainer.new()
	content_hbox.layout_mode = 2
	content_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_hbox.add_theme_constant_override("separation", 12)
	scroll_container.add_child(content_hbox)

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

	# Bottom spacer for footer padding
	var bottom_spacer := Control.new()
	bottom_spacer.custom_minimum_size = Vector2(0, 8)
	main_vbox.add_child(bottom_spacer)

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
		# Check unlock state from GameManager
		var is_unlocked: bool = false
		if GameManager and GameManager.has_method("is_weapon_unlocked"):
			is_unlocked = GameManager.is_weapon_unlocked(weapon_id)
		# Check if unlock condition is met (for gold highlighting)
		var condition_met: bool = false
		if not is_unlocked and _unlock_manager and _unlock_manager.has_method("is_weapon_condition_met"):
			condition_met = _unlock_manager.is_weapon_condition_met(weapon_id)
		var slot := _create_item_slot(weapon_id, weapon_data, false, is_unlocked, condition_met)
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
			# Check unlock state from GrenadeManager
			var is_unlocked: bool = false
			if _grenade_manager.has_method("is_grenade_unlocked"):
				is_unlocked = _grenade_manager.is_grenade_unlocked(grenade_type)
			# Check if unlock condition is met (for gold highlighting)
			var condition_met: bool = false
			if not is_unlocked and _unlock_manager and _unlock_manager.has_method("is_grenade_condition_met"):
				condition_met = _unlock_manager.is_grenade_condition_met(grenade_type)
			var grenade_info := {
				"name": gdata.get("name", "Unknown"),
				"icon_path": gdata.get("icon_path", ""),
				"description": gdata.get("description", ""),
				"grenade_type": grenade_type
			}
			var slot := _create_item_slot(str(grenade_type), grenade_info, true, is_unlocked, condition_met)
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

	# --- SPECIAL SECTION ---
	_add_category_header(right_vbox, "SPECIAL")
	_active_item_grid = GridContainer.new()
	_active_item_grid.columns = SPECIAL_GRID_COLUMNS
	_active_item_grid.layout_mode = 2
	_active_item_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_active_item_grid.add_theme_constant_override("h_separation", 6)
	_active_item_grid.add_theme_constant_override("v_separation", 6)
	right_vbox.add_child(_active_item_grid)

	# Populate active item grid from ActiveItemManager
	var active_item_index: int = 0
	var max_visible_active_items: int = MAX_ACTIVE_ITEM_ROWS_COLLAPSED * SPECIAL_GRID_COLUMNS
	if _active_item_manager:
		for item_type in _active_item_manager.get_all_active_item_types():
			var adata: Dictionary = _active_item_manager.get_active_item_data(item_type)
			# Check unlock state from ActiveItemManager
			var is_unlocked: bool = false
			if _active_item_manager.has_method("is_active_item_unlocked"):
				is_unlocked = _active_item_manager.is_active_item_unlocked(item_type)
			# Check if unlock condition is met (for gold highlighting)
			var condition_met: bool = false
			if not is_unlocked and _unlock_manager and _unlock_manager.has_method("is_active_item_condition_met"):
				condition_met = _unlock_manager.is_active_item_condition_met(item_type)
			var item_info := {
				"name": adata.get("name", "Unknown"),
				"icon_path": adata.get("icon_path", ""),
				"description": adata.get("description", ""),
				"active_item_type": item_type
			}
			var slot := _create_active_item_slot(str(item_type), item_info, item_type, is_unlocked, condition_met)
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


## Returns true if any slot in the given overflow array has condition_met == true and is locked.
func _has_condition_met_in_overflow(overflow_slots: Array) -> bool:
	for slot in overflow_slots:
		var is_unlocked: bool = slot.get_meta("is_unlocked", true)
		var condition_met: bool = slot.get_meta("condition_met", false)
		if not is_unlocked and condition_met:
			return true
	return false


## Apply gold style to an accordion button to indicate hidden condition-met items.
func _apply_accordion_button_condition_met_style(button: Button) -> void:
	button.add_theme_color_override("font_color", Color(1.0, 0.8, 0.1, 1.0))


## Reset accordion button to default font color.
func _apply_accordion_button_default_style(button: Button) -> void:
	button.remove_theme_color_override("font_color")


## Toggle weapon accordion (expand/collapse overflow items).
func _toggle_weapon_accordion() -> void:
	_weapons_expanded = not _weapons_expanded
	if _weapons_expanded:
		_weapon_accordion_button.text = "Collapse ▲"
		_apply_accordion_button_default_style(_weapon_accordion_button)
		for slot in _weapon_overflow_slots:
			slot.visible = true
	else:
		_apply_accordion_collapsed_weapons()


## Collapse weapon overflow slots.
func _apply_accordion_collapsed_weapons() -> void:
	_weapon_accordion_button.text = "Show all ▼"
	for slot in _weapon_overflow_slots:
		slot.visible = false
	if _has_condition_met_in_overflow(_weapon_overflow_slots):
		_apply_accordion_button_condition_met_style(_weapon_accordion_button)
	else:
		_apply_accordion_button_default_style(_weapon_accordion_button)


## Toggle grenade accordion (expand/collapse overflow items).
func _toggle_grenade_accordion() -> void:
	_grenades_expanded = not _grenades_expanded
	if _grenades_expanded:
		_grenade_accordion_button.text = "Collapse ▲"
		_apply_accordion_button_default_style(_grenade_accordion_button)
		for slot in _grenade_overflow_slots:
			slot.visible = true
	else:
		_apply_accordion_collapsed_grenades()


## Collapse grenade overflow slots.
func _apply_accordion_collapsed_grenades() -> void:
	_grenade_accordion_button.text = "Show all ▼"
	for slot in _grenade_overflow_slots:
		slot.visible = false
	if _has_condition_met_in_overflow(_grenade_overflow_slots):
		_apply_accordion_button_condition_met_style(_grenade_accordion_button)
	else:
		_apply_accordion_button_default_style(_grenade_accordion_button)


## Toggle active item accordion (expand/collapse overflow items).
func _toggle_active_item_accordion() -> void:
	_active_items_expanded = not _active_items_expanded
	if _active_items_expanded:
		_active_item_accordion_button.text = "Collapse ▲"
		_apply_accordion_button_default_style(_active_item_accordion_button)
		for slot in _active_item_overflow_slots:
			slot.visible = true
	else:
		_apply_accordion_collapsed_active_items()


## Collapse active item overflow slots.
func _apply_accordion_collapsed_active_items() -> void:
	_active_item_accordion_button.text = "Show all ▼"
	for slot in _active_item_overflow_slots:
		slot.visible = false
	if _has_condition_met_in_overflow(_active_item_overflow_slots):
		_apply_accordion_button_condition_met_style(_active_item_accordion_button)
	else:
		_apply_accordion_button_default_style(_active_item_accordion_button)


## Add a styled category header label.
func _add_category_header(parent: VBoxContainer, text: String) -> void:
	var header := Label.new()
	header.text = text
	header.add_theme_font_size_override("font_size", 14)
	header.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8, 1.0))
	parent.add_child(header)


## Create an item slot (used for both weapons and grenades).
## Locked items show weapon case icon and hidden name for future animated opening.
## @param condition_met: If true and item is locked, highlights the slot in gold to indicate
##                       the player has earned the right to unlock this item.
func _create_item_slot(item_id: String, item_data: Dictionary, is_grenade: bool, is_unlocked: bool, condition_met: bool = false) -> PanelContainer:
	var slot := PanelContainer.new()
	slot.name = item_id + "_slot"
	slot.custom_minimum_size = Vector2(90, 80)

	# Store metadata for click handling
	slot.set_meta("item_id", item_id)
	slot.set_meta("is_grenade", is_grenade)
	slot.set_meta("is_unlocked", is_unlocked)
	slot.set_meta("condition_met", condition_met)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 3)
	slot.add_child(vbox)

	# Item icon or weapon case for locked items
	var icon_container := CenterContainer.new()
	icon_container.custom_minimum_size = Vector2(48, 48)
	vbox.add_child(icon_container)

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
		# Locked item: show appropriate case icon based on type
		var case_texture_rect := TextureRect.new()
		case_texture_rect.custom_minimum_size = Vector2(48, 48)
		case_texture_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		case_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		case_texture_rect.name = "CaseIcon"  # Named for future animation access

		# Choose icon based on item type
		var case_icon_path: String
		if is_grenade:
			case_icon_path = GRENADE_CASE_ICON_PATH
		else:
			case_icon_path = WEAPON_CASE_ICON_PATH

		if ResourceLoader.exists(case_icon_path):
			var case_texture: Texture2D = load(case_icon_path)
			if case_texture:
				case_texture_rect.texture = case_texture
		icon_container.add_child(case_texture_rect)

	# Item name - hidden for locked items (requirement: names of closed items should be hidden)
	var name_label := Label.new()
	if is_unlocked:
		name_label.text = item_data.get("name", "???")
	else:
		# Hide name for locked items - empty label preserves slot layout
		name_label.text = ""
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(name_label)

	# Tooltip: description for unlocked items, unlock condition for locked items
	if is_unlocked:
		slot.tooltip_text = item_data.get("description", "")
	else:
		var unlock_desc: String = ""
		if _unlock_manager:
			if is_grenade:
				var grenade_type: int = item_data.get("grenade_type", int(item_id))
				if _unlock_manager.has_method("get_grenade_unlock_description"):
					unlock_desc = _unlock_manager.get_grenade_unlock_description(grenade_type)
			else:
				if _unlock_manager.has_method("get_weapon_unlock_description"):
					unlock_desc = _unlock_manager.get_weapon_unlock_description(item_id)
		slot.tooltip_text = unlock_desc

	# Make all items clickable (unlocked for selection, locked for unlocking)
	slot.mouse_filter = Control.MOUSE_FILTER_STOP
	slot.gui_input.connect(_on_slot_gui_input.bind(slot, item_id, is_grenade, item_data, is_unlocked, condition_met))
	if is_unlocked:
		slot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	else:
		# Locked items show pointing hand to indicate they can be unlocked
		slot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	# Apply style: gold if condition is met and item is locked, default otherwise
	if not is_unlocked and condition_met:
		_apply_condition_met_style(slot)
	else:
		_apply_default_style(slot)

	return slot


## Create an active item slot (separate handler for active item clicks).
## Locked items show weapon case icon and hidden name for future animated opening.
## @param condition_met: If true and item is locked, highlights the slot in gold to indicate
##                       the player has earned the right to unlock this item.
func _create_active_item_slot(item_id: String, item_data: Dictionary, item_type: int, is_unlocked: bool, condition_met: bool = false) -> PanelContainer:
	var slot := PanelContainer.new()
	slot.name = "active_" + item_id + "_slot"
	slot.custom_minimum_size = Vector2(90, 80)

	# Store metadata
	slot.set_meta("item_id", item_id)
	slot.set_meta("is_active_item", true)
	slot.set_meta("is_unlocked", is_unlocked)
	slot.set_meta("condition_met", condition_met)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 3)
	slot.add_child(vbox)

	# Item icon or placeholder
	var icon_container := CenterContainer.new()
	icon_container.custom_minimum_size = Vector2(48, 48)
	vbox.add_child(icon_container)

	var icon_path: String = item_data.get("icon_path", "")
	var item_name: String = item_data.get("name", "")

	if not is_unlocked:
		# Locked active item: show item case icon
		var case_texture_rect := TextureRect.new()
		case_texture_rect.custom_minimum_size = Vector2(48, 48)
		case_texture_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		case_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		case_texture_rect.name = "ItemCaseIcon"

		if ResourceLoader.exists(ITEM_CASE_ICON_PATH):
			var case_texture: Texture2D = load(ITEM_CASE_ICON_PATH)
			if case_texture:
				case_texture_rect.texture = case_texture
		icon_container.add_child(case_texture_rect)
	elif icon_path != "" and ResourceLoader.exists(icon_path):
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
		none_label.text = "-" if item_name == "None" else "?"
		none_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		none_label.add_theme_font_size_override("font_size", 24)
		none_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 0.8))
		icon_container.add_child(none_label)

	# Item name - hidden for locked items
	var name_label := Label.new()
	if is_unlocked:
		name_label.text = item_name if item_name != "" else "???"
	else:
		name_label.text = ""  # Hide name for locked items
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(name_label)

	# Tooltip: description for unlocked items, unlock condition for locked items
	if is_unlocked:
		slot.tooltip_text = item_data.get("description", "")
	else:
		var unlock_desc: String = ""
		if _unlock_manager and _unlock_manager.has_method("get_active_item_unlock_description"):
			unlock_desc = _unlock_manager.get_active_item_unlock_description(item_type)
		slot.tooltip_text = unlock_desc

	# Make all items clickable (unlocked for selection, locked for unlocking)
	slot.mouse_filter = Control.MOUSE_FILTER_STOP
	slot.gui_input.connect(_on_active_item_slot_gui_input.bind(slot, item_type, is_unlocked, condition_met))
	slot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	# Apply style: gold if condition is met and item is locked, default otherwise
	if not is_unlocked and condition_met:
		_apply_condition_met_style(slot)
	else:
		_apply_default_style(slot)

	return slot


## Handle click on an active item slot.
func _on_active_item_slot_gui_input(event: InputEvent, slot: PanelContainer, item_type: int, is_unlocked: bool, condition_met: bool = false) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if is_unlocked:
				# Unlocked item: select it immediately
				_pending_active_item_type = item_type

				# Play click sound via AudioManager
				var audio_manager = get_node_or_null("/root/AudioManager")
				if audio_manager and audio_manager.has_method("play_ui_click"):
					audio_manager.play_ui_click()

				# Update visuals to show pending selection
				_highlight_selected_items()
				_update_loadout_panel()
				_update_apply_button_state()

				# Play shake + glint animation on the selected slot
				_play_weapon_selection_animation(slot)
			elif condition_met:
				# Locked item with condition met: start tracking LMB hold for unlocking
				_lmb_hold_tracking[slot] = {
					"start_time": Time.get_ticks_msec() / 1000.0,
					"item_id": str(item_type),
					"is_grenade": false,
					"is_active_item": true,
					"active_item_type": item_type
				}
				# Start the unlock timer if not already running
				if not _unlock_timer.is_stopped():
					pass  # Already running
				else:
					_unlock_timer.start()
		else:
			# LMB released: stop tracking this slot and clean up visuals
			if slot in _lmb_hold_tracking:
				_lmb_hold_tracking.erase(slot)
				# Clean up progress overlay
				_remove_progress_overlay(slot)
			# Stop timer if no slots are being tracked
			if _lmb_hold_tracking.size() == 0:
				_unlock_timer.stop()


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


## Apply gold "condition met" style to a locked slot whose unlock condition has been satisfied.
## This highlights items in gold to indicate the player can now unlock them.
func _apply_condition_met_style(slot: PanelContainer) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.28, 0.22, 0.08, 0.85)
	style.border_color = Color(1.0, 0.8, 0.1, 1.0)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	slot.add_theme_stylebox_override("panel", style)


## Handle click on an item slot.
## Sets the pending selection (does NOT restart — user must press Apply).
## For locked items, holding LMB unlocks the item only if the unlock condition is met.
func _on_slot_gui_input(event: InputEvent, slot: PanelContainer, item_id: String, is_grenade: bool, item_data: Dictionary, is_unlocked: bool, condition_met: bool = false) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if is_unlocked:
				# Unlocked item: select it immediately
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

				# Play shake + glint animation on the selected slot
				_play_weapon_selection_animation(slot)
			elif condition_met:
				# Locked item with condition met: start tracking LMB hold for unlocking
				_lmb_hold_tracking[slot] = {
					"start_time": Time.get_ticks_msec() / 1000.0,
					"item_id": item_id,
					"is_grenade": is_grenade,
					"is_active_item": false,
					"grenade_type": item_data.get("grenade_type", 0) if is_grenade else -1
				}
				# Start the unlock timer if not already running
				if not _unlock_timer.is_stopped():
					pass  # Already running
				else:
					_unlock_timer.start()
		else:
			# LMB released: stop tracking this slot and clean up visuals
			if slot in _lmb_hold_tracking:
				_lmb_hold_tracking.erase(slot)
				# Clean up progress overlay
				_remove_progress_overlay(slot)
			# Stop timer if no slots are being tracked
			if _lmb_hold_tracking.size() == 0:
				_unlock_timer.stop()


## Check if the pending selection differs from the current applied selection.
func _has_pending_changes() -> bool:
	var current_weapon_id: String = "makarov_pm"
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
	var current_weapon_id: String = "makarov_pm"
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

	# Apply changes: either restart level or return to score screen (Issue #1006)
	if weapon_changed or grenade_changed or active_item_changed:
		if opened_from_score_screen:
			# Issue #1006: When opened from score screen, hide armory and return
			# to score screen instead of restarting the level.
			apply_pressed_from_score_screen.emit()
			queue_free()
		elif GameManager:
			get_tree().paused = false
			Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED_HIDDEN)
			GameManager.restart_scene()


## Highlight the currently selected (pending) weapon, grenade, and active item slots.
## Preserves gold condition-met styling for locked slots whose unlock condition is met.
func _highlight_selected_items() -> void:
	# Reset all weapon slots to default or condition-met gold
	for wid in _weapon_slots:
		var slot: PanelContainer = _weapon_slots[wid]
		var slot_unlocked: bool = slot.get_meta("is_unlocked", true)
		var slot_condition_met: bool = slot.get_meta("condition_met", false)
		if not slot_unlocked and slot_condition_met:
			_apply_condition_met_style(slot)
		else:
			_apply_default_style(slot)

	# Reset all grenade slots to default or condition-met gold
	for gtype in _grenade_slots:
		var slot: PanelContainer = _grenade_slots[gtype]
		var slot_unlocked: bool = slot.get_meta("is_unlocked", true)
		var slot_condition_met: bool = slot.get_meta("condition_met", false)
		if not slot_unlocked and slot_condition_met:
			_apply_condition_met_style(slot)
		else:
			_apply_default_style(slot)

	# Reset all active item slots to default or condition-met gold
	for atype in _active_item_slots:
		var slot: PanelContainer = _active_item_slots[atype]
		var slot_unlocked: bool = slot.get_meta("is_unlocked", true)
		var slot_condition_met: bool = slot.get_meta("condition_met", false)
		if not slot_unlocked and slot_condition_met:
			_apply_condition_met_style(slot)
		else:
			_apply_default_style(slot)

	# Highlight pending weapon
	if _pending_weapon_id in _weapon_slots:
		_apply_selected_style(_weapon_slots[_pending_weapon_id])

	# Highlight pending grenade
	if _pending_grenade_type in _grenade_slots:
		_apply_selected_style(_grenade_slots[_pending_grenade_type])

	# Highlight pending active item
	if _pending_active_item_type in _active_item_slots:
		_apply_selected_style(_active_item_slots[_pending_active_item_type])

	# Update accordion button gold highlights to reflect current condition_met states
	if _weapon_accordion_button and not _weapons_expanded:
		if _has_condition_met_in_overflow(_weapon_overflow_slots):
			_apply_accordion_button_condition_met_style(_weapon_accordion_button)
		else:
			_apply_accordion_button_default_style(_weapon_accordion_button)
	if _grenade_accordion_button and not _grenades_expanded:
		if _has_condition_met_in_overflow(_grenade_overflow_slots):
			_apply_accordion_button_condition_met_style(_grenade_accordion_button)
		else:
			_apply_accordion_button_default_style(_grenade_accordion_button)
	if _active_item_accordion_button and not _active_items_expanded:
		if _has_condition_met_in_overflow(_active_item_overflow_slots):
			_apply_accordion_button_condition_met_style(_active_item_accordion_button)
		else:
			_apply_accordion_button_default_style(_active_item_accordion_button)


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
	bbcode += "[b][color=#d4c896]SPECIAL: %s[/color][/b]\n" % item_name
	bbcode += "[color=#aab0b8]%s[/color]\n" % item_desc
	if _pending_active_item_type != 0:  # Not "None" (ActiveItemType.NONE)
		var activation_hint: String = item_data.get("activation_hint", "Hold Space to activate")
		bbcode += "\n[color=#888888]%s[/color]" % activation_hint

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


## Timer callback for checking unlock progress.
## Updates visual progress indicators and triggers unlock when threshold reached.
func _on_unlock_timer_timeout() -> void:
	var current_time: float = Time.get_ticks_msec() / 1000.0
	var slots_to_remove: Array = []

	for slot in _lmb_hold_tracking:
		var track_data: Dictionary = _lmb_hold_tracking[slot]
		var hold_duration: float = current_time - track_data["start_time"]
		var progress: float = minf(hold_duration / UNLOCK_HOLD_DURATION, 1.0)

		# Update visual progress
		_update_progress_overlay(slot, progress)

		# Play progress beep at certain thresholds (every 20% progress)
		var last_beep_threshold: float = track_data.get("last_beep_threshold", 0.0)
		var current_threshold: float = floor(progress * 5.0) / 5.0  # 0.0, 0.2, 0.4, 0.6, 0.8
		if current_threshold > last_beep_threshold:
			_play_progress_beep(progress)
			track_data["last_beep_threshold"] = current_threshold

		if hold_duration >= UNLOCK_HOLD_DURATION:
			# Unlock threshold reached - play reveal animation then unlock
			var slot_ref: PanelContainer = slot  # Capture for closure

			if track_data["is_active_item"]:
				# Unlock active item
				var item_type: int = track_data["active_item_type"]
				_play_unlock_reveal_animation(slot_ref, func():
					if _active_item_manager and _active_item_manager.has_method("unlock_active_item"):
						_active_item_manager.unlock_active_item(item_type)
						# Rebuild the slot to show unlocked state
						_rebuild_active_item_slot_animated(item_type)
				)
			elif track_data["is_grenade"]:
				# Unlock grenade
				var grenade_type: int = track_data["grenade_type"]
				_play_unlock_reveal_animation(slot_ref, func():
					if _grenade_manager and _grenade_manager.has_method("unlock_grenade"):
						_grenade_manager.unlock_grenade(grenade_type)
						# Rebuild the slot to show unlocked state
						_rebuild_grenade_slot_animated(grenade_type)
				)
			else:
				# Unlock weapon
				var weapon_id: String = track_data["item_id"]
				_play_unlock_reveal_animation(slot_ref, func():
					if GameManager and GameManager.has_method("unlock_weapon"):
						GameManager.unlock_weapon(weapon_id)
						# Rebuild the slot to show unlocked state
						_rebuild_weapon_slot_animated(weapon_id)
				)

			# Mark this slot for removal from tracking
			slots_to_remove.append(slot)

	# Remove unlocked slots from tracking
	for slot in slots_to_remove:
		_lmb_hold_tracking.erase(slot)

	# Stop timer if no slots are being tracked
	if _lmb_hold_tracking.size() == 0:
		_unlock_timer.stop()


## Rebuild a weapon slot to show unlocked state (legacy, no animation).
func _rebuild_weapon_slot(weapon_id: String) -> void:
	if weapon_id not in _weapon_slots:
		return

	var old_slot: PanelContainer = _weapon_slots[weapon_id]
	var parent: Node = old_slot.get_parent()
	var slot_index: int = old_slot.get_index()

	# Remove old slot
	parent.remove_child(old_slot)
	old_slot.queue_free()

	# Create new unlocked slot
	var weapon_data: Dictionary = FIREARMS[weapon_id]
	var new_slot := _create_item_slot(weapon_id, weapon_data, false, true)

	# Insert at same position
	parent.add_child(new_slot)
	parent.move_child(new_slot, slot_index)
	_weapon_slots[weapon_id] = new_slot

	# Update visuals
	_highlight_selected_items()


## Rebuild a weapon slot with animated item reveal.
func _rebuild_weapon_slot_animated(weapon_id: String) -> void:
	if weapon_id not in _weapon_slots:
		return

	var old_slot: PanelContainer = _weapon_slots[weapon_id]
	var parent: Node = old_slot.get_parent()
	var slot_index: int = old_slot.get_index()

	# Remove old slot
	parent.remove_child(old_slot)
	old_slot.queue_free()

	# Create new unlocked slot with initial fade-in state
	var weapon_data: Dictionary = FIREARMS[weapon_id]
	var new_slot := _create_item_slot(weapon_id, weapon_data, false, true)
	new_slot.modulate.a = 0.0  # Start invisible for fade-in

	# Insert at same position
	parent.add_child(new_slot)
	parent.move_child(new_slot, slot_index)
	_weapon_slots[weapon_id] = new_slot

	# Animate the new slot appearing
	_animate_slot_reveal(new_slot)

	# Update visuals
	_highlight_selected_items()


## Rebuild a grenade slot to show unlocked state (legacy, no animation).
func _rebuild_grenade_slot(grenade_type: int) -> void:
	if grenade_type not in _grenade_slots:
		return

	var old_slot: PanelContainer = _grenade_slots[grenade_type]
	var parent: Node = old_slot.get_parent()
	var slot_index: int = old_slot.get_index()

	# Remove old slot
	parent.remove_child(old_slot)
	old_slot.queue_free()

	# Create new unlocked slot
	if _grenade_manager:
		var gdata: Dictionary = _grenade_manager.get_grenade_data(grenade_type)
		var grenade_info := {
			"name": gdata.get("name", "Unknown"),
			"icon_path": gdata.get("icon_path", ""),
			"description": gdata.get("description", ""),
			"grenade_type": grenade_type
		}
		var new_slot := _create_item_slot(str(grenade_type), grenade_info, true, true)

		# Insert at same position
		parent.add_child(new_slot)
		parent.move_child(new_slot, slot_index)
		_grenade_slots[grenade_type] = new_slot

		# Update visuals
		_highlight_selected_items()


## Rebuild a grenade slot with animated item reveal.
func _rebuild_grenade_slot_animated(grenade_type: int) -> void:
	if grenade_type not in _grenade_slots:
		return

	var old_slot: PanelContainer = _grenade_slots[grenade_type]
	var parent: Node = old_slot.get_parent()
	var slot_index: int = old_slot.get_index()

	# Remove old slot
	parent.remove_child(old_slot)
	old_slot.queue_free()

	# Create new unlocked slot
	if _grenade_manager:
		var gdata: Dictionary = _grenade_manager.get_grenade_data(grenade_type)
		var grenade_info := {
			"name": gdata.get("name", "Unknown"),
			"icon_path": gdata.get("icon_path", ""),
			"description": gdata.get("description", ""),
			"grenade_type": grenade_type
		}
		var new_slot := _create_item_slot(str(grenade_type), grenade_info, true, true)
		new_slot.modulate.a = 0.0  # Start invisible for fade-in

		# Insert at same position
		parent.add_child(new_slot)
		parent.move_child(new_slot, slot_index)
		_grenade_slots[grenade_type] = new_slot

		# Animate the new slot appearing
		_animate_slot_reveal(new_slot)

		# Update visuals
		_highlight_selected_items()


## Rebuild an active item slot to show unlocked state (legacy, no animation).
func _rebuild_active_item_slot(item_type: int) -> void:
	if item_type not in _active_item_slots:
		return

	var old_slot: PanelContainer = _active_item_slots[item_type]
	var parent: Node = old_slot.get_parent()
	var slot_index: int = old_slot.get_index()

	# Remove old slot
	parent.remove_child(old_slot)
	old_slot.queue_free()

	# Create new unlocked slot
	if _active_item_manager:
		var adata: Dictionary = _active_item_manager.get_active_item_data(item_type)
		var item_info := {
			"name": adata.get("name", "Unknown"),
			"icon_path": adata.get("icon_path", ""),
			"description": adata.get("description", ""),
			"active_item_type": item_type
		}
		var new_slot := _create_active_item_slot(str(item_type), item_info, item_type, true)

		# Insert at same position
		parent.add_child(new_slot)
		parent.move_child(new_slot, slot_index)
		_active_item_slots[item_type] = new_slot

		# Update visuals
		_highlight_selected_items()


## Rebuild an active item slot with animated item reveal.
func _rebuild_active_item_slot_animated(item_type: int) -> void:
	if item_type not in _active_item_slots:
		return

	var old_slot: PanelContainer = _active_item_slots[item_type]
	var parent: Node = old_slot.get_parent()
	var slot_index: int = old_slot.get_index()

	# Remove old slot
	parent.remove_child(old_slot)
	old_slot.queue_free()

	# Create new unlocked slot
	if _active_item_manager:
		var adata: Dictionary = _active_item_manager.get_active_item_data(item_type)
		var item_info := {
			"name": adata.get("name", "Unknown"),
			"icon_path": adata.get("icon_path", ""),
			"description": adata.get("description", ""),
			"active_item_type": item_type
		}
		var new_slot := _create_active_item_slot(str(item_type), item_info, item_type, true)
		new_slot.modulate.a = 0.0  # Start invisible for fade-in

		# Insert at same position
		parent.add_child(new_slot)
		parent.move_child(new_slot, slot_index)
		_active_item_slots[item_type] = new_slot

		# Animate the new slot appearing
		_animate_slot_reveal(new_slot)

		# Update visuals
		_highlight_selected_items()


## Plays a shake + glint animation on a weapon/grenade/item slot when it is selected.
## The animation consists of:
##   1. A 4-step horizontal shake (right → left → right → settle) for tactile "punch" feel.
##   2. A simultaneous scale bump: slightly enlarge then spring back (TRANS_BACK ease).
##   3. A brightness flash (modulate) that briefly bleaches the slot white then fades back.
##
## Based on the 4-step pixel art animation principle from saint11.art/blog/pixel-art-tutorials/:
## anticipation → action → follow-through → settle.
func _play_weapon_selection_animation(slot: PanelContainer) -> void:
	# Kill any in-progress selection tween for this slot to avoid conflicts
	if slot in _active_selection_tweens:
		var old_tween = _active_selection_tweens[slot]
		if old_tween and old_tween.is_valid():
			old_tween.kill()
		_active_selection_tweens.erase(slot)
		# Reset any leftover modulate from a previous animation
		slot.modulate = Color(1.0, 1.0, 1.0, 1.0)

	var vbox: VBoxContainer = slot.get_child(0) as VBoxContainer
	if vbox == null:
		return

	# Ensure pivot is at the centre of the vbox for scale animations
	vbox.pivot_offset = vbox.size / 2.0

	# Store the original x position for the shake so we always return to it
	var original_x: float = vbox.position.x

	# --- GLINT OVERLAY ---
	# Create a short-lived ColorRect that sweeps diagonally across the icon to simulate
	# light reflecting off the weapon surface (the "blick"/glint requested in the issue).
	var icon_container: CenterContainer = vbox.get_child(0) as CenterContainer
	if icon_container:
		# Clip the glint to the icon bounds
		icon_container.clip_contents = true

		var glint := ColorRect.new()
		glint.name = "_glint_overlay"
		glint.color = Color(1.0, 1.0, 1.0, 0.0)
		# Make the glint a narrow vertical band, rotated ~30° for diagonal effect.
		# Width is intentionally wider than the container; it enters from the left.
		glint.custom_minimum_size = Vector2(12, 200)
		glint.size = Vector2(12, 200)
		glint.rotation_degrees = 30.0
		# Start the glint to the left of the visible area
		glint.position = Vector2(-20, -60)
		icon_container.add_child(glint)

		# Animate the glint sweep: slide from left to right while fading in then out
		var glint_tween := create_tween()
		glint_tween.set_parallel(true)
		# Fade in then out (two sequential steps)
		glint_tween.tween_property(glint, "color:a", 0.65, 0.07)
		glint_tween.tween_property(glint, "color:a", 0.0, 0.12).set_delay(0.07)
		# Sweep from left (-20) to beyond right edge of icon container (~60)
		glint_tween.tween_property(glint, "position:x", 64.0, 0.19).set_ease(Tween.EASE_OUT)
		# Remove the glint node once the animation is done
		glint_tween.tween_callback(glint.queue_free).set_delay(0.20)

	# --- SCALE BUMP (4-step: squish start → overshoot → spring back → settle) ---
	# Step 1 — anticipation: squish slightly
	vbox.scale = Vector2(0.92, 0.92)

	# --- BUILD MAIN TWEEN (sequential shake + parallel scale spring) ---
	var tween := create_tween()
	_active_selection_tweens[slot] = tween

	# Scale: spring back to normal with TRANS_BACK overshoot (settle naturally)
	# Run in parallel with the shake below
	tween.set_parallel(true)
	tween.tween_property(vbox, "scale", Vector2(1.0, 1.0), 0.22) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

	# Brightness flash: slot briefly bleaches to near-white then fades back
	tween.tween_property(slot, "modulate", Color(1.9, 1.9, 1.9, 1.0), 0.05) \
		.set_ease(Tween.EASE_IN)
	tween.tween_property(slot, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.18) \
		.set_ease(Tween.EASE_OUT).set_delay(0.05)

	# Horizontal shake (sequential, runs alongside the scale/brightness in parallel mode)
	# Step 1 — action: jolt right
	tween.tween_property(vbox, "position:x", original_x + 4.0, 0.04) \
		.set_ease(Tween.EASE_OUT)
	# Step 2 — follow-through: swing left past centre
	tween.tween_property(vbox, "position:x", original_x - 5.0, 0.05) \
		.set_ease(Tween.EASE_IN_OUT)
	# Step 3 — rebound: move back right slightly
	tween.tween_property(vbox, "position:x", original_x + 2.0, 0.04) \
		.set_ease(Tween.EASE_IN_OUT)
	# Step 4 — settle: return to original position
	tween.tween_property(vbox, "position:x", original_x, 0.07) \
		.set_ease(Tween.EASE_OUT)

	# Clean up tracking entry when done
	tween.tween_callback(func():
		if slot in _active_selection_tweens:
			_active_selection_tweens.erase(slot)
		# Ensure position is exactly restored even if tween was interrupted
		if is_instance_valid(vbox):
			vbox.position.x = original_x
	)


## Animates a newly created slot appearing with fade-in and scale pop.
func _animate_slot_reveal(slot: PanelContainer) -> void:
	# Get the VBoxContainer for scale animation
	var vbox: VBoxContainer = slot.get_child(0) as VBoxContainer
	if vbox:
		vbox.pivot_offset = vbox.size / 2
		vbox.scale = Vector2(0.5, 0.5)

	# Create the reveal animation
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(slot, "modulate:a", 1.0, 0.3).set_ease(Tween.EASE_OUT)
	if vbox:
		tween.tween_property(vbox, "scale", Vector2(1.0, 1.0), 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause"):
		_on_back_pressed()
		get_viewport().set_input_as_handled()


func _on_back_pressed() -> void:
	back_pressed.emit()


## Creates a simple sine wave beep sound and plays it.
## @param frequency: The frequency of the beep in Hz.
## @param duration: Duration of the beep in seconds.
## @param volume_db: Volume in decibels (default -10).
func _play_beep(frequency: float, duration: float = 0.05, volume_db: float = -10.0) -> void:
	if _unlock_audio_player == null:
		return

	# Create a simple AudioStreamGenerator for the beep
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = 44100.0
	generator.buffer_length = 0.1

	_unlock_audio_player.stream = generator
	_unlock_audio_player.volume_db = volume_db
	_unlock_audio_player.play()

	var playback: AudioStreamGeneratorPlayback = _unlock_audio_player.get_stream_playback()

	# Generate sine wave samples
	var sample_rate: float = 44100.0
	var num_samples: int = int(duration * sample_rate)

	for i in range(num_samples):
		var t: float = float(i) / sample_rate
		# Sine wave with envelope (fade out)
		var envelope: float = 1.0 - (float(i) / float(num_samples))
		envelope = envelope * envelope  # Quadratic falloff
		var sample: float = sin(2.0 * PI * frequency * t) * envelope * 0.3
		playback.push_frame(Vector2(sample, sample))


## Plays a rising anticipation beep based on progress (0.0 to 1.0).
## The frequency increases as progress approaches completion.
func _play_progress_beep(progress: float) -> void:
	# Frequency rises from 220Hz to 880Hz based on progress
	var frequency: float = BEEP_BASE_FREQUENCY * 0.5 * (1.0 + progress * 2.0)
	_play_beep(frequency, 0.03, -15.0)


## Plays a celebratory success sound when item is unlocked.
func _play_unlock_success_sound() -> void:
	# Play ascending arpeggio for celebration
	var base: float = BEEP_BASE_FREQUENCY
	for i in range(4):
		var semitones: int = [0, 4, 7, 12][i]
		var frequency: float = base * pow(2.0, float(semitones) / 12.0)
		get_tree().create_timer(i * 0.08).timeout.connect(
			func(): _play_beep(frequency, 0.15, -8.0)
		)


## Creates a progress overlay for a slot to show unlock progress.
## Returns the created ColorRect overlay.
func _create_progress_overlay(slot: PanelContainer) -> ColorRect:
	# Create progress bar overlay
	var overlay := ColorRect.new()
	overlay.name = "UnlockProgressOverlay"
	overlay.color = Color(0.3, 0.8, 0.3, 0.0)  # Start invisible
	overlay.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	overlay.anchor_top = 1.0
	overlay.anchor_bottom = 1.0
	overlay.offset_top = -4
	overlay.offset_bottom = 0
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(overlay)
	return overlay


## Creates a glow/flash overlay for the unlock animation.
func _create_glow_overlay(slot: PanelContainer) -> ColorRect:
	var glow := ColorRect.new()
	glow.name = "UnlockGlowOverlay"
	glow.color = Color(1.0, 1.0, 1.0, 0.0)  # Start invisible
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(glow)
	return glow


## Updates the progress overlay visual to show current unlock progress.
func _update_progress_overlay(slot: PanelContainer, progress: float) -> void:
	var overlay: ColorRect = _slot_progress_overlays.get(slot)
	if overlay == null:
		overlay = _create_progress_overlay(slot)
		_slot_progress_overlays[slot] = overlay

	# Update overlay height to show progress (from bottom up)
	var slot_height: float = slot.size.y
	overlay.anchor_top = 1.0 - progress
	overlay.anchor_bottom = 1.0
	overlay.offset_top = 0
	overlay.offset_bottom = 0

	# Fade in the overlay
	overlay.color = Color(0.3, 0.8, 0.3, 0.4 + progress * 0.3)

	# Apply shaking effect to inner container to avoid GridContainer layout conflicts
	var shake_intensity: float = progress * 3.0
	var vbox: VBoxContainer = slot.get_child(0) as VBoxContainer
	if vbox:
		# Use offset on inner VBoxContainer instead of slot position to avoid GridContainer layout conflicts
		vbox.position = Vector2(
			randf_range(-shake_intensity, shake_intensity),
			randf_range(-shake_intensity, shake_intensity)
		)


## Removes the progress overlay from a slot and resets position.
func _remove_progress_overlay(slot: PanelContainer) -> void:
	var overlay: ColorRect = _slot_progress_overlays.get(slot)
	if overlay != null:
		overlay.queue_free()
		_slot_progress_overlays.erase(slot)
	# Reset inner container position to avoid visual offset
	var vbox: VBoxContainer = slot.get_child(0) as VBoxContainer
	if vbox:
		vbox.position = Vector2.ZERO


## Plays the animated unlock reveal sequence for a slot.
func _play_unlock_reveal_animation(slot: PanelContainer, callback: Callable) -> void:
	# Remove any progress overlay first
	_remove_progress_overlay(slot)

	# Play success sound
	_play_unlock_success_sound()

	# Create glow overlay for flash effect
	var glow := _create_glow_overlay(slot)

	# Get the icon container for scale animation
	var vbox: VBoxContainer = slot.get_child(0) as VBoxContainer
	var icon_container: CenterContainer = vbox.get_child(0) as CenterContainer if vbox else null

	# Create the reveal animation sequence
	var tween := create_tween()
	_active_reveal_tweens[slot] = tween

	# Phase 1: Flash white (0.15s)
	tween.tween_property(glow, "color:a", 0.8, 0.1).set_ease(Tween.EASE_OUT)

	# Phase 2: Pop scale effect (0.2s)
	if icon_container:
		tween.set_parallel(true)
		tween.tween_property(icon_container, "scale", Vector2(1.3, 1.3), 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tween.set_parallel(false)

	# Phase 3: Settle back and fade glow (0.3s)
	tween.tween_property(glow, "color:a", 0.0, 0.3).set_ease(Tween.EASE_IN)
	if icon_container:
		tween.set_parallel(true)
		tween.tween_property(icon_container, "scale", Vector2(1.0, 1.0), 0.2).set_ease(Tween.EASE_OUT)
		tween.set_parallel(false)

	# Cleanup and trigger callback after animation
	tween.tween_callback(func():
		glow.queue_free()
		_active_reveal_tweens.erase(slot)
		callback.call()
	)
