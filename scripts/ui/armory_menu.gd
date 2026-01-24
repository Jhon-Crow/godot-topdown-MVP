extends CanvasLayer
## Armory menu for viewing unlocked and locked weapons.
##
## Displays a grid of weapons showing which are unlocked (available) and
## which are locked (coming in future updates). Also shows available grenades.
## Selecting a different grenade will restart the level.

## Signal emitted when the back button is pressed.
signal back_pressed

## Signal emitted when a weapon is selected.
signal weapon_selected(weapon_id: String)

## Dictionary of all weapons with their data.
## Keys: weapon_id, Values: dictionary with name, icon_path, unlocked status
const WEAPONS: Dictionary = {
	"m16": {
		"name": "M16",
		"icon_path": "res://assets/sprites/weapons/m16_rifle.png",
		"unlocked": true,
		"description": "Standard assault rifle",
		"is_grenade": false
	},
	"flashbang": {
		"name": "Flashbang",
		"icon_path": "res://assets/sprites/weapons/flashbang.png",
		"unlocked": true,
		"description": "Stun grenade - blinds enemies for 12s, stuns for 6s. Press G + RMB drag to throw.",
		"is_grenade": true,
		"grenade_type": 0
	},
	"frag_grenade": {
		"name": "Frag Grenade",
		"icon_path": "res://assets/sprites/weapons/frag_grenade.png",
		"unlocked": true,
		"description": "Offensive grenade - explodes on impact, releases 4 shrapnel pieces that ricochet. Press G + RMB drag to throw.",
		"is_grenade": true,
		"grenade_type": 1
	},
	"ak47": {
		"name": "???",
		"icon_path": "",
		"unlocked": false,
		"description": "Coming soon",
		"is_grenade": false
	},
	"shotgun": {
		"name": "Shotgun",
		"icon_path": "res://assets/sprites/weapons/shotgun_icon.png",
		"unlocked": true,
		"description": "Pump-action shotgun - 6-12 pellets per shot, 15° spread, no wall penetration. Press LMB to fire.",
		"is_grenade": false
	},
	"mini_uzi": {
		"name": "Mini UZI",
		"icon_path": "res://assets/sprites/weapons/mini_uzi_icon.png",
		"unlocked": true,
		"description": "Submachine gun - 15 shots/sec, 9mm bullets (0.5 damage), high spread, ricochets at ≤20°, no wall penetration. Press LMB to fire.",
		"is_grenade": false
	},
	"silenced_pistol": {
		"name": "Silenced Pistol",
		"icon_path": "res://assets/sprites/weapons/silenced_pistol_topdown.png",
		"unlocked": true,
		"description": "Beretta M9 with suppressor - semi-auto, 9mm, 13 rounds, silent shots, enemies stunned on hit (can't move/shoot until next shot). Press LMB to fire.",
		"is_grenade": false
	},
	"smg": {
		"name": "???",
		"icon_path": "",
		"unlocked": false,
		"description": "Coming soon",
		"is_grenade": false
	},
	"sniper": {
		"name": "???",
		"icon_path": "",
		"unlocked": false,
		"description": "Coming soon",
		"is_grenade": false
	},
	"pistol": {
		"name": "???",
		"icon_path": "",
		"unlocked": false,
		"description": "Coming soon",
		"is_grenade": false
	}
}

## Reference to UI elements.
@onready var weapon_grid: GridContainer = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/ScrollContainer/WeaponGrid
@onready var back_button: Button = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/BackButton
@onready var status_label: Label = $MenuContainer/PanelContainer/MarginContainer/VBoxContainer/StatusLabel

## Currently selected weapon slot (for visual highlighting).
var _selected_slot: PanelContainer = null

## Map of weapon slots by weapon ID.
var _weapon_slots: Dictionary = {}

## Reference to GrenadeManager autoload.
var _grenade_manager: Node = null


func _ready() -> void:
	# Connect button signals
	back_button.pressed.connect(_on_back_pressed)

	# Get GrenadeManager reference
	_grenade_manager = get_node_or_null("/root/GrenadeManager")

	# Populate weapon grid
	_populate_weapon_grid()

	# Set process mode to allow input while paused
	process_mode = Node.PROCESS_MODE_ALWAYS


func _populate_weapon_grid() -> void:
	# Clear existing children and slot tracking
	for child in weapon_grid.get_children():
		child.queue_free()
	_weapon_slots.clear()
	_selected_slot = null

	# Count unlocked weapons for status
	var unlocked_count: int = 0
	var total_count: int = WEAPONS.size()

	# Create a slot for each weapon
	for weapon_id in WEAPONS:
		var weapon_data: Dictionary = WEAPONS[weapon_id]
		var slot := _create_weapon_slot(weapon_id, weapon_data)
		weapon_grid.add_child(slot)
		_weapon_slots[weapon_id] = slot

		if weapon_data["unlocked"]:
			unlocked_count += 1

	# Update status label
	status_label.text = "Unlocked: %d / %d" % [unlocked_count, total_count]

	# Highlight currently selected weapon and grenade from managers
	_highlight_selected_items()


