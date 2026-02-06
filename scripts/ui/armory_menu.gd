extends CanvasLayer
## Armory menu for selecting weapons and grenades by category.
##
## Displays weapons and grenades in separate sections with category headers.
## Shows a "Current Loadout" panel with detailed stats for the selected
## weapon and grenade. Selecting a different item will restart the level.
## Designed for extensibility — new categories can be added as sections.

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
		"icon_path": "res://assets/sprites/weapons/silenced_pistol_topdown.png",
		"unlocked": true,
		"description": "Beretta M9 with suppressor — silent, stuns enemies on hit"
	},
	"sniper": {
		"name": "ASVK",
		"icon_path": "res://assets/sprites/weapons/asvk_topdown.png",
		"unlocked": true,
		"description": "Anti-materiel sniper — bolt-action, penetrates walls and enemies"
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

## Reference to UI elements — these are created in code, not from scene nodes.
var _scroll_container: ScrollContainer
var _main_vbox: VBoxContainer
var _weapon_grid: GridContainer
var _grenade_grid: GridContainer
var _loadout_panel: PanelContainer
var _weapon_stats_label: RichTextLabel
var _grenade_stats_label: RichTextLabel
var _back_button: Button

## Currently selected weapon slot (for visual highlighting).
var _selected_slot: PanelContainer = null

## Map of weapon slots by weapon ID.
var _weapon_slots: Dictionary = {}

## Map of grenade slots by grenade type.
var _grenade_slots: Dictionary = {}

## Reference to GrenadeManager autoload.
var _grenade_manager: Node = null

## Cached weapon resource data.
var _weapon_resources: Dictionary = {}


func _ready() -> void:
	# Get GrenadeManager reference
	_grenade_manager = get_node_or_null("/root/GrenadeManager")

	# Load weapon resource data
	_load_weapon_resources()

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

	# Centered panel
	var panel := PanelContainer.new()
	panel.name = "MainPanel"
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -380
	panel.offset_top = -310
	panel.offset_right = 380
	panel.offset_bottom = 310
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
	margin.add_theme_constant_override("margin_top", 15)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 15)
	panel.add_child(margin)

	# Main vertical layout
	_main_vbox = VBoxContainer.new()
	_main_vbox.layout_mode = 2
	_main_vbox.add_theme_constant_override("separation", 10)
	margin.add_child(_main_vbox)

	# Title
	var title := Label.new()
	title.text = "ARMORY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7, 1.0))
	_main_vbox.add_child(title)

	# Separator
	var sep := HSeparator.new()
	_main_vbox.add_child(sep)

	# Scrollable area for weapons + grenades + loadout
	_scroll_container = ScrollContainer.new()
	_scroll_container.layout_mode = 2
	_scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll_container.custom_minimum_size = Vector2(0, 420)
	_main_vbox.add_child(_scroll_container)

	var scroll_vbox := VBoxContainer.new()
	scroll_vbox.layout_mode = 2
	scroll_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_vbox.add_theme_constant_override("separation", 10)
	_scroll_container.add_child(scroll_vbox)

	# --- WEAPONS SECTION ---
	_add_category_header(scroll_vbox, "WEAPONS")
	_weapon_grid = GridContainer.new()
	_weapon_grid.columns = 4
	_weapon_grid.layout_mode = 2
	_weapon_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_weapon_grid.add_theme_constant_override("h_separation", 10)
	_weapon_grid.add_theme_constant_override("v_separation", 10)
	scroll_vbox.add_child(_weapon_grid)

	# Populate weapon grid
	for weapon_id in FIREARMS:
		var weapon_data: Dictionary = FIREARMS[weapon_id]
		var slot := _create_item_slot(weapon_id, weapon_data, false)
		_weapon_grid.add_child(slot)
		_weapon_slots[weapon_id] = slot

	# --- GRENADES SECTION ---
	var grenade_sep := HSeparator.new()
	grenade_sep.add_theme_constant_override("separation", 5)
	scroll_vbox.add_child(grenade_sep)

	_add_category_header(scroll_vbox, "GRENADES")
	_grenade_grid = GridContainer.new()
	_grenade_grid.columns = 4
	_grenade_grid.layout_mode = 2
	_grenade_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grenade_grid.add_theme_constant_override("h_separation", 10)
	_grenade_grid.add_theme_constant_override("v_separation", 10)
	scroll_vbox.add_child(_grenade_grid)

	# Populate grenade grid from GrenadeManager
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

	# --- CURRENT LOADOUT SECTION ---
	var loadout_sep := HSeparator.new()
	loadout_sep.add_theme_constant_override("separation", 5)
	scroll_vbox.add_child(loadout_sep)

	_add_category_header(scroll_vbox, "CURRENT LOADOUT")
	_loadout_panel = PanelContainer.new()
	_loadout_panel.layout_mode = 2
	var loadout_style := StyleBoxFlat.new()
	loadout_style.bg_color = Color(0.15, 0.18, 0.2, 0.9)
	loadout_style.corner_radius_top_left = 6
	loadout_style.corner_radius_top_right = 6
	loadout_style.corner_radius_bottom_left = 6
	loadout_style.corner_radius_bottom_right = 6
	loadout_style.border_color = Color(0.3, 0.4, 0.35, 0.8)
	loadout_style.border_width_left = 1
	loadout_style.border_width_right = 1
	loadout_style.border_width_top = 1
	loadout_style.border_width_bottom = 1
	_loadout_panel.add_theme_stylebox_override("panel", loadout_style)
	scroll_vbox.add_child(_loadout_panel)

	var loadout_margin := MarginContainer.new()
	loadout_margin.layout_mode = 2
	loadout_margin.add_theme_constant_override("margin_left", 12)
	loadout_margin.add_theme_constant_override("margin_top", 8)
	loadout_margin.add_theme_constant_override("margin_right", 12)
	loadout_margin.add_theme_constant_override("margin_bottom", 8)
	_loadout_panel.add_child(loadout_margin)

	var loadout_hbox := HBoxContainer.new()
	loadout_hbox.layout_mode = 2
	loadout_hbox.add_theme_constant_override("separation", 20)
	loadout_margin.add_child(loadout_hbox)

	# Weapon stats (left side)
	_weapon_stats_label = RichTextLabel.new()
	_weapon_stats_label.layout_mode = 2
	_weapon_stats_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_weapon_stats_label.bbcode_enabled = true
	_weapon_stats_label.fit_content = true
	_weapon_stats_label.scroll_active = false
	_weapon_stats_label.add_theme_font_size_override("normal_font_size", 13)
	loadout_hbox.add_child(_weapon_stats_label)

	# Vertical separator between weapon and grenade stats
	var vsep := VSeparator.new()
	loadout_hbox.add_child(vsep)

	# Grenade stats (right side)
	_grenade_stats_label = RichTextLabel.new()
	_grenade_stats_label.layout_mode = 2
	_grenade_stats_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grenade_stats_label.bbcode_enabled = true
	_grenade_stats_label.fit_content = true
	_grenade_stats_label.scroll_active = false
	_grenade_stats_label.add_theme_font_size_override("normal_font_size", 13)
	loadout_hbox.add_child(_grenade_stats_label)

	# --- BACK BUTTON ---
	_back_button = Button.new()
	_back_button.text = "Back"
	_back_button.custom_minimum_size = Vector2(200, 36)
	_back_button.layout_mode = 2
	_back_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_back_button.pressed.connect(_on_back_pressed)
	_main_vbox.add_child(_back_button)

	# Highlight current selections and update loadout panel
	_highlight_selected_items()
	_update_loadout_panel()