func _create_weapon_slot(weapon_id: String, weapon_data: Dictionary) -> PanelContainer:
	var slot := PanelContainer.new()
	slot.name = weapon_id + "_slot"
	slot.custom_minimum_size = Vector2(100, 100)

	# Store weapon_id in slot's metadata for click handling
	slot.set_meta("weapon_id", weapon_id)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	slot.add_child(vbox)

	# Weapon icon or placeholder
	var icon_container := CenterContainer.new()
	icon_container.custom_minimum_size = Vector2(64, 64)
	vbox.add_child(icon_container)

	if weapon_data["unlocked"] and weapon_data["icon_path"] != "":
		var texture_rect := TextureRect.new()
		texture_rect.custom_minimum_size = Vector2(64, 64)
		texture_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

		var texture: Texture2D = load(weapon_data["icon_path"])
		if texture:
			texture_rect.texture = texture

		icon_container.add_child(texture_rect)
	else:
		# Locked weapon - show lock icon (using text for now)
		var lock_label := Label.new()
		lock_label.text = "🔒"
		lock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lock_label.add_theme_font_size_override("font_size", 32)
		icon_container.add_child(lock_label)

	# Weapon name
	var name_label := Label.new()
	name_label.text = weapon_data["name"]
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	if not weapon_data["unlocked"]:
		name_label.modulate = Color(0.5, 0.5, 0.5)

	vbox.add_child(name_label)

	# Add tooltip
	slot.tooltip_text = weapon_data["description"]

	# Make unlocked weapons clickable
	if weapon_data["unlocked"]:
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		slot.gui_input.connect(_on_slot_gui_input.bind(slot, weapon_id))
		# Change cursor on hover for clickable slots
		slot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	else:
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE

	return slot


## Handle click on weapon slot.
func _on_slot_gui_input(event: InputEvent, slot: PanelContainer, weapon_id: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var weapon_data: Dictionary = WEAPONS.get(weapon_id, {})
		var is_grenade: bool = weapon_data.get("is_grenade", false)

		if is_grenade:
			_select_grenade(weapon_id, weapon_data)
		else:
			_select_weapon(weapon_id)

		# Play click sound via AudioManager
		var audio_manager = get_node_or_null("/root/AudioManager")
		if audio_manager and audio_manager.has_method("play_ui_click"):
			audio_manager.play_ui_click()


## Select a weapon and update GameManager.
## This will restart the level if a different weapon is selected.
func _select_weapon(weapon_id: String) -> void:
	# Check if already selected
	var current_weapon_id: String = "m16"  # Default
	if GameManager:
		current_weapon_id = GameManager.get_selected_weapon()

	if weapon_id == current_weapon_id:
		return  # Already selected, no need to restart

	# Update selection in GameManager
	if GameManager:
		GameManager.set_selected_weapon(weapon_id)

	# Emit signal for external listeners
	weapon_selected.emit(weapon_id)

	# Update visual highlighting
	_highlight_selected_items()

	# Restart the level to apply the new weapon (like grenades do)
	if GameManager:
		# IMPORTANT: Unpause the game before restarting
		# This prevents the game from getting stuck in paused state when
		# changing weapons from the armory menu while the game is paused
		get_tree().paused = false

		# Restore hidden cursor for gameplay (confined and hidden)
		Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED_HIDDEN)

		GameManager.restart_scene()


## Select a grenade and update GrenadeManager.
## This will restart the level.
func _select_grenade(weapon_id: String, weapon_data: Dictionary) -> void:
	if _grenade_manager == null:
		return

	var grenade_type: int = weapon_data.get("grenade_type", 0)

	# Check if already selected
	if _grenade_manager.is_selected(grenade_type):
		return

	# Set new grenade type - this will restart the level
	_grenade_manager.set_grenade_type(grenade_type, true)


## Highlight the currently selected weapon and grenade slots.
func _highlight_selected_items() -> void:
	var current_weapon_id: String = "m16"  # Default
	if GameManager:
		current_weapon_id = GameManager.get_selected_weapon()

	# Get currently selected grenade type
	var current_grenade_type: int = 0  # Default to flashbang
	if _grenade_manager:
		current_grenade_type = _grenade_manager.current_grenade_type

	# Reset all slots to default style
	for wid in _weapon_slots:
		var slot: PanelContainer = _weapon_slots[wid]
		# Create default style (transparent/subtle background)
		var default_style := StyleBoxFlat.new()
		default_style.bg_color = Color(0.2, 0.2, 0.2, 0.5)
		default_style.corner_radius_top_left = 4
		default_style.corner_radius_top_right = 4
		default_style.corner_radius_bottom_left = 4
		default_style.corner_radius_bottom_right = 4
		slot.add_theme_stylebox_override("panel", default_style)

	# Highlight selected weapon slot (non-grenade)
	if current_weapon_id in _weapon_slots:
		var weapon_data: Dictionary = WEAPONS.get(current_weapon_id, {})
		if not weapon_data.get("is_grenade", false):
			_apply_selected_style(_weapon_slots[current_weapon_id])

	# Highlight selected grenade slot
	for wid in WEAPONS:
		var weapon_data: Dictionary = WEAPONS[wid]
		if weapon_data.get("is_grenade", false):
			var grenade_type: int = weapon_data.get("grenade_type", -1)
			if grenade_type == current_grenade_type and wid in _weapon_slots:
				_apply_selected_style(_weapon_slots[wid])


## Apply the selected (green highlight) style to a slot.
func _apply_selected_style(slot: PanelContainer) -> void:
	var selected_style := StyleBoxFlat.new()
	selected_style.bg_color = Color(0.3, 0.5, 0.3, 0.8)  # Green highlight
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
	_selected_slot = slot


func _on_back_pressed() -> void:
	back_pressed.emit()