## Add a styled category header label.
func _add_category_header(parent: VBoxContainer, text: String) -> void:
	var header := Label.new()
	header.text = text
	header.add_theme_font_size_override("font_size", 15)
	header.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8, 1.0))
	parent.add_child(header)


## Create an item slot (used for both weapons and grenades).
func _create_item_slot(item_id: String, item_data: Dictionary, is_grenade: bool) -> PanelContainer:
	var slot := PanelContainer.new()
	slot.name = item_id + "_slot"
	slot.custom_minimum_size = Vector2(100, 90)

	# Store metadata for click handling
	slot.set_meta("item_id", item_id)
	slot.set_meta("is_grenade", is_grenade)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 4)
	slot.add_child(vbox)

	# Item icon or lock placeholder
	var icon_container := CenterContainer.new()
	icon_container.custom_minimum_size = Vector2(56, 56)
	vbox.add_child(icon_container)

	var is_unlocked: bool = item_data.get("unlocked", false)

	if is_unlocked and item_data.get("icon_path", "") != "":
		var texture_rect := TextureRect.new()
		texture_rect.custom_minimum_size = Vector2(56, 56)
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
		lock_label.add_theme_font_size_override("font_size", 28)
		lock_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 0.8))
		icon_container.add_child(lock_label)

	# Item name
	var name_label := Label.new()
	name_label.text = item_data.get("name", "???")
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 12)
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
func _on_slot_gui_input(event: InputEvent, slot: PanelContainer, item_id: String, is_grenade: bool, item_data: Dictionary) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if is_grenade:
			var grenade_type: int = item_data.get("grenade_type", 0)
			_select_grenade(grenade_type)
		else:
			_select_weapon(item_id)

		# Play click sound via AudioManager
		var audio_manager = get_node_or_null("/root/AudioManager")
		if audio_manager and audio_manager.has_method("play_ui_click"):
			audio_manager.play_ui_click()


## Select a weapon and update GameManager.
## This will restart the level if a different weapon is selected.
func _select_weapon(weapon_id: String) -> void:
	# Check if already selected
	var current_weapon_id: String = "m16"
	if GameManager:
		current_weapon_id = GameManager.get_selected_weapon()

	if weapon_id == current_weapon_id:
		return

	# Update selection in GameManager
	if GameManager:
		GameManager.set_selected_weapon(weapon_id)

	# Emit signal for external listeners
	weapon_selected.emit(weapon_id)

	# Update visual highlighting and loadout panel
	_highlight_selected_items()
	_update_loadout_panel()

	# Restart the level to apply the new weapon
	if GameManager:
		get_tree().paused = false
		Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED_HIDDEN)
		GameManager.restart_scene()


## Select a grenade and update GrenadeManager.
## This will restart the level.
func _select_grenade(grenade_type: int) -> void:
	if _grenade_manager == null:
		return

	if _grenade_manager.is_selected(grenade_type):
		return

	_grenade_manager.set_grenade_type(grenade_type, true)


## Highlight the currently selected weapon and grenade slots.
func _highlight_selected_items() -> void:
	var current_weapon_id: String = "m16"
	if GameManager:
		current_weapon_id = GameManager.get_selected_weapon()

	var current_grenade_type: int = 0
	if _grenade_manager:
		current_grenade_type = _grenade_manager.current_grenade_type

	# Reset all weapon slots to default
	for wid in _weapon_slots:
		_apply_default_style(_weapon_slots[wid])

	# Reset all grenade slots to default
	for gtype in _grenade_slots:
		_apply_default_style(_grenade_slots[gtype])

	# Highlight selected weapon
	if current_weapon_id in _weapon_slots:
		_apply_selected_style(_weapon_slots[current_weapon_id])

	# Highlight selected grenade
	if current_grenade_type in _grenade_slots:
		_apply_selected_style(_grenade_slots[current_grenade_type])


## Update the Current Loadout panel with stats for selected weapon and grenade.
func _update_loadout_panel() -> void:
	_update_weapon_stats()
	_update_grenade_stats()


## Update weapon stats in the loadout panel.
func _update_weapon_stats() -> void:
	if _weapon_stats_label == null:
		return

	var current_weapon_id: String = "m16"
	if GameManager:
		current_weapon_id = GameManager.get_selected_weapon()

	var weapon_info: Dictionary = FIREARMS.get(current_weapon_id, {})
	var weapon_name: String = weapon_info.get("name", "Unknown")

	# Try to load weapon resource for detailed stats
	var resource = _weapon_resources.get(current_weapon_id)

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
		bbcode += "[color=#aab0b8]Damage:[/color] %s  [color=#aab0b8]Rate:[/color] %.0f/s\n" % [damage_text, fire_rate]

		# Magazine
		var mag_size: int = resource.get("MagazineSize")
		var reserve: int = resource.get("MaxReserveAmmo")
		bbcode += "[color=#aab0b8]Magazine:[/color] %d rnd  [color=#aab0b8]Reserve:[/color] %d\n" % [mag_size, reserve]

		# Reload time
		var reload: float = resource.get("ReloadTime")
		bbcode += "[color=#aab0b8]Reload:[/color] %.1fs\n" % reload

		# Range & Spread
		var weapon_range: float = resource.get("Range")
		var spread: float = resource.get("SpreadAngle")
		bbcode += "[color=#aab0b8]Range:[/color] %.0fpx  [color=#aab0b8]Spread:[/color] %.1f°\n" % [weapon_range, spread]

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


## Update grenade stats in the loadout panel.
func _update_grenade_stats() -> void:
	if _grenade_stats_label == null:
		return

	var current_grenade_type: int = 0
	if _grenade_manager:
		current_grenade_type = _grenade_manager.current_grenade_type

	var grenade_data: Dictionary = {}
	if _grenade_manager:
		grenade_data = _grenade_manager.get_grenade_data(current_grenade_type)

	var grenade_name: String = grenade_data.get("name", "Unknown")
	var grenade_desc: String = grenade_data.get("description", "No data available")

	var bbcode: String = ""
	bbcode += "[b][color=#d4c896]GRENADE: %s[/color][/b]\n" % grenade_name
	bbcode += "[color=#aab0b8]%s[/color]\n" % grenade_desc
	bbcode += "\n[color=#888888]Press G + RMB drag to throw[/color]"

	_grenade_stats_label.text = bbcode


## Refresh the weapon grid (called when menu is reshown).
func _populate_weapon_grid() -> void:
	_highlight_selected_items()
	_update_loadout_panel()


func _on_back_pressed() -> void:
	back_pressed.emit()
